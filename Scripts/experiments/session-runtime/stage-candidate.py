#!/usr/bin/env python3
"""Upload a signed candidate only into a current owned disposable guest."""
import hashlib,importlib.machinery,json,os,pathlib,re,shlex,subprocess,sys,uuid
RIG=pathlib.Path('/private/tmp/vm-lab-hid-rig');pilot=importlib.machinery.SourceFileLoader('stage_pilot',str(RIG/'rig/physical-baseline.py')).load_module()
lease=sys.argv[1];archive=pathlib.Path(sys.argv[2]).resolve()
if not re.fullmatch('cbx_[0-9a-f]{12}',lease) or not archive.is_file():raise RuntimeError('invalid candidate')
digest=hashlib.sha256(archive.read_bytes()).hexdigest();upload='/tmp/keypath-session-'+uuid.uuid4().hex+'.zip';guest='/Users/keypathqa/keypath-session-update.zip'
manifest='/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/leases/'+lease+'/manifest.tsv'
def remote(script):
 result=subprocess.run(['ssh','-o','BatchMode=yes',pilot.HOST,script],capture_output=True,text=True,timeout=120)
 if result.returncode:raise RuntimeError('owned candidate transport failed; diagnostics suppressed')
 return result.stdout
subprocess.run(['scp','-q',str(archive),pilot.HOST+':'+upload],check=True,timeout=120)
try:
 script='set -e; m='+shlex.quote(manifest)+'; '
 for key,value in [('owner','keypath-installer-lab-v1'),('status','ready'),('provider','parallels')]:
  script+='test "$(awk -F \'\\t\' \'$1=="'+key+'"{print $2}\' "$m")" = '+shlex.quote(value)+'; '
 script+='test "$(awk -F \'\\t\' \'$1=="expires_epoch"{print $2}\' "$m")" -gt "$(date +%s)"; '
 script+='test "$(shasum -a 256 '+upload+' | cut -d " " -f 1)" = '+digest+'; '
 script+='r=$(awk -F \'\\t\' \'$1=="provider_resource"{print $2}\' "$m"); '
 script+='ip=$("/Applications/Parallels Desktop.app/Contents/MacOS/prlctl" list -i -f -j "$r" | /opt/homebrew/bin/python3 -c '+shlex.quote('import json,sys;rows=json.load(sys.stdin);print(next(x["ip"] for x in rows[0]["Network"]["ipAddresses"] if x.get("type")=="ipv4"))')+'); '
 script+='k="$HOME/Library/Application Support/crabbox/testboxes/'+lease+'/id_ed25519"; h="$HOME/Library/Application Support/crabbox/testboxes/'+lease+'/known_hosts"; test -f "$k" && test ! -L "$k" && test -O "$k"; test -f "$h" && test ! -L "$h" && test -O "$h"; '
 script+=r'h=${h// /\\ }; '
 script+='scp -q -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$h" -i "$k" '+upload+' "keypathqa@$ip:'+guest+'"'
 remote(script)
 command='true; set -e; test "$(shasum -a 256 '+guest+' | cut -d " " -f 1)" = '+digest+'; '
 command+='test -z "$(pgrep -u 501 -x KeyPath || true)"; mkdir -p /Users/keypathqa/keypath-session-stage; ditto -x -k '+guest+' /Users/keypathqa/keypath-session-stage; '
 command+='codesign --verify --deep --strict /Users/keypathqa/keypath-session-stage/KeyPath.app; test "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" /Users/keypathqa/keypath-session-stage/KeyPath.app/Contents/Info.plist)" = com.keypath.KeyPath; '
 command+='rm -rf /Users/keypathqa/Applications/KeyPath.app; ditto /Users/keypathqa/keypath-session-stage/KeyPath.app /Users/keypathqa/Applications/KeyPath.app; chown -R keypathqa:staff /Users/keypathqa/Applications/KeyPath.app; codesign --verify --deep --strict /Users/keypathqa/Applications/KeyPath.app; rm -rf /Users/keypathqa/keypath-session-stage; rm -f '+guest+'; echo CANDIDATE_STAGED'
 result=pilot.lab(lease,'guest-root','--','/bin/zsh','-lc',command)
 if 'CANDIDATE_STAGED' not in result:raise RuntimeError('candidate verification failed')
 print(json.dumps({'staged':True,'lease':lease,'archiveSHA256':digest,'guestResigned':False}))
finally:remote('rm -f '+upload)
