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

final class KitCLI {
    let executableURL: URL

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    func status() throws -> KitStatus {
        let data = try run(arguments: ["status", "--json"])
        return try JSONDecoder().decode(KitStatus.self, from: data)
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
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let kit = KitCLI(executableURL: URL(fileURLWithPath: ProcessInfo.processInfo.environment["KIT_CLI"] ?? "/usr/local/bin/kit"))

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
            addCommand("Listen", id: "listen", status: status, to: menu)
            addCommand("Next Meeting Prep", id: "next_meeting_prep", status: status, to: menu)
            addCommand("Brief", id: "brief", status: status, to: menu)

            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Notifications: \(status.notifications.available ? "available" : "not configured")", action: nil, keyEquivalent: ""))
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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
