import SwiftUI

struct KeyOverlayView: View {
    let key: TracingKey
    let isSelected: Bool
    let cornerRadius: Double
    let zoom: Double
    let coordinateScale: Double
    let canvasOrigin: CGPoint
    let onSelect: () -> Void
    let onMove: (CGSize, Bool) -> Void
    let onResize: (CGSize, Bool) -> Void
    @State private var dragStarted = false

    var body: some View {
        let frame = key.rect.applying(CGAffineTransform(scaleX: zoom * coordinateScale, y: zoom * coordinateScale))
        let renderedCornerRadius = max(0, cornerRadius * min(zoom, 1.4))
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: renderedCornerRadius)
                .fill(isSelected ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.18))
            RoundedRectangle(cornerRadius: renderedCornerRadius)
                .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.7), lineWidth: isSelected ? 2 : 1)

            Text(key.label.isEmpty ? "Key" : key.label)
                .font(.system(size: max(11, 13 * min(zoom, 1.2)), weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if isSelected {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                    .padding(6)
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
        }
        .frame(width: frame.width, height: frame.height)
        .rotationEffect(.degrees(key.rotation ?? 0))
        .offset(x: frame.minX + canvasOrigin.x, y: frame.minY + canvasOrigin.y)
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture()
                .onEnded {
                    onSelect()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if !dragStarted {
                        dragStarted = true
                        onSelect()
                    }
                    onMove(value.translation, false)
                }
                .onEnded { value in
                    onMove(value.translation, true)
                    dragStarted = false
                }
        )
    }
}
