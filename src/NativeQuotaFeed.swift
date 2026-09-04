import AppKit
import Foundation

private let appName = "Codex Dock Quota Feed"
private let environment = ProcessInfo.processInfo.environment
private let formalAppPath = environment["CODEX_DOCK_BADGE_APP"] ?? "/Applications/ChatGPT.app"
private let outputPath = environment["CODEX_DOCK_BADGE_OUTPUT"] ?? "/tmp/codex-quota.png"
private let statusPath = environment["CODEX_DOCK_BADGE_STATUS"] ?? "/tmp/codex-quota-percent.txt"
private let sourceIconPath = environment["CODEX_DOCK_BADGE_ICON"]
    ?? "\(formalAppPath)/Contents/Resources/icon-codex-light.png"

private func log(_ message: String) {
    let formatter = ISO8601DateFormatter()
    print("[\(formatter.string(from: Date()))] \(message)")
    fflush(stdout)
}

private func renderComposite(percent: Int) throws {
    guard let sourceIcon = NSImage(contentsOfFile: sourceIconPath) else {
        throw NSError(
            domain: appName,
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing source icon"]
        )
    }

    let value = min(100, max(0, percent))
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()

    sourceIcon.draw(
        in: NSRect(origin: .zero, size: size),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )

    let badgeRect = NSRect(x: 560, y: 690, width: 420, height: 275)
    let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 82, yRadius: 82)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = 25
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    NSColor(calibratedWhite: 0.075, alpha: 0.96).setFill()
    badgePath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.42).setStroke()
    badgePath.lineWidth = 6
    badgePath.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    ("\(value)%" as NSString).draw(
        in: NSRect(x: badgeRect.minX, y: badgeRect.minY + 93, width: badgeRect.width, height: 150),
        withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 138, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
            .kern: -2.0
        ]
    )

    let trackRect = NSRect(x: badgeRect.minX + 58, y: badgeRect.minY + 42, width: 304, height: 25)
    let track = NSBezierPath(roundedRect: trackRect, xRadius: 12.5, yRadius: 12.5)
    NSColor.white.withAlphaComponent(0.22).setFill()
    track.fill()

    let ratio = CGFloat(value) / 100
    let fillRect = NSRect(
        x: trackRect.minX,
        y: trackRect.minY,
        width: trackRect.width * ratio,
        height: trackRect.height
    )
    if fillRect.width > 0 {
        let fill = NSBezierPath(
            roundedRect: fillRect,
            xRadius: min(fillRect.height / 2, fillRect.width / 2),
            yRadius: min(fillRect.height / 2, fillRect.width / 2)
        )
        NSColor.white.withAlphaComponent(0.95).setFill()
        fill.fill()
    }

    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: appName,
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unable to encode composite icon"]
        )
    }

    let outputURL = URL(fileURLWithPath: outputPath)
    let temporaryURL = outputURL
        .deletingLastPathComponent()
        .appendingPathComponent(".codex-quota.tmp-\(UUID().uuidString)")
    try png.write(to: temporaryURL, options: .atomic)
    if FileManager.default.fileExists(atPath: outputURL.path) {
        _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: temporaryURL)
    } else {
        try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputPath)
    try "\(value)\n".write(
        to: URL(fileURLWithPath: statusPath),
        atomically: true,
        encoding: .utf8
    )
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: statusPath)
}

private final class UsageClient {
    private var process: Process?
    private var input: FileHandle?
    private var output: Pipe?
    private var buffer = Data()
    private var nextRequestID = 10
    private var pollTimer: Timer?
    private var restartTimer: Timer?
    private let onRemainingPercent: (Int) -> Void

    init(onRemainingPercent: @escaping (Int) -> Void) {
        self.onRemainingPercent = onRemainingPercent
    }

    func start() {
        launchServer()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.requestLimits()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    func stop() {
        pollTimer?.invalidate()
        restartTimer?.invalidate()
        output?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
    }

    private func launchServer() {
        guard process?.isRunning != true else { return }
        guard let executable = codexExecutable() else {
            log("Codex executable not found")
            scheduleRestart()
            return
        }

        let proc = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        proc.executableURL = executable
        proc.arguments = ["app-server"]
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = Pipe()
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.process = nil
                self?.input = nil
                self?.output?.fileHandleForReading.readabilityHandler = nil
                self?.output = nil
                self?.scheduleRestart()
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            DispatchQueue.main.async { self?.consume(data) }
        }

        do {
            try proc.run()
            process = proc
            input = stdinPipe.fileHandleForWriting
            output = stdoutPipe
            send([
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": [
                        "name": "codex_native_quota_feed",
                        "title": appName,
                        "version": "1.0.0"
                    ]
                ]
            ])
            send(["method": "initialized", "params": [:]])
            requestLimits()
            log("Connected to Codex App Server")
        } catch {
            log("Failed to launch Codex App Server: \(error.localizedDescription)")
            scheduleRestart()
        }
    }

    private func requestLimits() {
        guard process?.isRunning == true else {
            launchServer()
            return
        }
        nextRequestID += 1
        send(["method": "account/rateLimits/read", "id": nextRequestID])
    }

    private func send(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let newline = "\n".data(using: .utf8) else { return }
        do {
            try input?.write(contentsOf: data + newline)
        } catch {
            log("Failed to write request: \(error.localizedDescription)")
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
            let line = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
            buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
            guard !line.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                continue
            }
            handle(json)
        }
    }

    private func handle(_ message: [String: Any]) {
        if let result = message["result"] as? [String: Any] {
            parseRateLimits(result)
            return
        }
        if message["method"] as? String == "account/rateLimits/updated",
           let params = message["params"] as? [String: Any] {
            parseRateLimits(params)
        }
    }

    private func parseRateLimits(_ payload: [String: Any]) {
        var bucket: [String: Any]?
        if let buckets = payload["rateLimitsByLimitId"] as? [String: Any],
           let codex = buckets["codex"] as? [String: Any] {
            bucket = codex
        } else if let single = payload["rateLimits"] as? [String: Any] {
            bucket = single
        }

        guard let primary = bucket?["primary"] as? [String: Any],
              let used = number(primary["usedPercent"]) else { return }
        onRemainingPercent(min(100, max(0, Int((100 - used).rounded()))))
    }

    private func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    private func scheduleRestart() {
        guard restartTimer == nil else { return }
        restartTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.restartTimer = nil
            self?.launchServer()
        }
    }

    private func codexExecutable() -> URL? {
        let candidates = [
            "\(formalAppPath)/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var usageClient: UsageClient?
    private var lastRenderedPercent: Int?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        let client = UsageClient { [weak self] percent in
            DispatchQueue.main.async {
                guard self?.lastRenderedPercent != percent else { return }
                do {
                    try renderComposite(percent: percent)
                    self?.lastRenderedPercent = percent
                    log("Rendered real remaining quota: \(percent)%")
                } catch {
                    log("Render failed: \(error.localizedDescription)")
                }
            }
        }
        usageClient = client
        client.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageClient?.stop()
    }
}

private let application = NSApplication.shared
private let delegate = AppDelegate()
application.setActivationPolicy(.prohibited)
application.delegate = delegate
application.run()
