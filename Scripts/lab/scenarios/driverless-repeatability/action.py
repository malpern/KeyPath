import os
import json,shlex,sys
from pathlib import Path
from guest_command import execute
R=Path(os.environ['KEYPATH_TRIAL_DIR']).resolve()
o=json.loads((R/'owned-lease.json').read_text());i=json.loads((R/'guest-identity.json').read_text())
source=(Path(__file__).resolve().parent/'restart_guest.py').read_text();compile(source,'<actual-runtime-command>','exec')
a=['/bin/launchctl','asuser','502','/usr/bin/sudo','-H','-u',i['account'],'/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13','-I','-B','-c',source,str(i['bootEpoch']),str(o['hardCutoffEpoch']),*sys.argv[2:]]
v=json.loads(execute(sys.argv[1],'exec '+shlex.join(a)))
if isinstance(v.get('target'),dict):
 v['target']={k:v['target'].get(k)for k in ('pid','uid','nonce','text','downs','ups','held','modifiers','active','focusLost')}
print(json.dumps(v))
