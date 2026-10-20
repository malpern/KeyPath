import Foundation

/// Shared, intentionally small Kanata configurations for tests that need valid
/// syntax but are not testing the configuration text itself.
enum KanataConfigFixtures {
    static let sessionQToA = """
    (defcfg)
    (defsrc q)
    (deflayer base a)
    """

    static let capsToEscapeBare = """
    (defcfg)
    (defsrc caps)
    (deflayer base esc)
    """

    static let capsToEscape = """
    (defcfg
      process-unmapped-keys yes
    )
    (defsrc caps)
    (deflayer base esc)
    """

    static let capsToEscapeInlineDefcfg = """
    (defcfg process-unmapped-keys yes)
    (defsrc caps)
    (deflayer base esc)
    """
}
