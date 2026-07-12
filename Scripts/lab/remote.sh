#!/bin/zsh
set -euo pipefail

PRODUCTION_ROOT="/Volumes/KeyPath Lab/CrabBox"
OWNER="keypath-installer-lab-v1"

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
  local macos=$1 slug=$2
  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
    "$CRABBOX" warmup --provider "$(provider_for "$macos")" --target macos --desktop --slug "$slug" --ttl 2h
  elif [[ "$macos" == "15" ]]; then
    if [[ "${USER:-}" == "clawd" ]]; then export TART_HOME="$LAB_ROOT/TartHome-clawd"; else export TART_HOME="$LAB_ROOT/TartHome"; fi
    export PATH="$LAB_ROOT/CompatTools/bin:$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    "$CRABBOX" warmup --provider tart --target macos --desktop \
      --tart-image ghcr.io/cirruslabs/macos-sequoia-base:latest \
      --tart-user admin --tart-cpu 4 --tart-memory 8192 --ssh-port 22 \
      --slug "$slug" --ttl 2h
  else
    export PATH="$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    "$CRABBOX" warmup --provider parallels --target macos --desktop \
      --parallels-template "keypath-macos-$macos" --parallels-user keypathqa \
      --parallels-work-root /Users/keypathqa/crabbox --ssh-port 22 \
      --slug "$slug" --ttl 2h
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

