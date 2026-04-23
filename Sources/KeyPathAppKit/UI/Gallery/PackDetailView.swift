// M1 Phase 3 — Pack Detail view, Direction-C flavored.
// Spec: docs/design/sprint-1/pack-detail-directions.md (Direction C).
//
// M1 scope: this ships as a sheet over the Gallery window. The full
// Direction-C behavior (real keyboard canvas dims behind the panel,
// affected keys glow with pending tint, install moment is a continuity
// transition) depends on having the main keyboard always visible behind
// Pack Detail — which KeyPath's current window model (main window is a
// splash) does not yet support. For M1 we approximate by:
//   - Presenting Pack Detail as a sheet with the Direction-C visual
//     vocabulary (affected-keys preview inside the sheet, animated
//     pending tint that transitions to installed state).
//   - Showing a confirmation toast after install/uninstall with Undo.
// The real in-place modification coupling is a follow-up once the main
// window grows a persistent keyboard canvas.

import AppKit
import SwiftUI

struct PackDetailView: View {
    let pack: Pack
    @Environment(\.dismiss) private var dismiss
    @Environment(KanataViewModel.self) private var kanataManager

    @State private var isInstalled = false
    @State private var isWorking = false
    @State private var justInstalled = false
    @State private var justUninstalled = false
    @State private var errorMessage: String?
    @State private var quickSettingValues: [String: Int] = [:]
    @State private var lastUndoSnapshot: UndoSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    affectedKeyboardPreview
                    descriptionBlock
                    if !pack.quickSettings.isEmpty {
                        quickSettingsBlock
                    }
                    bindingsBlock
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 640)
        .task {
            await refreshInstallState()
            loadDefaultQuickSettings()
        }
        .overlay(toastOverlay, alignment: .bottom)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            heroIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(pack.category.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(pack.name)
                        .font(.system(size: 20, weight: .semibold))
                    if isInstalled {
                        installedBadge
                    }
                }
                Text(pack.tagline)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(pack.author) · v\(pack.version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.quaternary))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    /// Larger version of the pack card's hero icon, for Pack Detail's header.
    private var heroIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.16),
                            Color.accentColor.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.5)
                )
                .frame(width: 72, height: 72)

            if let secondary = pack.iconSecondarySymbol {
                HStack(spacing: 3) {
                    Image(systemName: pack.iconSymbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: secondary)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                }
            } else {
                Image(systemName: pack.iconSymbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }

    private var installedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("On")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
        }
    }

    // MARK: - Affected-keys preview

    /// Visual approximation of Direction C's "affected keys glow" on the
    /// real keyboard. Since we don't have a main-window keyboard in M1,
    /// this lives inside the sheet and animates the keys from default →
    /// pending → installed as the user interacts.
    private var affectedKeyboardPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.05))
            HStack(spacing: 8) {
                ForEach(Array(pack.affectedKeys.prefix(8).enumerated()), id: \.offset) { _, key in
                    KeycapChipView(
                        label: displayLabel(for: key),
                        state: previewKeyState
                    )
                }
                if pack.affectedKeys.count > 8 {
                    Text("+\(pack.affectedKeys.count - 8)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(height: 74)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var previewKeyState: KeycapChipView.KeyState {
        if justInstalled { return .installed }
        if isInstalled { return .installed }
        if justUninstalled { return .pending }
        // Pre-install resting state: show what will happen via pending tint.
        return .pending
    }

    // MARK: - Description

    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pack.shortDescription)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(pack.longDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
    }

    // MARK: - Quick settings

    private var quickSettingsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Quick settings")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(pack.quickSettings) { setting in
                quickSettingRow(setting)
            }
        }
    }

    @ViewBuilder
    private func quickSettingRow(_ setting: PackQuickSetting) -> some View {
        switch setting.kind {
        case let .slider(_, min: lo, max: hi, step: step, unitSuffix: suffix):
            HStack(spacing: 10) {
                Text(setting.label)
                    .font(.system(size: 12))
                    .frame(width: 110, alignment: .leading)
                Slider(
                    value: sliderBinding(for: setting.id),
                    in: Double(lo) ... Double(hi),
                    step: Double(step)
                )
                Text("\(quickSettingValues[setting.id] ?? 0)\(suffix)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
    }

    // MARK: - Binding list

    private var bindingsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("What this will change")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(pack.bindings.enumerated()), id: \.offset) { _, template in
                bindingRow(template)
            }
        }
    }

    private func bindingRow(_ template: PackBindingTemplate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            KeycapChipView(label: displayLabel(for: template.input), state: previewKeyState)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                if let title = template.title {
                    Text(title).font(.system(size: 12, weight: .medium))
                }
                if let hold = template.holdOutput, !hold.isEmpty {
                    Text("Tap: \(template.output)  ·  Hold: \(hold)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Output: \(template.output)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let notes = template.notes {
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.85))
                        .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if isInstalled {
                Button("Turn Off", role: .destructive) { Task { await uninstall() } }
                    .disabled(isWorking)
            } else {
                Button("Turn On") { Task { await install() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Toast overlay

    @ViewBuilder
    private var toastOverlay: some View {
        if let error = errorMessage {
            toastView(
                icon: "exclamationmark.triangle.fill",
                iconColor: .orange,
                message: error,
                action: nil
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 72)
        } else if justInstalled {
            toastView(
                icon: "checkmark.circle.fill",
                iconColor: .green,
                message: installedToastMessage,
                action: ("Undo", { Task { await undoInstall() } })
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 72)
        } else if justUninstalled {
            toastView(
                icon: "checkmark.circle.fill",
                iconColor: .green,
                message: "\(pack.name) turned off.",
                action: ("Undo", { Task { await undoUninstall() } })
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 72)
        }
    }

    private var installedToastMessage: String {
        pack.bindings.count == 1
            ? "\(pack.name) turned on."
            : "\(pack.name) turned on · \(pack.bindings.count) bindings added."
    }

    private func toastView(
        icon: String,
        iconColor: Color,
        message: String,
        action: (label: String, handler: () -> Void)?
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            if let action {
                Button(action.label, action: action.handler)
                    .buttonStyle(.link)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
    }

    // MARK: - State actions

    private func sliderBinding(for id: String) -> Binding<Double> {
        Binding(
            get: { Double(quickSettingValues[id] ?? 0) },
            set: { quickSettingValues[id] = Int($0) }
        )
    }

    private func loadDefaultQuickSettings() {
        for setting in pack.quickSettings {
            if quickSettingValues[setting.id] == nil,
               let defaultVal = setting.defaultSliderValue
            {
                quickSettingValues[setting.id] = defaultVal
            }
        }
    }

    private func refreshInstallState() async {
        let installed = await PackInstaller.shared.isInstalled(packID: pack.id)
        let saved = await PackInstaller.shared.quickSettings(for: pack.id)
        await MainActor.run {
            isInstalled = installed
            if installed, !saved.isEmpty {
                quickSettingValues = saved
            }
        }
    }

    private func install() async {
        isWorking = true
        errorMessage = nil
        do {
            let manager = kanataManager.underlyingManager.ruleCollectionsManager
            _ = try await PackInstaller.shared.install(
                pack,
                quickSettingValues: quickSettingValues,
                manager: manager
            )
            lastUndoSnapshot = .init(quickSettingValues: quickSettingValues)
            await refreshInstallState()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                justInstalled = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) { justInstalled = false }
                }
            }
        } catch {
            withAnimation { errorMessage = error.localizedDescription }
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) { errorMessage = nil }
                }
            }
        }
        isWorking = false
    }

    private func uninstall() async {
        isWorking = true
        errorMessage = nil
        do {
            let manager = kanataManager.underlyingManager.ruleCollectionsManager
            try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager)
            await refreshInstallState()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                justUninstalled = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) { justUninstalled = false }
                }
            }
        } catch {
            withAnimation { errorMessage = error.localizedDescription }
        }
        isWorking = false
    }

    private func undoInstall() async {
        withAnimation(.easeOut(duration: 0.2)) { justInstalled = false }
        await uninstall()
    }

    private func undoUninstall() async {
        withAnimation(.easeOut(duration: 0.2)) { justUninstalled = false }
        // Re-install with the saved settings from just before uninstall.
        if let snap = lastUndoSnapshot {
            quickSettingValues = snap.quickSettingValues
        }
        await install()
    }

    // MARK: - Helpers

    private func displayLabel(for kanataKey: String) -> String {
        switch kanataKey.lowercased() {
        case "caps": "⇪"
        case "lmet": "⌘"
        case "rmet": "⌘"
        case "lalt": "⌥"
        case "ralt": "⌥"
        case "lctl": "⌃"
        case "rctl": "⌃"
        case "lsft": "⇧"
        case "rsft": "⇧"
        case "spc": "Space"
        case "ret", "enter": "⏎"
        case "tab": "⇥"
        case "esc": "⎋"
        case "bspc", "backspace": "⌫"
        case "del": "⌦"
        case "minus": "-"
        case "equal": "="
        default: kanataKey
        }
    }
}

