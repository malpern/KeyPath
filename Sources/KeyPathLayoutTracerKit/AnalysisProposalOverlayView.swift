import SwiftUI

struct AnalysisProposalOverlayView: View {
    let proposal: LayoutAnalysisProposal
    let zoom: Double
    let coordinateScale: Double
    let canvasOrigin: CGPoint

    var body: some View {
        let frame = proposal.rect.applying(CGAffineTransform(scaleX: zoom * coordinateScale, y: zoom * coordinateScale))
        let cornerRadius = max(4, 8 * min(zoom, 1.4))

        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.orange.opacity(0.18))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.orange.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            .overlay(alignment: .topLeading) {
                Text("\(Int((proposal.confidence * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.7), in: Capsule())
                    .padding(4)
            }
            .frame(width: frame.width, height: frame.height)
            .rotationEffect(.degrees(proposal.rotation))
            .offset(x: frame.minX + canvasOrigin.x, y: frame.minY + canvasOrigin.y)
            .allowsHitTesting(false)
    }
}
