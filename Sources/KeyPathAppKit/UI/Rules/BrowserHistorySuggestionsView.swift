import AppKit
import SwiftUI

/// Opt-in UI for scanning browser history to suggest frequently visited websites.
///
/// **Privacy**: Data is processed locally and never transmitted.
/// Requires Full Disk Access permission to read browser history databases.
struct BrowserHistorySuggestionsView: View {
    let onComplete: ([BrowserHistoryScanner.VisitedSite]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: Step = .explanation
    @State private var selectedBrowsers: Set<BrowserHistoryScanner.Browser> = []
    @State private var installedBrowsers: [BrowserHistoryScanner.Browser] = []
    @State private var hasFullDiskAccess = false
    @State private var isScanning = false
    @State private var scannedSites: [BrowserHistoryScanner.VisitedSite] = []
    @State private var selectedSites: Set<UUID> = []
    @State private var errorMessage: String?

    enum Step {
        case explanation
        case browserSelection
        case scanning
        case results
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content based on step
            Group {
                switch currentStep {
                case .explanation:
                    explanationStep
                case .browserSelection:
                    browserSelectionStep
                case .scanning:
                    scanningStep
                case .results:
                    resultsStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer with actions
            footer
        }
        .frame(width: 480, height: 500)
        .task {
            async let browsers = BrowserHistoryScanner.shared.installedBrowsers()
            async let fdaAccess = BrowserHistoryScanner.shared.hasFullDiskAccess()
            installedBrowsers = await browsers
            selectedBrowsers = Set(installedBrowsers)
            hasFullDiskAccess = await fdaAccess
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading) {
                Text("Personalize from Browser History")
                    .font(.headline)
                Text("Suggest websites based on your browsing habits")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("browser-history-close-button")
            .accessibilityLabel("Close")
        }
        .padding()
    }

    // MARK: - Step Views

    private var explanationStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Your Privacy is Protected")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("We'll scan your browser history to find your most-visited websites and suggest shortcuts for them.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("This data stays on your Mac and is never transmitted anywhere.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)

            Spacer()

            // Privacy assurances
            VStack(alignment: .leading, spacing: 12) {
                privacyBullet(icon: "lock.shield", text: "Data is processed locally on your Mac")
                privacyBullet(icon: "network.slash", text: "No data is sent over the network")
                privacyBullet(icon: "trash", text: "History data is discarded after scanning")
                privacyBullet(icon: "hand.raised", text: "You choose which sites to add")
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }

    private func privacyBullet(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 24)
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }

    private var browserSelectionStep: some View {
        VStack(spacing: 20) {
            if !hasFullDiskAccess {
                // FDA warning
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)

                    Text("Full Disk Access Required")
                        .font(.headline)

                    Text("KeyPath needs Full Disk Access permission to read browser history databases.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)

                    Button("Open System Settings") {
                        openFullDiskAccessSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 20)
            }

            if installedBrowsers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "safari")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No supported browsers found")
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select browsers to scan:")
                        .font(.headline)

                    ForEach(installedBrowsers, id: \.self) { browser in
                        Toggle(isOn: Binding(
                            get: { selectedBrowsers.contains(browser) },
                            set: { isOn in
                                if isOn {
                                    selectedBrowsers.insert(browser)
                                } else {
                                    selectedBrowsers.remove(browser)
                                }
                            }
                        )) {
                            HStack {
                                browserIcon(for: browser)
                                    .frame(width: 24, height: 24)
                                Text(browser.displayName)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("browser-history-toggle-\(browser.rawValue)")
                    }
                }
                .padding(.horizontal, 40)
            }

            Spacer()
        }
        .padding()
    }

    private func browserIcon(for browser: BrowserHistoryScanner.Browser) -> some View {
        let iconName = switch browser {
        case .safari: "safari"
        case .chrome: "globe"
        case .firefox: "flame"
        case .arc: "circle.hexagongrid"
        case .brave: "shield"
        case .edge: "globe"
        case .dia: "circle.grid.cross"
        }
        return Image(systemName: iconName)
            .foregroundColor(.accentColor)
    }

    private var scanningStep: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Scanning browser history...")
                .font(.headline)

            Text("This may take a few seconds")
                .font(.callout)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }

    private var resultsStep: some View {
        VStack(spacing: 16) {
            if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text("Scan Failed")
                        .font(.headline)
                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if scannedSites.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No sites found")
                        .font(.headline)
                    Text("No frequently visited websites were found in your browser history.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Your Top Sites")
                            .font(.headline)
                        Spacer()
                        Text("\(selectedSites.count) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(scannedSites) { site in
                                SiteRow(
                                    site: site,
                                    isSelected: selectedSites.contains(site.id),
                                    onSelect: {
                                        if selectedSites.contains(site.id) {
                                            selectedSites.remove(site.id)
                                        } else {
                                            selectedSites.insert(site.id)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if currentStep != .explanation {
                Button("Back") {
                    goBack()
                }
                .accessibilityIdentifier("browser-history-back-button")
            }

            Spacer()

            Button(currentStep == .results ? "Add Selected" : "Continue") {
                goNext()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isNextDisabled)
            .accessibilityIdentifier("browser-history-next-button")
        }
        .padding()
    }

    private var isNextDisabled: Bool {
        switch currentStep {
        case .explanation:
            false
        case .browserSelection:
            selectedBrowsers.isEmpty || !hasFullDiskAccess
        case .scanning:
            true
        case .results:
            selectedSites.isEmpty
        }
    }

    // MARK: - Navigation

    private func goBack() {
        withAnimation {
            switch currentStep {
            case .browserSelection:
                currentStep = .explanation
            case .results:
                currentStep = .browserSelection
            default:
                break
            }
        }
    }

    private func goNext() {
        withAnimation {
            switch currentStep {
            case .explanation:
                currentStep = .browserSelection
            case .browserSelection:
                startScan()
            case .results:
                complete()
            default:
                break
            }
        }
    }

    private func startScan() {
        currentStep = .scanning
        isScanning = true
        errorMessage = nil

        Task {
            do {
                let sites = try await BrowserHistoryScanner.shared.scanHistory(
                    browsers: Array(selectedBrowsers),
                    limit: 20
                )

                await MainActor.run {
                    scannedSites = sites
                    // Pre-select top 5
                    selectedSites = Set(sites.prefix(5).map(\.id))
                    currentStep = .results
                    isScanning = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    currentStep = .results
                    isScanning = false
                }
            }
        }
    }

    private func complete() {
        let selected = scannedSites.filter { selectedSites.contains($0.id) }
        onComplete(selected)
        dismiss()
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Site Row

private struct SiteRow: View {
    let site: BrowserHistoryScanner.VisitedSite
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var favicon: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in onSelect() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityIdentifier("browser-history-toggle-\(site.domain)")

            // Favicon
            Group {
                if let favicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "globe")
                        .frame(width: 20, height: 20)
                        .foregroundColor(.secondary)
                }
            }

            // Domain
            Text(site.domain)
                .font(.system(size: 13))

            Spacer()

            // Visit count
            Text("\(site.visitCount) visits")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .task {
            favicon = await FaviconLoader.shared.favicon(for: site.domain)
        }
    }
}
