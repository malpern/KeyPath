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

CG_DIAGNOSTIC_SOURCE = '''
"""Trial-local read-only observation; root injects its existing fresh guest guard.

No event creation/posting, state mutation, polling, or fixture dispatch.
C ABI: CGEventSourceStateID int32; CGEventFlags uint64;
CGKeyCode uint16; CGEventSourceKeyState returns C bool.
"""
import ctypes
import json
import os
import sys
import time


def observe_caps_cg_state():
    if sys.platform != 'darwin' or os.getuid() != 502 or os.stat('/dev/console').st_uid != 502:
        raise RuntimeError('UID502 macOS console required; fresh scoped guard must precede observation')
    cg = ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
    flags_state = cg.CGEventSourceFlagsState
    flags_state.argtypes = [ctypes.c_int32]
    flags_state.restype = ctypes.c_uint64
    key_state = cg.CGEventSourceKeyState
    key_state.argtypes = [ctypes.c_int32, ctypes.c_uint16]
    key_state.restype = ctypes.c_bool
    request_epoch = time.time()
    states = {}
    for name, state_id in (('combinedSessionState', 0), ('hidSystemState', 1)):
        flags = int(flags_state(state_id))
        states[name] = dict(stateID=state_id, flags=flags, flagsHex=hex(flags),
            functionFlag=bool(flags & (1 << 23)), controlFlag=bool(flags & (1 << 18)),
            capsFlag=bool(flags & (1 << 16)),
            keys={name: dict(keyCode=code, down=bool(key_state(state_id, code)))
                  for name, code in (('fn', 63), ('f18', 79), ('control', 59),
                                     ('caps', 57), ('q', 12), ('a', 0))})
    return dict(readOnly=True, pid=os.getpid(), uid=os.getuid(), home=os.environ.get('HOME'),
                requestEpoch=request_epoch, replyEpoch=time.time(), monotonicAt=time.monotonic(),
                states=states, observationAtomic=False)

'''

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

def diagnostic_released_journal(t):
    rows = t.get('keyEventsJournal')
    require(type(rows) is list and len(rows) <= 128 and t.get('keyEventsDropped') == 0,
            'complete bounded prior key journal required')
    held, downs, ups = set(), 0, 0
    for sequence, row in enumerate(rows, 1):
        require(type(row) is dict and row.get('sequence') == sequence
                and row.get('keyCode') in (79, 0)
                and row.get('active') is True and row.get('focusLost') is False
                and row.get('windowKey') is True and row.get('requestedResponderFocused') is True
                and row.get('focusedMode') == 'normal' and row.get('secureInputEnabled') in (False, 0)
                and row.get('modifiers') in (0, 0x100, 0x800000, 0x800100)
                and type(row.get('isRepeat')) is bool, 'prior key journal state refused')
        key = row['keyCode']
        if row.get('type') == 'down':
            require((key in held) == row['isRepeat'], 'unpaired or duplicate prior press')
            held.add(key); downs += 1
        else:
            require(row.get('type') == 'up' and key in held and not row['isRepeat'],
                    'unpaired prior release')
            held.remove(key); ups += 1
        require(row.get('held') == sorted(held), 'prior journal held state changed')
    require(not held and type(t.get('downs')) is int and type(t.get('ups')) is int
            and (downs, ups) == (t['downs'], t['ups']), 'prior key journal counts or release refused')

def ready(value, empty=False, function_diagnostic=False):
    require(len(value['parents']) == 1 and len(value['workers']) == 1, 'one live parent/worker required')
    t, w = value['target'], value['workers'][0]['report']
    require(type(t) is dict and t.get('uid') == 502
            and t.get('active') is True and t.get('focusLost') is False
            and t.get('windowKey') is True and t.get('requestedResponderFocused') is True
            and t.get('secureTest') is False and t.get('secureInputEnabled') is False
            and t.get('held') == [] and (t.get('modifiers') in (0,0x100,0x800000,0x800100) if function_diagnostic else t.get('modifiers') == 0)
            and 0 <= time.time()-t.get('observedAt', 0) < 3
            and w.get('state') == 'running' and w.get('tapActive') is True
            and w.get('heldOutputUsages') == [], 'fresh normal all-up target/worker required')
    if function_diagnostic:
        diagnostic_cg(value.get('cgState'))
        require(type(t.get('text')) is str, 'prior target text required')
        diagnostic_released_journal(t)
    if empty and not function_diagnostic:
        require(t.get('text') == '' and t.get('downs') == 0 and t.get('ups') == 0,
                'fresh empty target required')

