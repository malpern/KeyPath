#!/usr/bin/env python3
"""Source-only timeout executor candidate; import is inert, physical release separate."""
import prepared_identity as prepared
import argparse,hashlib,importlib.util,json,math,os,pathlib,re,shlex,sys,time,uuid
H_PATH=pathlib.Path('/private/tmp/keypath-d8-readonly-transport-candidate/Scripts/experiments/session-runtime/held-secure-acceptance.py')
D7_PATH=pathlib.Path('/private/tmp/keypath-guest-identity/Scripts/experiments/session-runtime/d7-fixture.py')
RIG=pathlib.Path('/private/tmp/vm-lab-guest-identity')
CONFIG='(defcfg)\n(defsrc q a)\n(deflayer base a a)\n'
TIMED=[(0,[0,20,0,0,0,0,0]),(10000000,[0,20,5,0,0,0,0]),(10050000,[0,20,0,0,0,0,0]),(45000000,[0]*7)]
DELAY=750
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
PINS={'/private/tmp/keypath-d8-readonly-transport-candidate/Scripts/experiments/session-runtime/held-secure-acceptance.py': 'd2907c9e0d9b62c0a555273e14cd3aef12491aa53507f4633dcd06fea75dabf2', '/private/tmp/keypath-d8-readonly-transport-candidate/Scripts/experiments/session-runtime/held_secure_predicates.py': '14fbed279df894085a39350e26d9de05528bdacbdf4a36306ecaed6b849d2de5', '/private/tmp/keypath-d8-readonly-transport-candidate/Scripts/experiments/session-runtime/parent_readiness.py': '69e69782c338a36768233fddcdadac54ea2b908a25d39ec84b9b4bcd6ee19f6b', '/private/tmp/keypath-guest-identity/Scripts/experiments/session-runtime/d7-fixture.py': 'c371991519f81292abf8b188720be7afd959225acc38112143fed5f2e75c928a', '/private/tmp/keypath-guest-identity/Scripts/experiments/session-runtime/guest-identity.py': 'dcafa2ad7ce7e94d779a4a332bf9a2231ed13f171cc5671ca132b8539fcb8637', '/private/tmp/vm-lab-guest-identity/rig/physical-baseline.py': '1082f5f411c3253f936f75672bd996d4b37bf38b5181d8500d278f5339e2a87a', '/private/tmp/vm-lab-guest-identity/rig/declared_identity.py': '657ea9673d4786b810d731c5d7506cd0c44109d229045557117076a07b4271f2'}
PINS.update({'/private/tmp/vm-lab-target-typed-booleans/SHA256SUMS':'7f5172f7a3354ca517679523a5f1cb26ff83096a8750b88be3dd560d269a1b89','/private/tmp/vm-lab-target-typed-booleans/rig/capture-target.m':'ec98a707195c3a732ada926f0f1ec8c12b2d497f1497dbb4ea6744334582b8bc'})
PINS[str(pathlib.Path(__file__).with_name('parent_readiness.py'))]='07bccc32ac73ab7984eae1d76136174b35da97e3fd79c80b7169daca904c8074'
PINS[str(pathlib.Path(__file__).with_name('prepared_identity.py'))]='575bd1a5d3d7057f216f2abcc4da1d5bf511ba88362da71ddb6e7f8d4ff7100d'
_LOCAL_READINESS_MODULE=None
def local_readiness():
    global _LOCAL_READINESS_MODULE
    path=pathlib.Path(__file__).with_name('parent_readiness.py')
    require(hashlib.sha256(path.read_bytes()).hexdigest()==PINS[str(path)],'local readiness collector changed')
    if _LOCAL_READINESS_MODULE is None:_LOCAL_READINESS_MODULE=module(path,'timeout_alias_readiness')
    return _LOCAL_READINESS_MODULE
def require(v,reason):
    if not v:raise RuntimeError(reason)
def module(path,name):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);sys.modules[name]=m;spec.loader.exec_module(m);return m
def dependencies():
    for p,d in PINS.items():require(hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()==d,'frozen dependency changed')
    sys.path.insert(0,str(H_PATH.parent));return module(H_PATH,'timeout_base')
def normal(t):
    require(all(t.get(k)is v for k,v in [('active',True),('windowKey',True),('focusLost',False),('secureTest',False),('secureInputEnabled',False),('requestedResponderFocused',True)]) and t.get('focusedMode')=='normal','normal target focus changed')
