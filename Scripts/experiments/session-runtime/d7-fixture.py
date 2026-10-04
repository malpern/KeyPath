"""D7 adapter derived from reviewed factory SHA256 78d188b220934cfaf6f264bb3203dbe3c7ea24d8d2ef556a55e5dd7999800f1b.

Import is inert. Explicit construction extracts only the selected fixture token
in memory; it performs no network/guest/hardware operation. Execution is gated.
"""
import hashlib
import http.client
import importlib.machinery
import importlib.util
import json
import math
import os
import pathlib
import re
import subprocess

CLIENT = pathlib.Path('/Users/malpern/local-code/keypath-pico-hid-fixture/Scripts/lab/pico-hid-fixture-client')
SOURCE_HASHES = {
    CLIENT: '91fe6b854215ffa3d26879b830e026170153e6c1a77a3ff30a8ab0e128098f11',
}
HOST = 'keypath-hid-fixture.local'
ENDPOINT = '192.168.1.221'
PORT = 8080
EXPECTED_IDENTITY = {
    'firmware': '0.3.2-esp32s3',
    'build': 'fc98a5acc0a5',
    'platform': 'waveshare-esp32-s3-touch-lcd-1.69',
    'address': ENDPOINT,
}
RUN = re.compile(r'session-[0-9a-f]{16}')


def _module(path, name):
    if hashlib.sha256(path.read_bytes()).hexdigest() != SOURCE_HASHES[path]:
        raise RuntimeError('reviewed fixture dependency changed')
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def _validate_response(value, token):
    """Inspect original strings, not JSON escaping; reject cycles/unknown objects.

    Transport responses are JSON values or raw trace strings. Limits bound work
    before anything can reach receipts, even for a malformed backend response.
    """
    pending, containers, nodes, characters = [(value, 0)], set(), 0, 0
    while pending:
        current, depth = pending.pop()
        nodes += 1
        if nodes > 4096 or depth > 32:
            raise ValueError('response bounds exceeded')
        kind = type(current)
        if kind is str:
            characters += len(current)
            if characters > 1048576 or (token and token in current):
                raise ValueError('unsafe response string')
        elif kind is dict or kind is list:
            identity = id(current)
            if identity in containers or nodes + len(pending) + len(current) > 4096:
                raise ValueError('cyclic or oversized response')
            containers.add(identity)
            if kind is dict:
                if nodes + len(pending) + 2 * len(current) > 4096:
                    raise ValueError('oversized response mapping')
                for key, item in current.items():
                    if type(key) is not str:
                        raise ValueError('unsupported response key')
                    pending.extend(((key, depth + 1), (item, depth + 1)))
            else:
                pending.extend((item, depth + 1) for item in current)
        elif current is None or kind is bool:
            continue
        elif kind is int:
            if current.bit_length() > 256:
                raise ValueError('oversized response integer')
        elif kind is float:
            if not math.isfinite(current):
                raise ValueError('nonfinite response number')
        else:
            raise ValueError('unsupported response object')


def _transport(module, token):
    """Reviewed one-shot transport; fixed address, original HTTP authority."""
    class FrozenClient(module.FixtureClient):
        connection = None

        def close(self):
            if self.connection is not None:
                self.connection.close()
                self.connection = None

        def request(self, method, path, body=None,
                    content_type='text/plain; charset=us-ascii', headers=None):
            try:
                if self.connection is None:
                    self.connection = http.client.HTTPConnection(ENDPOINT, PORT, timeout=self.timeout)
                outgoing = dict(headers or {})
                # Caller headers cannot change the reviewed authority or credential.
                for key in list(outgoing):
                    if key.lower() in ('host', 'authorization', 'connection'):
                        del outgoing[key]
                outgoing.update({'Host': HOST + ':' + str(PORT),
                                 'Authorization': 'Bearer ' + self.token,
                                 'Connection': 'close'})
                if body is not None:
                    outgoing['Content-Type'] = content_type
                self.connection.request(method, path, body, headers=outgoing)
                response = self.connection.getresponse()
                payload = response.read()
                if not 200 <= response.status < 300:
                    raise RuntimeError('fixture request rejected')
                return payload.decode('utf-8')
            except Exception:
                try:
                    self.close()
                except Exception:
                    pass
                raise RuntimeError('fixture transport failed; diagnostics suppressed; no retry') from None

    # Construction does not resolve, connect, authenticate, or inspect the fixture.
    return FrozenClient(HOST, token, port=PORT, timeout=10.0)


