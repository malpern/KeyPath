"""No fixture imports or calls. Live ordinary setup requires separate release."""
import argparse
import ast
import base64
from dataclasses import dataclass
import hashlib
import importlib.util
import json
import math
import os
import pathlib
import re
import shlex
import subprocess
import stat
import sys
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parent
HARNESS = pathlib.Path('/private/tmp/keypath-d8-readonly-transport-candidate/Scripts/experiments/session-runtime/held-secure-acceptance.py')
IDENTITY = pathlib.Path('/private/tmp/keypath-guest-identity/Scripts/experiments/session-runtime/guest-identity.py')
RIG = pathlib.Path('/private/tmp/vm-lab-guest-identity')
SOURCE_PINS_SHA = '87217ca0531722cdb65be33f1b19242e4eb5748524816d303dded14bbc34032c'
BASE_SCOPE=dict(version=1,account='keypathqa_438d6abc',uid=502,home='/Users/keypathqa_438d6abc',productSource='6ed4ea99052c19bc94e99517cfe9827377b17af7',binarySHA256='d3420624a492016df316fa6285e932470bbc49d25ff538639a2d19c31e196682',targetSHA256='55c8fa008280633ecf6137d7d47df27e152b16a8ba37bbf01dca4c7ab4ef4858',targetArchiveSHA256='26e5b024f561ebd6ccee43f2d4b07056d9da8d09c5be5aab9a61553380a52fb8',targetExecutable='/Users/keypathqa_438d6abc/Applications/VM Lab Rig Target.app/Contents/MacOS/RigTarget')
EXECUTOR=ROOT/'executor.py'
BINDING_FIELDS=('identityReceipt','identityReceiptSHA256','lease','providerUUID','bootEpoch','deadline','baselineInventory','baselineInventorySHA256')
import prepared_identity as prepared
import fresh_capture

@dataclass(frozen=True)
class Scope:
    lease: str
    provider_uuid: str
    boot_epoch: int
    account: str
    uid: int
    home: str
    deadline: int
    product_source: str
    binary_sha256: str
    receipt_path: str
    receipt_sha256: str
    target_executable: str
    target_sha256: str
    baseline_path: str
    baseline_sha: str

    def identity_tuple(self):
        return dict(account=self.account, uid=self.uid, home=self.home, lease=self.lease,
                    providerUUID=self.provider_uuid, bootEpoch=self.boot_epoch)


def admit_scope(value):
    require(type(value) is dict and set(value) == set(BASE_SCOPE) | set(BINDING_FIELDS),
            'invalid timing scope schema')
    require(all(type(value[k]) is type(v) and value[k] == v for k, v in BASE_SCOPE.items()),
            'timing scope identity/product/deadline changed')
    require(type(value['lease'])is str and re.fullmatch('cbx_[0-9a-f]{12}',value['lease']) and type(value['providerUUID'])is str and prepared.valid_uuid(value['providerUUID']) and type(value['bootEpoch'])is int and value['bootEpoch']>0 and type(value['deadline'])is int and value['deadline']>0 and value['baselineInventorySHA256']==prepared.BASELINE_SHA and type(value['baselineInventory'])is str,'fresh prepared scope required')
    for name in ('identityReceiptSHA256', 'targetSHA256'):
        require(type(value[name]) is str and re.fullmatch(r'[a-f0-9]{64}', value[name]) is not None,
                'timing scope binding incomplete')
    require(type(value['identityReceipt']) is str and value['identityReceipt'].startswith('/private/tmp/')
            and '..' not in pathlib.Path(value['identityReceipt']).parts
            and str(pathlib.Path(value['identityReceipt'])) == value['identityReceipt'],
            'private identity receipt namespace required')
    require(type(value['targetExecutable']) is str and value['targetExecutable'].startswith(value['home'] + '/')
            and not any(ord(c) < 32 for c in value['targetExecutable'])
            and '..' not in pathlib.Path(value['targetExecutable']).parts
            and str(pathlib.Path(value['targetExecutable'])) == value['targetExecutable'],
            'owned target executable binding required')
    return Scope(value['lease'], value['providerUUID'], value['bootEpoch'], value['account'], value['uid'],
                 value['home'], value['deadline'], value['productSource'], value['binarySHA256'],
                 value['identityReceipt'], value['identityReceiptSHA256'], value['targetExecutable'], value['targetSHA256'],value['baselineInventory'],value['baselineInventorySHA256'])


