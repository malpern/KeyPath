#!/usr/bin/env swift
/// Quick validation script for drag-to-authorize.
/// Run this, then manually drag from the floating panel into System Settings.
///
/// Usage:
///   1. swift dev-tools/test-drag-to-settings.swift
///   2. System Settings > Privacy > Accessibility opens automatically
///   3. A small floating window appears — drag the icon into the Settings list
///   4. Check the console output for success/failure
///
/// Tests both .app bundle and bare executable to determine what Settings accepts.

import AppKit

class DragTestView: NSView, NSDraggingSource {
    let fileURL: URL
    let label: String

    init(fileURL: URL, label: String, frame: NSRect) {
        self.fileURL = fileURL
        self.label = label
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 8
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)

        let dragItem = NSDraggingItem(pasteboardWriter: item)
        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        icon.size = NSSize(width: 32, height: 32)
        dragItem.setDraggingFrame(bounds, contents: icon)

        print("[\(label)] Starting drag for: \(fileURL.path)")
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] {
            print("✅ [\(label)] DROP ACCEPTED — operation: \(operation.rawValue)")
        } else {
            print("❌ [\(label)] Drop rejected or cancelled")
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        icon.draw(in: NSRect(x: 8, y: (bounds.height - 24) / 2, width: 24, height: 24))

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor
        ]
        (label as NSString).draw(at: NSPoint(x: 38, y: (bounds.height - 14) / 2), withAttributes: attrs)
    }
}

// --- Main ---

let app = NSApplication.shared
app.setActivationPolicy(.regular)

// Paths to test
let appPath = Bundle.main.bundlePath  // This script itself (won't work for real, but tests .app drag)
let keyPathApp = "/Applications/KeyPath.app"
let kanataLauncher = "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher"

print("=== Drag-to-Settings Validation ===")
print("KeyPath.app exists: \(FileManager.default.fileExists(atPath: keyPathApp))")
print("kanata-launcher exists: \(FileManager.default.fileExists(atPath: kanataLauncher))")
print("")
print("Instructions:")
print("  1. System Settings will open to Accessibility")
print("  2. Drag each row from the floating window into the Settings list")
print("  3. Watch console for ✅ or ❌")
print("")

// Open Settings
let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
NSWorkspace.shared.open(url)

// Create test window
let window = NSPanel(
    contentRect: NSRect(x: 200, y: 100, width: 320, height: 120),
    styleMask: [.titled, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
window.title = "Drag Test — which file types does Settings accept?"
window.level = .floating
window.isFloatingPanel = true

let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))

// Row 1: KeyPath.app (should work — this is what Permiso does)
let appDrag = DragTestView(
    fileURL: URL(fileURLWithPath: keyPathApp),
    label: "KeyPath.app (full app bundle)",
    frame: NSRect(x: 10, y: 70, width: 300, height: 40)
)
container.addSubview(appDrag)

// Row 2: kanata-launcher (the real question — bare executable)
let launcherDrag = DragTestView(
    fileURL: URL(fileURLWithPath: kanataLauncher),
    label: "kanata-launcher (bare binary)",
    frame: NSRect(x: 10, y: 20, width: 300, height: 40)
)
container.addSubview(launcherDrag)

window.contentView = container
window.orderFront(nil)

print("Window shown. Drag items into System Settings to test.")
print("Press Ctrl+C to quit.\n")

app.run()
