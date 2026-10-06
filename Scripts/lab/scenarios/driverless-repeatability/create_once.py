"""One-shot source launcher for the reviewed prepared CREATE SDK route for integrated Caps product acceptance.

This file is intentionally not a generic vm-lab wrapper. It binds one exact
artifact, tenant, CLI/source revision, provider executable, Mac 26 unmanaged-ui
desktop route, template, and 1h TTL. Importing it never dispatches anything.
"""
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import time

ROOT = Path(os.environ['KEYPATH_TRIAL_DIR']).resolve()
LAB = Path('/private/tmp/vm-lab-reusable-setup')
TENANT_PROJECT = Path('/private/tmp/keypath-tap-timeout-hook-build')
ARTIFACT_DIR = Path('/private/tmp/keypath-queued-writer-408099759-artifact')
ARTIFACT_MANIFEST = ARTIFACT_DIR / 'artifact-manifest.json'
ARTIFACT_ZIP = ARTIFACT_DIR / 'keypath-queued-writer-clean.zip'
PROVIDER_BINARY = Path('/private/tmp/keypath-create-posix-sdk-build-ada4b9f/crabbox-create-posix-sdk')
REGISTRY = ROOT / 'tenants.tsv'

LAB_COMMIT = 'f2d3b6594284e5b14f48b0c8e49a68e50d9ed935'
PRODUCT_COMMIT = '40809975962922f852c4729f2dced76eb7e47dd8'
ARTIFACT_MANIFEST_SHA256 = 'e61c13e38116032a1465d66b12aa88a64272a6277e191c7a412954ce02d33eb0'
ARTIFACT_ZIP_SHA256 = '7ad23b3666b1907eab43f53253758f0b339401c213a53a53649e8def695d0d28'
ARTIFACT_ZIP_SIZE = 97901564
PACKAGED_MAIN_SIZE = 107946096
PACKAGED_MAIN_SHA256 = 'b615f21e368e77693cf7da07c0e7aeca0cef24eb7bea9a7640ab654e21b36420'
PRODUCT_DESCRIPTOR_SHA256 = 'e19ba4ee0e850b52e6eef498b5c1ca5eadeb157c7f90eead78d76078df4218d9'
REGISTRY_SHA256 = '905907bda0d8c302839ea416f2fb9456a04d6159536c901e1372210782721c5e'
CLI_SHA256 = 'f8470518428f75590e7ea6f481a6a544f40745f4a881039b9d4ed884231cdc03'
REMOTE_SHA256 = '9e5b849322f5beffe2513f69c9ace8a4dfbe1d8d6c3cd3877a2d804186a33a24'
HELPER_SHA256 = '564dbf43cfe8e338dcb072bfa086608a64713551a70d6ed6e31cc16b2d6ab144'
PROVIDER_SHA256 = 'fd2671373f626f8e762559f6e58c06b04277f32ac02db670d41b4803be63a179'
PROVIDER_SIZE = 143390034
TEMPLATE = 'keypath-macos-26-runtime-v1-7285826ed9f6'
HOST = 'malpern@mini'
TENANT = 'keypath'
TTL = '1h'
CREATE_TIMEOUT_SECONDS = 480

SOURCE_PINS = {
    LAB / 'bin/vm-lab': CLI_SHA256,
    LAB / 'lib/remote.sh': REMOTE_SHA256,
    LAB / 'lib/create-posix-sdk.py': HELPER_SHA256,
    TENANT_PROJECT / '.vm-lab.tsv': PRODUCT_DESCRIPTOR_SHA256,
}


class Refused(RuntimeError):
    pass


class AlreadyClaimed(Refused):
    pass


def _sig(st):
    return (st.st_dev, st.st_ino, st.st_mode, st.st_uid, st.st_gid,
            st.st_nlink, st.st_size, st.st_mtime_ns, st.st_ctime_ns)


def _hash_regular(path, expected, *, size=None, mode=None, uid=None, limit=200_000_000,
                  capture=False):
    """Hash one bounded regular file through a no-follow fd and recheck path identity."""
    path = Path(path)
    before_path = path.lstat()
    if not stat.S_ISREG(before_path.st_mode) or before_path.st_nlink != 1:
        raise Refused('pinned input must be a singly-linked regular file: ' + str(path))
    if size is not None and before_path.st_size != size:
        raise Refused('pinned input size changed: ' + str(path))
    if before_path.st_size <= 0 or before_path.st_size > limit:
        raise Refused('pinned input size outside bound: ' + str(path))
    if mode is not None and stat.S_IMODE(before_path.st_mode) != mode:
        raise Refused('pinned input mode changed: ' + str(path))
    if uid is not None and before_path.st_uid != uid:
        raise Refused('pinned input owner changed: ' + str(path))
    fd = os.open(str(path), os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) |
                 getattr(os, 'O_NONBLOCK', 0))
    try:
        before_fd = os.fstat(fd)
        if _sig(before_path) != _sig(before_fd):
            raise Refused('pinned input changed while opening: ' + str(path))
        digest = hashlib.sha256()
        chunks = []
        count = 0
        while True:
            block = os.read(fd, 1024 * 1024)
            if not block:
                break
            count += len(block)
            if count > limit:
                raise Refused('pinned input exceeded read bound: ' + str(path))
            digest.update(block)
            if capture:
                chunks.append(block)
        after_fd = os.fstat(fd)
        after_path = path.lstat()
        if count != before_fd.st_size or _sig(before_fd) != _sig(after_fd) or _sig(after_fd) != _sig(after_path):
            raise Refused('pinned input changed while hashing: ' + str(path))
    finally:
        os.close(fd)
    actual = digest.hexdigest()
    if actual != expected:
        raise Refused('pinned input SHA-256 changed: ' + str(path))
    return b''.join(chunks) if capture else actual