def identity_dependency():
    verify_sources()
    return module(IDENTITY, 'timing_identity')


def read_scope(path, expected_sha):
    private_receipt_parents(path)
    identity_module = identity_dependency()
    raw = identity_module.read_private_receipt(path)
    require(type(expected_sha) is str and hashlib.sha256(raw).hexdigest() == expected_sha,
            'frozen timing scope changed')
    scope = admit_scope(json.loads(raw, object_pairs_hook=identity_module.unique_keys))
    return scope, hashlib.sha256(raw).hexdigest()


def private_receipt_parents(path):
    """Trust /private/tmp itself; require private owned canonical descendants."""
    parent = pathlib.Path(path).parent
    anchor = pathlib.Path('/private/tmp')
    while parent != anchor:
        require(anchor in parent.parents, 'private identity receipt namespace required')
        metadata = parent.lstat()
        require(stat.S_ISDIR(metadata.st_mode) and metadata.st_uid == os.getuid()
                and stat.S_IMODE(metadata.st_mode) == 0o700,
                'identity receipt parent must be owned private directory')
        parent = parent.parent


def bound_identity(scope, identity_module):
    private_receipt_parents(scope.receipt_path)
    identity=prepared.load(pathlib.Path(scope.receipt_path),scope.receipt_sha256,pathlib.Path(scope.baseline_path),scope.baseline_sha,scope.deadline)
    require(identity.receipt_sha256 == scope.receipt_sha256 and identity.account == scope.account
            and identity.uid == scope.uid and identity.home == scope.home and identity.lease == scope.lease
            and identity.provider_uuid == scope.provider_uuid and identity.boot_epoch == scope.boot_epoch,
            'identity tuple changed')
    return identity


def bind_scope(destination, receipt, receipt_sha, target_executable, target_sha, inventory, inventory_sha, deadline):
    ident=prepared.load(receipt,receipt_sha,inventory,inventory_sha,deadline)
    require(type(deadline)is int and deadline>time.time()+180,'fresh declared cutoff required')
    scope_value = dict(BASE_SCOPE, identityReceipt=str(receipt), identityReceiptSHA256=receipt_sha,
                       targetExecutable=target_executable, targetSHA256=target_sha,lease=ident.lease,providerUUID=ident.provider_uuid,bootEpoch=ident.boot_epoch,deadline=deadline,baselineInventory=str(inventory),baselineInventorySHA256=inventory_sha)
    scope = admit_scope(scope_value)
    bound_identity(scope, identity_dependency())  # local private-file checks only
    require(destination.is_absolute() and destination.parent == ROOT, 'candidate scope namespace required')
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as output:
        output.write(json.dumps(scope_value, indent=2) + '\n')
        output.flush()
        os.fsync(output.fileno())
    return hashlib.sha256(destination.read_bytes()).hexdigest()

def require(condition, reason):
    if not condition:
        raise RuntimeError(reason)

def verify_sources():
    raw = (ROOT / 'source-pins.json').read_bytes()
    require(hashlib.sha256(raw).hexdigest() == SOURCE_PINS_SHA, 'source pin manifest changed')
    for name, expected in json.loads(raw).items():
        require(hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest() == expected, 'frozen source changed')

def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    sys.modules[name] = value
    spec.loader.exec_module(value)
    return value

