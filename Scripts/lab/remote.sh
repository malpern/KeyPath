#!/bin/zsh
set -euo pipefail

PRODUCTION_ROOT="/Volumes/KeyPath Lab/CrabBox"
OWNER="keypath-installer-lab-v1"
NAMEPLATE_VERSION="0.2.5"
NAMEPLATE_SHA256="96d1b6c58167b4a8f3713a61a7e216f8a24c2adad36c9027db974f852d543a3d"

if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
  LAB_ROOT="${KEYPATH_LAB_TEST_ROOT:?KEYPATH_LAB_TEST_ROOT is required in test mode}"
  LAUNCHER_15="${KEYPATH_LAB_LAUNCHER_15:?test launcher 15 is required}"
  LAUNCHER_26="${KEYPATH_LAB_LAUNCHER_26:?test launcher 26 is required}"
  LAUNCHER_27="${KEYPATH_LAB_LAUNCHER_27:?test launcher 27 is required}"
  CRABBOX="${KEYPATH_LAB_CRABBOX:?test CrabBox is required}"
  TART="${KEYPATH_LAB_TART:?test Tart is required}"
  GUEST_SSH="${KEYPATH_LAB_GUEST_SSH:?test guest SSH is required}"
else
  LAB_ROOT="$PRODUCTION_ROOT"
  LAUNCHER_15="$LAB_ROOT/keypath15"
  LAUNCHER_26="$LAB_ROOT/keypath26"
  LAUNCHER_27="$LAB_ROOT/keypath27"
  CRABBOX="$LAB_ROOT/SharedTools/bin/crabbox"
  TART="${KEYPATH_LAB_TART:-$LAB_ROOT/CompatTools/bin/tart}"
  GUEST_SSH="${KEYPATH_LAB_GUEST_SSH:-/usr/bin/ssh}"
fi

TART_USB_TOOL_ROOT="${KEYPATH_LAB_TART_USB_TOOL_ROOT:-$LAB_ROOT/CompatTools/KeyPathUSB}"

STATE_ROOT="$LAB_ROOT/KeyPathInstallerLab"
ARCHIVES="$STATE_ROOT/archives"
LEASES="$STATE_ROOT/leases"
ARTIFACTS="$STATE_ROOT/artifacts"
LOGS="$STATE_ROOT/logs"
OPERATIONS="$STATE_ROOT/operations"
HELD_ADMISSION_LOCK=
HELD_ADMISSION_OWNER=
PENDING_ADMISSION_OWNER=

die() { print -u2 "keypath-lab(remote): $*"; exit 1; }
now_epoch() { date +%s; }
utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

valid_id() {
  [[ "$1" =~ '^[A-Za-z0-9._-]+$' ]] || die "invalid identifier: $1"
}

valid_archive_key() {
  valid_id "$1"
  [[ "$1" =~ '^[0-9a-f]{40}-[0-9a-f]{64}(-h[0-9a-f]{40})?(-[0-9a-f]{64})?$' ]] || die "invalid archive key"
}

launcher_for() {
  case "$1" in
    15) print -r -- "$LAUNCHER_15" ;;
    26) print -r -- "$LAUNCHER_26" ;;
    27) print -r -- "$LAUNCHER_27" ;;
    *) die "unsupported macOS lane: $1" ;;
  esac
}

provider_for() {
  case "$1" in 15) print tart ;; 26|27) print parallels ;; *) die "unsupported macOS lane: $1" ;; esac
}

configure_tart_path() {
  local usb_prefix=
  if [[ "${CRABBOX_TART_USB_PASSTHROUGH:-false}" == "true" ]]; then
    usb_prefix="$TART_USB_TOOL_ROOT/bin:"
  fi
  export PATH="${usb_prefix}$LAB_ROOT/CompatTools/bin:$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
}

base_for() {
  local macos=$1 lane=$2 desktop=${3:-0}
  if [[ "$macos" == "15" ]]; then
    [[ "$lane" == "managed-functional" ]] && print keypath-macos-15-managed || print ghcr.io/cirruslabs/macos-sequoia-base:latest
  elif [[ "$macos" == "27" && "$desktop" == "1" ]]; then
    print keypath-macos-27-desktop
  else
    [[ "$lane" == "managed-functional" ]] && print "keypath-macos-$macos-managed" || print "keypath-macos-$macos"
  fi
}

manifest_path() { print -r -- "$LEASES/$1/manifest.tsv"; }

field() {
  local manifest=$1 key=$2
  awk -F '\t' -v key="$key" '$1 == key {sub(/^[^\t]*\t/, ""); print; exit}' "$manifest"
}

set_field() {
  local manifest=$1 key=$2 value=$3 temp="${manifest}.tmp.$$"
  awk -F '\t' -v key="$key" -v value="$value" 'BEGIN {OFS="\t"} $1 == key {$0=key OFS value; found=1} {print} END {if (!found) print key, value}' "$manifest" > "$temp"
  mv "$temp" "$manifest"
}

owned_manifest() {
  local lease=$1 manifest
  valid_id "$lease"
  manifest=$(manifest_path "$lease")
  [[ -f "$manifest" ]] || die "lease is not owned by this interface: $lease"
  [[ "$(field "$manifest" owner)" == "$OWNER" ]] || die "ownership marker mismatch for lease: $lease"
  [[ "$(field "$manifest" lease_id)" == "$lease" ]] || die "lease manifest id mismatch: $lease"
  print -r -- "$manifest"
}

duration_seconds() {
  local value=$1 number unit
  if [[ "$value" == <-> ]]; then print "$value"; return; fi
  number=${value[1,-2]}
  unit=${value[-1]}
  [[ "$number" == <-> ]] || die "invalid duration: $value"
  case "$unit" in
    m) print $((number * 60)) ;;
    h) print $((number * 3600)) ;;
    d) print $((number * 86400)) ;;
    *) die "invalid duration: $value" ;;
  esac
}

ensure_roots() {
  mkdir -p "$ARCHIVES" "$LEASES" "$ARTIFACTS" "$LOGS" "$OPERATIONS"
}

provider_capacity() {
  case "$1" in
    tart) print "${KEYPATH_LAB_CAPACITY_TART:-1}" ;;
    parallels) print "${KEYPATH_LAB_CAPACITY_PARALLELS:-2}" ;;
    *) die "unsupported provider capacity key: $1" ;;
  esac
}

host_free_kib() {
  if [[ -n "${KEYPATH_LAB_TEST_FREE_KIB:-}" ]]; then
    print -r -- "$KEYPATH_LAB_TEST_FREE_KIB"
  else
    df -Pk /System/Volumes/Data | awk 'NR == 2 {print $4}'
  fi
}

assert_internal_disk_reserve() {
  local minimum_gib=${KEYPATH_LAB_MIN_FREE_DISK_GIB:-100} free_kib minimum_kib
  [[ "$minimum_gib" == <-> && "$minimum_gib" -gt 0 ]] || die "invalid disk reserve: $minimum_gib GiB"
  free_kib=$(host_free_kib)
  [[ "$free_kib" == <-> ]] || die "could not determine internal free space"
  minimum_kib=$((minimum_gib * 1024 * 1024))
  print -u2 "disk_reserve\tfree_gib=$((free_kib / 1024 / 1024))\tminimum_gib=$minimum_gib"
  if (( free_kib < minimum_kib )); then
    print -u2 "disk_reserve_busy\tfree_gib=$((free_kib / 1024 / 1024))\tminimum_gib=$minimum_gib"
    return 75
  fi
}

acquire_admission_lock() {
  local provider=$1 attempt=0 owner owner_pid stale lock_age lock_mtime lock="$STATE_ROOT/provider-admission-$provider.lock"
  local owner_record="$STATE_ROOT/.provider-admission-$provider.owner.$$"
  local max_attempts=${KEYPATH_LAB_ADMISSION_WAIT_ATTEMPTS:-3000}
  local incomplete_grace=${KEYPATH_LAB_INCOMPLETE_LOCK_GRACE_SECONDS:-5}
  [[ "$max_attempts" == <-> && "$max_attempts" -gt 0 ]] || die "invalid admission wait attempts: $max_attempts"
  [[ "$incomplete_grace" == <-> ]] || die "invalid incomplete lock grace: $incomplete_grace"
  PENDING_ADMISSION_OWNER="$owner_record"
  {
    print "pid\t$$"
    print "provider\t$provider"
    print "created_at\t$(utc_now)"
  } > "$owner_record"
  while ((attempt < max_attempts)); do
    if ln "$owner_record" "$lock" 2>/dev/null; then
      PENDING_ADMISSION_OWNER=
      HELD_ADMISSION_LOCK="$lock"
      HELD_ADMISSION_OWNER="$owner_record"
      return
    fi
    if [[ -d "$lock" ]]; then
      # Recover directory locks created by the initial implementation of this protocol.
      owner_pid=$(field "$lock/owner.tsv" pid 2>/dev/null || true)
      lock_mtime=$(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || print 0)
      lock_age=$(( $(now_epoch) - lock_mtime ))
    else
      owner_pid=$(field "$lock" pid 2>/dev/null || true)
      lock_age=0
    fi
    if { [[ "$owner_pid" == <-> ]] && ! kill -0 "$owner_pid" 2>/dev/null; } ||
       { [[ -d "$lock" && -z "$owner_pid" && "$lock_age" -ge "$incomplete_grace" ]]; }; then
      stale="$STATE_ROOT/provider-admission-$provider.stale.$$"
      if mv "$lock" "$stale" 2>/dev/null; then
        rm -rf "$stale"
        continue
      fi
    fi
    ((attempt += 1))
    sleep 0.1
  done
  rm -f "$owner_record"
  PENDING_ADMISSION_OWNER=
  if [[ -d "$lock" ]]; then
    owner=$(cat "$lock/owner.tsv" 2>/dev/null || print unavailable)
  else
    owner=$(cat "$lock" 2>/dev/null || print unavailable)
  fi
  print -u2 "admission_lock_busy"
  print -u2 -- "$owner"
  return 75
}

release_admission_lock() {
  [[ -n "$PENDING_ADMISSION_OWNER" ]] && rm -f "$PENDING_ADMISSION_OWNER"
  PENDING_ADMISSION_OWNER=
  if [[ -n "$HELD_ADMISSION_LOCK" && -n "$HELD_ADMISSION_OWNER" &&
        -f "$HELD_ADMISSION_LOCK" && "$HELD_ADMISSION_LOCK" -ef "$HELD_ADMISSION_OWNER" ]]; then
    rm -f "$HELD_ADMISSION_LOCK"
  fi
  [[ -n "$HELD_ADMISSION_OWNER" ]] && rm -f "$HELD_ADMISSION_OWNER"
  HELD_ADMISSION_LOCK=
  HELD_ADMISSION_OWNER=
}

release_admission_lock_and_exit() {
  local exit_code=$1
  trap - EXIT INT TERM HUP
  release_admission_lock || true
  exit "$exit_code"
}

assert_provider_capacity() {
  local provider=$1 capacity active=0 manifest lease expires cleanup lease_status commit macos lane slug
  capacity=$(provider_capacity "$provider")
  [[ "$capacity" == <-> && "$capacity" -gt 0 ]] || die "invalid $provider capacity: $capacity"
  for manifest in "$LEASES"/*/manifest.tsv(N); do
    [[ "$(field "$manifest" owner)" == "$OWNER" ]] || continue
    [[ "$(field "$manifest" provider)" == "$provider" ]] || continue
    cleanup=$(field "$manifest" cleanup_status)
    lease_status=$(field "$manifest" status)
    expires=$(field "$manifest" expires_epoch)
    [[ "$cleanup" != complete && "$lease_status" != destroyed && "$expires" == <-> && "$expires" -gt "$(now_epoch)" ]] || continue
    lease=$(field "$manifest" lease_id)
    commit=$(field "$manifest" keypath_commit)
    macos=$(field "$manifest" macos)
    lane=$(field "$manifest" test_lane)
    slug=$(field "$manifest" slug)
    ((active += 1))
    print -u2 "active_lease\t$lease\tprovider=$provider\tmacos=$macos\tlane=${lane:-legacy}\tstatus=$lease_status\texpires_epoch=$expires\tcommit=$commit\tslug=$slug"
  done
  if ((active >= capacity)); then
    print -u2 "capacity_busy\tprovider=$provider\tactive=$active\tlimit=$capacity"
    return 75
  fi
}

managed_identity_scope_for() {
  local macos=$1 lane=$2 base_name enrollment_id
  [[ "$lane" == managed-functional ]] || { print none; return 0; }
  if [[ "$macos" == "15" ]]; then
    print unique-clone
    return 0
  fi
  base_name=$(base_for "$macos" "$lane")
  enrollment_id=$(managed_enrollment_id_for "$base_name")
  print -r -- "shared:$enrollment_id"
}

assert_managed_identity_available() {
  local macos=$1 lane=$2 requested_scope manifest cleanup lease_status expires
  local existing_lease existing_scope existing_macos
  [[ "$lane" == managed-functional ]] || return 0
  requested_scope=$(managed_identity_scope_for "$macos" "$lane")
  [[ "$requested_scope" == unique-clone ]] && return 0
  for manifest in "$LEASES"/*/manifest.tsv(N); do
    [[ "$(field "$manifest" owner)" == "$OWNER" ]] || continue
    [[ "$(field "$manifest" test_lane)" == managed-functional ]] || continue
    cleanup=$(field "$manifest" cleanup_status)
    lease_status=$(field "$manifest" status)
    expires=$(field "$manifest" expires_epoch)
    [[ "$cleanup" != complete && "$lease_status" != destroyed && "$expires" == <-> && "$expires" -gt "$(now_epoch)" ]] || continue
    existing_macos=$(field "$manifest" macos)
    if [[ -z "$existing_macos" ]]; then
      existing_scope=legacy-unknown
    else
      existing_scope=$(managed_identity_scope_for "$existing_macos" managed-functional)
    fi
    [[ "$existing_scope" == "$requested_scope" || "$existing_scope" == legacy-unknown ]] || continue
    existing_lease=$(field "$manifest" lease_id)
    print -u2 "managed_identity_busy\tactive_lease=$existing_lease\tscope=$requested_scope\tstatus=$lease_status\texpires_epoch=$expires"
    return 75
  done
}

record_command() {
  local lease=$1 result=$2; shift 2
  local command_text
  command_text=$(printf '%q ' "$@")
  print -r -- "$(utc_now)\t$result\t$command_text" >> "$LEASES/$lease/commands.tsv"
}

