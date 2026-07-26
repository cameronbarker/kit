import AppKit
import Foundation
import UniformTypeIdentifiers

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

struct AttentionSnapshot {
    var needsReview: Int?
    var waitingOnMe: Int?
    var open: Int?
    var nextActionText: String?
    var fetchedAt: Date?
}

extension Dictionary where Key == String, Value == Any {
    func digInt(_ keys: String...) -> Int? {
        var current: Any = self
        for key in keys {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[key] else {
                return nil
            }
            current = next
        }

        if let int = current as? Int {
            return int
        }
        if let number = current as? NSNumber {
            return number.intValue
        }
        return nil
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
    private let statusIcon = AppDelegate.loadStatusIcon()
    private var lastError: String?
    private var statusError: String?
    private var listenStatus: ListenStatus?
    private var kitHealthOK = true
    private var listenPollTimer: Timer?
    private var listenPulse = false
    private var menuOpen = false
    private var listenStatusMenuItem: NSMenuItem?
    private var listenDetailMenuItem: NSMenuItem?
    private var kitStatus: KitStatus?
    private var attention = AttentionSnapshot()
    private var lastResultLine: String?
    private var fileTranscriptionInFlight = false
    private let attentionCacheSeconds: TimeInterval = 15
    private var statusRefreshInFlight = false
    private var listenRefreshInFlight = false
    private var attentionRefreshInFlight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        applyStatusItemAppearance()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        renderMenu(in: menu)
        refreshMenu()
        startListenPollingIfNeeded()
    }

    @objc private func refreshMenu() {
        renderMenu()
        refreshSnapshots(forceAttentionRefresh: true)
    }