def hold(s,run,prefix):
    require(s.get('runId')==run and s.get('state')=='running' and type(s.get('reportsSubmitted'))is int and s['reportsSubmitted']==prefix,'physical held-q prefix unavailable')
def terminal(r,identity,baseline,now,prior=None):
    require(tuple(r.get(k)for k in('pid','uid','nonce'))==tuple(identity[k]for k in('pid','uid','nonce')),'terminal generation mismatch')
    if r.get('state')=='running':return None
    if r.get('failure')=='tap-disabled-observed':raise RuntimeError('inconclusive: timer-only disabled observation')
    require(r.get('state')=='failed' and r.get('failure')=='tap-disabled-by-timeout' and r.get('tapActive')is False and r.get('heldOutputUsages')==[],'actual OS timeout terminal unavailable')
    stamp=r.get('timestamp');require(type(stamp)in(int,float) and math.isfinite(stamp) and baseline<stamp+978307200<=now and now-stamp-978307200<3,'first terminal freshness unavailable')
    require(prior is None or prior==r,'first terminal changed');return r

def released(t,before,r,s,run,exited):
    normal(t);hold(s,run,3)
    require(exited is True and 0 in before['held'] and 0 not in t['held'] and t['ups']>before['ups'] and t['aDowns']==before['aDowns'] and t['observedAt']>=r['timestamp']+978307200,'independent a-up before physical q-up unavailable')
def timing(v,binary,receipt,now):
    cleanup=v.get('cleanup');require(v.get('passed')is True and type(cleanup)is dict and type(cleanup.get('errorCount'))is int and cleanup['errorCount']==0 and cleanup.get('profileBytewiseRestored')is True,'successful timing receipt and cleanup required')
    require(type(v.get('version'))is int and v.get('version')==1 and v.get('binarySHA256')==binary and v.get('identitySHA256')==receipt and v.get('delayMillis')==750 and v.get('triggerMicros')==10000000,'timing scope mismatch')
    for k in('snapshotWorstSeconds','readyWorstSeconds','callbackFsyncWorstSeconds','marginSeconds','measuredAtEpoch'):
        require(type(v.get(k))in(int,float) and math.isfinite(v[k]) and v[k]>=0,'finite measured timing required')
    require(0<=now-v['measuredAtEpoch']<3600 and 2*v['snapshotWorstSeconds']+v['readyWorstSeconds']+v['marginSeconds']<9 and .5+.75+v['callbackFsyncWorstSeconds']+v['marginSeconds']<2,'measured timing window unavailable')
def delay_evidence(v,worker,parent):
    for phase in('entered','returned'):
        r=v.get(phase,{});require(all(type(r.get(k))is int for k in('version','sequence','pid','uid','parentPID','durationMillis')) and r.get('phase')==phase and r.get('version')==1 and r.get('sequence')==1 and r.get('durationMillis')==750 and tuple(r.get(k)for k in('pid','uid','nonce'))==tuple(worker[k]for k in('pid','uid','nonce')) and r.get('parentPID')==parent and type(r.get('monotonicNanos'))is int and r['monotonicNanos']>0,'delay receipt identity mismatch')
    require(v['returned']['monotonicNanos']>=v['entered']['monotonicNanos'],'delay clock regressed')

def start_target(t,now):
    normal(t);require(t.get('held')==[] and type(t.get('modifiers'))is int and t['modifiers']==0 and t.get('combinedSessionControl')is False and type(t.get('observedAt'))in(int,float) and 0<=now-t['observedAt']<3,'fresh all-up target required before input')

def scoped_client(client,expiry,save,before_start=None):
    request=client._client.request;claimed=set()
    def guarded(method,path,*args,**kwargs):
        require((method,path)in{('GET','/v1/status'),('POST','/v1/script'),('POST','/v1/arm'),('POST','/v1/start'),('POST','/v1/abort')} or method=='GET' and re.fullmatch(r'/v1/trace\?from=[0-9]+&limit=[1-8]',path),'fixture route outside scope')
        require(time.time()<expiry,'fixture dispatch cutoff reached')
        if method=='POST':
            key=(client._run,path);require(key not in claimed,'mutation replay refused');claimed.add(key)
            save('fixture-dispatch-intent',dict(runId=client._run,method=method,path=path,expiresEpoch=expiry))
            if path=='/v1/start':
                require(before_start is not None,'physical start admission absent');before_start()
                require(expiry-time.time()>=120,'physical start cleanup reserve unavailable')
            require(time.time()<expiry,'fixture cutoff after journal; no dispatch')
        result=request(method,path,*args,**kwargs);require(time.time()<expiry,'fixture response crossed cutoff; no replay');return result
    client._client.request=guarded;return client

