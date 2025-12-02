import SwiftUI

/// Displays simulation results in a readable format.
struct SimulationResultsView: View {
    let result: SimulationResult?
    let error: Error?

    var body: some View {
        ScrollView {
            if let error {
                errorCard(error)
            } else if let result {
                resultContent(result)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Click keys above, then Run to simulate")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Error Card

    private func errorCard(_ error: Error) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Simulation Error", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundColor(.red)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
        .padding()
    }

    // MARK: - Result Content

    private func resultContent(_ result: SimulationResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary card
            summaryCard(result)

            // Output events
            if !outputEvents(from: result).isEmpty {
                outputKeysSection(result)
            }

            // Layer changes
            if !layerChanges(from: result).isEmpty {
                layerChangesSection(result)
            }

            // Full timeline
            timelineSection(result)
        }
        .padding()
    }

    // MARK: - Summary Card

    private func summaryCard(_ result: SimulationResult) -> some View {
        HStack(spacing: 20) {
            // Duration
            VStack(alignment: .leading, spacing: 2) {
                Text("Duration")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(result.durationMs)ms")
                    .font(.system(.body, design: .monospaced))
            }

            Divider()
                .frame(height: 30)

            // Final layer
            VStack(alignment: .leading, spacing: 2) {
                Text("Final Layer")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(result.finalLayer ?? "base")
                    .font(.system(.body, design: .monospaced))
            }

            Divider()
                .frame(height: 30)

            // Event counts
            VStack(alignment: .leading, spacing: 2) {
                Text("Events")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(result.events.count)")
                    .font(.system(.body, design: .monospaced))
            }

            Spacer()
        }
        .padding()
        .background(Color(white: 0.95))
        .cornerRadius(8)
    }

    // MARK: - Output Keys Section

    private func outputKeysSection(_ result: SimulationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output Keys")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                ForEach(outputEvents(from: result), id: \.timestamp) { event in
                    outputEventChip(event)
                }
            }
        }
    }

    private func outputEventChip(_ event: SimEvent) -> some View {
        HStack(spacing: 4) {
            if case let .output(_, action, key) = event {
                Text(action.symbol)
                    .font(.caption)
                Text(key)
                    .font(.system(.caption, design: .monospaced, weight: .medium))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.15))
        .cornerRadius(6)
    }

    // MARK: - Layer Changes Section

    private func layerChangesSection(_ result: SimulationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layer Changes")
                .font(.headline)

            ForEach(layerChanges(from: result), id: \.timestamp) { event in
                if case let .layer(t, from, to) = event {
                    HStack {
                        Text("\(t)ms")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)

                        Text(from)
                            .font(.system(.caption, design: .monospaced))

                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(to)
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }
            }
        }
    }

    // MARK: - Timeline Section

    private func timelineSection(_ result: SimulationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Event Timeline")
                .font(.headline)

            ForEach(Array(result.events.enumerated()), id: \.offset) { _, event in
                timelineRow(event)
            }
        }
    }

    private func timelineRow(_ event: SimEvent) -> some View {
        HStack(spacing: 12) {
            // Timestamp
            Text("\(event.timestamp)ms")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)

            // Event type badge
            eventTypeBadge(event)

            // Event description
            Text(event.displayDescription)
                .font(.system(.caption, design: .monospaced))

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func eventTypeBadge(_ event: SimEvent) -> some View {
        let (label, color): (String, Color) = switch event {
        case .input: ("IN", .blue)
        case .output: ("OUT", .green)
        case .layer: ("LYR", .purple)
        case .unicode: ("UNI", .orange)
        case .mouse: ("MSE", .pink)
        }

        return Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(4)
    }

    // MARK: - Helpers

    private func outputEvents(from result: SimulationResult) -> [SimEvent] {
        result.events.filter(\.isOutput)
    }

    private func layerChanges(from result: SimulationResult) -> [SimEvent] {
        result.events.filter(\.isLayerChange)
    }
}

// MARK: - Preview

#Preview("Empty") {
    SimulationResultsView(result: nil, error: nil)
}

#Preview("Error") {
    SimulationResultsView(
        result: nil,
        error: SimulatorError.configNotFound("/path/to/config.kbd")
    )
}

#Preview("Result") {
    SimulationResultsView(
        result: SimulationResult(
            events: [
                .input(t: 0, action: .press, key: "j"),
                .output(t: 0, action: .press, key: "j"),
                .input(t: 200, action: .release, key: "j"),
                .output(t: 200, action: .release, key: "j"),
                .layer(t: 1500, from: "base", to: "nav")
            ],
            finalLayer: "nav",
            durationMs: 1500
        ),
        error: nil
    )
}
