import AppKit
import SwiftUI
import ResetCore


@MainActor final class IslandPresentation: ObservableObject {
    @Published var progress = 0.0
    @Published var contourFill = 1.0
    @Published var closingElapsed = 0.0
}

@MainActor final class UsageStore: ObservableObject {
    @Published var promptingOpen = false
    let prompting = PromptingStore()
    func showPrompting(_ value: Bool) {
        promptingOpen = value
        if value { prompting.refreshIfNeeded() }
        onData?()
    }
    @Published var weeklyHistoryOpen = false
    @Published var pinnedDay: TokenDay?
    @Published var dayDetailsExpanded = false
    private var dayExpandTask: Task<Void, Never>?
    var dayCardHeight: CGFloat { pinnedDay == nil ? 0 : dayDetailsExpanded ? 122 : 86 }
    func pinDay(_ day: TokenDay, revealDetails: Bool = true) {
        dayExpandTask?.cancel()
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.9)) {
            pinnedDay = day
            if revealDetails { dayDetailsExpanded = true }
        }
        onData?()
    }
    func closeDay() {
        dayExpandTask?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { pinnedDay = nil; dayDetailsExpanded = false }
        onData?()
    }
    @Published var tokenDays: [TokenDay] = []
    @Published var historyLoading = false
    private var historyHoverTask: Task<Void, Never>?
    private var historyLoadedAt: Date?
    private var historyLastStartedAt: Date?
    private var historyLoadedProvider: UsageProvider?
    private var historyGeneration = UUID()
    private var historyTask: Task<Void, Never>?
    private var shuttingDown = false
    private var historyRoots: [String] {
        switch provider {
        case .codex: [TokenHistory.defaultRoot().standardizedFileURL.path]
        case .claude: ClaudeTokenHistory.defaultRoots().map { $0.standardizedFileURL.path }
        }
    }
    private func restoreHistoryCache() {
        guard let data = UserDefaults.standard.data(forKey: "tokenHistoryCache.\(provider.rawValue)"),
              let cache = try? JSONDecoder().decode(TokenHistoryCache.self, from: data),
              cache.provider == provider, cache.roots == historyRoots else { return }
        tokenDays = cache.displayDays()
    }
    func hoverWeekly(_ inside: Bool) {
        historyHoverTask?.cancel()
        guard inside, !weeklyHistoryOpen else { return }
        historyHoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            setHistoryOpen(true)
        }
    }
    func setHistoryOpen(_ open: Bool) {
        guard weeklyHistoryOpen != open else { return }
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88)) { weeklyHistoryOpen = open }
        onData?()
    }
    /// Hover only reveals existing data. One background scan serves launch, refresh,
    /// wake and provider changes, while cached rows remain on screen.
    private func refreshHistory(force: Bool = false) {
        guard !shuttingDown, historyTask == nil,
              force ||
              !(historyLoadedProvider == provider && historyLastStartedAt.map({ Date().timeIntervalSince($0) < 55 }) == true)
        else { return }
        historyLoading = true
        historyLastStartedAt = Date()
        let requestedProvider = provider
        let requestedGeneration = historyGeneration
        let roots = historyRoots
        historyTask = Task { @MainActor [weak self] in
            let history = await Task.detached(priority: .background) { () -> (days: [TokenDay], resets: [QuotaResetEvent]) in
                switch requestedProvider {
                case .codex:
                    let root = URL(fileURLWithPath: roots[0])
                    let result = TokenHistory.read(root: root, dayCount: 14)
                    return (result.days, ResetHistory.recovered(from: result.quotaObservations))
                case .claude:
                    return (ClaudeTokenHistory.days(roots: roots.map { URL(fileURLWithPath: $0) }, dayCount: 14), [])
                }
            }.value
            guard let self, !self.shuttingDown, !Task.isCancelled else { return }
            self.historyTask = nil
            guard self.provider == requestedProvider, self.historyGeneration == requestedGeneration else {
                self.historyLoading = false
                self.refreshHistory(force: true)
                return
            }
            resetHistory.merge(history.resets); saveResetHistory()
            tokenDays = history.days; historyLoading = false; historyLoadedAt = Date(); historyLoadedProvider = requestedProvider
            let cache = TokenHistoryCache(provider: requestedProvider, roots: roots, days: history.days)
            if let data = try? JSONEncoder().encode(cache) {
                UserDefaults.standard.set(data, forKey: "tokenHistoryCache.\(requestedProvider.rawValue)")
            }
            onData?()
        }
    }
    @Published var provider = UsageProvider(rawValue: UserDefaults.standard.string(forKey: "usageProvider") ?? "codex") ?? .codex
    @Published var buckets: [LimitBucket] = []
    @Published var selectedID = "codex"
    @Published var credits: ResetCredits?
    var displayedCreditDates: [Date?] {
        let actual = credits?.credits?.filter { $0.status == "available" }.map { $0.expiresAt.map(Date.init(timeIntervalSince1970:)) } ?? []
        let missing = max(0, (credits?.availableCount ?? 0) - actual.count)
        return (actual + Array(repeating: nil, count: missing)).sorted { ($0 ?? .distantFuture) < ($1 ?? .distantFuture) }
    }
    @Published var lastUpdated: Date?
    @Published var now = Date()
    @Published var refreshing = false
    @Published var error: String?
    @Published var expanded = false
    func selectProvider(_ value: UsageProvider) {
        guard provider != value else { return }
        stopRequest()
        usageRevealTask?.cancel(); recentUsageChange = false
        provider = value
        UserDefaults.standard.set(value.rawValue, forKey: "usageProvider")
        buckets = []; credits = nil; selectedID = value.rawValue
        lastUpdated = nil; error = nil
        tokenDays = []; historyLoadedAt = nil; historyLoadedProvider = nil; historyLoading = false
        historyGeneration = UUID()
        restoreHistoryCache()
        onData?()
        refresh()
    }
    func displayWindows(_ bucket: LimitBucket) -> [LimitWindow] { bucket.windows }
    let motion = IslandPresentation()
    var islandProgress: Double {
        get { motion.progress }
        set { motion.progress = newValue }
    }
    @Published var indicatorHidden = false
    let visibilitySettings = VisibilitySettings.shared
    private var recentUsageChange = false
    private var usageRevealTask: Task<Void, Never>?
    var externalHoverOnly = false
    var indicatorRevealed: Bool {
        if externalHoverOnly { return !hoveredRegions.isEmpty || expanded || islandProgress > 0.001 }
        return IndicatorVisibility.shouldShow(alwaysOn: visibilitySettings.alwaysOn,
            hovered: !hoveredRegions.isEmpty, expanded: expanded || islandProgress > 0.001,
            recentChange: visibilitySettings.revealChanges && recentUsageChange,
            activeAppSelected: visibilitySettings.activeAppSelected)
    }
    private func revealUsageChange() {
        recentUsageChange = true
        usageRevealTask?.cancel()
        onVisibility?()
        usageRevealTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.recentUsageChange = false
            self.onVisibility?()
        }
    }
    @Published var samples: [UsageSample] = []
    @Published private(set) var resetHistory = ResetHistory()
    private func saveResetHistory() {
        if let data = try? JSONEncoder().encode(resetHistory) {
            UserDefaults.standard.set(data, forKey: "quotaResetHistoryV1")
        }
    }
    @Published var hasNotch = false
    @Published var notchSize = CGSize(width: 210, height: 40)
    var onExpand: ((Bool) -> Void)?
    var onVisibility: (() -> Void)?
    var onData: (() -> Void)?
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = Data()
    private var timeout: Timer?
    private var tick: Timer?
    private var refreshTimer: Timer?
    private var hoverTask: Task<Void, Never>?
    private var providerTask: Task<Void, Never>?
    private var retryNotBefore: [UsageProvider: Date] = [:]
    private var generation = UUID()
    var menuTracking = false
    private var hoveredRegions = Set<String>()
    private var hoverIntent = false
    var selected: LimitBucket? { buckets.first { $0.id == selectedID } ?? buckets.first }
    var window: LimitWindow? { selected?.constraining }
    var stale: Bool { lastUpdated.map { now.timeIntervalSince($0) > 150 } ?? true }
    var sourceFresh: Bool { !stale && error == nil }
    var usable: Bool { sourceFresh && window != nil }
    var tint: Color { !usable ? Color.secondary : ((window?.remaining ?? 0) <= 10 ? BrandPalette.sand : BrandPalette.cream) }
    var sharedFiveHour: LimitWindow? {
        guard sourceFresh, let main = buckets.first(where: { $0.id == provider.rawValue }) ?? buckets.first else { return nil }
        return main.windows.first(where: { $0.windowDurationMins == 300 }) ?? main.constraining
    }
    var remainingText: String { usable ? "\(Int(window!.remaining.rounded()))%" : "—" }
    var freshness: String {
        guard let lastUpdated else { return refreshing ? "Connecting" : "Unavailable" }
        if error != nil { return "Refresh failed" }
        let seconds = Int(now.timeIntervalSince(lastUpdated))
        return seconds < 60 ? "\(max(0, seconds))s ago" : "\(seconds / 60)m ago"
    }
    var pace: Double? {
        guard usable, let selected, let window else { return nil }
        return UsageMath.pointsPerHour(samples: samples.filter { now.timeIntervalSince($0.timestamp) <= 3600 }, bucketID: selected.id, resetAt: window.resetsAt)
    }
    init() {
        visibilitySettings.onChange = { [weak self] in self?.onVisibility?() }
        if let data = UserDefaults.standard.data(forKey: "usageSamples"), let stored = try? JSONDecoder().decode([UsageSample].self, from: data) {
            samples = stored.filter { Date().timeIntervalSince($0.timestamp) < 86400 }
        }
        if let data = UserDefaults.standard.data(forKey: "quotaResetHistoryV1"),
           let saved = try? JSONDecoder().decode(ResetHistory.self, from: data) {
            resetHistory = saved
        } else {
            // Migrate only windows whose duration is known; the old pace samples
            // could represent either allowance and are unsuitable as reset evidence.
            let weekly = samples.filter { $0.bucketID.hasSuffix(":weekly") }.map { sample in
                let bucket = String(sample.bucketID.dropLast(7))
                let provider: UsageProvider = bucket.hasPrefix("claude") ? .claude : .codex
                return QuotaObservation(provider: provider, bucketID: bucket, bucketName: provider.displayName,
                    durationMinutes: 10_080, used: sample.used, resetsAt: sample.resetAt,
                    timestamp: sample.timestamp, source: .codexHistory)
            }
            resetHistory.observe(weekly); saveResetHistory()
        }
        tick = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in Task { @MainActor in self?.now = Date() } }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        restoreHistoryCache()
        refreshHistory(force: true)
    }
    func hover(_ inside: Bool, region: String = "panel") {
        let wasHovered = !hoveredRegions.isEmpty
        if inside { hoveredRegions.insert(region) } else { hoveredRegions.remove(region) }
        if wasHovered != !hoveredRegions.isEmpty { onVisibility?() }
        guard !menuTracking else { return }
        let shouldOpen = !hoveredRegions.isEmpty
        guard shouldOpen != hoverIntent || (hoverTask == nil && expanded != shouldOpen) else { return }
        hoverIntent = shouldOpen
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: shouldOpen ? 120_000_000 : 140_000_000)
            guard !Task.isCancelled, !self.menuTracking else { return }
            setExpanded(shouldOpen)
            hoverTask = nil
        }
    }
    private var sensorStartTask: Task<Void, Never>?
    func setExpanded(_ value: Bool) {
        guard value != expanded else { return }
        if !value { historyHoverTask?.cancel(); dayExpandTask?.cancel(); pinnedDay = nil; dayDetailsExpanded = false; weeklyHistoryOpen = false }
        sensorStartTask?.cancel(); sensorStartTask = nil
        expanded = value; onExpand?(value)
        if value {
            sensorStartTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled, self?.expanded == true else { return }
                MacTilt.shared.setSceneActive(true)
            }
        } else { MacTilt.shared.setSceneActive(false) }
    }
    func dismiss() { hoverTask?.cancel(); hoverTask = nil; hoveredRegions.removeAll(); hoverIntent = false; setExpanded(false) }
    var detailHeight: CGFloat {
        if promptingOpen { return 78 + 32 + 300 }
        let groups = buckets.reduce(CGFloat(0)) { $0 + 33 + CGFloat(max(1, displayWindows($1).count)) * 52 }
        return 32 + min(600, dayCardHeight + (weeklyHistoryOpen ? 120 : 0) + 58 + max(62, groups) + (!weeklyHistoryOpen || displayedCreditDates.isEmpty ? 0 : 32) + (error != nil ? 68 : 0))
    }
    var islandHeight: CGFloat { detailHeight - 78 + notchSize.height - 7 }
    func toggleIndicator() {
        indicatorHidden.toggle()
        dismiss()
        onVisibility?()
    }
    func countdown(_ date: Date?) -> String {
        guard let date else { return "Time unavailable" }
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "Awaiting refresh" }
        if seconds >= 172800 { return "\(seconds / 86400)d" }
        if seconds >= 86400 { return "\(seconds / 86400)d \((seconds % 86400) / 3600)h" }
        if seconds >= 3600 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
        return "\(max(1, seconds / 60))m"
    }
    func refresh() {
        refreshHistory()
        guard !refreshing else { return }
        if let retryAt = retryNotBefore[provider], retryAt > Date() {
            if provider == .claude {
                error = "Claude is rate limiting usage checks until \(retryAt.formatted(date: .omitted, time: .shortened))."
            }
            onData?()
            return
        }
        refreshing = true; now = Date()
        let token = UUID(); generation = token
        if provider == .claude {
            providerTask = Task { @MainActor [weak self] in
                do {
                    let snapshot = try await ClaudeUsageReader().fetch()
                    guard let self, self.generation == token, self.provider == .claude else { return }
                    self.accept(snapshot)
                } catch is CancellationError {
                    return
                } catch let readError as ClaudeUsageReadError {
                    guard let self, self.generation == token, self.provider == .claude else { return }
                    if case let .rateLimited(retryAt) = readError {
                        self.retryNotBefore[.claude] = retryAt.map { max($0, Date().addingTimeInterval(1)) }
                            ?? Date().addingTimeInterval(300)
                    }
                    self.fail(readError.errorDescription ?? "Claude usage is unavailable.")
                } catch {
                    guard let self, self.generation == token, self.provider == .claude else { return }
                    self.fail("Claude usage is unavailable.")
                }
            }
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            home + "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            home + "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
        ]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            fail("Install the Codex CLI and sign in, then try again."); return
        }
        let task = Process(), stdinPipe = Pipe(), stdoutPipe = Pipe()
        process = task; input = stdinPipe; output = stdoutPipe; buffer = Data()
        task.executableURL = URL(fileURLWithPath: path); task.arguments = ["app-server"]
        task.standardInput = stdinPipe; task.standardOutput = stdoutPipe; task.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin"
        task.environment = environment
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if data.isEmpty { if self.refreshing { self.fail("Codex ended the connection. Check your CLI sign-in and try again.") }; return }
                self.receive(data)
            }
        }
        do {
            try task.run()
            send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "reset", "version": "0.1.0"], "capabilities": ["experimentalApi": true]]])
            timeout = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in Task { @MainActor in self?.fail("Codex usage request timed out.") } }
        } catch { fail("Couldn’t start the Codex CLI. Check your installation and try again.") }
    }
    private func send(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(10)
        do { try input?.fileHandleForWriting.write(contentsOf: data) }
        catch { fail("The Codex connection closed. Try refreshing.") }
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = object["id"] as? Int else { continue }
            if object["error"] != nil { fail("Codex couldn’t provide usage. Check that the CLI is signed in to a supported account."); return }
            if id == 1 { send(["method": "initialized"]); send(["id": 2, "method": "account/rateLimits/read"]) }
            if id == 2, let result = object["result"], let json = try? JSONSerialization.data(withJSONObject: result), let response = try? JSONDecoder().decode(UsageResponse.self, from: json) {
                guard !response.buckets.isEmpty else {
                    fail("Codex returned no usable allowance data for this account."); return
                }
                accept(ProviderUsageSnapshot(provider: .codex, buckets: response.buckets, credits: response.rateLimitResetCredits))
                return
            } else if id == 2 {
                fail("Codex returned usage in an unsupported format."); return
            }
        }
    }
    private func accept(_ snapshot: ProviderUsageSnapshot) {
        guard snapshot.provider == provider else { return }
        retryNotBefore[provider] = nil
        resetHistory.observe(QuotaObservation.snapshot(snapshot, at: Date())); saveResetHistory()
        let changed = IndicatorVisibility.usageChanged(from: buckets, to: snapshot.buckets)
        buckets = snapshot.buckets; credits = snapshot.credits
        if changed { revealUsageChange() }
        lastUpdated = Date(); now = Date(); error = nil
        if !buckets.contains(where: { $0.id == selectedID }) { selectedID = buckets.first?.id ?? provider.rawValue }
        samples = samples.filter { now.timeIntervalSince($0.timestamp) < 86400 }
        samples.append(contentsOf: UsageSampling.samples(from: buckets, timestamp: now))
        if let encoded = try? JSONEncoder().encode(samples) { UserDefaults.standard.set(encoded, forKey: "usageSamples") }
        stopRequest(); onData?()
    }
    private func fail(_ message: String) { error = message; stopRequest(); onData?() }
    private func stopRequest() {
        generation = UUID(); timeout?.invalidate(); timeout = nil
        providerTask?.cancel(); providerTask = nil
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        if let process, process.isRunning { process.terminate() }
        process = nil; input = nil; output = nil; refreshing = false
    }
    func shutdown() { shuttingDown = true; historyTask?.cancel(); usageRevealTask?.cancel(); hoverTask?.cancel(); sensorStartTask?.cancel(); tick?.invalidate(); refreshTimer?.invalidate(); stopRequest() }
}
