import AppKit
import Foundation
import SQLite3
import SwiftUI

private enum ProviderChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case auto
    case codex
    case claude

    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .codex: return "Codex"
        case .claude: return "Claude"
        }
    }
    var subtitle: String {
        switch self {
        case .auto: return "RCC chooses"
        case .codex: return "Build & edit"
        case .claude: return "Analyze & review"
        }
    }
    var symbol: String {
        switch self {
        case .auto: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .claude: return "sun.max.fill"
        }
    }
    var tint: Color {
        switch self {
        case .auto: return Color(red: 0.38, green: 0.86, blue: 0.58)
        case .codex: return Color(red: 0.82, green: 0.51, blue: 0.94)
        case .claude: return Color(red: 0.93, green: 0.49, blue: 0.34)
        }
    }
}

private struct NativeSessionSummary: Identifiable, Sendable {
    let id: String
    let provider: ProviderChoice
    let title: String
    let workspace: String
    let updatedAt: Date
    let sourcePath: String?
    var linkedTitle: String?

    var displayTitle: String {
        let value = (linkedTitle ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Untitled session" : value
    }
}

private struct NativeSessionMessage: Identifiable, Sendable {
    let id: String
    let role: MessageRole
    let text: String
    let timestamp: Date?
}

private enum NativeSessionReader {
    nonisolated(unsafe) private static let iso8601 = ISO8601DateFormatter()

    static func sessions(for provider: ProviderChoice) throws -> [NativeSessionSummary] {
        switch provider {
        case .codex: return try codexSessions()
        case .claude: return try claudeSessions()
        case .auto: return []
        }
    }

    static func transcript(for session: NativeSessionSummary) throws -> [NativeSessionMessage] {
        switch session.provider {
        case .codex: return try codexTranscript(sessionID: session.id)
        case .claude: return try claudeTranscript(session: session)
        case .auto: return []
        }
    }

    private static func codexSessions() throws -> [NativeSessionSummary] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.codex/state_5.sqlite"
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            throw RunnerError.message("Codex session index could not be opened.")
        }
        defer { sqlite3_close(database) }
        let query = """
        SELECT id,
               COALESCE(NULLIF(name, ''), NULLIF(title, ''), NULLIF(first_user_message, ''), 'Untitled session'),
               cwd,
               COALESCE(NULLIF(recency_at_ms, 0), NULLIF(updated_at_ms, 0), updated_at * 1000)
        FROM threads
        WHERE archived = 0 AND preview <> ''
        ORDER BY recency_at_ms DESC, updated_at_ms DESC
        LIMIT 500
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw RunnerError.message("Codex session index could not be read.")
        }
        defer { sqlite3_finalize(statement) }
        var result: [NativeSessionSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = columnText(statement, 0)
            guard !id.isEmpty else { continue }
            result.append(NativeSessionSummary(
                id: id,
                provider: .codex,
                title: columnText(statement, 1),
                workspace: columnText(statement, 2),
                updatedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 3)) / 1_000),
                sourcePath: nil,
                linkedTitle: nil
            ))
        }
        return result
    }

    private static func codexTranscript(sessionID: String) throws -> [NativeSessionMessage] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.codex/thread_history_1.sqlite"
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            throw RunnerError.message("Codex transcript database could not be opened.")
        }
        defer { sqlite3_close(database) }
        let query = """
        SELECT item_type, item_json, created_at_ms
        FROM (
          SELECT rollout_ordinal, item_type, item_json, created_at_ms
          FROM thread_items
          WHERE thread_id = ? AND item_type IN ('userMessage', 'agentMessage')
          ORDER BY rollout_ordinal DESC
          LIMIT 400
        )
        ORDER BY rollout_ordinal ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw RunnerError.message("Codex transcript could not be read.")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sessionID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        var result: [NativeSessionMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let type = columnText(statement, 0)
            let json = columnText(statement, 1)
            guard let data = json.data(using: .utf8),
                  let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let text: String
            let role: MessageRole
            if type == "userMessage" {
                role = .user
                text = textContent(item["content"])
            } else {
                role = .assistant
                text = item["text"] as? String ?? ""
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            result.append(NativeSessionMessage(
                id: (item["id"] as? String) ?? "codex-\(result.count)",
                role: role,
                text: trimmed,
                timestamp: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 2)) / 1_000)
            ))
        }
        return result
    }

    private static func claudeSessions() throws -> [NativeSessionSummary] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            files.append((url, values?.contentModificationDate ?? .distantPast))
        }
        files.sort { $0.1 > $1.1 }
        return files.prefix(300).compactMap { url, modifiedAt in
            guard let records = try? readJSONLines(url, maximumBytes: 768 * 1_024), !records.isEmpty else { return nil }
            var id = url.deletingPathExtension().lastPathComponent
            var workspace = ""
            var timestamp = modifiedAt
            var title = ""
            for record in records {
                if let value = record["sessionId"] as? String, !value.isEmpty { id = value }
                if let value = record["cwd"] as? String, !value.isEmpty { workspace = value }
                if let value = record["timestamp"] as? String, let date = iso8601.date(from: value) { timestamp = max(timestamp, date) }
                if title.isEmpty, record["type"] as? String == "user",
                   let message = record["message"] as? [String: Any] {
                    title = firstLine(textContent(message["content"]))
                }
            }
            return NativeSessionSummary(
                id: id,
                provider: .claude,
                title: title,
                workspace: workspace,
                updatedAt: timestamp,
                sourcePath: url.path,
                linkedTitle: nil
            )
        }
    }

    private static func claudeTranscript(session: NativeSessionSummary) throws -> [NativeSessionMessage] {
        guard let sourcePath = session.sourcePath else { return [] }
        let records = try readJSONLines(URL(fileURLWithPath: sourcePath), maximumBytes: nil)
        var result: [NativeSessionMessage] = []
        for record in records {
            guard let type = record["type"] as? String, type == "user" || type == "assistant",
                  let message = record["message"] as? [String: Any] else { continue }
            let text = textContent(message["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let timestamp = (record["timestamp"] as? String).flatMap(iso8601.date(from:))
            result.append(NativeSessionMessage(
                id: (record["uuid"] as? String) ?? "claude-\(result.count)",
                role: type == "user" ? .user : .assistant,
                text: text,
                timestamp: timestamp
            ))
        }
        return Array(result.suffix(400))
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private static func readJSONLines(_ url: URL, maximumBytes: Int?) throws -> [[String: Any]] {
        let data: Data
        if let maximumBytes {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: maximumBytes) ?? Data()
        } else {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            guard let lineData = String(line).data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
        }
    }

    private static func textContent(_ value: Any?) -> String {
        if let value = value as? String { return value }
        guard let values = value as? [[String: Any]] else { return "" }
        return values.compactMap { item -> String? in
            guard item["type"] as? String == "text" || item["type"] as? String == "input_text" || item["type"] as? String == "output_text" else { return nil }
            return item["text"] as? String
        }.joined(separator: "\n\n")
    }

    private static func firstLine(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed).prefix(90))
    }
}

private enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case receipt
    case system
}

private struct ChatMessage: Codable, Identifiable, Sendable {
    let id: UUID
    let role: MessageRole
    let text: String
    let provider: String?
    let permissionProfile: String?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String,
        provider: String? = nil,
        permissionProfile: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.provider = provider
        self.permissionProfile = permissionProfile
        self.timestamp = timestamp
    }
}

private struct ConversationSession: Codable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var workspace: String
    var provider: ProviderChoice
    var messages: [ChatMessage]
    var codexSessionID: String?
    var claudeSessionID: String?
    var lastProvider: String?
    var codexCapacity: Int?
    var claudeCapacity: Int?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "New session pair",
        workspace: String,
        provider: ProviderChoice = .auto,
        messages: [ChatMessage] = [],
        codexSessionID: String? = nil,
        claudeSessionID: String? = nil,
        lastProvider: String? = nil,
        codexCapacity: Int = 30,
        claudeCapacity: Int = 100,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.workspace = workspace
        self.provider = provider
        self.messages = messages
        self.codexSessionID = codexSessionID
        self.claudeSessionID = claudeSessionID
        self.lastProvider = lastProvider
        self.codexCapacity = codexCapacity
        self.claudeCapacity = claudeCapacity
        self.updatedAt = updatedAt
    }

    var effectiveCodexCapacity: Int { codexCapacity ?? 30 }
    var effectiveClaudeCapacity: Int { claudeCapacity ?? 100 }
}

private struct SessionEnvelope: Codable {
    let schema: Int
    let sessions: [ConversationSession]
}

private struct AppRunStep: Decodable, Sendable {
    let sequence: Int
    let provider: String
    let action: String
    let effort: String
    let sessionID: String
    let permissionProfile: String
    let exitCode: Int32
    let output: String
    let stderr: String
    let durationMS: Int64

    enum CodingKeys: String, CodingKey {
        case sequence, provider, action, effort, output, stderr
        case sessionID = "session_id"
        case permissionProfile = "permission_profile"
        case exitCode = "exit_code"
        case durationMS = "duration_ms"
    }
}

private struct AppRunSummary: Decodable, Sendable {
    let status: String
    let steps: [AppRunStep]
}

private enum RunnerError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}

private func backendTierLabel(action: String, provider: String) -> String {
    let engine = provider == "codex" ? "Codex" : "Claude"
    switch action {
    case "agent_run_efficient": return "Efficient \(engine) backend"
    case "agent_run_deep": return "Deep \(engine) backend"
    default: return "Standard \(engine) backend"
    }
}

private func compactSessionAge(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "now" }
    if seconds < 3_600 { return "\(seconds / 60)m" }
    if seconds < 86_400 { return "\(seconds / 3_600)h" }
    if seconds < 2_592_000 { return "\(seconds / 86_400)d" }
    return date.formatted(date: .abbreviated, time: .omitted)
}

private enum OS1Runner {
    static func run(
        workspace: String,
        prompt: String,
        provider: ProviderChoice,
        context: String,
        codexSessionID: String?,
        claudeSessionID: String?,
        codexCapacity: Int,
        claudeCapacity: Int
    ) async throws -> AppRunSummary {
        try await Task.detached(priority: .userInitiated) {
            try runBlocking(
                workspace: workspace,
                prompt: prompt,
                provider: provider,
                context: context,
                codexSessionID: codexSessionID,
                claudeSessionID: claudeSessionID,
                codexCapacity: codexCapacity,
                claudeCapacity: claudeCapacity
            )
        }.value
    }

