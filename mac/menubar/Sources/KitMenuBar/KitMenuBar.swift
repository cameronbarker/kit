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

    enum CodingKeys: String, CodingKey {
        case phase
        case recorderPid = "recorder_pid"
        case title
        case sessionId = "session_id"
        case chunkCount = "chunk_count"
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let kit = KitCLI(executableURL: URL(fileURLWithPath: ProcessInfo.processInfo.environment["KIT_CLI"] ?? "/usr/local/bin/kit"))
    private var lastError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.button?.title = "Kit"
        refreshMenu()
    }

    @objc private func refreshMenu() {
        let menu = NSMenu()

        do {
            let status = try kit.status()
            statusItem.button?.title = status.health.indicator == "ok" ? "Kit" : "Kit*"
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
            statusItem.button?.title = "Kit!"
            menu.addItem(NSMenuItem(title: error.localizedDescription, action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshMenu), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quit Kit Menu Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func addCommand(_ fallbackTitle: String, id: String, status: KitStatus, to menu: NSMenu) {
        guard let command = status.commands[id] else { return }

        let suffix = command.implemented ? "" : " (planned)"
        let item = NSMenuItem(title: "\(command.label.isEmpty ? fallbackTitle : command.label)\(suffix)", action: nil, keyEquivalent: "")
        item.isEnabled = command.implemented
        menu.addItem(item)
    }

    private func addListenControls(to menu: NSMenu) {
        do {
            let listen = try kit.listenStatus()
            let title = listen.title ?? "No active session"
            menu.addItem(NSMenuItem(title: "Listen: \(listen.phase) · \(title) · chunks \(listen.chunkCount)", action: nil, keyEquivalent: ""))

            switch listen.phase {
            case "recording", "transcribing":
                addListenAction("Pause", action: #selector(pauseListen), enabled: listen.phase == "recording", to: menu)
                addListenAction("Stop", action: #selector(stopListen), enabled: true, to: menu)
            case "paused":
                addListenAction("Resume", action: #selector(resumeListen), enabled: true, to: menu)
                addListenAction("Stop", action: #selector(stopListen), enabled: true, to: menu)
            default:
                addListenAction("Start Listening", action: #selector(startListen), enabled: true, to: menu)
            }
        } catch {
            menu.addItem(NSMenuItem(title: "Listen status unavailable", action: nil, keyEquivalent: ""))
            addListenAction("Start Listening", action: #selector(startListen), enabled: true, to: menu)
        }
    }

    private func addListenAction(_ title: String, action: Selector, enabled: Bool, to menu: NSMenu) {
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
            self.refreshMenu()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
