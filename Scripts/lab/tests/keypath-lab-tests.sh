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
 run)
   if [[ "\$*" == *"nameplate-instrumentation"* ]]; then
     [[ -f "$ROOT/fail-nameplate-hide" && " \$* " == *" hide "* ]] && exit 9
     [[ -f "$ROOT/fail-nameplate-show" && " \$* " == *" show "* ]] && exit 10
     echo $'nameplate_version\t0.2.5'
     echo $'nameplate_sha256\t96d1b6c58167b4a8f3713a61a7e216f8a24c2adad36c9027db974f852d543a3d'
     [[ " \$* " == *" hide "* ]] && echo $'nameplate_state\thidden' || echo $'nameplate_state\tvisible'
   else
     echo product=15.7.7; echo build=24G720
   fi ;;
 stop) echo "stop-15 \$2" >> "$CALLS" ;;
 list) echo cbx_test15 ;;
esac
EOF
cat > "$ROOT/bin/launcher26" <<EOF
#!/bin/bash
case "\$1" in
 doctor) echo doctor-26 ;;
 warmup) echo cbx_test26 ;;
 run)
   if [[ "\$*" == *"nameplate-instrumentation"* ]]; then
     echo $'nameplate_version\t0.2.5'
     echo $'nameplate_sha256\t96d1b6c58167b4a8f3713a61a7e216f8a24c2adad36c9027db974f852d543a3d'
     [[ " \$* " == *" hide "* ]] && echo $'nameplate_state\thidden' || echo $'nameplate_state\tvisible'
   else
     echo product=26.5.2; echo build=25F84
   fi ;;
 stop) echo "stop-26 \$2" >> "$CALLS" ;;
 list) echo cbx_test26 ;;
esac
EOF
cat > "$ROOT/bin/launcher27" <<EOF
#!/bin/bash
case "\$1" in
 doctor) echo doctor-27 ;;
 warmup) echo cbx_test27 ;;
 run)
   if [[ "\$*" == *"nameplate-instrumentation"* ]]; then
     echo $'nameplate_version\t0.2.5'
     echo $'nameplate_sha256\t96d1b6c58167b4a8f3713a61a7e216f8a24c2adad36c9027db974f852d543a3d'
     [[ " \$* " == *" hide "* ]] && echo $'nameplate_state\thidden' || echo $'nameplate_state\tvisible'
   else
     echo product=27.0; echo build=26A5378j
   fi ;;
 stop) echo "stop-27 \$2" >> "$CALLS" ;;
 list) echo cbx_test27 ;;
esac
EOF
cat > "$ROOT/bin/crabbox" <<EOF
#!/bin/bash
echo "crabbox \$*" >> "$CALLS"
if [[ \$1 == warmup ]]; then
  if [[ " \$* " == *" --provider tart "* ]]; then
    echo 'leased cbx_stale instance=stale-resource'
    echo 'diagnostic previous=cbx_unrelated'
    printf 'leased cbx_desktop15 instance=test-resource'
  elif [[ " \$* " == *"keypath27-"* ]]; then
    printf 'leased cbx_desktop27 vm=11111111-1111-1111-1111-111111111111'
  else
    printf 'leased cbx_desktop26 vm=00000000-0000-0000-0000-000000000000'
  fi
  [[ \${KEYPATH_LAB_TEST_WARMUP_FAIL:-0} == 1 ]] && exit 9
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
chmod +x "$ROOT/bin/launcher15" "$ROOT/bin/launcher26" "$ROOT/bin/launcher27" "$ROOT/bin/crabbox"

echo 192.0.2.15 > "$TMP/tart-ip"
cat > "$ROOT/bin/tart" <<EOF
#!/bin/bash
[[ \$1 == ip ]] && cat "$TMP/tart-ip"
EOF
cat > "$ROOT/bin/guest-ssh" <<EOF
#!/bin/bash
printf '%s\n' "\$*" > "$TMP/guest-ssh-args"
if [[ " \$* " == *" /bin/test -p /tmp/keypath-console-login-"* ]]; then
  cat >/dev/null
else
  cat > "$TMP/guest-ssh-stdin"