    private static func executable() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("os1").path
        let candidates = [bundled].compactMap { $0 } + [
            "/usr/local/bin/os1",
            "/opt/homebrew/bin/os1",
            "\(home)/.local/bin/os1",
        ]
        guard let path = candidates.first(where: FileManager.default.isExecutableFile) else {
            throw RunnerError.message("OS-1 runtime is missing. Reinstall OS-1, then try again.")
        }
        return path
    }

    private static func runBlocking(
        workspace: String,
        prompt: String,
        provider: ProviderChoice,
        context: String,
        codexSessionID: String?,
        claudeSessionID: String?,
        codexCapacity: Int,
        claudeCapacity: Int
    ) throws -> AppRunSummary {
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory
            .appendingPathComponent("os1-app-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: temporary,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: temporary) }

        let stdoutURL = temporary.appendingPathComponent("stdout.json")
        let stderrURL = temporary.appendingPathComponent("stderr.txt")
        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)

        var arguments = [
            "run",
            "--workspace", workspace,
            "--prompt", prompt,
            "--provider", provider.rawValue,
            "--output-format", "json",
        ]
        if !context.isEmpty {
            let contextURL = temporary.appendingPathComponent("session-context.txt")
            try Data(context.utf8).write(
                to: contextURL,
                options: [.atomic, .completeFileProtectionUnlessOpen]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: contextURL.path
            )
            arguments += ["--context-file", contextURL.path]
        }
        if let codexSessionID { arguments += ["--codex-session-id", codexSessionID] }
        if let claudeSessionID { arguments += ["--claude-session-id", claudeSessionID] }
        arguments += [
            "--codex-capacity", String(codexCapacity),
            "--claude-capacity", String(claudeCapacity),
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: try executable())
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        var environment = ProcessInfo.processInfo.environment
        let home = fileManager.homeDirectoryForCurrentUser.path
        let preferredPath = [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            environment["PATH"] ?? "",
        ].joined(separator: ":")
        environment["PATH"] = preferredPath
        process.environment = environment

        do {
            try process.run()
            process.waitUntilExit()
            try stdout.close()
            try stderr.close()
        } catch {
            try? stdout.close()
            try? stderr.close()
            throw RunnerError.message("OS-1 could not start: \(error.localizedDescription)")
        }

        let outputData = try Data(contentsOf: stdoutURL)
        let errorText = String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            let fallback = String(decoding: outputData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RunnerError.message(errorText.isEmpty ? fallback : errorText)
        }
        do {
            return try JSONDecoder().decode(AppRunSummary.self, from: outputData)
        } catch {
            throw RunnerError.message("OS-1 returned an unreadable result.")
        }
    }
}

@MainActor
private final class SessionStore: ObservableObject {
    @Published var sessions: [ConversationSession] = []
    @Published var selectedSessionID: UUID?
    @Published var surface: ProviderChoice = .auto
    @Published var composer = ""
    @Published var search = ""
    @Published var nativeSearch = ""
    @Published var nativeSessions: [NativeSessionSummary] = []
    @Published var selectedNativeSessionID: String?
    @Published var nativeMessages: [NativeSessionMessage] = []
    @Published var isLoadingNativeSessions = false
    @Published var isRunning = false
    @Published var statusText = "Ready"
    @Published var alertMessage: String?

    private let fileManager = FileManager.default

    init() {
        load()
        if sessions.isEmpty {
            createSession(provider: .auto)
        } else {
            selectedSessionID = sessions.first?.id
        }
    }

    var selectedIndex: Int? {
        sessions.firstIndex(where: { $0.id == selectedSessionID })
    }

    var selectedSession: ConversationSession? {
        guard let index = selectedIndex else { return nil }
        return sessions[index]
    }

