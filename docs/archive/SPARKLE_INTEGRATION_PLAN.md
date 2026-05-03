# Sparkle Auto-Update Integration Plan

**Status:** Planned
**Author:** Claude
**Date:** December 2025 (living doc; keep dates/version numbers in sync with current release)
**Effort Estimate:** 2-3 days implementation + testing

## Overview

This document outlines the integration of [Sparkle 2](https://sparkle-project.org/) for automatic updates in KeyPath. Sparkle is the de facto standard for macOS app updates outside the App Store.

## Goals

1. Enable users to receive automatic update notifications
2. Provide seamless in-app updates without manual DMG downloads
3. Maintain security via EdDSA code signatures
4. Handle KeyPath's unique architecture (LaunchDaemon, privileged helper) via InstallerEngine façade
5. Support both manual "Check for Updates" and background checking
6. Keep privacy-friendly defaults (no hardware profiling; HTTPS-only feeds)

## Non-Goals

- Mac App Store distribution (incompatible with our permission requirements)
- Windows/Linux support (Sparkle is macOS-only)
- Delta updates (nice-to-have for future, not MVP)

---

## Architecture

### Current State

```
KeyPath.app
├── Contents/
│   ├── MacOS/KeyPath           # Main executable
│   ├── Library/
│   │   ├── KeyPath/kanata      # Kanata binary
│   │   └── LaunchServices/
│   │       └── com.keypath.helper  # Privileged helper
│   └── Info.plist
```

**Update Challenges:**
- LaunchDaemon (`com.keypath.kanata`) runs as root, references paths in app bundle
- Privileged helper has signature requirements tied to app's Team ID
- Running kanata process holds file handles in the bundle
- InstallerEngine is the only allowed surface for install/repair/uninstall (no direct LaunchDaemon/SM calls)

### Target State

```
┌─────────────────────────────────────────────────────────────┐
│                     Sparkle Update Flow                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Check appcast.xml ──────────────────────────────────►  │
│                                                             │
│  2. Compare versions                                        │
│     └── Current: CFBundleVersion                           │
│     └── Available: sparkle:version                         │
│                                                             │
│  3. Download update (ZIP/DMG)                              │
│     └── Verify EdDSA signature                             │
│                                                             │
│  4. Pre-install hook ◄────────────────────────────────────  │
│     └── InstallerEngine.inspectSystem()                    │
│     └── InstallerEngine.run(intent: .repair, using: broker)│
│         (stop services; prep helper/daemon for swap)       │
│                                                             │
│  5. Sparkle replaces app bundle                            │
│                                                             │
│  6. Relaunch app                                           │
│     └── Post-install hook                                  │
│     └── InstallerEngine.run(intent: .repair, using: broker)│
│         (re-register helper/daemon after bundle swap)      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: Sparkle Integration (Core)

**1.1 Add Sparkle Dependency**

Update `Package.swift`:

```swift
let package = Package(
    name: "KeyPath",
    platforms: [
        .macOS(.v15) // keep aligned with appcast minimumSystemVersion 15.0
    ],
    // ... existing products ...
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        // KeyPathAppKit needs Sparkle for the updater service
        .target(
            name: "KeyPathAppKit",
            dependencies: [
                "KeyPathCore",
                "KeyPathPermissions",
                "KeyPathDaemonLifecycle",
                "KeyPathWizardCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            // ... rest unchanged
        ),
        // ... other targets
    ]
)
```

**1.2 Info.plist Additions**

Add to `Sources/KeyPathApp/Info.plist`:

```xml
<!-- Sparkle Configuration -->
<key>SUFeedURL</key>
<string>https://keypath.app/appcast.xml</string> <!-- stable channel -->
<key>SUAllowsAutomaticUpdates</key>
<true/>

<!-- Optional beta channel (toggle in Settings by switching updater.feedURL) -->
<!-- <key>SUBetaFeedURL</key><string>https://keypath.app/appcast-beta.xml</string> -->

<key>SUPublicEDKey</key>
<string>BASE64_ENCODED_ED25519_PUBLIC_KEY</string>

<!-- Privacy: disable system profiling by default -->
<key>SUEnableSystemProfiling</key>
<false/>

<!-- Allow automatic update checks (user can disable) -->
<key>SUEnableAutomaticChecks</key>
<true/>

<!-- Check interval: 24 hours (86400 seconds) -->
<key>SUScheduledCheckInterval</key>
<integer>86400</integer>

<!-- Show release notes -->
<key>SUShowReleaseNotes</key>
<true/>
```

**1.3 Create UpdateService**

New file: `Sources/KeyPathAppKit/Services/UpdateService.swift`

```swift
import Foundation
import Sparkle

/// Manages application updates via Sparkle framework
@MainActor
public final class UpdateService: NSObject, ObservableObject {

    // MARK: - Singleton

    public static let shared = UpdateService()

    // MARK: - Properties

    private var updaterController: SPUStandardUpdaterController?
    private let broker = PrivilegeBroker() // required for InstallerEngine calls

    @Published public private(set) var canCheckForUpdates = false
    @Published public private(set) var lastUpdateCheckDate: Date?
    @Published public private(set) var automaticallyChecksForUpdates = true

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Initialize the updater. Call once at app startup.
    public func initialize() {
        guard updaterController == nil else { return }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        // Bind to updater properties
        if let updater = updaterController?.updater {
            canCheckForUpdates = updater.canCheckForUpdates
            lastUpdateCheckDate = updater.lastUpdateCheckDate
            automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        }
    }

    /// Manually trigger an update check
    public func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    /// Enable or disable automatic update checks
    public func setAutomaticChecks(enabled: Bool) {
        updaterController?.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
    }

    /// Get the underlying updater for advanced use
    public var updater: SPUUpdater? {
        updaterController?.updater
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateService: SPUUpdaterDelegate {

    /// Called before an update is installed
    public nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdate item: SUAppcastItem
    ) {
        Task { @MainActor in
            await prepareForUpdate()
        }
    }

    /// Called after the app relaunches post-update
    public nonisolated func updaterDidRelaunchApplication(_ updater: SPUUpdater) {
        Task { @MainActor in
            await finalizeUpdate()
        }
    }

    /// Allow update to non-notarized builds during development
    public nonisolated func updater(
        _ updater: SPUUpdater,
        mayPerform updateCheck: SPUUpdateCheck
    ) throws {
        // Allow all update checks
    }

    // MARK: - Update Lifecycle

    @MainActor
    private func prepareForUpdate() async {
        Log.info("[UpdateService] Preparing for update - stopping services")

        // Stop kanata + helper via InstallerEngine (per AGENTS.md)
        do {
            let engine = InstallerEngine()
            _ = try await engine.inspectSystem()
            _ = try await engine.run(intent: .repair, using: broker)
            Log.info("[UpdateService] Services stopped/prepared successfully")
        } catch {
            Log.error("[UpdateService] Failed to stop services: \(error)")
            // Continue anyway - Sparkle will handle it
        }
    }

    @MainActor
    private func finalizeUpdate() async {
        Log.info("[UpdateService] Post-update - repairing services")

        // Re-install/repair services after update
        do {
            let engine = InstallerEngine()
            _ = try await engine.run(intent: .repair, using: broker)
            Log.info("[UpdateService] Services repaired successfully")
        } catch {
            Log.error("[UpdateService] Failed to repair services: \(error)")
            // User will see wizard on next launch if needed
        }
    }
}
```

**1.4 Integrate with App Lifecycle**

Update `Sources/KeyPathAppKit/App.swift` (or equivalent):

```swift
import SwiftUI
import Sparkle

public struct KeyPathApp: App {

    init() {
        // Initialize update service early
        UpdateService.shared.initialize()
    }

    public var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: UpdateService.shared.updater)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

/// SwiftUI wrapper for "Check for Updates" menu item
struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel

    init(updater: SPUUpdater?) {
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: checkForUpdatesViewModel.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    private let updater: SPUUpdater?
    private var cancellable: Any?

    init(updater: SPUUpdater?) {
        self.updater = updater

        if let updater = updater {
            cancellable = updater.publisher(for: \.canCheckForUpdates)
                .assign(to: &$canCheckForUpdates)
        }
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }
}
```

Notes:
- Use `SPUStandardUserDriver` (or custom SwiftUI driver) to surface progress/failure UI and any required restarts when InstallerEngine restarts services.
- Copy should warn that keyboard remapping pauses briefly while services restart.

**1.6 Optional Beta Feed Toggle**

Expose a toggle in Settings to switch feeds at runtime:

```swift
struct UpdateChannelView: View {
    @ObservedObject var service = UpdateService.shared

    enum Channel: String, CaseIterable { case stable, beta }

    @State private var channel: Channel = .stable

    var body: some View {
        Picker("Update channel", selection: $channel) {
            ForEach(Channel.allCases, id: \.self) { channel in
                Text(channel == .stable ? "Stable" : "Beta").tag(channel)
            }
        }
        .onChange(of: channel) { newValue in
            service.updater?.feedURL = URL(string: newValue == .stable
                ? "https://keypath.app/appcast.xml"
                : "https://keypath.app/appcast-beta.xml")
        }
    }
}
```

Guard beta feed behind an opt-in warning and persist the choice in user defaults.

**1.5 Settings UI Integration**

Add to Settings panel:

```swift
struct UpdateSettingsView: View {
    @ObservedObject var updateService = UpdateService.shared

    var body: some View {
        Form {
            Section("Updates") {
                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { updateService.automaticallyChecksForUpdates },
                        set: { updateService.setAutomaticChecks(enabled: $0) }
                    )
                )

                if let lastCheck = updateService.lastUpdateCheckDate {
                    Text("Last checked: \(lastCheck, style: .relative) ago")
                        .foregroundStyle(.secondary)
                }

                Button("Check for Updates Now") {
                    updateService.checkForUpdates()
                }
                .disabled(!updateService.canCheckForUpdates)
            }
        }
    }
}
```

---

### Phase 2: Signing Infrastructure

**2.1 Generate EdDSA Keys**

Run once to create signing keys:

```bash
# Download Sparkle tools (or build from source)
# The generate_keys tool creates an Ed25519 keypair

