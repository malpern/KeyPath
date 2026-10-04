"""Explicit disposable guest identity, verified from independent OS observations."""
from __future__ import annotations
from dataclasses import dataclass
import json
import os
import pathlib
import stat
import uuid
import re
import shlex
import hashlib
import time

@dataclass(frozen=True)
class GuestIdentity:
    account: str = 'keypathqa'
    uid: int = 501
    lease: str | None = None
    provider_uuid: str | None = None
    boot_epoch: int | None = None
    receipt_path: str | None = None
    receipt_sha256: str | None = None

    def __post_init__(self):
        if not isinstance(self.account, str) or not re.fullmatch(r'keypathqa(?:_[a-f0-9]{8})?', self.account):
            raise ValueError('unsupported disposable guest account')
        if type(self.uid) is not int or not 501 <= self.uid <= 599:
            raise ValueError('invalid disposable guest UID')
        if self.account == 'keypathqa' and self.uid != 501:
            raise ValueError('canonical QA identity changed')
        declared = (self.lease, self.provider_uuid, self.boot_epoch)
        if any(value is not None for value in declared):
            if not isinstance(self.lease, str) or not re.fullmatch(r'cbx_[a-f0-9]{12}', self.lease):
                raise ValueError('invalid declared owned lease')
            try:
                valid_uuid = isinstance(self.provider_uuid, str) and str(uuid.UUID(self.provider_uuid)) == self.provider_uuid.lower()
            except (ValueError, AttributeError):
                valid_uuid = False
            if not valid_uuid:
                raise ValueError('invalid provider UUID')
            if type(self.boot_epoch) is not int or self.boot_epoch <= 0:
                raise ValueError('invalid boot epoch')
        if self.account != 'keypathqa':
            if not self.lease or self.account != 'keypathqa_' + self.lease[4:12] or self.uid != 502:
                raise ValueError('account is not scoped to declared lease')

    @property
    def home(self):
        return '/Users/' + self.account

    @property
    def app(self):
        return self.home + '/Applications/KeyPath.app'

    def guard(self):
        account = shlex.quote(self.account)
        command = ('test "$(id -u ' + account + ')" = ' + str(self.uid) +
                ' && test "$(dscl . -read /Users/' + account +
                ' NFSHomeDirectory | cut -d " " -f 2-)" = ' + shlex.quote(self.home) +
                ' && test "$(stat -f %Su /dev/console)" = ' + account +
                ' && test "$(stat -f %u /dev/console)" = ' + str(self.uid))
        if self.boot_epoch is not None:
            command += ' && test "$(sysctl -n kern.boottime | sed -E \'s/^.*sec = ([0-9]+),.*$/\\1/\')" = ' + str(self.boot_epoch)
        return command

    def verify(self, pilot, lease):
        if self.lease is not None and lease != self.lease:
            raise RuntimeError('guest identity receipt belongs to another lease')
        if self.receipt_path:
            raw = read_private_receipt(pathlib.Path(self.receipt_path))
            if hashlib.sha256(raw).hexdigest() != self.receipt_sha256:
                raise RuntimeError('frozen identity receipt changed')
        if self.provider_uuid is not None:
            verify_provider(pilot.lab(lease, 'status'), lease, self.provider_uuid, time.time())
        result = pilot.observe(lease, 'guest-root', '--', '/bin/zsh', '-lc',
                               self.guard() + ' && printf KEYPATH_GUEST_IDENTITY_VERIFIED')
        if result.strip() != 'KEYPATH_GUEST_IDENTITY_VERIFIED':
            raise RuntimeError('guest account/home/UID/console identity mismatch')
        return {'account': self.account, 'uid': self.uid, 'home': self.home,
                'lease': self.lease, 'providerUUID': self.provider_uuid, 'bootEpoch': self.boot_epoch}


def add_arguments(parser):
    parser.add_argument('--guest-account')
    parser.add_argument('--guest-uid', type=int)
    parser.add_argument('--guest-identity-receipt',default=os.environ.get('KEYPATH_GUEST_IDENTITY_RECEIPT'))


def from_arguments(args):
    if (args.guest_account is None) != (args.guest_uid is None):
        raise ValueError('guest account and UID must be declared together')
    if args.guest_identity_receipt:
        path=pathlib.Path(args.guest_identity_receipt)
        raw = read_private_receipt(path)
        value = json.loads(raw, object_pairs_hook=unique_keys)
        if not isinstance(value, dict) or set(value) != {'version','lease','providerUUID','account','uid','home','bootEpoch'} or type(value['version']) is not int or value['version'] != 1:
            raise ValueError('invalid identity receipt schema')
        identity=GuestIdentity(value['account'],value['uid'],value['lease'],value['providerUUID'],value['bootEpoch'],str(path),hashlib.sha256(raw).hexdigest())
        if any(value[key] is None for key in ('lease', 'providerUUID', 'bootEpoch')):
            raise ValueError('identity receipt requires complete provenance')
        if value['home'] != identity.home or (args.guest_account is not None and (args.guest_account,args.guest_uid) != (identity.account,identity.uid)):
            raise ValueError('identity receipt tuple mismatch')
        os.environ['KEYPATH_GUEST_IDENTITY_RECEIPT']=str(path)
        return identity
    return GuestIdentity() if args.guest_account is None else GuestIdentity(args.guest_account,args.guest_uid)


def unique_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate identity receipt key')
        result[key] = value
    return result


def read_private_receipt(path):
    if not path.is_absolute():
        raise ValueError('identity receipt must be absolute')
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        raise ValueError('identity receipt unavailable or linked') from None
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid() or before.st_nlink != 1 or stat.S_IMODE(before.st_mode) != 0o600 or not 0 < before.st_size <= 4096:
            raise ValueError('identity receipt must be an owned private regular file')
        raw = os.read(fd, 4097)
        after = os.fstat(fd)
        current = path.lstat()
        metadata = lambda s: (s.st_dev, s.st_ino, s.st_mode, s.st_uid, s.st_gid, s.st_nlink, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
        if metadata(before) != metadata(after) or metadata(after) != metadata(current) or len(raw) != before.st_size:
            raise ValueError('identity receipt changed while reading')
        return raw
    finally:
        os.close(fd)


def verify_provider(output, lease, provider_uuid, now):
    # vm-lab status emits the owned manifest followed by an explicitly bounded
    # inventory section. Only manifest TSV fields establish routing identity.
    header = output.split('provider_inventory_begin', 1)[0]
    fields = {}
    for line in header.splitlines():
        if '\t' not in line:
            raise RuntimeError('malformed owned lease status')
        key, value = line.split('\t', 1)
        if key in fields:
            raise RuntimeError('duplicate owned lease status field')
        fields[key] = value
    expected = {'lease_id': lease, 'owner': 'keypath-installer-lab-v1',
                'status': 'ready', 'provider': 'parallels'}
    if any(fields.get(key) != value for key, value in expected.items()):
        raise RuntimeError('owned lease provider identity mismatch')
    try:
        resource = str(uuid.UUID(fields['provider_resource']))
        expires = int(fields['expires_epoch'])
    except (KeyError, ValueError):
        raise RuntimeError('owned lease provider evidence unavailable') from None
    if resource != provider_uuid.lower() or expires <= now:
        raise RuntimeError('owned lease provider changed or expired')
