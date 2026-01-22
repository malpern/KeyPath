import Foundation

/// Maps text characters to Kanata key names using a US keyboard layout.
public enum TextToKanataKeyMapper {
    public struct MappingError: Error, Equatable, Sendable {
        public let character: Character

        public init(character: Character) {
            self.character = character
        }
    }

    /// Convert a full text string into Kanata key names.
    public static func map(text: String) -> Result<[String], MappingError> {
        var keys: [String] = []
        keys.reserveCapacity(text.count)

        for character in text {
            guard let key = map(character: character) else {
                return .failure(MappingError(character: character))
            }
            keys.append(key)
        }

        return .success(keys)
    }

    /// Return the first unsupported character in a string, if any.
    public static func firstUnsupportedCharacter(in text: String) -> Character? {
        for character in text {
            if map(character: character) == nil {
                return character
            }
        }
        return nil
    }

    /// Map a single character to a Kanata key name.
    public static func map(character: Character) -> String? {
        guard let scalar = character.unicodeScalars.first, scalar.isASCII else {
            return nil
        }

        let value = scalar.value
        if value == 0x0A { return "ret" } // \n
        if value == 0x0D { return "ret" } // \r
        if value == 0x09 { return "tab" } // \t
        if value == 0x20 { return "spc" } // space

        if character.isLetter {
            let lower = String(character).lowercased()
            if character.isUppercase {
                return "S-\(lower)"
            }
            return lower
        }

        if character.isNumber {
            return String(character)
        }

        if let direct = unshiftedMap[character] {
            return direct
        }

        if let shiftedBase = shiftedMap[character] {
            return "S-\(shiftedBase)"
        }

        return nil
    }

    private static let unshiftedMap: [Character: String] = [
        "-": "min",
        "=": "eql",
        "[": "[",
        "]": "]",
        "\\": "\\",
        ";": ";",
        "'": "'",
        ",": ",",
        ".": ".",
        "/": "/",
        "`": "grv"
    ]

    private static let shiftedMap: [Character: String] = [
        "!": "1",
        "@": "2",
        "#": "3",
        "$": "4",
        "%": "5",
        "^": "6",
        "&": "7",
        "*": "8",
        "(": "9",
        ")": "0",
        "_": "min",
        "+": "eql",
        "{": "[",
        "}": "]",
        "|": "\\",
        ":": ";",
        "\"": "'",
        "<": ",",
        ">": ".",
        "?": "/",
        "~": "grv"
    ]
}