    var filteredSessions: [ConversationSession] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }
        return sessions.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.workspace.localizedCaseInsensitiveContains(query)
        }
    }

    var filteredNativeSessions: [NativeSessionSummary] {
        let query = nativeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nativeSessions }
        return nativeSessions.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query) ||
            $0.workspace.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedNativeSession: NativeSessionSummary? {
        nativeSessions.first(where: { $0.id == selectedNativeSessionID })
    }

    func createSession(provider: ProviderChoice? = nil) {
        let inherited = provider ?? selectedSession?.provider ?? .auto
        let session = ConversationSession(
            workspace: fileManager.homeDirectoryForCurrentUser.path,
            provider: inherited
        )
        sessions.insert(session, at: 0)
        selectedSessionID = session.id
        composer = ""
        statusText = "Choose a workspace, then describe the task"
        save()
    }

    func select(_ id: UUID) {
        selectedSessionID = id
        composer = ""
        statusText = "Ready"
    }

    func chooseProvider(_ provider: ProviderChoice) {
        guard let index = selectedIndex else { return }
        let previous = sessions[index].provider
        guard previous != provider else { return }
        sessions[index].provider = provider
        sessions[index].updatedAt = Date()
        if !sessions[index].messages.isEmpty {
            sessions[index].messages.append(ChatMessage(
                role: .system,
                text: provider == .auto
                    ? "RCC will choose and continue the matching native Codex or Claude session."
                    : "Next turn will create or resume the linked native \(provider.title) session.",
                provider: provider.rawValue
            ))
        }
        statusText = provider == .auto
            ? "RCC will choose the next engine"
            : "Next turn: \(provider.title)"
        save()
    }

    func showClaudexHome() {
        guard !isRunning else { return }
        surface = .auto
        chooseProvider(.auto)
        statusText = "Claudex home · RCC auto routing"
        NSApp.activate(ignoringOtherApps: true)
    }

    func inspectBackend(_ provider: ProviderChoice) {
        guard !isRunning, provider != .auto else { return }
        surface = provider
        nativeSearch = ""
        let preferredID = provider == .codex
            ? selectedSession?.codexSessionID
            : selectedSession?.claudeSessionID
        statusText = "Syncing local \(provider.title) sessions…"
        isLoadingNativeSessions = true
        nativeMessages = []
        Task {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try NativeSessionReader.sessions(for: provider)
                }.value
                guard surface == provider else { return }
                var linkedTitles: [String: String] = [:]
                for session in sessions {
                    let id = provider == .codex ? session.codexSessionID : session.claudeSessionID
                    if let id { linkedTitles[id] = session.title }
                }
                nativeSessions = loaded.map { value in
                    var copy = value
                    copy.linkedTitle = linkedTitles[value.id]
                    return copy
                }
                selectedNativeSessionID = preferredID.flatMap { id in
                    nativeSessions.contains(where: { $0.id == id }) ? id : nil
                } ?? nativeSessions.first?.id
                isLoadingNativeSessions = false
                statusText = "\(provider.title) backend · \(nativeSessions.count) local sessions synced"
                loadSelectedNativeTranscript()
            } catch {
                guard surface == provider else { return }
                isLoadingNativeSessions = false
                nativeSessions = []
                selectedNativeSessionID = nil
                nativeMessages = []
                alertMessage = error.localizedDescription
                statusText = "Native session sync needs attention"
            }
        }
    }

    func refreshNativeSessions() {
        guard surface != .auto else { return }
        inspectBackend(surface)
    }

    func selectNativeSession(_ id: String) {
        selectedNativeSessionID = id
        loadSelectedNativeTranscript()
    }

    private func loadSelectedNativeTranscript() {
        guard let session = selectedNativeSession else {
            nativeMessages = []
            return
        }
        let expectedID = session.id
        isLoadingNativeSessions = true
        Task {
            do {
                let messages = try await Task.detached(priority: .userInitiated) {
                    try NativeSessionReader.transcript(for: session)
                }.value
                guard selectedNativeSessionID == expectedID else { return }
                nativeMessages = messages
                isLoadingNativeSessions = false
            } catch {
                guard selectedNativeSessionID == expectedID else { return }
                nativeMessages = []
                isLoadingNativeSessions = false
                alertMessage = error.localizedDescription
            }
        }
    }

    func setCapacity(_ provider: ProviderChoice, value: Int) {
        guard let index = selectedIndex, [0, 10, 25, 50, 75, 100].contains(value) else { return }
        if provider == .codex { sessions[index].codexCapacity = value }
        if provider == .claude { sessions[index].claudeCapacity = value }
        if sessions[index].effectiveCodexCapacity + sessions[index].effectiveClaudeCapacity == 0 {
            if provider == .codex { sessions[index].claudeCapacity = 10 }
            if provider == .claude { sessions[index].codexCapacity = 10 }
        }
        sessions[index].provider = .auto
        sessions[index].updatedAt = Date()
        statusText = "RCC capacity mix updated"
        save()
    }

    func chooseWorkspace() {
        guard !isRunning, let index = selectedIndex else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose the project folder OS-1 may work in"
        panel.prompt = "Use this folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: sessions[index].workspace, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let nextWorkspace = url.standardizedFileURL.path
        if sessions[index].workspace != nextWorkspace,
           sessions[index].codexSessionID != nil || sessions[index].claudeSessionID != nil {
            sessions[index].codexSessionID = nil
            sessions[index].claudeSessionID = nil
            sessions[index].lastProvider = nil
            sessions[index].messages.append(ChatMessage(
                role: .system,
                text: "Workspace changed. Native Codex and Claude links were reset so sessions cannot resume in the wrong project."
            ))
        }
        sessions[index].workspace = nextWorkspace
        sessions[index].updatedAt = Date()
        statusText = "Workspace connected"
        save()
    }

    func useSuggestion(_ value: String) {
        composer = value
    }

    func send() {
        let request = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isRunning, let index = selectedIndex else { return }
        var isDirectory: ObjCBool = false
        let workspace = sessions[index].workspace
        guard fileManager.fileExists(atPath: workspace, isDirectory: &isDirectory), isDirectory.boolValue else {
            alertMessage = "Choose an existing project folder before sending the task."
            return
        }

        let sessionID = sessions[index].id
        let provider = sessions[index].provider
        let codexSessionID = sessions[index].codexSessionID
        let claudeSessionID = sessions[index].claudeSessionID
        let context = handoffContext(for: sessions[index], nextProvider: provider)
        if sessions[index].messages.isEmpty {
            sessions[index].title = title(for: request)
        }
        sessions[index].messages.append(ChatMessage(role: .user, text: request))
        sessions[index].updatedAt = Date()
        composer = ""
        isRunning = true
        statusText = provider == .auto
            ? "RCC is choosing the best engine…"
            : "\(provider.title) is working…"
        save()

        Task {
            do {
                let summary = try await OS1Runner.run(
                    workspace: workspace,
                    prompt: request,
                    provider: provider,
                    context: context,
                    codexSessionID: codexSessionID,
                    claudeSessionID: claudeSessionID,
                    codexCapacity: sessions[index].effectiveCodexCapacity,
                    claudeCapacity: sessions[index].effectiveClaudeCapacity
                )
                guard let target = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
                if summary.steps.isEmpty {
                    sessions[target].messages.append(ChatMessage(
                        role: .assistant,
                        text: "The governed route completed without an additional model step.",
                        provider: provider.rawValue
                    ))
                }
                for step in summary.steps {
                    if step.provider == "codex" {
                        sessions[target].codexSessionID = step.sessionID
                    } else if step.provider == "claude" {
                        sessions[target].claudeSessionID = step.sessionID
                    }
                    sessions[target].lastProvider = step.provider
                    let visibleOutput = step.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    let visibleError = step.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    sessions[target].messages.append(ChatMessage(
                        role: .assistant,
                        text: visibleOutput.isEmpty
                            ? (visibleError.isEmpty ? "The engine finished without text output." : visibleError)
                            : visibleOutput,
                        provider: step.provider,
                        permissionProfile: step.permissionProfile
                    ))
                    sessions[target].messages.append(ChatMessage(
                        role: .receipt,
                        text: "\(backendTierLabel(action: step.action, provider: step.provider)) · \(step.effort) reasoning · native session linked · step \(step.sequence) · \(step.durationMS / 1_000)s · exit \(step.exitCode)",
                        provider: step.provider,
                        permissionProfile: step.permissionProfile
                    ))
                }
                sessions[target].updatedAt = Date()
                statusText = "Native session linked · evidence recorded"
            } catch {
                guard let target = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
                sessions[target].messages.append(ChatMessage(
                    role: .system,
                    text: error.localizedDescription
                ))
                sessions[target].updatedAt = Date()
                statusText = "Needs attention"
            }
            isRunning = false
            save()
        }
    }

    private func title(for request: String) -> String {
        let firstLine = request.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? request
        return String(firstLine.prefix(48))
    }

    private func handoffContext(for session: ConversationSession, nextProvider: ProviderChoice) -> String {
        guard !session.messages.isEmpty else { return "" }
        if nextProvider != .auto, session.lastProvider == nextProvider.rawValue { return "" }
        let relevant = session.messages.filter { $0.role == .user || $0.role == .assistant }.suffix(16)
        let text = relevant.map { message in
            let speaker = message.role == .user
                ? "USER"
                : (message.provider?.uppercased() ?? "ASSISTANT")
            return "\(speaker):\n\(String(message.text.prefix(12_000)))"
        }.joined(separator: "\n\n")
        return String(text.suffix(180_000))
    }

    private var storageURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OS-1", isDirectory: true)
            .appendingPathComponent("sessions.json", isDirectory: false)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let envelope = try? JSONDecoder().decode(SessionEnvelope.self, from: data),
              [1, 2, 3].contains(envelope.schema) else { return }
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        sessions = envelope.sessions
            .filter { $0.updatedAt >= cutoff }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(30)
            .map { session in
                var bounded = session
                bounded.messages = Array(session.messages.suffix(40))
                return bounded
            }
    }

    private func save() {
        let directory = storageURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let bounded = sessions.sorted { $0.updatedAt > $1.updatedAt }.prefix(30).map { session in
                var copy = session
                copy.messages = Array(session.messages.suffix(40)).map { message in
                    ChatMessage(
                        id: message.id,
                        role: message.role,
                        text: String(message.text.prefix(120_000)),
                        provider: message.provider,
                        permissionProfile: message.permissionProfile,
                        timestamp: message.timestamp
                    )
                }
                return copy
            }
            let data = try JSONEncoder().encode(SessionEnvelope(schema: 3, sessions: bounded))
            try data.write(to: storageURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
        } catch {
            alertMessage = "Session history could not be saved: \(error.localizedDescription)"
        }
    }
}