def _assert_private_state_dir(root):
    root = Path(root)
    st = root.lstat()
    if not stat.S_ISDIR(st.st_mode) or stat.S_ISLNK(st.st_mode):
        raise Refused('state root must be a real directory')
    if st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) != 0o700:
        raise Refused('state root owner/mode refused')


def _git_head(path):
    result = subprocess.run(['git', '-C', str(path), 'rev-parse', 'HEAD'],
                            capture_output=True, text=True, timeout=5, check=False)
    if result.returncode != 0:
        raise Refused('source checkout head unavailable')
    return result.stdout.strip()


def verify_inputs():
    """Verify all fixed source, tenant, artifact, and executable authorities."""
    if _git_head(LAB) != LAB_COMMIT:
        raise Refused('canonical lab commit changed')
    if _git_head(TENANT_PROJECT) != '40809975962922f852c4729f2dced76eb7e47dd8':
        raise Refused('reviewed documentation-only checkout revision changed')
    for path, expected in SOURCE_PINS.items():
        _hash_regular(path, expected)
    registry_raw = _hash_regular(REGISTRY, REGISTRY_SHA256, mode=0o600,
                                 uid=os.getuid(), limit=4096, capture=True)
    registry_text = registry_raw.decode('utf-8')
    if registry_text != 'keypath\t/private/tmp/keypath-tap-timeout-hook-build\n':
        raise Refused('tenant registry route changed')
    manifest_raw = _hash_regular(ARTIFACT_MANIFEST, ARTIFACT_MANIFEST_SHA256,
                                 limit=1_000_000, capture=True)
    manifest = json.loads(manifest_raw.decode('utf-8'))
    if manifest.get('sourceCommit') != PRODUCT_COMMIT or \
            manifest.get('packagedMainSHA256') != PACKAGED_MAIN_SHA256 or \
            (ARTIFACT_DIR / 'KeyPath.app/Contents/MacOS/KeyPath').stat().st_size != PACKAGED_MAIN_SIZE or \
            manifest.get('archiveSHA256') != ARTIFACT_ZIP_SHA256 or \
            manifest.get('archiveSizeBytes') != ARTIFACT_ZIP_SIZE:
        raise Refused('current artifact manifest fields changed')
    _hash_regular(ARTIFACT_ZIP, ARTIFACT_ZIP_SHA256, size=ARTIFACT_ZIP_SIZE)
    _hash_regular(PROVIDER_BINARY, PROVIDER_SHA256, size=PROVIDER_SIZE,
                  mode=0o500, uid=os.getuid(), limit=160 * 1024 * 1024)
    return {
        'labCommit': LAB_COMMIT,
        'productCommit': PRODUCT_COMMIT,
        'artifactManifestSHA256': ARTIFACT_MANIFEST_SHA256,
        'artifactZipSHA256': ARTIFACT_ZIP_SHA256,
        'providerSHA256': PROVIDER_SHA256,
        'providerSize': PROVIDER_SIZE,
        'cliSHA256': CLI_SHA256,
        'remoteSHA256': REMOTE_SHA256,
        'helperSHA256': HELPER_SHA256,
        'registrySHA256': REGISTRY_SHA256,
    }


