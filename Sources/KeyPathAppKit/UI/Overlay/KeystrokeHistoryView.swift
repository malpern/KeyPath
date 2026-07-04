import SwiftUI

struct KeystrokeHistoryView: View {
    let isDark: Bool
    @State private var service = KeystrokeHistoryService.shared
    @State private var autoScroll = true
    @Namespace private var bottomAnchor

    var body: some View {
        VStack(spacing: 0) {
            historyToolbar
            Divider().opacity(0.3)
            timelineContent
        }
    }

    // MARK: - Toolbar

    private var historyToolbar: some View {
        HStack(spacing: 8) {
            Button {
                service.isRecording.toggle()
            } label: {
                Image(systemName: service.isRecording ? "pause.circle.fill" : "record.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(service.isRecording ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .help(service.isRecording ? "Pause recording" : "Resume recording")
            .accessibilityLabel(service.isRecording ? "Pause recording" : "Resume recording")

            Text("\(service.eventCount) events")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                autoScroll.toggle()
            } label: {
                Image(systemName: autoScroll ? "arrow.down.to.line" : "arrow.down.to.line")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(autoScroll ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(autoScroll ? "Auto-scroll on" : "Auto-scroll off")
            .accessibilityLabel(autoScroll ? "Turn off auto-scroll" : "Turn on auto-scroll")

            Button {
                service.clearEvents()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear history")
            .accessibilityLabel("Clear history")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Timeline

    private var timelineContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if service.segments.isEmpty {
                        emptyState
                    } else {
                        ForEach(service.segments) { segment in
                            segmentView(for: segment)
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .onChange(of: service.segments.count) {
                if autoScroll {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(service.isRecording ? "Start typing to see history" : "Recording paused")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Segment Dispatch

    @ViewBuilder
    private func segmentView(for segment: TimelineSegment) -> some View {
        switch segment {
        case let .textRun(run):
            TextRunView(segment: run, isDark: isDark)
        case let .eventCard(card):
            EventCardView(segment: card, isDark: isDark)
        case let .layerDivider(divider):
            LayerDividerView(segment: divider)
        case let .appChanged(app):
            AppChangedView(segment: app)
        }
    }
}
