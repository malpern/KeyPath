#!/usr/bin/env python3
"""Bounded experiment controller. Never creates/adopts provider VMs directly."""
import argparse, base64, json, pathlib, re, shlex, subprocess, sys

p = argparse.ArgumentParser()
p.add_argument("lease")
p.add_argument("action", choices=["run", "upload", "root", "key", "key-json", "key-release", "key-press", "chord", "hrm-hold", "read", "secure"])
p.add_argument("args", nargs="*")
p.add_argument("--log", default="last-run.log")
a = p.parse_args()
if not re.fullmatch(r"cbx_[0-9a-f]{12}", a.lease): p.error("invalid lease")
prefix = ["vm-lab", "--host", "mini", "keypath"]
stdin_payload = None
if a.action == "upload":
    src, dest = a.args
    payload = base64.b64encode(pathlib.Path(src).read_bytes()).decode()
    command = "printf %s " + shlex.quote(payload) + " | base64 -D > /tmp/permission-upload.zip; ditto -x -k /tmp/permission-upload.zip " + shlex.quote(dest)
    cmd = prefix + ["run", a.lease, "--", "/bin/zsh", "-lc", command]
elif a.action in ["root", "key", "key-json", "key-release", "key-press", "chord", "hrm-hold"]:
    # Existing authorized Parallels guest-control channel, gated on this owned lease.
    manifest = "/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/leases/" + a.lease + "/manifest.tsv"
    script = "set -e; m=" + shlex.quote(manifest) + "; "
    script += "test \"$(awk -F '\\t' '$1==\"owner\"{print $2}' \"$m\")\" = keypath-installer-lab-v1; "
    script += "test \"$(awk -F '\\t' '$1==\"status\"{print $2}' \"$m\")\" = ready; "
    script += "test \"$(awk -F '\\t' '$1==\"provider\"{print $2}' \"$m\")\" = parallels; "
    script += "r=$(awk -F '\\t' '$1==\"provider_resource\"{print $2}' \"$m\"); "
    prl = '"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"'
    if a.action == "root":
        script += prl + ' exec "$r" /bin/zsh -lc ' + shlex.quote("true; " + a.args[0])
    elif a.action == "hrm-hold":
        script += "trap '" + prl + ' send-key-event "$r" --key 24 --event release >/dev/null' + "' EXIT; "
        script += prl + ' send-key-event "$r" --key 24 --event press; sleep .35; '
        script += prl + ' send-key-event "$r" --key 38 --event press; '
        script += prl + ' send-key-event "$r" --key 38 --event release; '
        script += prl + ' send-key-event "$r" --key 24 --event release; trap - EXIT; '
    else:
        for key in a.args:
            if not key.isdigit(): p.error("numeric native keycode required")
            if a.action == "key-json":
                script += "printf '%s\\n' " + shlex.quote(json.dumps([{"key":int(key)}])) + ' | ' + prl + ' send-key-event "$r" --json; '
            else:
                if a.action in ('key-release', 'key-press', 'chord'):
                    script += prl + ' send-key-event "$r" --key ' + key + (' --event release; ' if a.action == 'key-release' else ' --event press; ')
                else:
                    script += prl + ' send-key-event "$r" --key ' + key + ' --event press; '
                    script += prl + ' send-key-event "$r" --key ' + key + ' --event release; '
        if a.action == 'chord':
            for key in reversed(a.args):
                script += prl + ' send-key-event "$r" --key ' + key + ' --event release; '
    cmd = ["ssh", "-o", "BatchMode=yes", "mini", script]
elif a.action == "secure":
    cmd = prefix + ["secure-dialog-input", a.lease] + a.args
else:
    command = a.args[0] if a.action == "run" else "cat " + shlex.quote(a.args[0])
    cmd = prefix + ["run", a.lease, "--", "/bin/zsh", "-lc", command]
# Current lab remote.sh assigns this variable only in its testing branch.
# After provisioning the guest administrator, `run` trips nounset. Execute the
# same ownership-guarded lab run handler with the missing non-secret default;
# no installed lab/host file is changed, and VM admission is never bypassed.
if a.action in ("run", "read", "upload"):
    remote = pathlib.Path.home() / "local-code/vm-lab/lib/remote.sh"
    stdin_payload = "LAB_GUEST_SSH_USER=keypathqa\n" + remote.read_text()
    remote_args = ["run", a.lease, "/bin/zsh", "-lc", command]
    cmd = ["ssh", "-o", "BatchMode=yes", "mini", "/bin/zsh -s -- " + shlex.join(remote_args)]
elif a.action == "secure":
    p.error("Credential entry disabled after a late focus failure; see permission-exploration-results.md. No credential is loaded.")

try:
    r = subprocess.run(cmd, input=stdin_payload, capture_output=True, text=True, timeout=60)
except subprocess.TimeoutExpired as e:
    pathlib.Path(a.log).write_bytes((e.stdout or b"") + (e.stderr or b""))
    print("timeout; evidence:", a.log); sys.exit(124)
pathlib.Path(a.log).write_text(r.stdout + r.stderr)
print("exit", r.returncode, "evidence", a.log)
if a.action in ("read", "key"):
    print((r.stdout + r.stderr)[-6500:])
else:
    # UI text only, omit huge controller command echoes such as binary uploads.
    text = r.stdout
    print("\n".join(line for line in text.splitlines() if line.startswith(("IDENTITY", "START", "END", "HID", "TAP", "ENGINE", "TARGET", "OUTPUT", "INPUT", "SECURE", "RECOVERY"))))
    for match in re.finditer(r'^\{\n', text, re.M):
        try:
            data, _ = json.JSONDecoder().raw_decode(text[match.start():])
            if "data" in data:
                d = data["data"]
                ui = d.get("text") or "\n".join(c.get("text", "") for c in d.get("content", []))
                print("\n".join(line for line in ui.splitlines() if any(x in line for x in ["Window:", "checkbox", "Toggle", "Password", "Modify", "Allow", "Open System", "button (", "Cancel", "Add\"", "Open\"", "Quit", "secure", "Go to", "textField", "elem_"]) and not any(x in line for x in ["outline row", "cell\"", "group\"", "column", "scroll", "Apple", "Sidebar", "outline", "page button"]))[:3500])
        except (ValueError, TypeError): pass
sys.exit(r.returncode)
