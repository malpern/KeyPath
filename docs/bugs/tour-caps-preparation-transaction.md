# Failed Caps tour setup must not become a saved rule

The first-success tour installed Caps Lock → Escape with `skipFinalReload: true`,
then separately asked the runtime to apply it. On a machine without a compatible
physical Caps keyboard, selection preparation correctly refused the runtime start.
The saved Caps collection and pack record survived, however. Every later ordinary
rule save then attempted to start a config containing that Caps mapping and failed
for the same reason, even while the existing worker remained healthy.

The Caps tour now supplies its recover-stopped-runtime callback to the pack install
transaction. Config, collection state, custom rules and installed-pack metadata stay
recoverable until runtime application returns. A rejected preparation restores the
previous revision; it does not blindly disable Caps or uninstall a preexisting pack.
The callback is explicit per operation, never a temporary replacement of the shared
rule-change callback. Successful application runs once. Pending application retains
the existing saved-but-not-active behavior.

Regression coverage in `PackRuleTransactionTests` exercises a rejected tour,
byte-identical recovery of all four files, retention of preexisting enabled/disabled
Caps state, preservation of custom rules, a following ordinary A → C save, and a
successful single application while the pack journal remains present. Runtime Caps
admission and physical-device requirements are unchanged.
