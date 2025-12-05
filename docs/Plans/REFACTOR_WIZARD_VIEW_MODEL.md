# Refactoring Task: Extract WizardViewModel from InstallationWizardView

## Problem Statement

`InstallationWizardView.swift` (1,775 lines) is a **God class** that violates SwiftUI best practices by mixing UI rendering with state management, business logic, and side effects. This makes it:

1. **Untestable**: All state is private `@State` properties that can't be tested in isolation
2. **Hard to maintain**: Changes risk breaking unrelated functionality
3. **Hard to debug**: State mutations are scattered across 30+ methods
4. **Poor separation of concerns**: View knows about TCP, daemon management, Login Items polling, etc.

### Current State Properties (40+ total)

```swift
// Manager objects (4)
@StateObject private var stateManager = WizardStateManager()
@StateObject private var stateMachine = WizardStateMachine()
@StateObject private var autoFixer = WizardAutoFixerManager()
@StateObject private var navigationCoordinator = WizardNavigationCoordinator()
@State private var asyncOperationManager = WizardAsyncOperationManager()
@State private var toastManager = WizardToastManager()

// UI State (16+)
@State private var isValidating: Bool = true
@State private var preflightStart = Date()
@State private var evaluationProgress: Double = 0.0
@State private var systemState: WizardSystemState = .initializing
@State private var currentIssues: [WizardIssue] = []
@State private var showAllSummaryItems: Bool = false
@State private var navSequence: [WizardPage] = []
@State private var inFlightFixActions: Set<AutoFixAction> = []
@State private var showingBackgroundApprovalPrompt = false
@State private var currentFixAction: AutoFixAction?
@State private var fixInFlight: Bool = false
@State private var lastRefreshAt: Date?

// Task management (5)
@State private var refreshTask: Task<Void, Never>?
@State private var isForceClosing = false
@State private var loginItemsPollingTask: Task<Void, Never>?
@State private var statusBannerMessage: String?
@State private var statusBannerTimestamp: Date?

// Dialog state (3)
@State private var showingStartConfirmation = false
@State private var startConfirmationResult: CheckedContinuation<Bool, Never>?
@State private var showingCloseConfirmation = false

// Focus state
@FocusState private var hasKeyboardFocus: Bool
```

### Business Logic in View (Methods that should be in ViewModel)

| Method | Lines | Responsibility |
|--------|-------|----------------|
| `setupWizard()` | 60 | Initialization, navigation |
| `performInitialStateCheck()` | 100 | State detection orchestration |
| `monitorSystemState()` | 25 | Background polling loop |
| `performSmartStateCheck()` | 70 | Targeted state refresh |
| `performAutoFix()` | 130 | Fix orchestration with fallbacks |
| `attemptFastRestartFix()` | 30 | Fast-path restart logic |
| `attemptAutoFixActions()` | 40 | Auto-fix action execution |
| `performAutoFix(_:suppressToast:)` | 165 | Single action fix with timeout |
| `refreshState()` | 35 | State refresh with debouncing |
| `applySystemStateResult(_:)` | 50 | State update and navigation |
| `startKanataService()` | 35 | Service start orchestration |
| `startLoginItemsApprovalPolling()` | 45 | Background approval polling |
| `forciblyCloseWizard()` | 45 | Nuclear shutdown |

**Total: ~830 lines of business logic that doesn't belong in a View**

---

## Target Architecture

### Before (Current)
```
InstallationWizardView (1,775 lines)
├── 40+ @State properties
├── Business logic methods
├── Navigation logic
├── Fix orchestration
├── Polling tasks
└── UI rendering
```

### After (Target)
```
InstallationWizardView (~300 lines)
├── @StateObject var viewModel: WizardViewModel
├── pageContent() - delegates to child views
└── Minimal onChange/onAppear wiring

WizardViewModel (~800 lines) : ObservableObject
├── @Published state properties
├── All business logic
├── Task management
└── Fix orchestration

Supporting Types (existing, unchanged)
├── WizardStateManager
├── WizardStateMachine
├── WizardNavigationCoordinator
├── WizardAsyncOperationManager
└── WizardAutoFixerManager
```

---

## Implementation Steps

### Step 1: Create WizardViewModel.swift

Location: `Sources/KeyPathAppKit/InstallationWizard/UI/WizardViewModel.swift`