prepare_worktree() {
  local repo=$1 changes
  [[ "$repo" == "$OPERATIONS"/*/repo ]] || die "unsafe lease worktree path"
  [[ -d "$repo/.git" ]] || die "lease checkout is not a Git worktree"
  changes=$(git -C "$repo" status --porcelain --untracked-files=all -- . \
    ':(exclude).crabbox/logs/**' \
    ':(exclude).crabbox/captures/**' \
    ':(exclude).crabbox/runs/**')
  [[ -z "$changes" ]] || die "refusing to sync a changing checkout"
}

managed_enrollment_id_for() {
  local base_name=$1 identity_file enrollment_id
  valid_id "$base_name"
  identity_file="$STATE_ROOT/managed-identities/$base_name.enrollment-id"
  [[ -f "$identity_file" && ! -L "$identity_file" ]] || die "managed enrollment identity is unavailable for base: $base_name"
  enrollment_id=$(<"$identity_file")
  [[ "$enrollment_id" =~ '^[A-Fa-f0-9-]{36}$' ]] || die "invalid managed enrollment identity for base: $base_name"
  print -r -- "$enrollment_id"
}

approve_peekaboo_capture() {
  local lease=$1 manifest macos resource key ip prompt_command prompt_coords private_prompt_command private_prompt_coords attempt approved
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  [[ "$macos" == "15" ]] || die "Peekaboo capture approval currently supports only the Tart macOS 15 lane"
  resource=$(field "$manifest" provider_resource)
  [[ "$resource" =~ '^[A-Za-z0-9._-]+$' && "$resource" != "unknown" ]] || die "invalid Tart resource id"

  key="$HOME/Library/Application Support/crabbox/testboxes/$lease/id_ed25519"
  [[ -f "$key" && ! -L "$key" && -O "$key" ]] || die "owned CrabBox SSH key not found for lease"
  if [[ "${USER:-}" == "clawd" ]]; then export TART_HOME="$LAB_ROOT/TartHome-clawd"; else export TART_HOME="$LAB_ROOT/TartHome"; fi
  export PATH="$LAB_ROOT/CompatTools/bin:$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  ip=$($TART ip "$resource")
  [[ "$ip" =~ '^[0-9A-Fa-f:.]+$' ]] || die "Tart returned an invalid guest address"
  prompt_command=$'/usr/bin/osascript -l JavaScript -e \'\nfunction run() {\n  var matches = Application("System Events").processes.whose({name: "NotificationCenter"})();\n  if (matches.length === 0 || matches[0].windows().length === 0) return "";\n  var window = matches[0].windows[0];\n  try {\n    var size = window.size();\n    if (window.subrole() === "AXSystemDialog" && size[0] === 1024 && size[1] === 768) return "512,399";\n  } catch (_) {}\n  return "";\n}\''
  private_prompt_command=$'/usr/bin/osascript -l JavaScript -e \'\nfunction run() {\n  var matches = Application("System Events").processes.whose({name: "UserNotificationCenter"})();\n  if (matches.length === 0 || matches[0].windows().length === 0) return "";\n  var window = matches[0].windows[0];\n  try {\n    var message = window.staticTexts().map(function(item) { return item.value() || ""; }).join(" ");\n    if (window.subrole() !== "AXSystemDialog" || message.indexOf("boo.peekaboo.peekaboo") === -1 || message.indexOf("private window picker") === -1) return "";\n    var buttons = window.buttons().filter(function(item) { return item.name() === "Allow"; });\n    if (buttons.length !== 1) return "";\n    var position = buttons[0].position();\n    var size = buttons[0].size();\n    return Math.round(position[0] + size[0] / 2) + "," + Math.round(position[1] + size[1] / 2);\n  } catch (_) {}\n  return "";\n}\''
  approved=0
  prompt_coords=
  for attempt in {1..20}; do
    prompt_coords=$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" \
      "/bin/zsh -lc $(printf %q "$prompt_command")")
    [[ -n "$prompt_coords" ]] && break
    sleep "${KEYPATH_LAB_CAPTURE_APPROVAL_POLL_SECONDS:-0.2}"
  done
  if [[ -n "$prompt_coords" ]]; then
    [[ "$prompt_coords" =~ '^[0-9]+,[0-9]+$' ]] || die "Peekaboo capture approval prompt coordinates are invalid"
    "$CRABBOX" desktop click --provider tart --target macos --id "$resource" \
      --x "${prompt_coords%,*}" --y "${prompt_coords#*,}" >/dev/null
    approved=1
    sleep "${KEYPATH_LAB_CAPTURE_APPROVAL_SETTLE_SECONDS:-5}"
  fi

  # macOS 15 can follow the full-screen ScreenCaptureKit prompt with a second,
  # smaller dialog authorizing Peekaboo's private-window-picker bypass. Leaving
  # that dialog on screen makes later RFB coordinates hit the obscured Settings
  # sidebar. Match the exact Peekaboo request and derive the Allow button center
  # from the live AX tree instead of storing another fixed coordinate.
  private_prompt_coords=
  for attempt in {1..20}; do
    private_prompt_coords=$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" \
      "/bin/zsh -lc $(printf %q "$private_prompt_command")")
    [[ -n "$private_prompt_coords" ]] && break
    sleep "${KEYPATH_LAB_CAPTURE_APPROVAL_POLL_SECONDS:-0.2}"
  done
  if [[ -n "$private_prompt_coords" ]]; then
    [[ "$private_prompt_coords" =~ '^[0-9]+,[0-9]+$' ]] || die "Peekaboo private capture approval coordinates are invalid"
    "$CRABBOX" desktop click --provider tart --target macos --id "$resource" \
      --x "${private_prompt_coords%,*}" --y "${private_prompt_coords#*,}" >/dev/null
    approved=1
    sleep "${KEYPATH_LAB_CAPTURE_APPROVAL_SETTLE_SECONDS:-5}"
    private_prompt_coords=$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" \
      "/bin/zsh -lc $(printf %q "$private_prompt_command")")
    [[ -z "$private_prompt_coords" ]] || die "Peekaboo private capture approval prompt remained visible"
  fi

  if ((approved)); then
    record_command "$lease" passed approve-peekaboo-capture
    print "peekaboo_capture_approval\tpassed"
  else
    print "peekaboo_capture_approval\talready-approved"
  fi
}

rehydrate_managed_clone() {
  local lease=$1 manifest macos base_name base_enrollment_id enrollment_id repo provider_resource profile_dir guest_policy guest_repo parallels_cli evidence filename launcher copy_command verify_command identity_output
  local enrollment_ready enrollment_record enrollment_status attempt
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  base_name=$(field "$manifest" base_name)
  base_enrollment_id=$(managed_enrollment_id_for "$base_name")
  repo=$(field "$manifest" worktree)
  provider_resource=$(field "$manifest" provider_resource)
  profile_dir="$repo/.keypath-lab/managed-policy"
  guest_policy=/Library/KeyPathLab/managed-policy
  guest_repo="/Users/$([[ "$macos" == "15" ]] && print admin || print keypathqa)/crabbox/$lease/repo"
  evidence="$ARTIFACTS/$lease/managed-policy"
  for filename in keypath-pppc.mobileconfig keypath-system-extension.mobileconfig keypath-service-management.mobileconfig manifest.json; do
    [[ -f "$profile_dir/$filename" && ! -L "$profile_dir/$filename" ]] || die "managed policy archive is missing: $filename"
  done
  if [[ "$macos" == "15" ]]; then
    launcher=$(launcher_for "$macos")
    identity_output=$(cd "$repo" && "$launcher" run "$lease" -- /bin/zsh -lc \
      "/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice -a | /usr/bin/plutil -extract 0.IOPlatformUUID raw -")
    enrollment_id=$(print -r -- "$identity_output" | sed -nE '/^[A-Fa-f0-9-]{36}$/p' | tail -1)
    [[ "$enrollment_id" =~ '^[A-Fa-f0-9-]{36}$' ]] || die "managed clone hardware identity is unavailable"
    [[ "$enrollment_id" != "$base_enrollment_id" ]] || die "managed clone retained the base hardware identity; Tart random serial personalization is required"
    if [[ "${KEYPATH_LAB_TESTING:-0}" != "1" ]]; then
      enrollment_ready=0
      enrollment_record="$HOME/Library/Application Support/KeyPathLabMDM/state/nanomdm/dbkv/enrollments"
      enrollment_status=$(cd "$repo" && "$launcher" run "$lease" -- /usr/bin/profiles status -type enrollment 2>/dev/null || true)
      if print -r -- "$enrollment_status" | grep -Fq 'MDM enrollment: Yes' &&
        find "$enrollment_record" -type f -name "$enrollment_id.type" -print -quit 2>/dev/null | grep -q .; then
        enrollment_ready=1
        print "managed_clone_enrollment\talready-enrolled"
      else
        desktop_bootstrap "$lease" 1
        run_command "$lease" /bin/zsh Scripts/lab/mdm/enroll-clone-ui
        approve_peekaboo_capture "$lease"
        protected_click "$lease" "System Settings" "__ANY__" "Device Management" native 249 226 1
        sleep "${KEYPATH_LAB_PROFILE_LIST_SETTLE_SECONDS:-20}"
        protected_click "$lease" "System Settings" "Device Management" "Device Management" native 600 216 2
        protected_click "$lease" "System Settings" "Device Management" "Device Management" native 329 610
        secure_dialog_input "$lease" SecurityAgent AXSecureTextField Enroll 0
        for attempt in {1..150}; do
          enrollment_status=$(cd "$repo" && "$launcher" run "$lease" -- /usr/bin/profiles status -type enrollment 2>/dev/null || true)
          if print -r -- "$enrollment_status" | grep -Fq 'MDM enrollment: Yes' &&
            find "$enrollment_record" -type f -name "$enrollment_id.type" -print -quit 2>/dev/null | grep -q .; then
            enrollment_ready=1
            break
          fi
          sleep "${KEYPATH_LAB_MANAGED_ENROLLMENT_POLL_SECONDS:-0.2}"
        done
        ((enrollment_ready == 1)) && print "managed_clone_enrollment\tuser-approved"
      fi
      ((enrollment_ready == 1)) || die "managed clone did not establish its unique NanoMDM enrollment"
    fi
    copy_command="setopt errexit nounset pipefail; mkdir -p '$guest_policy';"
    for filename in keypath-pppc.mobileconfig keypath-system-extension.mobileconfig keypath-service-management.mobileconfig manifest.json; do
      copy_command+=" /usr/bin/install -m 444 '$guest_repo/.keypath-lab/managed-policy/$filename' '$guest_policy/$filename';"
    done
    (cd "$repo" && "$launcher" run "$lease" -- /bin/zsh -lc "sudo -n /bin/zsh -lc $(printf %q "$copy_command")")
  else
    enrollment_id=$base_enrollment_id
    [[ "$provider_resource" =~ '^[A-Fa-f0-9-]{36}$' ]] || die "invalid managed Parallels resource id"
    parallels_cli=${KEYPATH_LAB_PRLCTL:-"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"}
    [[ -x "$parallels_cli" ]] || die "Parallels CLI is unavailable"
    "$parallels_cli" exec "$provider_resource" /bin/mkdir -p "$guest_policy"
    for filename in keypath-pppc.mobileconfig keypath-system-extension.mobileconfig keypath-service-management.mobileconfig manifest.json; do
      "$parallels_cli" exec "$provider_resource" /usr/bin/tee "$guest_policy/$filename" < "$profile_dir/$filename" >/dev/null
    done
    "$parallels_cli" exec "$provider_resource" /bin/chmod 444 \
      "$guest_policy/keypath-pppc.mobileconfig" \
      "$guest_policy/keypath-system-extension.mobileconfig" \
      "$guest_policy/keypath-service-management.mobileconfig" \
      "$guest_policy/manifest.json"
  fi
  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" && "${KEYPATH_LAB_TEST_PUBLISH_MANAGED:-0}" != "1" ]]; then
    mkdir -p "$evidence"
    cp "$profile_dir/manifest.json" "$evidence/manifest.json"
    print "enrollment_id\t$enrollment_id"
  else
    "$repo/Scripts/lab/mdm/publish-managed-profiles" \
      --profile-dir "$profile_dir" \
      --evidence-dir "$evidence" \
      --enrollment-id "$enrollment_id" || return $?
  fi
  if [[ "$macos" == "15" ]]; then
    verify_command="'$guest_repo/Scripts/lab/mdm/verify-lane' managed-functional --manifest '$guest_policy/manifest.json'"
    (cd "$repo" && "$launcher" run "$lease" -- /bin/zsh -lc "sudo -n /bin/zsh -lc $(printf %q "$verify_command")")
  else
    "$parallels_cli" exec "$provider_resource" \
      "$guest_repo/Scripts/lab/mdm/verify-lane" managed-functional \
      --manifest "$guest_policy/manifest.json"
  fi
  print "managed_policy_rehydration\tpassed"
}

resume_managed_policy() {
  local lease=$1 manifest lane result
  manifest=$(owned_manifest "$lease")
  lane=$(field "$manifest" test_lane)
  [[ "$lane" == managed-functional ]] || die "managed policy resume requires a managed-functional lease"

  set +e
  (rehydrate_managed_clone "$lease") > "$LOGS/$lease/managed-policy.log" 2>&1
  result=$?
  set -e
  set_field "$manifest" managed_policy_result "$result"
  set_field "$manifest" managed_policy_at "$(utc_now)"
  cat "$LOGS/$lease/managed-policy.log"
  if ((result != 0)); then
    set_field "$manifest" status managed-policy-failed
    return "$result"
  fi
  set_field "$manifest" status ready
  record_command "$lease" passed managed-policy-rehydration
  print "managed_policy_resume\tpassed"
}

run_with_download() {
  local macos=$1 lease=$2 remote_file=$3 local_file=$4; shift 4
  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    "$CRABBOX" run --provider "$(provider_for "$macos")" --target macos --id "$lease" \
      --stop-after never --download "$remote_file=$local_file" -- "$@"
  elif [[ "$macos" == "15" ]]; then
    if [[ "${USER:-}" == "clawd" ]]; then export TART_HOME="$LAB_ROOT/TartHome-clawd"; else export TART_HOME="$LAB_ROOT/TartHome"; fi
    export PATH="$LAB_ROOT/CompatTools/bin:$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    "$CRABBOX" run --provider tart --target macos --id "$lease" \
      --tart-user admin --ssh-port 22 --stop-after never \
      --download "$remote_file=$local_file" -- "$@"
  else
    export PATH="$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    "$CRABBOX" run --provider parallels --target macos --id "$lease" \
      --parallels-user keypathqa --parallels-work-root /Users/keypathqa/crabbox \
      --ssh-port 22 --stop-after never --download "$remote_file=$local_file" -- "$@"
  fi
}

warmup_desktop() {
  local macos=$1 lane=$2 slug=$3
  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    if [[ "$(provider_for "$macos")" == "parallels" ]]; then
      "$CRABBOX" warmup --provider parallels --target macos --desktop \
        --parallels-template "$(base_for "$macos" "$lane" 1)" --slug "$slug" --ttl 2h
    else
      "$CRABBOX" warmup --provider tart --target macos --desktop --slug "$slug" --ttl 2h
    fi
  elif [[ "$macos" == "15" ]]; then
    if [[ "${USER:-}" == "clawd" ]]; then export TART_HOME="$LAB_ROOT/TartHome-clawd"; else export TART_HOME="$LAB_ROOT/TartHome"; fi
    configure_tart_path
    "$CRABBOX" warmup --provider tart --target macos --desktop \
      --tart-image "$(base_for "$macos" "$lane" 1)" \
      --tart-user admin --tart-cpu 4 --tart-memory 8192 --tart-random-serial --ssh-port 22 \
      --slug "$slug" --ttl 2h
  else
    export PATH="$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    "$CRABBOX" warmup --provider parallels --target macos --desktop \
      --parallels-template "$(base_for "$macos" "$lane" 1)" --parallels-user keypathqa \
      --parallels-work-root /Users/keypathqa/crabbox --ssh-port 22 \
      --slug "$slug" --ttl 2h
  fi
}

warmup_lease() {
  local macos=$1 lane=$2 slug=$3 desktop=$4
  if [[ "$desktop" == "1" ]]; then
    warmup_desktop "$macos" "$lane" "$slug"
  elif [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    "$(launcher_for "$macos")" warmup "$slug"
  elif [[ "$macos" == "15" ]]; then
    if [[ "${USER:-}" == "clawd" ]]; then export TART_HOME="$LAB_ROOT/TartHome-clawd"; else export TART_HOME="$LAB_ROOT/TartHome"; fi
    configure_tart_path
    "$CRABBOX" warmup --provider tart --target macos \
      --tart-image "$(base_for "$macos" "$lane")" \
      --tart-user admin --tart-cpu 4 --tart-memory 8192 --tart-random-serial --ssh-port 22 \
      --slug "$slug" --ttl 2h
  else
    export PATH="$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    "$CRABBOX" warmup --provider parallels --target macos \
      --parallels-template "$(base_for "$macos" "$lane")" \
      --parallels-user keypathqa --parallels-work-root /Users/keypathqa/crabbox \
      --ssh-port 22 --slug "$slug" --ttl 2h
  fi
}

preflight() {
  local mount_point
  [[ "$LAB_ROOT" == "$PRODUCTION_ROOT" || "${KEYPATH_LAB_TESTING:-0}" == "1" ]] || die "unsafe lab root"
  [[ -d "$LAB_ROOT" ]] || die "lab root is not mounted: $LAB_ROOT"
  [[ -x "$LAUNCHER_15" && -x "$LAUNCHER_26" && -x "$LAUNCHER_27" && -x "$CRABBOX" ]] || die "lab launchers or CrabBox are unavailable"
  if [[ "${KEYPATH_LAB_TESTING:-0}" != "1" ]]; then
    mount_point=$(df -P "$LAB_ROOT" | awk 'NR == 2 {for (i=6; i<=NF; i++) printf "%s%s", (i == 6 ? "" : " "), $i; print ""}')
    [[ "$mount_point" == "/Volumes/KeyPath Lab" ]] || die "lab root is not on the expected external volume"
  fi
  ensure_roots
  "$LAUNCHER_15" doctor
  "$LAUNCHER_26" doctor
  "$LAUNCHER_27" doctor
  print "host_os\t$(sw_vers -productVersion 2>/dev/null || print unknown)"
  print "host_build\t$(sw_vers -buildVersion 2>/dev/null || print unknown)"
  print "lab_root\t$LAB_ROOT"
  print "capacity_tart\t$(provider_capacity tart)"
  print "capacity_parallels\t$(provider_capacity parallels)"
  print "disk_reserve_minimum_gib\t${KEYPATH_LAB_MIN_FREE_DISK_GIB:-100}"
  print "disk_reserve_free_gib\t$(( $(host_free_kib) / 1024 / 1024 ))"
  print "safety\tdisposable-owned-leases-only"
}

prepare_upload() {
  valid_archive_key "$1"
  mktemp "/tmp/keypath-lab.XXXXXXXX"
}

archive_status() {
  local key=$1 commit=$2 installer_sha=$3 installer_name=$4 destination ready
  valid_archive_key "$key"
  [[ "$commit" =~ '^[0-9a-f]{40}$' ]] || die "invalid commit SHA"
  [[ "$installer_sha" =~ '^[0-9a-f]{64}$' ]] || die "invalid installer checksum"
  [[ "$installer_name" =~ '^[A-Za-z0-9._-]+$' ]] || die "invalid installer name"
  destination="$ARCHIVES/$key"
  ready="$destination/ready.tsv"
  [[ -f "$ready" && -d "$destination/repo/.git" ]] || return 1
  [[ "$(field "$ready" owner)" == "$OWNER" ]] || die "archive ownership mismatch"
  [[ "$(field "$ready" keypath_commit)" == "$commit" ]] || die "archive commit mismatch"
  [[ "$(field "$ready" installer_sha256)" == "$installer_sha" ]] || die "archive installer checksum mismatch"
  [[ "$(field "$ready" installer_name)" == "$installer_name" ]] || die "archive installer name mismatch"
  print "archive\tready\t$key"
}

install_archive() {
  local source=$1 key=$2 commit=$3 installer_sha=$4 installer_name=$5
  [[ "$source" =~ '^/tmp/keypath-lab\.[A-Za-z0-9]+$' ]] || die "invalid upload ticket"
  [[ -f "$source" && ! -L "$source" && -O "$source" ]] || die "upload ticket is not an owned regular file"
  valid_archive_key "$key"
  [[ "$commit" =~ '^[0-9a-f]{40}$' ]] || die "invalid commit SHA"
  [[ "$installer_sha" =~ '^[0-9a-f]{64}$' ]] || die "invalid installer checksum"
  [[ "$installer_name" =~ '^[A-Za-z0-9._-]+$' ]] || die "invalid installer name"
  ensure_roots
  local destination="$ARCHIVES/$key" staging="$ARCHIVES/.staging-$key-$$" lock="$ARCHIVES/.lock-$key" attempt
  if [[ -f "$destination/ready.tsv" ]]; then
    [[ "$(field "$destination/ready.tsv" owner)" == "$OWNER" ]] || die "archive ownership mismatch"
    [[ "$(field "$destination/ready.tsv" keypath_commit)" == "$commit" ]] || die "archive commit mismatch"
    [[ "$(field "$destination/ready.tsv" installer_sha256)" == "$installer_sha" ]] || die "archive installer checksum mismatch"
    rm -f "$source"
    print "archive\treused\t$key"
    return
  fi
  mkdir -p "$staging"
  tar -xzf "$source" -C "$staging"
  rm -f "$source"
  [[ -d "$staging/repo" && ! -e "$staging/repo/.git" ]] || die "uploaded payload must contain exported content without Git state"
  local actual_sha
  actual_sha=$(shasum -a 256 "$staging/repo/.keypath-lab/installer/$installer_name" | awk '{print $1}')
  [[ "$actual_sha" == "$installer_sha" ]] || die "installer checksum mismatch"
  git -C "$staging/repo" init -q
  git -C "$staging/repo" config user.name "KeyPath Lab"
  git -C "$staging/repo" config user.email "keypath-lab@localhost"
  git -C "$staging/repo" add -A
  # The product checkout ignores local campaign state under .keypath-lab, but
  # an immutable lab archive must retain its installer, policy, and fixture
  # payload when it is cloned into a disposable operation worktree.
  git -C "$staging/repo" add -f .keypath-lab
  GIT_AUTHOR_DATE=2000-01-01T00:00:00Z GIT_COMMITTER_DATE=2000-01-01T00:00:00Z git -C "$staging/repo" commit -q -m "KeyPath lab archive $commit"
  [[ -z "$(git -C "$staging/repo" status --porcelain)" ]] || die "archive checkout is dirty"
  {
    print "owner\t$OWNER"
    print "keypath_commit\t$commit"
    print "installer_sha256\t$installer_sha"
    print "installer_name\t$installer_name"
    print "created_at\t$(utc_now)"
  } > "$staging/ready.tsv"
  if ! mkdir "$lock" 2>/dev/null; then
    rm -rf "$staging"
    for attempt in {1..100}; do
      if [[ -f "$destination/ready.tsv" ]]; then
        [[ "$(field "$destination/ready.tsv" owner)" == "$OWNER" ]] || die "archive ownership mismatch after concurrent publish"
        [[ "$(field "$destination/ready.tsv" keypath_commit)" == "$commit" ]] || die "archive commit mismatch after concurrent publish"
        [[ "$(field "$destination/ready.tsv" installer_sha256)" == "$installer_sha" ]] || die "archive checksum mismatch after concurrent publish"
        print "archive\treused\t$key"
        return
      fi
      sleep 0.1
    done
    die "timed out waiting for concurrent archive publish: $key"
  fi
  if [[ -f "$destination/ready.tsv" ]]; then
    rm -rf "$staging"
    rmdir "$lock"
    print "archive\treused\t$key"
    return
  fi
  if [[ -e "$destination" ]]; then
    rm -rf "$staging"
    rmdir "$lock"
    die "archive destination exists without a ready marker: $key"
  fi
  mv "$staging" "$destination"
  rmdir "$lock"
  print "archive\tcreated\t$key"
}

derive_archive() {
  local overlay=$1 source_key=$2 key=$3 commit=$4 installer_sha=$5 installer_name=$6 harness_commit=$7
  [[ "$overlay" =~ '^/tmp/keypath-lab\.[A-Za-z0-9]+$' ]] || die "invalid upload ticket"
  [[ -f "$overlay" && ! -L "$overlay" && -O "$overlay" ]] || die "upload ticket is not an owned regular file"
  valid_archive_key "$source_key"
  valid_archive_key "$key"
  [[ "$commit" =~ '^[0-9a-f]{40}$' ]] || die "invalid commit SHA"
  [[ "$installer_sha" =~ '^[0-9a-f]{64}$' ]] || die "invalid installer checksum"
  [[ "$installer_name" =~ '^[A-Za-z0-9._-]+$' ]] || die "invalid installer name"
  [[ "$harness_commit" =~ '^[0-9a-f]{40}$' ]] || die "invalid harness commit"
  ensure_roots
  local source="$ARCHIVES/$source_key" destination="$ARCHIVES/$key"
  local staging="$ARCHIVES/.staging-$key-$$" lock="$ARCHIVES/.lock-$key" attempt actual_sha
  [[ -f "$source/ready.tsv" && -d "$source/repo/.git" ]] || die "source archive is unavailable"
  [[ "$(field "$source/ready.tsv" owner)" == "$OWNER" ]] || die "source archive ownership mismatch"
  [[ "$(field "$source/ready.tsv" keypath_commit)" == "$commit" ]] || die "source archive commit mismatch"
  [[ "$(field "$source/ready.tsv" installer_sha256)" == "$installer_sha" ]] || die "source archive installer mismatch"
  if [[ -f "$destination/ready.tsv" ]]; then
    rm -f "$overlay"
    print "archive\treused\t$key"
    return
  fi
  if ! mkdir "$lock" 2>/dev/null; then
    rm -f "$overlay"
    for attempt in {1..100}; do
      [[ -f "$destination/ready.tsv" ]] && { print "archive\treused\t$key"; return; }
      sleep 0.1
    done
    die "timed out waiting for concurrent derived archive publish: $key"
  fi
  git clone -q --no-hardlinks "$source/repo" "$staging/repo"
  rm -rf "$staging/repo/Scripts/lab"
  tar -xzf "$overlay" -C "$staging/repo"
  rm -f "$overlay"
  actual_sha=$(shasum -a 256 "$staging/repo/.keypath-lab/installer/$installer_name" | awk '{print $1}')
  [[ "$actual_sha" == "$installer_sha" ]] || die "derived archive installer checksum mismatch"
  git -C "$staging/repo" config user.name "KeyPath Lab"
  git -C "$staging/repo" config user.email "keypath-lab@localhost"
  git -C "$staging/repo" add -A
  git -C "$staging/repo" add -f .keypath-lab
  GIT_AUTHOR_DATE=2000-01-01T00:00:00Z GIT_COMMITTER_DATE=2000-01-01T00:00:00Z \
    git -C "$staging/repo" commit -q -m "KeyPath lab harness $harness_commit"
  [[ -z "$(git -C "$staging/repo" status --porcelain)" ]] || die "derived archive checkout is dirty"
  {
    print "owner\t$OWNER"
    print "keypath_commit\t$commit"
    print "harness_commit\t$harness_commit"
    print "installer_sha256\t$installer_sha"
    print "installer_name\t$installer_name"
    print "derived_from\t$source_key"
    print "created_at\t$(utc_now)"
  } > "$staging/ready.tsv"
  if [[ -e "$destination" ]]; then
    rm -rf "$staging"
    rmdir "$lock"
    die "derived archive destination exists without a ready marker: $key"
  fi
  mv "$staging" "$destination"
  rmdir "$lock"
  print "archive\tderived\t$key"
}

write_provisional_lease_manifest() {
  local lease=$1 slug=$2 macos=$3 lane=$4 provider=$5 archive_key=$6 commit=$7 installer_sha=$8 installer_name=$9 repo=${10} created=${11} expires=${12} desktop=${13}
  local manifest identity_scope
  valid_id "$lease"
  identity_scope=$(managed_identity_scope_for "$macos" "$lane")
  mkdir -p "$LEASES/$lease" "$LOGS/$lease" "$ARTIFACTS/$lease"
  manifest=$(manifest_path "$lease")
  [[ -e "$manifest" ]] && return
  {
    print "owner\t$OWNER"
    print "lease_id\t$lease"
    print "slug\t$slug"
    print "macos\t$macos"
    print "test_lane\t$lane"
    print "base_name\t$(base_for "$macos" "$lane" "$desktop")"
    print "managed_identity_scope\t$identity_scope"
    print "provider\t$provider"
    print "archive_key\t$archive_key"
    print "keypath_commit\t$commit"
    print "installer_sha256\t$installer_sha"
    print "installer_name\t$installer_name"
    print "worktree\t$repo"
    print "created_epoch\t$created"
    print "created_at\t$(utc_now)"
    print "expires_epoch\t$expires"
    print "status\tprovisioning"
    print "cleanup_status\tpending"
    print "desktop_enabled\t$([[ "$desktop" == "1" ]] && print true || print false)"
    print "provider_resource\tunknown"
  } > "$manifest"
}

lease_candidate_from_line() {
  print -r -- "$1" | awk '
    $1 == "leased" && $2 ~ /^cbx_[A-Za-z0-9]+$/ {print $2; exit}
    $0 ~ /^cbx_[A-Za-z0-9]+$/ {print; exit}
  '
}

create_lease() {
  local macos=$1 lane=$2 archive_key=$3 commit=$4 installer_sha=$5 installer_name=$6 ttl=$7 desktop=$8 tart_usb_passthrough=${9:-0}
  local launcher provider archive repo slug output lease created expires manifest guest_output product build operation ttl_seconds
  local provider_resource create_status candidate_file create_log exit_code managed_policy_exit identity_scope
  launcher=$(launcher_for "$macos")
  provider=$(provider_for "$macos")
  [[ "$lane" == "managed-functional" || "$lane" == "unmanaged-ui" ]] || die "invalid test lane: $lane"
  [[ ! ("$macos" == "27" && "$lane" == "managed-functional") ]] || die "managed-functional is not yet supported on macOS 27"
  [[ "$tart_usb_passthrough" == "0" || "$tart_usb_passthrough" == "1" ]] || die "invalid Tart USB passthrough setting"
  [[ "$tart_usb_passthrough" == "0" || "$macos" == "15" ]] || die "Tart USB passthrough requires macOS 15"
  if [[ "$tart_usb_passthrough" == "1" ]]; then
    [[ -x "$TART_USB_TOOL_ROOT/bin/crabbox-usb" ]] || die "USB-enabled CrabBox is unavailable"
    [[ -x "$TART_USB_TOOL_ROOT/tart-usb.app/Contents/MacOS/tart" ]] || die "signed USB-enabled Tart is unavailable"
    CRABBOX="$TART_USB_TOOL_ROOT/bin/crabbox-usb"
    export CRABBOX_TART_USB_PASSTHROUGH=true
    export PATH="$TART_USB_TOOL_ROOT/bin:$PATH"
  fi
  if [[ "${KEYPATH_LAB_TESTING:-0}" != "1" && "$macos" == "15" && "$lane" == "managed-functional" ]]; then
    desktop=1
  fi
  valid_archive_key "$archive_key"
  archive="$ARCHIVES/$archive_key"
  [[ -f "$archive/ready.tsv" && -d "$archive/repo/.git" ]] || die "prepared archive not found: $archive_key"
  ttl_seconds=$(duration_seconds "$ttl")
  (( ttl_seconds > 0 && ttl_seconds <= 7200 )) || die "TTL must be between 1 second and 2 hours"
  trap 'release_admission_lock' EXIT
  trap 'release_admission_lock_and_exit 130' INT
  trap 'release_admission_lock_and_exit 143' TERM
  trap 'release_admission_lock_and_exit 129' HUP
  acquire_admission_lock "$provider" || {
    exit_code=$?
    trap - EXIT INT TERM HUP
    return "$exit_code"
  }
  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" && -n "${KEYPATH_LAB_TEST_PAUSE_AFTER_ADMISSION_LOCK:-}" ]]; then
    sleep "$KEYPATH_LAB_TEST_PAUSE_AFTER_ADMISSION_LOCK"
  fi
  assert_provider_capacity "$provider" || return $?
  assert_managed_identity_available "$macos" "$lane" || return $?
  assert_internal_disk_reserve || return $?
  created=$(now_epoch)
  expires=$((created + ttl_seconds))
  slug="keypath${macos}-$(print -r -- "$commit" | cut -c1-8)-$(date -u +%Y%m%d%H%M%S)-$$"
  operation="$OPERATIONS/$slug"
  mkdir -p "$operation"
  git clone -q --local --no-hardlinks "$archive/repo" "$operation/repo"
  repo="$operation/repo"
  prepare_worktree "$repo"
  create_log="$operation/create.log"
  candidate_file="$operation/lease-candidate.tsv"
  : > "$create_log"
  : > "$candidate_file"
  set +e
  (cd "$repo" && warmup_lease "$macos" "$lane" "$slug" "$desktop" 2>&1) | while IFS= read -r line || [[ -n "$line" ]]; do
    print -r -- "$line"
    print -r -- "$line" >> "$create_log"
    candidate=$(lease_candidate_from_line "$line")
    if [[ -n "$candidate" ]]; then
      print -r -- "$candidate" > "$candidate_file"
      write_provisional_lease_manifest "$candidate" "$slug" "$macos" "$lane" "$provider" "$archive_key" "$commit" "$installer_sha" "$installer_name" "$repo" "$created" "$expires" "$desktop"
    fi
  done
  create_status=${pipestatus[1]}
  set -e
  output=$(<"$create_log")
  lease=$(<"$candidate_file")
  [[ -n "$lease" ]] || die "CrabBox did not report a lease id; inspect provider inventory before cleanup"
  valid_id "$lease"
  provider_resource=$(print -r -- "$output" | sed -nE 's/.* (vm|instance)=([^ ]+).*/\2/p' | tail -1)
  mkdir -p "$LEASES/$lease" "$LOGS/$lease" "$ARTIFACTS/$lease"
  manifest=$(manifest_path "$lease")
  identity_scope=$(managed_identity_scope_for "$macos" "$lane")
  {
    print "owner\t$OWNER"
    print "lease_id\t$lease"
    print "slug\t$slug"
    print "macos\t$macos"
    print "test_lane\t$lane"
    print "base_name\t$(base_for "$macos" "$lane" "$desktop")"
    print "managed_identity_scope\t$identity_scope"
    print "provider\t$provider"
    print "archive_key\t$archive_key"
    print "keypath_commit\t$commit"
    print "installer_sha256\t$installer_sha"
    print "installer_name\t$installer_name"
    print "worktree\t$repo"
    print "created_epoch\t$created"
    print "created_at\t$(utc_now)"
    print "expires_epoch\t$expires"
    print "status\tcreated"
    print "cleanup_status\tpending"
    print "desktop_enabled\t$([[ "$desktop" == "1" ]] && print true || print false)"
    print "tart_usb_passthrough\t$([[ "$tart_usb_passthrough" == "1" ]] && print true || print false)"
    print "provider_resource\t${provider_resource:-unknown}"
  } > "$manifest"
  # Emit the durable controller identity as soon as the owned manifest exists.
  # Callers must be able to adopt and clean up a lease even when a later guest
  # verification or managed-policy step fails.
  print "lease_id\t$lease"
  if (( create_status != 0 )); then
    set_field "$manifest" status provisioning-failed
    set_field "$manifest" provision_result "$create_status"
    release_admission_lock
    trap - EXIT INT TERM HUP
    return "$create_status"
  fi
  print -r -- "$output" > "$LOGS/$lease/create.log"
  guest_output=$(cd "$repo" && "$launcher" run "$lease" -- /bin/zsh -lc 'printf "product=%s\n" "$(sw_vers -productVersion)"; printf "build=%s\n" "$(sw_vers -buildVersion)"' 2>&1) || {
    record_command "$lease" failed sw_vers
    set_field "$manifest" status verification-failed
    print -r -- "$guest_output" > "$LOGS/$lease/guest-version.log"
    die "lease created but guest verification failed: $lease"
  }
  print -r -- "$guest_output" > "$LOGS/$lease/guest-version.log"
  product=$(print -r -- "$guest_output" | sed -n 's/^product=//p' | tail -1)
  build=$(print -r -- "$guest_output" | sed -n 's/^build=//p' | tail -1)
  set_field "$manifest" macos_product_version "${product:-unknown}"
  set_field "$manifest" macos_build "${build:-unknown}"
  if [[ "$lane" == managed-functional ]]; then
    set +e
    (rehydrate_managed_clone "$lease") > "$LOGS/$lease/managed-policy.log" 2>&1
    managed_policy_exit=$?
    set -e
    set_field "$manifest" managed_policy_result "$managed_policy_exit"
    set_field "$manifest" managed_policy_at "$(utc_now)"
    cat "$LOGS/$lease/managed-policy.log"
    if ((managed_policy_exit != 0)); then
      set_field "$manifest" status managed-policy-failed
      release_admission_lock
      trap - EXIT INT TERM HUP
      return "$managed_policy_exit"
    fi
    record_command "$lease" passed managed-policy-rehydration
  fi
  set_field "$manifest" status ready
  record_command "$lease" passed sw_vers
  release_admission_lock
  trap - EXIT INT TERM HUP
  print "lease_id\t$lease"
  print "manifest\t$manifest"
}

install_app() {
  local lease=$1 manifest macos lane repo installer_name provider_resource guest_repo command exit_code admission_command
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  lane=$(field "$manifest" test_lane)
  repo=$(field "$manifest" worktree)
  installer_name=$(field "$manifest" installer_name)
  provider_resource=$(field "$manifest" provider_resource)
  prepare_worktree "$repo"
  guest_repo="/Users/$([[ "$macos" == "15" ]] && print admin || print keypathqa)/crabbox/$lease/repo"
  admission_command="cd '$guest_repo'; Scripts/lab/mdm/verify-lane '$lane'"
  if [[ "$lane" == "managed-functional" ]]; then
    admission_command+=" --manifest /Library/KeyPathLab/managed-policy/manifest.json"
  fi
  command="setopt errexit nounset pipefail; $admission_command; rm -rf /tmp/keypath-install; mkdir -p /tmp/keypath-install; ditto -x -k '$guest_repo/.keypath-lab/installer/$installer_name' /tmp/keypath-install; cd '$guest_repo'; if [[ '$lane' == managed-functional ]]; then Scripts/lab/mdm/verify-artifact-policy --app /tmp/keypath-install/KeyPath.app --manifest /Library/KeyPathLab/managed-policy/manifest.json; fi; rm -rf /Applications/KeyPath.app; ditto /tmp/keypath-install/KeyPath.app /Applications/KeyPath.app"
  set +e
  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    print "admission $lane" >> "$LOGS/$lease/install-app.log"
    print "install-app $macos $lease $provider_resource" >> "$LOGS/$lease/install-app.log"
    exit_code=0
  elif [[ "$macos" == "15" ]]; then
    (cd "$repo" && "$(launcher_for "$macos")" run "$lease" -- /bin/zsh -lc "sudo -n /bin/zsh -lc $(printf %q "$command")") > "$LOGS/$lease/install-app.log" 2>&1
    exit_code=$?
  else
    [[ "$provider_resource" =~ '^[A-Fa-f0-9-]+$' && "$provider_resource" != "unknown" ]] || die "invalid Parallels resource id"
    "/Applications/Parallels Desktop.app/Contents/MacOS/prlctl" exec "$provider_resource" /bin/zsh -lc "$command" > "$LOGS/$lease/install-app.log" 2>&1
    exit_code=$?
  fi
  set -e
  set_field "$manifest" install_app_result "$exit_code"
  set_field "$manifest" admission_result "$exit_code"
  set_field "$manifest" install_app_at "$(utc_now)"
  cat "$LOGS/$lease/install-app.log"
  return "$exit_code"
}

install_runtime() {
  local lease=$1 manifest lane runtime_status exit_code recovery_exit
  manifest=$(owned_manifest "$lease")
  lane=$(field "$manifest" test_lane)
  runtime_status=$(field "$manifest" install_runtime_status)

  if [[ "$runtime_status" == "mutation-started" ]]; then
    # A controller interruption can strand the manifest before the guest
    # installer mutation begins. Recover only when durable guest evidence proves
    # that no install report or mutation state was ever written.
    set +e
    (run_command "$lease" /bin/zsh -lc \
      'out=.keypath-lab/scenario-output/install-runtime; test ! -e "$out/state.tsv" && test ! -e "$out/install-report.json" && test -e "$out/preflight-inspect.json"')
    recovery_exit=$?
    set -e
    if ((recovery_exit == 0)); then
      set_field "$manifest" install_runtime_status staged
      runtime_status=staged
      print "install_runtime_recovery\tpreflight-only"
    else
      die "install-runtime has an uncertain prior mutation; inspect artifacts before any retry"
    fi
  fi
  if [[ "$runtime_status" == "failed" ]]; then
    die "install-runtime has an uncertain or failed prior mutation; inspect artifacts before any retry"
  fi
  if [[ "$runtime_status" == "passed" ]]; then
    print "install_runtime\tpassed"
    return 0
  fi

  if [[ "$runtime_status" == "uninstalled" ]]; then
    # Preserve the first installation's durable evidence before creating a
    # fresh output directory for the reinstall. Fail closed rather than
    # overwriting either evidence set on an ambiguous retry.
    run_command "$lease" /bin/zsh -lc \
      'source=.keypath-lab/scenario-output/install-runtime; target=.keypath-lab/scenario-output/install-runtime-before-reinstall; test -d "$source"; test ! -e "$target"; mv "$source" "$target"' || \
      die "could not preserve the first install-runtime evidence before reinstall"
    install_app "$lease" || {
      set_field "$manifest" install_runtime_status failed
      set_field "$manifest" install_runtime_at "$(utc_now)"
      return 1
    }
    set_field "$manifest" install_runtime_status staged
    runtime_status=staged
  fi

  if [[ -z "$runtime_status" ]]; then
    install_app "$lease" || {
      set_field "$manifest" install_runtime_status failed
      set_field "$manifest" install_runtime_at "$(utc_now)"
      return 1
    }
    set_field "$manifest" install_runtime_status staged
  fi

  if [[ "$runtime_status" != "awaiting-approval" ]]; then
    set_field "$manifest" install_runtime_status mutation-started
  fi

  set +e
  (run_command "$lease" /bin/zsh Scripts/lab/install-runtime "$lane")
  exit_code=$?
  set -e
  case "$exit_code" in
    0) set_field "$manifest" install_runtime_status passed ;;
    4) set_field "$manifest" install_runtime_status awaiting-approval ;;
    *) set_field "$manifest" install_runtime_status failed ;;
  esac
  set_field "$manifest" install_runtime_at "$(utc_now)"
  return "$exit_code"
}