./bin/generate_keys

# Output:
# A]  The private key has been saved to the Keychain.
# B]  Add the following line to your Info.plist:
#     <key>SUPublicEDKey</key>
#     <string>BASE64_PUBLIC_KEY_HERE</string>
```

**2.2 Create Signing Script**

New file: `Scripts/sign-for-sparkle.sh`

```bash
#!/bin/bash
set -euo pipefail

# Sign a release archive for Sparkle distribution
# Usage: ./Scripts/sign-for-sparkle.sh KeyPath-1.2.0.zip

ARCHIVE="$1"

if [ ! -f "$ARCHIVE" ]; then
    echo "Error: Archive not found: $ARCHIVE"
    exit 1
fi

# Sparkle's sign_update reads the private key from Keychain
# (stored by generate_keys during initial setup)
SIGNATURE=$(./bin/sign_update "$ARCHIVE")

echo "EdDSA Signature for appcast.xml:"
echo "sparkle:edSignature=\"$SIGNATURE\""
echo ""
echo "File size:"
stat -f "length=\"%z\"" "$ARCHIVE"
```

**2.3 Update Build Script**

Modify `Scripts/build-and-sign.sh` to create distributable archive:

```bash
# After notarization, create Sparkle-compatible archive
create_sparkle_archive() {
    local VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
    local ARCHIVE_NAME="KeyPath-${VERSION}.zip"

    echo "Creating Sparkle archive: $ARCHIVE_NAME"

    # Create ZIP (Sparkle prefers ZIP over DMG for seamless updates)
    cd "$DIST_DIR"
    ditto -c -k --keepParent "KeyPath.app" "$ARCHIVE_NAME"

    # Generate signature
    if command -v sign_update &> /dev/null; then
        SIGNATURE=$(sign_update "$ARCHIVE_NAME")
        echo "Sparkle signature: $SIGNATURE"
        echo "$SIGNATURE" > "${ARCHIVE_NAME}.sig"
    else
        echo "Warning: sign_update not found. Run 'brew install sparkle' or build from source."
    fi

    # Output appcast entry
    local SIZE=$(stat -f%z "$ARCHIVE_NAME")
    local DATE=$(date -R)

    cat << EOF > "${ARCHIVE_NAME}.appcast-entry.xml"
<item>
    <title>Version $VERSION</title>
    <sparkle:version>$VERSION</sparkle:version>
    <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
    <pubDate>$DATE</pubDate>
    <enclosure
        url="https://github.com/OWNER/KeyPath/releases/download/v${VERSION}/${ARCHIVE_NAME}"
        sparkle:edSignature="$SIGNATURE"
        length="$SIZE"
        type="application/octet-stream"/>
    <sparkle:releaseNotesLink>
        https://github.com/OWNER/KeyPath/releases/tag/v${VERSION}
    </sparkle:releaseNotesLink>
</item>
EOF

    echo "Appcast entry written to: ${ARCHIVE_NAME}.appcast-entry.xml"
}
```

---

### Phase 3: Appcast Hosting

**3.1 Appcast File Structure**

Create `appcast.xml` (stable) and `appcast-beta.xml` (beta) hosted over HTTPS (keypath.app or GitHub Pages/Release artifacts):

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>KeyPath Updates</title>
        <link>https://keypath.app</link>
        <description>KeyPath keyboard remapping for macOS</description>
        <language>en</language>

        <!-- Latest release -->
        <item>
            <title>Version 1.1.0</title>
            <sparkle:version>1.1.0</sparkle:version>
            <sparkle:shortVersionString>1.1.0</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <pubDate>Wed, 10 Dec 2025 12:00:00 +0000</pubDate>
            <enclosure
                url="https://github.com/OWNER/KeyPath/releases/download/v1.1.0/KeyPath-1.1.0.zip"
                sparkle:edSignature="SIGNATURE_HERE"
                length="12345678"
                type="application/octet-stream"/>
            <sparkle:releaseNotesLink>
                https://github.com/OWNER/KeyPath/releases/tag/v1.1.0
            </sparkle:releaseNotesLink>
        </item>

        <!-- Previous releases for rollback -->
        <item>
            <title>Version 1.0.0</title>
            <sparkle:version>1.0.0</sparkle:version>
            <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <pubDate>Mon, 01 Dec 2025 12:00:00 +0000</pubDate>
            <enclosure
                url="https://github.com/OWNER/KeyPath/releases/download/v1.0.0/KeyPath-1.0.0.zip"
                sparkle:edSignature="SIGNATURE_HERE"
                length="12345678"
                type="application/octet-stream"/>
        </item>
    </channel>
</rss>
```

