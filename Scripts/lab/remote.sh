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

base_for() {
  local macos=$1 lane=$2
  if [[ "$macos" == "15" ]]; then
    [[ "$lane" == "managed-functional" ]] && print keypath-macos-15-managed || print ghcr.io/cirruslabs/macos-sequoia-base:latest
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
    "$CRABBOX" warmup --provider "$(provider_for "$macos")" --target macos --desktop --slug "$slug" --ttl 2h
  elif [[ "$macos" == "15" ]]; then
    if [[ "${USER:-}" == "clawd" ]]; then export TART_HOME="$LAB_ROOT/TartHome-clawd"; else export TART_HOME="$LAB_ROOT/TartHome"; fi
    export PATH="$LAB_ROOT/CompatTools/bin:$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    "$CRABBOX" warmup --provider tart --target macos --desktop \
      --tart-image "$(base_for "$macos" "$lane")" \
      --tart-user admin --tart-cpu 4 --tart-memory 8192 --ssh-port 22 \
      --slug "$slug" --ttl 2h
  else
    export PATH="$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    "$CRABBOX" warmup --provider parallels --target macos --desktop \
      --parallels-template "$(base_for "$macos" "$lane")" --parallels-user keypathqa \
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
    export PATH="$LAB_ROOT/CompatTools/bin:$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    "$CRABBOX" warmup --provider tart --target macos \
      --tart-image "$(base_for "$macos" "$lane")" \
      --tart-user admin --tart-cpu 4 --tart-memory 8192 --ssh-port 22 \
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
  valid_id "$1"
  [[ "$1" =~ '^[0-9a-f]{40}-[0-9a-f]{64}$' ]] || die "invalid archive key"
  mktemp "/tmp/keypath-lab.XXXXXXXX"
}

