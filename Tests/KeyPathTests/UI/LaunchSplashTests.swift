import AppKit
@testable import KeyPathAppKit
import SwiftUI
import XCTest

/// The launch splash is the KeyPath poster, and a normal test launch is not a login-item launch.
@MainActor
final class LaunchSplashTests: XCTestCase {
    private var resources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/KeyPathApp/Resources")
    }

    func testPosterShipsAtTwiceItsDisplayWidth() throws {
        let url = resources.appendingPathComponent("keypath-poster-hor.png")
        let rep = try XCTUnwrap(NSImageRep(contentsOf: url))
        XCTAssertEqual(rep.pixelsWide, 1120, "Drawn 560 pt wide, so 1120 px covers Retina")
        let bytes = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        XCTAssertLessThan(bytes, 1_000_000, "Keep the poster small; the original was 6.4 MB")
    }

    func testTestRunIsNotALoginItemLaunch() {
        XCTAssertFalse(AppDelegate.wasLaunchedAsLoginItem())
    }

    /// Renders the real view with the real poster and checks the poster is drawn
    /// across the middle of the window. Set KEYPATH_SPLASH_DUMP to a path to save it.
    func testSplashRendersThePoster() throws {
        let bundle = try XCTUnwrap(Bundle(url: resources))
        SplashView.PosterCache.warmIfNeeded(bundle: bundle)
        XCTAssertNotNil(SplashView.PosterCache.image)

        let presentation = SplashPresentation()
        presentation.isPreparing = false
        let renderer = ImageRenderer(content: SplashView().environment(presentation).frame(width: 640, height: 440))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage)
        if let path = ProcessInfo.processInfo.environment["KEYPATH_SPLASH_DUMP"],
           let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff)
        {
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        XCTAssertEqual(image.size, NSSize(width: 640, height: 440))

        // The background gradient runs top to bottom, so a row across it is one
        // colour. A row through the poster has many.
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let rep = NSBitmapImageRep(cgImage: cg)
        let middle = rep.pixelsHigh / 2
        let colours = Set((0 ..< rep.pixelsWide).compactMap { x -> String? in
            guard let c = rep.colorAt(x: x, y: middle)?.usingColorSpace(.sRGB) else { return nil }
            return String(format: "%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        })
        XCTAssertGreaterThan(colours.count, 50, "The middle of the splash should be the poster, not the plain background")
        let edge = try XCTUnwrap(rep.colorAt(x: 4, y: middle)?.usingColorSpace(.sRGB))
        let centre = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: middle)?.usingColorSpace(.sRGB))
        XCTAssertNotEqual(edge, centre)
    }
}
