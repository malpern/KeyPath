# Applied catalog updates must not be offered again

On the Air (October 18), Rules showed "Review Catalog Updates" for Window Snapping
after every apply. Three applies (15:07–15:08) each created a backup; only the
first changed `RuleCollections.json`.

`catalogUpdatePreviews()` offers an update when `upgradedCollection(from:)` differs
from the saved collection. For Window Snapping with a chosen key convention, the
upgrade regenerates mappings with `windowMappings(for:)`, and `KeyMapping` gets a
fresh UUID per construction. Its synthesized equality includes `id`, so the
proposal never equalled the saved collection, however often it was applied.

Regenerated mappings now take the ids of the saved mappings they replace (matched
by input). Existing saved data needs no migration: it compares equal on the next
check. `RuleCollectionCatalogTests` covers Window Snapping after apply and a JSON
round trip for both conventions, and idempotence of every default collection's
upgrade; both failed before the fix (only Window Snapping was non-idempotent).
