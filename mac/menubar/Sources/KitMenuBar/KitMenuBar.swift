import AppKit
import Foundation

struct KitStatus: Decodable {
    struct Health: Decodable {
        let indicator: String
        let message: String
    }

    struct Command: Decodable {
        let label: String
        let command: [String]
        let implemented: Bool
    }

    struct Notifications: Decodable {
        let backend: String
        let appIcon: String
        let available: Bool

        enum CodingKeys: String, CodingKey {
            case backend
            case appIcon = "app_icon"
            case available
        }
    }

    let kitVersion: String
    let health: Health
    let commands: [String: Command]
    let notifications: Notifications

    enum CodingKeys: String, CodingKey {
        case kitVersion = "kit_version"
        case health
        case commands
        case notifications
    }
}

struct ListenStatus: Decodable {
    let phase: String
    let recorderPid: Int?
    let title: String?
    let sessionId: String?
    let chunkCount: Int
    let sourceDevice: String?
    let startedAt: String?
    let progressMessage: String?
    let latestError: String?
    let transcriptMd: String?

    enum CodingKeys: String, CodingKey {
        case phase
        case recorderPid = "recorder_pid"
        case title
        case sessionId = "session_id"
        case chunkCount = "chunk_count"
        case sourceDevice = "source_device"
        case startedAt = "started_at"
        case progressMessage = "progress_message"
        case latestError = "latest_error"
        case transcriptMd = "transcript_md"
    }

    var isActive: Bool {
        phase == "recording" || phase == "paused" || phase == "transcribing"
    }
}

final class KitCLI {
    let executableURL: URL

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    func status() throws -> KitStatus {
        let data = try run(arguments: ["status", "--json"])
        return try JSONDecoder().decode(KitStatus.self, from: data)
    }

    func listenStatus() throws -> ListenStatus {
        let data = try run(arguments: ["listen", "status", "--json"])
        return try JSONDecoder().decode(ListenStatus.self, from: data)
    }

