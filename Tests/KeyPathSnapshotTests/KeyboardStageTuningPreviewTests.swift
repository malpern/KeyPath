import AppKit
@testable import KeyPathAppKit
import Metal
import XCTest

/// Offscreen tuning previews: renders the first-lesson dark hold and settled
/// frames through the exact Metal pipeline into a scratch directory, honoring
/// `KEYPATH_STAGE_TUNING_FILE` overrides. This gives lighting-tuning sessions
/// a deterministic, screen-free loop — no installed app, no window automation.
///
///     KEYPATH_STAGE_TUNING_FILE=~/t.json \
///     KEYPATH_STAGE_PREVIEW_DIR=/tmp/stage-previews \
///     swift test --filter KeyboardStageTuningPreviewTests
///
/// Skips unless `KEYPATH_STAGE_PREVIEW_DIR` is set, so it never runs in CI or
/// ordinary suites and never touches the recorded goldens.
@MainActor
final class KeyboardStageTuningPreviewTests: XCTestCase {
    func testRenderTuningPreviews() throws {
        guard let outputPath = ProcessInfo.processInfo
            .environment["KEYPATH_STAGE_PREVIEW_DIR"], !outputPath.isEmpty
        else {
            throw XCTSkip("Set KEYPATH_STAGE_PREVIEW_DIR to render tuning previews.")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available on this machine.")
        }

        let outputDirectory = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let moments: [(String, KeyboardStageMoment)] = [
            ("caps", .capsMotivation),
            ("launcher", .launcher),
            ("handoff", .handoff),
        ]
        let scenes = moments.map { name, moment in
            (name, KeyboardStageSceneBuilder.make(
                layout: .macBookUS,
                keymap: .qwertyUS,
                moment: moment,
                displayMode: .standard
            ))
        }
        let scene = scenes[0].1
        let renderer = try KeyboardStageMetalRenderer(
            device: device,
            frame: KeyboardStagePresentedFrame(
                scene: scene,
                entrance: KeyboardStageEntranceFrame(progress: 0, reduceMotion: false)
            ),
            onFirstFramePresented: {},
            onFailure: { _ in }
        )
        if let tuningURL = KeyboardStageTuning.environmentFileURL {
            try renderer.update(tuning: KeyboardStageTuning.load(from: tuningURL))
        }

        for (sceneName, momentScene) in scenes {
            for (name, progress) in [("dark", Float(0)), ("mid", 0.5), ("settled", 1)] {
                let capture = try renderer.captureFrame(
                    frame: KeyboardStagePresentedFrame(
                        scene: momentScene,
                        entrance: KeyboardStageEntranceFrame(
                            progress: progress,
                            reduceMotion: false
                        )
                    ),
                    drawableSize: CGSize(width: 1800, height: 1040),
                    windowX: SIMD2<Float>(0.42, 0.58)
                )
                let destination = outputDirectory
                    .appendingPathComponent("preview-\(sceneName)-\(name).png")
                let representation = NSBitmapImageRep(cgImage: capture.image)
                let data = try XCTUnwrap(representation.representation(
                    using: .png,
                    properties: [:]
                ))
                try data.write(to: destination)
            }
        }
    }
}
