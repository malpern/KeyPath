import AppKit
import Darwin
import Foundation
import HIDCaptureCore

private struct ControlCommand: Codable {
    let id: String
    let action: String
    let runID: String?
    let expected: String?
    let timeoutMs: UInt64?
    let settleMs: UInt64?
}

private struct ControlResponse: Codable {
    let id: String
    let ok: Bool
    let message: String
    let processID: Int32
    let snapshot: CaptureSnapshot
    let systemReadiness: SystemReadinessAssessment
}

private func monotonicNow() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
}

private final class SystemResourceMonitor {
    private var samples: [SystemResourceSample] = []
    private var lastSampleNs: UInt64 = 0
    private var previousCPUTicks: (busy: UInt64, total: UInt64)?
    private(set) var assessment = SystemReadinessAssessment.calibrating

    @discardableResult
    func sampleIfNeeded(nowNs: UInt64, force: Bool = false) -> Bool {
        guard force || lastSampleNs == 0 || nowNs - lastSampleNs >= 1_000_000_000 else {
            return false
        }
        lastSampleNs = nowNs
        samples.append(capture(nowNs: nowNs))
        if samples.count > 12 {
            samples.removeFirst(samples.count - 12)
        }
        assessment = SystemReadinessModel.resolve(samples: samples)
        return true
    }

    private func capture(nowNs: UInt64) -> SystemResourceSample {
        let processors = max(1, ProcessInfo.processInfo.activeProcessorCount)
        var averages = [Double](repeating: 0, count: 3)
        let averageCount = averages.withUnsafeMutableBufferPointer {
            getloadavg($0.baseAddress, Int32($0.count))
        }
        let oneMinuteLoad = averageCount > 0 ? averages[0] : 0
        return SystemResourceSample(
            timestampNs: nowNs,
            cpuUtilization: cpuUtilization(),
            loadAveragePerCore: max(0, oneMinuteLoad / Double(processors)),
            availableMemoryBytes: availableMemoryBytes(),
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            threadCount: integerSysctl("kern.num_taskthreads"),
            logicalProcessorCount: processors,
            memoryPressureLevel: integerSysctl("kern.memorystatus_vm_pressure_level"),
            thermalState: thermalStateName(ProcessInfo.processInfo.thermalState)
        )
    }

    private func cpuUtilization() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let busy = UInt64(info.cpu_ticks.0) + UInt64(info.cpu_ticks.1) + UInt64(info.cpu_ticks.3)
        let total = busy + UInt64(info.cpu_ticks.2)
        defer { previousCPUTicks = (busy, total) }
        guard let previousCPUTicks, total > previousCPUTicks.total else { return nil }
        let totalDelta = total - previousCPUTicks.total
        let busyDelta = busy >= previousCPUTicks.busy ? busy - previousCPUTicks.busy : 0
        return min(1, max(0, Double(busyDelta) / Double(totalDelta)))
    }

    private func availableMemoryBytes() -> UInt64 {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return 0 }
        let reclaimable = UInt64(info.free_count) + UInt64(info.inactive_count) +
            UInt64(info.speculative_count) + UInt64(info.purgeable_count)
        return reclaimable * UInt64(pageSize)
    }

    private func integerSysctl(_ name: String) -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = name.withCString {
            sysctlbyname($0, &value, &size, nil, 0)
        }
        return result == 0 ? Int(value) : 0
    }

    private func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

private final class CaptureCanvas: NSView {
    let session: CaptureSession
    var onFocusChange: ((Bool) -> Void)?
    var systemReadiness = SystemReadinessAssessment.calibrating
    private var fontCache: [String: NSFont] = [:]
    private var paragraphCache: [Int: NSParagraphStyle] = [:]
    private let brandAmber = NSColor(
        calibratedRed: 0.95, green: 0.56, blue: 0.12, alpha: 1
    )
    private let brandOrange = NSColor(
        calibratedRed: 0.86, green: 0.31, blue: 0.07, alpha: 1
    )
    private let brandLight = NSColor(
        calibratedRed: 1.0, green: 0.96, blue: 0.83, alpha: 1
    )
    private lazy var keyPathLogo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "KeyPathLogo", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    init(session: CaptureSession) {
        self.session = session
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isOpaque: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        onFocusChange?(true)
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        onFocusChange?(false)
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        session.record(
            phase: .down,
            keyCode: event.keyCode,
            characters: event.characters ?? "",
            modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue,
            isRepeat: event.isARepeat,
            nowNs: monotonicNow()
        )
        needsDisplay = true
    }