def build_invocation(base_env=None):
    """Build the single canonical CLI invocation and its exact selected env."""
    env = dict(os.environ if base_env is None else base_env)
    for key in (
        'VM_LAB_TRANSPORT_DIAGNOSTIC_NONCE',
        'KEYPATH_LAB_CLONE_ROOT',
        'KEYPATH_LAB_DISK_RESERVE_PATH',
        'KEYPATH_LAB_MIN_FREE_DISK_GIB',
        'KEYPATH_LAB_CAPACITY_PARALLELS',
        'KEYPATH_LAB_CAPACITY_TART',
        'KEYPATH_LAB_TESTING',
        'KEYPATH_LAB_CREATE_POSIX_BINARY_B64',
        'KEYPATH_LAB_CREATE_POSIX_HELPER_B64',
        'CRABBOX_EXPERIMENT_PREPARED_CREATE_POSIX_SDK',
        'CRABBOX_EXPERIMENT_PREPARED_CREATE_POSIX_SDK_HELPER',
    ):
        env.pop(key, None)
    env.update({
        'VM_LAB_REGISTRY': str(REGISTRY),
        'KEYPATH_LAB_PARALLELS_TEMPLATE_26_DESKTOP': TEMPLATE,
        'KEYPATH_LAB_CREATE_POSIX_REQUIRED': '1',
        'KEYPATH_LAB_CREATE_POSIX_BINARY_SHA256': PROVIDER_SHA256,
        'KEYPATH_LAB_CREATE_POSIX_BINARY_FILE': str(PROVIDER_BINARY),
    })
    argv = [
        str(LAB / 'bin/vm-lab'), '--host', HOST, TENANT, 'create',
        '--macos', '26', '--lane', 'unmanaged-ui', '--commit', PRODUCT_COMMIT,
        '--installer', str(ARTIFACT_ZIP), '--desktop', '--ttl', TTL,
    ]
    return argv, env


def _write_exclusive(root, name, value):
    path = Path(root) / name
    raw = (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8')
    if len(raw) > 1_000_000:
        raise Refused('journal record exceeds bound')
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                 getattr(os, 'O_NOFOLLOW', 0), 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    parent_fd = os.open(str(root), os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    try:
        os.fsync(parent_fd)
    finally:
        os.close(parent_fd)
    return path


def dispatch_once(root=ROOT, *, runner=subprocess.run, env_source=None,
                  verify=verify_inputs, clock=time.time):
    """Claim before the only subprocess call; every uncertain result stays spent."""
    root = Path(root)
    _assert_private_state_dir(root)
    source_facts = verify()
    argv, env = build_invocation(env_source)
    if argv[argv.index('--installer') + 1] != str(ARTIFACT_ZIP):
        raise Refused('selected installer path changed')
    selected_env = {key: env[key] for key in (
        'VM_LAB_REGISTRY', 'KEYPATH_LAB_PARALLELS_TEMPLATE_26_DESKTOP',
        'KEYPATH_LAB_CREATE_POSIX_REQUIRED', 'KEYPATH_LAB_CREATE_POSIX_BINARY_SHA256',
        'KEYPATH_LAB_CREATE_POSIX_BINARY_FILE')}
    claim = {
        'version': 1,
        'phase': 'fresh-caps-runtime-sdk-create-dispatch-claimed',
        'purpose': 'fresh owned Caps runtime macOS 26 unmanaged-ui desktop CREATE, 1h TTL',
        'argv': argv,
        'selectedEnvironment': selected_env,
        'sourceFacts': source_facts,
        'claimedAtEpoch': clock(),
        'runnerSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'noReplay': True,
    }
    _write_exclusive(root, 'create-claim.json', claim)
    started = time.monotonic()
    try:
        completed = runner(argv, env=env, capture_output=True, text=True,
                           timeout=CREATE_TIMEOUT_SECONDS, check=False)
        status = completed.returncode
        if type(status) is not int:
            raise Refused('canonical CLI returned a non-integer status')
        result = {
            'phase': 'fresh-caps-runtime-sdk-create-result',
            'actualStatus': status,
            'classification': 'completed',
            'stdout': completed.stdout,
            'stderr': completed.stderr,
            'elapsedSeconds': time.monotonic() - started,
            'finishedAtEpoch': clock(),
            'noReplay': True,
        }
    except subprocess.TimeoutExpired as exc:
        result = {
            'phase': 'fresh-caps-runtime-sdk-create-result',
            'actualStatus': None,
            'classification': 'completion-unknown-timeout-no-replay',
            'partialOutputPresent': bool(exc.stdout or exc.stderr),
            'elapsedSeconds': time.monotonic() - started,
            'finishedAtEpoch': clock(),
            'noReplay': True,
        }
    except Exception as exc:
        result = {
            'phase': 'fresh-caps-runtime-sdk-create-result',
            'actualStatus': None,
            'classification': 'completion-unknown-exception-no-replay',
            'exceptionClass': type(exc).__name__,
            'elapsedSeconds': time.monotonic() - started,
            'finishedAtEpoch': clock(),
            'noReplay': True,
        }
    _write_exclusive(root, 'create-result.json', result)
    return result


def main():
    if len(sys.argv) != 1:
        print('usage: launch_once.py', file=sys.stderr)
        return 64
    try:
        result = dispatch_once()
    except AlreadyClaimed as exc:
        print(str(exc), file=sys.stderr)
        return 79
    except FileExistsError:
        print('fresh CREATE already claimed; reconcile without replay', file=sys.stderr)
        return 79
    except Exception as exc:
        print('fresh CREATE refused: ' + type(exc).__name__, file=sys.stderr)
        return 79
    print(json.dumps(result, sort_keys=True))
    status = result['actualStatus']
    return status if type(status) is int and 0 <= status <= 255 else 79


if __name__ == '__main__':
    raise SystemExit(main())
