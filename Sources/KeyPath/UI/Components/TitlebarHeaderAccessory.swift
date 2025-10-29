import AppKit
import SwiftUI

final class TitlebarHeaderAccessory: NSTitlebarAccessoryViewController {
    init(width _: CGFloat = 500) {
        super.init(nibName: nil, bundle: nil)

        let info = BuildInfo.current()
        let path = Bundle.main.bundlePath
        let stamp = "v\(info.version) (\(info.build)) • \(info.git)"

        let view = NSHostingView(rootView:
            HStack {
                Spacer(minLength: 0)
                Text(stamp)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 8)
                    .help(path)
            }
            .frame(height: 24)
            .background(
                VisualEffectRepresentable(material: .menu, blending: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            )
        )
        self.view = view
        layoutAttribute = .right
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