install_archive() {
  local source=$1 key=$2 commit=$3 installer_sha=$4 installer_name=$5
  [[ "$source" =~ '^/tmp/keypath-lab\.[A-Za-z0-9]+$' ]] || die "invalid upload ticket"
  [[ -f "$source" && ! -L "$source" && -O "$source" ]] || die "upload ticket is not an owned regular file"
  valid_id "$key"
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

write_provisional_lease_manifest() {
  local lease=$1 slug=$2 macos=$3 lane=$4 provider=$5 archive_key=$6 commit=$7 installer_sha=$8 installer_name=$9 repo=${10} created=${11} expires=${12} desktop=${13}
  local manifest
  valid_id "$lease"
  mkdir -p "$LEASES/$lease" "$LOGS/$lease" "$ARTIFACTS/$lease"
  manifest=$(manifest_path "$lease")
  [[ -e "$manifest" ]] && return
  {
    print "owner\t$OWNER"
    print "lease_id\t$lease"
    print "slug\t$slug"
    print "macos\t$macos"
    print "test_lane\t$lane"
    print "base_name\t$(base_for "$macos" "$lane")"
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
  local macos=$1 lane=$2 archive_key=$3 commit=$4 installer_sha=$5 installer_name=$6 ttl=$7 desktop=$8
  local launcher provider archive repo slug output lease created expires manifest guest_output product build operation ttl_seconds provider_resource create_status candidate_file create_log exit_code
  launcher=$(launcher_for "$macos")
  provider=$(provider_for "$macos")
  [[ "$lane" == "managed-functional" || "$lane" == "unmanaged-ui" ]] || die "invalid test lane: $lane"
  [[ ! ("$macos" == "27" && "$lane" == "managed-functional") ]] || die "managed-functional is not yet supported on macOS 27"
  valid_id "$archive_key"
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
  assert_internal_disk_reserve || return $?
  created=$(now_epoch)
  expires=$((created + ttl_seconds))
  slug="keypath${macos}-$(print -r -- "$commit" | cut -c1-8)-$(date -u +%Y%m%d%H%M%S)-$$"
  operation="$OPERATIONS/$slug"
  mkdir -p "$operation"
  git clone -q --local "$archive/repo" "$operation/repo"
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
  {
    print "owner\t$OWNER"
    print "lease_id\t$lease"
    print "slug\t$slug"
    print "macos\t$macos"
    print "test_lane\t$lane"
    print "base_name\t$(base_for "$macos" "$lane")"
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
    print "provider_resource\t${provider_resource:-unknown}"
  } > "$manifest"
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
  command="set -euo pipefail; $admission_command; rm -rf /tmp/keypath-install; mkdir -p /tmp/keypath-install; ditto -x -k '$guest_repo/.keypath-lab/installer/$installer_name' /tmp/keypath-install; cd '$guest_repo'; if [[ '$lane' == managed-functional ]]; then Scripts/lab/mdm/verify-artifact-policy --app /tmp/keypath-install/KeyPath.app --manifest /Library/KeyPathLab/managed-policy/manifest.json; fi; rm -rf /Applications/KeyPath.app; ditto /tmp/keypath-install/KeyPath.app /Applications/KeyPath.app"
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

run_command() {
  local lease=$1; shift
  local manifest macos launcher repo log exit_code
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  launcher=$(launcher_for "$macos")
  repo=$(field "$manifest" worktree)
  prepare_worktree "$repo"
  log="$LOGS/$lease/run-$(date -u +%Y%m%dT%H%M%SZ).log"
  set +e
  (cd "$repo" && "$launcher" run "$lease" -- "$@") 2>&1 | tee "$log"
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

  # Peekaboo's MCP type response contains the typed value. Suppress both output
  # streams for that command so the secret cannot enter controller logs.
  local refresh_command field_command click_command submit_command submit_label_quoted button_geometry_command postcondition_command
  local -a refresh_args focus_args click_args submit_args button_geometry_args postcondition_args
  guest_command='set -euo pipefail; command -v /opt/homebrew/bin/peekaboo >/dev/null; command -v /opt/homebrew/bin/mcporter >/dev/null; '
  if [[ "$field_label" == "AXSecureTextField" ]]; then
    [[ -n "$submit_button" ]] || die "AXSecureTextField requires a submit button for postcondition verification"
    [[ "$already_focused" == "0" ]] || die "AXSecureTextField does not use --already-focused"
    focus_args=(/usr/bin/osascript -l JavaScript -e 'function descendants(element) { var result = []; try { var children = element.uiElements(); for (var i = 0; i < children.length; i++) { result.push(children[i]); result = result.concat(descendants(children[i])); } } catch (_) {} return result; } function run(argv) { var appName = argv[1]; var secret = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null).js.replace(/\r?\n$/, ""); var process = Application("System Events").processes.byName(appName); var field = descendants(process.windows[0]).find(function (element) { try { return element.subrole() === "AXSecureTextField"; } catch (_) { return false; } }); if (!field) throw new Error("secure text field not found"); field.value = secret; }')
    printf -v field_command '%q ' "${focus_args[@]}"
    guest_command+='IFS= read -r secret_value; secret_path=$(/usr/bin/mktemp /tmp/keypath-secure-input.XXXXXX); /bin/chmod 600 "$secret_path"; trap '\''rm -f "$secret_path"'\'' EXIT; printf '\''%s'\'' "$secret_value" > "$secret_path"; unset secret_value; '
    guest_command+="$field_command \"\$secret_path\" $(printf %q "$app") >/dev/null; rm -f \"\$secret_path\"; trap - EXIT"
  elif [[ "$already_focused" == "0" ]]; then
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
  if [[ "$field_label" != "AXSecureTextField" ]]; then
    guest_command+='PEEKABOO_VISUALIZER_MASK_TYPED_TEXT=true /opt/homebrew/bin/mcporter call --stdio '\''peekaboo mcp serve --bridge-socket "$HOME/Library/Application Support/Peekaboo/daemon.sock"'\'' --env PEEKABOO_VISUALIZER_MASK_TYPED_TEXT=true type text=@/dev/stdin clear=true --output json --timeout 20000 >/dev/null 2>&1 || exit 42'
  fi
  if [[ -n "$submit_button" ]]; then
    if [[ "$field_label" == "AXSecureTextField" ]]; then
      button_geometry_args=(/usr/bin/osascript -l JavaScript -e 'function descendants(element) { var result = []; try { var children = element.uiElements(); for (var i = 0; i < children.length; i++) { result.push(children[i]); result = result.concat(descendants(children[i])); } } catch (_) {} return result; } function run(argv) { var process = Application("System Events").processes.byName(argv[0]); var label = argv[1]; var button = descendants(process.windows[0]).find(function (element) { try { return element.role() === "AXButton" && (element.name() === label || element.description() === label); } catch (_) { return false; } }); if (!button) throw new Error("submit button not found"); var position = button.position(); var size = button.size(); return Math.round(position[0] + size[0] / 2) + "," + Math.round(position[1] + size[1] / 2); }' "$app" "$submit_button")
      printf -v button_geometry_command '%q ' "${button_geometry_args[@]}"
      guest_command+="; button_coords=\$( $button_geometry_command ); [[ \"\$button_coords\" =~ '^-?[0-9]+,-?[0-9]+$' ]] || exit 78; /opt/homebrew/bin/peekaboo click --coords \"\$button_coords\" --global-coords --foreground --input-strategy synthOnly --json >/dev/null"
    else
      submit_args=(/opt/homebrew/bin/peekaboo click "$submit_button" --app "$app" --foreground --json)
      printf -v submit_command '%q ' "${submit_args[@]}"
      printf -v submit_label_quoted '%q' "$submit_button"
      guest_command+="; $refresh_command >/tmp/keypath-secure-submit.json || exit 44; if ! $submit_command >/dev/null; then $refresh_command >/tmp/keypath-secure-submit.json || exit 43; /usr/bin/env python3 -c 'import json,sys; elements=json.load(open(sys.argv[1])).get(\"data\",{}).get(\"ui_elements\",[]); raise SystemExit(1 if any(e.get(\"label\")==sys.argv[2] for e in elements) else 0)' /tmp/keypath-secure-submit.json $submit_label_quoted || exit 43; fi"
      guest_command+="; for attempt in {1..150}; do $refresh_command >/tmp/keypath-secure-postcondition.json || exit 44; /usr/bin/env python3 -c 'import json,sys; elements=json.load(open(sys.argv[1])).get(\"data\",{}).get(\"ui_elements\",[]); labels={e.get(\"label\") for e in elements}; raise SystemExit(0 if sys.argv[2] not in labels and sys.argv[3] not in labels else 1)' /tmp/keypath-secure-postcondition.json $(printf %q "$field_label") $submit_label_quoted && break; sleep 0.1; done; /usr/bin/env python3 -c 'import json,sys; elements=json.load(open(sys.argv[1])).get(\"data\",{}).get(\"ui_elements\",[]); labels={e.get(\"label\") for e in elements}; raise SystemExit(0 if sys.argv[2] not in labels and sys.argv[3] not in labels else 79)' /tmp/keypath-secure-postcondition.json $(printf %q "$field_label") $submit_label_quoted"
    fi
  fi
  if [[ "$field_label" == "AXSecureTextField" ]]; then
    postcondition_args=(/usr/bin/osascript -l JavaScript -e 'function descendants(element) { var result = []; try { var children = element.uiElements(); for (var i = 0; i < children.length; i++) { result.push(children[i]); result = result.concat(descendants(children[i])); } } catch (_) {} return result; } function run(argv) { var processes = Application("System Events").processes.whose({name: argv[0]})(); if (processes.length === 0 || processes[0].windows().length === 0) return "closed"; var open = descendants(processes[0].windows[0]).some(function (element) { try { return element.subrole() === "AXSecureTextField"; } catch (_) { return false; } }); return open ? "open" : "closed"; }' "$app")
    printf -v postcondition_command '%q ' "${postcondition_args[@]}"
    guest_command+="; for attempt in {1..150}; do [[ \$( $postcondition_command ) == closed ]] && exit 0; sleep 0.1; done; exit 77"
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
  local lease=$1 app=$2 expected_before=$3 expected_after=$4 coordinate_space=$5 x=$6 y=$7
  local manifest macos resource key ip before after guest_command geometry_command geometry
  local native_width native_height logical_width logical_height scale_x scale_y
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  [[ "$macos" == "15" ]] || die "protected click currently supports only the Tart macOS 15 lane"
  [[ "$(field "$manifest" desktop_enabled)" == "true" ]] || die "protected click requires a desktop-enabled lease"
  [[ "$x" == <-> && "$y" == <-> ]] || die "protected click coordinates must be non-negative integers"
  [[ "$coordinate_space" == "native" || "$coordinate_space" == "ax" ]] || die "invalid protected click coordinate space"
  resource=$(field "$manifest" provider_resource)
  [[ "$resource" =~ '^[A-Za-z0-9._-]+$' && "$resource" != "unknown" ]] || die "invalid Tart resource id"

  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    before=${KEYPATH_LAB_TEST_WINDOW_BEFORE:-$expected_before}
  else
    key="$HOME/Library/Application Support/crabbox/testboxes/$lease/id_ed25519"
    [[ -f "$key" && ! -L "$key" && -O "$key" ]] || die "owned CrabBox SSH key not found for lease"
    if [[ "${USER:-}" == "clawd" ]]; then export TART_HOME="$LAB_ROOT/TartHome-clawd"; else export TART_HOME="$LAB_ROOT/TartHome"; fi
    export PATH="$LAB_ROOT/CompatTools/bin:$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    ip=$($TART ip "$resource")
    [[ "$ip" =~ '^[0-9A-Fa-f:.]+$' ]] || die "Tart returned an invalid guest address"
    printf -v guest_command '%q ' /opt/homebrew/bin/peekaboo see --app "$app" --json
    guest_command+="| /usr/bin/env python3 -c 'import json,sys; print(json.load(sys.stdin).get(\"data\",{}).get(\"window_title\",\"\"))'"
    before=$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$guest_command")")
  fi
  [[ "$before" == "$expected_before" ]] || {
    record_command "$lease" failed protected-click --app "$app" --window "$expected_before" --x "$x" --y "$y"
    die "protected click precondition failed: expected window '$expected_before', found '${before:-unknown}'"
  }

  if [[ "$coordinate_space" == "ax" ]]; then
    if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
      geometry=${KEYPATH_LAB_TEST_DISPLAY_GEOMETRY:-'2048 1536 1024 768'}
    else
      geometry_command='/opt/homebrew/bin/peekaboo list windows --app '$(printf %q "$app")' --json | /usr/bin/env python3 -c '\''import json,re,sys; data=json.load(sys.stdin).get("data",{}); windows=data.get("windows",data if isinstance(data,list) else []); names=[w.get("screenName","") for w in windows if isinstance(w,dict)]; m=next((re.search(r"([0-9]+)×([0-9]+)",n) for n in names if re.search(r"([0-9]+)×([0-9]+)",n)),None); print(f"{m.group(1)} {m.group(2)}" if m else "",end="")'\''; printf " "; /usr/bin/osascript -l JavaScript -e '\''ObjC.import("AppKit"); var s=$.NSScreen.mainScreen.frame.size; s.width+" "+s.height'\'''
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

  "$CRABBOX" desktop click --provider tart --target macos --id "$resource" --x "$x" --y "$y" >/dev/null
  sleep "${KEYPATH_LAB_PROTECTED_CLICK_SETTLE_SECONDS:-1}"
  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    after=${KEYPATH_LAB_TEST_WINDOW_AFTER:-$expected_after}
  else
    after=$("$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$guest_command")")
  fi
  [[ "$after" == "$expected_after" ]] || {
    record_command "$lease" failed protected-click --app "$app" --window "$expected_before" --after-window "$expected_after" --x "$x" --y "$y"
    die "protected click postcondition failed: expected window '$expected_after', found '${after:-unknown}'"
  }
  record_command "$lease" passed protected-click --app "$app" --window "$expected_before" --after-window "$expected_after" --x "$x" --y "$y"
  print "protected_click\tpassed"
  print "window_before\t$before"
  print "window_after\t$after"
  print "coordinate_space\t$coordinate_space"
  if [[ "$coordinate_space" == "ax" ]]; then
    print "display_scale\t$scale_x"
  fi
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
      [[ "$provider_resource" =~ '^[A-Fa-f0-9-]+$' && "$provider_resource" != "unknown" ]] || die "invalid Parallels resource id"
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
  local lease=$1 name=$2 manifest repo scenario_script lane
  manifest=$(owned_manifest "$lease")
  repo=$(field "$manifest" worktree)
  lane=$(field "$manifest" test_lane)
  prepare_worktree "$repo"
  scenario_script="Scripts/lab/scenarios/installer-scenario"
  [[ -x "$repo/$scenario_script" ]] || die "scenario runner missing from archived commit"
  run_command "$lease" "/bin/zsh" "$scenario_script" "$name" "$lane"
}

desktop_bootstrap() {
  local lease=$1 install_tools=$2 manifest macos repo output guest_output command
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  [[ "$(field "$manifest" desktop_enabled)" == "true" ]] || die "desktop bootstrap requires a desktop-enabled lease"
  repo=$(field "$manifest" worktree)
  prepare_worktree "$repo"
  output=".keypath-lab/scenario-output/bootstrap"
  command=(/bin/zsh Scripts/lab/desktop-bootstrap --output "$output")
  [[ "$install_tools" == "1" ]] && command+=(--install-tools)
  run_command "$lease" "${command[@]}"
  set_field "$manifest" desktop_bootstrap_at "$(utc_now)"
  set_field "$manifest" desktop_bootstrap_status passed
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
  local lease=$1 manifest macos launcher exit_code repo inventory inventory_exit
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
  if (( exit_code != 0 )) && [[ "$(field "$manifest" provider_resource)" == "unknown" ]]; then
    set +e
    inventory=$("$launcher" list 2>> "$LOGS/$lease/destroy.log")
    inventory_exit=$?
    set -e
    print -r -- "$inventory" >> "$LOGS/$lease/destroy.log"
  fi
  if (( exit_code == 0 )) || {
    (( inventory_exit == 0 )) &&
      ! print -r -- "$inventory" | grep -Eo 'cbx_[A-Za-z0-9]+' | grep -Fxq "$lease"
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
  prepare-upload) [[ $# -eq 1 ]] || die "prepare-upload requires archive key"; prepare_upload "$1" ;;
  install-archive) [[ $# -eq 5 ]] || die "install-archive requires ticket, key, commit, checksum, and name"; install_archive "$@" ;;
  create) [[ $# -eq 8 ]] || die "create requires macOS, test lane, archive, commit, checksum, name, ttl, desktop"; create_lease "$@" ;;
  install-app) [[ $# -eq 1 ]] || die "install-app requires lease"; install_app "$1" ;;
  secure-dialog-input) [[ $# -eq 5 ]] || die "secure-dialog-input requires lease, app, field, optional submit value, and focus mode"; secure_dialog_input "$@" ;;
  protected-click) [[ $# -eq 7 ]] || die "protected-click requires lease, app, before window, after window, coordinate space, x, and y"; protected_click "$@" ;;
  desktop-type) [[ $# -eq 2 ]] || die "desktop-type requires lease and text"; desktop_type "$@" ;;
  run) [[ $# -ge 2 ]] || die "run requires lease and command"; run_command "$@" ;;
  status) [[ $# -eq 1 ]] || die "status requires lease"; print_status "$1" ;;
  list) [[ $# -eq 0 ]] || die "list takes no arguments"; list_leases ;;
  artifacts) [[ $# -eq 1 ]] || die "artifacts requires lease"; collect_artifacts "$1" ;;
  scenario) [[ $# -eq 2 ]] || die "scenario requires lease and name"; scenario "$1" "$2" ;;
  desktop-bootstrap) [[ $# -eq 2 ]] || die "desktop-bootstrap requires lease and install-tools flag"; desktop_bootstrap "$@" ;;
  nameplate) [[ $# -eq 2 ]] || die "nameplate requires lease and action"; nameplate_control "$@" ;;
  destroy) [[ $# -eq 1 ]] || die "destroy requires lease"; destroy_lease "$1" ;;
  cleanup) cleanup_expired "${1:-}" ;;
  *) die "unknown action: $action" ;;
esac
