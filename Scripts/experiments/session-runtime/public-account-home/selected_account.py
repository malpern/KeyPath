"""Selected public account observer; callbacks are explicit, no import effects."""
import plistlib
import re
import stat
from create_home import Refusal, require


def selected_account(name, rows, query, lstat, *, allow_missing_home=False):
    require(type(name) is str and re.fullmatch('keypathqa(?:_[0-9a-f]{8})?', name)
            and name in rows and type(rows[name]) is int, 'selected account unavailable')
    raw = query(['/usr/bin/dscl', '-plist', '.', '-read', '/Users/' + name,
                 'UniqueID', 'NFSHomeDirectory', 'RealName'], (0,))[1]
    value = plistlib.loads(raw.encode())
    def selected(key):
        values = value.get('dsAttrTypeStandard:' + key)
        require(type(values) is list and len(values) == 1 and type(values[0]) is str,
                'selected account field ambiguous')
        return values[0]
    raw_uid = selected('UniqueID')
    require(re.fullmatch('[0-9]+', raw_uid) is not None, 'selected UID unavailable')
    uid = int(raw_uid)
    require(uid == rows[name] and uid == (501 if name == 'keypathqa' else 502),
            'selected UID changed during scan')
    home = selected('NFSHomeDirectory')
    require(home == '/Users/' + name, 'selected home mismatch')
    try:
        metadata = lstat(home)
    except FileNotFoundError:
        require(allow_missing_home and name != 'keypathqa', 'selected home unavailable')
        metadata = None
    admin = query(['/usr/sbin/dseditgroup', '-o', 'checkmember', '-m', name, 'admin'],
                  (0, 1))[1].startswith('yes ')
    token = query(['/usr/sbin/sysadminctl', '-secureTokenStatus', name], (0,))
    matches = re.findall(r'Secure token is (ENABLED|DISABLED) for user '
                         + re.escape(selected('RealName')) + r'(?:\n|$)', token[1] + token[2])
    require(len(matches) == 1, 'selected token status unavailable')
    return {'account': name, 'uid': uid, 'home': home,
            'homeOwner': None if metadata is None else metadata.st_uid,
            'homeKind': 'absent' if metadata is None else
                        ('directory' if stat.S_ISDIR(metadata.st_mode) else 'other'),
            'homeSymlink': False if metadata is None else stat.S_ISLNK(metadata.st_mode),
            'realName': selected('RealName'), 'admin': admin, 'secureToken': matches[0]}
