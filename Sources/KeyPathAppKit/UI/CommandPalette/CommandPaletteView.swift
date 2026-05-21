import SwiftUI

struct CommandPaletteView: View {
    let items: [CommandPaletteItem]
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var filtered: [CommandPaletteItem] {
        items.filter { $0.matches(searchText) }
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
        .frame(width: 440, height: 340)
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .onAppear {
            selectedIndex = 0
            searchText = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
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
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                        CommandPaletteRow(
                            item: item,
                            isSelected: index == selectedIndex
                        ) {
                            onDismiss()
                            item.action()
                        }
                        .id(item.id)
                        .onHover { hovering in
                            if hovering { selectedIndex = index }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                if newIndex < filtered.count {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(filtered[newIndex].id, anchor: .center)
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
        .foregroundStyle(.tertiary)
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
