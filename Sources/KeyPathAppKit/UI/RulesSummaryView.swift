import KeyPathCore
import SwiftUI

#if os(macOS)
  import AppKit
#endif

struct RulesTabView: View {
  @EnvironmentObject var kanataManager: KanataViewModel
  @State private var showingResetConfirmation = false
  @State private var showingNewRuleSheet = false
  @State private var settingsToastManager = WizardToastManager()
  @State private var isPresentingNewRule = false
  @State private var editingRule: CustomRule?
  @State private var createButtonHovered = false
  private let catalog = RuleCollectionCatalog()

  // Show all catalog collections, merging with existing state
  private var allCollections: [RuleCollection] {
    let catalog = RuleCollectionCatalog()
    return catalog.defaultCollections().map { catalogCollection in
      // Find matching collection from kanataManager to preserve enabled state
      if let existing = kanataManager.ruleCollections.first(where: { $0.id == catalogCollection.id }
      ) {
        return existing
      }
      // Return catalog item with its default enabled state
      return catalogCollection
    }
  }

  private var customRulesTitle: String {
    let count = kanataManager.customRules.count
    return count > 0 ? "Custom Rules (\(count))" : "Custom Rules"
  }

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      // Left Column: Create Rule + Advanced
      VStack(alignment: .leading, spacing: 24) {
        // Create Rule Section
        VStack(spacing: 16) {
          VStack(spacing: 12) {
            CreateRuleButton(
              isPressed: $isPresentingNewRule,
              externalHover: $createButtonHovered
            )

            Button {
              isPresentingNewRule = true
            } label: {
              Text("Create Rule")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
              createButtonHovered = hovering
            }
          }

          Button {
            isPresentingNewRule = true
          } label: {
            Text("Create")
              .frame(minWidth: 100)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
        }
        .frame(minWidth: 220)

        // Action buttons centered under image
        VStack(spacing: 8) {
          Button(action: { openConfigInEditor() }) {
            Label("Edit Config File", systemImage: "doc.text.magnifyingglass")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)

          Button(action: { showingResetConfirmation = true }) {
            Label("Reset to Default", systemImage: "arrow.counterclockwise")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .tint(.red)
        }
        .frame(maxWidth: .infinity)

        Spacer()
      }
      .padding(20)
      .frame(width: 280)
      .background(Color(NSColor.windowBackgroundColor))

      // Right Column: Rules List
      ScrollView {
        VStack(spacing: 0) {
          // Custom Rules Section (toggleable, expanded when has rules)
          ExpandableCollectionRow(
            name: customRulesTitle,
            icon: "square.and.pencil",
            count: kanataManager.customRules.count,
            isEnabled: kanataManager.customRules.isEmpty
              || kanataManager.customRules.allSatisfy(\.isEnabled),
            mappings: kanataManager.customRules.map { ($0.input, $0.output, $0.isEnabled, $0.id) },
            onToggle: { isOn in
              Task {
                for rule in kanataManager.customRules {
                  await kanataManager.toggleCustomRule(rule.id, enabled: isOn)
                }
              }
            },
            onEditMapping: { id in
              if let rule = kanataManager.customRules.first(where: { $0.id == id }) {
                editingRule = rule
              }
            },
            onDeleteMapping: { id in
              Task { await kanataManager.removeCustomRule(id) }
            },
            showZeroState: kanataManager.customRules.isEmpty,
            onCreateFirstRule: { isPresentingNewRule = true },
            description: "Remap any key combination or sequence",
            defaultExpanded: !kanataManager.customRules.isEmpty
          )
          .padding(.vertical, 4)

          // Collection Rows
          ForEach(allCollections) { collection in
            ExpandableCollectionRow(
              name: collection.name,
              icon: collection.icon ?? "circle",
              count: collection.mappings.count,
              isEnabled: collection.isEnabled,
              mappings: collection.mappings.map {
                ($0.input, $0.output, collection.isEnabled, $0.id)
              },
              onToggle: { isOn in
                Task { await kanataManager.toggleRuleCollection(collection.id, enabled: isOn) }
              },
              onEditMapping: nil,
              onDeleteMapping: nil,
              description: collection.summary,
              layerActivator: collection.momentaryActivator
            )
            .padding(.vertical, 4)
          }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(NSColor.windowBackgroundColor))
    }
    .frame(maxHeight: 450)
    .settingsBackground()
    .withToasts(settingsToastManager)
    .sheet(isPresented: $isPresentingNewRule) {
      CustomRuleEditorView(rule: nil) { newRule in
        _ = Task { await kanataManager.saveCustomRule(newRule) }
      }
    }
    .sheet(item: $editingRule) { rule in
      CustomRuleEditorView(rule: rule) { updatedRule in
        _ = Task { await kanataManager.saveCustomRule(updatedRule) }
      }
    }
    .alert("Reset Configuration?", isPresented: $showingResetConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Open Backups Folder") {
        openBackupsFolder()
      }
      Button("Reset", role: .destructive) {
        resetToDefaultConfig()
      }
    } message: {
      Text(
        """
        This will reset your configuration to macOS Function Keys only (all custom rules removed).
        A safety backup will be stored in ~/.config/keypath/.backups.
        """)
    }
  }

