@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// The overlay Mapper saves on capture and has no Save button, so a save that
/// declines must say so, in the status the overlay shows and in the log.
@MainActor
final class MapperAutosaveVisibilityTests: KeyPathTestCase {
    private func sequence(_ key: String, keyCode: Int64) -> KeySequence {
        KeySequence(keys: [KeyPress(baseKey: key, modifiers: [], keyCode: keyCode)], captureMode: .single)
    }

    func testCaptureWithoutARuntimeCoordinatorReportsInsteadOfVanishing() {
        let vm = MapperViewModel()
        vm.kanataManager = nil
        vm.inputSequence = sequence("grave", keyCode: 50)
        vm.outputSequence = sequence("mute", keyCode: 1007)
        XCTAssertTrue(vm.canSave)
        vm.finalizeCapture()
        XCTAssertTrue(vm.statusIsError)
        XCTAssertEqual(vm.statusMessage, "Couldn't save: the Mapper isn't connected to the runtime. Reopen the overlay.")
    }

    func testIdentityMappingDeclinesWithAMessage() async {
        let vm = MapperViewModel()
        vm.inputSequence = sequence("a", keyCode: 0)
        vm.outputSequence = sequence("a", keyCode: 0)
        await vm.save(kanataManager: RuntimeCoordinator())
        XCTAssertTrue(vm.statusIsError)
        XCTAssertEqual(vm.statusMessage, "Nothing to save - input and output are the same")
    }

    func testMissingCaptureDeclinesWithAMessage() async {
        let vm = MapperViewModel()
        vm.inputSequence = sequence("a", keyCode: 0)
        vm.outputSequence = nil
        await vm.save(kanataManager: RuntimeCoordinator())
        XCTAssertTrue(vm.statusIsError)
        XCTAssertEqual(vm.statusMessage, "Capture both input and output first")
    }
}