def dependencies(scope):
    """Extract reviewed Guest and transport only; no campaign/fixture entrypoint."""
    verify_sources()
    identity_module = module(IDENTITY, 'timing_identity')
    identity = bound_identity(scope, identity_module)
    pilot_ns = dict(subprocess=subprocess, time=time, ROOT=RIG, HOST='malpern@mini')
    tree = ast.parse((RIG / 'rig/physical-baseline.py').read_text())
    functions = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in ('lab', 'observe')]
    require(len(functions) == 2, 'transport source shape changed')
    exec(compile(ast.Module(body=functions, type_ignores=[]), 'pinned-readonly-pilot', 'exec'), pilot_ns)
    underlying = pilot_ns['lab']
    def guarded_lab(*values):
        require(time.time() < scope.deadline, 'lease dispatch cutoff reached')
        result = underlying(*values)
        require(time.time() < scope.deadline, 'lease response crossed cutoff; no replay')
        return result
    status=guarded_lab(scope.lease,'status')
    prepared.admit_provider(status,identity,scope.deadline,time.time())
    pilot_ns['lab'] = guarded_lab  # observe retains its frozen one read-only retry
    pilot = type('Pilot', (), dict(lab=staticmethod(guarded_lab), observe=staticmethod(pilot_ns['observe'])))()
    predicates = module(HARNESS.with_name('held_secure_predicates.py'), 'timing_predicates')
    tree = ast.parse(HARNESS.read_text())
    nodes = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.ClassDef))
             and n.name in ('Guest', 'load_module', 'readiness_module')]
    require(len(nodes) == 3, 'Guest source shape changed')
    ns = dict(__file__=str(HARNESS), argparse=argparse, base64=base64, hashlib=hashlib,
              importlib=__import__('importlib'), json=json, os=os, sys=sys, pathlib=pathlib,
              re=re, shlex=shlex, time=time, uuid=uuid, require=predicates.require,
              Refusal=predicates.Refusal, IDENTITY_MODULE=IDENTITY,
              PARENT_READINESS_SHA256='69e69782c338a36768233fddcdadac54ea2b908a25d39ec84b9b4bcd6ee19f6b',
              _READINESS_MODULE=None, GUEST_PYTHON='/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13',
              CONFIG='(defcfg)\n(defsrc q a)\n(deflayer base a a)\n')
    exec(compile(ast.Module(body=nodes, type_ignores=[]), str(HARNESS), 'exec'), ns)
    # Locally pinned collector correction; tuple/time/report admission unchanged.
    corrected_readiness=module(ROOT/'parent_readiness.py','timeout_filtered_parent_readiness')
    ns['readiness_module']=lambda:corrected_readiness
    # Reuse corrected real Guest.start/read call sites; Campaign is never constructed.
    executor=module(EXECUTOR,'timeout_timing_executor')
    adapter=type('Adapter',(),dict(Guest=ns['Guest'],Campaign=object,Refusal=predicates.Refusal,GUEST_PYTHON=ns['GUEST_PYTHON']))
    Guest,_=executor.classes(adapter)
    Guest=diagnostic_guest(Guest,predicates.Refusal,ns['CONFIG'])
    guest=Guest(scope.lease, pilot, scope.binary_sha256, scope.target_sha256, identity)
    guest.capture_scope=scope
    return guest, identity, pilot

START_STAGES=('parent.initial-identity','parent.backup-dispatch','parent.profile-identity','parent.profile-launch-dispatch','parent.discovery','parent.identity')
def diagnostic_guest(Base,Refusal,CONFIG):
    class Guest(Base):
        READ_STAGES=Base.READ_STAGES+('capture.preflight','capture.observe')
        def startup_preflight(self):
            require(not self.processes(), 'existing KeyPath process; campaign refuses adoption')
            require(self.read('stat -f %Su /dev/console', 'preflight.console').strip()==self.account,'wrong owned console')
            self.check_account()
            self.read('codesign --verify --deep --strict -R='+shlex.quote('anchor apple generic and certificate leaf[subject.OU] = "X2RKZ5TG99"')+' '+shlex.quote(self.app),'preflight.signature')
            require(self.read('shasum -a 256 '+shlex.quote(self.exe),'preflight.hash').split()[0]==self.binary_sha,'frozen parent/worker binary mismatch')
            self.read('/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13 -I -B -c '+shlex.quote('import json,os,pathlib,stat,sys; assert sys.version_info[:3] == (3,13,16)'),'preflight.python')
            return fresh_capture.preflight(self,self.capture_scope)
        def fresh_capture(self, claim):
            return fresh_capture.capture(self,self.capture_scope,claim,target_check)
        def start(self):
            self.start_stage='parent.initial-identity';self.check_account()
            self.start_stage='parent.backup-dispatch'
            self.run('test -f '+shlex.quote(self.profile)+' && test ! -e '+shlex.quote(self.backup)+' && cp -p '+shlex.quote(self.profile)+' '+shlex.quote(self.backup))
            self.backed_up=True
            self.start_stage='parent.profile-identity';self.check_account()
            self.parent_launch_requested_at=time.time()
            self.start_stage='parent.profile-launch-dispatch'
            self.run('printf %s '+shlex.quote(CONFIG)+' > '+shlex.quote(self.profile)+' && chown '+shlex.quote(self.account)+' '+shlex.quote(self.profile)+' && launchctl asuser '+str(self.uid)+' sudo -H -u '+shlex.quote(self.account)+' open -n '+shlex.quote(self.app)+' --args --headless')
            deadline=time.monotonic()+8
            while time.monotonic()<deadline:
                self.start_stage='parent.discovery';rows=self.processes()
                require(time.monotonic()<deadline,'parent discovery overran deadline')
                parents=[(pid,args)for pid,uid,args in rows if uid==self.uid and '--headless'in args and '--session-runtime'not in args]
                require(len(parents)<=1,'ambiguous parent launch')
                if parents:
                    self.parent,self.parent_args=parents[0]
                    self.start_stage='parent.identity';identity=self.identity(self.parent,self.parent_args)
                    require(time.monotonic()<deadline,'parent identity overran deadline');return identity
                time.sleep(.2)
            raise Refusal('parent launch deadline')
    return Guest

