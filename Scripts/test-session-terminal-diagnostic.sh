#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/keypath-terminal-diagnostic.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

swiftc -DKEYPATH_TAP_TIMEOUT_EXPERIMENT \
    "$repo_root/Sources/KeyPathCore/SessionRuntime/SessionRuntimeReport.swift" \
    "$repo_root/Tests/Experiments/SessionTerminalDiagnosticRunner.swift" \
    -o "$tmp_dir/session-terminal-diagnostic-runner"
"$tmp_dir/session-terminal-diagnostic-runner"
