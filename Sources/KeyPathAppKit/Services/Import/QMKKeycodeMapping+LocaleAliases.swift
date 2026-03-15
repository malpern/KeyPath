// swiftlint:disable file_length

// MARK: - QMK Locale Keycode Aliases

/// Maps locale-prefixed QMK keycodes (JP_Q, DE_A, FR_M, etc.) to their canonical KC_* equivalents.
///
/// QMK's `keymap_extras/*.h` headers define locale-specific keycode aliases that resolve to
/// standard HID scancodes. For example, `JP_Q` is the same scancode as `KC_Q`, and `FR_A`
/// maps to `KC_Q` (because A is in the Q position on AZERTY).
///
/// This table covers base-tier mappings only (no Shift/AltGr variants).
/// Generated from QMK firmware `quantum/keymap_extras/` headers (2024-Q4 snapshot).
/// Refresh procedure: docs/architecture/upstream-maintenance-plan.md
///
/// Supported locales: JP, DE, FR, UK, KR, ES, IT, BR, BP (Bépo), DV (Dvorak), CM (Colemak),
/// CH (Swiss), DK, NO, SE, PT, TR, CZ, HU, PL, RO, HR, SI, BE, EE, IS, LV, LT, GR, IL,
/// RS, RU, UA, US (International), NE (Neo2), FI, CA (Canadian Multilingual)
extension QMKKeycodeMapping {
    // swiftlint:disable function_body_length
    static let localeAliases: [String: String] = {
        var map: [String: String] = [:]

        func alias(_ locale: String, _ pairs: (String, String)...) {
            for (localeName, kcName) in pairs {
                map["\(locale)_\(localeName)"] = kcName
            }
        }

        // MARK: - Japanese (JP)
        alias("JP",
              ("ZKHK", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("CIRC", "KC_EQL"), ("YEN", "KC_INT3"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("AT", "KC_LBRC"), ("LBRC", "KC_RBRC"),
              ("EISU", "KC_CAPS"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("SCLN", "KC_SCLN"), ("COLN", "KC_QUOT"), ("RBRC", "KC_NUHS"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("SLSH", "KC_SLSH"),
              ("BSLS", "KC_INT1"), ("MHEN", "KC_INT5"), ("HENK", "KC_INT4"), ("KANA", "KC_INT2"))

        // MARK: - German (DE)
        alias("DE",
              ("CIRC", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("SS", "KC_MINS"), ("ACUT", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Z", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("UDIA", "KC_LBRC"), ("PLUS", "KC_RBRC"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("ODIA", "KC_SCLN"), ("ADIA", "KC_QUOT"), ("HASH", "KC_NUHS"),
              ("LABK", "KC_NUBS"),
              ("Y", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("MINS", "KC_SLSH"))

        // MARK: - French (FR)
        alias("FR",
              ("SUP2", "KC_GRV"), ("AMPR", "KC_1"), ("EACU", "KC_2"), ("DQUO", "KC_3"),
              ("QUOT", "KC_4"), ("LPRN", "KC_5"), ("MINS", "KC_6"), ("EGRV", "KC_7"),
              ("UNDS", "KC_8"), ("CCED", "KC_9"), ("AGRV", "KC_0"),
              ("RPRN", "KC_MINS"), ("EQL", "KC_EQL"),
              ("A", "KC_Q"), ("Z", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("CIRC", "KC_LBRC"), ("DLR", "KC_RBRC"),
              ("Q", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("M", "KC_SCLN"), ("UGRV", "KC_QUOT"), ("ASTR", "KC_NUHS"),
              ("LABK", "KC_NUBS"),
              ("W", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("COMM", "KC_M"),
              ("SCLN", "KC_COMM"), ("COLN", "KC_DOT"), ("EXLM", "KC_SLSH"))

        // MARK: - UK (UK)
        alias("UK",
              ("GRV", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("EQL", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("LBRC", "KC_LBRC"), ("RBRC", "KC_RBRC"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("SCLN", "KC_SCLN"), ("QUOT", "KC_QUOT"), ("HASH", "KC_NUHS"),
              ("BSLS", "KC_NUBS"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("SLSH", "KC_SLSH"))

        // MARK: - Korean (KR)
        alias("KR",
              ("GRV", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("EQL", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("LBRC", "KC_LBRC"), ("RBRC", "KC_RBRC"),
              ("WON", "KC_BSLS"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("SCLN", "KC_SCLN"), ("QUOT", "KC_QUOT"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("SLSH", "KC_SLSH"),
              ("HANJ", "KC_LNG2"), ("HAEN", "KC_LNG1"))

        // MARK: - Spanish (ES)
        alias("ES",
              ("MORD", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("QUOT", "KC_MINS"), ("IEXL", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("GRV", "KC_LBRC"), ("PLUS", "KC_RBRC"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("NTIL", "KC_SCLN"), ("ACUT", "KC_QUOT"), ("CCED", "KC_NUHS"),
              ("LABK", "KC_NUBS"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("MINS", "KC_SLSH"))

        // MARK: - Italian (IT)
        alias("IT",
              ("BSLS", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("QUOT", "KC_MINS"), ("IGRV", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("EGRV", "KC_LBRC"), ("PLUS", "KC_RBRC"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("OGRV", "KC_SCLN"), ("AGRV", "KC_QUOT"), ("UGRV", "KC_NUHS"),
              ("LABK", "KC_NUBS"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("B", "KC_B"),
              ("V", "KC_V"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("MINS", "KC_SLSH"))

        // MARK: - Brazilian ABNT2 (BR)
        alias("BR",
              ("QUOT", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("EQL", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("ACUT", "KC_LBRC"), ("LBRC", "KC_RBRC"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("CCED", "KC_SCLN"), ("TILD", "KC_QUOT"), ("RBRC", "KC_BSLS"),
              ("BSLS", "KC_NUBS"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("SCLN", "KC_SLSH"),
              ("SLSH", "KC_INT1"), ("PDOT", "KC_PCMM"), ("PCMM", "KC_PDOT"))

        // MARK: - Nordic/Scandinavian (NO, SE, DK, FI)
        for prefix in ["NO", "SE", "DK", "FI"] {
            // These four locales share the same QWERTY alpha layout
            alias(prefix,
                  ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
                  ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
                  ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
                  ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
                  ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
                  ("O", "KC_O"), ("P", "KC_P"),
                  ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
                  ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
                  ("L", "KC_L"),
                  ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
                  ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
                  ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("MINS", "KC_SLSH"),
                  ("LABK", "KC_NUBS"))
        }
        // Locale-specific punctuation/special keys
        // Norwegian
        map["NO_PIPE"] = "KC_GRV"; map["NO_PLUS"] = "KC_MINS"; map["NO_BSLS"] = "KC_EQL"
        map["NO_ARNG"] = "KC_LBRC"; map["NO_DIAE"] = "KC_RBRC"
        map["NO_OSTR"] = "KC_SCLN"; map["NO_AE"] = "KC_QUOT"; map["NO_QUOT"] = "KC_NUHS"
        // Swedish
        map["SE_SECT"] = "KC_GRV"; map["SE_PLUS"] = "KC_MINS"; map["SE_ACUT"] = "KC_EQL"
        map["SE_ARNG"] = "KC_LBRC"; map["SE_DIAE"] = "KC_RBRC"
        map["SE_ODIA"] = "KC_SCLN"; map["SE_ADIA"] = "KC_QUOT"; map["SE_QUOT"] = "KC_NUHS"
        // Danish
        map["DK_HALF"] = "KC_GRV"; map["DK_PLUS"] = "KC_MINS"; map["DK_ACUT"] = "KC_EQL"
        map["DK_ARNG"] = "KC_LBRC"; map["DK_DIAE"] = "KC_RBRC"
        map["DK_AE"] = "KC_SCLN"; map["DK_OSTR"] = "KC_QUOT"; map["DK_QUOT"] = "KC_NUHS"
        // Finnish
        map["FI_SECT"] = "KC_GRV"; map["FI_PLUS"] = "KC_MINS"; map["FI_ACUT"] = "KC_EQL"
        map["FI_ARNG"] = "KC_LBRC"; map["FI_DIAE"] = "KC_RBRC"
        map["FI_ODIA"] = "KC_SCLN"; map["FI_ADIA"] = "KC_QUOT"; map["FI_QUOT"] = "KC_NUHS"

        // MARK: - Swiss (CH) — shared by Swiss German and Swiss French
        alias("CH",
              ("SECT", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("QUOT", "KC_MINS"), ("CIRC", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Z", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("UDIA", "KC_LBRC"), ("DIAE", "KC_RBRC"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("ODIA", "KC_SCLN"), ("ADIA", "KC_QUOT"), ("DLR", "KC_NUHS"),
              ("LABK", "KC_NUBS"),
              ("Y", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("MINS", "KC_SLSH"))
        // Swiss French overrides
        map["CH_EGRV"] = "KC_LBRC"; map["CH_EACU"] = "KC_SCLN"; map["CH_AGRV"] = "KC_QUOT"

        // MARK: - Portuguese (PT)
        alias("PT",
              ("BSLS", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("QUOT", "KC_MINS"), ("LDAQ", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("PLUS", "KC_LBRC"), ("ACUT", "KC_RBRC"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("CCED", "KC_SCLN"), ("MORD", "KC_QUOT"), ("TILD", "KC_NUHS"),
              ("LABK", "KC_NUBS"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("MINS", "KC_SLSH"))

        // MARK: - Turkish Q (TR)
        alias("TR",
              ("DQUO", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("ASTR", "KC_MINS"), ("MINS", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("GBRV", "KC_LBRC"), ("UDIA", "KC_RBRC"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("SCED", "KC_SCLN"), ("IDOT", "KC_QUOT"), ("COMM", "KC_NUHS"),
              ("LABK", "KC_NUBS"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("ODIA", "KC_COMM"), ("CCED", "KC_DOT"), ("DOT", "KC_SLSH"))

        // MARK: - Central/Eastern European (CZ, HU, HR, SI, RO, PL)
        // Czech — QWERTZ with diacritics on number row
        alias("CZ",
              ("SCLN", "KC_GRV"), ("PLUS", "KC_1"), ("ECAR", "KC_2"), ("SCAR", "KC_3"),
              ("CCAR", "KC_4"), ("RCAR", "KC_5"), ("ZCAR", "KC_6"), ("YACU", "KC_7"),
              ("AACU", "KC_8"), ("IACU", "KC_9"), ("EACU", "KC_0"),
              ("EQL", "KC_MINS"), ("ACUT", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Z", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("UACU", "KC_LBRC"), ("RPRN", "KC_RBRC"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("URNG", "KC_SCLN"), ("SECT", "KC_QUOT"), ("DIAE", "KC_NUHS"),
              ("BSLS", "KC_NUBS"),
              ("Y", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("MINS", "KC_SLSH"))

        // Hungarian — QWERTZ
        alias("HU",
              ("0", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("ODIA", "KC_0"),
              ("UDIA", "KC_MINS"), ("OACU", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Z", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("ODAC", "KC_LBRC"), ("UACU", "KC_RBRC"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("EACU", "KC_SCLN"), ("AACU", "KC_QUOT"), ("UDAC", "KC_NUHS"),
              ("IACU", "KC_NUBS"),
              ("Y", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("MINS", "KC_SLSH"))

        // Croatian and Slovenian share the same QWERTZ layout
        for prefix in ["HR", "SI"] {
            alias(prefix,
                  ("CEDL", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
                  ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
                  ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
                  ("QUOT", "KC_MINS"), ("PLUS", "KC_EQL"),
                  ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
                  ("T", "KC_T"), ("Z", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
                  ("O", "KC_O"), ("P", "KC_P"), ("SCAR", "KC_LBRC"), ("DSTR", "KC_RBRC"),
                  ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
                  ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
                  ("L", "KC_L"), ("CCAR", "KC_SCLN"), ("CACU", "KC_QUOT"), ("ZCAR", "KC_NUHS"),
                  ("LABK", "KC_NUBS"),
                  ("Y", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
                  ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
                  ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("MINS", "KC_SLSH"))
        }

        // Romanian — QWERTY
        alias("RO",
              ("DLQU", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("EQL", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("ABRV", "KC_LBRC"), ("ICIR", "KC_RBRC"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("SCOM", "KC_SCLN"), ("TCOM", "KC_QUOT"), ("ACIR", "KC_NUHS"),
              ("BSLS", "KC_NUBS"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("SLSH", "KC_SLSH"))

        // Polish — QWERTY (same physical layout as US)
        alias("PL",
              ("GRV", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("EQL", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("LBRC", "KC_LBRC"), ("RBRC", "KC_RBRC"),
              ("BSLS", "KC_BSLS"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("SCLN", "KC_SCLN"), ("QUOT", "KC_QUOT"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("SLSH", "KC_SLSH"))

        // MARK: - Belgian (BE) — AZERTY variant
        alias("BE",
              ("SUP2", "KC_GRV"), ("AMPR", "KC_1"), ("EACU", "KC_2"), ("DQUO", "KC_3"),
              ("QUOT", "KC_4"), ("LPRN", "KC_5"), ("SECT", "KC_6"), ("EGRV", "KC_7"),
              ("EXLM", "KC_8"), ("CCED", "KC_9"), ("AGRV", "KC_0"),
              ("RPRN", "KC_MINS"), ("MINS", "KC_EQL"),
              ("A", "KC_Q"), ("Z", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("DCIR", "KC_LBRC"), ("DLR", "KC_RBRC"),
              ("Q", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("M", "KC_SCLN"), ("UGRV", "KC_QUOT"), ("MICR", "KC_NUHS"),
              ("LABK", "KC_NUBS"),
              ("W", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("COMM", "KC_M"),
              ("SCLN", "KC_COMM"), ("COLN", "KC_DOT"), ("EQL", "KC_SLSH"))

        // MARK: - Baltic (EE, LV, LT)
        // Estonian — QWERTY
        alias("EE",
              ("CARN", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("PLUS", "KC_MINS"), ("ACUT", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("UDIA", "KC_LBRC"), ("OTIL", "KC_RBRC"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("ODIA", "KC_SCLN"), ("ADIA", "KC_QUOT"), ("QUOT", "KC_NUHS"),
              ("LABK", "KC_NUBS"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("MINS", "KC_SLSH"))

        // Latvian — QWERTY
        alias("LV",
              ("GRV", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("EQL", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("LBRC", "KC_LBRC"), ("RBRC", "KC_RBRC"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("SCLN", "KC_SCLN"), ("QUOT", "KC_QUOT"), ("BSLS", "KC_NUHS"),
              ("NUBS", "KC_NUBS"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("SLSH", "KC_SLSH"))

        // Lithuanian QWERTY
        alias("LT",
              ("GRV", "KC_GRV"), ("AOGO", "KC_1"), ("CCAR", "KC_2"), ("EOGO", "KC_3"),
              ("EDOT", "KC_4"), ("IOGO", "KC_5"), ("SCAR", "KC_6"), ("UOGO", "KC_7"),
              ("UMAC", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("ZCAR", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("LBRC", "KC_LBRC"), ("RBRC", "KC_RBRC"),
              ("BSLS", "KC_BSLS"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("SCLN", "KC_SCLN"), ("QUOT", "KC_QUOT"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("SLSH", "KC_SLSH"))

        // MARK: - Icelandic (IS)
        alias("IS",
              ("RNGA", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("ODIA", "KC_MINS"), ("MINS", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("ETH", "KC_LBRC"), ("QUOT", "KC_RBRC"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("AE", "KC_SCLN"), ("ACUT", "KC_QUOT"), ("PLUS", "KC_NUHS"),
              ("LABK", "KC_NUBS"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("THRN", "KC_SLSH"))

        // MARK: - Cyrillic (RU, UA, RS)
        // Russian
        alias("RU",
              ("YO", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("EQL", "KC_EQL"),
              ("SHTI", "KC_Q"), ("TSE", "KC_W"), ("U", "KC_E"), ("KA", "KC_R"),
              ("IE", "KC_T"), ("EN", "KC_Y"), ("GHE", "KC_U"), ("SHA", "KC_I"),
              ("SHCH", "KC_O"), ("ZE", "KC_P"), ("HA", "KC_LBRC"), ("HARD", "KC_RBRC"),
              ("BSLS", "KC_BSLS"),
              ("EF", "KC_A"), ("YERU", "KC_S"), ("VE", "KC_D"), ("A", "KC_F"),
              ("PE", "KC_G"), ("ER", "KC_H"), ("O", "KC_J"), ("EL", "KC_K"),
              ("DE", "KC_L"), ("ZHE", "KC_SCLN"), ("E", "KC_QUOT"),
              ("YA", "KC_Z"), ("CHE", "KC_X"), ("ES", "KC_C"), ("EM", "KC_V"),
              ("I", "KC_B"), ("TE", "KC_N"), ("SOFT", "KC_M"),
              ("BE", "KC_COMM"), ("YU", "KC_DOT"), ("DOT", "KC_SLSH"))

        // Ukrainian
        alias("UA",
              ("QUOT", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("EQL", "KC_EQL"),
              ("YOT", "KC_Q"), ("TSE", "KC_W"), ("U", "KC_E"), ("KA", "KC_R"),
              ("E", "KC_T"), ("EN", "KC_Y"), ("HE", "KC_U"), ("SHA", "KC_I"),
              ("SHCH", "KC_O"), ("ZE", "KC_P"), ("KHA", "KC_LBRC"), ("YI", "KC_RBRC"),
              ("BSLS", "KC_BSLS"),
              ("EF", "KC_A"), ("I", "KC_S"), ("VE", "KC_D"), ("A", "KC_F"),
              ("PE", "KC_G"), ("ER", "KC_H"), ("O", "KC_J"), ("EL", "KC_K"),
              ("DE", "KC_L"), ("ZHE", "KC_SCLN"), ("YE", "KC_QUOT"),
              ("YA", "KC_Z"), ("CHE", "KC_X"), ("ES", "KC_C"), ("EM", "KC_V"),
              ("Y", "KC_B"), ("TE", "KC_N"), ("SOFT", "KC_M"),
              ("BE", "KC_COMM"), ("YU", "KC_DOT"), ("DOT", "KC_SLSH"))

        // Serbian
        alias("RS",
              ("GRV", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("QUOT", "KC_MINS"), ("PLUS", "KC_EQL"),
              ("LJE", "KC_Q"), ("NJE", "KC_W"), ("IE", "KC_E"), ("ER", "KC_R"),
              ("TE", "KC_T"), ("ZE", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("PE", "KC_P"), ("SHA", "KC_LBRC"), ("DJE", "KC_RBRC"),
              ("A", "KC_A"), ("ES", "KC_S"), ("DE", "KC_D"), ("EF", "KC_F"),
              ("GHE", "KC_G"), ("HA", "KC_H"), ("JE", "KC_J"), ("KA", "KC_K"),
              ("EL", "KC_L"), ("CHE", "KC_SCLN"), ("TSHE", "KC_QUOT"), ("ZHE", "KC_NUHS"),
              ("LABK", "KC_NUBS"),
              ("DZE", "KC_Z"), ("DZHE", "KC_X"), ("TSE", "KC_C"), ("VE", "KC_V"),
              ("BE", "KC_B"), ("EN", "KC_N"), ("EM", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("MINS", "KC_SLSH"))

        // MARK: - Greek (GR)
        alias("GR",
              ("GRV", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("EQL", "KC_EQL"),
              ("SCLN", "KC_Q"), ("FSIG", "KC_W"), ("EPSL", "KC_E"), ("RHO", "KC_R"),
              ("TAU", "KC_T"), ("UPSL", "KC_Y"), ("THET", "KC_U"), ("IOTA", "KC_I"),
              ("OMCR", "KC_O"), ("PI", "KC_P"), ("LBRC", "KC_LBRC"), ("RBRC", "KC_RBRC"),
              ("ALPH", "KC_A"), ("SIGM", "KC_S"), ("DELT", "KC_D"), ("PHI", "KC_F"),
              ("GAMM", "KC_G"), ("ETA", "KC_H"), ("XI", "KC_J"), ("KAPP", "KC_K"),
              ("LAMB", "KC_L"), ("TONS", "KC_SCLN"), ("QUOT", "KC_QUOT"), ("BSLS", "KC_NUHS"),
              ("ZETA", "KC_Z"), ("CHI", "KC_X"), ("PSI", "KC_C"), ("OMEG", "KC_V"),
              ("BETA", "KC_B"), ("NU", "KC_N"), ("MU", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("SLSH", "KC_SLSH"))

        // MARK: - Hebrew (IL)
        alias("IL",
              ("SCLN", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("EQL", "KC_EQL"),
              ("SLSH", "KC_Q"), ("QUOT", "KC_W"), ("QOF", "KC_E"), ("RESH", "KC_R"),
              ("ALEF", "KC_T"), ("TET", "KC_Y"), ("VAV", "KC_U"), ("FNUN", "KC_I"),
              ("FMEM", "KC_O"), ("PE", "KC_P"), ("RBRC", "KC_LBRC"), ("LBRC", "KC_RBRC"),
              ("SHIN", "KC_A"), ("DALT", "KC_S"), ("GIML", "KC_D"), ("KAF", "KC_F"),
              ("AYIN", "KC_G"), ("YOD", "KC_H"), ("HET", "KC_J"), ("LAMD", "KC_K"),
              ("FKAF", "KC_L"), ("FPE", "KC_SCLN"), ("COMM", "KC_QUOT"), ("BSLS", "KC_NUHS"),
              ("ZAYN", "KC_Z"), ("SMKH", "KC_X"), ("BET", "KC_C"), ("HE", "KC_V"),
              ("NUN", "KC_B"), ("MEM", "KC_N"), ("TSDI", "KC_M"),
              ("TAV", "KC_COMM"), ("FTSD", "KC_DOT"), ("DOT", "KC_SLSH"))

        // MARK: - Alternative Layouts (DV, CM, BP, NE)
        // Dvorak
        alias("DV",
              ("GRV", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("LBRC", "KC_MINS"), ("RBRC", "KC_EQL"),
              ("QUOT", "KC_Q"), ("COMM", "KC_W"), ("DOT", "KC_E"), ("P", "KC_R"),
              ("Y", "KC_T"), ("F", "KC_Y"), ("G", "KC_U"), ("C", "KC_I"),
              ("R", "KC_O"), ("L", "KC_P"), ("SLSH", "KC_LBRC"), ("EQL", "KC_RBRC"),
              ("BSLS", "KC_BSLS"),
              ("A", "KC_A"), ("O", "KC_S"), ("E", "KC_D"), ("U", "KC_F"),
              ("I", "KC_G"), ("D", "KC_H"), ("H", "KC_J"), ("T", "KC_K"),
              ("N", "KC_L"), ("S", "KC_SCLN"), ("MINS", "KC_QUOT"),
              ("SCLN", "KC_Z"), ("Q", "KC_X"), ("J", "KC_C"), ("K", "KC_V"),
              ("X", "KC_B"), ("B", "KC_N"), ("M", "KC_M"),
              ("W", "KC_COMM"), ("V", "KC_DOT"), ("Z", "KC_SLSH"))

        // Colemak
        alias("CM",
              ("GRV", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("EQL", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("F", "KC_E"), ("P", "KC_R"),
              ("G", "KC_T"), ("J", "KC_Y"), ("L", "KC_U"), ("U", "KC_I"),
              ("Y", "KC_O"), ("SCLN", "KC_P"), ("LBRC", "KC_LBRC"), ("RBRC", "KC_RBRC"),
              ("BSLS", "KC_BSLS"),
              ("A", "KC_A"), ("R", "KC_S"), ("S", "KC_D"), ("T", "KC_F"),
              ("D", "KC_G"), ("H", "KC_H"), ("N", "KC_J"), ("E", "KC_K"),
              ("I", "KC_L"), ("O", "KC_SCLN"), ("QUOT", "KC_QUOT"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("K", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("SLSH", "KC_SLSH"))

        // Bépo
        alias("BP",
              ("DLR", "KC_GRV"), ("DQUO", "KC_1"), ("LDAQ", "KC_2"), ("RDAQ", "KC_3"),
              ("LPRN", "KC_4"), ("RPRN", "KC_5"), ("AT", "KC_6"), ("PLUS", "KC_7"),
              ("MINS", "KC_8"), ("SLSH", "KC_9"), ("ASTR", "KC_0"),
              ("EQL", "KC_MINS"), ("PERC", "KC_EQL"),
              ("B", "KC_Q"), ("EACU", "KC_W"), ("P", "KC_E"), ("O", "KC_R"),
              ("EGRV", "KC_T"), ("DCIR", "KC_Y"), ("V", "KC_U"), ("D", "KC_I"),
              ("L", "KC_O"), ("J", "KC_P"), ("Z", "KC_LBRC"), ("W", "KC_RBRC"),
              ("A", "KC_A"), ("U", "KC_S"), ("I", "KC_D"), ("E", "KC_F"),
              ("COMM", "KC_G"), ("C", "KC_H"), ("T", "KC_J"), ("S", "KC_K"),
              ("R", "KC_L"), ("N", "KC_SCLN"), ("M", "KC_QUOT"), ("CCED", "KC_BSLS"),
              ("ECIR", "KC_NUBS"),
              ("AGRV", "KC_Z"), ("Y", "KC_X"), ("X", "KC_C"), ("DOT", "KC_V"),
              ("K", "KC_B"), ("QUOT", "KC_N"), ("Q", "KC_M"),
              ("G", "KC_COMM"), ("H", "KC_DOT"), ("F", "KC_SLSH"))

        // Neo2
        alias("NE",
              ("CIRC", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("GRV", "KC_EQL"),
              ("X", "KC_Q"), ("V", "KC_W"), ("L", "KC_E"), ("C", "KC_R"),
              ("W", "KC_T"), ("K", "KC_Y"), ("H", "KC_U"), ("G", "KC_I"),
              ("F", "KC_O"), ("Q", "KC_P"), ("SS", "KC_LBRC"), ("ACUT", "KC_RBRC"),
              ("L3L", "KC_CAPS"),
              ("U", "KC_A"), ("I", "KC_S"), ("A", "KC_D"), ("E", "KC_F"),
              ("O", "KC_G"), ("S", "KC_H"), ("N", "KC_J"), ("R", "KC_K"),
              ("T", "KC_L"), ("D", "KC_SCLN"), ("Y", "KC_QUOT"), ("L3R", "KC_NUHS"),
              ("L4L", "KC_NUBS"),
              ("UDIA", "KC_Z"), ("ODIA", "KC_X"), ("ADIA", "KC_C"), ("P", "KC_V"),
              ("Z", "KC_B"), ("B", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("J", "KC_SLSH"))

        // MARK: - US International (US)
        alias("US",
              ("DGRV", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("EQL", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("LBRC", "KC_LBRC"), ("RBRC", "KC_RBRC"),
              ("BSLS", "KC_BSLS"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("SCLN", "KC_SCLN"), ("ACUT", "KC_QUOT"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("SLSH", "KC_SLSH"))

        // MARK: - Canadian Multilingual (CA)
        alias("CA",
              ("SLSH", "KC_GRV"), ("1", "KC_1"), ("2", "KC_2"), ("3", "KC_3"),
              ("4", "KC_4"), ("5", "KC_5"), ("6", "KC_6"), ("7", "KC_7"),
              ("8", "KC_8"), ("9", "KC_9"), ("0", "KC_0"),
              ("MINS", "KC_MINS"), ("EQL", "KC_EQL"),
              ("Q", "KC_Q"), ("W", "KC_W"), ("E", "KC_E"), ("R", "KC_R"),
              ("T", "KC_T"), ("Y", "KC_Y"), ("U", "KC_U"), ("I", "KC_I"),
              ("O", "KC_O"), ("P", "KC_P"), ("CIRC", "KC_LBRC"), ("CCED", "KC_RBRC"),
              ("A", "KC_A"), ("S", "KC_S"), ("D", "KC_D"), ("F", "KC_F"),
              ("G", "KC_G"), ("H", "KC_H"), ("J", "KC_J"), ("K", "KC_K"),
              ("L", "KC_L"), ("SCLN", "KC_SCLN"), ("EGRV", "KC_QUOT"), ("AGRV", "KC_NUHS"),
              ("UGRV", "KC_NUBS"),
              ("Z", "KC_Z"), ("X", "KC_X"), ("C", "KC_C"), ("V", "KC_V"),
              ("B", "KC_B"), ("N", "KC_N"), ("M", "KC_M"),
              ("COMM", "KC_COMM"), ("DOT", "KC_DOT"), ("EACU", "KC_SLSH"))

        return map
    }()
    // swiftlint:enable function_body_length
}
// swiftlint:enable file_length