install_fixture() {
  local lease=$1 manifest macos lane repo fixture_name provider_resource guest_repo command exit_code admission_command
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  lane=$(field "$manifest" test_lane)
  repo=$(field "$manifest" worktree)
  provider_resource=$(field "$manifest" provider_resource)
  prepare_worktree "$repo"
  fixture_name=$(awk -F $'\t' '$1 == "fixture_name" {print $2}' "$repo/.keypath-lab/source.tsv")
  [[ -n "$fixture_name" && "$fixture_name" =~ '^[A-Za-z0-9._-]+$' ]] || die "lease does not contain a valid upgrade fixture"
  [[ -f "$repo/.keypath-lab/fixtures/$fixture_name" ]] || die "upgrade fixture is missing from lease archive"
  guest_repo="/Users/$([[ "$macos" == "15" ]] && print admin || print keypathqa)/crabbox/$lease/repo"
  admission_command="cd '$guest_repo'; Scripts/lab/mdm/verify-lane '$lane'"
  if [[ "$lane" == "managed-functional" ]]; then
    admission_command+=" --manifest /Library/KeyPathLab/managed-policy/manifest.json"
  fi
  command="setopt errexit nounset pipefail; $admission_command; rm -rf /tmp/keypath-fixture-install; mkdir -p /tmp/keypath-fixture-install; ditto -x -k '$guest_repo/.keypath-lab/fixtures/$fixture_name' /tmp/keypath-fixture-install; cd '$guest_repo'; if [[ '$lane' == managed-functional ]]; then Scripts/lab/mdm/verify-artifact-policy --app /tmp/keypath-fixture-install/KeyPath.app --manifest /Library/KeyPathLab/managed-policy/manifest.json; fi; rm -rf /Applications/KeyPath.app; ditto /tmp/keypath-fixture-install/KeyPath.app /Applications/KeyPath.app"
  set +e
  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    print "admission $lane" >> "$LOGS/$lease/install-fixture.log"
    print "install-fixture $macos $lease $provider_resource $fixture_name" >> "$LOGS/$lease/install-fixture.log"
    exit_code=0
  elif [[ "$macos" == "15" ]]; then
    (cd "$repo" && "$(launcher_for "$macos")" run "$lease" -- /bin/zsh -lc "sudo -n /bin/zsh -lc $(printf %q "$command")") > "$LOGS/$lease/install-fixture.log" 2>&1
    exit_code=$?
  else
    [[ "$provider_resource" =~ '^[A-Fa-f0-9-]+$' && "$provider_resource" != "unknown" ]] || die "invalid Parallels resource id"
    "/Applications/Parallels Desktop.app/Contents/MacOS/prlctl" exec "$provider_resource" /bin/zsh -lc "$command" > "$LOGS/$lease/install-fixture.log" 2>&1
    exit_code=$?
  fi
  set -e
  set_field "$manifest" install_fixture_result "$exit_code"
  set_field "$manifest" install_fixture_at "$(utc_now)"
  cat "$LOGS/$lease/install-fixture.log"
  return "$exit_code"
}

