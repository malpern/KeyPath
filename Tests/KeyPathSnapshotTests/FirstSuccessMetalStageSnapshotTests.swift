import AppKit
@testable import KeyPathAppKit
import Metal
import SnapshotTesting
import XCTest

/// Golden-image coverage for the Metal keyboard stage itself — the actual
/// product surface. The SwiftUI-fallback snapshots in
/// `FirstSuccessOnboardingSnapshotTests` cannot catch regressions in the
/// shader, atlas, or post pipeline; these render the same first-lesson scene
/// offscreen through the full HDR + bloom + composite path at the entrance's
/// contract checkpoints (dark hold, 25/50/75% reveal, settled).
///
/// Recording and comparison run only on the machine family that recorded the
/// goldens; like all screenshot suites this is gated behind
/// `KEYPATH_SNAPSHOTS=1` / `SNAPSHOT_RECORD=1`.
@MainActor
final class FirstSuccessMetalStageSnapshotTests: ScreenshotTestCase {
    /// Mirrors the installed composition: the stage occupies the trailing
    /// portion of the dialog, which drives the cinematic light coordinates.
    private static let stageWindowX = SIMD2<Float>(0.42, 0.58)
    private static let captureSize = CGSize(width: 1800, height: 1040)

    func testMetalEntranceContractFrames() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available on this machine.")
        }

        let scene = KeyboardStageSceneBuilder.make(
            layout: .macBookUS,
            keymap: .qwertyUS,
            moment: .capsMotivation,
            displayMode: .standard
        )
        let checkpoints: [(name: String, progress: Float)] = [
            ("metal-dark-hold", 0),
            ("metal-reveal-25", 0.25),
            ("metal-reveal-50", 0.5),
            ("metal-reveal-75", 0.75),
            ("metal-settled", 1),
        ]
        let initialFrame = KeyboardStagePresentedFrame(
            scene: scene,
            entrance: KeyboardStageEntranceFrame(progress: 0, reduceMotion: false)
        )
        let renderer = try KeyboardStageMetalRenderer(
            device: device,
            frame: initialFrame,
            onFirstFramePresented: {},
            onFailure: { _ in }
        )

        var gpuDurations: [String: TimeInterval] = [:]
        for checkpoint in checkpoints {
            let frame = KeyboardStagePresentedFrame(
                scene: scene,
                entrance: KeyboardStageEntranceFrame(
                    progress: checkpoint.progress,
                    reduceMotion: false
                )
            )
            // Warm-up render: the very first submission pays pipeline and
            // atlas setup; capture timings from a settled second submission.
            let capture = try renderer.captureFrame(
                frame: frame,
                drawableSize: Self.captureSize,
                windowX: Self.stageWindowX
            )
            let timed = try renderer.captureFrame(
                frame: frame,
                drawableSize: Self.captureSize,
                windowX: Self.stageWindowX
            )
            gpuDurations[checkpoint.name] = timed.gpuDuration

            assertMetalCapture(capture.image, named: checkpoint.name)
        }

        let report = gpuDurations
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \(String(format: "%.2f", $0.value * 1000)) ms" }
            .joined(separator: "\n")
        let attachment = XCTAttachment(string: report)
        attachment.name = "keyboard-stage-gpu-frame-times"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("Keyboard-stage GPU frame times (full pipeline, 1800x1040):\n\(report)")
    }

    private func assertMetalCapture(
        _ image: CGImage,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let rendered = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
        // GPU floating-point differences across driver updates land well
        // below these thresholds; real regressions (missing pass, palette
        // drift, geometry change) land far above them.
        let strategy = appKitPNGStrategy(
            precision: 0.985,
            perceptualPrecision: 0.975
        )
        if isRecordingMode {
            assertSnapshot(
                of: rendered,
                as: strategy,
                named: name,
                record: true,
                file: file,
                testName: testName,
                line: line
            )
        } else {
            assertSnapshot(
                of: rendered,
                as: strategy,
                named: name,
                file: file,
                testName: testName,
                line: line
            )
        }
    }
}
