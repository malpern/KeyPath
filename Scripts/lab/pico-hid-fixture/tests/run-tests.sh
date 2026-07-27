#!/bin/sh
set -eu

fixture_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_binary=$(mktemp "${TMPDIR:-/tmp}/keypath-pico-core.XXXXXX")
trap 'rm -f "$test_binary"' EXIT HUP INT TERM

cc -std=c11 -Wall -Wextra -Werror -pedantic \
  -I"$fixture_root/src" \
  "$fixture_root/src/fixture_core.c" \
  "$fixture_root/src/fixture_presentation.c" \
  "$fixture_root/src/fixture_ui_model.c" \
  "$fixture_root/src/fixture_visual_model.c" \
  "$fixture_root/src/fixture_wifi_model.c" \
  "$fixture_root/tests/fixture_core_tests.c" \
  -o "$test_binary"
"$test_binary"