run_command() {
  local lease=$1; shift
  local manifest macos launcher repo log exit_code guest_home guest_path
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  launcher=$(launcher_for "$macos")
  repo=$(field "$manifest" worktree)
  guest_home="/Users/$([[ "$macos" == "15" ]] && print admin || print keypathqa)"
  guest_path="$guest_home/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  prepare_worktree "$repo"
  log="$LOGS/$lease/run-$(date -u +%Y%m%dT%H%M%SZ).log"
  set +e
  (cd "$repo" && "$launcher" run "$lease" -- /usr/bin/env "PATH=$guest_path" "$@") 2>&1 | tee "$log"
  exit_code=${pipestatus[1]}
  set -e
  if (( exit_code == 0 )); then record_command "$lease" passed "$@"; else record_command "$lease" "failed:$exit_code" "$@"; fi
  set_field "$manifest" last_result "$exit_code"
  set_field "$manifest" last_run_at "$(utc_now)"
  return "$exit_code"
}

secure_dialog_input() {
  local lease=$1 app=$2 field_label=$3 submit_button=$4 already_focused=$5
  local manifest macos resource key ip secret_file guest_command exit_code
  local focus_command focus_result button_geometry_command button_coords postcondition_command postcondition_result
  local click_x click_y focus_x focus_y
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  [[ "$macos" == "15" ]] || die "secure dialog input currently supports only the Tart macOS 15 lane"
  [[ "$(field "$manifest" desktop_enabled)" == "true" ]] || die "secure dialog input requires a desktop-enabled lease"
  resource=$(field "$manifest" provider_resource)
  [[ "$resource" =~ '^[A-Za-z0-9._-]+$' && "$resource" != "unknown" ]] || die "invalid Tart resource id"
  key="$HOME/Library/Application Support/crabbox/testboxes/$lease/id_ed25519"
  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    key="${KEYPATH_LAB_TEST_SSH_KEY:?test SSH key is required}"
    secret_file="${KEYPATH_LAB_TEST_SECRET_FILE:?test secret file is required}"
  else
    [[ -f "$key" && ! -L "$key" && -O "$key" ]] || die "owned CrabBox SSH key not found for lease"
    secret_file=$(mktemp "$STATE_ROOT/.secure-input.XXXXXXXX")
    chmod 600 "$secret_file"
    typeset -g KEYPATH_LAB_SECURE_TEMP="$secret_file"
    trap '[[ -z ${KEYPATH_LAB_SECURE_TEMP:-} ]] || rm -f "$KEYPATH_LAB_SECURE_TEMP"' EXIT
    /opt/homebrew/bin/sops -d "$HOME/dotfiles/secrets.env" | awk -F= '$1 == "KEYPATH_TART_ADMIN_PASSWORD" {sub(/^[^=]*=/, ""); printf "%s", $0; found=1} END {if (!found) exit 1}' > "$secret_file" || die "KEYPATH_TART_ADMIN_PASSWORD is unavailable"
  fi
  [[ -s "$secret_file" ]] || die "secure input secret is empty"
  if [[ "${USER:-}" == "clawd" ]]; then export TART_HOME="$LAB_ROOT/TartHome-clawd"; else export TART_HOME="$LAB_ROOT/TartHome"; fi
  ip=$($TART ip "$resource")
  [[ "$ip" =~ '^[0-9A-Fa-f:.]+$' ]] || die "Tart returned an invalid guest address"
  export PATH="$LAB_ROOT/CompatTools/bin:$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  if [[ "$field_label" == "AXSecureTextField" ]]; then
    [[ -n "$submit_button" ]] || die "AXSecureTextField requires a submit button for postcondition verification"
    [[ "$already_focused" == "0" ]] || die "AXSecureTextField does not use --already-focused"

    # SecurityAgent rejects synthetic Accessibility typing. Use Accessibility
    # only to focus and inspect the protected sheet, then deliver the secret as
    # real RFB key events over CrabBox stdin. The secret never enters argv,
    # guest storage, or controller output.
    focus_command=$'/usr/bin/osascript -l JavaScript -e \'\nfunction descendants(element) {\n  var result = [];\n  try {\n    var children = element.uiElements();\n    for (var i = 0; i < children.length; i++) {\n      result.push(children[i]);\n      result = result.concat(descendants(children[i]));\n    }\n  } catch (_) {}\n  return result;\n}\nfunction run(argv) {\n  var matches = Application("System Events").processes.whose({name: argv[0]})();\n  if (matches.length === 0 || matches[0].windows().length === 0) throw new Error("dialog process not found");\n  var window = matches[0].windows[0];\n  var sheets = window.sheets();\n  var root = sheets.length > 0 ? sheets[0] : window;\n  var fields = root.textFields.whose({subrole: "AXSecureTextField"})();\n  var field = fields.length > 0 ? fields[0] : descendants(root).find(function (element) {\n    try { return element.subrole() === "AXSecureTextField"; } catch (_) { return false; }\n  });\n  if (!field) throw new Error("secure text field not found");\n  field.focused = true;\n  var position = field.position();\n  var size = field.size();\n  return (field.focused() ? "focused" : "not-focused") + "," + Math.round(position[0] + size[0] / 2) + "," + Math.round(position[1] + size[1] / 2);\n}\' -- '$(printf %q "$app")
    set +e
    focus_result=$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$focus_command")" </dev/null)
    exit_code=$?
    set -e
    if (( exit_code != 0 )) || [[ ! "$focus_result" =~ '^focused,[0-9]+,[0-9]+$' ]]; then
      record_command "$lease" "failed:41" secure-dialog-input --app "$app" --field "$field_label" --submit "$submit_button"
      die "secure dialog input failed while focusing the field"
    fi
    IFS=',' read -r _ focus_x focus_y <<< "$focus_result"

    # Tart's 1024x768 RFB viewport uses the same coordinate space reported by
    # Accessibility. The 2048x1536 backing store is a Retina implementation
    # detail; scaling AX coordinates to backing pixels moves the native click
    # outside the protected sheet.

    set +e
    "$CRABBOX" desktop click --provider tart --target macos --id "$resource" --x "$focus_x" --y "$focus_y" >/dev/null 2>&1
    exit_code=$?
    set -e
    if (( exit_code != 0 )); then
      record_command "$lease" "failed:41" secure-dialog-input --app "$app" --field "$field_label" --submit "$submit_button"
      die "secure dialog input failed while giving the field native pointer focus"
    fi

    # Secure authorization sheets ignore Tart's VNC key events. Stream the
    # secret directly into one guest osascript process and synthesize local key
    # events in the logged-in session. The value never enters argv, logs, the
    # clipboard, or a guest file. The process returns only a filled/empty
    # postcondition; it never prints the value or its length.
    local secure_type_command
    secure_type_command=$'/usr/bin/osascript -l JavaScript -e \'\nObjC.import("Foundation");\nfunction descendants(element) {\n  var result = [];\n  try {\n    var children = element.uiElements();\n    for (var i = 0; i < children.length; i++) {\n      result.push(children[i]);\n      result = result.concat(descendants(children[i]));\n    }\n  } catch (_) {}\n  return result;\n}\nfunction run(argv) {\n  var data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;\n  var payload = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js;\n  if (!payload) throw new Error("secure input is empty");\n  var events = Application("System Events");\n  var process = events.processes.byName(argv[0]);\n  if (process.windows().length === 0) throw new Error("secure dialog process not found");\n  var window = process.windows[0];\n  var sheets = window.sheets();\n  var root = sheets.length > 0 ? sheets[0] : window;\n  var fields = root.textFields.whose({subrole: "AXSecureTextField"})();\n  var field = fields.length > 0 ? fields[0] : descendants(root).find(function(element) {\n    try { return element.subrole() === "AXSecureTextField"; } catch (_) { return false; }\n  });\n  if (!field) throw new Error("secure text field not found");\n  field.focused = true;\n  for (var i = 0; i < 128; i++) events.keyCode(51);\n  events.keystroke(payload);\n  delay(0.2);\n  if (String(field.value()).length === 0) throw new Error("secure text field remained empty");\n  return "filled";\n}\' -- '$(printf %q "$app")
    set +e
    "$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$secure_type_command")" < "$secret_file" >/dev/null 2>&1
    exit_code=$?
    set -e
    if (( exit_code != 0 )); then
      record_command "$lease" "failed:42" secure-dialog-input --app "$app" --field "$field_label" --submit "$submit_button"
      die "secure dialog input failed while streaming masked input"
    fi

    button_geometry_command=$'/usr/bin/osascript -l JavaScript -e \'\nfunction descendants(element) {\n  var result = [];\n  try {\n    var children = element.uiElements();\n    for (var i = 0; i < children.length; i++) {\n      result.push(children[i]);\n      result = result.concat(descendants(children[i]));\n    }\n  } catch (_) {}\n  return result;\n}\nfunction run(argv) {\n  var process = Application("System Events").processes.byName(argv[0]);\n  var window = process.windows[0];\n  var sheets = window.sheets();\n  var root = sheets.length > 0 ? sheets[0] : window;\n  var button = root.buttons().find(function (element) {\n    try { return element.role() === "AXButton" && (element.name() === argv[1] || element.description() === argv[1]); } catch (_) { return false; }\n  });\n  if (!button) button = descendants(root).find(function (element) {\n    try { return element.role() === "AXButton" && (element.name() === argv[1] || element.description() === argv[1]); } catch (_) { return false; }\n  });\n  if (!button) throw new Error("submit button not found");\n  var position = button.position();\n  var size = button.size();\n  return Math.round(position[0] + size[0] / 2) + "," + Math.round(position[1] + size[1] / 2);\n}\' -- '$(printf %q "$app")' '$(printf %q "$submit_button")
    set +e
    button_coords=$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$button_geometry_command")" </dev/null)
    exit_code=$?
    set -e
    if (( exit_code != 0 )) || [[ ! "$button_coords" =~ '^[0-9]+,[0-9]+$' ]]; then
      record_command "$lease" "failed:78" secure-dialog-input --app "$app" --field "$field_label" --submit "$submit_button"
      die "secure dialog input could not resolve valid SecurityAgent button geometry"
    fi
    IFS=',' read -r click_x click_y <<< "$button_coords"

    set +e
    "$CRABBOX" desktop click --provider tart --target macos --id "$resource" --x "$click_x" --y "$click_y" >/dev/null 2>&1
    exit_code=$?
    set -e
    if (( exit_code != 0 )); then
      record_command "$lease" "failed:43" secure-dialog-input --app "$app" --field "$field_label" --submit "$submit_button"
      die "secure dialog input failed while submitting the dialog"
    fi

    postcondition_command=$'/usr/bin/osascript -l JavaScript -e \'\nfunction descendants(element) {\n  var result = [];\n  try {\n    var children = element.uiElements();\n    for (var i = 0; i < children.length; i++) {\n      result.push(children[i]);\n      result = result.concat(descendants(children[i]));\n    }\n  } catch (_) {}\n  return result;\n}\nfunction run(argv) {\n  var matches = Application("System Events").processes.whose({name: argv[0]})();\n  if (matches.length === 0 || matches[0].windows().length === 0) return "closed";\n  var window = matches[0].windows[0];\n  var sheets = window.sheets();\n  var root = sheets.length > 0 ? sheets[0] : window;\n  var open = root.textFields.whose({subrole: "AXSecureTextField"})().length > 0 || descendants(root).some(function (element) {\n    try { return element.subrole() === "AXSecureTextField"; } catch (_) { return false; }\n  });\n  return open ? "open" : "closed";\n}\' -- '$(printf %q "$app")
    postcondition_result=open
    for attempt in {1..150}; do
      postcondition_result=$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$postcondition_command")" </dev/null) || postcondition_result=open
      [[ "$postcondition_result" == "closed" ]] && break
      sleep 0.1
    done
    if [[ "$postcondition_result" != "closed" ]]; then
      record_command "$lease" "failed:77" secure-dialog-input --app "$app" --field "$field_label" --submit "$submit_button"
      die "secure dialog input was submitted but the SecurityAgent sheet did not close"
    fi

    if [[ "${KEYPATH_LAB_TESTING:-0}" != "1" ]]; then
      rm -f "$secret_file"
      KEYPATH_LAB_SECURE_TEMP=
    fi
    record_command "$lease" passed secure-dialog-input --app "$app" --field "$field_label" --submit "$submit_button"
    print "secure_dialog_input\tpassed"
    return 0
  fi

  # Peekaboo's MCP type response contains the typed value. Suppress both output
  # streams for that command so the secret cannot enter controller logs.
  local refresh_command field_command click_command submit_command submit_label_quoted button_geometry_command postcondition_command
  local -a refresh_args focus_args click_args submit_args button_geometry_args postcondition_args
  guest_command='set -euo pipefail; command -v /opt/homebrew/bin/peekaboo >/dev/null; command -v /opt/homebrew/bin/mcporter >/dev/null; '
  if [[ "$already_focused" == "0" ]]; then
    refresh_args=(/opt/homebrew/bin/peekaboo see --app "$app" --json)
    printf -v refresh_command '%q ' "${refresh_args[@]}"
    guest_command+="$refresh_command >/dev/null || exit 40; "
    # Peekaboo 3 accepts the semantic target as the positional click argument.
    # --query belongs to Scripts/lab/peekaboo-ui and is not a Peekaboo option.
    click_args=(/opt/homebrew/bin/peekaboo click "$field_label" --app "$app" --foreground --json)
    printf -v click_command '%q ' "${click_args[@]}"
    guest_command+="$click_command >/dev/null || exit 41; "
  elif [[ -n "$submit_button" ]]; then
    die "--already-focused cannot be combined with a submit button"
  fi
  guest_command+='PEEKABOO_VISUALIZER_MASK_TYPED_TEXT=true /opt/homebrew/bin/mcporter call --stdio '\''peekaboo mcp serve --bridge-socket "$HOME/Library/Application Support/Peekaboo/daemon.sock"'\'' --env PEEKABOO_VISUALIZER_MASK_TYPED_TEXT=true type text=@/dev/stdin clear=true --output json --timeout 20000 >/dev/null 2>&1 || exit 42'
  if [[ -n "$submit_button" ]]; then
    submit_args=(/opt/homebrew/bin/peekaboo click "$submit_button" --app "$app" --foreground --json)
    printf -v submit_command '%q ' "${submit_args[@]}"
    printf -v submit_label_quoted '%q' "$submit_button"
    guest_command+="; $refresh_command >/tmp/keypath-secure-submit.json || exit 44; if ! $submit_command >/dev/null; then $refresh_command >/tmp/keypath-secure-submit.json || exit 43; /usr/bin/env python3 -c 'import json,sys; elements=json.load(open(sys.argv[1])).get(\"data\",{}).get(\"ui_elements\",[]); raise SystemExit(1 if any(e.get(\"label\")==sys.argv[2] for e in elements) else 0)' /tmp/keypath-secure-submit.json $submit_label_quoted || exit 43; fi"
    guest_command+="; for attempt in {1..150}; do $refresh_command >/tmp/keypath-secure-postcondition.json || exit 44; /usr/bin/env python3 -c 'import json,sys; elements=json.load(open(sys.argv[1])).get(\"data\",{}).get(\"ui_elements\",[]); labels={e.get(\"label\") for e in elements}; raise SystemExit(0 if sys.argv[2] not in labels and sys.argv[3] not in labels else 1)' /tmp/keypath-secure-postcondition.json $(printf %q "$field_label") $submit_label_quoted && break; sleep 0.1; done; /usr/bin/env python3 -c 'import json,sys; elements=json.load(open(sys.argv[1])).get(\"data\",{}).get(\"ui_elements\",[]); labels={e.get(\"label\") for e in elements}; raise SystemExit(0 if sys.argv[2] not in labels and sys.argv[3] not in labels else 79)' /tmp/keypath-secure-postcondition.json $(printf %q "$field_label") $submit_label_quoted"
  fi
  set +e
  "$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$guest_command")" < "$secret_file"
  exit_code=$?
  set -e
  if [[ "${KEYPATH_LAB_TESTING:-0}" != "1" ]]; then
    rm -f "$secret_file"
    KEYPATH_LAB_SECURE_TEMP=
  fi
  if (( exit_code == 0 )); then
    record_command "$lease" passed secure-dialog-input --app "$app" --field "$field_label" ${submit_button:+--submit "$submit_button"}
    print "secure_dialog_input\tpassed"
  elif (( exit_code == 40 )); then
    record_command "$lease" "failed:$exit_code" secure-dialog-input --app "$app" --field "$field_label" ${submit_button:+--submit "$submit_button"}
    die "secure dialog input failed while refreshing the dialog snapshot"
  elif (( exit_code == 41 )); then
    record_command "$lease" "failed:$exit_code" secure-dialog-input --app "$app" --field "$field_label" ${submit_button:+--submit "$submit_button"}
    die "secure dialog input failed while focusing the field"
  elif (( exit_code == 42 )); then
    record_command "$lease" "failed:$exit_code" secure-dialog-input --app "$app" --field "$field_label" ${submit_button:+--submit "$submit_button"}
    die "secure dialog input failed while streaming masked input"
  elif (( exit_code == 43 )); then
    record_command "$lease" "failed:$exit_code" secure-dialog-input --app "$app" --field "$field_label" ${submit_button:+--submit "$submit_button"}
    die "secure dialog input failed while submitting the dialog"
  elif (( exit_code == 44 )); then
    record_command "$lease" "failed:$exit_code" secure-dialog-input --app "$app" --field "$field_label" ${submit_button:+--submit "$submit_button"}
    die "secure dialog input failed while refreshing the submitted dialog"
  elif (( exit_code == 77 )); then
    record_command "$lease" "failed:$exit_code" secure-dialog-input --app "$app" --field "$field_label" ${submit_button:+--submit "$submit_button"}
    die "secure dialog input was submitted but the SecurityAgent sheet did not close"
  elif (( exit_code == 78 )); then
    record_command "$lease" "failed:$exit_code" secure-dialog-input --app "$app" --field "$field_label" ${submit_button:+--submit "$submit_button"}
    die "secure dialog input could not resolve valid SecurityAgent button geometry"
  elif (( exit_code == 79 )); then
    record_command "$lease" "failed:$exit_code" secure-dialog-input --app "$app" --field "$field_label" ${submit_button:+--submit "$submit_button"}
    die "secure dialog input was submitted but the authentication sheet did not close"
  else
    record_command "$lease" "failed:$exit_code" secure-dialog-input --app "$app" --field "$field_label" ${submit_button:+--submit "$submit_button"}
    die "secure dialog input failed"
  fi
}

