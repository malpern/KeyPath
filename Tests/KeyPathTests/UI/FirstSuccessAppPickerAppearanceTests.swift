import AppKit
@testable import KeyPathAppKit
import SwiftUI
import XCTest

@MainActor
final class FirstSuccessAppPickerAppearanceTests: XCTestCase {
    func testPickerOwnsReadableSurfaceInsideDarkSheet() throws {
        // The tour overrides its foreground to dark text, while a native sheet
        // can retain the system dark appearance. Exercise that exact mismatch.
        let content = FirstSuccessRunningAppPicker(selectApp: { _ in }, browse: {})
            .foregroundStyle(Color(red: 0.17, green: 0.16, blue: 0.16))
            .environment(\.colorScheme, .dark)
            .background(Color(red: 0.16, green: 0.15, blue: 0.14))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let background = try XCTUnwrap(bitmap.colorAt(x: 165, y: 200)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(background.redComponent, 0.85, "The light tour picker must supply its own light surface, even in a dark native sheet")
        // Header contains readable dark ink on that light surface.
        var darkPixels = 0
        for y in 10..<40 {
            for x in 14..<145 {
                if let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                   pixel.redComponent < 0.3 && pixel.greenComponent < 0.3 {
                    darkPixels += 1
                }
            }
        }
        XCTAssertGreaterThan(darkPixels, 40)
    }
}
