#!/usr/bin/env python3
"""Bounded parent-owned remap, Secure Input and resume acceptance in an owned guest."""
import argparse,importlib.machinery,json,os,pathlib,shlex,subprocess,time,uuid
import parent_readiness
ROOT=pathlib.Path(__file__).resolve().parents[3]
identity_module=importlib.machinery.SourceFileLoader('guest_identity',str(pathlib.Path(__file__).with_name('guest-identity.py'))).load_module()
a=argparse.ArgumentParser();a.add_argument('lease');a.add_argument('--binary-sha',required=True);a.add_argument('--remap-only',action='store_true');identity_module.add_arguments(a);args=a.parse_args();identity=identity_module.from_arguments(args);identity_args=['--guest-account',identity.account,'--guest-uid',str(identity.uid)]
RIG=pathlib.Path(os.environ.get('VM_LAB_RIG_ROOT','/private/tmp/vm-lab-hid-rig'))
if str(RIG) not in ('/private/tmp/vm-lab-hid-rig','/private/tmp/vm-lab-guest-identity'):raise RuntimeError('unreviewed rig source root')
p=importlib.machinery.SourceFileLoader('parent_pilot',str(RIG/'rig/physical-baseline.py')).load_module()
t=importlib.machinery.SourceFileLoader('trial',str(ROOT/'Scripts/experiments/session-runtime/physical-trial.py')).load_module()
t.configure_identity(identity)
lease=args.lease;app=t.APP;owner=None;worker=None;nonce=None;path=None;backup=identity.home+'/.config/keypath/keypath.kbd.parent-backup-'+uuid.uuid4().hex;cfg=identity.home+'/.config/keypath/keypath.kbd'
r={'passed':False,'lease':lease,'binarySHA256':args.binary_sha,'remapOnly':args.remap_only,'backendOptInFlagUsed':False}
launch_requested_at=None
def staged_call(stage,operation,*values,**options):
 r['stage']=stage
 return operation(*values,**options)
def verify_identity(stage):
 r['stage']=stage+'.verify'
 class IdentityPilot:
  def lab(self,*values):return staged_call(stage+'.provider-status',p.lab,*values)
  def observe(self,*values):return staged_call(stage+'.guest-identity',p.observe,*values)
 return identity.verify(IdentityPilot(),lease)
def observe(cmd,stage='observation'):
 return staged_call(stage,p.observe,lease,'guest-root','--','/bin/zsh','-lc','true; '+cmd+'; true')
def run(cmd,stage='mutation'):
 verify_identity(stage+'.identity')
 # This records dispatch intent, never command success. Mutation is still one-shot.
 r.setdefault('mutationDispatchAttempts',[]).append(stage)
 if stage=='launch':r['launchMutationAttempted']=True
 return staged_call(stage+'.dispatch',p.lab,lease,'guest-root','--','/bin/zsh','-lc','true; '+identity.guard()+' && '+cmd)
def prepare(secure=False):
 stage='prepare.secure' if secure else 'prepare.normal'
 verify_identity(stage+'.identity')
 staged_call(stage+'.target',subprocess.run,['python3',str(RIG/'rig/prepare-target.py'),lease,'--account',identity.account]+(['--secure-test'] if secure else []),check=True)
def discover(stage='discover'):
 verify_identity(stage+'.identity')
 result=observe('ps -axo pid=,uid=,comm= && echo KEYPATH_PROCESS_SCAN_COMPLETE',stage+'.process-scan').splitlines()
 if not result or result[-1]!='KEYPATH_PROCESS_SCAN_COMPLETE':raise RuntimeError('guest process scan not verified')
 rows=result[:-1];found=[]
 for row in rows:
  pieces=row.split(maxsplit=2)
  if len(pieces)==3 and pieces[1]==str(identity.uid) and pieces[2]==app+'/Contents/MacOS/KeyPath':
   pid=int(pieces[0]);args=observe('ps -p '+str(pid)+' -o args=',stage+'.process-arguments');found.append((pid,args))
 return found
def require_parent_ready(pid,path,nonce,worker_args):
 verify_identity('ready.identity')
 marker='KEYPATH_READY_READ_'+uuid.uuid4().hex
 r['stage']='ready.command-binding'
 command=parent_readiness.log_command(identity,owner,pid,nonce,path,worker_args,marker)
 output=staged_call('ready.log-and-report',p.observe,lease,'guest-root','--','/bin/zsh','-lc',command)
 r['stage']='ready.observation-framing'
 log,current=parent_readiness.split_observation(output,marker)
 r['stage']='ready.admission'
 evidence=parent_readiness.admit(log,marker,owner,pid,nonce,identity.uid,current,launch_requested_at,time.time())
 r['parentReadiness']=evidence
 return current
def child():
 for pid,args in discover('child.discovery'):
  if '--session-runtime' in args and '--session-owner '+str(owner)+' ' in args:
   r['stage']='child.argument-binding'
   vals=shlex.split(args);path=vals[vals.index('--session-report')+1];nonce=vals[vals.index('--session-nonce')+1]
   try:v=staged_call('child.worker-report',t.report,lease,path,nonce)
   except RuntimeError as error:
    if str(error) in ('session report unavailable','stale worker report'):continue
    raise
   if v.get('state')=='running' and v.get('tapActive') and v.get('pid')==pid:
    try:v=require_parent_ready(pid,path,nonce,args)
    except parent_readiness.NotReady:continue
    return pid,path,nonce,v
 return None
