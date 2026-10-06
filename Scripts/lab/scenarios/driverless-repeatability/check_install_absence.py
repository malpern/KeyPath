import os
import shlex
from guest_command import execute
body="import json,os;from pathlib import Path;h=Path('/Users/keypathqa_438d6abc');assert os.getuid()==502 and os.stat('/dev/console').st_uid==502;a=h/'Applications';print(json.dumps(dict(destinationsAbsent=all(not p.exists() and not p.is_symlink() for p in [a/'KeyPath.app',a/'VM Lab Rig Target.app',a/'secure-focus']),stagingPaths=[str(p) for p in (h/'.local/share/vm-lab').glob('.keypath-artifacts-*')])))"
cmd='/bin/launchctl asuser 502 /usr/bin/sudo -H -u keypathqa_438d6abc /Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13 -I -B -c '+shlex.quote(body)
print(execute('install-absence02',cmd))
