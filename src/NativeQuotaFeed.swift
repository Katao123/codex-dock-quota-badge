import AppKit
import Foundation

private let appName = "Codex Dock Quota Feed"
private let environment = ProcessInfo.processInfo.environment
private let formalAppPath = environment["CODEX_DOCK_BADGE_APP"] ?? "/Applications/ChatGPT.app"
private let outputPath = environment["CODEX_DOCK_BADGE_OUTPUT"] ?? "/tmp/codex-quota.png"
private let statusPath = environment["CODEX_DOCK_BADGE_STATUS"] ?? "/tmp/codex-quota-percent.txt"
private let stylePath = environment["CODEX_DOCK_BADGE_STYLE_FILE"]
    ?? "\(NSHomeDirectory())/Library/Application Support/Codex Dock Quota Badge/style"
private let sourceIconPath = environment["CODEX_DOCK_BADGE_ICON"]
    ?? "\(formalAppPath)/Contents/Resources/icon-codex-light.png"

private enum QuotaStyle: String {
    case numeric
    case ring
}

private func log(_ message: String) {
    let formatter = ISO8601DateFormatter()
    print("[\(formatter.string(from: Date()))] \(message)")
    fflush(stdout)
}

private func selectedStyle() -> QuotaStyle {
    if let override = environment["CODEX_DOCK_BADGE_STYLE"],
       let style = QuotaStyle(rawValue: override.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return style
    }
    guard let configured = try? String(contentsOfFile: stylePath, encoding: .utf8),
          let style = QuotaStyle(rawValue: configured.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return .numeric
    }
    return style
}

private var cachedRingContour: [NSPoint]?

private func fallbackRingRadius(angle: CGFloat) -> CGFloat {
    let exponent: CGFloat = 4.15
    let cosine = abs(cos(angle))
    let sine = abs(sin(angle))
    let denominator = pow(pow(cosine, exponent) + pow(sine, exponent), 1 / exponent)
    return 408 / max(denominator, 0.001)
}

private func isGlassSurface(_ color: NSColor?) -> Bool {
    guard let rgb = color?.usingColorSpace(.deviceRGB), rgb.alphaComponent >= 0.88 else { return false }
    let luminance = (0.2126 * rgb.redComponent) + (0.7152 * rgb.greenComponent) + (0.0722 * rgb.blueComponent)
    return luminance >= 0.84
}

