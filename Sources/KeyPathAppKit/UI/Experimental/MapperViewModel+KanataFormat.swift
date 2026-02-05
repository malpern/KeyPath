import Foundation
import KeyPathCore

extension MapperViewModel {
    // MARK: - Kanata Format Conversion (Delegated to KeyMappingFormatter)

    /// Convert layer name string to RuleCollectionLayer
    func layerFromString(_ name: String) -> RuleCollectionLayer {
        KeyMappingFormatter.layerFromString(name)
    }

    /// Convert KeySequence to kanata format string
    func convertSequenceToKanataFormat(_ sequence: KeySequence) -> String {
        KeyMappingFormatter.toKanataFormat(sequence)
    }

    /// Best-effort input kanata string for rule removal
    func currentInputKanataString() -> String? {
        if let inputSeq = inputSequence {
            return convertSequenceToKanataFormat(inputSeq)
        }
        if let origInput = originalInputKey {
            let seq = KeySequence(
                keys: [KeyPress(baseKey: origInput, modifiers: [], keyCode: 0)],
                captureMode: .single
            )
            return convertSequenceToKanataFormat(seq)
        }
        return nil
    }
}