# MacOSX27.0 SDK: NX_NONCOALSESCEDMASK=0x100; AlphaShift=0x10000; SecondaryFn=0x800000.
# Preserve raw flags; noncoalesced is not a held modifier.
def diagnostic_cg(value):
    require(type(value) is dict and value.get('readOnly') is True and value.get('uid')==502
            and 0<=time.time()-value.get('requestEpoch',0)<3, 'fresh read-only CG observation required')
    states=value.get('states',{})
    require(set(states)=={'combinedSessionState','hidSystemState'},'CG state domains required')
    for name,sid in (('combinedSessionState',0),('hidSystemState',1)):
        row=states[name]
        require(row.get('stateID')==sid and type(row.get('flags')) is int and row['flags'] in (0,0x100,0x800000,0x800100)
                and set(row.get('keys',{}))=={'fn','f18','control','caps','q','a'}
                and all(row['keys'][name].get('keyCode')==code and row['keys'][name].get('down') is False
                        for name,code in (('fn',63),('f18',79),('control',59),('caps',57),('q',12),('a',0))),
                'Function/noncoalesced-only flags and physically released selected keys required')
    return value

def diagnostic_prestart_equal(before,current):
    require(before['target']['modifiers']==current['target']['modifiers']
            and before['cgState']['states']==current['cgState']['states'],
            'diagnostic CG states or target flags changed before input')

def retain_sample_evidence(record,before,after,status,trace):
    record.update(trace=trace,fixture={k:status.get(k) for k in ('runId','state','reportsSubmitted')},
        observations={name:dict(target={k:(value.get('target') or {}).get(k)
            for k in ('text','downs','ups','held','modifiers','observedAt')},
            workers=[{k:(row.get('report') or {}).get(k)
                for k in ('pid','nonce','inputCount','outputCount','heldOutputUsages')}
                for row in value.get('workers',[])]) for name,value in (('before',before),('after',after))})

def identity(value):
    p, w, t = value['parents'][0], value['workers'][0], value['target']
    return dict(parentPID=p['pid'], parentArguments=p['arguments'], workerPID=w['pid'],
                workerArguments=w['arguments'], reportPath=w['reportPath'],
                workerNonce=w['report']['nonce'], targetPID=t['pid'], targetNonce=t['nonce'])