```swift
import Foundation
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

@MainActor
final class WizardViewModel: ObservableObject {
    // MARK: - Dependencies (injected or created)
    let stateManager = WizardStateManager()
    let stateMachine = WizardStateMachine()
    let autoFixer = WizardAutoFixerManager()
    let navigationCoordinator = WizardNavigationCoordinator()
    var asyncOperationManager = WizardAsyncOperationManager()
    var toastManager = WizardToastManager()
    let stateInterpreter = WizardStateInterpreter()

    // External dependency
    weak var kanataManager: RuntimeCoordinator?

    // MARK: - Published State
    @Published var isValidating: Bool = true
    @Published var evaluationProgress: Double = 0.0
    @Published var systemState: WizardSystemState = .initializing
    @Published var currentIssues: [WizardIssue] = []
    @Published var showAllSummaryItems: Bool = false
    @Published var navSequence: [WizardPage] = []
    @Published var fixInFlight: Bool = false
    @Published var statusBannerMessage: String?

    // Dialog state
    @Published var showingBackgroundApprovalPrompt = false
    @Published var showingStartConfirmation = false
    @Published var showingCloseConfirmation = false

    // MARK: - Internal State (not published)
    var inFlightFixActions: Set<AutoFixAction> = []
    var currentFixAction: AutoFixAction?
    var lastRefreshAt: Date?
    var preflightStart = Date()
    var statusBannerTimestamp: Date?
    var isForceClosing = false

    // Task handles
    var refreshTask: Task<Void, Never>?
    var loginItemsPollingTask: Task<Void, Never>?
    var startConfirmationResult: CheckedContinuation<Bool, Never>?

    // MARK: - Initialization
    init() {}

    func configure(kanataManager: RuntimeCoordinator, initialPage: WizardPage?) {
        self.kanataManager = kanataManager
        // Setup logic moved from setupWizard()
    }

    // MARK: - Public Actions (called from View)
    func setup(initialPage: WizardPage?) async { ... }
    func refresh() { ... }
    func performAutoFix() { ... }
    func performAutoFix(_ action: AutoFixAction, suppressToast: Bool) async -> Bool { ... }
    func startService() { ... }
    func handleCloseButtonTapped() { ... }
    func forciblyClose() { ... }
    func confirmStartService() async -> Bool { ... }
    func openLoginItemsSettings() { ... }

    // MARK: - Internal Logic (moved from View)
    // All the private methods from InstallationWizardView
}
```

### Step 2: Move Methods to ViewModel

Move these methods **unchanged** (logic preservation):

1. `setupWizard()` → `setup(initialPage:)`
2. `performInitialStateCheck(retryAllowed:)` → keep as private
3. `monitorSystemState()` → keep as private
4. `performSmartStateCheck(retryAllowed:)` → keep as private
5. `performAutoFix()` → public, called from view
6. `attemptFastRestartFix()` → private
7. `attemptAutoFixActions()` → private
8. `performAutoFix(_:suppressToast:)` → public
9. `refreshState()` → `refresh()`
10. `applySystemStateResult(_:)` → private
11. `sanitizedIssues(from:for:)` → private
12. `shouldSuppressCommunicationIssues(for:)` → private
13. `isCommunicationIssue(_:)` → private
14. `startKanataService()` → `startService()`
15. `handleCloseButtonTapped()` → public
16. `forceInstantClose()` → private
17. `dismissAndRefreshMainScreen()` → needs View dismiss callback
18. `performBackgroundCleanup()` → private
19. `forciblyCloseWizard()` → `forciblyClose()`
20. `showStartConfirmation()` → `confirmStartService()`
21. `startLoginItemsApprovalPolling()` → private
22. `stopLoginItemsApprovalPolling()` → private
23. `openLoginItemsSettings()` → public
24. `showStatusBanner(_:)` → private
25. `autoNavigateIfSingleIssue(in:state:)` → private
26. `preferredDetailPage(for:issues:)` → private
27. `cachedPreferredPage()` → private
28. `getCurrentOperationName()` → public (for UI)
29. `getCurrentOperationProgress()` → public
30. `isCurrentOperationIndeterminate()` → public
31. `getAutoFixActionDescription(_:)` → public
32. `getDetailedErrorMessage(for:actionDescription:)` → private
33. `describeServiceState()` → private
34. Helper methods for navigation

### Step 3: Handle View Dismissal

The ViewModel needs a way to dismiss the view. Options:

**Option A: Callback injection (recommended)**
```swift
class WizardViewModel: ObservableObject {
    var onDismiss: (() -> Void)?

    func dismissAndRefreshMainScreen() {
        stopLoginItemsApprovalPolling()
        NotificationCenter.default.post(name: .kp_startupRevalidate, object: nil)
        onDismiss?()
    }
}

// In View
.onAppear {
    viewModel.onDismiss = { dismiss() }
}
```

**Option B: Published shouldDismiss flag**
```swift
@Published var shouldDismiss = false

// In View
.onChange(of: viewModel.shouldDismiss) { _, shouldDismiss in
    if shouldDismiss { dismiss() }
}
```

### Step 4: Simplify InstallationWizardView

After extraction, the view should look like:

