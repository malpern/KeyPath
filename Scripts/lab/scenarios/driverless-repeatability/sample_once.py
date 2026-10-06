#!/usr/bin/env python3
"""One fixed physical q sample; imported modules never dispatch a campaign."""
import hashlib
import importlib.util
import json
import os
import pathlib
import shlex
import socket
import subprocess
import sys
import time
import uuid

R = pathlib.Path(os.environ['KEYPATH_TRIAL_DIR']).resolve()
FIXTURE_PATH = pathlib.Path.home()/'local-code/keypath-pico-hid-fixture/Scripts/lab/pico-hid-fixture-client'
BASELINE_PATH = pathlib.Path('/private/tmp/vm-lab-guest-identity/rig/physical-baseline.py')
USB_ID = '3110000|cafe|4010|full|--|2884855553BC'

def require(ok, why):
    if not ok:
        raise RuntimeError(why)

def module(path, name):
    from importlib.machinery import SourceFileLoader
    spec = importlib.util.spec_from_loader(name, SourceFileLoader(name, str(path)))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

def write(name, value):
    fd = os.open(R/name, os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(value, stream, sort_keys=True)
        stream.write('\n'); stream.flush(); os.fsync(stream.fileno())

def scope():
    owned = json.loads((R/'owned-lease.json').read_text())
    identity = json.loads((R/'guest-identity.json').read_text())
    require(identity['lease'] == owned['lease'] and identity['providerUUID'] == owned['provider']
            and identity['uid'] == 502 and identity['account'] == 'keypathqa_438d6abc'
            and identity['home'] == '/Users/keypathqa_438d6abc'
            and time.time()+120 < owned['hardCutoffEpoch'] <= owned['manifestExpiresEpoch'],
            'owned scope refused')
    return owned, identity

def attached(path, owned):
    require(path.parent == R and path.resolve() == path, 'attachment receipt path refused')
    proof = json.loads(path.read_text())
    require(proof.get('passed') is True and proof.get('readOnly') is True
            and proof.get('actualStatus') == 0 and proof.get('lease') == owned['lease']
            and proof.get('providerUUID') == owned['provider']
            and 0 <= time.time()-proof.get('observedAtEpoch', 0) <= 30,
            'fresh attachment proof required')
    fixture = proof.get('fixture', {})
    require(fixture.get('System name') == USB_ID and fixture.get('Connected-To-Vm') == 'YES'
            and fixture.get('Used-By-Vm-Uuid', '').strip('{}').lower() == owned['provider'],
            'attachment binding changed')
    return proof

def host_usb(owned):
    p = subprocess.run(['/usr/bin/ssh', '-o', 'BatchMode=yes', 'malpern@mini',
                        "'/Applications/Parallels Desktop.app/Contents/MacOS/prlsrvctl' usb list --json"],
                       capture_output=True, text=True, timeout=20)
    require(p.returncode == 0, 'host USB observation failed')
    matches = [v for v in json.loads(p.stdout) if v.get('System name') == USB_ID]
    require(len(matches) == 1, 'fixture USB ambiguous')
    row = matches[0]
    require(row.get('Connected-To-Vm') == 'YES'
            and row.get('Used-By-Vm-Uuid', '').strip('{}').lower() == owned['provider']
            and row.get('Autoconnect-Action') == 'ask' and row.get('Autoconnect-Vm-Uuid') == '',
            'fixture USB ownership changed')
    return dict(systemName=USB_ID, providerUUID=owned['provider'], actualStatus=p.returncode,
                observedAtEpoch=time.time())

def observe(transport, source, label, owned, identity):
    args = ['/bin/launchctl', 'asuser', '502', '/usr/bin/sudo', '-H', '-u', identity['account'],
            '/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13', '-I', '-B',
            '-c', source, str(identity['bootEpoch']), str(owned['hardCutoffEpoch']), 'inspect']
    value = json.loads(transport.execute(label, 'exec '+shlex.join(args)))
    require(type(value) is dict and 'parents' in value and 'workers' in value, 'inspect refused')
    return value

def ready(value, empty=False):
    require(len(value['parents']) == 1 and len(value['workers']) == 1, 'one live parent/worker required')
    t, w = value['target'], value['workers'][0]['report']
    require(type(t) is dict and t.get('uid') == 502
            and t.get('active') is True and t.get('focusLost') is False
            and t.get('windowKey') is True and t.get('requestedResponderFocused') is True
            and t.get('secureTest') is False and t.get('secureInputEnabled') is False
            and t.get('held') == [] and t.get('modifiers') == 0
            and 0 <= time.time()-t.get('observedAt', 0) < 3
            and w.get('state') == 'running' and w.get('tapActive') is True
            and w.get('heldOutputUsages') == [], 'fresh normal all-up target/worker required')
    if empty:
        require(t.get('text') == '' and t.get('downs') == 0 and t.get('ups') == 0,
                'fresh empty target required')

def identity(value):
    p, w, t = value['parents'][0], value['workers'][0], value['target']
    return dict(parentPID=p['pid'], parentArguments=p['arguments'], workerPID=w['pid'],
                workerArguments=w['arguments'], reportPath=w['reportPath'],
                workerNonce=w['report']['nonce'], targetPID=t['pid'], targetNonce=t['nonce'])

def main(label, proof_path):
    require(label.replace('-', '').isalnum() and len(label) <= 40, 'sample label refused')
    owned, ident = scope()
    proof = attached(proof_path, owned)
    source = (pathlib.Path(__file__).resolve().parent/'restart_guest.py').read_text()
    write(label+'-sample-intent.json', dict(lease=owned['lease'], providerUUID=owned['provider'],
          bootEpoch=ident['bootEpoch'], cutoff=owned['hardCutoffEpoch'], noReplay=True,
          sample='q', scriptParameters=[120,40,1,200], startDelayMs=500,
          guestSourceSHA256=hashlib.sha256(source.encode()).hexdigest(), at=time.time()))
    transport = module(pathlib.Path(__file__).resolve().parent/'guest_command.py', 'sample_guest_command')
    before = observe(transport, source, label+'-before', owned, ident)
    ready(before, True)
    fixture = module(FIXTURE_PATH, 'sample_fixture')
    pilot = module(BASELINE_PATH, 'sample_pilot')
    run = 'restart-'+uuid.uuid4().hex
    script = fixture.compile_text(run, 'q', 120, 40, 1, 200)
    client = None
    record = dict(passed=False, lease=owned['lease'], providerUUID=owned['provider'], runId=run,
                  sample='q', expectedText='a', attachmentObservedAt=proof['observedAtEpoch'])
    try:
        scope(); ready(before, True)
        env = dict(os.environ, SOPS_AGE_KEY_FILE=str(pathlib.Path.home()/'.config/sops/age/keys.txt'))
        decrypted = subprocess.run(['/opt/homebrew/bin/sops', '-d', str(pathlib.Path.home()/'dotfiles/secrets.env')],
                                   capture_output=True, text=True, timeout=10, env=env)
        tokens = [line.split('=',1)[1] for line in decrypted.stdout.splitlines()
                  if line.startswith('KEYPATH_FIXTURE_TOKEN=')] if decrypted.returncode == 0 else []
        require(len(tokens) == 1 and bool(tokens[0]), 'fixture credential unavailable')
        addresses={row[4][0] for row in socket.getaddrinfo('keypath-hid-fixture.local',8080,family=socket.AF_INET,type=socket.SOCK_STREAM)}
        require(len(addresses)==1,'fixture address ambiguous')
        address=next(iter(addresses));require(address.startswith('192.168.1.'),'fixture address outside local network')
        record['fixtureResolution']=dict(hostname='keypath-hid-fixture.local',address=address,observedAtEpoch=time.time())
        client = pilot.persistent_client(fixture, address, tokens[0])
        probe_started=time.monotonic();client.status();require(time.monotonic()-probe_started<1,'numeric control path too slow')
        del tokens, decrypted
        require(client.status().get('state') in ('idle', 'complete', 'aborted'), 'foreign fixture campaign')
        client.load_script(script)
        client.arm(run)
        current = observe(transport, source, label+'-armed', owned, ident)
        ready(current, True)
        require(identity(current) == identity(before), 'identity changed before start')
        record['hostUSB'] = host_usb(owned)
        attached(proof_path, owned); scope()
        # Final target observation follows host USB read, so freshness is tested
        # directly at dispatch rather than across the SSH USB observation.
        before = observe(transport, source, label+'-prestart', owned, ident)
        ready(before, True)
        require(identity(before) == identity(current), 'identity changed before input')
        attached(proof_path, owned); scope()
        client.start(run, 500)
        deadline = min(time.monotonic()+8, time.monotonic()+owned['hardCutoffEpoch']-time.time()-120)
        while time.monotonic() < deadline:
            status = client.status()
            require(status.get('runId') == run, 'fixture ownership changed')
            if status.get('state') == 'complete':
                break
            time.sleep(.1)
        else:
            raise RuntimeError('fixture timeout')
        time.sleep(.3)
        after = observe(transport, source, label+'-after', owned, ident)
        ready(after)
        require(identity(after) == identity(before), 'identity changed after input')
        trace = client.trace_all(retry_seconds=5)
        expected = [list(map(int, line.split()[1:])) for line in script.splitlines()[1:]]
        actual = [[row.get('modifiers'), *row.get('keys', [])] for row in trace]
        t, wb, wa = after['target'], before['workers'][0]['report'], after['workers'][0]['report']
        checks = dict(exactTrace=actual == expected, reportsSubmitted=status.get('reportsSubmitted') == len(expected),
                      text=t.get('text') == 'a', downs=t.get('downs') == 1, ups=t.get('ups') == 1,
                      inputDelta=wa.get('inputCount',0)-wb.get('inputCount',0) == 2,
                      outputDelta=wa.get('outputCount',0)-wb.get('outputCount',0) == 2,
                      allUp=t.get('held') == [] and t.get('modifiers') == 0 and wa.get('heldOutputUsages') == [])
        require(all(checks.values()), 'physical sample acceptance failed')
        scope()
        record.update(passed=True, identity=identity(after), checks=checks, trace=trace,
                      target={k:t.get(k) for k in ('text','downs','ups','held','modifiers','observedAt')},
                      fixture={k:status.get(k) for k in ('runId','state','reportsSubmitted')})
    except Exception as error:
        record.update(errorType=type(error).__name__, error=str(error))
    finally:
        if client:
            try:
                state = client.status()
                if state.get('runId') == run and state.get('state') in ('loaded','armed','running'):
                    client.abort()
            except Exception:
                record.update(passed=False, cleanupError='owned fixture cleanup unverified')
            finally:
                client.close(); client.token = ''
        write(label+'-sample-result.json', record)
    print(json.dumps(record, sort_keys=True))
    return 0 if record['passed'] else 79

if __name__ == '__main__':
    require(len(sys.argv) == 3, 'expected LABEL ATTACHMENT_RECEIPT')
    sys.exit(main(sys.argv[1], pathlib.Path(sys.argv[2])))
