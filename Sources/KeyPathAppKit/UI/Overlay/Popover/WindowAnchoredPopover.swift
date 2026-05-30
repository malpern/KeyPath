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
    ///
    /// - Parameters:
    ///   - isPresented: Controls visibility. Setting to `false` (e.g. via the
    ///     host's tap-outside or ESC handling) dismisses the popover.
    ///   - edge: The edge of the trigger the popover attaches to. Defaults to
    ///     `.leading` (popover floats left of the trigger), which is the right
    ///     choice for triggers in a right-side sidebar. The host auto-flips
    ///     to the opposite edge if the popover would clip the host bounds.
    ///   - gap: Space between the trigger edge and the popover edge.
    ///   - content: The popover content. Built once when `isPresented`
    ///     becomes `true` and cached until dismissal, so heavier content
    ///     doesn't pay a rebuild cost on every layout pass.
    func windowAnchoredPopover(
        isPresented: Binding<Bool>,
        edge: WindowAnchoredPopoverEdge = .leading,
        gap: CGFloat = 8,
        @ViewBuilder content: @escaping () -> some View
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

struct WindowAnchoredPopoverEntry: Identifiable, Equatable, @unchecked Sendable {
    let id: UUID
    let anchor: Anchor<CGRect>
    let edge: WindowAnchoredPopoverEdge
    let gap: CGFloat
    /// Type-erased so any caller can attach arbitrary popover content
    /// without bubbling a generic parameter all the way to the host.
    /// The trade-off is that SwiftUI can't diff inside the popover
    /// subtree across `entries` updates — acceptable for picker-style
    /// content; revisit if the host renders large dynamic trees.
    let content: AnyView
    let dismiss: () -> Void

    /// Identity-only equality. `anchor` is `Anchor<CGRect>` (not Equatable),
    /// `content` is `AnyView` (untyped), and `dismiss` is a closure — none of
    /// these can participate. Comparing only `id` also matches our semantic
    /// intent: the host only needs to know when the *set of open popovers*
    /// changes (so it can rebind the ESC monitor). Layout-driven anchor
    /// movement should not retrigger that work.
    static func == (lhs: WindowAnchoredPopoverEntry, rhs: WindowAnchoredPopoverEntry) -> Bool {
        lhs.id == rhs.id
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

    /// Stable per trigger-site identity. SwiftUI preserves `@State` across
    /// recompositions of the same view, so this UUID is generated once and
    /// reused for every emitted entry from this modifier.
    @State private var id = UUID()

    /// Cached popover content. Built once when `isPresented` flips to `true`
    /// and held until dismissal, so the popover view tree is not
    /// re-instantiated on every layout pass (which the surrounding
    /// `anchorPreference` transform would otherwise trigger).
    @State private var cachedContent: AnyView?

    func body(content: Content) -> some View {
        content
            .anchorPreference(
                key: WindowAnchoredPopoverPreferenceKey.self,
                value: .bounds
            ) { anchor in
                guard isPresented, let cachedContent else { return [] }
                return [
                    WindowAnchoredPopoverEntry(
                        id: id,
                        anchor: anchor,
                        edge: edge,
                        gap: gap,
                        content: cachedContent,
                        dismiss: { isPresented = false }
                    )
                ]
            }
            .onChange(of: isPresented) { _, isOpen in
                if isOpen {
                    cachedContent = AnyView(contentBuilder())
                } else {
                    cachedContent = nil
                }
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
        // When no popover is open the host contributes nothing to the view
        // tree at all (no GeometryReader, no overlay layer). This keeps
        // `.windowAnchoredPopoverHost()` invisible to snapshot tests and
        // hit-testing when idle.
        if entries.isEmpty {
            Color.clear
                .frame(width: 0, height: 0)
                .hidden()
                .allowsHitTesting(false)
                .onChange(of: entries) { _, _ in removeEscMonitor() }
                .onDisappear { removeEscMonitor() }
        } else {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    // 0.001 opacity makes this layer invisible while still
                    // hit-testable, so taps outside the popover dismiss it
                    // without darkening the underlying UI.
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            for entry in entries {
                                entry.dismiss()
                            }
                        }
                        .accessibilityIdentifier("window-anchored-popover-dismiss-backdrop")
                        .accessibilityLabel("Dismiss popover")
                        .accessibilityAddTraits(.isButton)
                        .transition(.identity)

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
            .onChange(of: entries) { _, newEntries in
                if newEntries.isEmpty {
                    removeEscMonitor()
                } else {
                    installEscMonitor(dismissAll: { for entry in newEntries {
                        entry.dismiss()
                    } })
                }
            }
            .onAppear {
                installEscMonitor(dismissAll: { for entry in entries {
                    entry.dismiss()
                } })
            }
            .onDisappear { removeEscMonitor() }
        }
    }

    private func installEscMonitor(dismissAll: @escaping () -> Void) {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // 53 = kVK_Escape (no Carbon import needed for this single constant)
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
        // Skip the flip on the unmeasured first frame so a stale
        // `fallbackSize` can't move the popover to the wrong side
        // (which would then need to animate back once measured).
        // The view is opacity-0 in that frame anyway.
        let edge = isMeasured ? resolveEdge(size: size) : entry.edge
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
            CGPoint(
                x: triggerFrame.minX - entry.gap - size.width / 2,
                y: clampVertical(centerY: triggerFrame.midY, size: size)
            )
        case .trailing:
            CGPoint(
                x: triggerFrame.maxX + entry.gap + size.width / 2,
                y: clampVertical(centerY: triggerFrame.midY, size: size)
            )
        case .top:
            CGPoint(
                x: clampHorizontal(centerX: triggerFrame.midX, size: size),
                y: triggerFrame.minY - entry.gap - size.height / 2
            )
        case .bottom:
            CGPoint(
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
