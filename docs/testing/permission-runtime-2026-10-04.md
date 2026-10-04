# KeyPath timeout experiment checkpoint — October 4, 2026

## Disposition

The prepared lease `cbx_4ce260f5a1bb` (Parallels UUID `8d9eba49-206c-4488-b496-178fa4c46635`, boot epoch `1791139117`) was destroyed at 19:02 UTC, before its hard cutoff at **19:08:50 UTC** (epoch `1791140930`). Root reports independently confirming the provider UUID absent after destroy; the exact ESP32 fixture is present on the host, detached from VMs, routing ask with an empty automatic binding. The retained source template UUID `64a9db80-0716-4340-ba96-e87108068b58` remained stopped and recognized as a template. No new runtime or physical acceptance resulted from this run; a separate fresh clone was subsequently admitted.

The source fix is committed and pushed on `experiment/tap-timeout-hook` at `6ed4ea99052c19bc94e99517cfe9827377b17af7`. Root reports a full-ON debug build with a 27.01-second duration and 16 policy/report-compatibility tests passing. The staged candidate is debug-signed and strict-signature-verified, not notarized; its manifest says build metadata and base resources were reused and Metal was not freshly compiled. These checks validate the source/build packet only.

The prepared-session receipts show identity and readiness published, artifacts installed, and both no-input capability smoke checks passed with clean exits. Those checks are not product acceptance: the direct reports separated AX from effective input. The LS capability report found AX true, effective input false, with zero input/output, no active tap and no listener; it did not show input working.

Two timing attempts were refused before hardware calls. The earlier attempt stopped at worker startup deadline (`samples: []`, `hardwareCalls: false`, cleanup error count zero, profile bytewise restored, and no worker PID per root verification). The later foreground attempt stopped at `setup.snapshot-target-check` because the normal target lost focus (`samples: []`, `hardwareCalls: false`, cleanup error count zero, profile bytewise restored). Root separately verified the foreground log sequence included finish/headless/persistent-worker-failed and the focus guard. This is a harness refusal and evidence of a focus/lifecycle issue; it is **not** a timing pass and does not by itself establish the product or OS cause. Preserve the startup refusal as unresolved; treat the later focus loss as the immediate reason the second timing attempt did not run.

## Next gates

Use foreground parent launch, then create and bind a fresh normally focused capture target. Preserve the old target's latched focus failure; never reset it to obtain a pass. Test the newly signed PostEvent candidate with current-process capability reports and actual worker/tap/TCP readiness before timing or physical input. A fresh timing pass, clean cleanup and bytewise profile restoration remain mandatory for the actual OS timeout campaign. Physical initial startup and explicit new-parent recovery need the same fresh-capture sequencing, retaining all prior held-release/fail-open evidence.

Console transition follows actual timeout. Caps Lock follows runtime stabilization; reduced-permission installer/onboarding UX follows completion of permission reduction. Genuine guest sleep/wake remains a separate platform coverage gap. Source builds and inert checks do not extend historical physical acceptance to this artifact.

## Evidence and provenance

This manifest records hashes for the selected receipts and packet artifacts only; it does not copy raw logs or private account content. Receipt facts above come from the listed JSON files. Build/test, destroy, provider-inventory, fixture, and foreground-log summaries marked as root-reported are operator observations relayed by root, not claims inside these receipts.

| Evidence | SHA256 |
| --- | --- |
| prepared identity state | `1fcb77c8642ad1184ebcd32405cb7da808be4859048d1902467dfd574fdf2892` |
| guest identity | `e44ed6a6826cae6cc49440a210386ef3d406ea481e51b266b3ce6d181eeea122` |
| readiness state | `b029e7d8d5fb21602756eeaed479ae7ede4446df18f980ed0314deecfe64bf87` |
| artifact staging state | `4401845728980b527b86e1e50ab43eab2c617e505cfcab71ca80ced41d5c20c1` |
| no-input smoke state | `c73cfe3e1479edc691eb0838830e7547fa89f3c29223c0ca75767697952fc9ca` |
| post-consent smoke state | `0d53397702e57a35ec9cfa041750aadab489e648ffed95af0159307a028e0fb0` |
| startup-deadline timing receipt | `31ae34af5f6c202c1ccab38b02067d5bb48fbe915004aa981f17b0b16156a52d` |
| LS capability state | `4ecd730982e9f948dbabf7b2121be10d6fdc7113ad990487d3b8e9b26d42b9ac` |
| foreground focus-refusal receipt | `f76672339aed940d05c2852fdc1dd01df319893f4e9937b650942019de581a36` |
| frozen prepared-runtime packet README | `693a1b9fa6f1ee12eb3b1edc191d92fe127eaf1a59ec71c0dbe0788ed81ce5c0` |
| post-event artifact manifest | `aa72dec3f55bd7b0464b876d630ebc40da527d4c7998f86e1554836a72d9ebfe` |
| active-tap candidate patch | `88369fe76e7c83d731ffca87be2a2a84218efffa32c3d1e9ad6eba9fb196f2a9` |
| active-tap candidate manifest | `d34f02a46bfaab5c464f949acba950d8e6f9ba1b5f13ccaa0ff8e16bb82ce0a7` |

Artifact-manifest details: source commit `6ed4ea99052c19bc94e99517cfe9827377b17af7`; debug main SHA256 `d3420624a492016df316fa6285e932470bbc49d25ff538639a2d19c31e196682`; archive SHA256 `7bfd007cbe3631c16aee1a55bbf65b45d7269758da033b7636fb224373dd3ded`; target SHA256 `55c8fa008280633ecf6137d7d47df27e152b16a8ba37bbf01dca4c7ab4ef4858`. The manifest records input authorization source `current-process.apple-api.modifying-tap-post-event`; no new runtime acceptance is recorded.
