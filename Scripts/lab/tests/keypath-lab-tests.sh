#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd -P)
LAB_DIR=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd -P)
REMOTE="$LAB_DIR/remote.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/keypath-lab-tests.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

ROOT="$TMP/CrabBox"
mkdir -p "$ROOT/bin" "$ROOT/KeyPathInstallerLab/archives"
CALLS="$TMP/calls.log"

cat > "$ROOT/bin/launcher15" <<EOF
#!/bin/bash
case "\$1" in
 doctor) echo doctor-15 ;;
 warmup) echo cbx_test15 ;;
 run) echo product=15.7.7; echo build=24G720 ;;
 stop) echo "stop-15 \$2" >> "$CALLS" ;;
 list) echo cbx_test15 ;;
esac
EOF
cat > "$ROOT/bin/launcher26" <<EOF
#!/bin/bash
case "\$1" in
 doctor) echo doctor-26 ;;
 warmup) echo cbx_test26 ;;
 run) echo product=26.5.2; echo build=25F84 ;;
 stop) echo "stop-26 \$2" >> "$CALLS" ;;
 list) echo cbx_test26 ;;
esac
EOF
cat > "$ROOT/bin/crabbox" <<EOF
#!/bin/bash
echo "crabbox \$*" >> "$CALLS"
if [[ \$1 == warmup ]]; then
  if [[ " \$* " == *" --provider tart "* ]]; then echo cbx_desktop15; else echo cbx_desktop26; fi
  exit 0