private func sampledRingContour() -> [NSPoint] {
    if let cachedRingContour { return cachedRingContour }

    let center = NSPoint(x: 512, y: 512)
    let sampleCount = 720
    let bitmap = (try? Data(contentsOf: URL(fileURLWithPath: sourceIconPath)))
        .flatMap(NSBitmapImageRep.init(data:))
    let pixelScaleX = CGFloat(bitmap?.pixelsWide ?? 1024) / 1024
    let pixelScaleY = CGFloat(bitmap?.pixelsHigh ?? 1024) / 1024
    var radii: [CGFloat] = []
    radii.reserveCapacity(sampleCount)

    for index in 0..<sampleCount {
        let progress = CGFloat(index) / CGFloat(sampleCount)
        let angle = CGFloat.pi - (2 * CGFloat.pi * progress)
        var detectedRadius: CGFloat?
        if let bitmap {
            var consecutiveSurfacePixels = 0
            for radius in stride(from: CGFloat(500), through: CGFloat(300), by: -1) {
                let x = Int((center.x + radius * cos(angle)) * pixelScaleX)
                let y = Int((center.y + radius * sin(angle)) * pixelScaleY)
                guard x >= 0, y >= 0, x < bitmap.pixelsWide, y < bitmap.pixelsHigh else { continue }
                if isGlassSurface(bitmap.colorAt(x: x, y: y)) {
                    consecutiveSurfacePixels += 1
                    if consecutiveSurfacePixels == 6 {
                        detectedRadius = radius + 5
                        break
                    }
                } else {
                    consecutiveSurfacePixels = 0
                }
            }
        }
        radii.append(detectedRadius ?? fallbackRingRadius(angle: angle))
    }

    let smoothingRadius = 5
    let smoothed = radii.indices.map { index -> CGFloat in
        var sum: CGFloat = 0
        for offset in -smoothingRadius...smoothingRadius {
            let wrapped = (index + offset + sampleCount) % sampleCount
            sum += radii[wrapped]
        }
        return sum / CGFloat((smoothingRadius * 2) + 1)
    }

    // Keep the full treatment inside the sampled glass edge. The wider inset
    // prevents the quota color from merging into the icon's outer shadow at
    // real Dock sizes.
    let strokeInset: CGFloat = 18
    let contour = smoothed.indices.map { index -> NSPoint in
        let progress = CGFloat(index) / CGFloat(sampleCount)
        let angle = CGFloat.pi - (2 * CGFloat.pi * progress)
        let radius = smoothed[index] - strokeInset
        return NSPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
    cachedRingContour = contour
    return contour
}

private func quotaRingPath(progress: CGFloat) -> NSBezierPath {
    let contour = sampledRingContour()
    let boundedProgress = min(1, max(0, progress))
    let exactEnd = boundedProgress * CGFloat(contour.count)
    let fullSegments = min(contour.count, Int(floor(exactEnd)))
    let path = NSBezierPath()
    guard boundedProgress > 0, let first = contour.first else { return path }
    path.move(to: first)

    func controls(for startIndex: Int) -> (start: NSPoint, first: NSPoint, second: NSPoint, end: NSPoint) {
        let count = contour.count
        let previous = contour[(startIndex - 1 + count) % count]
        let start = contour[startIndex % count]
        let end = contour[(startIndex + 1) % count]
        let following = contour[(startIndex + 2) % count]
        let firstControl = NSPoint(
            x: start.x + ((end.x - previous.x) / 6),
            y: start.y + ((end.y - previous.y) / 6)
        )
        let secondControl = NSPoint(
            x: end.x - ((following.x - start.x) / 6),
            y: end.y - ((following.y - start.y) / 6)
        )
        return (start, firstControl, secondControl, end)
    }

    for segment in 0..<fullSegments {
        let curve = controls(for: segment)
        path.curve(to: curve.end, controlPoint1: curve.first, controlPoint2: curve.second)
    }

    let fraction = exactEnd - floor(exactEnd)
    if fullSegments < contour.count, fraction > 0 {
        let curve = controls(for: fullSegments)
        let a = NSPoint(
            x: curve.start.x + ((curve.first.x - curve.start.x) * fraction),
            y: curve.start.y + ((curve.first.y - curve.start.y) * fraction)
        )
        let b = NSPoint(
            x: curve.first.x + ((curve.second.x - curve.first.x) * fraction),
            y: curve.first.y + ((curve.second.y - curve.first.y) * fraction)
        )
        let c = NSPoint(
            x: curve.second.x + ((curve.end.x - curve.second.x) * fraction),
            y: curve.second.y + ((curve.end.y - curve.second.y) * fraction)
        )
        let d = NSPoint(x: a.x + ((b.x - a.x) * fraction), y: a.y + ((b.y - a.y) * fraction))
        let e = NSPoint(x: b.x + ((c.x - b.x) * fraction), y: b.y + ((c.y - b.y) * fraction))
        let endpoint = NSPoint(x: d.x + ((e.x - d.x) * fraction), y: d.y + ((e.y - d.y) * fraction))
        path.curve(to: endpoint, controlPoint1: a, controlPoint2: d)
    }
    return path
}

private func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
    path.lineCapStyle = .round
    color.setStroke()
    path.lineWidth = width
    path.stroke()
}

