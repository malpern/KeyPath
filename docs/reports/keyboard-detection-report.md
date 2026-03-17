# Keyboard Detection Report

- Generated: 2026-03-17 16:20:14Z
- Exact entries: 1999 (+0 vs previous manifest)
- Vendor fallback entries: 4 (+0 vs previous manifest)
- Final exact source mix: override=0, via=1986, qmk=13
- VIA revision: `b4b9281282c7f9406ecd477fca20a4d7a0c98315`
- VIA parsed files: 2001 (skipped without IDs: 0)
- QMK exact source entries: 23
- QMK vendor source entries: 4
- QMK unresolved vendor fallbacks omitted from runtime index: 3
- Exact precedence conflicts resolved: 7
- Exact conflicts omitted pending override: 9

## Resolved Exact-Match Conflicts

- `1209:A1E5` selected `via:atreus` over `qmk:atreus`

## Omitted Exact-Match Conflicts

- `4653:0001` omitted because `qmk:sofle/rev1` disagrees with `via:crkbd`
- `1209:2328` omitted because `qmk:zsa/planck_ez` disagrees with `via:ergodone`
- `3297:4974` omitted because `qmk:keebio/iris/rev7` disagrees with `via:ergodox_ez`
- `4335:0001` omitted because `qmk:handwired/dactyl_manuform/5x6` disagrees with `via:gh60/revc`
- `CB10:1133` omitted because `qmk:crkbd/rev1` disagrees with `via:keebio/bdn9`
- `CB10:1256` omitted because `qmk:crkbd/rev4_0/standard` disagrees with `via:keebio/iris`
- `1209:2303` omitted because `qmk:boardsource/unicorne` disagrees with `via:keyboardio/atreus`
- `FC32:1287` omitted because `qmk:ferris/sweep` disagrees with `via:sofle`
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