fi
EOF
chmod +x "$ROOT/bin/tart" "$ROOT/bin/guest-ssh"
cat > "$ROOT/bin/prlctl" <<EOF
#!/bin/bash
echo "prlctl \$*" >> "$CALLS"
if [[ \$1 == exec && " \$* " == *sysadminctl*autologin*set* ]]; then
  touch "$TMP/console-fifo-ready"
  for _ in {1..100}; do
    if [[ -f "$TMP/guest-ssh-stdin" ]]; then
      if [[ \${KEYPATH_LAB_TEST_CONSOLE_AUTH_FAIL:-0} == 1 ]]; then
        echo started
        exit 9
      fi
      exit 0
    fi
    sleep 0.01
  done
  exit 9
fi
if [[ \$1 == exec && " \$* " == *" /usr/bin/test -p /tmp/keypath-console-login-"* ]]; then
  [[ -f "$TMP/console-fifo-ready" ]]
fi
if [[ \$1 == exec && " \$* " == *" /usr/sbin/sysadminctl -autologin status "* ]]; then
  echo 'Automatic login is ON.'
fi
if [[ \$1 == exec && " \$* " == *" /usr/bin/stat -f %Su /dev/console "* ]]; then
  echo keypathqa
fi
if [[ \$1 == status ]]; then
  echo running
fi
if [[ \$1 == capture && \$3 == --file ]]; then
  mkdir -p "\$(dirname "\$4")"
  echo png > "\$4"
fi
EOF
chmod +x "$ROOT/bin/prlctl"
echo test-private-key > "$TMP/id_ed25519"
printf 'fixture-password-that-must-not-leak' > "$TMP/secure-input"
grep -Fq 'IFS= read -r KEYPATH_GUEST_PASSWORD < \"\$fifo\" || [[ -n \"\$KEYPATH_GUEST_PASSWORD\" ]]' "$REMOTE"

/bin/bash -n "$LAB_DIR/../qa-macos-27-regression.sh"
/bin/zsh -n "$LAB_DIR/desktop-bootstrap"
/bin/zsh -n "$LAB_DIR/nameplate-instrumentation"
/bin/zsh -n "$LAB_DIR/scenarios/kanata-vhid-two-clients"
grep -q 'macos-27-regression)' "$LAB_DIR/scenarios/installer-scenario"

run_remote() {
    KEYPATH_LAB_TESTING=1 \
    KEYPATH_LAB_TEST_ROOT="$ROOT" \
    KEYPATH_LAB_LAUNCHER_15="$ROOT/bin/launcher15" \
    KEYPATH_LAB_LAUNCHER_26="$ROOT/bin/launcher26" \
    KEYPATH_LAB_LAUNCHER_27="$ROOT/bin/launcher27" \
    KEYPATH_LAB_CRABBOX="$ROOT/bin/crabbox" \
    KEYPATH_LAB_TART="$ROOT/bin/tart" \
    KEYPATH_LAB_GUEST_SSH="$ROOT/bin/guest-ssh" \
    KEYPATH_LAB_PRLCTL="$ROOT/bin/prlctl" \
    KEYPATH_LAB_TEST_SSH_KEY="$TMP/id_ed25519" \
    KEYPATH_LAB_TEST_SECRET_FILE="$TMP/secure-input" \
    KEYPATH_LAB_TEST_CONSOLE_AUTH_FAIL="${KEYPATH_LAB_TEST_CONSOLE_AUTH_FAIL:-0}" \
    KEYPATH_LAB_TEST_CURSOR_BEFORE="${KEYPATH_LAB_TEST_CURSOR_BEFORE:-10 10}" \
    KEYPATH_LAB_TEST_CURSOR_AFTER="${KEYPATH_LAB_TEST_CURSOR_AFTER:-160 120}" \
        /bin/zsh "$REMOTE" "$@"
}

assert_contains() {
    [[ $1 == *"$2"* ]] || { echo "expected '$2' in: $1" >&2; exit 1; }
}