protected_click() {
  local lease=$1 app=$2 expected_before=$3 expected_after=$4 coordinate_space=$5 x=$6 y=$7 count=${8:-1}
  local manifest macos resource key ip before after before_frontmost after_frontmost guest_command geometry_command geometry
  local occlusion occlusion_command occlusion_qualification_script
  local native_width native_height logical_width logical_height scale_x scale_y
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  [[ "$macos" == "15" ]] || die "protected click currently supports only the Tart macOS 15 lane"
  [[ "$(field "$manifest" desktop_enabled)" == "true" ]] || die "protected click requires a desktop-enabled lease"
  [[ "$x" == <-> && "$y" == <-> ]] || die "protected click coordinates must be non-negative integers"
  [[ "$count" == "1" || "$count" == "2" ]] || die "protected click count must be 1 or 2"
  [[ "$coordinate_space" == "native" || "$coordinate_space" == "ax" ]] || die "invalid protected click coordinate space"
  resource=$(field "$manifest" provider_resource)
  [[ "$resource" =~ '^[A-Za-z0-9._-]+$' && "$resource" != "unknown" ]] || die "invalid Tart resource id"

  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    before=${KEYPATH_LAB_TEST_WINDOW_BEFORE:-$expected_before}
    before_frontmost=${KEYPATH_LAB_TEST_FRONTMOST_BEFORE:-true}
  else
    key="$HOME/Library/Application Support/crabbox/testboxes/$lease/id_ed25519"
    [[ -f "$key" && ! -L "$key" && -O "$key" ]] || die "owned CrabBox SSH key not found for lease"
    if [[ "${USER:-}" == "clawd" ]]; then export TART_HOME="$LAB_ROOT/TartHome-clawd"; else export TART_HOME="$LAB_ROOT/TartHome"; fi
    export PATH="$LAB_ROOT/CompatTools/bin:$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    ip=$($TART ip "$resource")
    [[ "$ip" =~ '^[0-9A-Fa-f:.]+$' ]] || die "Tart returned an invalid guest address"
    guest_command=$'/usr/bin/osascript -l JavaScript -e \'\nfunction run(argv) {\n  var matches = Application("System Events").processes.whose({name: argv[0]})();\n  if (matches.length === 0 || matches[0].windows().length === 0) return "false\\t";\n  var name = matches[0].windows[0].name() || "__UNTITLED__";\n  return String(matches[0].frontmost()) + "\\t" + name;\n}\' -- '$(printf %q "$app")
    IFS=$'\t' read -r before_frontmost before <<< "$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$guest_command")")"
  fi
  [[ "$before_frontmost" == "true" ]] || {
    record_command "$lease" failed protected-click --app "$app" --window "$expected_before" --x "$x" --y "$y"
    die "protected click precondition failed: '$app' is not frontmost"
  }
  [[ "$expected_before" == "__ANY__" && -n "$before" ]] || [[ "$before" == "$expected_before" ]] || {
    record_command "$lease" failed protected-click --app "$app" --window "$expected_before" --x "$x" --y "$y"
    die "protected click precondition failed: expected window '$expected_before', found '${before:-unknown}'"
  }

  if [[ "$coordinate_space" == "ax" ]]; then
    if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
      geometry=${KEYPATH_LAB_TEST_DISPLAY_GEOMETRY:-'2048 1536 1024 768'}
    else
      geometry_command='/usr/bin/osascript -l JavaScript -e '\''ObjC.import("AppKit"); var screen=$.NSScreen.mainScreen; var logical=screen.frame.size; var scale=Number(screen.backingScaleFactor); Math.round(logical.width*scale)+" "+Math.round(logical.height*scale)+" "+Math.round(logical.width)+" "+Math.round(logical.height)'\'''
      geometry=$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$geometry_command")")
    fi
    IFS=' ' read -r native_width native_height logical_width logical_height <<< "$geometry"
    [[ "$native_width" == <-> && "$native_height" == <-> && "$logical_width" == <-> && "$logical_height" == <-> && "$logical_width" -gt 0 && "$logical_height" -gt 0 ]] || die "protected click could not measure display geometry"
    (( native_width % logical_width == 0 && native_height % logical_height == 0 )) || die "protected click measured a non-integral display scale"
    scale_x=$((native_width / logical_width))
    scale_y=$((native_height / logical_height))
    (( scale_x == scale_y && scale_x > 0 )) || die "protected click measured inconsistent display scales"
    x=$((x * scale_x))
    y=$((y * scale_y))
  fi

  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    occlusion=${KEYPATH_LAB_TEST_OCCLUSION:-}
  else
    occlusion_command=$'/usr/bin/osascript -l JavaScript -e \'\nObjC.import("AppKit");\nfunction contains(element, x, y) {\n  try {\n    var position = element.position();\n    var size = element.size();\n    return size[0] > 1 && size[1] > 1 && x >= position[0] && x <= position[0] + size[0] && y >= position[1] && y <= position[1] + size[1];\n  } catch (_) { return false; }\n}\nfunction bounds(element) {\n  var position = element.position();\n  var size = element.size();\n  return Math.round(position[0]) + "," + Math.round(position[1]) + "," + Math.round(size[0]) + "," + Math.round(size[1]);\n}\nfunction descendants(element) {\n  var result = [];\n  try {\n    var children = element.uiElements();\n    for (var i = 0; i < children.length; i++) {\n      result.push(children[i]);\n      result = result.concat(descendants(children[i]));\n    }\n  } catch (_) {}\n  return result;\n}\nfunction run(argv) {\n  var x = Number(argv[0]) / Number($.NSScreen.mainScreen.backingScaleFactor);\n  var y = Number(argv[1]) / Number($.NSScreen.mainScreen.backingScaleFactor);\n  var events = Application("System Events");\n  var processNames = ["NotificationCenter", "UserNotificationCenter"];\n  for (var p = 0; p < processNames.length; p++) {\n    var matches = events.processes.whose({name: processNames[p]})();\n    if (matches.length === 0) continue;\n    var windows = matches[0].windows();\n    for (var w = 0; w < windows.length; w++) {\n      try {\n        if (windows[w].subrole() === "AXSystemDialog" && contains(windows[w], x, y)) {\n          return processNames[p] + ":dialog:" + bounds(windows[w]);\n        }\n      } catch (_) {}\n      var elements = descendants(windows[w]);\n      for (var e = 0; e < elements.length; e++) {\n        try {\n          var role = elements[e].role();\n          if (["AXGroup", "AXButton", "AXStaticText", "AXImage"].indexOf(role) !== -1 && contains(elements[e], x, y)) {\n            return processNames[p] + ":" + role + ":" + bounds(elements[e]);\n          }\n        } catch (_) {}\n      }\n    }\n  }\n  return "";\n}\' -- '$(printf %q "$x")' '$(printf %q "$y")
    occlusion=$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$occlusion_command")") || die "protected click could not verify notification occlusion"
    if [[ "$occlusion" == *":dialog:"* ]]; then
      read -r -d '' occlusion_qualification_script <<'JXA' || true
ObjC.import("AppKit");
function contains(element, x, y) {
  try {
    var position = element.position();
    var size = element.size();
    return size[0] > 1 && size[1] > 1 && x >= position[0] && x <= position[0] + size[0] && y >= position[1] && y <= position[1] + size[1];
  } catch (_) { return false; }
}
function descendants(element) {
  var result = [];
  try {
    var children = element.uiElements();
    for (var i = 0; i < children.length; i++) {
      result.push(children[i]);
      result = result.concat(descendants(children[i]));
    }
  } catch (_) {}
  return result;
}
function run(argv) {
  var x = Number(argv[0]) / Number($.NSScreen.mainScreen.backingScaleFactor);
  var y = Number(argv[1]) / Number($.NSScreen.mainScreen.backingScaleFactor);
  var events = Application("System Events");
  var processNames = ["NotificationCenter", "UserNotificationCenter"];
  for (var p = 0; p < processNames.length; p++) {
    var matches = events.processes.whose({name: processNames[p]})();
    if (matches.length === 0) continue;
    var windows = matches[0].windows();
    for (var w = 0; w < windows.length; w++) {
      try {
        var dialogText = windows[w].staticTexts().map(function(item) { return item.value() || ""; }).join(" ").toLowerCase();
        var captureConsent = dialogText.indexOf("screen") !== -1 && (dialogText.indexOf("record") !== -1 || dialogText.indexOf("capture") !== -1 || dialogText.indexOf("share") !== -1);
        if (captureConsent || dialogText.indexOf("private window picker") !== -1) return processNames[p] + ":consent-dialog";
      } catch (_) {}
      var elements = descendants(windows[w]);
      for (var e = 0; e < elements.length; e++) {
        try {
          var role = elements[e].role();
          var boundedVisibleRole = ["AXButton", "AXStaticText", "AXImage"].indexOf(role) !== -1;
          if (role === "AXGroup") {
            var elementSize = elements[e].size();
            var windowSize = windows[w].size();
            boundedVisibleRole = elementSize[0] * elementSize[1] < windowSize[0] * windowSize[1] * 0.5;
          }
          if (boundedVisibleRole && contains(elements[e], x, y)) return processNames[p] + ":" + role;
        } catch (_) {}
      }
    }
  }
  return "";
}
JXA
      occlusion_command="/usr/bin/osascript -l JavaScript -e $(printf %q "$occlusion_qualification_script") -- $(printf %q "$x") $(printf %q "$y")"
      occlusion=$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$occlusion_command")") || die "protected click could not qualify notification occlusion"
    fi
  fi
  [[ -z "$occlusion" ]] || {
    record_command "$lease" failed protected-click --app "$app" --window "$expected_before" --x "$x" --y "$y"
    die "protected click target is occluded by a notification ($occlusion)"
  }

  if [[ "$count" == "2" ]]; then
    "$CRABBOX" desktop click --provider tart --target macos --id "$resource" --x "$x" --y "$y" --count 2 >/dev/null
  else
    "$CRABBOX" desktop click --provider tart --target macos --id "$resource" --x "$x" --y "$y" >/dev/null
  fi
  sleep "${KEYPATH_LAB_PROTECTED_CLICK_SETTLE_SECONDS:-1}"
  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    after=${KEYPATH_LAB_TEST_WINDOW_AFTER:-$expected_after}
    after_frontmost=${KEYPATH_LAB_TEST_FRONTMOST_AFTER:-true}
  else
    IFS=$'\t' read -r after_frontmost after <<< "$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$guest_command")")"
  fi
  if [[ "$after" != "$expected_after" && "$expected_before" == "__ANY__" ]]; then
    sleep "${KEYPATH_LAB_INITIAL_SETTINGS_RETRY_SECONDS:-5}"
    "$CRABBOX" desktop click --provider tart --target macos --id "$resource" --x "$x" --y "$y" >/dev/null
    sleep "${KEYPATH_LAB_PROTECTED_CLICK_SETTLE_SECONDS:-1}"
    IFS=$'\t' read -r after_frontmost after <<< "$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$guest_command")")"
  fi
  [[ "$after_frontmost" == "true" ]] || {
    record_command "$lease" failed protected-click --app "$app" --window "$expected_before" --after-window "$expected_after" --x "$x" --y "$y"
    die "protected click postcondition failed: '$app' is no longer frontmost"
  }
  [[ "$after" == "$expected_after" ]] || {
    record_command "$lease" failed protected-click --app "$app" --window "$expected_before" --after-window "$expected_after" --x "$x" --y "$y"
    die "protected click postcondition failed: expected window '$expected_after', found '${after:-unknown}'"
  }
  record_command "$lease" passed protected-click --app "$app" --window "$expected_before" --after-window "$expected_after" --x "$x" --y "$y"
  print "protected_click\tpassed"
  print "window_before\t$before"
  print "window_after\t$after"
  print "coordinate_space\t$coordinate_space"
  print "click_count\t$count"
  if [[ "$coordinate_space" == "ax" ]]; then
    print "display_scale\t$scale_x"
  fi
}

input_monitoring_rows() {
  local lease=$1 manifest resource key ip guest_script guest_command open_command
  manifest=$(owned_manifest "$lease")
  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    if [[ -n "${KEYPATH_LAB_TEST_INPUT_MONITORING_ROWS:-}" ]]; then
      print -r -- "$KEYPATH_LAB_TEST_INPUT_MONITORING_ROWS"
    else
      printf 'Kanata Engine\t0\t402\t247\nkanata-launcher\t0\t402\t289\nKeyPath\t0\t402\t331\n'
    fi
    return
  fi

  resource=$(field "$manifest" provider_resource)
  [[ "$resource" =~ '^[A-Za-z0-9._-]+$' && "$resource" != "unknown" ]] || die "invalid Tart resource id"
  key="$HOME/Library/Application Support/crabbox/testboxes/$lease/id_ed25519"
  [[ -f "$key" && ! -L "$key" && -O "$key" ]] || die "owned CrabBox SSH key not found for lease"
  if [[ "${USER:-}" == "clawd" ]]; then export TART_HOME="$LAB_ROOT/TartHome-clawd"; else export TART_HOME="$LAB_ROOT/TartHome"; fi
  export PATH="$LAB_ROOT/CompatTools/bin:$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  ip=$($TART ip "$resource")
  [[ "$ip" =~ '^[0-9A-Fa-f:.]+$' ]] || die "Tart returned an invalid guest address"

  read -r -d '' guest_script <<'JXA' || true
function safe(callback, fallback) {
  try { return callback(); } catch (_) { return fallback; }
}
function descendants(element) {
  var result = [];
  safe(function() {
    element.uiElements().forEach(function(child) {
      result.push(child);
      result = result.concat(descendants(child));
    });
  }, null);
  return result;
}
function run() {
  Application("System Settings").activate();
  var process = Application("System Events").processes.byName("System Settings");
  for (var attempt = 0; attempt < 20 && (!process.exists() || process.windows().length === 0); attempt++) delay(0.25);
  if (!process.exists() || process.windows().length === 0) throw new Error("System Settings is unavailable");
  var window = process.windows[0];
  if (window.name() !== "Input Monitoring") throw new Error("Input Monitoring page did not open");
  window.position = [154, 330];
  delay(0.5);
  var targets = ["Kanata Engine", "kanata-launcher", "KeyPath"];
  var checkboxes = descendants(window).filter(function(element) {
    return safe(function() { return element.role() === "AXCheckBox"; }, false);
  });
  return targets.map(function(target) {
    var matches = checkboxes.filter(function(element) {
      return safe(function() { return element.name() === target; }, false);
    });
    if (matches.length !== 1) throw new Error("Expected one Input Monitoring row for " + target);
    var checkbox = matches[0];
    var position = checkbox.position();
    var size = checkbox.size();
    return target + "\t" + checkbox.value() + "\t" +
      Math.round(position[0] + size[0] / 2) + "\t" +
      Math.round(position[1] + size[1] / 2);
  }).join("\n");
}
JXA
  guest_command="/usr/bin/killall -TERM KeyPath >/dev/null 2>&1 || true"
  "$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$guest_command")"
  open_command="/usr/bin/open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent'"
  "$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$open_command")" >/dev/null
  guest_command="/usr/bin/osascript -l JavaScript -e $(printf %q "$guest_script")"
  "$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$guest_command")"
}

approve_input_monitoring() {
  local lease=$1 manifest macos lane rows row target value x y verified
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  lane=$(field "$manifest" test_lane)
  [[ "$macos" == "15" ]] || die "Input Monitoring approval currently supports only the Tart macOS 15 lane"
  [[ "$lane" == "managed-functional" ]] || die "Input Monitoring approval requires managed-functional policy"
  [[ "$(field "$manifest" desktop_enabled)" == "true" ]] || die "Input Monitoring approval requires a desktop-enabled lease"

  rows=$(input_monitoring_rows "$lease") || die "could not inspect Input Monitoring rows"
  for target in "Kanata Engine" "kanata-launcher" "KeyPath"; do
    row=$(print -r -- "$rows" | awk -F '\t' -v target="$target" '$1 == target {print; exit}')
    [[ -n "$row" ]] || die "Input Monitoring row is missing: $target"
    IFS=$'\t' read -r _ value x y <<< "$row"
    [[ "$value" == "0" || "$value" == "1" ]] || die "Input Monitoring row has an invalid state: $target"
    [[ "$x" == <-> && "$y" == <-> ]] || die "Input Monitoring row has invalid geometry: $target"
    if [[ "$value" == "1" ]]; then
      print "input_monitoring_row\t$target\talready-enabled"
      continue
    fi

    protected_click "$lease" "System Settings" "Input Monitoring" "Input Monitoring" ax "$x" "$y" 1 >/dev/null
    if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
      verified=${KEYPATH_LAB_TEST_INPUT_MONITORING_VERIFY:-1}
    else
      rows=$(input_monitoring_rows "$lease") || die "could not refresh Input Monitoring rows"
      verified=$(print -r -- "$rows" | awk -F '\t' -v target="$target" '$1 == target {print $2; exit}')
    fi
    [[ "$verified" == "1" ]] || die "Input Monitoring toggle did not remain enabled: $target"
    print "input_monitoring_row\t$target\tenabled"
  done
  record_command "$lease" passed approve-input-monitoring
  print "approve_input_monitoring\tpassed"
}

desktop_type() {
  local lease=$1 text=$2 manifest macos resource
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  [[ "$macos" == "15" ]] || die "desktop type currently supports only the Tart macOS 15 lane"
  [[ "$(field "$manifest" desktop_enabled)" == "true" ]] || die "desktop type requires a desktop-enabled lease"
  resource=$(field "$manifest" provider_resource)
  [[ "$resource" =~ '^[A-Za-z0-9._-]+$' && "$resource" != "unknown" ]] || die "invalid Tart resource id"
  if [[ "${USER:-}" == "clawd" ]]; then export TART_HOME="$LAB_ROOT/TartHome-clawd"; else export TART_HOME="$LAB_ROOT/TartHome"; fi
  export PATH="$LAB_ROOT/CompatTools/bin:$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  "$CRABBOX" desktop type --provider tart --target macos --id "$resource" --text "$text"
  record_command "$lease" passed desktop-type --bytes "${#text}"
}

