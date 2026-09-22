import Foundation

public struct ContextTask: Identifiable, Sendable {
    public var id: String
    public var title: String
    public var context: String?
    public init(id: String, title: String, context: String?) { self.id = id; self.title = title; self.context = context }
}
public struct ContextHour: Identifiable, Sendable {
    public var date: Date
    public var tasks: [ContextTask]
    public var id: Date { date }
    public var contexts: [String] { Array(Set(tasks.compactMap(\.context))).sorted() }
    public var unclassified: Int { tasks.filter { $0.context == nil }.count }
}
public enum ContextMetrics {
    /// Only hours with recorded eligible prompts participate; unknown groupings are not zero.
    public static func hours(messages: [PromptingMessage], tasks: [ContextTask], day: Date, overrides: [String: String] = [:], calendar: Calendar = .current) -> [ContextHour] {
        let lookup = Dictionary(tasks.map { task -> (String, ContextTask) in
            var task = task
            if let label = overrides[task.id] { task.context = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : label.trimmingCharacters(in: .whitespacesAndNewlines) }
            return (task.id, task)
        }, uniquingKeysWith: { first, _ in first })
        var hours: [Date: Set<String>] = [:]
        for message in messages where calendar.isDate(message.at, inSameDayAs: day) && lookup[message.task] != nil {
            if let hour = calendar.dateInterval(of: .hour, for: message.at)?.start { hours[hour, default: []].insert(message.task) }
        }
        return hours.map { ContextHour(date: $0.key, tasks: $0.value.compactMap { lookup[$0] }.sorted { $0.title < $1.title }) }.sorted { $0.date < $1.date }
    }
    public static func average(_ hours: [ContextHour]) -> Double? {
        let known = hours.filter { $0.unclassified == 0 && !$0.tasks.isEmpty }
        return known.isEmpty ? nil : Double(known.reduce(0) { $0 + $1.contexts.count }) / Double(known.count)
    }
    /// Project folders establish project identity; projectless interests use conservative title rules.
    /// Unrecognized projectless tasks remain unclassified.
    public static func suggestedContext(cwd: String, title: String) -> String? {
        let title = title.lowercased()
        if title.contains("psychosis") { return "Focus & AI habits" }
        if ["gpt-6", "sol model", "sol usage", "sol threads", "session history", "project skills"].contains(where: title.contains) { return "AI tools & workflow" }
        if title.contains("reset app") || title.contains("resetme") { return "ResetMe" }
        if title.contains("reswitch") { return "RESWITCH" }
        if title.contains("speakmac") { return "Speakmac" }
        let folder = URL(fileURLWithPath: cwd).lastPathComponent
        if folder == "vibe-code" { return "Speakmac" }
        if folder == "kiosk-wear-on" { return "Kiosk Wear-On" }
        if folder == "sk-spaces" { return "SK Spaces" }
        if folder == "reset" { return "ResetMe" }
        if folder == "reinventra" { return "Reinventra" }
        // Generic projectless folders and personal catch-alls do not establish a shared context.
        let path = URL(fileURLWithPath: cwd).standardizedFileURL.path
        let generic = ["self", "Desktop", "Documents", "Downloads", "Users", "home", "tmp", "private", "Codex", "codex-workspace", "things", "projects", "workspace", "workspaces"]
        guard path.hasPrefix("/"), !folder.isEmpty, !generic.contains(folder),
              !folder.hasPrefix("."), path != NSHomeDirectory(),
              !path.hasPrefix("/tmp/"), !path.hasPrefix("/private/tmp/"), !path.hasPrefix("/var/folders/"),
              path.range(of: "^/(?:Users|home)/[^/]+$", options: .regularExpression) == nil,
              path.range(of: "/Codex/\\d{4}-\\d{2}-\\d{2}/", options: .regularExpression) == nil,
              path.range(of: "/\\.codex/worktrees/[^/]+$", options: .regularExpression) == nil else { return nil }
        return folder
    }
}