private enum Theme {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.045)
    static let panel = Color(red: 0.055, green: 0.055, blue: 0.068)
    static let panelRaised = Color(red: 0.075, green: 0.075, blue: 0.092)
    static let border = Color.white.opacity(0.09)
    static let muted = Color.white.opacity(0.48)
    static let text = Color.white.opacity(0.93)
    static let green = Color(red: 0.35, green: 0.92, blue: 0.55)
}

@main
private struct OS1DesktopApp: App {
    @StateObject private var store = SessionStore()

    var body: some Scene {
        WindowGroup("OS-1 Claudex") {
            RootView(store: store)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New session pair") { store.createSession() }
                    .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}

private struct RootView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        HStack(spacing: 0) {
            ProviderRail(store: store)
            Divider().overlay(Theme.border)
            if store.surface == .auto {
                SessionSidebar(store: store)
                Divider().overlay(Theme.border)
                ConversationView(store: store)
            } else {
                NativeSessionBrowser(store: store, provider: store.surface)
            }
        }
        .frame(minWidth: 1_040, minHeight: 680)
        .background(Theme.background)
        .alert("OS-1 Claudex", isPresented: Binding(
            get: { store.alertMessage != nil },
            set: { if !$0 { store.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }
}

private struct ProviderRail: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(spacing: 18) {
            Button { store.showClaudexHome() } label: {
                ZStack {
                    Circle()
                        .fill(AngularGradient(
                            colors: [.pink, .purple, .orange, .pink],
                            center: .center
                        ))
                    Circle().fill(Theme.background).padding(7)
                    Circle().fill(Color.white.opacity(0.9)).frame(width: 7, height: 7)
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .disabled(store.isRunning)
            .help("Claudex home")
            .accessibilityLabel("Claudex home")
            .padding(.bottom, 5)

            ForEach([ProviderChoice.codex, ProviderChoice.claude]) { provider in
                BackendStatus(
                    provider: provider,
                    selected: store.surface == provider,
                    active: store.selectedSession?.lastProvider == provider.rawValue,
                    linked: provider == .codex
                        ? store.selectedSession?.codexSessionID != nil
                        : store.selectedSession?.claudeSessionID != nil,
                    disabled: store.isRunning
                ) { store.inspectBackend(provider) }
            }

            Spacer()

            RailButton(
                provider: .auto,
                selected: store.selectedSession?.provider == .auto,
                disabled: store.isRunning
            ) { store.chooseProvider(.auto) }

            VStack(spacing: 5) {
                Circle().fill(Theme.green).frame(width: 7, height: 7)
                    .shadow(color: Theme.green.opacity(0.7), radius: 5)
                Text("RCC")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 18)
        .frame(width: 82)
        .background(Color.black.opacity(0.2))
    }
}

private struct BackendStatus: View {
    let provider: ProviderChoice
    let selected: Bool
    let active: Bool
    let linked: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: provider.symbol).font(.system(size: 17, weight: .semibold))
                Text(provider == .claude ? "CLAUDE CODE" : "CODEX")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                HStack(spacing: 3) {
                    Circle().fill(linked ? Theme.green : Theme.muted).frame(width: 4, height: 4)
                    Text(linked ? "SYNCED" : "CONNECT")
                        .font(.system(size: 6, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(linked ? provider.tint : Theme.muted)
            .frame(width: 62, height: 66)
            .background(linked ? provider.tint.opacity(selected ? 0.18 : (active ? 0.14 : 0.07)) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(linked ? provider.tint.opacity(selected || active ? 1 : 0.45) : Theme.border, lineWidth: selected ? 1.8 : (active ? 1.6 : 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help("View synchronized \(provider.title) sessions inside Claudex")
        .accessibilityLabel(provider == .claude ? "Claude Code backend" : "Codex backend")
    }
}

private struct NativeSessionBrowser: View {
    @ObservedObject var store: SessionStore
    let provider: ProviderChoice

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider == .claude ? "CLAUDE CODE" : "CODEX")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(provider.tint)
                    HStack(spacing: 6) {
                        Circle().fill(Theme.green).frame(width: 6, height: 6)
                        Text("LOCAL BACKEND · \(store.nativeSessions.count) SESSIONS")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 23)
                .padding(.bottom, 16)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Search \(provider.title) sessions", text: $store.nativeSearch)
                        .textFieldStyle(.plain)
                    Button { store.refreshNativeSessions() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh local sessions")
                    .accessibilityLabel("Refresh backend sessions")
                }
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(Color.black.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                if store.isLoadingNativeSessions && store.nativeSessions.isEmpty {
                    Spacer()
                    ProgressView("Synchronizing local sessions…")
                        .controlSize(.small)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else if store.filteredNativeSessions.isEmpty {
                    Spacer()
                    Text("No local sessions found")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(store.filteredNativeSessions) { session in
                                NativeSessionRow(
                                    session: session,
                                    selected: store.selectedNativeSessionID == session.id,
                                    tint: provider.tint
                                ) { store.selectNativeSession(session.id) }
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.bottom, 12)
                    }
                }
            }
            .frame(width: 310)
            .background(Theme.panel)

            Divider().overlay(Theme.border)

            NativeTranscriptView(store: store, provider: provider)
        }
    }
}

private struct NativeSessionRow: View {
    let session: NativeSessionSummary
    let selected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Circle().fill(session.linkedTitle == nil ? Theme.muted : Theme.green)
                        .frame(width: 6, height: 6)
                    Text(session.displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if session.linkedTitle != nil {
                        Text("OS1")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.green)
                    }
                }
                HStack(spacing: 6) {
                    Text(URL(fileURLWithPath: session.workspace).lastPathComponent.isEmpty
                         ? "No workspace"
                         : URL(fileURLWithPath: session.workspace).lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Text(compactSessionAge(session.updatedAt))
                        .lineLimit(1)
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? tint.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(selected ? tint.opacity(0.8) : Theme.border, lineWidth: selected ? 1.4 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.displayTitle)
    }
}

private struct NativeTranscriptView: View {
    @ObservedObject var store: SessionStore
    let provider: ProviderChoice

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.selectedNativeSession?.displayTitle ?? "Select a session")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Circle().fill(Theme.green).frame(width: 6, height: 6)
                        Text(store.selectedNativeSession?.linkedTitle == nil
                             ? "Native local session"
                             : "Synchronized with OS-1 Claudex")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                if let workspace = store.selectedNativeSession?.workspace, !workspace.isEmpty {
                    Label(URL(fileURLWithPath: workspace).lastPathComponent, systemImage: "folder")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(Theme.panelRaised)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 70)
            .background(Theme.panel)

            Divider().overlay(Theme.border)

            if store.selectedNativeSession == nil {
                Spacer()
                Text("Choose a \(provider.title) session from the left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Spacer()
            } else if store.isLoadingNativeSessions && store.nativeMessages.isEmpty {
                Spacer()
                ProgressView("Loading synchronized transcript…")
                    .controlSize(.small)
                    .foregroundStyle(Theme.muted)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(store.nativeMessages) { message in
                                NativeMessageCard(message: message, provider: provider)
                                    .id(message.id)
                            }
                            if store.nativeMessages.isEmpty {
                                Text("This session has no visible user or assistant messages yet.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                                    .padding(.top, 60)
                            }
                        }
                        .padding(22)
                    }
                    .onAppear { scrollToBottom(proxy) }
                    .onChange(of: store.nativeMessages.count) { _ in scrollToBottom(proxy) }
                }
            }

            Divider().overlay(Theme.border)
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Read-only synchronized backend view · use Claudex Home to route the next task")
                Spacer()
                Text(provider == .claude ? "CLAUDE CODE" : "CODEX")
                    .foregroundStyle(provider.tint)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Theme.panel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let id = store.nativeMessages.last?.id else { return }
        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .bottom) }
    }
}

private struct NativeMessageCard: View {
    let message: NativeSessionMessage
    let provider: ProviderChoice

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 100) }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: message.role == .user ? "person.crop.circle.fill" : provider.symbol)
                    Text(message.role == .user ? "YOU" : (provider == .claude ? "CLAUDE CODE" : "CODEX"))
                    Spacer()
                    if let timestamp = message.timestamp {
                        Text(timestamp, style: .time)
                    }
                }
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(message.role == .user ? Theme.muted : provider.tint)
                Text(message.text)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(message.role == .user ? Theme.panelRaised : provider.tint.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(message.role == .user ? Theme.border : provider.tint.opacity(0.25))
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))
            if message.role != .user { Spacer(minLength: 60) }
        }
    }
}