def selected_failure(guest,error):
    out={};stages=getattr(guest,'READ_STAGES',())
    allowed={stage+suffix for stage in stages for suffix in('.identity','.command')}
    for name in ('read_stage','read_failure_stage'):
        value=getattr(guest,name,None)
        if value in allowed:out[name]=value
    value=getattr(guest,'start_stage',None)
    if value in START_STAGES:out['parentStartStage']=value
    if type(error)is RuntimeError:
        match=re.fullmatch(r'owned guest operation failed: (guest-root|status) exit=(255|79|1); diagnostics suppressed',str(error))
        if match:out.update(transportVerb=match[1],transportExitCode=int(match[2]))
    if str(error)in ('parent discovery overran deadline','parent identity overran deadline','ambiguous parent launch','parent launch deadline') and type(error).__name__ in ('RuntimeError','Refusal'):
        out['parentStartReason']=str(error)
    return out

SCOPED_DIRECTORY_CODE = '''import os,pathlib,re,stat,uuid
def scoped_directory(raw,uid,nonce):
 raw=pathlib.Path(raw)
 assert type(uid)is int and uid>=0 and str(uuid.UUID(nonce)).upper()==nonce.upper()
 pattern=r'/(?:private/)?var/folders/[A-Za-z0-9_/-]+/T/keypath-session-'+re.escape(nonce)
 assert re.fullmatch(pattern,str(raw)) and '..'not in raw.parts and str(raw)==os.path.normpath(str(raw))
 expected=pathlib.Path('/private'+str(raw))if str(raw).startswith('/var/')else raw
 assert pathlib.Path('/var').resolve()==pathlib.Path('/private/var')
 canonical=raw.resolve(strict=True)
 assert canonical==expected and canonical.resolve(strict=True)==canonical
 current=pathlib.Path('/')
 for part in canonical.parts[1:]:
  current=current/part;s=current.lstat();assert stat.S_ISDIR(s.st_mode) and not stat.S_ISLNK(s.st_mode)
 signature=lambda s:(s.st_dev,s.st_ino,s.st_mode,s.st_uid,s.st_gid)
 a=raw.lstat();b=canonical.lstat()
 assert signature(a)==signature(b) and stat.S_ISDIR(b.st_mode) and b.st_uid==uid and stat.S_IMODE(b.st_mode)==0o700
 return canonical,signature(b)
def recheck_directory(raw,uid,nonce,d,signature):
 actual,metadata=scoped_directory(raw,uid,nonce)
 assert actual==d and metadata==signature
'''
FSYNC_CODE = SCOPED_DIRECTORY_CODE+'''import json,os,pathlib,stat,sys,time
stage='report-scope'
try:
 stage='report-scope'
 report=pathlib.Path(sys.argv[1]);expected=json.loads(sys.argv[2]);label=sys.argv[3]
 assert len(label)==32 and all(c in '0123456789abcdef' for c in label)
 rawdir=report.parent;meta=lambda s:(s.st_dev,s.st_ino,s.st_mode,s.st_uid,s.st_gid,s.st_nlink,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
 stage='directory-metadata';assert os.getuid()==expected['uid'];d,owned=scoped_directory(rawdir,expected['uid'],expected['nonce']);report=d/report.name;assert report.name=='report.json'
 stage='report-open';fd=os.open(report,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
 try:
  stage='report-metadata';s=os.fstat(fd);assert stat.S_ISREG(s.st_mode) and s.st_uid==expected['uid'] and s.st_nlink==1 and stat.S_IMODE(s.st_mode)==0o600 and 0<s.st_size<65536
  stage='report-read-stability';raw=os.read(fd,65537);assert meta(s)==meta(os.fstat(fd))==meta(report.lstat());r=json.loads(raw)
  stage='report-identity-idle';assert all(r[k]==v for k,v in expected.items()if k!='ownerPID') and r['state']=='running' and r['tapActive']is True and r['heldOutputUsages']==[] and r['inputCount']==r['outputCount']==0
  stage='report-freshness';assert 0<=time.time()-r['timestamp']-978307200<3
 finally:os.close(fd)
 values=[]
 for i in range(3):
  begin=time.perf_counter()
  for phase in ('entered','returned'):
   recheck_directory(rawdir,expected['uid'],expected['nonce'],d,owned)
   p=d/('timing-fsync-'+label+'-'+str(i)+'-'+phase+'.json')
   body=dict(version=1,sequence=1,pid=expected['pid'],uid=expected['uid'],parentPID=expected['ownerPID'],nonce=expected['nonce'],phase=phase,durationMillis=750,monotonicNanos=time.monotonic_ns())
   raw=json.dumps(body,sort_keys=True,separators=(',',':')).encode()
   stage='receipt-open';fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
   try:
    stage='receipt-write';assert os.write(fd,raw)==len(raw)
    stage='receipt-fsync';os.fsync(fd)
   finally:os.close(fd)
   stage='directory-open';fd=os.open(d,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
   try:
    stage='directory-fsync';os.fsync(fd)
   finally:os.close(fd)
  values.append(time.perf_counter()-begin)
 recheck_directory(rawdir,expected['uid'],expected['nonce'],d,owned)
 print(json.dumps(dict(passed=True,samples=values)))
except Exception as error:
 kind=type(error).__name__
 if kind not in ('AssertionError','FileNotFoundError','PermissionError','OSError','ValueError','KeyError','TypeError'):kind='OtherException'
 errno=getattr(error,'errno',None)
 if type(errno)is not int or not 0<=errno<=4095:errno=None
 print(json.dumps(dict(passed=False,stage=stage,exceptionClass=kind,errno=errno)))
'''