    private func renderMenu(in existingMenu: NSMenu? = nil) {
        let menu = existingMenu ?? statusItem.menu ?? NSMenu()
        menu.removeAllItems()
        menu.delegate = self
        listenStatusMenuItem = nil
        listenDetailMenuItem = nil

        if let status = kitStatus {
            kitHealthOK = status.health.indicator == "ok"
        }
        applyStatusItemAppearance()

        addSectionTitle("Now", to: menu)
        addCommand("Needs review", id: "needs_review", count: attention.needsReview, action: #selector(runNeedsReview), status: kitStatus, to: menu)
        addCommand("Waiting on me", id: "waiting_on_me", count: attention.waitingOnMe, action: #selector(runWaitingOnMe), status: kitStatus, to: menu)
        if let nextActionText = attention.nextActionText, !nextActionText.isEmpty {
            addInfoLine("Next: \(truncate(nextActionText, limit: 54))", to: menu)
        }

        menu.addItem(.separator())
        addSectionTitle("Capture", to: menu)
        addListenControls(to: menu)

        menu.addItem(.separator())
        addSectionTitle("Support", to: menu)
        addCommand("Today's Surface", id: "today_surface", count: attention.open, action: #selector(runTodaySurface), status: kitStatus, to: menu)
        addCommand("Weekly Brief", id: "brief", count: nil, action: #selector(runBrief), status: kitStatus, to: menu)

        if let diagnosticError = lastError ?? statusError {
            menu.addItem(.separator())
            addDiagnostics(status: kitStatus, error: diagnosticError, to: menu)
        } else if let lastResultLine {
            menu.addItem(.separator())
            addInfoLine(lastResultLine, to: menu)
        }

        menu.addItem(.separator())
        addAction("Refresh", action: #selector(refreshMenu), to: menu, keyEquivalent: "r")
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        if statusItem.menu !== menu {
            statusItem.menu = menu
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        renderMenu(in: menu)
        refreshSnapshots(forceAttentionRefresh: false)
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
    }

    private func addCommand(_ fallbackTitle: String, id: String, count: Int?, action: Selector, status: KitStatus?, to menu: NSMenu) {
        var title = fallbackTitle
        if let command = status?.commands[id] {
            guard command.implemented else { return }
            title = command.label.isEmpty ? fallbackTitle : command.label
        }
        if let count {
            title += " (\(count))"
        }
        addAction(title, action: action, to: menu)
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
            addListenAction("Transcribe Audio File…", action: #selector(transcribeAudioFile), enabled: canTranscribeAudioFile, to: menu)
            return
        }

        switch listen.phase {
        case "recording":
            addListenAction("Transcribe Audio File…", action: #selector(transcribeAudioFile), enabled: false, to: menu)
            addListenAction("Pause", action: #selector(pauseListen), enabled: true, to: menu)
            addListenAction("Stop", action: #selector(stopListen), enabled: true, to: menu)
        case "paused":
            addListenAction("Transcribe Audio File…", action: #selector(transcribeAudioFile), enabled: false, to: menu)
            addListenAction("Resume", action: #selector(resumeListen), enabled: true, to: menu)
            addListenAction("Stop", action: #selector(stopListen), enabled: true, to: menu)
        case "transcribing":
            addListenAction("Transcribe Audio File…", action: #selector(transcribeAudioFile), enabled: false, to: menu)
            addListenAction("Transcribing…", action: nil, enabled: false, to: menu)
        case "error":
            addListenAction("Start Listening", action: #selector(startListen), enabled: canRetryListen, to: menu)
            addListenAction("Transcribe Audio File…", action: #selector(transcribeAudioFile), enabled: canTranscribeAudioFile, to: menu)
        default:
            addListenAction("Start Listening", action: #selector(startListen), enabled: true, to: menu)
            addListenAction("Transcribe Audio File…", action: #selector(transcribeAudioFile), enabled: canTranscribeAudioFile, to: menu)
        }
    }

    private var canTranscribeAudioFile: Bool {
        !fileTranscriptionInFlight && listenStatus?.isActive != true
    }

    private var canRetryListen: Bool {
        guard let error = listenStatus?.latestError else { return true }
        return !isMissingListenModelError(error)
    }

    private func addListenAction(_ title: String, action: Selector?, enabled: Bool, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
    }

    private func addSectionTitle(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addInfoLine(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addAction(_ title: String, action: Selector, to menu: NSMenu, keyEquivalent: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = true
        menu.addItem(item)
    }

    private func addDiagnostics(status: KitStatus?, error: String, to menu: NSMenu) {
        let diagnostics = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if let status {
            addInfoLine(status.health.message, to: submenu)
            addInfoLine("Notifications: \(status.notifications.available ? "available" : "not configured")", to: submenu)
        } else {
            addInfoLine("Kit status unavailable", to: submenu)
        }
        let label = listenStatus?.phase == "error" ? "Last listen error" : "Last error"
        addInfoLine("\(label): \(truncate(error, limit: 96))", to: submenu)
        diagnostics.submenu = submenu
        menu.addItem(diagnostics)
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

    @objc private func transcribeAudioFile() {
        guard canTranscribeAudioFile else {
            lastResultLine = "Transcribe: listen is active"
            renderMenu()
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Transcribe Audio File"
        panel.prompt = "Transcribe"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = ["m4a", "wav", "mp3", "aac", "caf", "mp4", "mov"].compactMap {
            UTType(filenameExtension: $0)
        }

        guard panel.runModal() == .OK,
              let inputURL = panel.url else {
            return
        }

        runFileTranscription(inputURL)
    }

    @objc private func runNeedsReview() {
        runKitAction(arguments: ["surface", "--needs-review-only", "--json"], label: "Needs review")
    }

    @objc private func runWaitingOnMe() {
        runKitAction(arguments: ["followup", "--waiting-on-me", "--json"], label: "Waiting on me")
    }

    @objc private func runTodaySurface() {
        runKitAction(arguments: ["surface"], label: "Today's Surface")
    }

    @objc private func runBrief() {
        runKitAction(arguments: ["brief", "--json"], label: "Weekly Brief")
    }

    private func runListenCommand(_ arguments: [String]) {
        kit.runAsync(arguments: arguments) { result in
            switch result {
            case .success:
                self.lastError = nil
            case .failure(let error):
                self.lastError = error.localizedDescription
            }
            self.renderMenu()
            self.refreshSnapshots(forceAttentionRefresh: true)
        }
        refreshListenSnapshotAsync()
        startListenPollingIfNeeded()
    }

    private func runFileTranscription(_ inputURL: URL) {
        fileTranscriptionInFlight = true
        lastError = nil
        lastResultLine = "File transcription: running..."
        renderMenu()

        kit.runAsync(arguments: ["listen", "transcribe", "--json", inputURL.path]) { result in
            self.fileTranscriptionInFlight = false
            switch result {
            case .success(let data):
                let summary = self.fileTranscriptionSummary(data)
                self.lastError = nil
                self.lastResultLine = summary
                self.notify(summary)
            case .failure(let error):
                self.lastError = error.localizedDescription
                self.lastResultLine = nil
                self.notify("File transcription failed")
            }
            self.renderMenu()
            self.refreshSnapshots(forceAttentionRefresh: true)
        }
    }

    private func runKitAction(arguments: [String], label: String) {
        lastResultLine = "\(label): running..."
        renderMenu()
        kit.runAsync(arguments: arguments) { result in
            switch result {
            case .success(let data):
                let summary = self.summary(for: label, data: data)
                self.lastError = nil
                self.lastResultLine = summary
                self.notify(summary)
            case .failure(let error):
                self.lastError = error.localizedDescription
                self.lastResultLine = nil
                self.notify("\(label) failed")
            }
            self.renderMenu()
            self.refreshSnapshots(forceAttentionRefresh: true)
        }
    }

    private func notify(_ message: String) {
        kit.runAsync(arguments: ["notify", message]) { _ in }
    }

    private func refreshSnapshots(forceAttentionRefresh: Bool) {
        refreshStatusSnapshotAsync()
        refreshListenSnapshotAsync()
        refreshAttentionSnapshotAsync(force: forceAttentionRefresh)
    }

    private func refreshStatusSnapshotAsync() {
        guard !statusRefreshInFlight else { return }

        statusRefreshInFlight = true
        kit.runAsync(arguments: ["status", "--json"]) { result in
            self.statusRefreshInFlight = false

            switch result {
            case .success(let data):
                do {
                    let status = try JSONDecoder().decode(KitStatus.self, from: data)
                    self.kitStatus = status
                    self.kitHealthOK = status.health.indicator == "ok"
                    self.statusError = nil
                } catch {
                    self.kitStatus = nil
                    self.kitHealthOK = false
                    self.statusError = error.localizedDescription
                }
            case .failure(let error):
                self.kitStatus = nil
                self.kitHealthOK = false
                self.statusError = error.localizedDescription
            }

            self.applyStatusItemAppearance()
            self.renderMenu()
        }
    }

    private func refreshListenSnapshotAsync() {
        guard !listenRefreshInFlight else { return }

        listenRefreshInFlight = true
        kit.runAsync(arguments: ["listen", "status", "--json"]) { result in
            self.listenRefreshInFlight = false

            switch result {
            case .success(let data):
                self.listenStatus = try? JSONDecoder().decode(ListenStatus.self, from: data)
                self.lastError = self.listenStatus?.phase == "error" ? self.listenStatus?.latestError : self.lastError
            case .failure:
                self.listenStatus = nil
            }

            self.applyStatusItemAppearance()
            self.updateListenMenuItems()
            self.startListenPollingIfNeeded()
            self.renderMenu()
        }
    }

    private func refreshAttentionSnapshotAsync(force: Bool) {
        if !force,
           let fetchedAt = attention.fetchedAt,
           Date().timeIntervalSince(fetchedAt) < attentionCacheSeconds {
            return
        }
        guard !attentionRefreshInFlight else {
            return
        }

        attentionRefreshInFlight = true
        DispatchQueue.global(qos: .userInitiated).async {
            var next = AttentionSnapshot(fetchedAt: Date())
            if let surface = try? self.kit.run(arguments: ["surface", "--json"]),
               let json = self.jsonObject(surface) {
                next.needsReview = json.digInt("counts", "needs_review")
                next.open = json.digInt("counts", "open")
                next.nextActionText = self.firstText(in: json, section: "needs_review")
                    ?? self.firstText(in: json, section: "i_made")
                    ?? self.firstText(in: json, section: "open_loops")
            }

            if let followup = try? self.kit.run(arguments: ["followup", "--waiting-on-me", "--json"]),
               let json = self.jsonObject(followup) {
                next.waitingOnMe = json.digInt("counts", "waiting_on_me")
                if next.nextActionText == nil {
                    next.nextActionText = self.firstText(in: json, section: "waiting_on_me")
                }
            }

            DispatchQueue.main.async {
                self.attentionRefreshInFlight = false
                self.attention = next
                self.applyStatusItemAppearance()
                self.renderMenu()
            }
        }
    }

    private func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func firstText(in json: [String: Any], section: String) -> String? {
        guard let sections = json["sections"] as? [String: Any],
              let items = sections[section] as? [[String: Any]],
              let first = items.first,
              let text = first["text"] as? String else {
            return nil
        }
        return text
    }

    private func summary(for label: String, data: Data) -> String {
        guard let json = jsonObject(data) else {
            return "\(label) complete"
        }

        switch label {
        case "Needs review":
            return "Needs review: \(json.digInt("counts", "needs_review") ?? 0)"
        case "Waiting on me":
            return "Waiting on me: \(json.digInt("counts", "waiting_on_me") ?? 0)"
        case "Weekly Brief":
            let waiting = json.digInt("counts", "waiting_on_me") ?? 0
            let review = json.digInt("counts", "needs_review") ?? 0
            return "Brief ready: \(waiting) waiting, \(review) review"
        default:
            return "\(label) complete"
        }
    }

    private func fileTranscriptionSummary(_ data: Data) -> String {
        guard let json = jsonObject(data) else {
            return "File transcription complete"
        }

        if let transcript = json["transcript_md"] as? String, !transcript.isEmpty {
            return "Transcript: \(truncate(transcript, limit: 80))"
        }
        return "File transcription complete"
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
                self.applyStatusItemAppearance()
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

    private func applyStatusItemAppearance() {
        guard let button = statusItem.button else { return }

        if shouldShowStatusIcon, let statusIcon {
            statusItem.length = NSStatusItem.squareLength
            button.title = ""
            button.image = statusIcon
            button.imagePosition = .imageOnly
            button.toolTip = statusToolTip()
        } else {
            statusItem.length = NSStatusItem.variableLength
            button.image = nil
            button.imagePosition = .noImage
            button.title = statusBarTitle()
            button.toolTip = statusToolTip()
        }
    }

    private var shouldShowStatusIcon: Bool {
        guard let listen = listenStatus else {
            return kitHealthOK
        }
        return kitHealthOK && !listen.isActive && listen.phase != "error"
    }

    private static func loadStatusIcon() -> NSImage? {
        let iconPath = ProcessInfo.processInfo.environment["KIT_MENUBAR_ICON"] ?? "../../assets/Kit-Logo-2424r.png"
        guard let image = NSImage(contentsOfFile: iconPath) else {
            return nil
        }

        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private func statusBarTitle() -> String {
        guard let listen = listenStatus, listen.isActive || listen.phase == "error" else {
            return kitHealthOK ? "Kit" : "Kit!"
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
            return kitHealthOK ? "Kit" : "Kit!"
        }
    }

    private func statusToolTip() -> String {
        var parts = [String]()
        if let needsReview = attention.needsReview, needsReview > 0 {
            parts.append("Needs review: \(needsReview)")
        }
        if let waitingOnMe = attention.waitingOnMe, waitingOnMe > 0 {
            parts.append("Waiting on me: \(waitingOnMe)")
        }
        if parts.isEmpty {
            return kitHealthOK ? "Kit" : "Kit error"
        }
        return parts.joined(separator: " · ")
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
            return "Listen unavailable"
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
            return friendlyListenError(listen.latestError)
        default:
            return "Device: \(ProcessInfo.processInfo.environment["KIT_LISTEN_AUDIO_DEVICE"] ?? "not set")"
        }
    }

    private func friendlyListenError(_ error: String?) -> String {
        guard let error, !error.isEmpty else {
            return "Recording failed"
        }
        if isMissingListenModelError(error) {
            return "Required audio model files are missing"
        }
        return truncate(error, limit: 72)
    }

    private func isMissingListenModelError(_ error: String) -> Bool {
        error.localizedCaseInsensitiveContains("model files are missing")
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

    private func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        let end = value.index(value.startIndex, offsetBy: max(limit - 1, 0))
        return String(value[..<end]) + "…"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