def classes(H):
    class Guest(H.Guest):
        READ_STAGES=H.Guest.READ_STAGES+('timeout.receipts',)
        def preflight(self,target):
            result=super().preflight(target)
            require(result.get('executable')==self.home+'/Applications/VM Lab Rig Target.app/Contents/MacOS/RigTarget','prepared target deployment path changed')
            return result
        def run(self,c):
            self.check_account();return self.pilot.lab(self.lease,'guest-root','--','/bin/zsh','-lc','true; if ! ( '+self.guest_identity.guard()+' ); then exit 79; fi; { '+c+'; }')
        def processes(self):
            result=[]
            for row in self.read('/bin/ps -ww -axo pid=,uid=,comm=','processes.table').splitlines():
                v=row.split(maxsplit=2)
                if len(v)==3 and v[2]==self.exe:
                    require(v[0].isdigit() and v[1].isdigit(),'malformed selected process');result.append((int(v[0]),int(v[1]),shlex.split(self.read('/bin/ps -ww -p '+v[0]+' -o args=','processes.arguments'))))
            return result
        def identity(self,pid,args):
            require(type(pid)is int and pid>0,'invalid owned PID')
            for option,wanted in [('uid',str(self.uid)),('comm',self.exe)]:require(self.read(f'/bin/ps -ww -p {pid} -o {option}=','identity.process').strip()==wanted,'owned process changed')
            raw=self.read(f'/bin/ps -ww -p {pid} -o args=','identity.arguments').strip();require(shlex.split(raw)==args,'owned arguments changed')
            require(self.read('shasum -a 256 '+shlex.quote(self.exe),'identity.hash').split()[0]==self.binary_sha,'owned binary changed')
            return dict(pid=pid,uid=self.uid,arguments=args,rawArguments=raw,binarySHA256=self.binary_sha)
        def parent_ready(self, identity):
            readiness = local_readiness()
            require(self.parent is not None and self.parent_launch_requested_at is not None,
                    'parent launch evidence unavailable')
            self.observation_scope()
            marker = 'KEYPATH_READY_READ_' + uuid.uuid4().hex
            command = readiness.log_command(self.guest_identity, self.parent, identity['pid'],
                                            identity['nonce'], identity['reportPath'],
                                            identity['rawArguments'], marker)
            output = self.pilot.observe(self.lease, 'guest-root', '--', '/bin/zsh', '-lc', command)
            log, current = readiness.split_observation(output, marker)
            evidence = readiness.admit(log, marker, self.parent, identity['pid'], identity['nonce'],
                                       self.uid, current, self.parent_launch_requested_at, time.time())
            return current, evidence

        def start(self):
            self.check_account()
            self.run('test -f ' + shlex.quote(self.profile) + ' && test ! -e ' + shlex.quote(self.backup)
                     + ' && cp -p ' + shlex.quote(self.profile) + ' ' + shlex.quote(self.backup))
            self.backed_up = True
            self.check_account()
            self.parent_launch_requested_at = time.time()
            self.run('printf %s ' + shlex.quote(CONFIG) + ' > ' + shlex.quote(self.profile)
                     + ' && chown ' + shlex.quote(self.account) + ' ' + shlex.quote(self.profile)
                     + ' && launchctl asuser ' + str(self.uid) + ' sudo -H -u ' + shlex.quote(self.account) + ' open -n '
                     + shlex.quote(self.app) + ' --args --headless')
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                rows = self.processes()
                require(time.monotonic() < deadline, 'parent discovery overran deadline')
                parents = [(pid, args) for pid, uid, args in rows
                           if uid == self.uid and '--headless' in args and '--session-runtime' not in args]
                require(len(parents) <= 1, 'ambiguous parent launch')
                if parents:
                    self.parent, self.parent_args = parents[0]
                    identity = self.identity(self.parent, self.parent_args)
                    require(time.monotonic() < deadline, 'parent identity overran deadline')
                    return identity
                time.sleep(.2)
            raise H.Refusal('parent launch deadline')

        def cleanup(self):
            if getattr(self,'cleanup_attempted',False):return dict(errors=['owner cleanup already attempted; no mutation replay'],profileBackup=self.backup,profileBytewiseRestored=False)
            self.cleanup_attempted=True
            return super().cleanup()
        def arm_delay(self,w):
            c=dict(version=1,sequence=1,pid=w['pid'],uid=self.uid,parentPID=self.parent,nonce=w['nonce'],binarySHA256=self.binary_sha,configSHA256=hashlib.sha256(CONFIG.encode()).hexdigest(),expiresEpoch=int(time.time())+25,durationMillis=750,triggerKeyCode=11)
            code=SCOPED_DIRECTORY_CODE+'''import sys,json
original=pathlib.Path(sys.argv[1]);command=json.loads(sys.argv[2]);rawdir=original.parent
d,owned=scoped_directory(rawdir,502,command['nonce']);p=d/original.name;s=d.lstat()
assert p.name=='tap-timeout-command.json'
recheck_directory(rawdir,502,command['nonce'],d,owned)
fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
try:
 os.fchown(fd,502,s.st_gid);raw=sys.argv[2].encode();assert os.write(fd,raw)==len(raw);os.fsync(fd)
finally:os.close(fd)
fd=os.open(d,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
try:os.fsync(fd)
finally:os.close(fd)
recheck_directory(rawdir,502,command['nonce'],d,owned)
'''
            self.identity(w['pid'],w['arguments']);path=str(pathlib.PurePosixPath(w['reportPath']).parent/'tap-timeout-command.json')
            self.run(shlex.quote(H.GUEST_PYTHON)+' -I -B -c '+shlex.quote(code)+' '+shlex.quote(path)+' '+shlex.quote(json.dumps(c,sort_keys=True,separators=(',',':'))));return c
        def receipts(self,w):
            code=SCOPED_DIRECTORY_CODE+'''import json,sys
out={};rawdir=pathlib.Path(sys.argv[1]);nonce=sys.argv[2]
d,owned=scoped_directory(rawdir,502,nonce)
for phase in ('entered','returned'):
 recheck_directory(rawdir,502,nonce,d,owned)
 p=d/('tap-timeout-delay-'+phase+'.json')
 fd=os.open(p,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
 try:
  s=os.fstat(fd);assert stat.S_ISREG(s.st_mode) and s.st_uid==502 and s.st_nlink==1 and stat.S_IMODE(s.st_mode)==0o600 and 0<s.st_size<4096
  raw=os.read(fd,4097);meta=lambda v:(v.st_dev,v.st_ino,v.st_mode,v.st_uid,v.st_gid,v.st_size,v.st_nlink,v.st_mtime_ns,v.st_ctime_ns)
  assert meta(s)==meta(os.fstat(fd))==meta(p.lstat());out[phase]=json.loads(raw)
 finally:os.close(fd)
recheck_directory(rawdir,502,nonce,d,owned)
print(json.dumps(out))
'''
            return json.loads(self.read(shlex.quote(H.GUEST_PYTHON)+' -I -B -c '+shlex.quote(code)+' '+shlex.quote(str(pathlib.PurePosixPath(w['reportPath']).parent))+' '+shlex.quote(w['nonce']),'timeout.receipts'))
    class Campaign(H.Campaign):
        def save(self,label,value):
            name=super().save(label,value)
            fd=os.open(self.destination/name,os.O_RDONLY|os.O_NOFOLLOW)
            try:os.fchmod(fd,0o600);os.fsync(fd)
            finally:os.close(fd)
            fd=os.open(self.destination,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
            try:os.fsync(fd)
            finally:os.close(fd)
            return name
        def start_input(self,rows,phase=None):
            self.guest.check_account();require(self.client.status().get('state')in('idle','complete','aborted'),'foreign fixture campaign')
            run='session-'+uuid.uuid4().hex[:16];self.active_run=run;self.save('fixture-script-intent',dict(runId=run,timedReports=rows))
            self.client.load_script(H.script(run,rows));self.client.arm(run);self.guest.check_account()
            t=self.target();start_target(t,time.time())
            if phase:self.history.begin(phase,t)
            self.client.start(run,500);return run
        def execute(self):
            t=self.target();normal(t);require(t['held']==[] and t['modifiers']==0 and t['combinedSessionControl']is False and t['downs']==t['ups']==0 and t['text']=='' and t['secureLength']==0,'fresh empty normal target required')
            self.record['targetIdentity']=self.guest.preflight(t);self.record['usbBefore']=self.guest.pilot.verify_usb(self.guest.lease);self.record['parentIdentity']=self.guest.start()
            def ready(_):
                found=self.latest['worker']
                if not found or found[1].get('state')!='running':return None
                try:r,e=self.guest.parent_ready(found[0])
                except local_readiness().NotReady:return None
                H.worker(r,tuple(found[0][k]for k in('pid','uid','nonce')),time.time());require(r['heldOutputUsages']==[],'new ledger not empty');return dict(identity=found[0],report=r,parentReadiness=e)
            _,old=self.wait('initial-ready',ready,8);self.save('delay-command-intent',old['identity']);self.save('delay-command',self.guest.arm_delay(old['identity']))
            run=self.start_input(TIMED,'timeout')
            def held(t):
                normal(t);found=self.latest['worker'];require(found is not None and found[0]['pid']==old['identity']['pid'],'worker absent before trigger')
                if found[1].get('heldOutputUsages')!=[4] or 0 not in t['held']:return None
                hold(self.client.status(),run,1);return dict(target=t,report=found[1])
            _,baseline=self.wait('a-held',held,7);self.first_terminal=None
            def release(t):
                r=terminal(self.latest['oldReport'],old['identity'],baseline['target']['observedAt'],time.time(),self.first_terminal)
                if r is None:return None
                if self.first_terminal is None:self.first_terminal=r;self.save('first-terminal',r)
                if self.latest['oldExited']is not True:return None
                released(t,baseline['target'],r,self.client.status(),run,True);return dict(target=t,report=r)
            _,accepted=self.wait('actual-timeout-release',release,15,old=old['identity'])
            receipts=self.guest.receipts(old['identity']);delay_evidence(receipts,old['identity'],self.guest.parent);self.save('delay-receipts',receipts)
            self.finish_input(TIMED,50);self.accept_phase('timeout',accepted)
            tap=[(0,[0,20,0,0,0,0,0]),(80000,[0]*7)]
            before=self.target();require(self.latest['worker']is None and before['held']==[],'old generation not stopped');self.start_input(tap);self.finish_input(tap,8);after=self.target();normal(after)
            require(self.latest['worker']is None and after['held']==[] and after['qDowns']-before['qDowns']==1 and after['aDowns']==before['aDowns'] and after['downs']-before['downs']==after['ups']-before['ups']==1,'fail-open q unbalanced');self.save('fail-open',dict(before=before,after=after))
            cleanup=self.guest.cleanup();require(not cleanup['errors'],'old owner cleanup failed');old_parent=self.guest.parent
            self.guest=Guest(self.guest.lease,self.guest.pilot,self.guest.binary_sha,self.guest.target_sha,self.guest.guest_identity);self.guest.preflight(after);self.guest.start()
            require(self.guest.parent!=old_parent,'new parent PID reused');_,new=self.wait('new-parent-ready',ready,8);require(new['identity']['pid']!=old['identity']['pid'] and new['identity']['nonce']!=old['identity']['nonce'],'worker generation reused')
            before=self.target();self.start_input(tap);self.finish_input(tap,8);after=self.target();normal(after)
            require(after['held']==[] and after['aDowns']-before['aDowns']==1 and after['qDowns']==before['qDowns'] and after['downs']-before['downs']==after['ups']-before['ups']==1,'recovery remap unbalanced')
            self.record.update(passed=True,recoveryScope='new-parent-only',untested=['same-parent recovery','sleep/wake','console departure'])
    return Guest,Campaign

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('lease')
    for flag in('artifact-manifest','timing-receipt','destination'):p.add_argument('--'+flag,type=pathlib.Path,required=True)
    for flag in('artifact-manifest-sha','timing-sha','target-sha','guest-identity-sha'):p.add_argument('--'+flag,required=True)
    p.add_argument('--baseline-inventory',type=pathlib.Path,required=True);p.add_argument('--baseline-inventory-sha',required=True);p.add_argument('--expires-epoch',type=int,required=True);p.add_argument('--reviewed-execution',action='store_true')
    H=dependencies();I=H.load_module(H.IDENTITY_MODULE,'timeout_identity');I.add_arguments(p);a=p.parse_args()
    require(a.reviewed_execution,'physical release not granted')
    for path,digest in[(a.artifact_manifest,a.artifact_manifest_sha),(a.timing_receipt,a.timing_sha)]:require(re.fullmatch('[0-9a-f]{64}',digest) and hashlib.sha256(path.read_bytes()).hexdigest()==digest,'declared pin changed')
    artifact=json.loads(a.artifact_manifest.read_text());binary=artifact.get('mainSHA256');require(binary=='82a8d104093b8080daa97d02f26e004dd257b784f57247ca224797885bc7a6d2','reviewed main pin changed')
    require(artifact.get('sourceCommit')=='4111b0de3e149bbe458ce527d959a78d1e2a1b42' and artifact.get('compileFlag')=='KEYPATH_TAP_TIMEOUT_EXPERIMENT' and artifact.get('strictSignatureVerified')is True and artifact.get('teamID')=='X2RKZ5TG99' and isinstance(binary,str) and re.fullmatch('[0-9a-f]{64}',binary) and len(set(binary))>1 and re.fullmatch('[0-9a-f]{64}',artifact.get('archiveSHA256','')),'declared experimental artifact unavailable')
    require(a.target_sha=='55c8fa008280633ecf6137d7d47df27e152b16a8ba37bbf01dca4c7ab4ef4858','reviewed target pin changed')
    identity=prepared.load(a.guest_identity_receipt,a.guest_identity_sha,a.baseline_inventory,a.baseline_inventory_sha,a.expires_epoch);require(a.guest_account in (None,identity.account) and a.guest_uid in (None,identity.uid),'declared prepared account changed');require(identity.uid==502 and identity.receipt_path and identity.receipt_sha256 and identity.provider_uuid and identity.boot_epoch and identity.lease==a.lease,'full public identity required')
    require(re.fullmatch('[0-9a-f]{64}',a.guest_identity_sha) and identity.receipt_sha256==a.guest_identity_sha,'declared guest identity pin changed')
    timing(json.loads(a.timing_receipt.read_text()),binary,identity.receipt_sha256,time.time())
    require(a.expires_epoch-time.time()>120,'campaign expiry headroom unavailable')
    pilot=prepared.bind_pilot(module(RIG/'rig/physical-baseline.py','timeout_pilot'),identity,a.expires_epoch)
    status=pilot.lab(a.lease,'status');prepared.admit_provider(status,identity,a.expires_epoch,time.time())
    require(str(a.destination)==str(a.destination.resolve()),'linked evidence namespace refused');a.destination.mkdir(mode=0o700,parents=True,exist_ok=False)
    parentfd=os.open(a.destination.parent,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
    try:os.fsync(parentfd)
    finally:os.close(parentfd)
    G,C=classes(H);H.CONFIG=CONFIG;guest=G(a.lease,pilot,binary,a.target_sha,identity)
    factory=module(D7_PATH,'timeout_fixture');campaign=C(guest,factory.create_client(),a.destination)
    campaign.client=scoped_client(campaign.client,a.expires_epoch,campaign.save,lambda:start_target(campaign.target(),time.time()))
    campaign.record.update(baselineInventorySHA256=a.baseline_inventory_sha,identitySHA256=identity.receipt_sha256,hardCutoffEpoch=a.expires_epoch,binarySHA256=binary,artifactManifestSHA256=a.artifact_manifest_sha,timingSHA256=a.timing_sha,requestedDelayMillis=750,triggerMicros=10000000)
    try:campaign.execute()
    except Exception as error:campaign.record.update(passed=False,error=str(error),failureType=type(error).__name__)
    finally:
        campaign.cleanup()
        with (a.destination/'campaign.json').open('x')as f:os.fchmod(f.fileno(),0o600);json.dump(campaign.record,f,indent=2);f.flush();os.fsync(f.fileno())
    print(json.dumps(dict(passed=campaign.record['passed'],evidence=str(a.destination))));return 0 if campaign.record['passed']else 79
if __name__=='__main__':raise SystemExit(main())