def benchmark_fsync(guest,worker,scope):
    expected={k:worker[k]for k in ('pid','uid','nonce')};expected['ownerPID']=guest.parent
    require(expected['uid']==502 and type(expected['pid'])is int and expected['pid']>0,'benchmark generation invalid')
    guest.identity(worker['pid'],worker['arguments'])
    command=('launchctl asuser 502 sudo -H -u '+shlex.quote(scope.account)+' '
             +shlex.quote('/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13')
             +' -I -B -c '+shlex.quote(FSYNC_CODE)+' '+shlex.quote(worker['reportPath'])
             +' '+shlex.quote(json.dumps(expected,sort_keys=True))+' '+uuid.uuid4().hex)
    # Mutation exactly once through run, never observe's read-only retry route.
    result=json.loads(guest.run(command))
    require(type(result)is dict and type(result.get('passed'))is bool,'invalid benchmark result')
    if result['passed']is False:
        stages=('report-scope','directory-metadata','report-open','report-metadata','report-read-stability','report-identity-idle','report-freshness','receipt-open','receipt-write','receipt-fsync','directory-open','directory-fsync')
        kinds=('AssertionError','FileNotFoundError','PermissionError','OSError','ValueError','KeyError','TypeError','OtherException')
        require(set(result)=={'passed','stage','exceptionClass','errno'} and result['stage']in stages and result['exceptionClass']in kinds and (result['errno']is None or type(result['errno'])is int and 0<=result['errno']<=4095),'invalid benchmark failure frame')
        guest.benchmark_failure=result
        raise RuntimeError('receipt fsync benchmark refused')
    require(set(result)=={'passed','samples'},'invalid benchmark success frame')
    samples=result['samples']
    require(type(samples)is list and len(samples)==3 and all(number(v) and v>=0 for v in samples),'invalid fsync samples')
    return samples

def number(value):
    return type(value) in (int, float) and math.isfinite(value)

