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
    ///   - content: The popover content. Rebuilt from live state as the host
    ///     re-renders, so it always reflects the trigger view's current state
    ///     (selection, drill-down page, etc.) rather than a snapshot from open.
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

struct WindowAnchoredPopoverEntry: Identifiable, @unchecked Sendable {
    let id: UUID
    let anchor: Anchor<CGRect>
    let edge: WindowAnchoredPopoverEdge
    let gap: CGFloat
    /// Type-erased so any caller can attach arbitrary popover content
    /// without bubbling a generic parameter all the way to the host.
    let content: AnyView
    let dismiss: () -> Void

    // Deliberately NOT `Equatable`. An identity-only `==` (comparing just `id`)
    // used to live here, but it caused SwiftUI to treat a same-id entry whose
    // *content* changed as unchanged — skipping both the preference update and
    // the content re-render. The result: the popover kept showing stale content
    // (e.g. the picker never navigated to a tapped sub-page even though the
    // model and rebuilt content were both correct). Without `Equatable`, the
    // host re-renders the content whenever it is re-emitted, so it always
    // reflects the latest state. Work that only cares about the *set* of open
    // popovers (the ESC monitor) keys on `entries.map(\.id)` instead.
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

    func body(content: Content) -> some View {
        content
            .anchorPreference(
                key: WindowAnchoredPopoverPreferenceKey.self,
                value: .bounds
            ) { anchor in
                guard isPresented else { return [] }
                // Build the content fresh each time the preference is
                // recomputed rather than caching it once on open. The popover
                // body depends on the trigger view's live state (e.g. the
                // mapper picker's expand/selection flags); a one-shot cache
                // froze that state, so expanding a section or changing the
                // selection never re-rendered and the rows looked dead to
                // clicks. Rebuilding ties content freshness to the source
                // view's re-renders. The build is a lightweight picker tree;
                // structural identity is stable so in-popover state persists.
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
    @State private var outsideClickMonitor: Any?

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
                .onChange(of: entries.map(\.id)) { _, _ in removeDismissMonitors() }
                .onDisappear { removeDismissMonitors() }
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
                .animation(.easeOut(duration: 0.12), value: entries.map(\.id))
            }
            // Key only on the set of open popover ids: the ESC monitor only
            // needs rebinding when a popover opens/closes, not when content or
            // anchor change on every layout pass.
            .onChange(of: entries.map(\.id)) { _, ids in
                if ids.isEmpty {
                    removeDismissMonitors()
                } else {
                    installDismissMonitors(dismissAll: { for entry in entries {
                        entry.dismiss()
                    } })
                }
            }
            .onAppear {
                installDismissMonitors(dismissAll: { for entry in entries {
                    entry.dismiss()
                } })
            }
            .onDisappear { removeDismissMonitors() }
        }
    }

    private func installDismissMonitors(dismissAll: @escaping () -> Void) {
        removeDismissMonitors()
        // ESC dismisses (local key monitor — no accessibility permission needed).
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // 53 = kVK_Escape (no Carbon import needed for this single constant)
            guard event.keyCode == 53 else { return event }
            dismissAll()
            return nil
        }
        // A click outside the app's own windows (another app, the desktop)
        // dismisses too. The in-window backdrop can't see those events, so the
        // popover would otherwise linger after the user clicks away. Global
        // monitors only observe events destined for *other* apps, so this never
        // fires for clicks on the overlay itself (those stay local).
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { _ in
            dismissAll()
        }
    }

    private func removeDismissMonitors() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
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