  private func openConfigInEditor() {
    let url = URL(fileURLWithPath: kanataManager.configPath)
    NSWorkspace.shared.open(url)
    AppLogger.shared.log("📝 [Rules] Opened config for editing")
  }

  private func openBackupsFolder() {
    let backupsPath = "\(NSHomeDirectory())/.config/keypath/.backups"
    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: backupsPath)
  }

  private func resetToDefaultConfig() {
    Task {
      do {
        try await kanataManager.resetToDefaultConfig()
        settingsToastManager.showSuccess("Configuration reset to default")
      } catch {
        settingsToastManager.showError("Reset failed: \(error.localizedDescription)")
      }
    }
  }
}

// MARK: - Expandable Collection Row

private struct ExpandableCollectionRow: View {
  let name: String
  let icon: String
  let count: Int
  let isEnabled: Bool
  let mappings: [(input: String, output: String, enabled: Bool, id: UUID)]
  let onToggle: (Bool) -> Void
  let onEditMapping: ((UUID) -> Void)?
  let onDeleteMapping: ((UUID) -> Void)?
  var showZeroState: Bool = false
  var onCreateFirstRule: (() -> Void)?
  var description: String?
  var layerActivator: MomentaryActivator?
  var defaultExpanded: Bool = false

  @State private var isExpanded = false
  @State private var isHovered = false
  @State private var hasInitialized = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header Row (clickable for expand/collapse)
      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          isExpanded.toggle()
        }
      } label: {
        HStack(alignment: .top, spacing: 12) {
          iconView(for: icon)
            .frame(width: 24)

          VStack(alignment: .leading, spacing: 2) {
            Text(name)
              .font(.headline)
              .foregroundColor(.primary)

            if let desc = description {
              Text(desc)
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            if let activator = layerActivator {
              Label("Hold \(prettyKeyName(activator.input))", systemImage: "hand.point.up.left")
                .font(.caption)
                .foregroundColor(.accentColor)
            }
          }

          Spacer()

          Toggle(
            "",
            isOn: Binding(
              get: { isEnabled },
              set: { onToggle($0) }
            )
          )
          .labelsHidden()
          .toggleStyle(.switch)
          .tint(.blue)
          .onTapGesture {}  // Prevents toggle from triggering row expansion

          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.callout)
            .foregroundColor(.secondary)
        }
        .padding(12)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background(Color(NSColor.windowBackgroundColor))
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(Color.white.opacity(isHovered ? 0.15 : 0), lineWidth: 1)
      )
      .onHover { hovering in
        isHovered = hovering
      }

      // Expanded Mappings or Zero State
      if isExpanded {
        if showZeroState, let onCreate = onCreateFirstRule {
          // Zero State
          VStack(spacing: 12) {
            Text("No rules yet")
              .font(.subheadline)
              .foregroundColor(.secondary)

            Button {
              onCreate()
            } label: {
              Label("Create Your First Rule", systemImage: "plus.circle.fill")
                .font(.body.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 20)
        } else {
          VStack(spacing: 6) {
            ForEach(mappings, id: \.id) { mapping in
              HStack(spacing: 8) {
                // Show layer activator if present
                if let activator = layerActivator {
                  HStack(spacing: 4) {
                    Text("Hold")
                      .font(.body.monospaced().weight(.semibold))
                      .foregroundColor(.accentColor)
                    Text(prettyKeyName(activator.input))
                      .font(.body.monospaced().weight(.semibold))
                      .foregroundColor(.primary)
                  }
                  .padding(.horizontal, 12)
                  .padding(.vertical, 6)
                  .background(
                    Capsule()
                      .fill(Color(NSColor.controlBackgroundColor))
                  )

                  Text("+")
                    .font(.body)
                    .foregroundColor(.secondary)
                }

                Text(prettyKeyName(mapping.input))
                  .font(.body.monospaced().weight(.semibold))
                  .foregroundColor(.primary)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 6)
                  .background(
                    Capsule()
                      .fill(Color(NSColor.controlBackgroundColor))
                  )

                Image(systemName: "arrow.right")
                  .font(.body.weight(.medium))
                  .foregroundColor(.secondary)

                Text(prettyKeyName(mapping.output))
                  .font(.body.monospaced().weight(.semibold))
                  .foregroundColor(.primary)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 6)
                  .background(
                    Capsule()
                      .fill(Color(NSColor.controlBackgroundColor))
                  )

                Spacer()

                if let onEdit = onEditMapping {
                  Button {
                    onEdit(mapping.id)
                  } label: {
                    Image(systemName: "pencil")
                      .font(.callout)
                  }
                  .buttonStyle(.plain)
                  .foregroundColor(.blue)
                }

                if let onDelete = onDeleteMapping {
                  Button {
                    onDelete(mapping.id)
                  } label: {
                    Image(systemName: "trash")
                      .font(.callout)
                  }
                  .buttonStyle(.plain)
                  .foregroundColor(.red)
                }
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 4)
            }
          }
          .padding(.top, 8)
          .padding(.bottom, 12)
        }
      }
    }
    .onAppear {
      if !hasInitialized {
        isExpanded = defaultExpanded
        hasInitialized = true
      }
    }
  }

  @ViewBuilder
  func iconView(for icon: String) -> some View {
    if icon.hasPrefix("text:") {
      let text = String(icon.dropFirst(5))
      Text(text)
        .font(.system(size: 14, weight: .bold, design: .monospaced))
        .foregroundColor(.secondary)
        .frame(width: 24, height: 24)
    } else {
      Image(systemName: icon)
        .font(.system(size: 24))
        .foregroundColor(.secondary)
    }
  }

  func prettyKeyName(_ raw: String) -> String {
    raw.replacingOccurrences(of: "_", with: " ")
      .trimmingCharacters(in: .whitespaces)
      .capitalized
  }
}

