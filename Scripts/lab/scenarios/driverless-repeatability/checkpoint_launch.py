import hashlib,json,os,shlex,sys
from pathlib import Path
r=Path(os.environ['KEYPATH_TRIAL_DIR']).resolve()
s=Path(__file__).resolve().parent
o=json.loads((r/'owned-lease.json').read_text());i=json.loads((r/'guest-identity.json').read_text())
for name,wanted in {'restart_guest.py': '1d2e5b197acce3a5db8e0c8aa3e2c74fd7d05d4fc0b0915e425044370fd3334e', 'caps_guest.py': '6049fa473406f5e4a7a59afe5854e9e197987f567010a9314209d5fd3a8c614b', 'guest_command.py': '5c347d1329d9a4863091c54aa9e4dfbed12ec624319146f1ff81206f715c87f4'}.items():
 assert hashlib.sha256((s/name).read_bytes()).hexdigest()==wanted
base=(s/'restart_guest.py').read_text().split("\nif __name__ == '__main__':\n")[0]
caps=(s/'caps_guest.py').read_text().split("\nif __name__ == '__main__':\n")[0]
extension=r"""
CRASH_ENV='KEYPATH_EXPERIMENTAL_CAPS_TERMINATE_AFTER_JOINED_APPLY'
BOOT,CUTOFF,ACTION=int(sys.argv[1]),int(sys.argv[2]),'launch'
DATA=json.loads(sys.argv[3],object_pairs_hook=unique)
guard();stopped();selected=selected_device()
require(read(PROFILE)==CAPS,'Caps profile required')
require(all(not value for value in env_values().values()),'existing selection refused')
require(command(['/bin/launchctl','getenv',CRASH_ENV]).rstrip('\n')=='','existing crash opt-in refused')
snapshot=mapping(selected)
require(snapshot['mappings']==[],'pristine selected mapping required')
guard();stopped();selected_device()
command(['/bin/launchctl','setenv',CRASH_ENV,str(selected['registryEntryID'])])
require(command(['/bin/launchctl','getenv',CRASH_ENV]).rstrip('\n')==str(selected['registryEntryID']),'crash environment verification failed')
print(json.dumps(main(),sort_keys=True),flush=True)
"""
assert len(sys.argv) in (3,4) and (len(sys.argv)==3 or sys.argv[3]=='--queued-writer')
if len(sys.argv)==4:
 extension=extension.replace('KEYPATH_EXPERIMENTAL_CAPS_TERMINATE_AFTER_JOINED_APPLY','KEYPATH_EXPERIMENTAL_CAPS_TERMINATE_WITH_QUEUED_WRITER')
 extension=extension.replace("guard();stopped();selected=selected_device()", "require(command(['/bin/launchctl','getenv','KEYPATH_EXPERIMENTAL_CAPS_TERMINATE_AFTER_JOINED_APPLY']).rstrip('\\n')=='','joined checkpoint must be unset')\n"+"guard();stopped();selected=selected_device()")
source=base+'\n'+caps+'\n'+extension
compile(source,'<checkpoint-guest>','exec')
from guest_command import execute
args=['/bin/launchctl','asuser','502','/usr/bin/sudo','-H','-u',i['account'],'/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13','-I','-B','-c',source,str(i['bootEpoch']),str(o['hardCutoffEpoch']),sys.argv[2]]
print(execute(sys.argv[1],'exec '+shlex.join(args)))