Notes:
- Beta feed (`appcast-beta.xml`) mirrors the structure above and is selected by switching `updater.feedURL` at runtime (Settings toggle).
- Keep minimumSystemVersion aligned with `Package.swift` deployment target (15.0/Sequoia today).

**3.2 Hosting Options**

| Option | Pros | Cons |
|--------|------|------|
| GitHub Pages | Free, version controlled | Must update repo for each release |
| GitHub Releases | Automatic with CI | Need separate appcast hosting |
| keypath.app | Full control | Hosting cost, maintenance |
| Cloudflare R2 | Cheap, fast CDN | More setup complexity |

**Recommendation:** Use GitHub for both:
- `appcast.xml` in repo root or `docs/` branch (GitHub Pages)
- Release archives attached to GitHub Releases

**3.3 GitHub Actions Workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-14

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Import signing certificate
        env:
          CERTIFICATE_BASE64: ${{ secrets.DEVELOPER_ID_CERTIFICATE }}
          CERTIFICATE_PASSWORD: ${{ secrets.CERTIFICATE_PASSWORD }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          # Create temporary keychain
          security create-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" build.keychain

          # Import certificate
          echo "$CERTIFICATE_BASE64" | base64 --decode > certificate.p12
          security import certificate.p12 -k build.keychain -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" build.keychain

      - name: Import Sparkle signing key
        env:
          SPARKLE_KEY_BASE64: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          # Sparkle stores key in Keychain, or we can use env var
          echo "$SPARKLE_KEY_BASE64" | base64 --decode > sparkle_private_key
          # Store for sign_update tool
          export SPARKLE_PRIVATE_KEY_PATH="$PWD/sparkle_private_key"

      - name: Build and sign
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          APPLE_APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
        run: |
          ./Scripts/build-and-sign.sh

      - name: Create Sparkle archive
        run: |
          VERSION=${GITHUB_REF#refs/tags/v}
          cd dist
          ditto -c -k --keepParent KeyPath.app "KeyPath-${VERSION}.zip"

          # Sign for Sparkle
          SIGNATURE=$(sign_update "KeyPath-${VERSION}.zip" --ed-key-file ../sparkle_private_key)
          echo "SPARKLE_SIGNATURE=$SIGNATURE" >> $GITHUB_ENV
          echo "VERSION=$VERSION" >> $GITHUB_ENV

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            dist/KeyPath-${{ env.VERSION }}.zip
          body: |
            ## KeyPath ${{ env.VERSION }}

            ### Installation
            1. Download `KeyPath-${{ env.VERSION }}.zip`
            2. Extract and move to Applications
            3. Run KeyPath and follow the setup wizard

            ### Sparkle Signature
            ```
            ${{ env.SPARKLE_SIGNATURE }}
            ```

      - name: Update appcast.xml
        run: |
          VERSION=${GITHUB_REF#refs/tags/v}
          ENTRY="dist/KeyPath-${VERSION}.appcast-entry.xml"
          test -f "$ENTRY" || (echo "appcast entry missing" && exit 1)
          # Enforce HTTPS URLs and embed signature
          python3 Scripts/ci/update_appcast.py --entry "$ENTRY" --feed appcast.xml --channel stable
          python3 Scripts/ci/update_appcast.py --entry "$ENTRY" --feed appcast-beta.xml --channel beta --optional
          python3 Scripts/ci/validate_appcast.py --feed appcast.xml --require-https --require-signature
          git status --short

      - name: Publish appcast (Pages or branch)
        run: |
          # Example: commit to pages branch; keep deterministic so release fails if publish fails
          ./Scripts/ci/publish_appcast.sh
```

---

### Phase 4: Version Management

**4.1 Automate Version Bumping**

Create `Scripts/bump-version.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Bump version in Info.plist files
# Usage: ./Scripts/bump-version.sh 1.2.0

NEW_VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/Scripts}"

# Update main app Info.plist
INFO_PLIST="$REPO_ROOT/Sources/KeyPathApp/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$INFO_PLIST"

echo "Updated version to $NEW_VERSION in:"
echo "  - $INFO_PLIST"

# Optionally update helper Info.plist if version matters there
HELPER_PLIST="$REPO_ROOT/Sources/KeyPathHelper/Info.plist"
if [ -f "$HELPER_PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$HELPER_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$HELPER_PLIST" 2>/dev/null || true
    echo "  - $HELPER_PLIST"
fi

echo ""
echo "Next steps:"
echo "  1. git add -A && git commit -m 'chore: bump version to $NEW_VERSION'"
echo "  2. git tag v$NEW_VERSION"
echo "  3. git push origin main --tags"
```

**4.2 Version Constants**

Add to `Sources/KeyPathCore/Version.swift`:

```swift
public enum AppVersion {
    /// Current app version (matches CFBundleShortVersionString)
    public static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Build number (matches CFBundleVersion)
    public static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// Full version string for display
    public static var displayString: String {
        "\(current) (\(build))"
    }
}
```

---

### Phase 5: Testing

**5.1 Local Testing Setup**

Create `Scripts/test-sparkle-update.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Test Sparkle updates locally
# 1. Builds a "fake old version" (1.0.0)
# 2. Builds a "new version" (1.0.1)
# 3. Hosts appcast locally
# 4. Runs old version to test update flow

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/Scripts}"
TEST_DIR="/tmp/sparkle-test"

mkdir -p "$TEST_DIR"

echo "=== Building 'old' version 1.0.0 ==="
"$SCRIPT_DIR/bump-version.sh" "1.0.0"
SKIP_NOTARIZE=1 "$REPO_ROOT/build.sh"
cp -R ~/Applications/KeyPath.app "$TEST_DIR/KeyPath-1.0.0.app"

echo "=== Building 'new' version 1.0.1 ==="
"$SCRIPT_DIR/bump-version.sh" "1.0.1"
SKIP_NOTARIZE=1 "$REPO_ROOT/build.sh"
cd "$TEST_DIR"
ditto -c -k --keepParent ~/Applications/KeyPath.app "KeyPath-1.0.1.zip"
SIGNATURE=$(sign_update "KeyPath-1.0.1.zip")
SIZE=$(stat -f%z "KeyPath-1.0.1.zip")

echo "=== Creating test appcast ==="
cat > "$TEST_DIR/appcast.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel>
    <title>KeyPath Test Updates</title>
    <item>
        <title>Version 1.0.1</title>
        <sparkle:version>1.0.1</sparkle:version>
        <sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
        <pubDate>$(date -R)</pubDate>
        <enclosure
            url="http://localhost:8000/KeyPath-1.0.1.zip"
            sparkle:edSignature="$SIGNATURE"
            length="$SIZE"
            type="application/octet-stream"/>
    </item>
</channel>
</rss>
EOF

echo "=== Starting local server ==="
cd "$TEST_DIR"
python3 -m http.server 8000 &
SERVER_PID=$!

echo "=== Modifying old app to use local appcast ==="
# Temporarily point SUFeedURL to localhost
/usr/libexec/PlistBuddy -c "Set :SUFeedURL http://localhost:8000/appcast.xml" \
    "$TEST_DIR/KeyPath-1.0.0.app/Contents/Info.plist"

echo ""
echo "=== Test Setup Complete ==="
echo "1. Run: open '$TEST_DIR/KeyPath-1.0.0.app'"
echo "2. Go to KeyPath > Check for Updates"
echo "3. Should offer update to 1.0.1"
echo ""
echo "Press Enter to stop test server and cleanup..."
read

kill $SERVER_PID
rm -rf "$TEST_DIR"
```

Improvements:
- Mock time/check interval for deterministic tests (avoid `Thread.sleep`); drive Sparkle timer via injected clock.
- Use a stub `PrivilegeBroker` so pre/post hooks exercise InstallerEngine without requiring privileges in CI.
- Add an automated headless test that asserts `prepareForUpdate` and `finalizeUpdate` delegate to InstallerEngine with `.repair` intent.

**5.2 Unit Tests**

Add tests for UpdateService (mock Sparkle):

```swift
@testable import KeyPathAppKit
import XCTest

final class UpdateServiceTests: XCTestCase {

    func testServiceInitialization() {
        // UpdateService should initialize without crashing
        // (Sparkle creates UI elements, so this tests basic integration)
        let service = UpdateService.shared
        XCTAssertNotNil(service)
    }

    func testVersionParsing() {
        // Test version string handling
        let current = AppVersion.current
        XCTAssertFalse(current.isEmpty)

        // Version should be semver format
        let components = current.split(separator: ".")
        XCTAssertGreaterThanOrEqual(components.count, 2)
    }
}
```

---

## Rollout Plan

### Week 1: Core Integration
- [ ] Add Sparkle package dependency
- [ ] Create UpdateService
- [ ] Add "Check for Updates" menu item
- [ ] Update Info.plist with feed URL

### Week 2: Signing & Hosting
- [ ] Generate EdDSA keypair
- [ ] Update build script for Sparkle archives
- [ ] Create initial appcast.xml
- [ ] Set up hosting (GitHub Pages recommended)

### Week 3: CI/CD & Testing
- [ ] Create GitHub Actions release workflow
- [ ] Add version bump script
- [ ] Local update testing
- [ ] Document release process
- [ ] Add appcast validation (HTTPS, signatures present, min system version matches build)
- [ ] Add headless test that verify pre/post hooks call InstallerEngine with `.repair` + broker

### Week 4: Beta Testing
- [ ] Release beta with Sparkle enabled
- [ ] Test update from 1.0.0 → 1.1.0-beta
- [ ] Verify daemon stop/restart during update
- [ ] Fix any issues found

---

## Security Considerations

### EdDSA Signatures
- Private key stored in macOS Keychain (never committed to repo)
- Public key embedded in app bundle
- All updates verified before installation

### Code Signing
- App remains Developer ID signed
- Notarization ensures Gatekeeper approval
- Helper signature requirements unchanged

### Network Security
- Appcast fetched over HTTPS only
- Update archives fetched over HTTPS
- No sensitive data in appcast

### Privacy
- `SUEnableSystemProfiling` set to false; no hardware profile submissions by default.

### Attack Vectors Mitigated
- **MITM attacks**: EdDSA signature verification
- **Downgrade attacks**: Sparkle compares version numbers
- **Tampered updates**: Signature verification before install
- **Compromised appcast**: Signature on each update, not feed

---

## Failure Modes & Recovery

### Update Fails Mid-Install
**Symptom:** App won't launch, daemon in broken state
**Recovery:**
1. User downloads fresh copy from website
2. `InstallerEngine.run(intent: .repair, using: broker)` on launch

### Services Not Restarted After Update
**Symptom:** Kanata not running after update
**Recovery:**
1. `UpdateService.finalizeUpdate()` runs `.repair` intent
2. If that fails, wizard prompts user on next launch
3. Provide in-app CTA: "Restart Keyboard Service" to re-run repair via InstallerEngine

### Signature Mismatch
**Symptom:** Update offered but fails to install
**Recovery:**
1. Sparkle shows error dialog
2. User can retry or download manually
3. Check if correct private key was used for signing

### Appcast Unreachable
**Symptom:** "Check for Updates" fails silently
**Recovery:**
1. Sparkle shows "no updates available" or network error
2. User can check manually via website
3. Monitor appcast hosting uptime

---

## Open Questions

1. **Beta rollout policy?** - Default opt-in/out, and when to flip feeds automatically.
2. **Release notes format?** - Markdown in appcast or link to GitHub releases?
3. **Minimum version enforcement?** - Force update for security issues?
4. **Analytics?** - Track update success rates? (Privacy implications)

---

## References

- [Sparkle Documentation](https://sparkle-project.org/documentation/)
- [Sparkle GitHub](https://github.com/sparkle-project/Sparkle)
- [Publishing Signed Updates](https://sparkle-project.org/documentation/publishing/)
- [SwiftUI Integration Guide](https://sparkle-project.org/documentation/programmatic-setup/)

---

## Appendix: File Changes Summary

| File | Change |
|------|--------|
| `Package.swift` | Add Sparkle dependency |
| `Sources/KeyPathApp/Info.plist` | Add SUFeedURL, SUPublicEDKey |
| `Sources/KeyPathAppKit/Services/UpdateService.swift` | New file |
| `Sources/KeyPathAppKit/App.swift` | Initialize UpdateService, add menu command |
| `Sources/KeyPathAppKit/UI/Settings/UpdateSettingsView.swift` | New file |
| `Sources/KeyPathCore/Version.swift` | New file |
| `Scripts/bump-version.sh` | New file |
| `Scripts/sign-for-sparkle.sh` | New file |
| `Scripts/build-and-sign.sh` | Add Sparkle archive creation |
| `.github/workflows/release.yml` | New file |
| `appcast.xml` | New file (hosted separately) |