nameplate_metadata=$(/bin/zsh "$LAB_DIR/nameplate-instrumentation" metadata)
assert_contains "$nameplate_metadata" $'nameplate_version\t0.2.5'
assert_contains "$nameplate_metadata" $'nameplate_sha256\t96d1b6c58167b4a8f3713a61a7e216f8a24c2adad36c9027db974f852d543a3d'
grep -q 'NAMEPLATE_VERSION="0.2.5"' "$LAB_DIR/remote.sh"
grep -q 'NAMEPLATE_SHA256="96d1b6c58167b4a8f3713a61a7e216f8a24c2adad36c9027db974f852d543a3d"' "$LAB_DIR/remote.sh"
if grep -q 'launchAtLogin -bool true' "$LAB_DIR/nameplate-instrumentation"; then
    echo "Nameplate instrumentation enabled launch at login" >&2
    exit 1
fi
grep -q 'useFleetFile -bool false' "$LAB_DIR/nameplate-instrumentation"
grep -q 'hasCompletedFirstRun -bool true' "$LAB_DIR/nameplate-instrumentation"
[[ $(grep -c '/usr/bin/pkill -x Nameplate || true' "$LAB_DIR/nameplate-instrumentation") -eq 2 ]]

preflight=$(run_remote preflight)
assert_contains "$preflight" doctor-15
assert_contains "$preflight" doctor-26
assert_contains "$preflight" doctor-27
assert_contains "$preflight" $'disk_reserve_minimum_gib\t100'

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
cp "$LAB_DIR/nameplate-instrumentation" "$repo/Scripts/lab/nameplate-instrumentation"
chmod +x "$repo/Scripts/lab/scenarios/installer-scenario"
chmod +x "$repo/Scripts/lab/nameplate-instrumentation"
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
set +e
disk_output=$(KEYPATH_LAB_TEST_FREE_KIB=104857599 run_remote create 15 unmanaged-ui "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 0 2>&1)
disk_exit=$?
set -e
[[ $disk_exit -eq 75 ]] || { echo "expected disk reserve admission to exit 75, got $disk_exit" >&2; exit 1; }
assert_contains "$disk_output" $'disk_reserve_busy\tfree_gib=99\tminimum_gib=100'

create=$(run_remote create 15 unmanaged-ui "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 0)
assert_contains "$create" $'lease_id\tcbx_test15'
manifest="$ROOT/KeyPathInstallerLab/leases/cbx_test15/manifest.tsv"
grep -q $'owner\tkeypath-installer-lab-v1' "$manifest"
grep -q $'macos_build\t24G720' "$manifest"
grep -q $'test_lane\tunmanaged-ui' "$manifest"
grep -q $'base_name\tghcr.io/cirruslabs/macos-sequoia-base:latest' "$manifest"

set +e
capacity_output=$(run_remote create 15 unmanaged-ui "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 0 2>&1)
capacity_exit=$?
set -e
[[ $capacity_exit -eq 75 ]] || { echo "expected Tart capacity admission to exit 75, got $capacity_exit" >&2; exit 1; }
assert_contains "$capacity_output" $'capacity_busy\tprovider=tart\tactive=1\tlimit=1'
assert_contains "$capacity_output" $'active_lease\tcbx_test15'

set +e
capacity_output=$(run_remote create 15 unmanaged-ui "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 0 2>&1)
capacity_exit=$?
set -e
[[ $capacity_exit -eq 75 ]] || { echo "expected Tart capacity admission to exit 75, got $capacity_exit" >&2; exit 1; }
assert_contains "$capacity_output" $'capacity_busy\tprovider=tart\tactive=1\tlimit=1'
assert_contains "$capacity_output" $'active_lease\tcbx_test15'

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
if run_remote nameplate cbx_test15 enable >/dev/null 2>&1; then
    echo "Nameplate accepted a non-desktop lease" >&2
    exit 1
fi

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

printf 'pid\t%s\nprovider\ttart\n' "$$" > "$ROOT/KeyPathInstallerLab/provider-admission-tart.lock"
parallel_provider_create=$(run_remote create 26 unmanaged-ui "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 0)
assert_contains "$parallel_provider_create" $'lease_id\tcbx_test26'
run_remote destroy cbx_test26 >/dev/null
set +e
lock_output=$(KEYPATH_LAB_ADMISSION_WAIT_ATTEMPTS=1 run_remote create 15 unmanaged-ui "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 0 2>&1)
lock_exit=$?
set -e
[[ $lock_exit -eq 75 ]] || { echo "expected admission-lock contention to exit 75, got $lock_exit" >&2; exit 1; }
assert_contains "$lock_output" admission_lock_busy

env \
    KEYPATH_LAB_TESTING=1 \
    KEYPATH_LAB_TEST_ROOT="$ROOT" \
    KEYPATH_LAB_LAUNCHER_15="$ROOT/bin/launcher15" \
    KEYPATH_LAB_LAUNCHER_26="$ROOT/bin/launcher26" \
    KEYPATH_LAB_LAUNCHER_27="$ROOT/bin/launcher27" \
    KEYPATH_LAB_CRABBOX="$ROOT/bin/crabbox" \
    KEYPATH_LAB_TART="$ROOT/bin/tart" \
    KEYPATH_LAB_GUEST_SSH="$ROOT/bin/guest-ssh" \
    KEYPATH_LAB_TEST_SSH_KEY="$TMP/id_ed25519" \
    KEYPATH_LAB_TEST_SECRET_FILE="$TMP/secure-input" \
    KEYPATH_LAB_ADMISSION_WAIT_ATTEMPTS=3000 \
    /bin/zsh "$REMOTE" create 15 unmanaged-ui "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 0 >"$TMP/interrupted-wait.log" 2>&1 &
interrupted_wait_pid=$!
for _ in {1..100}; do
    compgen -G "$ROOT/KeyPathInstallerLab/.provider-admission-tart.owner.*" >/dev/null && break
    sleep 0.05
done
compgen -G "$ROOT/KeyPathInstallerLab/.provider-admission-tart.owner.*" >/dev/null || { echo "contending create did not write pending owner record" >&2; exit 1; }
kill -TERM "$interrupted_wait_pid"
set +e
wait "$interrupted_wait_pid"
interrupted_wait_exit=$?
set -e
[[ $interrupted_wait_exit -eq 143 ]] || { cat "$TMP/interrupted-wait.log" >&2; echo "expected interrupted lock wait to exit 143, got $interrupted_wait_exit" >&2; exit 1; }
if compgen -G "$ROOT/KeyPathInstallerLab/.provider-admission-tart.owner.*" >/dev/null; then
    echo "interrupted lock wait left a pending owner record" >&2
    exit 1
fi
rm -rf "$ROOT/KeyPathInstallerLab/provider-admission-tart.lock"

env \
    KEYPATH_LAB_TESTING=1 \
    KEYPATH_LAB_TEST_ROOT="$ROOT" \
    KEYPATH_LAB_LAUNCHER_15="$ROOT/bin/launcher15" \
    KEYPATH_LAB_LAUNCHER_26="$ROOT/bin/launcher26" \
    KEYPATH_LAB_LAUNCHER_27="$ROOT/bin/launcher27" \
    KEYPATH_LAB_CRABBOX="$ROOT/bin/crabbox" \
    KEYPATH_LAB_TART="$ROOT/bin/tart" \
    KEYPATH_LAB_GUEST_SSH="$ROOT/bin/guest-ssh" \
    KEYPATH_LAB_TEST_SSH_KEY="$TMP/id_ed25519" \
    KEYPATH_LAB_TEST_SECRET_FILE="$TMP/secure-input" \
    KEYPATH_LAB_TEST_PAUSE_AFTER_ADMISSION_LOCK=1 \
    /bin/zsh "$REMOTE" create 15 unmanaged-ui "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 0 >"$TMP/interrupted-create.log" 2>&1 &
interrupted_pid=$!
for _ in {1..100}; do
    grep -q $'^pid\t' "$ROOT/KeyPathInstallerLab/provider-admission-tart.lock" 2>/dev/null && break
    sleep 0.05
done
[[ -f "$ROOT/KeyPathInstallerLab/provider-admission-tart.lock" ]] || { echo "interrupted create never acquired admission lock" >&2; exit 1; }
kill -TERM "$interrupted_pid"
set +e
wait "$interrupted_pid"
interrupted_exit=$?
set -e
[[ $interrupted_exit -eq 143 ]] || { cat "$TMP/interrupted-create.log" >&2; echo "expected interrupted create to exit 143, got $interrupted_exit" >&2; exit 1; }
[[ ! -e "$ROOT/KeyPathInstallerLab/provider-admission-tart.lock" ]] || { echo "interrupted create left admission lock" >&2; exit 1; }

printf 'pid\t99999999\nprovider\tparallels\n' > "$ROOT/KeyPathInstallerLab/provider-admission-parallels.lock"
create26=$(run_remote create 26 unmanaged-ui "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 0)
assert_contains "$create26" $'lease_id\tcbx_test26'
[[ ! -e "$ROOT/KeyPathInstallerLab/provider-admission-parallels.lock" ]] || { echo "stale Parallels admission lock was not reclaimed" >&2; exit 1; }
artifacts26=$(run_remote artifacts cbx_test26)
assert_contains "$artifacts26" $'download_status\t0'
grep -q 'crabbox run --provider parallels --target macos --id cbx_test26 --stop-after never --download' "$CALLS"
run_remote destroy cbx_test26 >/dev/null

create27=$(run_remote create 27 unmanaged-ui "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 0)
assert_contains "$create27" $'lease_id\tcbx_test27'
artifacts27=$(run_remote artifacts cbx_test27)
assert_contains "$artifacts27" $'download_status\t0'
grep -q 'crabbox run --provider parallels --target macos --id cbx_test27 --stop-after never --download' "$CALLS"
run_remote destroy cbx_test27 >/dev/null
grep -q 'stop-27 cbx_test27' "$CALLS"

desktop27_create=$(run_remote create 27 unmanaged-ui "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 1)
assert_contains "$desktop27_create" $'lease_id\tcbx_desktop27'
console_login=$(KEYPATH_LAB_CONSOLE_LOGIN_POLL_SECONDS=0 run_remote console-login cbx_desktop27)
assert_contains "$console_login" $'console_login\tpassed'
assert_contains "$console_login" $'console_user\tkeypathqa'
[[ "$(cat "$TMP/guest-ssh-stdin")" == "$(cat "$TMP/secure-input")" ]] || { echo "console login streamed the wrong credential" >&2; exit 1; }
grep -q 'prlctl exec 11111111-1111-1111-1111-111111111111 /bin/zsh -lc' "$CALLS"
grep -q 'sysadminctl.*autologin.*set.*userName.*keypathqa.*password' "$CALLS"
grep -q 'prlctl restart 11111111-1111-1111-1111-111111111111' "$CALLS"
grep -q $'console_login_status\tpassed' "$ROOT/KeyPathInstallerLab/leases/cbx_desktop27/manifest.tsv"
rfb_probe=$(KEYPATH_LAB_RFB_POINTER_SETTLE_SECONDS=0 run_remote rfb-pointer-probe cbx_desktop27 160 120)
assert_contains "$rfb_probe" $'rfb_pointer_probe\tpassed'
assert_contains "$rfb_probe" $'cursor_before\t10 10'
assert_contains "$rfb_probe" $'cursor_after\t160 120'
grep -q 'crabbox desktop click --provider parallels --target macos --id cbx_desktop27 --x 160 --y 120' "$CALLS"
set +e
rfb_probe_undelivered=$(KEYPATH_LAB_TEST_CURSOR_AFTER='10 10' KEYPATH_LAB_RFB_POINTER_SETTLE_SECONDS=0 run_remote rfb-pointer-probe cbx_desktop27 160 120 2>&1)
rfb_probe_undelivered_status=$?
set -e
[[ $rfb_probe_undelivered_status -ne 0 ]]
assert_contains "$rfb_probe_undelivered" 'CrabBox acknowledged the RFB click but the guest cursor did not move'
if grep -R -F 'fixture-password-that-must-not-leak' "$ROOT/KeyPathInstallerLab" "$CALLS"; then
    echo "console login leaked its secret into controller logs or arguments" >&2
    exit 1
fi
set +e
console_login_bad_credential=$(KEYPATH_LAB_TEST_CONSOLE_AUTH_FAIL=1 KEYPATH_LAB_CONSOLE_LOGIN_POLL_SECONDS=0 run_remote console-login cbx_desktop27 2>&1)
console_login_bad_credential_status=$?
set -e
[[ $console_login_bad_credential_status -ne 0 ]]
assert_contains "$console_login_bad_credential" 'KEYPATH_LAB_GUEST_PASSWORD does not authenticate the keypathqa guest account'
grep -q $'console_login_status\tcredential-mismatch' "$ROOT/KeyPathInstallerLab/leases/cbx_desktop27/manifest.tsv"
run_remote destroy cbx_desktop27 >/dev/null

desktop26_create=$(run_remote create 26 unmanaged-ui "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 1)
assert_contains "$desktop26_create" $'lease_id\tcbx_desktop26'
desktop26_artifacts=$(run_remote artifacts cbx_desktop26)
assert_contains "$desktop26_artifacts" $'screenshot_status\t0'
grep -q 'prlctl capture 00000000-0000-0000-0000-000000000000 --file' "$CALLS"
desktop26_manifest="$ROOT/KeyPathInstallerLab/leases/cbx_desktop26/manifest.tsv"
awk -F '\t' 'BEGIN {OFS="\t"} $1 == "provider_resource" {$2="-option-like-id"} {print}' "$desktop26_manifest" > "$desktop26_manifest.tmp"
mv "$desktop26_manifest.tmp" "$desktop26_manifest"
prlctl_calls_before=$(grep -c '^prlctl capture ' "$CALLS")
set +e
invalid_resource_output=$(run_remote artifacts cbx_desktop26 2>&1)
invalid_resource_exit=$?
set -e
[[ $invalid_resource_exit -eq 1 ]]
assert_contains "$invalid_resource_output" 'invalid Parallels resource id'
[[ $(grep -c '^prlctl capture ' "$CALLS") -eq $prlctl_calls_before ]]
run_remote destroy cbx_desktop26 >/dev/null

desktop_create=$(run_remote create 15 unmanaged-ui "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 1)
assert_contains "$desktop_create" $'lease_id\tcbx_desktop15'
grep -q $'status\tprovisioning' "$ROOT/KeyPathInstallerLab/leases/cbx_stale/manifest.tsv"
run_remote destroy cbx_stale >/dev/null
desktop_manifest="$ROOT/KeyPathInstallerLab/leases/cbx_desktop15/manifest.tsv"
grep -q $'desktop_enabled\ttrue' "$desktop_manifest"
nameplate_enable=$(run_remote nameplate cbx_desktop15 enable)
assert_contains "$nameplate_enable" $'nameplate_state\tvisible'
grep -q $'nameplate_version\t0.2.5' "$desktop_manifest"
grep -q $'nameplate_sha256\t96d1b6c58167b4a8f3713a61a7e216f8a24c2adad36c9027db974f852d543a3d' "$desktop_manifest"
grep -q $'nameplate_state\tvisible' "$desktop_manifest"
nameplate_status=$(run_remote nameplate cbx_desktop15 status)
assert_contains "$nameplate_status" $'nameplate_state\tvisible'
nameplate_hide=$(run_remote nameplate cbx_desktop15 hide)
assert_contains "$nameplate_hide" $'nameplate_state\thidden'
nameplate_show=$(run_remote nameplate cbx_desktop15 show)
assert_contains "$nameplate_show" $'nameplate_state\tvisible'
desktop_artifacts=$(run_remote artifacts cbx_desktop15)
assert_contains "$desktop_artifacts" $'screenshot_status\t0'
assert_contains "$desktop_artifacts" $'nameplate_hide_status\t0'
assert_contains "$desktop_artifacts" $'nameplate_restore_status\t0'
desktop_artifact_dir=$(printf '%s\n' "$desktop_artifacts" | awk -F '\t' '$1 == "artifact_dir" {print $2}')
[[ -f "$desktop_artifact_dir/screenshot.png" ]]
[[ -f "$desktop_artifact_dir/nameplate-hide.log" && -f "$desktop_artifact_dir/nameplate-restore.log" ]]
grep -q $'nameplate_state\tvisible' "$desktop_manifest"
touch "$ROOT/fail-nameplate-hide"
failed_hide_artifacts=$(run_remote artifacts cbx_desktop15)
rm "$ROOT/fail-nameplate-hide"
assert_contains "$failed_hide_artifacts" $'download_status\t0'
assert_contains "$failed_hide_artifacts" $'screenshot_status\tunavailable:nameplate-hide-failed'
assert_contains "$failed_hide_artifacts" $'nameplate_hide_status\t1'
assert_contains "$failed_hide_artifacts" $'nameplate_restore_status\tnot-needed'
failed_hide_artifact_dir=$(printf '%s\n' "$failed_hide_artifacts" | awk -F '\t' '$1 == "artifact_dir" {print $2}')
[[ -f "$failed_hide_artifact_dir/nameplate-hide.log" && ! -f "$failed_hide_artifact_dir/screenshot.png" ]]
grep -q 'guest reported unexpected Nameplate version: missing' "$failed_hide_artifact_dir/nameplate-hide.log"
touch "$ROOT/fail-nameplate-show"
failed_restore_artifacts=$(run_remote artifacts cbx_desktop15)
rm "$ROOT/fail-nameplate-show"
assert_contains "$failed_restore_artifacts" $'download_status\t0'
assert_contains "$failed_restore_artifacts" $'screenshot_status\t0'
assert_contains "$failed_restore_artifacts" $'nameplate_hide_status\t0'
assert_contains "$failed_restore_artifacts" $'nameplate_restore_status\t1'
failed_restore_artifact_dir=$(printf '%s\n' "$failed_restore_artifacts" | awk -F '\t' '$1 == "artifact_dir" {print $2}')
[[ -f "$failed_restore_artifact_dir/nameplate-hide.log" && -f "$failed_restore_artifact_dir/nameplate-restore.log" ]]
grep -q 'guest reported unexpected Nameplate version: missing' "$failed_restore_artifact_dir/nameplate-restore.log"
grep -q $'nameplate_state\thidden' "$desktop_manifest"
secure_result=$(run_remote secure-dialog-input cbx_desktop15 'System Settings' Password 'Modify Settings' 0)
assert_contains "$secure_result" $'secure_dialog_input\tpassed'
grep -q 'admin@192.0.2.15' "$TMP/guest-ssh-args"
grep -q 'mcporter' "$TMP/guest-ssh-args"
grep -q 'text=@/dev/stdin' "$TMP/guest-ssh-args"
grep -q 'dev/null' "$TMP/guest-ssh-args"
grep -q 'peekaboo.*click.*Password.*--app.*System.*Settings' "$TMP/guest-ssh-args"
grep -q 'peekaboo.*click.*Modify.*Settings.*--app.*System.*Settings' "$TMP/guest-ssh-args"
grep -q 'keypath-secure-postcondition' "$TMP/guest-ssh-args"
grep -q 'keypath-secure-postcondition.json.*79' "$TMP/guest-ssh-args"
if grep -q -- '--query' "$TMP/guest-ssh-args"; then
    echo "secure dialog input passed the adapter-only --query option to Peekaboo" >&2
    exit 1
fi
if grep -q 'click--app' "$TMP/guest-ssh-args"; then
    echo "secure dialog input collapsed adjacent guest arguments" >&2
    exit 1
fi
cmp -s "$TMP/secure-input" "$TMP/guest-ssh-stdin"
if grep -R -F 'fixture-password-that-must-not-leak' "$ROOT/KeyPathInstallerLab" "$TMP/guest-ssh-args"; then
    echo "secure dialog input leaked its secret into logs or arguments" >&2
    exit 1
fi
secure_agent_result=$(run_remote secure-dialog-input cbx_desktop15 SecurityAgent AXSecureTextField Allow 0)
assert_contains "$secure_agent_result" $'secure_dialog_input\tpassed'
grep -q 'keypath-secure-input' "$TMP/guest-ssh-args"
grep -q 'button.*position.*size' "$TMP/guest-ssh-args"
grep -q 'peekaboo.*click.*--coords.*button_coords.*--global-coords' "$TMP/guest-ssh-args"
grep -q -- '--foreground.*--input-strategy.*synthOnly' "$TMP/guest-ssh-args"
grep -q 'SecurityAgent.*closed' "$TMP/guest-ssh-args"
if grep -q '/usr/bin/sudo\|pbcopy\|the\\ clipboard' "$TMP/guest-ssh-args"; then
    echo "SecurityAgent secure input used an unsafe password path" >&2
    exit 1
fi
secure_settings_result=$(run_remote secure-dialog-input cbx_desktop15 'System Settings' AXSecureTextField 'Modify Settings' 0)
assert_contains "$secure_settings_result" $'secure_dialog_input\tpassed'
grep -q 'processes.byName.*appName' "$TMP/guest-ssh-args"
grep -q 'System.*Settings.*Modify.*Settings' "$TMP/guest-ssh-args"
grep -q 'AXSecureTextField' "$TMP/guest-ssh-args"
grep -q 'return.*open.*closed' "$TMP/guest-ssh-args"
secure_focused_result=$(run_remote secure-dialog-input cbx_desktop15 SecurityAgent Password '' 1)
assert_contains "$secure_focused_result" $'secure_dialog_input\tpassed'
if grep -q 'peekaboo.*see\|peekaboo.*click' "$TMP/guest-ssh-args"; then
    echo "already-focused secure input attempted inaccessible AX discovery" >&2
    exit 1
fi
protected_result=$(KEYPATH_LAB_PROTECTED_CLICK_SETTLE_SECONDS=0 run_remote protected-click cbx_desktop15 'System Settings' Accessibility Accessibility native 402 247)
assert_contains "$protected_result" $'protected_click\tpassed'
grep -q 'crabbox desktop click --provider tart --target macos --id test-resource --x 402 --y 247' "$CALLS"
set +e
protected_wrong_page=$(KEYPATH_LAB_TEST_WINDOW_AFTER=Network KEYPATH_LAB_PROTECTED_CLICK_SETTLE_SECONDS=0 run_remote protected-click cbx_desktop15 'System Settings' Accessibility Accessibility native 402 247 2>&1)
protected_wrong_page_exit=$?
set -e
[[ $protected_wrong_page_exit -ne 0 ]] || { echo "protected click accepted the wrong destination page" >&2; exit 1; }
assert_contains "$protected_wrong_page" "protected click postcondition failed"
protected_ax_result=$(KEYPATH_LAB_PROTECTED_CLICK_SETTLE_SECONDS=0 run_remote protected-click cbx_desktop15 'System Settings' Accessibility Accessibility ax 402 247)
assert_contains "$protected_ax_result" $'display_scale\t2'
grep -q 'crabbox desktop click --provider tart --target macos --id test-resource --x 804 --y 494' "$CALLS"
run_remote desktop-type cbx_desktop15 q >/dev/null
grep -q 'crabbox desktop type --provider tart --target macos --id test-resource --text q' "$CALLS"
run_remote destroy cbx_desktop15 >/dev/null

set +e
KEYPATH_LAB_TEST_WARMUP_FAIL=1 run_remote create 15 unmanaged-ui "$archive_key" "$commit" "$checksum" KeyPath.zip 2h 1 >/dev/null 2>&1
warmup_fail_exit=$?
set -e
[[ $warmup_fail_exit -ne 0 ]] || { echo "warmup failure fixture unexpectedly succeeded" >&2; exit 1; }
failed_manifest="$ROOT/KeyPathInstallerLab/leases/cbx_desktop15/manifest.tsv"
grep -q $'status\tprovisioning-failed' "$failed_manifest"
grep -q $'provision_result\t9' "$failed_manifest"

if run_remote create 26 unmanaged-ui "$archive_key" "$commit" "$checksum" KeyPath.zip 3h 0 >/dev/null 2>&1; then
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
if PATH="$TMP/fake-bin:$PATH" "$LAB_DIR/keypath-lab" create --macos 15 --lane unmanaged-ui --commit abc --installer "$TMP/KeyPath.zip" >/dev/null 2>&1; then
    echo "controller accepted a non-explicit commit SHA" >&2
    exit 1
fi
if PATH="$TMP/fake-bin:$PATH" "$LAB_DIR/keypath-lab" create --macos 15 --commit "$(printf 'a%.0s' {1..40})" --installer "$TMP/KeyPath.zip" >/dev/null 2>&1; then
    echo "create accepted a request without an explicit test lane" >&2
    exit 1
fi
if PATH="$TMP/fake-bin:$PATH" "$LAB_DIR/keypath-lab" create --macos 27 --lane managed-functional --commit "$(printf 'a%.0s' {1..40})" --installer "$TMP/KeyPath.zip" >/dev/null 2>&1; then
    echo "create accepted the unsupported macOS 27 managed lane" >&2
    exit 1
fi

"$LAB_DIR/tests/peekaboo-ui-tests.sh"

echo "keypath-lab shell tests passed"
