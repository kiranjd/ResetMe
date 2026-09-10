import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VisibilityApp: Codable, Identifiable {
    let id: String
    let name: String
    let path: String
    init?(url: URL) {
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return nil }
        id = identifier
        name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        path = url.path
    }
}

@MainActor final class VisibilitySettings: ObservableObject {
    static let shared = VisibilitySettings()
    @Published var showInMenuBar: Bool { didSet { defaults.set(showInMenuBar, forKey: "showInMenuBar"); onMenuBarChange?() } }
    var onMenuBarChange: (() -> Void)?
    @Published var alwaysOn: Bool { didSet { defaults.set(alwaysOn, forKey: "visibilityAlwaysOn"); onChange?() } }
    @Published var revealChanges: Bool { didSet { defaults.set(revealChanges, forKey: "visibilityRevealChanges"); onChange?() } }
    @Published var useActiveApps: Bool { didSet { defaults.set(useActiveApps, forKey: "visibilityUseActiveApps"); onChange?() } }
    @Published var selected: Set<String> { didSet { defaults.set(Array(selected), forKey: "visibilitySelectedApps"); onChange?() } }
    @Published var apps: [VisibilityApp] = []
    @Published var activeID: String?
    var onChange: (() -> Void)?
    private let defaults = UserDefaults.standard
    private var observer: NSObjectProtocol?
    private var window: NSWindow?
    private var savedApps: [VisibilityApp] = []
    init() {
        showInMenuBar = UserDefaults.standard.object(forKey: "showInMenuBar") as? Bool ?? true
        alwaysOn = UserDefaults.standard.bool(forKey: "visibilityAlwaysOn")
        revealChanges = UserDefaults.standard.object(forKey: "visibilityRevealChanges") as? Bool ?? true
        useActiveApps = UserDefaults.standard.object(forKey: "visibilityUseActiveApps") as? Bool ?? true
        selected = Set(UserDefaults.standard.stringArray(forKey: "visibilitySelectedApps") ?? [])
        if let data = defaults.data(forKey: "visibilityAddedApps") { savedApps = (try? JSONDecoder().decode([VisibilityApp].self, from: data)) ?? [] }
        activeID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let identifier = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor in self?.activeID = identifier; self?.onChange?() }
        }
        discover()
        if defaults.object(forKey: "visibilitySelectedApps") == nil {
            selected = Set(apps.filter { Self.suggested($0.name) }.map(\.id))
            defaults.set(Array(selected), forKey: "visibilitySelectedApps")
        }
    }
    var activeAppSelected: Bool { useActiveApps && activeID.map { selected.contains($0) } == true }
    static func suggested(_ name: String) -> Bool {
        let normalized = name.components(separatedBy: "(")[0].lowercased().filter { $0.isLetter || $0.isNumber }
        return ["chatgpt", "chatgptclassic", "chatgptatlas", "codex", "opencode", "t3code", "synara", "claude", "cursor", "windsurf", "zed", "visualstudiocode", "vscodium", "antigravity", "warp", "gemini", "xcode"].contains(normalized)
    }
    func discover() {
        var found = savedApps
        let roots = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"), URL(fileURLWithPath: "/System/Applications")]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "app" {
                if let app = VisibilityApp(url: url) { found.append(app) }
            }
        }
        found += NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap { $0.bundleURL.flatMap(VisibilityApp.init) }
        var unique: [String: VisibilityApp] = [:]
        for app in found where app.id != Bundle.main.bundleIdentifier { unique[app.id] = app }
        apps = unique.values.sorted {
            if Self.suggested($0.name) != Self.suggested($1.name) { return Self.suggested($0.name) }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    func setSelected(_ app: VisibilityApp, enabled: Bool) {
        if enabled { selected.insert(app.id) } else { selected.remove(app.id) }
        if !savedApps.contains(where: { $0.id == app.id }) { savedApps.append(app) }
        if let data = try? JSONEncoder().encode(savedApps) { defaults.set(data, forKey: "visibilityAddedApps") }
    }
    func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.prompt = "Add Apps"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { if let app = VisibilityApp(url: url) { setSelected(app, enabled: true) } }
        discover()
    }
    func show() {
        discover()
        if window == nil {
            let created = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            created.title = "ResetMe Settings"; created.isReleasedWhenClosed = false
            created.contentView = NSHostingView(rootView: VisibilitySettingsView(settings: self))
            created.center(); window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct VisibilitySettingsView: View {
    @ObservedObject var settings: VisibilitySettings
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Show in menu bar", isOn: $settings.showInMenuBar)
            Divider()
            Text("Notch visibility").font(.title2.weight(.semibold))
            Toggle("Always on", isOn: $settings.alwaysOn)
            Text("Hover over the notch to open ResetMe anytime.").font(.callout).foregroundStyle(.secondary)
            Divider()
            Toggle("Show briefly when usage changes", isOn: $settings.revealChanges)
            Text("Reveal for 5 seconds after a refresh detects a change. Usage checks run every minute.").font(.caption).foregroundStyle(.secondary)
            Toggle("Show while selected apps are active", isOn: $settings.useActiveApps)
            Text("Visible while a selected app is in the foreground. Choose a terminal to cover any CLI inside it.").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Search apps", text: $search)
                Button("Add App…") { settings.addApp() }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(settings.apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { app in
                        Toggle(isOn: Binding(get: { settings.selected.contains(app.id) }, set: { settings.setSelected(app, enabled: $0) })) {
                            HStack {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 22, height: 22)
                                Text(app.name)
                            }
                        }
                    }
                }.padding(8)
            }.background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }.padding(24).frame(width: 440, height: 560).tint(BrandPalette.olive)
    }
}
