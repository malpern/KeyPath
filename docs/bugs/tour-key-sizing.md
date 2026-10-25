# Tour pages 1 and 2 changed ordinary key widths

The Caps lesson used a 1.18 camera zoom while Hyper used 0.98 (explaining/applying) and 1 (installed). Because projection applies the extra zoom horizontally, ordinary keys visibly narrowed when advancing to page 2 even though the viewport and physical layout were unchanged.

Both lessons now use the shared Caps camera framing (1.18), including all applying and installed phases. Featured-key transforms remain intact, as do the explicit camera overrides used by later scenes.

`KeyboardStageSceneTests.testFirstTwoTourPagesKeepOrdinaryKeySizeStable` projects an ordinary A key through every phase of both lessons at two viewport sizes. Before the fix it failed six width assertions (73.82375 versus 62.56250 points at the larger size). After the fix all 65 keyboard-stage tests passed, with zero compiler warnings. Accessibility checks passed for 380 files.

The earlier broader adversarial review has no remaining confirmed unfixed findings: A1–A11 were fixed and the full Swift suite passed 5,426 tests. Correction after locating the later recovery report: explicit Try Again recovery was fixed and physically verified in lease cbx_112536399cec on 2026-10-11. Reattaching the ESP32 and pressing Try Again started worker PID 2178 without changing parent PID 737; two physical Escape down/up pairs passed with no F18 leakage. A full reboot/reselection run remains distinct from that verified reconnection case. Snapshot and fresh-TCC acceptance were not part of the broader review validation.

Signed candidate installed on the Air; deep/strict code-sign verification passed and KeyPath reopened with Ready status. ZIP SHA-256: `f3cebbc085ebe9abc9518a71c4a3458d389b113ef58d9522ea9c6a18d87c7814`. The page-size regression is verified through scene projection tests; an installed tour page-to-page visual pass remains pending.


Final live verification (2026-10-11): Air Help → Replay tour, page 1 → 2 → Back, unchanged window. Number/letter/modifier key and case bounds remain fixed, including A key approximately x1144–1286, y605–725 at 1920×1356 screenshot extent. Full reboot/reselection acceptance now passed. A distinct same-boot hot-reconnect journal/selection defect was reproduced, fixed and physically verified; see caps-replug-recovery.md.
