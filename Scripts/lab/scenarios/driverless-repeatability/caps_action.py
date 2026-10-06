"""Same owned guest-command route as action.py, with a trial-only Caps extension.

Usage: python3 -B caps_action.py UNIQUE_LABEL ACTION [DEVICE_JSON]
Actions: profile; launch DEVICE_JSON; observe DEVICE_JSON; inspect;
target; retire-target TARGET_BINDING_JSON; cleanup DEVICE_JSON; restore.
No operation runs on import. Existing intent/result O_EXCL prevents replay.
"""
import hashlib
import json
import os
import shlex
import sys
from pathlib import Path


def main():
    root = Path(os.environ['KEYPATH_TRIAL_DIR']).resolve()
    source_root = Path(__file__).resolve().parent
    base = (source_root / 'restart_guest.py').read_bytes()
    assert hashlib.sha256(base).hexdigest() == 'bd77ea3723b69dbe81033933b67b6f6aa86773e37d661112368a37ceac8addef'
    route = (source_root / 'guest_command.py').read_bytes()
    assert hashlib.sha256(route).hexdigest() == '5c347d1329d9a4863091c54aa9e4dfbed12ec624319146f1ff81206f715c87f4'
    owned = json.loads((root / 'owned-lease.json').read_text())
    identity = json.loads((root / 'guest-identity.json').read_text())
    assert identity['account'] == 'keypathqa_438d6abc' and identity['uid'] == 502
    assert identity['home'] == '/Users/keypathqa_438d6abc'
    assert identity['lease'] == owned['lease'] and identity['providerUUID'] == owned['provider']
    assert hashlib.sha256((source_root / 'caps_guest.py').read_bytes()).hexdigest() == '6049fa473406f5e4a7a59afe5854e9e197987f567010a9314209d5fd3a8c614b'
    marker = "\nif __name__ == '__main__':\n"
    assert base.decode().count(marker) == 1
    source = base.decode().split(marker)[0] + '\n' + (source_root / 'caps_guest.py').read_text()
    assert len(sys.argv) in (3, 4)
    compile(source, '<caps-guest>', 'exec')
    args = ['/bin/launchctl', 'asuser', '502', '/usr/bin/sudo', '-H', '-u', identity['account'],
            '/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13', '-I', '-B',
            '-c', source, str(identity['bootEpoch']), str(owned['hardCutoffEpoch']), *sys.argv[2:]]
    # Import only after confirming the existing transport is unchanged.
    from guest_command import execute
    result = json.loads(execute(sys.argv[1], 'exec ' + shlex.join(args)))
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()