print_status() {
  local lease=$1 manifest macos launcher
  manifest=$(owned_manifest "$lease")
  cat "$manifest"
  macos=$(field "$manifest" macos)
  launcher=$(launcher_for "$macos")
  print "provider_inventory_begin"
  "$launcher" list || true
  print "provider_inventory_end"
}

list_leases() {
  ensure_roots
  print "lease_id\tmacos\ttest_lane\tbase_name\tprovider\tstatus\texpires_epoch\tcommit\tcleanup"
  local manifest lease
  for manifest in "$LEASES"/*/manifest.tsv(N); do
    [[ "$(field "$manifest" owner)" == "$OWNER" ]] || continue
    lease=$(field "$manifest" lease_id)
    print "$lease\t$(field "$manifest" macos)\t$(field "$manifest" test_lane)\t$(field "$manifest" base_name)\t$(field "$manifest" provider)\t$(field "$manifest" status)\t$(field "$manifest" expires_epoch)\t$(field "$manifest" keypath_commit)\t$(field "$manifest" cleanup_status)"
  done
}

collect_artifacts() {
  local lease=$1 manifest output exit_code macos repo archive provider_resource parallels_cli
  local parallels_resource_pattern='^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$'
  local nameplate_restore=0 nameplate_hide_status=not-needed nameplate_restore_status=not-needed
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  repo=$(field "$manifest" worktree)
  prepare_worktree "$repo"
  output="$ARTIFACTS/$lease/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$output"
  cp "$manifest" "$output/manifest.tsv"
  cp "$LEASES/$lease/commands.tsv" "$output/commands.tsv" 2>/dev/null || true
  cp -R "$LOGS/$lease" "$output/controller-logs"
  if [[ -d "$repo/.crabbox/captures" ]]; then
    cp -R "$repo/.crabbox/captures" "$output/controller-crabbox-captures"
  fi
  if [[ "$(field "$manifest" nameplate_state)" == visible ]]; then
    set +e
    (nameplate_control "$lease" hide) > "$output/nameplate-hide.log" 2>&1
    nameplate_hide_status=$?
    set -e
    if (( nameplate_hide_status == 0 )); then
      nameplate_restore=1
    fi
  fi
  archive="$output/scenario-output.tar.gz"
  set +e
  (cd "$repo" && run_with_download "$macos" "$lease" ".keypath-lab/scenario-output.tar.gz" "$archive" \
    /bin/zsh -lc 'set -e; out=.keypath-lab/scenario-output/controller-capture; mkdir -p "$out/logs"; sw_vers > "$out/sw-vers.txt"; date -u +%Y-%m-%dT%H:%M:%SZ > "$out/captured-at.txt"; cp -R "$HOME/Library/Logs/KeyPath/." "$out/logs/" 2>/dev/null || true; /Applications/KeyPath.app/Contents/MacOS/keypath-cli system inspect --json > "$out/system-inspect.json" 2>/dev/null || true; tar -czf .keypath-lab/scenario-output.tar.gz -C .keypath-lab scenario-output') > "$output/download.log" 2>&1
  exit_code=$?
  set -e
  if (( exit_code == 0 )); then
    tar -xzf "$archive" -C "$output"
  fi
  if [[ "$(field "$manifest" desktop_enabled)" == "true" && "$nameplate_hide_status" != "0" && "$nameplate_hide_status" != not-needed ]]; then
    screenshot_exit=unavailable:nameplate-hide-failed
    set_field "$manifest" screenshot_status "$screenshot_exit"
  elif [[ "$(field "$manifest" desktop_enabled)" == "true" ]]; then
    set +e
    if [[ "$macos" == "15" ]]; then
      if [[ "${USER:-}" == "clawd" ]]; then export TART_HOME="$LAB_ROOT/TartHome-clawd"; else export TART_HOME="$LAB_ROOT/TartHome"; fi
      export PATH="$LAB_ROOT/CompatTools/bin:$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      (cd "$repo" && "$CRABBOX" screenshot --provider tart --target macos --id "$lease" --output "$output/screenshot.png") >> "$output/download.log" 2>&1
    else
      provider_resource=$(field "$manifest" provider_resource)
      [[ "$provider_resource" =~ $parallels_resource_pattern ]] || die "invalid Parallels resource id"
      parallels_cli=${KEYPATH_LAB_PRLCTL:-"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"}
      [[ -x "$parallels_cli" ]] || die "Parallels CLI is unavailable"
      "$parallels_cli" capture "$provider_resource" --file "$output/screenshot.png" >> "$output/download.log" 2>&1
    fi
    screenshot_exit=$?
    set -e
    set_field "$manifest" screenshot_status "$screenshot_exit"
  else
    screenshot_exit=unavailable:lease-not-created-with-desktop
    set_field "$manifest" screenshot_status "$screenshot_exit"
  fi
  if (( nameplate_restore )); then
    set +e
    (nameplate_control "$lease" show) > "$output/nameplate-restore.log" 2>&1
    nameplate_restore_status=$?
    set -e
  fi
  set_field "$manifest" artifacts_status "$exit_code"
  set_field "$manifest" artifacts_last_collected_at "$(utc_now)"
  set_field "$manifest" nameplate_artifact_hide_status "$nameplate_hide_status"
  set_field "$manifest" nameplate_artifact_restore_status "$nameplate_restore_status"
  cp "$manifest" "$output/manifest.tsv"
  cp "$LEASES/$lease/commands.tsv" "$output/commands.tsv" 2>/dev/null || true
  print "artifact_dir\t$output"
  print "download_status\t$exit_code"
  print "screenshot_status\t$screenshot_exit"
  print "nameplate_hide_status\t$nameplate_hide_status"
  print "nameplate_restore_status\t$nameplate_restore_status"
  return "$exit_code"
}

scenario() {
  local lease=$1 name=$2 manifest repo scenario_script lane runtime_status exit_code
  manifest=$(owned_manifest "$lease")
  repo=$(field "$manifest" worktree)
  lane=$(field "$manifest" test_lane)
  prepare_worktree "$repo"
  scenario_script="Scripts/lab/scenarios/installer-scenario"
  [[ -x "$repo/$scenario_script" ]] || die "scenario runner missing from archived commit"
  set +e
  (run_command "$lease" "/bin/zsh" "$scenario_script" "$name" "$lane")
  exit_code=$?
  set -e
  if ((exit_code == 0)) && [[ "$name" == "uninstall" ]]; then
    runtime_status=$(field "$manifest" install_runtime_status)
    if [[ -n "$runtime_status" ]]; then
      set_field "$manifest" install_runtime_status uninstalled
      set_field "$manifest" uninstall_at "$(utc_now)"
    fi
  fi
  return "$exit_code"
}

desktop_bootstrap() {
  local lease=$1 install_tools=$2 manifest macos repo output command exit_code approval_output attempt
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  [[ "$(field "$manifest" desktop_enabled)" == "true" ]] || die "desktop bootstrap requires a desktop-enabled lease"
  repo=$(field "$manifest" worktree)
  prepare_worktree "$repo"
  output=".keypath-lab/scenario-output/bootstrap"
  command=(/bin/zsh Scripts/lab/desktop-bootstrap --output "$output")
  [[ "$install_tools" == "1" ]] && command+=(--install-tools)
  if [[ "$macos" == "15" ]]; then
    # Clear a consent prompt left by an interrupted bootstrap before asking
    # Peekaboo to capture again.
    approve_peekaboo_capture "$lease"
  fi
  exit_code=1
  for attempt in {1..3}; do
    set +e
    (run_command "$lease" "${command[@]}")
    exit_code=$?
    set -e
    ((exit_code == 0)) && break
    [[ "$macos" == "15" ]] || return "$exit_code"
    approval_output=$(approve_peekaboo_capture "$lease")
    print -r -- "$approval_output"
    print -r -- "$approval_output" | grep -Fq $'peekaboo_capture_approval\tpassed' || return "$exit_code"
    # Installing tools re-signs the dedicated Peekaboo host. Do that once;
    # re-signing on every consent retry creates a fresh Screen Recording
    # request and prevents the bootstrap from ever reaching its postcondition.
    command=(/bin/zsh Scripts/lab/desktop-bootstrap --output "$output")
  done
  ((exit_code == 0)) || return "$exit_code"
  set_field "$manifest" desktop_bootstrap_at "$(utc_now)"
  set_field "$manifest" desktop_bootstrap_status passed
}

verify_console_login() {
  local lease=$1 manifest macos resource parallels_cli console_user
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  [[ "$macos" == "27" ]] || die "inherited console-login verification currently supports only the macOS 27 lane"
  [[ "$(field "$manifest" provider)" == "parallels" ]] || die "inherited console-login verification requires a Parallels lease"
  [[ "$(field "$manifest" desktop_enabled)" == "true" ]] || die "inherited console-login verification requires a desktop-enabled lease"
  resource=$(field "$manifest" provider_resource)
  [[ "$resource" =~ '^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$' ]] || die "invalid Parallels resource id"
  parallels_cli=${KEYPATH_LAB_PRLCTL:-"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"}
  [[ -x "$parallels_cli" ]] || die "Parallels CLI is unavailable"
  console_user=$("$parallels_cli" exec "$resource" /usr/bin/stat -f %Su /dev/console 2>/dev/null || true)
  if [[ "$console_user" != "keypathqa" ]]; then
    set_field "$manifest" console_login_status postcondition-failed
    set_field "$manifest" console_login_method inherited-base
    record_command "$lease" failed verify-console-login
    die "fresh desktop-base clone did not inherit the keypathqa console session"
  fi
  set_field "$manifest" console_login_status passed
  set_field "$manifest" console_login_method inherited-base
  set_field "$manifest" console_login_at "$(utc_now)"
  record_command "$lease" passed verify-console-login
  print "console_login\tpassed"
  print "console_login_method\tinherited-base"
  print "console_user\t$console_user"
}

console_login() {
  local lease=$1 manifest macos resource parallels_cli secret_file exit_code console_user attempt guest_command autologin_status guest_control_ready configure_stage
  local guest_ip key known_hosts known_hosts_option fifo status_file configure_pid fifo_ready stream_exit credential_timeout
  local secret_leak
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  [[ "$macos" == "27" ]] || die "console login currently supports only the macOS 27 Parallels lane"
  [[ "$(field "$manifest" provider)" == "parallels" ]] || die "console login requires a Parallels lease"
  [[ "$(field "$manifest" desktop_enabled)" == "true" ]] || die "console login requires a desktop-enabled lease"
  resource=$(field "$manifest" provider_resource)
  [[ "$resource" =~ '^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$' ]] || die "invalid Parallels resource id"
  parallels_cli=${KEYPATH_LAB_PRLCTL:-"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"}
  [[ -x "$parallels_cli" ]] || die "Parallels CLI is unavailable"
  if ! "$parallels_cli" status "$resource" 2>/dev/null | grep -q running; then
    "$parallels_cli" start "$resource" > "$LOGS/$lease/console-login-start.log" 2>&1 || die "failed to start the disposable Parallels guest"
  fi
  guest_control_ready=0
  for attempt in {1..90}; do
    if "$parallels_cli" exec "$resource" /usr/bin/true >/dev/null 2>&1; then
      guest_control_ready=1
      break
    fi
    sleep "${KEYPATH_LAB_CONSOLE_LOGIN_POLL_SECONDS:-2}"
  done
  (( guest_control_ready == 1 )) || die "Parallels guest control did not become ready"

  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    secret_file="${KEYPATH_LAB_TEST_SECRET_FILE:?test secret file is required}"
    key="${KEYPATH_LAB_TEST_SSH_KEY:?test SSH key is required}"
    known_hosts="${KEYPATH_LAB_TEST_KNOWN_HOSTS:-/dev/null}"
    guest_ip=192.0.2.27
  else
    key="$HOME/Library/Application Support/crabbox/testboxes/$lease/id_ed25519"
    [[ -f "$key" && ! -L "$key" && -O "$key" ]] || die "owned CrabBox SSH key not found for lease"
    known_hosts="$HOME/Library/Application Support/crabbox/testboxes/$lease/known_hosts"
    [[ -f "$known_hosts" && ! -L "$known_hosts" && -O "$known_hosts" ]] || die "owned CrabBox known-hosts file not found for lease"
    guest_ip=$("$parallels_cli" list -i -f -j "$resource" | python3 -c 'import json,sys; rows=json.load(sys.stdin); addresses=rows[0].get("Network",{}).get("ipAddresses",[]) if rows else []; print(next((item.get("ip","") for item in addresses if item.get("type")=="ipv4"),""),end="")')
    [[ "$guest_ip" =~ '^[0-9A-Fa-f:.]+$' ]] || die "Parallels returned an invalid guest address"
    secret_file=$(mktemp "$STATE_ROOT/.console-login.XXXXXXXX")
    chmod 600 "$secret_file"
    typeset -g KEYPATH_LAB_SECURE_TEMP="$secret_file"
    trap '[[ -z ${KEYPATH_LAB_SECURE_TEMP:-} ]] || rm -f "$KEYPATH_LAB_SECURE_TEMP"' EXIT
    /opt/homebrew/bin/sops -d "$HOME/dotfiles/secrets.env" | awk -F= '$1 == "KEYPATH_LAB_GUEST_PASSWORD" {sub(/^[^=]*=/, ""); printf "%s", $0; found=1} END {if (!found) exit 1}' > "$secret_file" || die "KEYPATH_LAB_GUEST_PASSWORD is unavailable"
  fi
  [[ -s "$secret_file" ]] || die "console login secret is empty"
  # OpenSSH parses -o values a second time, so spaces in this path must remain
  # escaped even though the complete option is already one shell argument.
  known_hosts_option=${known_hosts// /\\ }
  credential_timeout=${KEYPATH_LAB_CONSOLE_CREDENTIAL_TIMEOUT_SECONDS:-30}
  [[ "$credential_timeout" == <-> && "$credential_timeout" -gt 0 ]] || die "console login credential timeout must be a positive integer"

  # Configure automatic login inside the disposable clone through Parallels'
  # root guest-control channel. prlctl exec does not forward stdin, so the root
  # process creates a lease-specific FIFO and the existing lease-owned SSH
  # channel streams the password into it. The controller's short-lived,
  # owner-only temp file is removed before the reboot; the value never appears
  # in controller process arguments or logs. Inside the disposable guest,
  # dscl and sysadminctl have no noninteractive stdin form and briefly receive
  # the value in argv. Do not run process-argument capture during this action.
  # sysadminctl's protected prompt cannot be driven through prlctl because
  # guest-control does not forward stdin. Expand the FIFO-fed value only inside
  # the isolated guest process; the controller command contains the variable
  # reference, never its value, and both guest command output streams stay
  # confined to the leak-checked controller log.
  fifo="/tmp/keypath-console-login-$lease-$$.fifo"
  status_file="/tmp/keypath-console-login-$lease-$$.status"
  guest_command="set -euo pipefail; fifo=$(printf %q "$fifo"); status_file=$(printf %q "$status_file"); rm -f \"\$fifo\" \"\$status_file\"; print -r -- started > \"\$status_file\"; /usr/bin/mkfifo \"\$fifo\"; /usr/sbin/chown keypathqa:staff \"\$fifo\"; /bin/chmod 600 \"\$fifo\"; trap 'rm -f \"\$fifo\"' EXIT; exec 3<> \"\$fifo\"; KEYPATH_GUEST_PASSWORD=; IFS= read -r -t $credential_timeout -u 3 KEYPATH_GUEST_PASSWORD || [[ -n \"\$KEYPATH_GUEST_PASSWORD\" ]]; print -r -- credential-received >> \"\$status_file\"; /usr/bin/dscl . -authonly keypathqa \"\$KEYPATH_GUEST_PASSWORD\" || exit 91; print -r -- credential-valid >> \"\$status_file\"; set +e; /usr/sbin/sysadminctl -autologin set -userName keypathqa -password \"\$KEYPATH_GUEST_PASSWORD\"; sysadmin_result=\$?; set -e; autologin_status=\$(/usr/sbin/sysadminctl -autologin status 2>&1 || true); if [[ \"\$autologin_status\" != *'Automatic login is ON'* && \"\$autologin_status\" != *'Automatic login user: keypathqa'* ]]; then kcpassword_tmp=\$(/usr/bin/mktemp /etc/kcpassword.XXXXXXXX); trap 'rm -f \"\$fifo\" \"\$kcpassword_tmp\"' EXIT; printf %s \"\$KEYPATH_GUEST_PASSWORD\" | /usr/bin/perl -e 'binmode STDIN; binmode STDOUT; local \$/; my \$password = <STDIN>; my @key = (0x7d,0x89,0x52,0x23,0xd2,0xbc,0xdd,0xea,0xa3,0xb9,0x1f); \$password .= chr(0); \$password .= chr(0) while length(\$password) % 12; print pack(\"C*\", map { ord(substr(\$password, \$_, 1)) ^ \$key[\$_ % @key] } 0 .. length(\$password)-1);' > \"\$kcpassword_tmp\"; /usr/sbin/chown root:wheel \"\$kcpassword_tmp\"; /bin/chmod 600 \"\$kcpassword_tmp\"; /bin/mv -f \"\$kcpassword_tmp\" /etc/kcpassword; /usr/bin/defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser -string keypathqa; print -r -- method:kcpassword-fallback >> \"\$status_file\"; fi; /bin/mkdir -p /var/db/crabbox; printf '%s\n' \"\$KEYPATH_GUEST_PASSWORD\" > /var/db/crabbox/vnc.password; /usr/sbin/chown root:wheel /var/db/crabbox/vnc.password; /bin/chmod 600 /var/db/crabbox/vnc.password; print -r -- rfb-credential:aligned >> \"\$status_file\"; unset KEYPATH_GUEST_PASSWORD; print -r -- sysadminctl-exit:\$sysadmin_result >> \"\$status_file\"; exit 0"
  set +e
  "$parallels_cli" exec "$resource" /bin/zsh -lc "$(printf %q "$guest_command")" \
    > "$LOGS/$lease/console-login-configure.log" 2>&1 &
  configure_pid=$!
  fifo_ready=0
  for attempt in {1..300}; do
    if "$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts_option" -i "$key" "keypathqa@$guest_ip" \
      "/bin/test -p $(printf %q "$fifo")" </dev/null >/dev/null 2>&1; then
      fifo_ready=1
      break
    fi
    sleep 0.1
  done
  if (( fifo_ready == 1 )); then
    # The decrypted dotenv value intentionally has no trailing newline. Frame
    # it as one record so the guest's `read` completes immediately instead of
    # waiting indefinitely after receiving a partial line from the FIFO.
    { /bin/cat "$secret_file"; printf '\n'; } | \
      /usr/bin/perl -e 'my $timeout = shift; alarm $timeout; exec @ARGV or exit 127' "$credential_timeout" \
        "$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts_option" -i "$key" "keypathqa@$guest_ip" \
        "/bin/zsh -c $(printf %q "/bin/cat > $(printf %q "$fifo")")" >/dev/null 2>&1
    stream_exit=$?
    (( stream_exit == 0 )) || kill "$configure_pid" 2>/dev/null || true
  else
    stream_exit=76
    kill "$configure_pid" 2>/dev/null || true
  fi
  wait "$configure_pid"
  exit_code=$?
  "$parallels_cli" exec "$resource" /bin/cat "$status_file" >> "$LOGS/$lease/console-login-configure.log" 2>&1 || true
  "$parallels_cli" exec "$resource" /bin/rm -f "$status_file" >/dev/null 2>&1 || true
  configure_stage=$(< "$LOGS/$lease/console-login-configure.log")
  (( stream_exit == 0 )) || exit_code=$stream_exit
  secret_leak=0
  if grep -Fq -f "$secret_file" "$LOGS/$lease/console-login-configure.log"; then
    : > "$LOGS/$lease/console-login-configure.log"
    secret_leak=1
    exit_code=90
  fi
  set -e
  if [[ "${KEYPATH_LAB_TESTING:-0}" != "1" ]]; then
    rm -f "$secret_file"
    KEYPATH_LAB_SECURE_TEMP=
    trap - EXIT
  fi
  if (( exit_code != 0 )); then
    if (( secret_leak == 1 )); then
      set_field "$manifest" console_login_status credential-leak-detected
      record_command "$lease" failed:credential-leak console-login
      die "guest credential disclosure was detected and redacted from the controller log"
    fi
    if (( stream_exit != 0 )); then
      set_field "$manifest" console_login_status "credential-stream-failed:$stream_exit"
      record_command "$lease" "failed:$stream_exit" console-login
      die "failed to stream the guest credential into the disposable guest"
    fi
    if [[ "$configure_stage" != *credential-valid* ]]; then
      set_field "$manifest" console_login_status credential-mismatch
      record_command "$lease" failed:credential-mismatch console-login
      die "KEYPATH_LAB_GUEST_PASSWORD does not authenticate the keypathqa guest account"
    fi
    set_field "$manifest" console_login_status "configure-failed:$exit_code"
    record_command "$lease" "failed:$exit_code" console-login
    die "failed to configure automatic login in the disposable guest"
  fi
  autologin_status=$("$parallels_cli" exec "$resource" /usr/sbin/sysadminctl -autologin status 2>&1 || true)
  if [[ "$autologin_status" != *"Automatic login is ON"* && "$autologin_status" != *"Automatic login user: keypathqa"* ]]; then
    set_field "$manifest" console_login_status "configure-postcondition-failed"
    record_command "$lease" failed console-login
    die "automatic login remained disabled after configuration"
  fi

  # A reboot is required because the source base is intentionally captured at
  # loginwindow. Use the provider-owned restart so the clone cannot be stranded
  # stopped when its guest-control connection closes during shutdown.
  "$parallels_cli" restart "$resource" \
    > "$LOGS/$lease/console-login-reboot.log" 2>&1 || die "failed to restart the disposable Parallels guest"
  console_user=
  for attempt in {1..90}; do
    sleep "${KEYPATH_LAB_CONSOLE_LOGIN_POLL_SECONDS:-2}"
    console_user=$("$parallels_cli" exec "$resource" /usr/bin/stat -f %Su /dev/console 2>/dev/null | tail -1 || true)
    [[ "$console_user" == "keypathqa" ]] && break
  done
  if [[ "$console_user" != "keypathqa" ]]; then
    set_field "$manifest" console_login_status "postcondition-failed"
    record_command "$lease" failed console-login
    die "automatic login did not establish the keypathqa console session"
  fi

  set_field "$manifest" console_login_status passed
  set_field "$manifest" console_login_at "$(utc_now)"
  record_command "$lease" passed console-login
  print "console_login\tpassed"
  print "console_user\t$console_user"
}

secure_console_submit() {
  local lease=$1 manifest macos resource parallels_cli secret_file key_events key_event
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  [[ "$macos" == "26" || "$macos" == "27" ]] || die "secure console submit requires a macOS 26 or 27 Parallels lane"
  [[ "$(field "$manifest" provider)" == "parallels" ]] || die "secure console submit requires a Parallels lease"
  [[ "$(field "$manifest" desktop_enabled)" == "true" ]] || die "secure console submit requires a desktop-enabled lease"
  resource=$(field "$manifest" provider_resource)
  [[ "$resource" =~ '^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$' ]] || die "invalid Parallels resource id"
  parallels_cli=${KEYPATH_LAB_PRLCTL:-"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"}
  [[ -x "$parallels_cli" ]] || die "Parallels CLI is unavailable"

  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    secret_file="${KEYPATH_LAB_TEST_SECRET_FILE:?test secret file is required}"
  else
    secret_file=$(mktemp "$STATE_ROOT/.secure-console.XXXXXXXX")
    chmod 600 "$secret_file"
    typeset -g KEYPATH_LAB_SECURE_TEMP="$secret_file"
    trap '[[ -z ${KEYPATH_LAB_SECURE_TEMP:-} ]] || rm -f "$KEYPATH_LAB_SECURE_TEMP"' EXIT
    /opt/homebrew/bin/sops -d "$HOME/dotfiles/secrets.env" | awk -F= '$1 == "KEYPATH_LAB_GUEST_PASSWORD" {sub(/^[^=]*=/, ""); printf "%s", $0; found=1} END {if (!found) exit 1}' > "$secret_file" || die "KEYPATH_LAB_GUEST_PASSWORD is unavailable"
  fi
  [[ -s "$secret_file" ]] || die "secure console secret is empty"

  # Convert the credential to explicit, paced Parallels event pairs. The
  # plaintext is
  # read only from the owner-only temp file and never enters argv, logs, the
  # guest pasteboard, or an artifact. One short-lived prlctl process per
  # explicit press/release pair prevents macOS from dropping a large burst
  # without relying on Parallels' ambiguous default key event.
  # Keep the accepted alphabet deliberately narrow; expanding it requires an
  # explicit key-map review.
  key_events=$(python3 -c 'import json,sys
codes={"a":38,"b":56,"c":54,"d":40,"e":26,"f":41,"g":42,"h":43,"i":31,"j":44,"k":45,"l":46,"m":58,"n":57,"o":32,"p":33,"q":24,"r":27,"s":39,"t":28,"u":30,"v":55,"w":25,"x":53,"y":29,"z":52,"1":10,"2":11,"3":12,"4":13,"5":14,"6":15,"7":16,"8":17,"9":18,"0":19,"-":20}
value=open(sys.argv[1],"r",encoding="utf-8").read()
if not value or any(ch not in codes for ch in value): raise SystemExit(64)
delay=max(0,round(float(sys.argv[2])*1000))
replace_events=[
    {"key":115,"event":"press","delay":delay},
    {"key":38,"event":"press","delay":delay},
    {"key":38,"event":"release","delay":delay},
    {"key":115,"event":"release","delay":delay},
    {"key":22,"event":"press","delay":delay},
    {"key":22,"event":"release","delay":delay},
]
print(json.dumps(replace_events,separators=(",",":")))
for ch in value:
    print(json.dumps(({"key":codes[ch],"event":"press","delay":delay},{"key":codes[ch],"event":"release","delay":delay}),separators=(",",":")))' "$secret_file" "${KEYPATH_LAB_SECURE_CONSOLE_KEY_DELAY_SECONDS:-0.2}" 3<&-) || \
    die "failed to encode the guest credential as Parallels key events"
  [[ -n "$key_events" ]] || die "failed to encode the guest credential as Parallels key events"
  while IFS= read -r key_event; do
    printf '%s\n' "$key_event" | "$parallels_cli" send-key-event "$resource" --json >/dev/null || \
      die "failed to deliver the guest credential through Parallels key events"
    sleep "${KEYPATH_LAB_SECURE_CONSOLE_KEY_DELAY_SECONDS:-0.2}"
  done <<< "$key_events"
  key_events=
  sleep "${KEYPATH_LAB_SECURE_CONSOLE_SETTLE_SECONDS:-0.25}"
  if [[ "$macos" == "26" ]]; then
    # SecurityAgent accepts password text from the Parallels console but
    # ignores synthetic application clicks. Leave the protected Enroll action
    # to a real user click.
    :
  else
    "$parallels_cli" send-key-event "$resource" --key 36 >/dev/null
  fi

  if [[ "${KEYPATH_LAB_TESTING:-0}" != "1" ]]; then
    rm -f "$secret_file"
    KEYPATH_LAB_SECURE_TEMP=
    trap - EXIT
  fi
  record_command "$lease" delivered secure-console-submit
  print "secure_console_submit\tdelivered"
  print "credential_field\treplaced-focused-value"
  print "credential_transport\tparallels-explicit-pairs-paced"
  print "credential_postcondition\tunverified"
}

console_key() {
  local lease=$1 key_code=$2 modifier_code=${3:-0} manifest macos resource parallels_cli
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  [[ "$macos" == "26" || "$macos" == "27" ]] || die "console key requires a macOS 26 or 27 Parallels lane"
  [[ "$(field "$manifest" provider)" == "parallels" ]] || die "console key requires a Parallels lease"
  [[ "$(field "$manifest" desktop_enabled)" == "true" ]] || die "console key requires a desktop-enabled lease"
  [[ "$key_code" == <-> && "$key_code" -ge 1 && "$key_code" -le 255 ]] || die "invalid Parallels key code"
  [[ "$modifier_code" == <-> && "$modifier_code" -ge 0 && "$modifier_code" -le 255 ]] || die "invalid Parallels modifier key code"
  resource=$(field "$manifest" provider_resource)
  [[ "$resource" =~ '^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$' ]] || die "invalid Parallels resource id"
  parallels_cli=${KEYPATH_LAB_PRLCTL:-"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"}
  [[ -x "$parallels_cli" ]] || die "Parallels CLI is unavailable"
  if (( modifier_code > 0 )); then
    "$parallels_cli" send-key-event "$resource" --key "$modifier_code" --event press >/dev/null
  fi
  "$parallels_cli" send-key-event "$resource" --key "$key_code" >/dev/null
  if (( modifier_code > 0 )); then
    "$parallels_cli" send-key-event "$resource" --key "$modifier_code" --event release >/dev/null
  fi
  record_command "$lease" passed console-key --key "$key_code" --modifier "$modifier_code"
  print "console_key\tpassed"
  print "parallels_key_code\t$key_code"
  print "parallels_modifier_code\t$modifier_code"
}

reset_guest_password() {
  local lease=$1 manifest resource parallels_cli secret_file key known_hosts known_hosts_option guest_ip
  local fifo account_file guest_command reset_pid fifo_ready attempt stream_exit reset_exit enrollment_account
  manifest=$(owned_manifest "$lease")
  [[ "$(field "$manifest" provider)" == "parallels" ]] || die "guest password reset requires a Parallels lease"
  [[ "$(field "$manifest" desktop_enabled)" == "true" ]] || die "guest password reset requires a desktop-enabled lease"
  resource=$(field "$manifest" provider_resource)
  [[ "$resource" =~ '^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$' ]] || die "invalid Parallels resource id"
  parallels_cli=${KEYPATH_LAB_PRLCTL:-"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"}
  [[ -x "$parallels_cli" ]] || die "Parallels CLI is unavailable"

  key="$HOME/Library/Application Support/crabbox/testboxes/$lease/id_ed25519"
  [[ -f "$key" && ! -L "$key" && -O "$key" ]] || die "owned CrabBox SSH key not found for lease"
  known_hosts="$HOME/Library/Application Support/crabbox/testboxes/$lease/known_hosts"
  [[ -f "$known_hosts" && ! -L "$known_hosts" && -O "$known_hosts" ]] || die "owned CrabBox known-hosts file not found for lease"
  known_hosts_option=${known_hosts// /\\ }
  guest_ip=$("$parallels_cli" list -i -f -j "$resource" | python3 -c 'import json,sys; rows=json.load(sys.stdin); addresses=rows[0].get("Network",{}).get("ipAddresses",[]) if rows else []; print(next((item.get("ip","") for item in addresses if item.get("type")=="ipv4"),""),end="")')
  [[ "$guest_ip" =~ '^[0-9A-Fa-f:.]+$' ]] || die "Parallels returned an invalid guest address"

  secret_file=$(mktemp "$STATE_ROOT/.guest-password-reset.XXXXXXXX")
  chmod 600 "$secret_file"
  typeset -g KEYPATH_LAB_SECURE_TEMP="$secret_file"
  trap '[[ -z ${KEYPATH_LAB_SECURE_TEMP:-} ]] || rm -f "$KEYPATH_LAB_SECURE_TEMP"' EXIT
  /opt/homebrew/bin/sops -d "$HOME/dotfiles/secrets.env" | awk -F= '$1 == "KEYPATH_LAB_GUEST_PASSWORD" {sub(/^[^=]*=/, ""); printf "%s", $0; found=1} END {if (!found) exit 1}' > "$secret_file" || die "KEYPATH_LAB_GUEST_PASSWORD is unavailable"
  [[ -s "$secret_file" ]] || die "guest password reset secret is empty"

  fifo="/tmp/keypath-password-reset-$lease-$$.fifo"
  account_file="/tmp/keypath-password-reset-$lease-$$.account"
  guest_command="set -euo pipefail; fifo=$(printf %q "$fifo"); account_file=$(printf %q "$account_file"); rm -f \"\$fifo\" \"\$account_file\"; /usr/bin/mkfifo \"\$fifo\"; /usr/sbin/chown keypathqa:staff \"\$fifo\"; /bin/chmod 600 \"\$fifo\"; trap 'rm -f \"\$fifo\"' EXIT; password=; IFS= read -r password < \"\$fifo\"; if /usr/sbin/sysadminctl -resetPasswordFor keypathqa -newPassword \"\$password\" >/dev/null 2>&1 && /usr/bin/dscl . -authonly keypathqa \"\$password\"; then account=keypathqa; else /usr/sbin/sysadminctl -deleteUser keypathmdm >/dev/null 2>&1 || true; /usr/sbin/sysadminctl -addUser keypathmdm -fullName 'KeyPath MDM' -password \"\$password\" -admin >/dev/null; /usr/bin/dscl . -authonly keypathmdm \"\$password\"; /usr/sbin/dseditgroup -o checkmember -m keypathmdm admin | /usr/bin/grep -q 'yes'; account=keypathmdm; fi; printf '%s\n' \"\$account\" > \"\$account_file\"; /bin/chmod 600 \"\$account_file\"; unset password"
  set +e
  "$parallels_cli" exec "$resource" /bin/zsh -lc "$(printf %q "$guest_command")" >/dev/null 2>&1 &
  reset_pid=$!
  fifo_ready=0
  for attempt in {1..300}; do
    if "$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts_option" -i "$key" "keypathqa@$guest_ip" \
      "/bin/test -p $(printf %q "$fifo")" </dev/null >/dev/null 2>&1; then
      fifo_ready=1
      break
    fi
    sleep 0.1
  done
  if (( fifo_ready == 1 )); then
    { /bin/cat "$secret_file"; printf '\n'; } | \
      "$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts_option" -i "$key" "keypathqa@$guest_ip" \
        "/bin/zsh -c $(printf %q "/bin/cat > $(printf %q "$fifo")")" >/dev/null 2>&1
    stream_exit=$?
  else
    stream_exit=76
    kill "$reset_pid" 2>/dev/null || true
  fi
  wait "$reset_pid"
  reset_exit=$?
  set -e
  "$parallels_cli" exec "$resource" /bin/rm -f "$fifo" >/dev/null 2>&1 || true
  enrollment_account=$("$parallels_cli" exec "$resource" /bin/cat "$account_file" 2>/dev/null | tail -1 || true)
  "$parallels_cli" exec "$resource" /bin/rm -f "$account_file" >/dev/null 2>&1 || true
  rm -f "$secret_file"
  KEYPATH_LAB_SECURE_TEMP=
  trap - EXIT
  (( stream_exit == 0 && reset_exit == 0 )) || die "failed to reset or provision and verify a disposable enrollment administrator"
  [[ "$enrollment_account" == "keypathqa" || "$enrollment_account" == "keypathmdm" ]] || die "disposable enrollment administrator result was invalid"

  record_command "$lease" passed reset-guest-password
  print "guest_password_reset\tpassed"
  print "credential_verification\tpassed"
  print "enrollment_account\t$enrollment_account"
}

reset_desktop_keychain() {
  local lease=$1 manifest macos resource parallels_cli secret_file key known_hosts known_hosts_option guest_ip
  local fifo marker guest_command reset_pid fifo_ready attempt stream_exit reset_exit backup
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  [[ "$macos" == "27" ]] || die "desktop keychain reset requires the macOS 27 lane"
  [[ "$(field "$manifest" provider)" == "parallels" ]] || die "desktop keychain reset requires a Parallels lease"
  [[ "$(field "$manifest" desktop_enabled)" == "true" ]] || die "desktop keychain reset requires a desktop-enabled lease"
  [[ "$(field "$manifest" console_login_status)" == "passed" ]] || die "desktop keychain reset requires a verified console login"
  resource=$(field "$manifest" provider_resource)
  [[ "$resource" =~ '^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$' ]] || die "invalid Parallels resource id"
  parallels_cli=${KEYPATH_LAB_PRLCTL:-"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"}
  [[ -x "$parallels_cli" ]] || die "Parallels CLI is unavailable"

  key="$HOME/Library/Application Support/crabbox/testboxes/$lease/id_ed25519"
  [[ -f "$key" && ! -L "$key" && -O "$key" ]] || die "owned CrabBox SSH key not found for lease"
  known_hosts="$HOME/Library/Application Support/crabbox/testboxes/$lease/known_hosts"
  [[ -f "$known_hosts" && ! -L "$known_hosts" && -O "$known_hosts" ]] || die "owned CrabBox known-hosts file not found for lease"
  known_hosts_option=${known_hosts// /\\ }
  guest_ip=$("$parallels_cli" list -i -f -j "$resource" | python3 -c 'import json,sys; rows=json.load(sys.stdin); addresses=rows[0].get("Network",{}).get("ipAddresses",[]) if rows else []; print(next((item.get("ip","") for item in addresses if item.get("type")=="ipv4"),""),end="")')
  [[ "$guest_ip" =~ '^[0-9A-Fa-f:.]+$' ]] || die "Parallels returned an invalid guest address"

  secret_file=$(mktemp "$STATE_ROOT/.desktop-keychain-reset.XXXXXXXX")
  chmod 600 "$secret_file"
  typeset -g KEYPATH_LAB_SECURE_TEMP="$secret_file"
  trap '[[ -z ${KEYPATH_LAB_SECURE_TEMP:-} ]] || rm -f "$KEYPATH_LAB_SECURE_TEMP"' EXIT
  /opt/homebrew/bin/sops -d "$HOME/dotfiles/secrets.env" | awk -F= '$1 == "KEYPATH_LAB_GUEST_PASSWORD" {sub(/^[^=]*=/, ""); printf "%s", $0; found=1} END {if (!found) exit 1}' > "$secret_file" || die "KEYPATH_LAB_GUEST_PASSWORD is unavailable"
  [[ -s "$secret_file" ]] || die "desktop keychain reset secret is empty"

  fifo="/tmp/keypath-keychain-reset-$lease-$$.fifo"
  marker="/tmp/keypath-keychain-reset-$lease-$$.marker"
  guest_command="set -euo pipefail; fifo=$(printf %q "$fifo"); marker=$(printf %q "$marker"); home=/Users/keypathqa; keychain=\"\$home/Library/Keychains/login.keychain-db\"; rm -f \"\$fifo\" \"\$marker\"; /usr/bin/mkfifo \"\$fifo\"; /usr/sbin/chown keypathqa:staff \"\$fifo\"; /bin/chmod 600 \"\$fifo\"; trap 'rm -f \"\$fifo\"' EXIT; password=; IFS= read -r password < \"\$fifo\"; backup=none; if [[ -e \"\$keychain\" ]]; then backup=\"\${keychain}.before-desktop-base-$(date -u +%Y%m%dT%H%M%SZ)\"; /bin/mv \"\$keychain\" \"\$backup\"; fi; /usr/sbin/chown -R keypathqa:staff \"\$home/Library/Keychains\"; /usr/bin/sudo -u keypathqa /usr/bin/env HOME=\"\$home\" /usr/bin/security create-keychain -p \"\$password\" \"\$keychain\"; /usr/bin/sudo -u keypathqa /usr/bin/env HOME=\"\$home\" /usr/bin/security list-keychains -d user -s \"\$keychain\"; /usr/bin/sudo -u keypathqa /usr/bin/env HOME=\"\$home\" /usr/bin/security default-keychain -d user -s \"\$keychain\"; /usr/bin/sudo -u keypathqa /usr/bin/env HOME=\"\$home\" /usr/bin/security unlock-keychain -p \"\$password\" \"\$keychain\"; /usr/bin/sudo -u keypathqa /usr/bin/env HOME=\"\$home\" /usr/bin/security set-keychain-settings -lut 21600 \"\$keychain\"; printf '%s\n' \"\$backup\" > \"\$marker\"; /bin/chmod 600 \"\$marker\"; unset password"
  set +e
  "$parallels_cli" exec "$resource" /bin/zsh -lc "$(printf %q "$guest_command")" >/dev/null 2>&1 &
  reset_pid=$!
  fifo_ready=0
  for attempt in {1..300}; do
    if "$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts_option" -i "$key" "keypathqa@$guest_ip" \
      "/bin/test -p $(printf %q "$fifo")" </dev/null >/dev/null 2>&1; then
      fifo_ready=1
      break
    fi
    sleep 0.1
  done
  if (( fifo_ready == 1 )); then
    { /bin/cat "$secret_file"; printf '\n'; } | \
      "$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts_option" -i "$key" "keypathqa@$guest_ip" \
        "/bin/zsh -c $(printf %q "/bin/cat > $(printf %q "$fifo")")" >/dev/null 2>&1
    stream_exit=$?
  else
    stream_exit=76
    kill "$reset_pid" 2>/dev/null || true
  fi
  wait "$reset_pid"
  reset_exit=$?
  set -e
  "$parallels_cli" exec "$resource" /bin/rm -f "$fifo" >/dev/null 2>&1 || true
  backup=$("$parallels_cli" exec "$resource" /bin/cat "$marker" 2>/dev/null | tail -1 || true)
  "$parallels_cli" exec "$resource" /bin/rm -f "$marker" >/dev/null 2>&1 || true
  rm -f "$secret_file"
  KEYPATH_LAB_SECURE_TEMP=
  trap - EXIT
  (( stream_exit == 0 && reset_exit == 0 )) || die "failed to establish a fresh disposable desktop keychain"
  [[ "$backup" == none || "$backup" == /Users/keypathqa/Library/Keychains/login.keychain-db.before-desktop-base-* ]] ||
    die "desktop keychain reset returned an invalid backup path"

  set_field "$manifest" desktop_keychain_status passed
  set_field "$manifest" desktop_keychain_at "$(utc_now)"
  record_command "$lease" passed reset-desktop-keychain
  print "desktop_keychain_reset\tpassed"
  print "previous_keychain\t$backup"
}

reboot_guest() {
  local lease=$1 manifest provider macos repo launcher resource parallels_cli state attempt ready=0 request_exit=0 poll_exit=0
  manifest=$(owned_manifest "$lease")
  provider=$(field "$manifest" provider)
  case "$provider" in
    parallels)
      resource=$(field "$manifest" provider_resource)
      [[ "$resource" =~ '^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$' ]] || die "invalid Parallels resource id"
      parallels_cli=${KEYPATH_LAB_PRLCTL:-"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"}
      [[ -x "$parallels_cli" ]] || die "Parallels CLI is unavailable"
      "$parallels_cli" restart "$resource" >/dev/null
      sleep 3
      for attempt in {1..600}; do
        state=$("$parallels_cli" list -i -f -j "$resource" 2>/dev/null |
          python3 -c 'import json,sys; rows=json.load(sys.stdin); print(rows[0].get("State","") if rows else "",end="")' 2>/dev/null || true)
        if [[ "$state" == "running" ]] &&
          "$parallels_cli" exec "$resource" /usr/bin/true >/dev/null 2>&1; then
          ready=1
          break
        fi
        sleep 0.1
      done
      (( ready == 1 )) || die "Parallels guest control did not recover after reboot"
      ;;
    tart)
      macos=$(field "$manifest" macos)
      [[ "$macos" == "15" ]] || die "unexpected Tart macOS lane: $macos"
      repo=$(field "$manifest" worktree)
      prepare_worktree "$repo"
      launcher=$(launcher_for "$macos")
      set +e
      (cd "$repo" && "$launcher" run "$lease" -- /bin/zsh -lc 'sudo -n /sbin/shutdown -r now') \
        > "$LOGS/$lease/reboot-request.log" 2>&1
      request_exit=$?
      set -e
      if (( request_exit != 0 )) && /usr/bin/grep -Eqi 'sudo:|not permitted|permission denied' "$LOGS/$lease/reboot-request.log"; then
        cat "$LOGS/$lease/reboot-request.log"
        die "Tart guest rejected the reboot request"
      fi
      sleep "${KEYPATH_LAB_TART_REBOOT_SETTLE_SECONDS:-3}"
      for attempt in {1..120}; do
        set +e
        (cd "$repo" && "$launcher" run "$lease" -- /usr/bin/true) \
          > "$LOGS/$lease/reboot-readiness.log" 2>&1
        poll_exit=$?
        set -e
        if (( poll_exit == 0 )); then
          ready=1
          break
        fi
        sleep "${KEYPATH_LAB_TART_REBOOT_POLL_SECONDS:-1}"
      done
      if (( ready != 1 )); then
        cat "$LOGS/$lease/reboot-readiness.log"
        die "Tart guest SSH did not recover after reboot"
      fi
      ;;
    *) die "unsupported reboot provider: $provider" ;;
  esac
  set_field "$manifest" guest_reboot_at "$(utc_now)"
  record_command "$lease" passed reboot-guest
  print "guest_reboot\tpassed"
  print "provider\t$provider"
}

rfb_pointer_probe() {
  local lease=$1 x=$2 y=$3 manifest macos resource parallels_cli key known_hosts known_hosts_option guest_ip cursor_command before after
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  [[ "$macos" == "26" || "$macos" == "27" ]] || die "RFB pointer probe currently supports only the macOS 26 and 27 Parallels lanes"
  [[ "$(field "$manifest" provider)" == "parallels" ]] || die "RFB pointer probe requires a Parallels lease"
  [[ "$(field "$manifest" desktop_enabled)" == "true" ]] || die "RFB pointer probe requires a desktop-enabled lease"
  if [[ "$macos" == "27" ]]; then
    [[ "$(field "$manifest" console_login_status)" == "passed" ]] || die "RFB pointer probe requires a verified console login on macOS 27"
  fi
  [[ "$x" == <-> && "$y" == <-> ]] || die "RFB pointer coordinates must be non-negative integers"
  resource=$(field "$manifest" provider_resource)
  [[ "$resource" =~ '^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$' ]] || die "invalid Parallels resource id"

  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    before=${KEYPATH_LAB_TEST_CURSOR_BEFORE:-"10 10"}
    key=${KEYPATH_LAB_TEST_SSH_KEY:?test SSH key is required}
  else
    parallels_cli=${KEYPATH_LAB_PRLCTL:-"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"}
    [[ -x "$parallels_cli" ]] || die "Parallels CLI is unavailable"
    key="$HOME/Library/Application Support/crabbox/testboxes/$lease/id_ed25519"
    [[ -f "$key" && ! -L "$key" && -O "$key" ]] || die "owned CrabBox SSH key not found for lease"
    known_hosts="$HOME/Library/Application Support/crabbox/testboxes/$lease/known_hosts"
    [[ -f "$known_hosts" && ! -L "$known_hosts" && -O "$known_hosts" ]] || die "owned CrabBox known-hosts file not found for lease"
    known_hosts_option=${known_hosts// /\\ }
    guest_ip=$("$parallels_cli" list -i -f -j "$resource" | python3 -c 'import json,sys; rows=json.load(sys.stdin); addresses=rows[0].get("Network",{}).get("ipAddresses",[]) if rows else []; print(next((item.get("ip","") for item in addresses if item.get("type")=="ipv4"),""),end="")')
    [[ "$guest_ip" =~ '^[0-9A-Fa-f:.]+$' ]] || die "Parallels returned an invalid guest address"
    cursor_command='/usr/bin/osascript -l JavaScript -e '\''ObjC.import("CoreGraphics"); p=$.CGEventGetLocation($.CGEventCreate(null)); p.x+" "+p.y'\'''
    before=$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts_option" -i "$key" "keypathqa@$guest_ip" "/bin/zsh -lc $(printf %q "$cursor_command")")
  fi
  [[ "$before" =~ '^[0-9]+(\.[0-9]+)? [0-9]+(\.[0-9]+)?$' ]] || die "RFB pointer probe could not read the initial guest cursor location"

  if [[ "${KEYPATH_LAB_TESTING:-0}" != "1" ]]; then
    export PATH="/Applications/Parallels Desktop.app/Contents/MacOS:$PATH"
  fi
  CRABBOX_PARALLELS_USER=keypathqa CRABBOX_SSH_USER=keypathqa CRABBOX_SSH_PORT=22 CRABBOX_SSH_KEY="$key" \
    "$CRABBOX" desktop click --provider parallels --target macos --id "$lease" --x "$x" --y "$y" >/dev/null
  sleep "${KEYPATH_LAB_RFB_POINTER_SETTLE_SECONDS:-1}"
  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    after=${KEYPATH_LAB_TEST_CURSOR_AFTER:-"$x $y"}
  else
    after=$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts_option" -i "$key" "keypathqa@$guest_ip" "/bin/zsh -lc $(printf %q "$cursor_command")")
  fi
  [[ "$after" =~ '^[0-9]+(\.[0-9]+)? [0-9]+(\.[0-9]+)?$' ]] || die "RFB pointer probe could not read the resulting guest cursor location"
  if [[ "$after" == "$before" ]]; then
    record_command "$lease" failed rfb-pointer-probe --x "$x" --y "$y"
    die "CrabBox acknowledged the RFB click but the guest cursor did not move"
  fi
  record_command "$lease" passed rfb-pointer-probe --x "$x" --y "$y"
  print "rfb_pointer_probe\tpassed"
  print "cursor_before\t$before"
  print "cursor_after\t$after"
}

nameplate_control() {
  local lease=$1 nameplate_action=$2 manifest macos lane provider repo script output version checksum state
  manifest=$(owned_manifest "$lease")
  [[ "$(field "$manifest" desktop_enabled)" == "true" ]] || die "Nameplate requires a desktop-enabled lease"
  repo=$(field "$manifest" worktree)
  prepare_worktree "$repo"
  script="Scripts/lab/nameplate-instrumentation"
  [[ -x "$repo/$script" ]] || die "Nameplate instrumentation is missing from the archived commit"
  if [[ "$nameplate_action" != enable ]]; then
    [[ "$(field "$manifest" nameplate_version)" == "$NAMEPLATE_VERSION" ]] || die "Nameplate is not enabled for lease: $lease"
  fi
  macos=$(field "$manifest" macos)
  lane=$(field "$manifest" test_lane)
  provider=$(field "$manifest" provider)
  case "$nameplate_action" in
    enable) output=$(run_command "$lease" /bin/zsh "$script" enable "$macos" "$lane" "$provider" "$lease") ;;
    show|hide|status) output=$(run_command "$lease" /bin/zsh "$script" "$nameplate_action") ;;
    *) die "invalid Nameplate action: $nameplate_action" ;;
  esac
  print -r -- "$output"
  version=$(printf '%s\n' "$output" | awk -F '\t' '$1 == "nameplate_version" {print $2; exit}')
  checksum=$(printf '%s\n' "$output" | awk -F '\t' '$1 == "nameplate_sha256" {print $2; exit}')
  state=$(printf '%s\n' "$output" | awk -F '\t' '$1 == "nameplate_state" {print $2; exit}')
  [[ "$version" == "$NAMEPLATE_VERSION" ]] || die "guest reported unexpected Nameplate version: ${version:-missing}"
  [[ "$checksum" == "$NAMEPLATE_SHA256" ]] || die "guest reported unexpected Nameplate checksum"
  [[ "$state" == visible || "$state" == hidden ]] || die "guest reported invalid Nameplate state: ${state:-missing}"
  if [[ "$nameplate_action" != status ]]; then
    set_field "$manifest" nameplate_version "$version"
    set_field "$manifest" nameplate_sha256 "$checksum"
    set_field "$manifest" nameplate_state "$state"
    set_field "$manifest" nameplate_last_changed_at "$(utc_now)"
  fi
}

destroy_lease() {
  local lease=$1 manifest macos launcher exit_code repo inventory inventory_exit provider_resource
  manifest=$(owned_manifest "$lease")
  [[ "$(field "$manifest" cleanup_status)" != "complete" ]] || { print "already_clean\t$lease"; return; }
  macos=$(field "$manifest" macos)
  launcher=$(launcher_for "$macos")
  repo=$(field "$manifest" worktree)
  prepare_worktree "$repo"
  mkdir -p "$LOGS/$lease"
  set +e
  (cd "$repo" && "$launcher" stop "$lease") > "$LOGS/$lease/destroy.log" 2>&1
  exit_code=$?
  set -e
  set_field "$manifest" cleanup_attempted_at "$(utc_now)"
  set_field "$manifest" cleanup_result "$exit_code"
  inventory=
  inventory_exit=1
  provider_resource=$(field "$manifest" provider_resource)
  if (( exit_code != 0 )); then
    set +e
    inventory=$("$launcher" list 2>> "$LOGS/$lease/destroy.log")
    inventory_exit=$?
    set -e
    print -r -- "$inventory" >> "$LOGS/$lease/destroy.log"
  fi
  if (( exit_code == 0 )) || {
    (( inventory_exit == 0 )) &&
      ! print -r -- "$inventory" | grep -Eo 'cbx_[A-Za-z0-9]+' | grep -Fxq "$lease" &&
      { [[ "$provider_resource" == "unknown" ]] || ! print -r -- "$inventory" | grep -Fq "$provider_resource"; }
  }; then
    set_field "$manifest" cleanup_status complete
    set_field "$manifest" status destroyed
    exit_code=0
  else
    set_field "$manifest" cleanup_status failed
    set_field "$manifest" status cleanup-failed
  fi
  cat "$LOGS/$lease/destroy.log"
  return "$exit_code"
}

cleanup_expired() {
  local dry_run=${1:-} current manifest lease expires cleanup
  [[ -z "$dry_run" || "$dry_run" == "--dry-run" ]] || die "invalid cleanup option"
  current=$(now_epoch)
  for manifest in "$LEASES"/*/manifest.tsv(N); do
    [[ "$(field "$manifest" owner)" == "$OWNER" ]] || continue
    lease=$(field "$manifest" lease_id)
    expires=$(field "$manifest" expires_epoch)
    cleanup=$(field "$manifest" cleanup_status)
    [[ "$expires" == <-> && "$expires" -le "$current" && "$cleanup" != "complete" ]] || continue
    if [[ "$dry_run" == "--dry-run" ]]; then
      print "would_destroy\t$lease"
    else
      destroy_lease "$lease" || true
    fi
  done
}

