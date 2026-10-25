# Simple Modifications bypassed save ownership

The editor previously generated and validated effective content from the current
file, then wrote the proposed mappings through SimpleModsWriter. This validated
the old revision rather than the proposed edit. It also discarded the canonical
reload result and ran separate health checks, leaving overlapping editor saves
outside the directory operation lease.

SimpleModsWriter now renders captured content only. SaveCoordinator admits before
capture and transformation, validates the proposal, checks that the file revision
still matches, writes and classifies reload using its existing raw-save path.
SimpleModsService preserves its loaded revision, serializes debounced settlement,
and refreshes editor state after failure. Temporary-directory tests cover rejected
and pending reloads, concurrent edits, and external changes before/after transform.

The parser also treated any line beginning with two recognized keys as a mapping,
including positional defsrc/deflayer rows. Outside the sentinel block it now
indexes entries only within explicit base deflayermap forms. Regression fixtures
include multiline layouts, another layer, and comments containing parentheses.

This change does not make the limited line parser a general Kanata parser. It
also does not establish ownership of external deflayermap entries or add
multi-store/crash/runtime recovery to raw saves. Those remain explicit follow-up
boundaries in the consolidation plan.

Installed Kanata `--check` also exposed two renderer issues: disabled mappings
used a single semicolon (not Kanata's double-semicolon comment), and removing the
last managed mapping could remove the only layer. Rendering now emits real
comments and retains an empty managed layer when needed. Empty, enabled and
disabled managed-layer fixtures were checked against the installed engine.

Appending a managed base layer to a file that already defines its own base layer
remains unsupported by the legacy renderer. The coordinated validator now rejects
that duplicate before writing, preserving the original file. Supporting those
files needs an explicit ownership/migration design; fake-engine save tests are
not evidence that arbitrary raw configurations can be edited.

Fully inline forms such as `(deflayermap (base) caps esc)` were not indexed by
the old line parser and remain outside its supported discovery syntax. This
slice does not add a complete S-expression parser or claim exhaustive conflict
detection for arbitrary hand-written syntax.
