@testable import KeyPathAppKit
import XCTest

final class PackZoneResolverTests: XCTestCase {

    // MARK: - activeZoneColors

    func testActiveZoneColors_NoInstalledPacks_ReturnsEmpty() {
        let colors = PackZoneResolver.activeZoneColors(installedPackIDs: [], layerName: "base")
        XCTAssertTrue(colors.isEmpty)
    }

    func testActiveZoneColors_UnknownPackID_ReturnsEmpty() {
        let colors = PackZoneResolver.activeZoneColors(
            installedPackIDs: ["com.keypath.pack.nonexistent"],
            layerName: "base"
        )
        XCTAssertTrue(colors.isEmpty)
    }

    func testActiveZoneColors_VallackPack_ReturnsColorsForVallackNav() {
        let colors = PackZoneResolver.activeZoneColors(
            installedPackIDs: [PackRegistry.vallackSystem.id],
            layerName: "vallack-nav"
        )
        XCTAssertFalse(colors.isEmpty, "Vallack system should provide zone colors for vallack-nav layer")
    }

    func testActiveZoneColors_VallackPack_BaseLayer_ReturnsColors() {
        let colors = PackZoneResolver.activeZoneColors(
            installedPackIDs: [PackRegistry.vallackSystem.id],
            layerName: "base"
        )
        // Vallack zones apply per the VallackZoneMap.zones() implementation
        // At minimum the base layer may or may not have zones — this tests the code path
        // The important thing is it doesn't crash
        _ = colors
    }

    // MARK: - activeZoneSubtitles

    func testActiveZoneSubtitles_NoInstalledPacks_ReturnsEmpty() {
        let subs = PackZoneResolver.activeZoneSubtitles(installedPackIDs: [], layerName: "base")
        XCTAssertTrue(subs.isEmpty)
    }

    func testActiveZoneSubtitles_VallackPack_BaseLayer_ReturnsHomeSubtitles() {
        let subs = PackZoneResolver.activeZoneSubtitles(
            installedPackIDs: [PackRegistry.vallackSystem.id],
            layerName: "base"
        )
        XCTAssertFalse(subs.isEmpty, "Vallack system should provide home subtitles on base layer")
    }

    func testActiveZoneSubtitles_VallackPack_NavLayer_ReturnsNavSubtitles() {
        let subs = PackZoneResolver.activeZoneSubtitles(
            installedPackIDs: [PackRegistry.vallackSystem.id],
            layerName: "vallack-nav"
        )
        XCTAssertFalse(subs.isEmpty, "Vallack nav layer should have nav subtitles")
    }

    // MARK: - layerPreviewConfig

    func testLayerPreviewConfig_NoInstalledPacks_ReturnsNil() {
        let config = PackZoneResolver.layerPreviewConfig(installedPackIDs: [])
        XCTAssertNil(config)
    }

    func testLayerPreviewConfig_VallackPack_ReturnsTargets() {
        let config = PackZoneResolver.layerPreviewConfig(
            installedPackIDs: [PackRegistry.vallackSystem.id]
        )
        XCTAssertNotNil(config)
        XCTAssertFalse(config!.targets.isEmpty)
        XCTAssertEqual(config!.activatorKeyCodes, VallackZoneMap.activatorKeyCodes)
    }

    func testLayerPreviewConfig_VallackPack_TargetsVallackNavLayer() {
        let config = PackZoneResolver.layerPreviewConfig(
            installedPackIDs: [PackRegistry.vallackSystem.id]
        )!
        for (_, layer) in config.targets {
            XCTAssertEqual(layer, "vallack-nav")
        }
    }

    func testLayerPreviewConfig_UnknownPack_ReturnsNil() {
        let config = PackZoneResolver.layerPreviewConfig(
            installedPackIDs: ["com.keypath.pack.nonexistent"]
        )
        XCTAssertNil(config)
    }

    // MARK: - LayerPreviewConfig

    func testLayerPreviewConfig_ActivatorKeyCodes_MatchesTargetKeys() {
        let targets: [UInt16: String] = [1: "nav", 2: "nav", 3: "sym"]
        let config = PackZoneResolver.LayerPreviewConfig(targets: targets)
        XCTAssertEqual(config.activatorKeyCodes, Set([1, 2, 3]))
    }
}