// MARK: - Keycap chip

/// Small keycap visual used in Pack Detail to represent affected keys.
/// Mirrors the chip style in PackCardView but renders larger.
struct KeycapChipView: View {
    enum KeyState {
        /// Default state — what the key does today, no pending change.
        case inert
        /// Pending state — this key will change if the user installs.
        case pending
        /// Installed state — the pack is active and this key is taking effect.
        case installed
    }

    let label: String
    let state: KeyState

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(foreground)
            .frame(minWidth: 36, minHeight: 36)
            .padding(.horizontal, 8)
            .background(background)
            .overlay(border)
            .animation(.easeInOut(duration: 0.24), value: state)
    }

    private var foreground: Color {
        switch state {
        case .inert: .primary.opacity(0.7)
        case .pending: .accentColor.opacity(0.85)
        case .installed: .accentColor
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fillColor)
    }

    private var fillColor: Color {
        switch state {
        case .inert: Color(nsColor: .controlBackgroundColor)
        case .pending: Color.accentColor.opacity(0.08)
        case .installed: Color.accentColor.opacity(0.14)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(borderColor, lineWidth: state == .inert ? 0.5 : 1)
    }

    private var borderColor: Color {
        switch state {
        case .inert: Color(nsColor: .separatorColor)
        case .pending: Color.accentColor.opacity(0.5)
        case .installed: Color.accentColor.opacity(0.7)
        }
    }
}

// MARK: - Undo snapshot

private struct UndoSnapshot {
    let quickSettingValues: [String: Int]
}
