import os
import json,shlex,sys
from guest_command import execute
if len(sys.argv)>2 and sys.argv[2]=='perform-action' and ('--app' in sys.argv[3:] or '--snapshot' in sys.argv[3:]):raise RuntimeError('unsupported perform-action targeting options')
prefix=['/bin/launchctl','asuser','502','/usr/bin/sudo','-H','-u','keypathqa_438d6abc','/Users/keypathqa_438d6abc/.local/share/vm-lab/peekaboo-3.10.0/peekaboo-macos-universal/peekaboo']
v=json.loads(execute(sys.argv[1],'exec '+shlex.join(prefix+sys.argv[2:]+['--json'])))
print(v.get('data',{}).get('text',json.dumps(v)))
