import Foundation

// MARK: - Karabiner JSON Decodable Models

/// Root of a Karabiner-Elements configuration file.
/// Mirrors the structure of `~/.config/karabiner/karabiner.json`.
struct KarabinerConfig: Decodable {
    let profiles: [KarabinerProfile]
    let global: KarabinerGlobal?

    private enum CodingKeys: String, CodingKey {
        case profiles
        case global
    }
}

struct KarabinerGlobal: Decodable {
    let checkForUpdatesOnStartup: Bool?
    let showInMenuBar: Bool?
    let showProfileNameInMenuBar: Bool?

    private enum CodingKeys: String, CodingKey {
        case checkForUpdatesOnStartup = "check_for_updates_on_startup"
        case showInMenuBar = "show_in_menu_bar"
        case showProfileNameInMenuBar = "show_profile_name_in_menu_bar"
    }
}

// MARK: - Profile

struct KarabinerProfile: Decodable {
    let name: String
    let selected: Bool?
    let simpleModifications: [KarabinerSimpleModification]?
    let complexModifications: KarabinerComplexModifications?
    let parameters: KarabinerParameters?

    private enum CodingKeys: String, CodingKey {
        case name
        case selected
        case simpleModifications = "simple_modifications"
        case complexModifications = "complex_modifications"
        case parameters
    }
}

// MARK: - Simple Modifications

struct KarabinerSimpleModification: Decodable {
    let from: KarabinerSimpleKey
    let to: [KarabinerSimpleKey]

    struct KarabinerSimpleKey: Decodable {
        let keyCode: String?
        let consumerKeyCode: String?
        let pointingButton: String?

        private enum CodingKeys: String, CodingKey {
            case keyCode = "key_code"
            case consumerKeyCode = "consumer_key_code"
            case pointingButton = "pointing_button"
        }
    }
}

// MARK: - Complex Modifications

struct KarabinerComplexModifications: Decodable {
    let rules: [KarabinerRule]?
    let parameters: KarabinerParameters?
}

struct KarabinerRule: Decodable {
    let description: String?
    let manipulators: [KarabinerManipulator]?
    let enabled: Bool?
}

// MARK: - Manipulator

struct KarabinerManipulator: Decodable {
    let type: String?
    let from: KarabinerFrom?
    let to: [KarabinerTo]?
    let toIfAlone: [KarabinerTo]?
    let toIfHeldDown: [KarabinerTo]?
    let toAfterKeyUp: [KarabinerTo]?
    let toDelayedAction: KarabinerDelayedAction?
    let conditions: [KarabinerCondition]?
    let parameters: KarabinerManipulatorParameters?

    private enum CodingKeys: String, CodingKey {
        case type
        case from
        case to
        case toIfAlone = "to_if_alone"
        case toIfHeldDown = "to_if_held_down"
        case toAfterKeyUp = "to_after_key_up"
        case toDelayedAction = "to_delayed_action"
        case conditions
        case parameters
    }
}

struct KarabinerDelayedAction: Decodable {
    let toIfInvoked: [KarabinerTo]?
    let toIfCanceled: [KarabinerTo]?

    private enum CodingKeys: String, CodingKey {
        case toIfInvoked = "to_if_invoked"
        case toIfCanceled = "to_if_canceled"
    }
}

struct KarabinerManipulatorParameters: Decodable {
    let basicToIfAloneTimeoutMilliseconds: Int?
    let basicToIfHeldDownThresholdMilliseconds: Int?
    let basicToDelayedActionDelayMilliseconds: Int?
    let basicSimultaneousThresholdMilliseconds: Int?

    private enum CodingKeys: String, CodingKey {
        case basicToIfAloneTimeoutMilliseconds = "basic.to_if_alone_timeout_milliseconds"
        case basicToIfHeldDownThresholdMilliseconds = "basic.to_if_held_down_threshold_milliseconds"
        case basicToDelayedActionDelayMilliseconds = "basic.to_delayed_action_delay_milliseconds"
        case basicSimultaneousThresholdMilliseconds = "basic.simultaneous_threshold_milliseconds"
    }
}

// MARK: - From

struct KarabinerFrom: Decodable {
    let keyCode: String?
    let consumerKeyCode: String?
    let pointingButton: String?
    let modifiers: KarabinerModifiers?
    let simultaneous: [KarabinerSimultaneousKey]?
    let simultaneousOptions: KarabinerSimultaneousOptions?