```swift
struct InstallationWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataViewModel: KanataViewModel
    @StateObject private var viewModel = WizardViewModel()

    var initialPage: WizardPage?

    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        ZStack {
            // Status banner (if showing)
            statusBannerView

            // Background
            WizardDesign.Colors.wizardBackground.ignoresSafeArea()

            // Main content
            VStack(spacing: 0) {
                pageContent()
                    .id(viewModel.navigationCoordinator.currentPage)
                    .overlay { operationProgressOverlay }
            }
            .frame(...)
        }
        .withToasts(viewModel.toastManager)
        .environmentObject(viewModel.navigationCoordinator)
        .focused($hasKeyboardFocus)
        .onAppear { setupView() }
        .onChange(of: viewModel.isValidating) { ... }
        // Other onChange handlers for UI-only concerns
        .overlay(alignment: .topTrailing) { closeButtonOverlay }
        .modifier(KeyboardNavigationModifier(...))
        .alert(...) // Dialogs bound to viewModel published properties
    }

    private func setupView() {
        hasKeyboardFocus = true
        viewModel.onDismiss = { dismiss() }
        Task { await viewModel.setup(
            kanataManager: kanataViewModel.underlyingManager,
            initialPage: initialPage
        )}
    }

    @ViewBuilder
    private func pageContent() -> some View {
        // Switch on viewModel.navigationCoordinator.currentPage
        // Pass viewModel properties to child page views
    }
}
```

### Step 5: Update Child Page Views

Child views currently receive many parameters. After refactoring, they should receive the ViewModel:

**Before:**
```swift
WizardSummaryPage(
    systemState: systemState,
    issues: currentIssues,
    stateInterpreter: stateInterpreter,
    onStartService: startKanataService,
    onDismiss: { dismissAndRefreshMainScreen() },
    onNavigateToPage: { page in navigationCoordinator.navigateToPage(page) },
    isValidating: isValidating,
    showAllItems: $showAllSummaryItems,
    navSequence: $navSequence
)
```

**After (Option A - Pass ViewModel):**
```swift
WizardSummaryPage(viewModel: viewModel)
```

**After (Option B - Keep explicit parameters, bind to ViewModel):**
```swift
WizardSummaryPage(
    systemState: viewModel.systemState,
    issues: viewModel.currentIssues,
    stateInterpreter: viewModel.stateInterpreter,
    onStartService: { viewModel.startService() },
    onDismiss: { viewModel.dismissAndRefreshMainScreen() },
    onNavigateToPage: { viewModel.navigationCoordinator.navigateToPage($0) },
    isValidating: viewModel.isValidating,
    showAllItems: $viewModel.showAllSummaryItems,
    navSequence: $viewModel.navSequence
)
```

Option B is preferred for incremental migration - child views don't need changes.

---

## Testing Strategy

### Unit Tests for WizardViewModel

Create: `Tests/KeyPathTests/InstallationWizard/WizardViewModelTests.swift`

```swift
@MainActor
final class WizardViewModelTests: KeyPathTestCase {
    var viewModel: WizardViewModel!
    var mockKanataManager: MockRuntimeCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        mockKanataManager = MockRuntimeCoordinator()
        viewModel = WizardViewModel()
        viewModel.configure(kanataManager: mockKanataManager, initialPage: nil)
    }

    func testInitialState() {
        XCTAssertTrue(viewModel.isValidating)
        XCTAssertEqual(viewModel.systemState, .initializing)
        XCTAssertTrue(viewModel.currentIssues.isEmpty)
    }

    func testRefreshDebouncing() async {
        viewModel.refresh()
        viewModel.lastRefreshAt = Date()
        viewModel.refresh() // Should be debounced
        // Assert only one refresh happened
    }

    func testAutoFixGuardsPreventsDoubleFix() async {
        viewModel.fixInFlight = true
        let result = await viewModel.performAutoFix(.installBundledKanata, suppressToast: true)
        XCTAssertFalse(result) // Should be blocked
    }

    func testForciblyCloseSetsFlagAndCancels() {
        viewModel.refreshTask = Task { }
        viewModel.forciblyClose()
        XCTAssertTrue(viewModel.isForceClosing)
        XCTAssertNil(viewModel.refreshTask) // Should be cancelled
    }
}
```

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Breaking existing functionality | Move code unchanged first, then refactor |
| View dismiss timing issues | Test dismiss callback thoroughly |
| Task cancellation bugs | Preserve exact cancellation logic |
| Navigation state sync | Keep navigationCoordinator as @StateObject |
| @Published performance | Only publish what UI actually observes |

---

## Definition of Done

- [ ] `WizardViewModel.swift` created with all business logic
- [ ] `InstallationWizardView.swift` reduced to ~300 lines
- [ ] All existing functionality preserved (manual QA)
- [ ] Unit tests for ViewModel core methods
- [ ] No new warnings or errors
- [ ] Wizard opens, validates, fixes, and closes correctly

---

## Estimated Effort

| Phase | Time |
|-------|------|
| Create ViewModel, move state | 1-2 hours |
| Move methods unchanged | 1-2 hours |
| Wire View to ViewModel | 1 hour |
| Fix compilation errors | 30 min |
| Manual QA testing | 30 min |
| Write unit tests | 1 hour |
| **Total** | **4-6 hours** |

---

## References

- Original file: `Sources/KeyPathAppKit/InstallationWizard/UI/InstallationWizardView.swift`
- Code review: `docs/CODE_REVIEW_REPORT.md`
- SwiftUI MVVM patterns: Apple's "App essentials in SwiftUI" WWDC sessions
