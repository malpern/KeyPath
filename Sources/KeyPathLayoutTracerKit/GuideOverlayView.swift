import SwiftUI

struct GuideOverlayView: View {
    let guide: TracingGuide
    let isSelected: Bool
    let contentSize: CGSize
    let canvasOrigin: CGPoint
    let zoom: Double
    let coordinateScale: Double
    let onSelect: () -> Void
    let onMove: (CGSize, Bool) -> Void

    var body: some View {
        switch guide.axis {
        case .vertical:
            verticalGuide
        case .horizontal:
            horizontalGuide
        }
    }

    private var verticalGuide: some View {
        let x = canvasOrigin.x + (guide.position * zoom * coordinateScale)

        return Rectangle()
            .fill((isSelected ? Color.accentColor : Color.orange).opacity(0.95))
            .frame(width: 2, height: contentSize.height)
            .overlay(alignment: .topLeading) {
                Text(labelText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.7), in: Capsule())
                    .offset(x: 6, y: 6)
                    .allowsHitTesting(false)
            }
            .overlay {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 12, height: contentSize.height)
            }
            .offset(x: x - 1, y: canvasOrigin.y)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSelect()
                        onMove(CGSize(width: value.translation.width, height: 0), false)
                    }
                    .onEnded { value in
                        onMove(CGSize(width: value.translation.width, height: 0), true)
                    }
            )
            .highPriorityGesture(
                TapGesture().onEnded {
                    onSelect()
                }
            )
    }

    private var horizontalGuide: some View {
        let y = canvasOrigin.y + (guide.position * zoom * coordinateScale)

        return Rectangle()
            .fill((isSelected ? Color.accentColor : Color.orange).opacity(0.95))
            .frame(width: contentSize.width, height: 2)
            .overlay(alignment: .topLeading) {
                Text(labelText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.7), in: Capsule())
                    .offset(x: 6, y: 6)
                    .allowsHitTesting(false)
            }
            .overlay {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: contentSize.width, height: 12)
            }
            .offset(x: canvasOrigin.x, y: y - 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSelect()
                        onMove(CGSize(width: 0, height: value.translation.height), false)
                    }
                    .onEnded { value in
                        onMove(CGSize(width: 0, height: value.translation.height), true)
                    }
            )
            .highPriorityGesture(
                TapGesture().onEnded {
                    onSelect()
                }
            )
    }

    private var labelText: String {
        String(Int(guide.position.rounded()))
    }
}
