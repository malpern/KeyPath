#!/bin/bash
# Throwaway spike: the one check the fixture cannot do — the Air's built-in
# keyboard. Run in Terminal ON THE AIR (it needs a person to press keys and
# Terminal needs Input Monitoring). Quit KeyPath first: it owns the built-in
# Caps lease and would refuse to restore a mapping it did not write.
#
#   swiftc -O -o /tmp/caps-hid-probe main.swift   # or scp the mini's build
#   ./air-manual-check.sh /tmp/caps-hid-probe
#
# During the 20 s window: tap Caps Lock 3 times, then hold Caps and type "asdf".
set -euo pipefail
PROBE=${1:?probe binary}
MATCH='{"LocationID":0xe7,"PrimaryUsagePage":1,"PrimaryUsage":6}'
if pgrep -x KeyPath >/dev/null; then echo "Quit KeyPath first (it holds the Caps lease)." >&2; exit 2; fi
before=$(hidutil property --matching "$MATCH" --get UserKeyMapping)
echo "$before"
echo "$before" | grep -q '(null)' || { echo "Built-in already has a mapping; not touching it." >&2; exit 2; }
trap 'hidutil property --matching "$MATCH" --set "{\"UserKeyMapping\":[]}" >/dev/null; echo restored:; hidutil property --matching "$MATCH" --get UserKeyMapping' EXIT
hidutil property --matching "$MATCH" --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000A5}]}' >/dev/null
echo "Mapped Caps -> 0x07/0xA5 on the built-in. Tap Caps 3x, then hold Caps and type asdf (20 s)."
"$PROBE" --seconds 20 | tee /tmp/caps-hid-air.ndjson | grep -E '"hidmgr".*"usage"|"tap".*"type"|lockState|access'