    private enum CodingKeys: String, CodingKey {
        case keyCode = "key_code"
        case consumerKeyCode = "consumer_key_code"
        case pointingButton = "pointing_button"
        case modifiers
        case simultaneous
        case simultaneousOptions = "simultaneous_options"
    }
}

struct KarabinerSimultaneousKey: Decodable {
    let keyCode: String?
    let consumerKeyCode: String?

    private enum CodingKeys: String, CodingKey {
        case keyCode = "key_code"
        case consumerKeyCode = "consumer_key_code"
    }
}

struct KarabinerSimultaneousOptions: Decodable {
    let detectKeyDownUninterruptedly: Bool?
    let keyDownOrder: String?
    let keyUpOrder: String?
    let keyUpWhen: String?
    let toAfterKeyUp: [KarabinerTo]?

    private enum CodingKeys: String, CodingKey {
        case detectKeyDownUninterruptedly = "detect_key_down_uninterruptedly"
        case keyDownOrder = "key_down_order"
        case keyUpOrder = "key_up_order"
        case keyUpWhen = "key_up_when"
        case toAfterKeyUp = "to_after_key_up"
    }
}

// MARK: - To

struct KarabinerTo: Decodable {
    let keyCode: String?
    let consumerKeyCode: String?
    let pointingButton: String?
    let shellCommand: String?
    let selectInputSource: KarabinerInputSource?
    let setVariable: KarabinerSetVariable?
    let mouseKey: KarabinerMouseKey?
    let modifiers: [String]?
    let lazy: Bool?
    let `repeat`: Bool?
    let halt: Bool?
    let holdDownMilliseconds: Int?

    private enum CodingKeys: String, CodingKey {
        case keyCode = "key_code"
        case consumerKeyCode = "consumer_key_code"
        case pointingButton = "pointing_button"
        case shellCommand = "shell_command"
        case selectInputSource = "select_input_source"
        case setVariable = "set_variable"
        case mouseKey = "mouse_key"
        case modifiers
        case lazy
        case `repeat`
        case halt
        case holdDownMilliseconds = "hold_down_milliseconds"
    }
}

struct KarabinerInputSource: Decodable {
    let language: String?
    let inputSourceId: String?
    let inputModeId: String?

    private enum CodingKeys: String, CodingKey {
        case language
        case inputSourceId = "input_source_id"
        case inputModeId = "input_mode_id"
    }
}

struct KarabinerSetVariable: Decodable {
    let name: String
    let value: KarabinerVariableValue

    private enum CodingKeys: String, CodingKey {
        case name
        case value
    }
}

/// Karabiner variable values can be Int, String, or Bool.
enum KarabinerVariableValue: Decodable, Equatable {
    case int(Int)
    case string(String)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.typeMismatch(
                KarabinerVariableValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected Int, String, or Bool for variable value"
                )
            )
        }
    }

    /// Returns true if this value represents an "on" state (1, true, or non-empty string).
    var isOn: Bool {
        switch self {
        case let .int(v): v != 0
        case let .bool(v): v
        case let .string(v): !v.isEmpty && v != "0"
        }
    }
}

struct KarabinerMouseKey: Decodable {
    let x: Int?
    let y: Int?
    let verticalWheel: Int?
    let horizontalWheel: Int?
    let speedMultiplier: Double?

    private enum CodingKeys: String, CodingKey {
        case x, y
        case verticalWheel = "vertical_wheel"
        case horizontalWheel = "horizontal_wheel"
        case speedMultiplier = "speed_multiplier"
    }
}

// MARK: - Modifiers

struct KarabinerModifiers: Decodable {
    let mandatory: [String]?
    let optional: [String]?
}

// MARK: - Conditions

struct KarabinerCondition: Decodable {
    let type: String
    let bundleIdentifiers: [String]?
    let filePaths: [String]?
    let name: String?
    let value: KarabinerVariableValue?
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case bundleIdentifiers = "bundle_identifiers"
        case filePaths = "file_paths"
        case name
        case value
        case description
    }
}

// MARK: - Parameters

/// Profile-level and complex-modification-level parameters share the same shape.
typealias KarabinerParameters = KarabinerManipulatorParameters