    override func keyUp(with event: NSEvent) {
        session.record(
            phase: .up,
            keyCode: event.keyCode,
            characters: "",
            modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue,
            isRepeat: false,
            nowNs: monotonicNow()
        )
        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        session.record(
            phase: .flagsChanged,
            keyCode: event.keyCode,
            characters: "",
            modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue,
            isRepeat: false,
            nowNs: monotonicNow()
        )
        needsDisplay = true
    }

    override func mouseDown(with _: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let nowNs = monotonicNow()
        let snapshot = session.snapshot(nowNs: nowNs)
        let motion = CaptureBrandMotion.resolve(
            snapshot: snapshot,
            nowNs: nowNs,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        let layout = CaptureLayoutMetrics.resolve(
            width: Double(bounds.width), height: Double(bounds.height)
        )
        let padding = CGFloat(layout.padding)
        let inset = bounds.insetBy(dx: padding, dy: padding)
        let opaqueBackground = (
            NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ??
                NSColor(calibratedWhite: 0.97, alpha: 1)
        ).withAlphaComponent(1)
        opaqueBackground.setFill()
        bounds.fill()

        let accent = systemReadiness.state == .waiting && snapshot.state == .idle
            ? brandOrange : color(for: snapshot.state)
        let headerHeight = CGFloat(layout.headerHeight)
        let header = NSRect(
            x: inset.minX, y: inset.maxY - headerHeight,
            width: inset.width, height: headerHeight
        )
        let headerPath = NSBezierPath(
            roundedRect: header,
            xRadius: layout.mode == .tiny ? 10 : 14,
            yRadius: layout.mode == .tiny ? 10 : 14
        )
        brandAmber.withAlphaComponent(0.08 + motion.breath * 0.025).setFill()
        headerPath.fill()
        brandAmber.withAlphaComponent(0.22).setStroke()
        headerPath.lineWidth = 1
        headerPath.stroke()

        let markSize: CGFloat = layout.mode == .tiny ? 22 : 34
        let markFrame = NSRect(
            x: header.minX + (layout.mode == .tiny ? 8 : 14),
            y: header.midY - markSize / 2,
            width: markSize,
            height: markSize
        )
        drawKeyPathLogo(in: markFrame)

        let focusWidth: CGFloat = layout.mode == .tiny ? 72 : 130
        let titleX = markFrame.maxX + (layout.mode == .tiny ? 6 : 10)
        drawText(
            layout.mode == .tiny ? "KEYPATH HID JIG" : "KEYPATH  /  HID CAPTURE JIG",
            rect: NSRect(
                x: titleX,
                y: header.midY - 10,
                width: max(40, header.maxX - focusWidth - titleX - 14), height: 22
            ),
            font: font(
                size: layout.mode == .tiny ? 10 : 14, weight: .semibold,
                monospaced: true
            ),
            color: accent
        )
        drawText(
            snapshot.focused ? (layout.mode == .tiny ? "FOCUS" : "FOCUSED") : "NO FOCUS",
            rect: NSRect(
                x: header.maxX - focusWidth - (layout.mode == .tiny ? 10 : 18),
                y: header.midY - 10, width: focusWidth, height: 22
            ),
            font: font(
                size: layout.mode == .tiny ? 9 : 12, weight: .bold,
                monospaced: true
            ),
            color: snapshot.focused ? NSColor.systemGreen : NSColor.systemRed,
            alignment: .right
        )
        drawActivityRail(in: header, motion: motion, stateAccent: accent)

        var cursor = header.minY - (layout.mode == .tiny ? 5 : 12)
        let stateHeight: CGFloat = layout.mode == .tiny ? 28 : 48
        let visibleState: String = if snapshot.state == .idle, systemReadiness.state == .waiting {
            layout.mode == .tiny ? "MAC BUSY" : "PAUSED · MAC BUSY"
        } else if snapshot.state == .idle, systemReadiness.state == .calibrating {
            layout.mode == .tiny ? "CHECKING" : "CHECKING THE MAC"
        } else {
            snapshot.state.rawValue.uppercased()
        }
        drawText(
            visibleState,
            rect: NSRect(
                x: inset.minX, y: cursor - stateHeight,
                width: inset.width, height: stateHeight
            ),
            font: font(size: CGFloat(layout.stateFontSize), weight: .bold),
            color: accent
        )
        cursor -= stateHeight
        let runHeight: CGFloat = layout.mode == .tiny ? 14 : 22
        let runSummary = snapshot.runID.isEmpty ? systemReadiness.summary : snapshot.runID
        drawText(
            runSummary,
            rect: NSRect(x: inset.minX, y: cursor - runHeight, width: inset.width, height: runHeight),
            font: font(
                size: layout.mode == .tiny ? 9 : 14, weight: .regular,
                monospaced: true
            ),
            color: NSColor.secondaryLabelColor
        )
        cursor -= runHeight + (layout.mode == .tiny ? 4 : 10)

        let labelHeight: CGFloat = layout.mode == .tiny ? 11 : 16
        let fieldHeight = CGFloat(layout.fieldHeight)
        let fieldBlockHeight = labelHeight + fieldHeight + (layout.mode == .tiny ? 4 : 8)
        drawField(
            label: "EXPECTED", value: snapshot.expected,
            frame: NSRect(
                x: inset.minX, y: cursor - labelHeight - fieldHeight,
                width: inset.width, height: fieldHeight
            ),
            labelHeight: labelHeight, compact: layout.mode != .regular
        )
        cursor -= fieldBlockHeight
        drawField(
            label: "RECEIVED", value: snapshot.received,
            frame: NSRect(
                x: inset.minX, y: cursor - labelHeight - fieldHeight,
                width: inset.width, height: fieldHeight
            ),
            labelHeight: labelHeight, compact: layout.mode != .regular,
            valueColor: snapshot.received == snapshot.expected && !snapshot.received.isEmpty
                ? NSColor.systemGreen : NSColor.labelColor
        )
        cursor -= fieldBlockHeight

        let issueText: String = if !snapshot.issues.isEmpty {
            snapshot.issues.joined(separator: "  •  ")
        } else if snapshot.state == .idle, systemReadiness.state != .ready {
            ([systemReadiness.detail] + systemReadiness.suggestions).joined(separator: "  •  ")
        } else if snapshot.state == .idle {
            "System resources are stable · ready to arm"
        } else {
            "No anomalies detected"
        }
        let resourceBlocked = snapshot.state == .idle && systemReadiness.state == .waiting
        let issueHeight: CGFloat = resourceBlocked
            ? (layout.mode == .regular ? 68 : (layout.mode == .compact ? 58 : 24))
            : (layout.mode == .tiny ? 18 : 28)
        let issueFrame = NSRect(
            x: inset.minX, y: cursor - issueHeight, width: inset.width, height: issueHeight
        )
        if resourceBlocked, layout.mode != .tiny {
            let why = systemReadiness.issues.prefix(2).joined(separator: " · ")
            let help = systemReadiness.suggestions.first ?? "Wait; the Jig will recheck automatically."
            drawWrappedText(
                "WHY  \(why)\nHELP  \(help)",
                rect: issueFrame,
                font: font(size: layout.mode == .regular ? 13 : 11, weight: .medium),
                color: brandOrange
            )
        } else {
            drawText(
                issueText,
                rect: issueFrame,
                font: font(size: layout.mode == .tiny ? 9 : 13, weight: .medium),
                color: !snapshot.issues.isEmpty ? NSColor.systemRed : NSColor.secondaryLabelColor
            )
        }
        cursor -= issueHeight + (layout.mode == .regular ? 12 : 6)

        let footerClearance: CGFloat = layout.showsFooter ? 28 : 0
        let burstFrame = NSRect(
            x: inset.minX,
            y: inset.minY + footerClearance,
            width: inset.width,
            height: max(54, cursor - inset.minY - footerClearance)
        )
        drawKeycapBurst(
            snapshot: snapshot,
            nowNs: nowNs,
            frame: burstFrame,
            mode: layout.mode,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )

        if layout.showsFooter {
            drawText(
                "Click this window to restore focus. Tests fail closed if focus moves elsewhere.",
                rect: NSRect(x: inset.minX, y: inset.minY, width: inset.width, height: 20),
                font: font(
                    size: layout.mode == .regular ? 12 : 10, weight: .regular
                ),
                color: NSColor.tertiaryLabelColor
            )
        }
    }

    private func drawField(
        label: String, value: String, frame: NSRect, labelHeight: CGFloat,
        compact: Bool, valueColor: NSColor = .labelColor
    ) {
        drawText(
            label,
            rect: NSRect(
                x: frame.minX, y: frame.maxY + 1,
                width: frame.width, height: labelHeight
            ),
            font: font(size: compact ? 9 : 11, weight: .semibold, monospaced: true),
            color: NSColor.tertiaryLabelColor
        )
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(
            roundedRect: frame, xRadius: compact ? 6 : 8, yRadius: compact ? 6 : 8
        ).fill()
        drawText(
            value.isEmpty ? "—" : value.debugDescription,
            rect: NSRect(
                x: frame.minX + (compact ? 8 : 12), y: frame.minY + (compact ? 5 : 8),
                width: frame.width - (compact ? 16 : 24), height: frame.height - 8
            ),
            font: font(size: compact ? 11 : 15, weight: .medium, monospaced: true),
            color: valueColor
        )
    }

    private func drawKeycapBurst(
        snapshot: CaptureSnapshot,
        nowNs: UInt64,
        frame: NSRect,
        mode: CaptureLayoutMode,
        reduceMotion: Bool
    ) {
        let output = KeycapBurstModel.resolve(
            events: snapshot.events,
            pressedKeyCodes: snapshot.pressedKeyCodes,
            nowNs: nowNs,
            reduceMotion: reduceMotion
        )
        let panel = NSBezierPath(
            roundedRect: frame,
            xRadius: mode == .tiny ? 10 : 16,
            yRadius: mode == .tiny ? 10 : 16
        )
        NSColor.controlBackgroundColor.withAlphaComponent(0.62).setFill()
        panel.fill()
        brandAmber.withAlphaComponent(0.12 + 0.13 * output.intensity).setStroke()
        panel.lineWidth = 1
        panel.stroke()

        let titleHeight: CGFloat = mode == .tiny ? 14 : 20
        let titleInset: CGFloat = mode == .tiny ? 9 : 14
        drawText(
            mode == .tiny ? "LIVE KEYS" : "LIVE KEYCAP STACK",
            rect: NSRect(
                x: frame.minX + titleInset,
                y: frame.maxY - titleHeight - (mode == .tiny ? 5 : 9),
                width: frame.width * 0.5,
                height: titleHeight
            ),
            font: font(size: mode == .tiny ? 8 : 11, weight: .semibold, monospaced: true),
            color: NSColor.tertiaryLabelColor
        )
        let evidence = if output.totalPresses == 0 {
            "WAITING FOR KEY-DOWN"
        } else if output.presentedPresses < output.totalPresses {
            "PLAYING \(output.presentedPresses)/\(output.totalPresses)  ·  BURST \(output.recentPresses)"
        } else if output.recentPresses > 0 {
            "\(output.recentPresses) NOW  ·  \(output.totalPresses) TOTAL"
        } else {
            "\(output.totalPresses) PRESSES CAPTURED"
        }
        drawText(
            evidence,
            rect: NSRect(
                x: frame.midX,
                y: frame.maxY - titleHeight - (mode == .tiny ? 5 : 9),
                width: frame.width * 0.5 - titleInset,
                height: titleHeight
            ),
            font: font(size: mode == .tiny ? 8 : 10, weight: .medium, monospaced: true),
            color: output.recentPresses > 0 ? brandOrange : NSColor.tertiaryLabelColor,
            alignment: .right
        )

        let stageTop = frame.maxY - titleHeight - (mode == .tiny ? 8 : 16)
        let stage = NSRect(
            x: frame.minX + titleInset,
            y: frame.minY + (mode == .tiny ? 5 : 10),
            width: frame.width - titleInset * 2,
            height: max(28, stageTop - frame.minY - (mode == .tiny ? 7 : 12))
        )

        guard !output.items.isEmpty else {
            drawEmptyKeycapStack(in: stage, mode: mode)
            return
        }

        let maxWidth = mode == .regular ? 118.0 : (mode == .compact ? 96.0 : 66.0)
        let capWidth = min(CGFloat(maxWidth), stage.width * (mode == .tiny ? 0.28 : 0.30))
        let capHeight = min(
            capWidth * 0.68,
            stage.height * (mode == .tiny ? 0.72 : 0.62)
        )
        let center = NSPoint(x: stage.midX, y: stage.midY - capHeight * 0.08)
        for item in output.items {
            drawKeycap(item, center: center, size: NSSize(width: capWidth, height: capHeight))
        }
    }

    private func drawEmptyKeycapStack(in frame: NSRect, mode: CaptureLayoutMode) {
        let capWidth = min(mode == .tiny ? 54 : 82, frame.width * 0.28)
        let capHeight = capWidth * 0.64
        for index in 0 ..< 3 {
            let cap = NSRect(
                x: frame.midX - capWidth / 2 + CGFloat(index - 1) * 3,
                y: frame.midY - capHeight / 2 + CGFloat(index) * 3,
                width: capWidth,
                height: capHeight
            )
            let path = NSBezierPath(roundedRect: cap, xRadius: 11, yRadius: 11)
            brandAmber.withAlphaComponent(0.08 + CGFloat(index) * 0.035).setFill()
            path.fill()
            brandAmber.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        if mode != .tiny {
            drawText(
                "physical input appears here",
                rect: NSRect(
                    x: frame.minX,
                    y: max(frame.minY, frame.midY - capHeight / 2 - 28),
                    width: frame.width,
                    height: 18
                ),
                font: font(size: 11, weight: .regular, monospaced: true),
                color: NSColor.tertiaryLabelColor,
                alignment: .center
            )
        }
    }

    private func drawKeycap(_ item: KeycapBurstItem, center: NSPoint, size: NSSize) {
        let width = size.width * CGFloat(item.scale)
        let height = size.height * CGFloat(item.scale)
        let x = center.x - width / 2 + CGFloat(item.xOffset)
        let y = center.y - height / 2 + CGFloat(item.yOffset)
        let opacity = CGFloat(item.opacity)
        let baseDepth = max(4, height * 0.12)
        let radius = max(8, width * 0.13)

        let base = NSRect(x: x, y: y, width: width, height: height)
        let basePath = NSBezierPath(roundedRect: base, xRadius: radius, yRadius: radius)
        (item.isRepeat ? NSColor.systemRed : brandOrange).withAlphaComponent(opacity * 0.88).setFill()
        basePath.fill()

        let compression = CGFloat(item.pressDepth) * baseDepth * 0.76
        let face = NSRect(
            x: x + width * 0.045,
            y: y + baseDepth - compression,
            width: width * 0.91,
            height: height - baseDepth - height * 0.055 + compression * 0.24
        )
        let facePath = NSBezierPath(
            roundedRect: face,
            xRadius: max(7, radius * 0.76),
            yRadius: max(7, radius * 0.76)
        )
        let pressedGlow = item.isPressed || item.pressDepth > 0.15
        let faceColor = pressedGlow
            ? brandLight.blended(withFraction: 0.16, of: brandAmber) ?? brandLight
            : brandLight
        faceColor.withAlphaComponent(opacity).setFill()
        facePath.fill()
        brandAmber.withAlphaComponent(opacity * (pressedGlow ? 0.95 : 0.60)).setStroke()
        facePath.lineWidth = pressedGlow ? 2 : 1
        facePath.stroke()

        let fontSize = min(width * (item.label.count > 2 ? 0.16 : 0.30), height * 0.38)
        drawText(
            item.label,
            rect: NSRect(
                x: face.minX + 4,
                y: face.midY - fontSize * 0.63,
                width: face.width - 8,
                height: fontSize * 1.35
            ),
            font: font(size: max(8, fontSize), weight: .bold, monospaced: true),
            color: NSColor(calibratedWhite: 0.14, alpha: opacity),
            alignment: .center
        )
    }

    private func drawText(
        _ text: String,
        rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph: NSParagraphStyle
        if let cached = paragraphCache[alignment.rawValue] {
            paragraph = cached
        } else {
            let value = NSMutableParagraphStyle()
            value.alignment = alignment
            value.lineBreakMode = .byTruncatingTail
            paragraph = value.copy() as! NSParagraphStyle
            paragraphCache[alignment.rawValue] = paragraph
        }
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
    }

    private func drawWrappedText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
        )
    }