def target_check(target, now, binding=None, uid=502):
    require(number(target.get('observedAt')) and 0 <= now - target['observedAt'] < 3, 'stale target')
    require(target.get('uid') == uid and type(target.get('pid')) is int and target['pid'] > 0
            and isinstance(target.get('nonce'), str), 'target identity unavailable')
    if binding:
        require(tuple(target.get(k) for k in ('pid', 'uid', 'nonce')) == binding, 'target instance changed')
    require(all(target.get(k) is True for k in ('active', 'windowKey', 'requestedResponderFocused'))
            and target.get('focusLost') is False and target.get('focusedMode') == 'normal'
            and target.get('secureTest') is False and target.get('secureInputEnabled') is False,
            'normal target focus lost')
    require(target.get('held') == [] and target.get('modifiers') == 0
            and target.get('combinedSessionControl') is False and target.get('downs') == target.get('ups') == 0
            and target.get('text') == '' and target.get('secureLength') == 0, 'target not empty/all-up')
    return tuple(target[k] for k in ('pid', 'uid', 'nonce'))

def worker_check(report, binding, now):
    require(tuple(report.get(k) for k in ('pid', 'uid', 'nonce')) == binding, 'worker generation changed')
    require(number(report.get('timestamp')) and 0 <= now - (report['timestamp'] + 978307200) < 3,
            'stale worker')
    require(report.get('inputAccessSource') == 'current-process.apple-api.modifying-tap-post-event'
            and report.get('accessibility') is True and report.get('effectiveInputAccess') is True,
            'reviewed modifying-tap permission source unavailable')
    require(report.get('state') == 'running' and report.get('tapActive') is True
            and report.get('heldOutputUsages') == [] and report.get('inputCount') == report.get('outputCount') == 0,
            'worker not idle/running')

def startup_worker(guest, parent, target_binding, scope, receipt, monotonic, wall, sleep):
    deadline = monotonic() + 8
    while True:
        receipt['stage']='setup.snapshot'
        require(monotonic() < deadline, 'worker startup deadline')
        require(wall() < scope.deadline, 'lease dispatch cutoff reached')
        initial = guest.snapshot()  # Frozen guards validate each read; exceptions never retry.
        require(monotonic() <= deadline, 'worker startup deadline')
        require(wall() < scope.deadline, 'lease response crossed cutoff; no replay')
        receipt['stage']='setup.snapshot-parent-check'
        observed = [p for p in initial['processes'] if p['pid'] == parent['pid']]
        require(len(observed) == 1 and all(observed[0][k] == parent[k]
                for k in ('uid', 'arguments', 'binarySHA256')), 'owned parent identity changed')
        receipt['stage']='setup.snapshot-target-check'
        target_check(initial['target'], wall(), target_binding, scope.uid)
        receipt['stage']='setup.snapshot-worker-check'
        if initial['worker'] is not None:
            return initial['worker'][0]
        remaining = min(deadline - monotonic(), scope.deadline - wall())
        require(remaining > 0, 'worker startup deadline')
        sleep(min(.2, remaining))