private struct RailButton: View {
    let provider: ProviderChoice
    let selected: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: provider.symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(provider.title.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
            }
            .foregroundStyle(selected ? provider.tint : Theme.muted)
            .frame(width: 58, height: 58)
            .background(selected ? provider.tint.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? provider.tint : Theme.border, lineWidth: selected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help("Use \(provider.title) for the next turn")
    }
}

private struct SessionSidebar: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OS-1")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(Theme.muted)
                Text("CLAUDEX")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 18)
            .padding(.top, 23)
            .padding(.bottom, 18)

            Button { store.createSession() } label: {
                Label("New session pair", systemImage: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Theme.panelRaised)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search sessions", text: $store.search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.black.opacity(0.16))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 14)
            .padding(.top, 10)

            HStack {
                Text("SESSION PAIRS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("\(store.filteredSessions.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.filteredSessions) { session in
                        SessionRow(
                            session: session,
                            selected: store.selectedSessionID == session.id
                        ) { store.select(session.id) }
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Circle().fill(Theme.green).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Governance active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Real native sessions")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(16)
        }
        .frame(width: 270)
        .background(Theme.panel)
    }
}

private struct SessionRow: View {
    let session: ConversationSession
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle().fill(session.provider.tint).frame(width: 6, height: 6)
                    Text(session.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    Text(URL(fileURLWithPath: session.workspace).lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    NativeBadge(label: "C", linked: session.codexSessionID != nil, tint: ProviderChoice.codex.tint)
                    NativeBadge(label: "A", linked: session.claudeSessionID != nil, tint: ProviderChoice.claude.tint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.white.opacity(0.07) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Theme.border : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct NativeBadge: View {
    let label: String
    let linked: Bool
    let tint: Color

    var body: some View {
        Text(label)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(linked ? tint : Theme.muted.opacity(0.55))
            .frame(width: 17, height: 15)
            .background(linked ? tint.opacity(0.13) : Color.white.opacity(0.025))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(linked ? tint.opacity(0.45) : Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct ConversationView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(spacing: 0) {
            ConversationHeader(store: store)
            Divider().overlay(Theme.border)
            if let session = store.selectedSession {
                if session.messages.isEmpty {
                    WelcomeView(store: store, session: session)
                } else {
                    MessageTimeline(session: session, isRunning: store.isRunning)
                }
                ComposerView(store: store, session: session)
            }
        }
        .background(Theme.background)
    }
}

private struct ConversationHeader: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.selectedSession?.title ?? "OS-1 Claudex")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(Theme.green).frame(width: 6, height: 6)
                    Text(store.statusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer()

            if let session = store.selectedSession {
                Menu {
                    Button("Auto routing") { store.chooseProvider(.auto) }
                    Divider()
                    Menu("Codex capacity · \(session.effectiveCodexCapacity)%") {
                        ForEach([0, 10, 25, 50, 75, 100], id: \.self) { value in
                            Button("\(value)%") { store.setCapacity(.codex, value: value) }
                        }
                    }
                    Menu("Claude capacity · \(session.effectiveClaudeCapacity)%") {
                        ForEach([0, 10, 25, 50, 75, 100], id: \.self) { value in
                            Button("\(value)%") { store.setCapacity(.claude, value: value) }
                        }
                    }
                    Divider()
                    Button("Force Codex next turn") { store.chooseProvider(.codex) }
                    Button("Force Claude next turn") { store.chooseProvider(.claude) }
                    Divider()
                    Button("Inspect Codex backend") { store.inspectBackend(.codex) }
                        .disabled(session.codexSessionID == nil)
                    Button("Inspect Claude backend") { store.inspectBackend(.claude) }
                        .disabled(session.claudeSessionID == nil)
                } label: {
                    Label(
                        session.provider == .auto
                            ? "Auto mix · C\(session.effectiveCodexCapacity) A\(session.effectiveClaudeCapacity)"
                            : "Override · \(session.provider.title)",
                        systemImage: "slider.horizontal.3"
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.green)
                    .padding(.horizontal, 10)
                    .frame(height: 35)
                    .background(Theme.green.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.green.opacity(0.3)))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(store.isRunning)

                Button { store.chooseWorkspace() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "folder")
                        Text(URL(fileURLWithPath: session.workspace).lastPathComponent)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 11)
                    .frame(height: 35)
                    .background(Theme.panelRaised)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(store.isRunning)
                .help(session.workspace)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(Theme.panel.opacity(0.8))
    }
}

private struct WelcomeView: View {
    @ObservedObject var store: SessionStore
    let session: ConversationSession

    private let suggestions = [
        "Inspect this project and explain the safest next step.",
        "Find the current bug, fix it, and verify the result.",
        "Review the repository and make the smallest production-ready improvement.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 34)
                Text("What are we building?")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("Pick a project once. OS-1 treats Codex and Claude Code as managed backends, then selects the backend, model tier, and reasoning effort from task fit and weekly capacity.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    WelcomeStep(number: "1", title: "Choose folder", detail: "The project OS-1 may inspect or edit")
                    WelcomeStep(number: "2", title: "Set capacity", detail: "Default mix conserves scarce Codex usage")
                    WelcomeStep(number: "3", title: "Use OS-1", detail: "RCC selects backend, model, and effort")
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("TRY ONE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(Theme.muted)
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button { store.useSuggestion(suggestion) } label: {
                            HStack {
                                Text(suggestion)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(Theme.panelRaised)
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 52)
            .frame(maxWidth: 850, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct WelcomeStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(number)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.green)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct MessageTimeline: View {
    let session: ConversationSession
    let isRunning: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(session.messages) { message in
                        MessageView(message: message).id(message.id)
                    }
                    if isRunning {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Working in \(session.workspace)…")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .id("running")
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 28)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                if let last = session.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: session.messages.count) { _ in
                if let last = session.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}

private struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 100)
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: message.provider == "claude"
                        ? ProviderChoice.claude.symbol
                        : ProviderChoice.codex.symbol)
                    Text((message.provider ?? "OS-1").uppercased())
                    if let permission = message.permissionProfile {
                        Text("· \(permission.replacingOccurrences(of: "_", with: " "))")
                            .foregroundStyle(Theme.muted)
                    }
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(message.provider == "claude"
                    ? ProviderChoice.claude.tint
                    : ProviderChoice.codex.tint)
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .receipt:
            HStack(spacing: 9) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(Theme.green)
                Text("RCC GOVERNANCE RECEIPT")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                Text(message.text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("VERIFIED")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.green)
            }
            .padding(.horizontal, 12)
            .frame(height: 39)
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .system:
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                Text(message.text)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .foregroundStyle(Theme.muted)
            .padding(.vertical, 4)
        }
    }
}

private struct ComposerView: View {
    @ObservedObject var store: SessionStore
    let session: ConversationSession
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                TextEditor(text: $store.composer)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(minHeight: 54, maxHeight: 120)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .disabled(store.isRunning)
                    .overlay(alignment: .topLeading) {
                        if store.composer.isEmpty {
                            Text("Tell OS-1 what outcome you want…")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.3))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }

                Button { store.send() } label: {
                    Image(systemName: store.isRunning ? "hourglass" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.86))
                        .frame(width: 38, height: 38)
                        .background(session.provider.tint)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(store.isRunning || store.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(10)
            .background(Theme.panelRaised)
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 13))

            HStack {
                Label(URL(fileURLWithPath: session.workspace).lastPathComponent, systemImage: "folder")
                Text("·")
                Text("OS-1 · RCC governed")
                Text("·")
                Text("capacity C\(session.effectiveCodexCapacity) / A\(session.effectiveClaudeCapacity)")
                Text("·")
                Text("Codex \(session.codexSessionID == nil ? "not linked" : "linked")")
                Text("·")
                Text("Claude \(session.claudeSessionID == nil ? "not linked" : "linked")")
                Spacer()
                Text("⌘↩ send")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(Theme.background)
    }
}