fi
if [[ \$1 == screenshot ]]; then
  while [[ \$# -gt 0 ]]; do
    if [[ \$1 == --output ]]; then mkdir -p "\$(dirname "\$2")"; echo png > "\$2"; break; fi
    shift
  done
  exit 0
fi
while [[ \$# -gt 0 ]]; do
  if [[ \$1 == --download ]]; then
    target=\${2#*=}
    mkdir -p "\$(dirname "\$target")"
    fixture="\$(mktemp -d)"
    mkdir -p "\$fixture/scenario-output/controller-capture"
    echo test > "\$fixture/scenario-output/controller-capture/sw-vers.txt"
    tar -czf "\$target" -C "\$fixture" scenario-output
    rm -rf "\$fixture"
    break
  fi
  shift
done
exit 0
EOF
chmod +x "$ROOT/bin/launcher15" "$ROOT/bin/launcher26" "$ROOT/bin/crabbox"

/bin/bash -n "$LAB_DIR/../qa-macos-27-regression.sh"
grep -q 'macos-27-regression)' "$LAB_DIR/scenarios/installer-scenario"

run_remote() {
    KEYPATH_LAB_TESTING=1 \
    KEYPATH_LAB_TEST_ROOT="$ROOT" \
    KEYPATH_LAB_LAUNCHER_15="$ROOT/bin/launcher15" \
    KEYPATH_LAB_LAUNCHER_26="$ROOT/bin/launcher26" \
    KEYPATH_LAB_CRABBOX="$ROOT/bin/crabbox" \
        /bin/zsh "$REMOTE" "$@"
}

assert_contains() {
    [[ $1 == *"$2"* ]] || { echo "expected '$2' in: $1" >&2; exit 1; }
}

preflight=$(run_remote preflight)
assert_contains "$preflight" doctor-15
assert_contains "$preflight" doctor-26

ticket_one=$(run_remote prepare-upload "$(printf 'a%.0s' {1..40})-$(printf 'b%.0s' {1..64})")
ticket_two=$(run_remote prepare-upload "$(printf 'a%.0s' {1..40})-$(printf 'b%.0s' {1..64})")
[[ "$ticket_one" == /tmp/keypath-lab.* && "$ticket_two" == /tmp/keypath-lab.* ]]
[[ "$ticket_one" != "$ticket_two" && -f "$ticket_one" && -f "$ticket_two" ]]
rm -f "$ticket_one" "$ticket_two"

publish_commit=$(printf 'c%.0s' {1..40})
publish_checksum=$(shasum -a 256 "$LAB_DIR/scenarios/installer-scenario" | awk '{print $1}')
publish_key="$publish_commit-$publish_checksum"
mkdir -p "$TMP/upload/repo/.keypath-lab/installer"
cp "$LAB_DIR/scenarios/installer-scenario" "$TMP/upload/repo/.keypath-lab/installer/installer.zip"
for pass in 1 2; do
    ticket=$(run_remote prepare-upload "$publish_key")
    tar -czf "$ticket" -C "$TMP/upload" repo
    published=$(run_remote install-archive "$ticket" "$publish_key" "$publish_commit" "$publish_checksum" installer.zip)
    if [[ $pass == 1 ]]; then assert_contains "$published" $'archive\tcreated'; else assert_contains "$published" $'archive\treused'; fi
done
if find "$ROOT/KeyPathInstallerLab/archives" -maxdepth 1 -name ".staging-$publish_key-*" | grep -q .; then
    echo "archive publish left a staging directory" >&2
    exit 1
fi

archive_key="$(printf 'a%.0s' {1..40})-$(printf 'b%.0s' {1..64})"
repo="$ROOT/KeyPathInstallerLab/archives/$archive_key/repo"
mkdir -p "$repo/.keypath-lab/installer" "$repo/Scripts/lab/scenarios"
cp "$LAB_DIR/scenarios/installer-scenario" "$repo/Scripts/lab/scenarios/installer-scenario"
chmod +x "$repo/Scripts/lab/scenarios/installer-scenario"
echo installer > "$repo/.keypath-lab/installer/KeyPath.zip"
git -C "$repo" init -q
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.com
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
cat > "$ROOT/KeyPathInstallerLab/archives/$archive_key/ready.tsv" <<EOF
owner	keypath-installer-lab-v1
EOF

commit=$(printf 'a%.0s' {1..40})
checksum=$(printf 'b%.0s' {1..64})
create=$(run_remote create 15 "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 0)
assert_contains "$create" $'lease_id\tcbx_test15'
manifest="$ROOT/KeyPathInstallerLab/leases/cbx_test15/manifest.tsv"
grep -q $'owner\tkeypath-installer-lab-v1' "$manifest"
grep -q $'macos_build\t24G720' "$manifest"

run_remote run cbx_test15 echo hello >/dev/null
grep -q 'echo hello' "$ROOT/KeyPathInstallerLab/leases/cbx_test15/commands.tsv"
run_remote scenario cbx_test15 clean-install >/dev/null
grep -q 'installer-scenario clean-install' "$ROOT/KeyPathInstallerLab/leases/cbx_test15/commands.tsv"
run_remote install-app cbx_test15 >/dev/null
grep -q 'install-app 15 cbx_test15' "$ROOT/KeyPathInstallerLab/logs/cbx_test15/install-app.log"

artifacts=$(run_remote artifacts cbx_test15)
assert_contains "$artifacts" $'download_status\t0'
assert_contains "$artifacts" $'screenshot_status\tunavailable:lease-not-created-with-desktop'
grep -q -- '--download' "$CALLS"
grep -q 'crabbox run --provider tart --target macos --id cbx_test15 --stop-after never --download' "$CALLS"
if grep -q 'crabbox cp' "$CALLS"; then
    echo "artifact collection used unsupported crabbox cp" >&2
    exit 1
fi
[[ -f "$(find "$ROOT/KeyPathInstallerLab/artifacts/cbx_test15" -path '*/scenario-output/controller-capture/sw-vers.txt' -print -quit)" ]]

operation_repo="$ROOT/KeyPathInstallerLab/operations/$(grep $'^slug\t' "$manifest" | cut -f2)/repo"
mkdir -p "$operation_repo/.crabbox/captures"
echo failure-evidence > "$operation_repo/.crabbox/captures/failure.tar.gz"
run_remote run cbx_test15 echo generated-output-is-safe >/dev/null
artifacts_with_capture=$(run_remote artifacts cbx_test15)
capture_dir=$(printf '%s\n' "$artifacts_with_capture" | awk -F '\t' '$1 == "artifact_dir" {print $2}')
[[ -f "$capture_dir/controller-crabbox-captures/failure.tar.gz" ]]

touch "$operation_repo/changing-file"
if run_remote run cbx_test15 echo unsafe >/dev/null 2>&1; then
    echo "run accepted a changing checkout" >&2
    exit 1
fi
rm "$operation_repo/changing-file"

mkdir -p "$ROOT/KeyPathInstallerLab/leases/not-owned"
printf 'owner\tother\nlease_id\tnot-owned\n' > "$ROOT/KeyPathInstallerLab/leases/not-owned/manifest.tsv"
if run_remote destroy not-owned >/dev/null 2>&1; then
    echo "destroy accepted an unowned lease" >&2
    exit 1
fi

run_remote destroy cbx_test15 >/dev/null
grep -q 'stop-15 cbx_test15' "$CALLS"
grep -q $'cleanup_status\tcomplete' "$manifest"

create26=$(run_remote create 26 "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 0)
assert_contains "$create26" $'lease_id\tcbx_test26'
artifacts26=$(run_remote artifacts cbx_test26)
assert_contains "$artifacts26" $'download_status\t0'
grep -q 'crabbox run --provider parallels --target macos --id cbx_test26 --stop-after never --download' "$CALLS"
run_remote destroy cbx_test26 >/dev/null

desktop_create=$(run_remote create 15 "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 1)
assert_contains "$desktop_create" $'lease_id\tcbx_desktop15'
desktop_manifest="$ROOT/KeyPathInstallerLab/leases/cbx_desktop15/manifest.tsv"
grep -q $'desktop_enabled\ttrue' "$desktop_manifest"
desktop_artifacts=$(run_remote artifacts cbx_desktop15)
assert_contains "$desktop_artifacts" $'screenshot_status\t0'
desktop_artifact_dir=$(printf '%s\n' "$desktop_artifacts" | awk -F '\t' '$1 == "artifact_dir" {print $2}')
[[ -f "$desktop_artifact_dir/screenshot.png" ]]
run_remote destroy cbx_desktop15 >/dev/null

if run_remote create 26 "$archive_key" "$commit" "$checksum" KeyPath.zip 3h 0 >/dev/null 2>&1; then
    echo "create accepted a TTL longer than the launchers support" >&2
    exit 1
fi

cp -R "$ROOT/KeyPathInstallerLab/leases/cbx_test15" "$ROOT/KeyPathInstallerLab/leases/cbx_expired"
expired="$ROOT/KeyPathInstallerLab/leases/cbx_expired/manifest.tsv"
sed -i '' 's/cbx_test15/cbx_expired/g; s/^expires_epoch.*/expires_epoch\t1/; s/^cleanup_status.*/cleanup_status\tpending/' "$expired"
dry_run=$(run_remote cleanup --dry-run)
assert_contains "$dry_run" $'would_destroy\tcbx_expired'
if grep -q 'stop-15 cbx_expired' "$CALLS"; then
    echo "dry-run destroyed a lease" >&2
    exit 1
fi
run_remote cleanup >/dev/null
grep -q 'stop-15 cbx_expired' "$CALLS"

touch "$ROOT/base-image-must-survive"
run_remote cleanup >/dev/null
[[ -f "$ROOT/base-image-must-survive" ]]

mkdir -p "$TMP/fake-bin"
cat > "$TMP/fake-bin/ssh" <<EOF
#!/bin/bash
echo "\$*" > "$TMP/ssh-args"
cat >/dev/null
echo controller-preflight
EOF
chmod +x "$TMP/fake-bin/ssh"
controller=$(PATH="$TMP/fake-bin:$PATH" KEYPATH_LAB_HOST=tester@test-host "$LAB_DIR/keypath-lab" preflight)
assert_contains "$controller" controller-preflight
grep -q 'tester@test-host' "$TMP/ssh-args"

echo fake-installer > "$TMP/KeyPath.zip"
if PATH="$TMP/fake-bin:$PATH" "$LAB_DIR/keypath-lab" create --macos 15 --commit abc --installer "$TMP/KeyPath.zip" >/dev/null 2>&1; then
    echo "controller accepted a non-explicit commit SHA" >&2
    exit 1
fi

"$LAB_DIR/tests/peekaboo-ui-tests.sh"

echo "keypath-lab shell tests passed"
