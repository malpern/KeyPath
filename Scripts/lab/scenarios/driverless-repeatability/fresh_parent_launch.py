"""One normal fresh launch after verified retained-marker owner absence."""
import hashlib, json, os, shlex
from pathlib import Path
r = Path(os.environ['KEYPATH_TRIAL_DIR']).resolve()
s = Path(__file__).resolve().parent
pins = {'restart_guest.py': '99b545c792fa9d52e26ff027abf41fea2a98f6450ee1f30ed4b50e17a97a2bfe', 'caps_guest.py': '6049fa473406f5e4a7a59afe5854e9e197987f567010a9314209d5fd3a8c614b', 'marker_observe.py': '502d7a2f301ebee38029fe1e42ee12682d9ed543d896dbeb25020d2fd3a5a72f'}
for name,digest in pins.items():
    assert hashlib.sha256((s/name).read_bytes()).hexdigest() == digest
assert hashlib.sha256((s/'guest_command.py').read_bytes()).hexdigest() == '5c347d1329d9a4863091c54aa9e4dfbed12ec624319146f1ff81206f715c87f4'
prior=json.loads(json.loads((r/'marker-stopped01-result.json').read_text())['stdout'])
assert prior['observed'] and prior['runtime']==dict(parents=[],workers=[],target=None)
b=dict(prior['scope'],expectedIntentSHA256=prior['journalRawSHA256'],expectedMarkerSHA256=prior['markerRawSHA256'])
source='\n'.join((s/name).read_text().split("\nif __name__ == '__main__':\n")[0] for name in pins)
source+='\n'+r'''
BOOT,CUTOFF=int(sys.argv[1]),int(sys.argv[2]);b=json.loads(sys.argv[3],object_pairs_hook=unique)
observed=json.loads(marker_observe(b))
require(observed['runtime']==dict(parents=[],workers=[],target=None),'original processes must be absent')
encoded=json.dumps(b['selectedDevice'],sort_keys=True,separators=(',',':'))
require(env_values()=={DEVICE_ENV:encoded,RESERVE_ENV:'1'},'selected device opt-in changed')
key='KEYPATH_EXPERIMENTAL_CAPS_TERMINATE_AFTER_JOINED_APPLY'
require(command(['/bin/launchctl','getenv',key]).strip()==str(b['selectedDevice']['registryEntryID']),'checkpoint opt-in changed')
command(['/bin/launchctl','unsetenv',key])
require(command(['/bin/launchctl','getenv',key]).strip()=='','checkpoint opt-in still present')
require(json.loads(marker_observe(b))['runtime']==dict(parents=[],workers=[],target=None),'state changed before launch')
command(['/usr/bin/open','-n',str(APP)])
print(json.dumps(dict(freshNormalLaunchRequested=True,checkpointOptInCleared=True,retainedIntentSHA256=b['expectedIntentSHA256'],retainedMarkerSHA256=b['expectedMarkerSHA256'])),flush=True)
'''
compile(source,'<fresh-parent-launch>','exec')
from guest_command import execute
args=['/bin/launchctl','asuser','502','/usr/bin/sudo','-H','-u',b['account'],'/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13','-I','-B','-c',source,str(b['bootEpoch']),str(b['hardCutoffEpoch']),json.dumps(b)]
print(execute('fresh-parent-launch01','exec '+shlex.join(args)))
