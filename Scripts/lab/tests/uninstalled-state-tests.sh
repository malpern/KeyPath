#!/bin/zsh
set -euo pipefail

repo=$(cd "$(dirname "$0")/../../.." >/dev/null && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/root" "$tmp/home/.config/keypath" "$tmp/bin"
print -n 'preserve-me' > "$tmp/home/.config/keypath/lab-sentinel"
expected=$(shasum -a 256 "$tmp/home/.config/keypath/lab-sentinel" | awk '{print $1}')

cat > "$tmp/bin/launchctl" <<'EOF'
#!/bin/zsh
exit 113
EOF
cat > "$tmp/bin/pgrep" <<'EOF'
#!/bin/zsh
exit 1
EOF
cat > "$tmp/bin/systemextensionsctl" <<'EOF'
#!/bin/zsh
print '* * G43BCU2T37 org.pqrs.Karabiner-DriverKit-VirtualHIDDevice [activated enabled]'
EOF
chmod +x "$tmp/bin/"*

base_env=(
  KEYPATH_LAB_ROOT="$tmp/root"
  KEYPATH_LAB_HOME="$tmp/home"
  KEYPATH_LAB_LAUNCHCTL="$tmp/bin/launchctl"
  KEYPATH_LAB_PGREP="$tmp/bin/pgrep"
  KEYPATH_LAB_SYSTEMEXTENSIONSCTL="$tmp/bin/systemextensionsctl"
)

env $base_env "$repo/Scripts/lab/assert-uninstalled-state" \
  --preserved-config "$tmp/home/.config/keypath/lab-sentinel" \
  --expected-sha256 "$expected"

mkdir -p "$tmp/root/Applications/KeyPath.app"
if env $base_env "$repo/Scripts/lab/assert-uninstalled-state" \
  --preserved-config "$tmp/home/.config/keypath/lab-sentinel" \
  --expected-sha256 "$expected" >/dev/null 2>&1; then
  print -u2 "remaining KeyPath app incorrectly passed uninstall assertion"
  exit 1
fi
rmdir "$tmp/root/Applications/KeyPath.app"

print -n 'changed' > "$tmp/home/.config/keypath/lab-sentinel"
if env $base_env "$repo/Scripts/lab/assert-uninstalled-state" \
  --preserved-config "$tmp/home/.config/keypath/lab-sentinel" \
  --expected-sha256 "$expected" >/dev/null 2>&1; then
  print -u2 "changed configuration incorrectly passed uninstall assertion"
  exit 1
fi

print "uninstalled-state tests passed"