private func drawGlassTrackRing(_ path: NSBezierPath, color: NSColor) {
    let fullTrack = quotaRingPath(progress: 1)
    stroke(fullTrack, color: NSColor.black.withAlphaComponent(0.10), width: 28)
    stroke(fullTrack, color: NSColor.white.withAlphaComponent(0.34), width: 14)

    NSGraphicsContext.current?.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color.withAlphaComponent(0.30)
    glow.shadowBlurRadius = 12
    glow.shadowOffset = .zero
    glow.set()
    stroke(path, color: color.withAlphaComponent(0.26), width: 28)
    NSGraphicsContext.current?.restoreGraphicsState()

    stroke(path, color: color.withAlphaComponent(0.94), width: 20)

    let endpoint = path.currentPoint
    let halo = NSBezierPath(ovalIn: NSRect(x: endpoint.x - 16, y: endpoint.y - 16, width: 32, height: 32))
    color.withAlphaComponent(0.18).setFill()
    halo.fill()

    let bead = NSBezierPath(ovalIn: NSRect(x: endpoint.x - 10, y: endpoint.y - 10, width: 20, height: 20))
    color.withAlphaComponent(0.96).setFill()
    bead.fill()

    let glint = NSBezierPath(ovalIn: NSRect(x: endpoint.x - 4, y: endpoint.y + 2, width: 4, height: 4))
    NSColor.white.withAlphaComponent(0.58).setFill()
    glint.fill()
}

private func drawQuotaRing(value: Int) {
    let progress = CGFloat(value) / 100
    let ring = quotaRingPath(progress: progress)
    let activeColor: NSColor
    switch value {
    case ..<20:
        activeColor = NSColor(calibratedRed: 1.00, green: 0.12, blue: 0.10, alpha: 0.92)
    case 20..<50:
        activeColor = NSColor(calibratedRed: 1.00, green: 0.66, blue: 0.06, alpha: 0.90)
    default:
        activeColor = NSColor(calibratedRed: 0.10, green: 0.78, blue: 0.38, alpha: 0.88)
    }
    drawGlassTrackRing(ring, color: activeColor)
}

private func renderComposite(
    percent: Int,
    style: QuotaStyle,
    destinationPath: String = outputPath,
    updateStatus: Bool = true
) throws {
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

    if style == .numeric {
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
    } else {
        drawQuotaRing(value: value)
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

    let outputURL = URL(fileURLWithPath: destinationPath)
    let temporaryURL = outputURL
        .deletingLastPathComponent()
        .appendingPathComponent(".codex-quota.tmp-\(UUID().uuidString)")
    try png.write(to: temporaryURL, options: .atomic)
    if FileManager.default.fileExists(atPath: outputURL.path) {
        _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: temporaryURL)
    } else {
        try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationPath)
    if updateStatus {
        try "\(value)\n".write(
            to: URL(fileURLWithPath: statusPath),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: statusPath)
    }
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
    private var lastRenderedStyle: QuotaStyle?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        let client = UsageClient { [weak self] percent in
            DispatchQueue.main.async {
                let style = selectedStyle()
                guard self?.lastRenderedPercent != percent || self?.lastRenderedStyle != style else { return }
                do {
                    try renderComposite(percent: percent, style: style)
                    self?.lastRenderedPercent = percent
                    self?.lastRenderedStyle = style
                    log("Rendered real remaining quota: \(percent)% (\(style.rawValue))")
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

if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--render-preview" {
    guard let style = QuotaStyle(rawValue: CommandLine.arguments[2]),
          let percent = Int(CommandLine.arguments[3]) else {
        fputs("Usage: CodexDockQuotaFeed --render-preview numeric|ring PERCENT OUTPUT\n", stderr)
        exit(2)
    }
    do {
        try renderComposite(
            percent: percent,
            style: style,
            destinationPath: CommandLine.arguments[4],
            updateStatus: false
        )
        exit(0)
    } catch {
        fputs("Preview failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

private let application = NSApplication.shared
private let delegate = AppDelegate()
application.setActivationPolicy(.prohibited)
application.delegate = delegate
application.run()