    private func font(
        size: CGFloat, weight: NSFont.Weight, monospaced: Bool = false
    ) -> NSFont {
        let key = "\(monospaced ? "mono" : "system"):\(size):\(weight.rawValue)"
        if let cached = fontCache[key] {
            return cached
        }
        let value = monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        fontCache[key] = value
        return value
    }

    private func color(for state: CaptureRunState) -> NSColor {
        switch state {
        case .idle: brandAmber
        case .armed: brandOrange
        case .capturing: brandAmber
        case .passed: NSColor.systemGreen
        case .failed: NSColor.systemRed
        }
    }

    private func drawKeyPathLogo(in frame: NSRect) {
        guard let keyPathLogo else {
            drawText(
                "KP",
                rect: frame,
                font: font(size: frame.height * 0.42, weight: .bold, monospaced: true),
                color: brandAmber,
                alignment: .center
            )
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .high
        keyPathLogo.draw(
            in: frame,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawActivityRail(
        in header: NSRect,
        motion: CaptureBrandMotion,
        stateAccent: NSColor
    ) {
        let rail = NSRect(x: header.minX + 12, y: header.minY + 3, width: header.width - 24, height: 2)
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        NSBezierPath(roundedRect: rail, xRadius: 1, yRadius: 1).fill()

        if motion.completion > 0 {
            let fill = NSRect(
                x: rail.minX, y: rail.minY,
                width: max(2, rail.width * CGFloat(motion.completion)), height: rail.height
            )
            stateAccent.withAlphaComponent(0.72).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 1, yRadius: 1).fill()
        }

        let travel = rail.minX + rail.width * CGFloat(motion.glintPosition)
        drawGlint(
            center: NSPoint(x: travel, y: rail.midY),
            size: 5 + CGFloat(motion.eventPulse * 4),
            color: brandLight.withAlphaComponent(0.55 + motion.eventPulse * 0.4)
        )
    }

    private func drawGlint(center: NSPoint, size: CGFloat, color: NSColor) {
        let half = size / 2
        let waist = max(0.6, size * 0.12)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x, y: center.y + half))
        path.line(to: NSPoint(x: center.x + waist, y: center.y + waist))
        path.line(to: NSPoint(x: center.x + half, y: center.y))
        path.line(to: NSPoint(x: center.x + waist, y: center.y - waist))
        path.line(to: NSPoint(x: center.x, y: center.y - half))
        path.line(to: NSPoint(x: center.x - waist, y: center.y - waist))
        path.line(to: NSPoint(x: center.x - half, y: center.y))
        path.line(to: NSPoint(x: center.x - waist, y: center.y + waist))
        path.close()
        color.setFill()
        path.fill()
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let session = CaptureSession()
    private let resourceMonitor = SystemResourceMonitor()
    private var window: NSWindow!
    private var canvas: CaptureCanvas!
    private var timer: Timer?
    private var lastCommandID = ""
    private var persistedTerminalKey = ""
    private var runActive = false
    private var lastRenderedState: CaptureRunState?
    private var ambientFrame = 0
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private lazy var stateDirectory: URL = {
        if let override = ProcessInfo.processInfo.environment["KEYPATH_CAPTURE_JIG_STATE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state/keypath-hid-capture-jig", isDirectory: true)
    }()

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildWindow()
        resourceMonitor.sampleIfNeeded(nowNs: monotonicNow(), force: true)
        canvas.systemReadiness = resourceMonitor.assessment
        prepareStateDirectory()
        writeReadyFile()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(canvas)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func windowDidBecomeKey(_: Notification) {
        window.makeFirstResponder(canvas)
        session.noteFocus(true, nowNs: monotonicNow())
        canvas.needsDisplay = true
    }

    func windowDidResignKey(_: Notification) {
        session.noteFocus(false, nowNs: monotonicNow())
        canvas.needsDisplay = true
    }

    private func buildWindow() {
        canvas = CaptureCanvas(session: session)
        canvas.onFocusChange = { [weak self] focused in
            self?.session.noteFocus(focused, nowNs: monotonicNow())
        }
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "KeyPath HID Capture Jig"
        window.minSize = NSSize(width: 380, height: 280)
        let frameAutosaveName = "KeyPathHIDCaptureJigWindow"
        if !window.setFrameUsingName(frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(frameAutosaveName)
        window.delegate = self
        window.contentView = canvas
    }

    private func prepareStateDirectory() {
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stateDirectory.path)
        let artifacts = stateDirectory.appendingPathComponent("artifacts", isDirectory: true)
        try? FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    }

    private func writeReadyFile() {
        let value: [String: Any] = [
            "schemaVersion": 1,
            "processID": ProcessInfo.processInfo.processIdentifier,
            "status": "ready",
            "stateDirectory": stateDirectory.path,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else { return }
        writeAtomically(data, to: stateDirectory.appendingPathComponent("ready.json"))
    }

    private func tick() {
        processCommandIfNeeded()
        let nowNs = monotonicNow()
        if resourceMonitor.sampleIfNeeded(nowNs: nowNs) {
            canvas.systemReadiness = resourceMonitor.assessment
            canvas.needsDisplay = true
        }
        let snapshot = session.snapshot(nowNs: nowNs)
        let burstAnimating = KeycapBurstModel.resolve(
            events: snapshot.events,
            pressedKeyCodes: snapshot.pressedKeyCodes,
            nowNs: nowNs,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ).isAnimating
        if !runActive {
            ambientFrame = (ambientFrame + 1) % 2
            if burstAnimating ||
                (!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && ambientFrame == 0)
            {
                canvas.needsDisplay = true
            }
            lastRenderedState = snapshot.state
            return
        }
        if snapshot.state == .armed, !snapshot.focused {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.makeFirstResponder(canvas)
        }
        if snapshot.state == .armed || snapshot.state == .capturing ||
            snapshot.state != lastRenderedState
        {
            canvas.needsDisplay = true
        }
        lastRenderedState = snapshot.state
        persistTerminalResultIfNeeded(snapshot)
        if snapshot.state == .passed || snapshot.state == .failed {
            runActive = false
        }
    }

    private func processCommandIfNeeded() {
        let commandURL = stateDirectory.appendingPathComponent("command.json")
        guard let data = try? Data(contentsOf: commandURL),
              let command = try? JSONDecoder().decode(ControlCommand.self, from: data),
              command.id != lastCommandID
        else { return }
        lastCommandID = command.id
        if command.action == "arm" {
            beginArm(command, attempt: 0)
            return
        }
        if command.action == "focus" {
            beginFocus(command, attempt: 0)
            return
        }
        let response = handle(command)
        write(response)
    }

    private func beginFocus(_ command: ControlCommand, attempt: Int) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(canvas)
        let focused = window.isKeyWindow && window.firstResponder === canvas
        if !focused, attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.beginFocus(command, attempt: attempt + 1)
            }
            return
        }
        write(ControlResponse(
            id: command.id,
            ok: focused,
            message: focused ? "capture jig focused" : "capture jig could not acquire keyboard focus",
            processID: ProcessInfo.processInfo.processIdentifier,
            snapshot: session.snapshot(nowNs: monotonicNow()),
            systemReadiness: resourceMonitor.assessment
        ))
    }

    private func beginArm(_ command: ControlCommand, attempt: Int) {
        let readiness = resourceMonitor.assessment
        guard readiness.canProceed else {
            runActive = false
            canvas.systemReadiness = readiness
            canvas.needsDisplay = true
            let guidance = readiness.suggestions.first.map { " \($0)" } ?? ""
            write(ControlResponse(
                id: command.id,
                ok: false,
                message: "capture paused: \(readiness.detail)\(guidance)",
                processID: ProcessInfo.processInfo.processIdentifier,
                snapshot: session.snapshot(nowNs: monotonicNow()),
                systemReadiness: readiness
            ))
            return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(canvas)
        let focused = window.isKeyWindow && window.firstResponder === canvas
        if !focused, attempt < 10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.beginArm(command, attempt: attempt + 1)
            }
            return
        }
        let ok = session.arm(
            runID: command.runID ?? "",
            expected: command.expected ?? "",
            timeoutMs: command.timeoutMs ?? 10000,
            settleMs: command.settleMs ?? 250,
            focused: focused,
            nowNs: monotonicNow()
        )
        persistedTerminalKey = ""
        runActive = ok
        lastRenderedState = nil
        canvas.needsDisplay = true
        write(ControlResponse(
            id: command.id,
            ok: ok,
            message: ok ? "capture armed and focused" : "capture refused: focus or command bounds invalid",
            processID: ProcessInfo.processInfo.processIdentifier,
            snapshot: session.snapshot(nowNs: monotonicNow()),
            systemReadiness: readiness
        ))
    }

    private func write(_ response: ControlResponse) {
        guard let encoded = try? encoder.encode(response) else { return }
        writeAtomically(encoded, to: stateDirectory.appendingPathComponent("response.json"))
    }

    private func handle(_ command: ControlCommand) -> ControlResponse {
        var ok = true
        var message = "status captured"
        switch command.action {
        case "status":
            break
        case "reset":
            session.reset()
            persistedTerminalKey = ""
            runActive = false
            lastRenderedState = nil
            message = "capture session reset"
        case "finalize":
            session.finalize(nowNs: monotonicNow())
            message = "capture finalized"
        case "quit":
            message = "capture jig quitting"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { NSApp.terminate(nil) }
        default:
            ok = false
            message = "unknown action: \(command.action)"
        }
        canvas.needsDisplay = true
        let snapshot = session.snapshot(nowNs: monotonicNow())
        return ControlResponse(
            id: command.id,
            ok: ok,
            message: message,
            processID: ProcessInfo.processInfo.processIdentifier,
            snapshot: snapshot,
            systemReadiness: resourceMonitor.assessment
        )
    }

    private func persistTerminalResultIfNeeded(_ snapshot: CaptureSnapshot) {
        guard snapshot.state == .passed || snapshot.state == .failed, !snapshot.runID.isEmpty else { return }
        let key = "\(snapshot.runID):\(snapshot.state.rawValue):\(snapshot.events.count)"
        guard key != persistedTerminalKey, let data = try? encoder.encode(snapshot) else { return }
        persistedTerminalKey = key
        let safeRunID = snapshot.runID.map { $0.isLetter || $0.isNumber || "-_.".contains($0) ? $0 : "_" }
        let filename = "\(String(safeRunID))-\(snapshot.state.rawValue).json"
        writeAtomically(data, to: stateDirectory.appendingPathComponent("artifacts/\(filename)"))
    }

    private func writeAtomically(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("HID Capture Jig could not write %@: %@", url.path, error.localizedDescription)
        }
    }
}

@main
private enum HIDCaptureJigMain {
    static func main() {
        let application = NSApplication.shared
        installMainMenu(on: application)
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }

    private static func installMainMenu(on application: NSApplication) {
        let applicationName = "KeyPath HID Capture Jig"
        let mainMenu = NSMenu()
        let applicationMenuItem = NSMenuItem()
        let applicationMenu = NSMenu(title: applicationName)

        applicationMenu.addItem(
            withTitle: "About \(applicationName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())

        let servicesMenu = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = servicesMenu
        applicationMenu.addItem(servicesItem)
        application.servicesMenu = servicesMenu

        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "Hide \(applicationName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )

        let hideOthersItem = applicationMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )

        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "Quit \(applicationName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)
        application.mainMenu = mainMenu
    }
}
