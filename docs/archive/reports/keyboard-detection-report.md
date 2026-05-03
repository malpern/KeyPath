# Keyboard Detection Report

- Generated: 2026-03-17 16:54:09Z
- Exact entries: 2004 (+5 vs previous manifest)
- Vendor fallback entries: 4 (+0 vs previous manifest)
- Final exact source mix: override=4, via=1987, qmk=13
- VIA revision: `4048fcc7e5265b17fee6ee104eb8076352dd1180`
- VIA parsed files: 2002 (skipped without IDs: 0)
- QMK exact source entries: 23
- QMK vendor source entries: 4
- QMK unresolved vendor fallbacks omitted from runtime index: 3
- Exact precedence conflicts resolved: 7
- Exact conflicts omitted pending override: 5

## Resolved Exact-Match Conflicts

- `1209:A1E5` selected `via:atreus` over `qmk:atreus`

## Omitted Exact-Match Conflicts

- `1209:2328` omitted because `qmk:zsa/planck_ez` disagrees with `via:ergodone`
- `3297:4974` omitted because `qmk:keebio/iris/rev7` disagrees with `via:ergodox_ez`
- `4335:0001` omitted because `qmk:handwired/dactyl_manuform/5x6` disagrees with `via:gh60/revc`
- `1209:2303` omitted because `qmk:boardsource/unicorne` disagrees with `via:keyboardio/atreus`
- `3297:1969` omitted because `qmk:keebio/iris/rev4` disagrees with `via:zsa`

## VIA Duplicate VID:PID Collisions

- `3434:0330` -> ansi, keychron/v3
- `3434:0331` -> keychron/v3, ansi_encoder
- `3434:0332` -> iso, keychron/v3
- `3434:0333` -> iso_encoder, keychron/v3
- `3434:0334` -> jis, keychron/v3
- `3434:0335` -> jis_encoder, keychron/v3

## Omitted Vendor Fallbacks

- `3297` -> keebio/iris/rev4, keebio/iris/rev7, keebio/levinson/rev3
- `4D58` -> lily58, lily58/rev1
- `3434` -> splitkb/aurora/corne/rev1, splitkb/aurora/sofle_v2/rev1, splitkb/aurora/sweep/rev1
