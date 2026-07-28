import Foundation

public enum CaptureLayoutMode: String, Sendable {
    case regular
    case compact
    case tiny
}

public struct CaptureLayoutMetrics: Equatable, Sendable {
    public let mode: CaptureLayoutMode
    public let padding: Double
    public let headerHeight: Double
    public let stateFontSize: Double
    public let fieldHeight: Double
    public let showsFooter: Bool

    public static func resolve(width: Double, height: Double) -> CaptureLayoutMetrics {
        if width >= 700, height >= 540 {
            return CaptureLayoutMetrics(
                mode: .regular, padding: 26, headerHeight: 54, stateFontSize: 38,
                fieldHeight: 34, showsFooter: true
            )
        }
        if width >= 480, height >= 360 {
            return CaptureLayoutMetrics(
                mode: .compact, padding: 18, headerHeight: 44, stateFontSize: 30,
                fieldHeight: 30, showsFooter: true
            )
        }
        return CaptureLayoutMetrics(
            mode: .tiny, padding: 10, headerHeight: 32, stateFontSize: 23,
            fieldHeight: 26, showsFooter: false
        )
    }
}
