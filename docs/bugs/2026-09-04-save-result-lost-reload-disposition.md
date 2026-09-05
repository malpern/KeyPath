# Save result discarded the reload disposition

## Evidence and scope

Source investigation at `a12bb07d5`: `SaveCoordinator.saveMapping` and
`saveGeneratedConfig` received a four-disposition `ReloadResult`, then returned
only a Boolean, an error, and mappings. Applied and pending both returned
success, so the caller could not distinguish saved content from active content.
Rejected and failed outcomes also lost their structured reload evidence.

This is a confirmed result-contract gap, not a reproduced UI incident. No
catalog organization, status presentation, or conflict policy changes accompany it.

## First repair

Keep the original reload result on `SaveResult` for both save paths. Keep nil
for failures before reload and retain existing Boolean semantics during caller
migration. Tests drive generated and mapping saves with each injected reload disposition,
assert one reload, verify the retained result, and check written or restored
content. Invalid content leaves the original file intact without a reload.

Tests use temporary stores and the guarded test base; validation in this suite
uses the project's test-mode parser. This does not qualify the bundled Kanata
validator or physical input behavior.

## Architectural follow-through

Result preservation alone does not complete a transaction. Collection mutations
still discard reload outcomes; raw/generated restoration is file-oriented;
preferences, source stores, and pack records can require separate recovery.
Move these through one transaction owner before changing Boolean callers to
interpret a reload failure as an instruction to retry or roll back.

Do not interpret a retained rejected/failed reload as evidence that recovery
succeeded. Cancellation and recovery failure need explicit transaction outcomes
in the next step. See `docs/planning/catalog-led-consolidation-plan.md`.