def measure(guest, identity, pilot, scope, scope_sha, monotonic=time.monotonic, wall=time.time, sleep=time.sleep, claim=None):
    receipt = dict(passed=False, productArchiveSHA256='dc0dfd52ad83c8c75af5f49e3653a8ba2dc269f17ac00e1b376e7b47156bf9fa', lease=scope.lease, baselineInventorySHA256=scope.baseline_sha,hardCutoffEpoch=scope.deadline,scopeSHA256=scope_sha, identityReceiptSHA256=scope.receipt_sha256,
                   productSource=scope.product_source, binarySHA256=scope.binary_sha256, targetSHA256=scope.target_sha256,
                   samples=[], stage='setup', hardwareCalls=False)
    try:
        receipt['stage']='setup.preflight'
        deployed_target = guest.startup_preflight()
        require(deployed_target['executable'] == scope.target_executable
                and deployed_target['binarySHA256'] == scope.target_sha256, 'reviewed target deployment changed')
        receipt['stage']='setup.parent-start'
        parent = guest.start()
        receipt['parentIdentity'] = {key: parent[key] for key in ('pid', 'uid', 'binarySHA256')}
        receipt['stage']='setup.fresh-target-launch'
        first = guest.fresh_capture(claim)
        receipt['stage']='setup.target-check'
        target_binding = target_check(first, wall(), uid=scope.uid)
        receipt['targetIdentity']=dict(zip(('pid','uid','nonce'),target_binding))
        receipt['targetCleanupOwner']='root; no target signal in no-input measurement'
        current = startup_worker(guest, parent, target_binding, scope, receipt, monotonic, wall, sleep)
        binding = tuple(current[k] for k in ('pid', 'uid', 'nonce'))
        receipt['stage']='setup.parent-ready'
        ready, evidence = guest.parent_ready(current)
        receipt['stage']='setup.ready-worker-check'
        worker_check(ready, binding, wall())
        receipt.update(targetIdentity=dict(zip(('pid', 'uid', 'nonce'), target_binding)),
                       workerIdentity=dict(zip(('pid', 'uid', 'nonce'), binding)), initialReadiness=evidence)
        begin = monotonic()
        def timed(stage, operation):
            receipt['stage'] = stage
            require(monotonic() - begin < 20, 'observation budget exceeded')
            start = monotonic()
            value = operation()
            elapsed = monotonic() - start
            receipt['samples'].append(dict(stage=stage, seconds=elapsed))
            require(monotonic() - begin <= 20, 'observation budget exceeded')
            return value
        for sample in range(1, 4):
            prefix = str(sample)
            verified = timed(prefix + '.identity', lambda: identity.verify(pilot, scope.lease))
            require(verified == scope.identity_tuple(), 'verified identity tuple changed')
            receipt['guestIdentity'] = verified
            snapshot = timed(prefix + '.snapshot', guest.snapshot)
            target_check(snapshot['target'], wall(), target_binding, scope.uid)
            require(snapshot['worker'] is not None, 'worker disappeared')
            current, report = snapshot['worker']
            worker_check(report, binding, wall())
            ready, evidence = timed(prefix + '.parent_ready', lambda: guest.parent_ready(current))
            worker_check(ready, binding, wall())
            target_check(snapshot['target'], wall(), target_binding, scope.uid)
            receipt['samples'][-1]['readiness'] = evidence
            receipt['samples'][-2]['targetObservedAt'] = snapshot['target']['observedAt']
            receipt['samples'][-2]['targetFocus'] = {key: snapshot['target'][key] for key in
                    ('active', 'windowKey', 'requestedResponderFocused', 'focusLost', 'focusedMode')}
        receipt['stage']='receipt-write-fsync'
        fsync_samples=benchmark_fsync(guest,current,scope)
        require(monotonic()-begin<=20,'observation budget exceeded')
        receipt['fsyncSamplesSeconds']=fsync_samples
        receipt['callbackFsyncMeasurement']=dict(method='Python same-volume receipt-pair file-and-directory fsync proxy',sampleCount=3,observedSwiftCallbackLatency=False,guaranteedFutureWorstCase=False)
        final=guest.snapshot();target_check(final['target'],wall(),target_binding,scope.uid)
        require(final['worker']is not None,'worker disappeared')
        worker_check(final['worker'][1],binding,wall())
        worker_check(guest.parent_ready(final['worker'][0])[0],binding,wall())
        require(monotonic()-begin<=20,'observation budget exceeded')
        receipt.update(passed=True, observationSeconds=monotonic() - begin,
                       version=1,identitySHA256=scope.receipt_sha256,delayMillis=750,triggerMicros=10000000,
                       snapshotWorstSeconds=max(x['seconds']for x in receipt['samples']if x['stage'].endswith('.snapshot')),
                       readyWorstSeconds=max(x['seconds']for x in receipt['samples']if x['stage'].endswith('.parent_ready')),
                       callbackFsyncWorstSeconds=max(fsync_samples),marginSeconds=.25,measuredAtEpoch=wall())
    except Exception as error:
        receipt.update(error='timing measurement refused', failureType=type(error).__name__, errorStage=receipt['stage'])
        receipt.update(selected_failure(guest,error))
        if getattr(guest,'benchmark_failure',None)is not None:receipt['benchmarkFailure']=guest.benchmark_failure
        # Never reflect arbitrary exception text. Emit only an exact reviewed
        # static source literal; substrings/prefixes/dynamic values do not match.
        safe = json.loads((ROOT / 'refusal-reasons.json').read_text())
        matched = safe.get(str(error))
        if type(error).__name__ in ('Refusal','NotReady','RuntimeError') and matched:
            receipt['refusalReason'] = matched['reason']
            receipt['refusalSource'] = matched['source']
    finally:
        receipt['stage'] = 'cleanup'
        try:
            cleanup = guest.cleanup()
            receipt['cleanup'] = dict(errorCount=len(cleanup['errors']), profileBackup=cleanup['profileBackup'],
                                      profileBytewiseRestored=cleanup['profileBytewiseRestored'])
            if cleanup['errors'] or cleanup['profileBytewiseRestored'] is not True:
                receipt['passed'] = False
        except Exception:
            receipt.update(passed=False, cleanupError='owned cleanup failed; inspect retained backup')
    return receipt

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root-reviewed-timing-setup', action='store_true')
    parser.add_argument('--attempt-dir', type=pathlib.Path)
    parser.add_argument('--scope', type=pathlib.Path)
    parser.add_argument('--scope-sha256')
    parser.add_argument('--runner-sha256')
    parser.add_argument('--bind-scope', type=pathlib.Path)
    parser.add_argument('--identity-receipt', type=pathlib.Path)
    parser.add_argument('--identity-receipt-sha256')
    parser.add_argument('--target-executable')
    parser.add_argument('--target-sha256')
    parser.add_argument('--baseline-inventory',type=pathlib.Path)
    parser.add_argument('--baseline-inventory-sha256')
    parser.add_argument('--expires-epoch',type=int)
    args = parser.parse_args()
    require(type(args.runner_sha256) is str
            and hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest() == args.runner_sha256,
            'reviewed timing runner changed')
    if args.bind_scope:
        require(not args.root_reviewed_timing_setup and args.attempt_dir is None and args.scope is None
                and args.scope_sha256 is None and args.identity_receipt is not None,
                'binding mode cannot release guest setup')
        digest = bind_scope(args.bind_scope, args.identity_receipt, args.identity_receipt_sha256,
                            args.target_executable, args.target_sha256,args.baseline_inventory,args.baseline_inventory_sha256,args.expires_epoch)
        print(json.dumps(dict(boundScope=str(args.bind_scope), scopeSHA256=digest, guestDispatch=False)))
        return 0
    require(all(v is None for v in (args.identity_receipt, args.identity_receipt_sha256,
            args.target_executable, args.target_sha256,args.baseline_inventory,args.baseline_inventory_sha256,args.expires_epoch)), 'binding arguments require binding mode')
    require(args.root_reviewed_timing_setup and args.scope is not None and args.attempt_dir is not None,
            'release/cutoff missing')
    scope, scope_sha = read_scope(args.scope, args.scope_sha256)
    require(time.time() + 180 < scope.deadline, 'release/cutoff missing')
    path = args.attempt_dir
    require(path.is_absolute() and str(path.parent) == '/private/tmp', 'private attempt namespace required')
    require(str(path)==str(path.resolve()),'linked attempt namespace refused')
    path.mkdir(mode=0o700)  # no adoption, overwrite or replay of prior attempts
    namespacefd=os.open(path.parent,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
    try:os.fsync(namespacefd)
    finally:os.close(namespacefd)
    fd = os.open(path / 'receipt.json', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        intent=json.dumps(dict(state='measurement-claimed',scopeSHA256=scope_sha,lease=scope.lease,deadline=scope.deadline)).encode()
        require(os.write(fd,intent)==len(intent),'journal write failed');os.fsync(fd)
        parentfd=os.open(path,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
        try:os.fsync(parentfd)
        finally:os.close(parentfd)
        guest, identity, pilot = dependencies(scope)
        receipt = measure(guest, identity, pilot, scope, scope_sha, claim=lambda value:fresh_capture.private_claim(path,value))
        os.lseek(fd,0,os.SEEK_SET);os.ftruncate(fd,0)
        with os.fdopen(fd, 'w') as output:
            fd = None
            output.write(json.dumps(receipt, indent=2) + '\n')
            output.flush()
            os.fsync(output.fileno())
        print(json.dumps(dict(passed=receipt['passed'], evidence=str(path / 'receipt.json'))))
        return 0 if receipt['passed'] else 79
    finally:
        if fd is not None:
            os.close(fd)

if __name__ == '__main__':
    raise SystemExit(main())
