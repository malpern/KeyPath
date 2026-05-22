import SwiftUI

struct CommandPaletteView: View {
    let items: [CommandPaletteItem]
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var scrollAccumulator: CGFloat = 0
    @State private var scrollMonitor: Any?
    @FocusState private var isSearchFocused: Bool

    private var filtered: [CommandPaletteItem] {
        items.filter { $0.matches(searchText) }
    }

    private var groupedFiltered: [CommandPaletteGroup] {
        let ordered = filtered
        var seen: [String] = []
        var groups: [String: [CommandPaletteItem]] = [:]
        for item in ordered {
            if groups[item.group] == nil { seen.append(item.group) }
            groups[item.group, default: []].append(item)
        }
        return seen.map { CommandPaletteGroup(id: $0, items: groups[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if filtered.isEmpty {
                emptyState
            } else {
                resultsList
            }
            Divider()
            hintBar
        }
        .frame(width: 440, height: 360)
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .onAppear {
            selectedIndex = 0
            searchText = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                handleScrollWheel(event.scrollingDeltaY)
                return nil
            }
        }
        .onDisappear {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filtered.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.return) {
            if selectedIndex < filtered.count {
                let item = filtered[selectedIndex]
                onDismiss()
                item.action()
            }
            return .handled
        }
        .focusable()
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "command")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Type a command\u{2026}", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isSearchFocused)
                .onSubmit {
                    if selectedIndex < filtered.count {
                        let item = filtered[selectedIndex]
                        onDismiss()
                        item.action()
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Results

    private var indexedGroups: [(group: String, items: [(globalIndex: Int, item: CommandPaletteItem)])] {
        var result: [(group: String, items: [(globalIndex: Int, item: CommandPaletteItem)])] = []
        var globalIndex = 0
        for group in groupedFiltered {
            var indexedItems: [(globalIndex: Int, item: CommandPaletteItem)] = []
            for item in group.items {
                indexedItems.append((globalIndex: globalIndex, item: item))
                globalIndex += 1
            }
            result.append((group: group.id, items: indexedItems))
        }
        return result
    }

    private func handleScrollWheel(_ delta: CGFloat) {
        scrollAccumulator += delta
        let threshold: CGFloat = 3
        if scrollAccumulator <= -threshold {
            if selectedIndex < filtered.count - 1 { selectedIndex += 1 }
            scrollAccumulator = 0
        } else if scrollAccumulator >= threshold {
            if selectedIndex > 0 { selectedIndex -= 1 }
            scrollAccumulator = 0
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let groups = indexedGroups

                    ForEach(Array(groups.enumerated()), id: \.element.group) { groupIdx, group in
                        Section {
                            ForEach(group.items, id: \.item.id) { entry in
                                CommandPaletteRow(
                                    item: entry.item,
                                    isSelected: entry.globalIndex == selectedIndex
                                ) {
                                    selectedIndex = entry.globalIndex
                                    let action = entry.item.action
                                    onDismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                        action()
                                    }
                                }
                                .id(entry.item.id)
                            }
                        } header: {
                            Text(group.group)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, groupIdx == 0 ? 6 : 12)
                                .padding(.bottom, 4)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollDisabled(true)
            .onChange(of: selectedIndex) { _, newIndex in
                let flatItems = filtered
                if newIndex < flatItems.count {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(flatItems[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No matching commands")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Hint Bar

    private var hintBar: some View {
        HStack(spacing: 12) {
            Label("navigate", systemImage: "arrow.up.arrow.down")
            Label("select", systemImage: "return")
            Label("dismiss", systemImage: "escape")
        }
        .font(.caption2)
        .foregroundStyle(.secondary.opacity(0.5))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

// MARK: - Row

private struct CommandPaletteRow: View {
    let item: CommandPaletteItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                    }
                }

                Spacer(minLength: 4)

                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(isSelected ? .white.opacity(0.6) : .secondary.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isSelected ? Color.white.opacity(0.15) : Color.secondary.opacity(0.12))
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Visual Effect Blur

private struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
