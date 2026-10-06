import hashlib,json,os,shlex,sys
from pathlib import Path
r=Path(os.environ['KEYPATH_TRIAL_DIR']).resolve();s=Path(__file__).resolve().parent;o=json.loads((r/'owned-lease.json').read_text());i=json.loads((r/'guest-identity.json').read_text())
assert hashlib.sha256((s/'restart_guest.py').read_bytes()).hexdigest()=='bd77ea3723b69dbe81033933b67b6f6aa86773e37d661112368a37ceac8addef'
assert hashlib.sha256((s/'caps_guest.py').read_bytes()).hexdigest()=='6049fa473406f5e4a7a59afe5854e9e197987f567010a9314209d5fd3a8c614b'
assert hashlib.sha256((s/'marker_observe.py').read_bytes()).hexdigest()=='502d7a2f301ebee38029fe1e42ee12682d9ed543d896dbeb25020d2fd3a5a72f'
assert hashlib.sha256((s/'guest_command.py').read_bytes()).hexdigest()=='5c347d1329d9a4863091c54aa9e4dfbed12ec624319146f1ff81206f715c87f4'
b=dict(lease=o['lease'],providerUUID=o['provider'],account=i['account'],home=i['home'],uid=502,bootEpoch=i['bootEpoch'],hardCutoffEpoch=o['hardCutoffEpoch'],selectedDevice=json.loads(sys.argv[2]),expectedIntentSHA256=None,expectedMarkerSHA256=None)
assert len(sys.argv) in (3,4,5)
if len(sys.argv)>=4:
 old=json.loads(json.loads((r/(sys.argv[3]+'-result.json')).read_text())['stdout']);assert old['observed'] is True
 b.update(expectedIntentSHA256=old['journalRawSHA256'],expectedMarkerSHA256=old['markerRawSHA256'])
if len(sys.argv)==5:b['replacementParentPID']=int(sys.argv[4])
source='\n'.join((s/name).read_text().split("\nif __name__ == '__main__':\n")[0] for name in ('restart_guest.py','caps_guest.py'))+'\n'+(s/'marker_observe.py').read_text()
compile(source,'<marker-observation>','exec')
from guest_command import execute
args=['/bin/launchctl','asuser','502','/usr/bin/sudo','-H','-u',i['account'],'/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13','-I','-B','-c',source,str(i['bootEpoch']),str(o['hardCutoffEpoch']),json.dumps(b)]
v=json.loads(execute(sys.argv[1],'exec '+shlex.join(args)))
print(json.dumps({k:v[k] for k in ('observed','selectedDevice','matchesApplied','journalRawSHA256','markerRawSHA256','recordedWorkerPIDAbsent','runtime')},sort_keys=True))