class ScopedClient:
    """Only the D7 control surface; no generic request/update/firmware API."""
    def __init__(self, client):
        self._client = client
        self._run = None
        self._closed = False

    def _call(self, method, *args, **kwargs):
        if self._closed:
            raise RuntimeError('fixture client closed')
        try:
            value = getattr(self._client, method)(*args, **kwargs)
            # Reflected credentials must never enter campaign receipts or errors.
            _validate_response(value, self._client.token)
            return value
        except Exception:
            raise RuntimeError('fixture operation failed; diagnostics suppressed; no retry') from None

    def status(self):
        return self._call('status')

    def _verified_status(self):
        status = self.status()
        if (type(status) is not dict or status.get('ok') is not True
            or any(status.get(key) != value for key, value in EXPECTED_IDENTITY.items())):
            raise RuntimeError('fixture identity mismatch; mutation refused')
        return status

    def load_script(self, script):
        try:
            header = script.splitlines()[0].split()
            valid = (len(header) == 6 and header[0] == 'KPHID1'
                     and RUN.fullmatch(header[1]) is not None
                     and len(script.encode('ascii')) <= 32768)
        except (AttributeError, IndexError, UnicodeError):
            valid = False
        if not valid:
            raise RuntimeError('unsupported D7 script')
        status = self._verified_status()
        if status.get('state') not in ('idle', 'complete', 'aborted'):
            raise RuntimeError('active or unknown fixture state; load refused')
        # Retain ownership even if load applies but its HTTP response is lost.
        self._run = header[1]
        return self._call('load_script', script)

    def _owned(self, run):
        if not self._run or run != self._run:
            raise RuntimeError('foreign fixture run refused')

    def arm(self, run):
        self._owned(run)
        status = self._verified_status()
        if status.get('runId') != run or status.get('state') != 'loaded':
            raise RuntimeError('foreign or nonloaded fixture run; arm refused')
        return self._call('arm', run)

    def start(self, run, delay_ms):
        self._owned(run)
        if type(delay_ms) is not int or not 100 <= delay_ms <= 60000:
            raise RuntimeError('invalid fixture start delay')
        status = self._verified_status()
        if status.get('runId') != run or status.get('state') != 'armed':
            raise RuntimeError('foreign or nonarmed fixture run; start refused')
        return self._call('start', run, delay_ms)

    def abort(self):
        self._owned(self._run)
        status = self._verified_status()
        if status.get('runId') != self._run or status.get('state') not in ('loaded', 'armed', 'running'):
            raise RuntimeError('foreign or inactive fixture abort refused')
        return self._call('abort')

    def trace_all(self, limit=8, retry_seconds=0):
        # Base client rejects zero and otherwise retries. Use its existing one-shot
        # request transport and protocol header, with strict finite pagination.
        if type(limit) is not int or not 1 <= limit <= 8 or retry_seconds != 0:
            raise RuntimeError('trace requires bounded pages and zero retries')
        self._owned(self._run)
        rows, available = [], None
        while available is None or len(rows) < available:
            raw = self._call('request', 'GET', f'/v1/trace?from={len(rows)}&limit={limit}')
            try:
                page = [json.loads(line) for line in raw.splitlines()]
                # NDJSON escaping can hide literal token bytes in the raw payload.
                # Inspect decoded headers and entries before returning any extras.
                _validate_response(page, self._client.token)
                header, batch = page[0], page[1:]
                count = header['available']
                if (header.get('runId') != self._run or header.get('from') != len(rows)
                    or type(count) is not int or not 0 <= count <= 256
                    or (available is not None and count != available)
                    or len(batch) > limit or any(not isinstance(row, dict) for row in batch)
                    or len(rows) + len(batch) > count or (not batch and len(rows) < count)):
                    raise ValueError('invalid trace page')
                available = count
                rows.extend(batch)
            except (ValueError, KeyError, IndexError, TypeError, AttributeError):
                raise RuntimeError('fixture trace refused; diagnostics suppressed; no retry') from None
        return rows

    def close(self):
        if not self._closed:
            self._closed = True
            try:
                self._client.close()
            except Exception:
                raise RuntimeError('fixture close failed; diagnostics suppressed') from None
            finally:
                self._client.token = ''


def _selected_token():
    """Extract only the selected scalar; never decrypt the whole store or log it."""
    try:
        env = dict(os.environ)
        env['SOPS_AGE_KEY_FILE'] = str(pathlib.Path.home() / '.config/sops/age/keys.txt')
        result = subprocess.run(
            ['/opt/homebrew/bin/sops', '-d', '--extract', '["KEYPATH_FIXTURE_TOKEN"]',
             '--output-type', 'json', str(pathlib.Path.home() / 'dotfiles/secrets.env')],
            env=env, capture_output=True, text=True, timeout=10)
        if result.returncode:
            raise ValueError('selected credential unavailable')
        raw = result.stdout.rstrip('\n')
        try:
            token = json.loads(raw)
        except ValueError:
            token = raw
        if type(token) is not str or not token or len(token) > 4096 or any(c in token for c in '\r\n'):
            raise ValueError('invalid selected scalar')
        return token
    except Exception:
        raise RuntimeError('selected fixture credential unavailable; diagnostics suppressed') from None


def create_client():
    """Explicit selected-scalar extraction; no credential environment or argv."""
    try:
        module = _module(CLIENT, 'd7_fixture_client_dependency')
        token = _selected_token()
        return ScopedClient(_transport(module, token))
    except (Exception, SystemExit):
        raise RuntimeError('selected fixture credential or reviewed dependency unavailable') from None