def main(label, proof_path, function_diagnostic=False):
    require(label.replace('-', '').isalnum() and len(label) <= 40, 'sample label refused')
    owned, ident = scope()
    proof = attached(proof_path, owned)
    source = (pathlib.Path(__file__).resolve().parent/'restart_guest.py').read_text()
    if function_diagnostic:
        marker="\nif __name__ == '__main__':\n"
        require(source.count(marker)==1,'guest entrypoint framing refused')
        head,tail=source.split(marker)
        source=head+'\n'+CG_DIAGNOSTIC_SOURCE+"\n_original_inspect=inspect\ndef inspect():\n    value=_original_inspect()\n    value['cgState']=observe_caps_cg_state()\n    return value\n"+marker+tail
        compile(source,'function-handback-guest','exec')
    write(label+'-sample-intent.json', dict(lease=owned['lease'], providerUUID=owned['provider'],
          bootEpoch=ident['bootEpoch'], cutoff=owned['hardCutoffEpoch'], noReplay=True,
          sample='q', scriptParameters=[120,40,1,200], startDelayMs=500,
          guestSourceSHA256=hashlib.sha256(source.encode()).hexdigest(), at=time.time()))
    transport = module(pathlib.Path(__file__).resolve().parent/'guest_command.py', 'sample_guest_command')
    before = observe(transport, source, label+'-before', owned, ident)
    ready(before, True, function_diagnostic)
    fixture = module(FIXTURE_PATH, 'sample_fixture')
    pilot = module(BASELINE_PATH, 'sample_pilot')
    run = 'restart-'+uuid.uuid4().hex
    script = fixture.compile_text(run, 'q', 120, 40, 1, 200)
    client = None
    record = dict(passed=False, lease=owned['lease'], providerUUID=owned['provider'], runId=run,
                  sample='q', expectedText='a', attachmentObservedAt=proof['observedAtEpoch'])
    try:
        scope(); ready(before, True, function_diagnostic)
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
        ready(current, True, function_diagnostic)
        require(identity(current) == identity(before), 'identity changed before start')
        if function_diagnostic:diagnostic_prestart_equal(before,current)
        record['hostUSB'] = host_usb(owned)
        attached(proof_path, owned); scope()
        # Final target observation follows host USB read, so freshness is tested
        # directly at dispatch rather than across the SSH USB observation.
        initial_before=before
        before = observe(transport, source, label+'-prestart', owned, ident)
        ready(before, True, function_diagnostic)
        require(identity(before) == identity(current), 'identity changed before input')
        if function_diagnostic:
            diagnostic_prestart_equal(initial_before,before)
            diagnostic_prestart_equal(current,before)
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
        if function_diagnostic:record.update(functionHandbackDiagnostic=True,beforeCG=before.get('cgState'),afterCG=after.get('cgState'))
        retain_sample_evidence(record,before,after,status,[])
        validation_error=None
        try:
            ready(after, function_diagnostic=function_diagnostic)
            require(identity(after) == identity(before), 'identity changed after input')
        except Exception as error:
            validation_error=error
        try:
            trace = client.trace_all(retry_seconds=5)
            retain_sample_evidence(record,before,after,status,trace)
        except Exception as error:
            if validation_error is not None:
                record['traceCollectionError']=str(error)
                raise validation_error
            raise
        if validation_error is not None:raise validation_error
        expected = [list(map(int, line.split()[1:])) for line in script.splitlines()[1:]]
        actual = [[row.get('modifiers'), *row.get('keys', [])] for row in trace]
        t, wb, wa = after['target'], before['workers'][0]['report'], after['workers'][0]['report']
        checks = dict(exactTrace=actual == expected, reportsSubmitted=status.get('reportsSubmitted') == len(expected),
                      text=t.get('text') == (before['target']['text']+'a' if function_diagnostic else 'a'),
                      downs=t.get('downs') == (before['target']['downs']+1 if function_diagnostic else 1),
                      ups=t.get('ups') == (before['target']['ups']+1 if function_diagnostic else 1),
                      inputDelta=wa.get('inputCount',0)-wb.get('inputCount',0) == 2,
                      outputDelta=wa.get('outputCount',0)-wb.get('outputCount',0) == 2,
                      allUp=t.get('held') == [] and (t.get('modifiers') in (0,0x100,0x800000,0x800100) if function_diagnostic else t.get('modifiers') == 0) and wa.get('heldOutputUsages') == [])
        if function_diagnostic:
            checks['controlAndHeldClear']=checks.pop('allUp')
            record.update(functionHandbackDiagnostic=True,beforeCG=before['cgState'],afterCG=after['cgState'],
                fullModifierAllUp=(t['modifiers'] & ~0x100)==0 and all((v['flags'] & ~0x100)==0 for v in after['cgState']['states'].values()),
                beforeTarget={k:before['target'].get(k) for k in ('text','downs','ups','held','modifiers')})
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
    diagnostic=len(sys.argv)==4 and sys.argv[3]=='--function-handback-diagnostic'
    require(len(sys.argv)==3 or diagnostic, 'expected LABEL ATTACHMENT_RECEIPT optional --function-handback-diagnostic')
    sys.exit(main(sys.argv[1], pathlib.Path(sys.argv[2]),diagnostic))