    func run(arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "KitMenuBar",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "kit \(arguments.joined(separator: " ")) failed"]
            )
        }
        return data
    }

    func runAsync(arguments: [String], completion: @escaping (Result<Data, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try self.run(arguments: arguments)
                DispatchQueue.main.async { completion(.success(data)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let kit = KitCLI(executableURL: URL(fileURLWithPath: ProcessInfo.processInfo.environment["KIT_CLI"] ?? "/usr/local/bin/kit"))
    private var lastError: String?
    private var listenStatus: ListenStatus?
    private var kitHealthOK = true
    private var listenPollTimer: Timer?
    private var listenPulse = false
    private var menuOpen = false
    private var listenStatusMenuItem: NSMenuItem?
    private var listenDetailMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.button?.title = "Kit"
        refreshMenu()
        startListenPollingIfNeeded()
    }

    @objc private func refreshMenu() {
        refreshListenSnapshot()
        let menu = NSMenu()
        menu.delegate = self

        do {
            let status = try kit.status()
            kitHealthOK = status.health.indicator == "ok"
            statusItem.button?.title = statusBarTitle()
            menu.addItem(NSMenuItem(title: status.health.message, action: nil, keyEquivalent: ""))
            menu.addItem(.separator())

            addCommand("Open Loops", id: "open_loops", status: status, to: menu)
            addCommand("Overdue Commitments", id: "overdue_commitments", status: status, to: menu)
            addCommand("Today's Surface", id: "today_surface", status: status, to: menu)
            addListenControls(to: menu)
            addCommand("Next Meeting Prep", id: "next_meeting_prep", status: status, to: menu)
            addCommand("Brief", id: "brief", status: status, to: menu)

            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Notifications: \(status.notifications.available ? "available" : "not configured")", action: nil, keyEquivalent: ""))
            if let lastError {
                menu.addItem(NSMenuItem(title: "Last error: \(lastError)", action: nil, keyEquivalent: ""))
            }
        } catch {
            kitHealthOK = false
            statusItem.button?.title = "Kit!"
            menu.addItem(NSMenuItem(title: error.localizedDescription, action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshMenu), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quit Kit Menu Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        refreshListenSnapshot()
        updateListenMenuItems()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
    }

    private func addCommand(_ fallbackTitle: String, id: String, status: KitStatus, to menu: NSMenu) {
        guard let command = status.commands[id] else { return }

        let suffix = command.implemented ? "" : " (planned)"
        let item = NSMenuItem(title: "\(command.label.isEmpty ? fallbackTitle : command.label)\(suffix)", action: nil, keyEquivalent: "")
        item.isEnabled = command.implemented
        menu.addItem(item)
    }

    private func addListenControls(to menu: NSMenu) {
        let statusItem = NSMenuItem(title: listenPrimaryLine(), action: nil, keyEquivalent: "")
        menu.addItem(statusItem)
        listenStatusMenuItem = statusItem

        let detailItem = NSMenuItem(title: listenDetailLine(), action: nil, keyEquivalent: "")
        menu.addItem(detailItem)
        listenDetailMenuItem = detailItem

        guard let listen = listenStatus else {
            addListenAction("Start Listening", action: #selector(startListen), enabled: true, to: menu)
            return
        }

        switch listen.phase {
        case "recording":
            addListenAction("Pause", action: #selector(pauseListen), enabled: true, to: menu)
            addListenAction("Stop", action: #selector(stopListen), enabled: true, to: menu)
        case "paused":
            addListenAction("Resume", action: #selector(resumeListen), enabled: true, to: menu)
            addListenAction("Stop", action: #selector(stopListen), enabled: true, to: menu)
        case "transcribing":
            addListenAction("Transcribing…", action: nil, enabled: false, to: menu)
        case "error":
            addListenAction("Start Listening", action: #selector(startListen), enabled: true, to: menu)
        default:
            addListenAction("Start Listening", action: #selector(startListen), enabled: true, to: menu)
        }
    }

    private func addListenAction(_ title: String, action: Selector?, enabled: Bool, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.isEnabled = enabled
        menu.addItem(item)
    }

    @objc private func startListen() {
        var arguments = ["listen", "start"]
        if let device = ProcessInfo.processInfo.environment["KIT_LISTEN_AUDIO_DEVICE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !device.isEmpty {
            arguments.append(device)
        }
        arguments.append(contentsOf: ["--json", "Menubar Listen"])
        runListenCommand(arguments)
    }

    @objc private func pauseListen() {
        runListenCommand(["listen", "pause", "--json"])
    }

    @objc private func resumeListen() {
        runListenCommand(["listen", "resume", "--json"])
    }

    @objc private func stopListen() {
        runListenCommand(["listen", "stop", "--json"])
    }

    private func runListenCommand(_ arguments: [String]) {
        kit.runAsync(arguments: arguments) { result in
            switch result {
            case .success:
                self.lastError = nil
            case .failure(let error):
                self.lastError = error.localizedDescription
            }
            self.refreshListenSnapshot()
            self.refreshMenu()
            self.startListenPollingIfNeeded()
        }
        refreshListenSnapshot()
        startListenPollingIfNeeded()
    }

    private func refreshListenSnapshot() {
        do {
            listenStatus = try kit.listenStatus()
            lastError = listenStatus?.phase == "error" ? listenStatus?.latestError : lastError
        } catch {
            listenStatus = nil
        }
        statusItem.button?.title = statusBarTitle()
        updateListenMenuItems()
        startListenPollingIfNeeded()
    }

    private func startListenPollingIfNeeded() {
        let shouldPoll = listenStatus?.isActive == true
        if shouldPoll {
            if listenPollTimer == nil {
                listenPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    self?.pollListenStatus()
                }
            }
        } else {
            listenPollTimer?.invalidate()
            listenPollTimer = nil
            listenPulse = false
        }
    }

    @objc private func pollListenStatus() {
        DispatchQueue.global(qos: .utility).async {
            let status = try? self.kit.listenStatus()
            DispatchQueue.main.async {
                self.listenStatus = status
                self.listenPulse.toggle()
                self.statusItem.button?.title = self.statusBarTitle()
                self.updateListenMenuItems()
                if status?.isActive != true {
                    self.startListenPollingIfNeeded()
                    if !self.menuOpen {
                        self.refreshMenu()
                    }
                }
            }
        }
    }

    private func updateListenMenuItems() {
        listenStatusMenuItem?.title = listenPrimaryLine()
        listenDetailMenuItem?.title = listenDetailLine()
    }

    private func statusBarTitle() -> String {
        guard let listen = listenStatus, listen.isActive || listen.phase == "error" else {
            return kitHealthOK ? "Kit" : "Kit*"
        }

        switch listen.phase {
        case "recording":
            return listenPulse ? "● REC" : "○ REC"
        case "paused":
            return "⏸"
        case "transcribing":
            return "…"
        case "error":
            return "Kit!"
        default:
            return kitHealthOK ? "Kit" : "Kit*"
        }
    }

    private func listenPrimaryLine() -> String {
        guard let listen = listenStatus else {
            return "Listen: unavailable"
        }

        switch listen.phase {
        case "recording":
            return "\(listenPulse ? "●" : "○") REC  \(formatElapsed(listen))  \(listen.title ?? "Session")"
        case "paused":
            return "❚❚ PAUSED  \(formatElapsed(listen))  \(listen.title ?? "Session")"
        case "transcribing":
            return "Transcribing…  \(listen.title ?? "Session")"
        case "completed":
            return "Done  \(listen.title ?? "Session")"
        case "error":
            return "Listen error  \(listen.latestError ?? "failed")"
        default:
            return "Listen: idle"
        }
    }

    private func listenDetailLine() -> String {
        guard let listen = listenStatus else {
            return "Start a session from the menu"
        }

        switch listen.phase {
        case "recording", "paused":
            let device = listen.sourceDevice ?? "?"
            return "\(device) · chunks \(listen.chunkCount)"
        case "transcribing":
            return listen.progressMessage.map { "… \($0)" } ?? "… working"
        case "completed":
            if let transcript = listen.transcriptMd {
                return "Transcript: \(transcript)"
            }
            return "Transcript ready"
        case "error":
            return listen.latestError ?? "Recording failed"
        default:
            return "Device: \(ProcessInfo.processInfo.environment["KIT_LISTEN_AUDIO_DEVICE"] ?? "not set")"
        }
    }

    private func formatElapsed(_ listen: ListenStatus) -> String {
        guard let startedAt = listen.startedAt else { return "00:00" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var start = formatter.date(from: startedAt)
        if start == nil {
            formatter.formatOptions = [.withInternetDateTime]
            start = formatter.date(from: startedAt)
        }
        guard let start else { return "00:00" }

        let total = max(Int(Date().timeIntervalSince(start)), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