action=${1:-}
shift || true
case "$action" in
  preflight) [[ $# -eq 0 ]] || die "preflight takes no arguments"; preflight ;;
  archive-status) [[ $# -eq 4 ]] || die "archive-status requires key, commit, checksum, and name"; archive_status "$@" ;;
  prepare-upload) [[ $# -eq 1 ]] || die "prepare-upload requires archive key"; prepare_upload "$1" ;;
  install-archive) [[ $# -eq 5 ]] || die "install-archive requires ticket, key, commit, checksum, and name"; install_archive "$@" ;;
  derive-archive) [[ $# -eq 7 ]] || die "derive-archive requires ticket, source key, destination key, commit, checksum, name, and harness commit"; derive_archive "$@" ;;
  create) [[ $# -eq 8 || $# -eq 9 ]] || die "create requires macOS, test lane, archive, commit, checksum, name, ttl, desktop, and optional Tart USB passthrough"; create_lease "$@" ;;
  install-app) [[ $# -eq 1 ]] || die "install-app requires lease"; install_app "$1" ;;
  install-runtime) [[ $# -eq 1 ]] || die "install-runtime requires lease"; install_runtime "$1" ;;
  install-fixture) [[ $# -eq 1 ]] || die "install-fixture requires lease"; install_fixture "$1" ;;
  secure-dialog-input) [[ $# -eq 5 ]] || die "secure-dialog-input requires lease, app, field, optional submit value, and focus mode"; secure_dialog_input "$@" ;;
  resume-managed-policy) [[ $# -eq 1 ]] || die "resume-managed-policy requires a lease"; resume_managed_policy "$1" ;;
  protected-click) [[ $# -eq 7 || $# -eq 8 ]] || die "protected-click requires lease, app, before window, after window, coordinate space, x, y, and optional count"; protected_click "$@" ;;
  approve-input-monitoring) [[ $# -eq 1 ]] || die "approve-input-monitoring requires lease"; approve_input_monitoring "$1" ;;
  desktop-type) [[ $# -eq 2 ]] || die "desktop-type requires lease and text"; desktop_type "$@" ;;
  run) [[ $# -ge 2 ]] || die "run requires lease and command"; run_command "$@" ;;
  status) [[ $# -eq 1 ]] || die "status requires lease"; print_status "$1" ;;
  list) [[ $# -eq 0 ]] || die "list takes no arguments"; list_leases ;;
  artifacts) [[ $# -eq 1 ]] || die "artifacts requires lease"; collect_artifacts "$1" ;;
  scenario) [[ $# -eq 2 ]] || die "scenario requires lease and name"; scenario "$1" "$2" ;;
  desktop-bootstrap) [[ $# -eq 2 ]] || die "desktop-bootstrap requires lease and install-tools flag"; desktop_bootstrap "$@" ;;
  console-login) [[ $# -eq 1 ]] || die "console-login requires lease"; console_login "$1" ;;
  verify-console-login) [[ $# -eq 1 ]] || die "verify-console-login requires lease"; verify_console_login "$1" ;;
  reset-guest-password) [[ $# -eq 1 ]] || die "reset-guest-password requires lease"; reset_guest_password "$1" ;;
  reset-desktop-keychain) [[ $# -eq 1 ]] || die "reset-desktop-keychain requires lease"; reset_desktop_keychain "$1" ;;
  reboot-guest) [[ $# -eq 1 ]] || die "reboot-guest requires lease"; reboot_guest "$1" ;;
  secure-console-submit) [[ $# -eq 1 ]] || die "secure-console-submit requires lease"; secure_console_submit "$1" ;;
  console-key) [[ $# -eq 3 ]] || die "console-key requires lease, Parallels key code, and modifier code"; console_key "$1" "$2" "$3" ;;
  rfb-pointer-probe) [[ $# -eq 3 ]] || die "rfb-pointer-probe requires lease, x, and y"; rfb_pointer_probe "$@" ;;
  nameplate) [[ $# -eq 2 ]] || die "nameplate requires lease and action"; nameplate_control "$@" ;;
  destroy) [[ $# -eq 1 ]] || die "destroy requires lease"; destroy_lease "$1" ;;
  cleanup) cleanup_expired "${1:-}" ;;
  *) die "unknown action: $action" ;;
esac
