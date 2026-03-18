import SwiftUI

struct LayoutBoundsOverlayView: View {
    let bounds: CGRect
    let isSelected: Bool
    let zoom: Double
    let coordinateScale: Double
    let canvasOrigin: CGPoint
    let onSelect: () -> Void
    let onMove: (CGSize, Bool) -> Void
    let onResize: (CGSize, Bool) -> Void

    var body: some View {
        let frame = bounds.applying(CGAffineTransform(scaleX: zoom * coordinateScale, y: zoom * coordinateScale))

        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            onSelect()
                            onMove(value.translation, false)
                        }
                        .onEnded { value in
                            onMove(value.translation, true)
                        }
                )
                .highPriorityGesture(
                    TapGesture().onEnded {
                        onSelect()
                    }
                )

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.white.opacity(0.72),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                )
                .shadow(color: .black.opacity(0.45), radius: 0, x: 0, y: 1)
                .allowsHitTesting(false)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 14, height: 14)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                }
                .padding(6)
                .allowsHitTesting(true)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            onResize(value.translation, false)
                        }
                        .onEnded { value in
                            onResize(value.translation, true)
                        }
                )
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX + canvasOrigin.x, y: frame.minY + canvasOrigin.y)
    }
}