create_lease() {
  local macos=$1 archive_key=$2 commit=$3 installer_sha=$4 installer_name=$5 ttl=$6 desktop=$7
  local launcher provider archive repo slug output lease created expires manifest guest_output product build operation ttl_seconds provider_resource
  launcher=$(launcher_for "$macos")
  provider=$(provider_for "$macos")
  valid_id "$archive_key"
  archive="$ARCHIVES/$archive_key"
  [[ -f "$archive/ready.tsv" && -d "$archive/repo/.git" ]] || die "prepared archive not found: $archive_key"
  ttl_seconds=$(duration_seconds "$ttl")
  (( ttl_seconds > 0 && ttl_seconds <= 7200 )) || die "TTL must be between 1 second and 2 hours"
  slug="keypath${macos}-$(print -r -- "$commit" | cut -c1-8)-$(date -u +%Y%m%d%H%M%S)-$$"
  operation="$OPERATIONS/$slug"
  mkdir -p "$operation"
  git clone -q --local "$archive/repo" "$operation/repo"
  repo="$operation/repo"
  prepare_worktree "$repo"
  if [[ "$desktop" == "1" ]]; then
    output=$(cd "$repo" && warmup_desktop "$macos" "$slug" 2>&1)
  else
    output=$(cd "$repo" && "$launcher" warmup "$slug" 2>&1)
  fi
  print -r -- "$output"
  print -r -- "$output" > "$operation/create.log"
  lease=$(print -r -- "$output" | grep -Eo 'cbx_[A-Za-z0-9]+' | tail -1 || true)
  [[ -n "$lease" ]] || die "CrabBox did not report a lease id; inspect provider inventory before cleanup"
  valid_id "$lease"
  provider_resource=$(print -r -- "$output" | sed -nE 's/.* (vm|instance)=([^ ]+).*/\2/p' | tail -1)
  created=$(now_epoch)
  expires=$((created + ttl_seconds))
  mkdir -p "$LEASES/$lease" "$LOGS/$lease" "$ARTIFACTS/$lease"
  manifest=$(manifest_path "$lease")
  {
    print "owner\t$OWNER"
    print "lease_id\t$lease"
    print "slug\t$slug"
    print "macos\t$macos"
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
  print "lease_id\t$lease"
  print "manifest\t$manifest"
}

install_app() {
  local lease=$1 manifest macos repo installer_name provider_resource guest_repo command exit_code
  manifest=$(owned_manifest "$lease")
  macos=$(field "$manifest" macos)
  repo=$(field "$manifest" worktree)
  installer_name=$(field "$manifest" installer_name)
  provider_resource=$(field "$manifest" provider_resource)
  prepare_worktree "$repo"
  guest_repo="/Users/$([[ "$macos" == "15" ]] && print admin || print keypathqa)/crabbox/$lease/repo"
  command="set -euo pipefail; rm -rf /tmp/keypath-install; mkdir -p /tmp/keypath-install; ditto -x -k '$guest_repo/.keypath-lab/installer/$installer_name' /tmp/keypath-install; rm -rf /Applications/KeyPath.app; ditto /tmp/keypath-install/KeyPath.app /Applications/KeyPath.app"
  set +e
  if [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]]; then
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
  local lease=$1 app=$2 field_label=$3 submit_button=$4
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
    trap 'rm -f "$secret_file"' EXIT
    /opt/homebrew/bin/sops -d "$HOME/dotfiles/secrets.env" | awk -F= '$1 == "KEYPATH_TART_ADMIN_PASSWORD" {sub(/^[^=]*=/, ""); print; found=1} END {if (!found) exit 1}' > "$secret_file" || die "KEYPATH_TART_ADMIN_PASSWORD is unavailable"
  fi
  [[ -s "$secret_file" ]] || die "secure input secret is empty"
  if [[ "${USER:-}" == "clawd" ]]; then export TART_HOME="$LAB_ROOT/TartHome-clawd"; else export TART_HOME="$LAB_ROOT/TartHome"; fi
  ip=$($TART ip "$resource")
  [[ "$ip" =~ '^[0-9A-Fa-f:.]+$' ]] || die "Tart returned an invalid guest address"

  # Peekaboo's MCP type response contains the typed value. Suppress both output
  # streams for that command so the secret cannot enter controller logs.
  guest_command='set -euo pipefail; command -v /opt/homebrew/bin/peekaboo >/dev/null; command -v /opt/homebrew/bin/mcporter >/dev/null; '
  printf -v guest_command '%s%q ' "$guest_command" /opt/homebrew/bin/peekaboo click --app "$app" --query "$field_label" --json
  guest_command+=" >/dev/null; "
  guest_command+='PEEKABOO_VISUALIZER_MASK_TYPED_TEXT=true /opt/homebrew/bin/mcporter call --stdio '\''peekaboo mcp serve --bridge-socket "$HOME/Library/Application Support/Peekaboo/daemon.sock"'\'' --env PEEKABOO_VISUALIZER_MASK_TYPED_TEXT=true type text=@/dev/stdin clear=true --output json --timeout 20000 >/dev/null 2>&1'
  if [[ -n "$submit_button" ]]; then
    printf -v guest_command '%s; %q ' "$guest_command" /opt/homebrew/bin/peekaboo click --app "$app" --query "$submit_button" --json
    guest_command+=" >/dev/null"
  fi
  set +e
  "$GUEST_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$key" "admin@$ip" "/bin/zsh -lc $(printf %q "$guest_command")" < "$secret_file"
  exit_code=$?
  set -e
  [[ "${KEYPATH_LAB_TESTING:-0}" == "1" ]] || rm -f "$secret_file"
  if (( exit_code == 0 )); then
    record_command "$lease" passed secure-dialog-input --app "$app" --field "$field_label" ${submit_button:+--submit "$submit_button"}
    print "secure_dialog_input\tpassed"
  else
    record_command "$lease" "failed:$exit_code" secure-dialog-input --app "$app" --field "$field_label" ${submit_button:+--submit "$submit_button"}
    die "secure dialog input failed"
  fi
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
  print "lease_id\tmacos\tprovider\tstatus\texpires_epoch\tcommit\tcleanup"
  local manifest lease
  for manifest in "$LEASES"/*/manifest.tsv(N); do
    [[ "$(field "$manifest" owner)" == "$OWNER" ]] || continue
    lease=$(field "$manifest" lease_id)
    print "$lease\t$(field "$manifest" macos)\t$(field "$manifest" provider)\t$(field "$manifest" status)\t$(field "$manifest" expires_epoch)\t$(field "$manifest" keypath_commit)\t$(field "$manifest" cleanup_status)"
  done
}

collect_artifacts() {
  local lease=$1 manifest output exit_code macos repo archive
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
  archive="$output/scenario-output.tar.gz"
  set +e
  (cd "$repo" && run_with_download "$macos" "$lease" ".keypath-lab/scenario-output.tar.gz" "$archive" \
    /bin/zsh -lc 'set -e; out=.keypath-lab/scenario-output/controller-capture; mkdir -p "$out/logs"; sw_vers > "$out/sw-vers.txt"; date -u +%Y-%m-%dT%H:%M:%SZ > "$out/captured-at.txt"; cp -R "$HOME/Library/Logs/KeyPath/." "$out/logs/" 2>/dev/null || true; /Applications/KeyPath.app/Contents/MacOS/keypath-cli system inspect --json > "$out/system-inspect.json" 2>/dev/null || true; tar -czf .keypath-lab/scenario-output.tar.gz -C .keypath-lab scenario-output') > "$output/download.log" 2>&1
  exit_code=$?
  set -e
  if (( exit_code == 0 )); then
    tar -xzf "$archive" -C "$output"
  fi
  if [[ "$(field "$manifest" desktop_enabled)" == "true" ]]; then
    set +e
    if [[ "$macos" == "15" ]]; then
      if [[ "${USER:-}" == "clawd" ]]; then export TART_HOME="$LAB_ROOT/TartHome-clawd"; else export TART_HOME="$LAB_ROOT/TartHome"; fi
      export PATH="$LAB_ROOT/CompatTools/bin:$LAB_ROOT/SharedTools/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      (cd "$repo" && "$CRABBOX" screenshot --provider tart --target macos --id "$lease" --output "$output/screenshot.png") >> "$output/download.log" 2>&1
    else
      (cd "$repo" && "$CRABBOX" screenshot --provider parallels --target macos --id "$lease" --parallels-user keypathqa --parallels-work-root /Users/keypathqa/crabbox --output "$output/screenshot.png") >> "$output/download.log" 2>&1
    fi
    screenshot_exit=$?
    set -e
    set_field "$manifest" screenshot_status "$screenshot_exit"
  else
    screenshot_exit=unavailable:lease-not-created-with-desktop
    set_field "$manifest" screenshot_status "$screenshot_exit"
  fi
  set_field "$manifest" artifacts_status "$exit_code"
  set_field "$manifest" artifacts_last_collected_at "$(utc_now)"
  print "artifact_dir\t$output"
  print "download_status\t$exit_code"
  print "screenshot_status\t$screenshot_exit"
  return "$exit_code"
}

scenario() {
  local lease=$1 name=$2 manifest repo scenario_script
  manifest=$(owned_manifest "$lease")
  repo=$(field "$manifest" worktree)
  prepare_worktree "$repo"
  scenario_script="Scripts/lab/scenarios/installer-scenario"
  [[ -x "$repo/$scenario_script" ]] || die "scenario runner missing from archived commit"
  run_command "$lease" "/bin/zsh" "$scenario_script" "$name"
}

destroy_lease() {
  local lease=$1 manifest macos launcher exit_code repo
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
  if (( exit_code == 0 )); then
    set_field "$manifest" cleanup_status complete
    set_field "$manifest" status destroyed
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
  create) [[ $# -eq 7 ]] || die "create requires lane, archive, commit, checksum, name, ttl, desktop"; create_lease "$@" ;;
  install-app) [[ $# -eq 1 ]] || die "install-app requires lease"; install_app "$1" ;;
  secure-dialog-input) [[ $# -eq 4 ]] || die "secure-dialog-input requires lease, app, field, and optional submit value"; secure_dialog_input "$@" ;;
  run) [[ $# -ge 2 ]] || die "run requires lease and command"; run_command "$@" ;;
  status) [[ $# -eq 1 ]] || die "status requires lease"; print_status "$1" ;;
  list) [[ $# -eq 0 ]] || die "list takes no arguments"; list_leases ;;
  artifacts) [[ $# -eq 1 ]] || die "artifacts requires lease"; collect_artifacts "$1" ;;
  scenario) [[ $# -eq 2 ]] || die "scenario requires lease and name"; scenario "$1" "$2" ;;
  destroy) [[ $# -eq 1 ]] || die "destroy requires lease"; destroy_lease "$1" ;;
  cleanup) cleanup_expired "${1:-}" ;;
  *) die "unknown action: $action" ;;
esac
