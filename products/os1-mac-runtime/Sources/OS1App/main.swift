import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let workspace = NSTextField(string: FileManager.default.homeDirectoryForCurrentUser.path)
    private let prompt = NSTextView()
    private let output = NSTextView()
    private let runButton = NSButton(title: "Run with OS-1", target: nil, action: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Open OS-1 Codex"
        window.center()

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Open OS-1 Codex")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        root.addArrangedSubview(title)
        root.addArrangedSubview(NSTextField(labelWithString: "Workspace"))
        root.addArrangedSubview(workspace)
        root.addArrangedSubview(NSTextField(labelWithString: "Task"))
        let promptScroll = NSScrollView()
        promptScroll.hasVerticalScroller = true
        promptScroll.documentView = prompt
        promptScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        root.addArrangedSubview(promptScroll)
        runButton.target = self
        runButton.action = #selector(runTask)
        runButton.bezelStyle = .rounded
        root.addArrangedSubview(runButton)
        root.addArrangedSubview(NSTextField(labelWithString: "Output"))
        output.isEditable = false
        let outputScroll = NSScrollView()
        outputScroll.hasVerticalScroller = true
        outputScroll.documentView = output
        root.addArrangedSubview(outputScroll)

        window.contentView = NSView()
        window.contentView?.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
        ])
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func runTask() {
        let task = prompt.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { output.string = "Enter a task first."; return }
        runButton.isEnabled = false
        output.string = "OS-1 is running…"
        let selectedWorkspace = workspace.stringValue
        Task { @MainActor [weak self] in
            let text = await Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/local/bin/os1")
                process.arguments = ["run", "--workspace", selectedWorkspace, "--prompt", task]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    return String(decoding: data, as: UTF8.self)
                } catch {
                    return "OS-1 failed to start: \(error)"
                }
            }.value
            self?.output.string = text
            self?.runButton.isEnabled = true
        }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