// MARK: - Create Rule Button

private struct CreateRuleButton: View {
  @Binding var isPressed: Bool
  @Binding var externalHover: Bool
  @State private var isHovered = false
  @State private var isMouseDown = false

  private var isAnyHovered: Bool {
    isHovered || externalHover
  }

  var body: some View {
    Button {
      isPressed = true
    } label: {
      ZStack {
        Circle()
          .fill(fillColor)
          .frame(width: 80, height: 80)
          .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)

        Image(systemName: "plus.circle.fill")
          .font(.system(size: 40))
          .foregroundColor(iconColor)
      }
      .scaleEffect(isMouseDown ? 0.95 : (isAnyHovered ? 1.05 : 1.0))
      .animation(.easeInOut(duration: 0.15), value: isAnyHovered)
      .animation(.easeInOut(duration: 0.1), value: isMouseDown)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
    }
    .simultaneousGesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in
          isMouseDown = true
        }
        .onEnded { _ in
          isMouseDown = false
        }
    )
  }

  private var fillColor: Color {
    if isMouseDown {
      Color.blue.opacity(0.3)
    } else if isAnyHovered {
      Color.blue.opacity(0.25)
    } else {
      Color.blue.opacity(0.15)
    }
  }

  private var iconColor: Color {
    if isMouseDown {
      .blue.opacity(0.8)
    } else if isAnyHovered {
      .blue
    } else {
      .blue.opacity(0.9)
    }
  }

  private var shadowColor: Color {
    if isMouseDown {
      .clear
    } else if isAnyHovered {
      Color.blue.opacity(0.3)
    } else {
      .clear
    }
  }

  private var shadowRadius: CGFloat {
    isAnyHovered ? 8 : 0
  }

  private var shadowY: CGFloat {
    isAnyHovered ? 2 : 0
  }
}