try:
 r['launchMutationAttempted']=False
 r['guestIdentity']=verify_identity('campaign.identity')
 prepare();assert not discover('prelaunch.discovery'),'existing KeyPath process'
 cmd=identity.guard()+' && test -f '+cfg+' && test ! -e '+backup+' && cp -p '+cfg+' '+backup+' && printf %s '+shlex.quote('(defcfg)\n(defsrc q a)\n(deflayer base a a)\n')+' > '+cfg+' && chown '+identity.account+' '+cfg+' && launchctl asuser '+str(identity.uid)+' sudo -H -u '+identity.account+' open -g -n '+shlex.quote(app)+' --args --headless'
 launch_requested_at=time.time();run(cmd,'launch')
 for _ in range(30):
  parents=[pid for pid,args in discover('parent.discovery') if '--headless' in args and '--session-runtime' not in args]
  if len(parents)==1:owner=parents[0];break
  time.sleep(.2)
 assert owner,'parent launch missing';r['parentPID']=owner
 for _ in range(30):
  c=child()
  if c:worker,path,nonce,v=c;break
  time.sleep(.2)
 assert worker,'parent runtime not ready';r['initialWorker']=v
 for label,secure in ([('parent-remap',False)] if args.remap_only else [('parent-remap',False),('parent-secure',True)]):
  # Verify completed parent startup immediately before target preparation can
  # enable Secure Input, and before a trial can load/arm physical input.
  current=child()
  if not current or current[:3]!=(worker,path,nonce):raise RuntimeError('current supervised parent startup unavailable')
  prepare(secure)
  staged_call('physical.'+label,subprocess.run,['python3',str(ROOT/'Scripts/experiments/session-runtime/physical-trial.py'),lease,'--label',label,'--mode','secure' if secure else 'remap','--expected-input','1','--binary-sha',r['binarySHA256'],'--existing-report',path,'--existing-nonce',nonce,'--owner-pid',str(owner),'--expected-worker-pid',str(worker)]+identity_args,check=True)
 if not args.remap_only:
  prepare()
  old=worker
  for _ in range(20):
   c=child()
   if c and c[0]!=old:worker,path,nonce,v=c;break
   time.sleep(.25)
  assert worker!=old,'secure recovery missing';r['resumedWorker']=v
  staged_call('physical.parent-resumed',subprocess.run,['python3',str(ROOT/'Scripts/experiments/session-runtime/physical-trial.py'),lease,'--label','parent-resumed','--mode','remap','--expected-input','1','--binary-sha',r['binarySHA256'],'--existing-report',path,'--existing-nonce',nonce,'--owner-pid',str(owner),'--expected-worker-pid',str(worker)]+identity_args,check=True)
  prepare()
  staged_call('physical.parent-held-crash',subprocess.run,['python3',str(ROOT/'Scripts/experiments/session-runtime/physical-trial.py'),lease,'--label','parent-held-crash','--mode','held-crash','--expected-input','1','--binary-sha',r['binarySHA256'],'--existing-report',path,'--existing-nonce',nonce,'--owner-pid',str(owner),'--expected-worker-pid',str(worker)]+identity_args,check=True)
  r['workerCrashAccepted']=True
 r['passed']=True
except Exception as e:r.update(error=str(e),errorStage=r.get('stage'))
finally:
 if owner:
  try:staged_call('cleanup.parent-stop',t.stop,lease,owner)
  except Exception as e:r.update(passed=False,parentCleanupError=str(e),parentCleanupStage=r.get('stage'))
 if worker and path:
  time.sleep(1)
  try:
   v=staged_call('cleanup.worker-report',t.report,lease,path,nonce,False);r['finalWorker']=v
   if not r.get('workerCrashAccepted') and (v.get('state')!='stopped' or v.get('heldOutputUsages')!=[]):r.update(passed=False,cleanupError='worker not cleanly stopped')
  except Exception as e:r.update(passed=False,cleanupError=str(e))
 try:
  remaining=discover('cleanup.discovery');r['cleanupProcessScanVerified']=True;r['remainingKeyPathPIDs']=[pid for pid,_ in remaining]
  if remaining:r.update(passed=False,cleanupError='KeyPath process remains')
 except Exception as e:r.update(passed=False,cleanupError=str(e))
 if observe(identity.guard()+' && test -f '+backup+' && echo saved','cleanup.profile-backup-read').strip()=='saved':
  restored=run(identity.guard()+' && cp -p '+backup+' '+cfg+' && cmp -s '+backup+' '+cfg+' && rm '+backup+' && test ! -e '+backup+' && echo KEYPATH_PROFILE_RESTORED','cleanup.profile-restore')
  r['profileRestoredVerified']=restored.strip()=='KEYPATH_PROFILE_RESTORED'
  if not r['profileRestoredVerified']:r.update(passed=False,profileCleanupError='profile restoration not independently verified')
 else:r.update(passed=False,profileCleanupError='saved original profile missing')
 destination=ROOT/'evidence/session-runtime'/('parent-campaign-'+str(int(time.time()))+'.json');destination.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r));raise SystemExit(0 if r['passed'] else 79)
