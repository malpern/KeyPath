import AppKit
import SwiftUI

// MARK: - Public API

/// Edge of the trigger that an anchored popover should attach to.
public enum WindowAnchoredPopoverEdge {
    case leading
    case trailing
    case top
    case bottom
}

public extension View {
    /// Attaches a popover whose content is rendered at the nearest
    /// `windowAnchoredPopoverHost()` ancestor instead of as a local overlay.
    ///
    /// Use this when the trigger lives inside a clipped container (e.g. a
    /// narrow sidebar) and the popover content needs to float over the rest
    /// of the window without being cropped by the trigger's parent.
    func windowAnchoredPopover<PopoverContent: View>(
        isPresented: Binding<Bool>,
        edge: WindowAnchoredPopoverEdge = .leading,
        gap: CGFloat = 8,
        @ViewBuilder content: @escaping () -> PopoverContent
    ) -> some View {
        modifier(
            WindowAnchoredPopoverModifier(
                isPresented: isPresented,
                edge: edge,
                gap: gap,
                contentBuilder: content
            )
        )
    }

    /// Hosts window-anchored popovers. Apply once on an ancestor that
    /// covers the area the popover should be able to float over (typically
    /// the root view of the window). Any descendant calling
    /// `.windowAnchoredPopover(...)` will render into this host.
    func windowAnchoredPopoverHost() -> some View {
        modifier(WindowAnchoredPopoverHostModifier())
    }
}

// MARK: - Internal Entry

struct WindowAnchoredPopoverEntry: Identifiable, Equatable {
    let id: UUID
    let anchor: Anchor<CGRect>
    let edge: WindowAnchoredPopoverEdge
    let gap: CGFloat
    let content: AnyView
    let dismiss: () -> Void

    static func == (lhs: WindowAnchoredPopoverEntry, rhs: WindowAnchoredPopoverEntry) -> Bool {
        lhs.id == rhs.id && lhs.edge == rhs.edge && lhs.gap == rhs.gap
    }
}

struct WindowAnchoredPopoverPreferenceKey: PreferenceKey {
    static let defaultValue: [WindowAnchoredPopoverEntry] = []

    static func reduce(value: inout [WindowAnchoredPopoverEntry], nextValue: () -> [WindowAnchoredPopoverEntry]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - Trigger Modifier

private struct WindowAnchoredPopoverModifier<PopoverContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let edge: WindowAnchoredPopoverEdge
    let gap: CGFloat
    let contentBuilder: () -> PopoverContent

    @State private var id = UUID()

    func body(content: Content) -> some View {
        content.anchorPreference(
            key: WindowAnchoredPopoverPreferenceKey.self,
            value: .bounds
        ) { anchor in
            guard isPresented else { return [] }
            return [
                WindowAnchoredPopoverEntry(
                    id: id,
                    anchor: anchor,
                    edge: edge,
                    gap: gap,
                    content: AnyView(contentBuilder()),
                    dismiss: { isPresented = false }
                )
            ]
        }
    }
}

// MARK: - Host Modifier

private struct WindowAnchoredPopoverHostModifier: ViewModifier {
    @State private var escMonitor: Any?

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(WindowAnchoredPopoverPreferenceKey.self) { entries in
            hostOverlay(entries: entries)
        }
    }

    @ViewBuilder
    private func hostOverlay(entries: [WindowAnchoredPopoverEntry]) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if !entries.isEmpty {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            for entry in entries { entry.dismiss() }
                        }
                        .transition(.identity)
                }

                ForEach(entries) { entry in
                    WindowAnchoredPopoverContent(
                        entry: entry,
                        triggerFrame: proxy[entry.anchor],
                        hostSize: proxy.size
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: entries)
        }
        .allowsHitTesting(!entries.isEmpty)
        .onChange(of: entries) { _, newEntries in
            if newEntries.isEmpty {
                removeEscMonitor()
            } else {
                installEscMonitor(dismissAll: { for entry in newEntries { entry.dismiss() } })
            }
        }
        .onDisappear { removeEscMonitor() }
    }

    private func installEscMonitor(dismissAll: @escaping () -> Void) {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard event.keyCode == 53 else { return event }
            dismissAll()
            return nil
        }
    }

    private func removeEscMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
    }
}

// MARK: - Positioning

private struct WindowAnchoredPopoverContent: View {
    let entry: WindowAnchoredPopoverEntry
    let triggerFrame: CGRect
    let hostSize: CGSize

    @State private var measuredSize: CGSize = .zero

    var body: some View {
        let isMeasured = measuredSize.width > 0 && measuredSize.height > 0
        let size = isMeasured ? measuredSize : fallbackSize
        let edge = resolveEdge(size: size)
        let center = position(for: edge, size: size)

        entry.content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: WindowAnchoredPopoverSizeKey.self,
                        value: proxy.size
                    )
                }
            )
            .onPreferenceChange(WindowAnchoredPopoverSizeKey.self) { newSize in
                if newSize != measuredSize, newSize.width > 0, newSize.height > 0 {
                    measuredSize = newSize
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .opacity(isMeasured ? 1 : 0)
            .position(center)
    }

    private var fallbackSize: CGSize {
        CGSize(width: 280, height: 220)
    }

    private func resolveEdge(size: CGSize) -> WindowAnchoredPopoverEdge {
        switch entry.edge {
        case .leading:
            if triggerFrame.minX - entry.gap - size.width < 0 {
                return .trailing
            }
        case .trailing:
            if triggerFrame.maxX + entry.gap + size.width > hostSize.width {
                return .leading
            }
        case .top:
            if triggerFrame.minY - entry.gap - size.height < 0 {
                return .bottom
            }
        case .bottom:
            if triggerFrame.maxY + entry.gap + size.height > hostSize.height {
                return .top
            }
        }
        return entry.edge
    }

    private func position(for edge: WindowAnchoredPopoverEdge, size: CGSize) -> CGPoint {
        switch edge {
        case .leading:
            return CGPoint(
                x: triggerFrame.minX - entry.gap - size.width / 2,
                y: clampVertical(centerY: triggerFrame.midY, size: size)
            )
        case .trailing:
            return CGPoint(
                x: triggerFrame.maxX + entry.gap + size.width / 2,
                y: clampVertical(centerY: triggerFrame.midY, size: size)
            )
        case .top:
            return CGPoint(
                x: clampHorizontal(centerX: triggerFrame.midX, size: size),
                y: triggerFrame.minY - entry.gap - size.height / 2
            )
        case .bottom:
            return CGPoint(
                x: clampHorizontal(centerX: triggerFrame.midX, size: size),
                y: triggerFrame.maxY + entry.gap + size.height / 2
            )
        }
    }

    private func clampVertical(centerY: CGFloat, size: CGSize) -> CGFloat {
        let inset: CGFloat = 8
        let half = size.height / 2
        let minCenter = half + inset
        let maxCenter = max(minCenter, hostSize.height - half - inset)
        return min(maxCenter, max(minCenter, centerY))
    }

    private func clampHorizontal(centerX: CGFloat, size: CGSize) -> CGFloat {
        let inset: CGFloat = 8
        let half = size.width / 2
        let minCenter = half + inset
        let maxCenter = max(minCenter, hostSize.width - half - inset)
        return min(maxCenter, max(minCenter, centerX))
    }
}

private struct WindowAnchoredPopoverSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 { value = next }
    }
}
