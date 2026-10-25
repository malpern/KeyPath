#!/usr/bin/env python3
"""Bounded parent-owned remap, Secure Input and resume acceptance in an owned guest."""
import argparse,importlib.machinery,json,pathlib,shlex,subprocess,time,uuid
ROOT=pathlib.Path(__file__).resolve().parents[3]
a=argparse.ArgumentParser();a.add_argument('lease');a.add_argument('--binary-sha',required=True);a.add_argument('--remap-only',action='store_true');args=a.parse_args()
p=importlib.machinery.SourceFileLoader('parent_pilot','/private/tmp/vm-lab-hid-rig/rig/physical-baseline.py').load_module()
t=importlib.machinery.SourceFileLoader('trial',str(ROOT/'Scripts/experiments/session-runtime/physical-trial.py')).load_module()
lease=args.lease;app=t.APP;owner=None;worker=None;nonce=None;path=None;backup='/Users/keypathqa/.config/keypath/keypath.kbd.parent-backup-'+uuid.uuid4().hex;cfg='/Users/keypathqa/.config/keypath/keypath.kbd'
r={'passed':False,'lease':lease,'binarySHA256':args.binary_sha,'remapOnly':args.remap_only,'backendOptInFlagUsed':False}
def observe(cmd):return p.observe(lease,'guest-root','--','/bin/zsh','-lc','true; '+cmd+'; true')
def run(cmd):return p.lab(lease,'guest-root','--','/bin/zsh','-lc','true; '+cmd+'; true')
def prepare(secure=False):
 subprocess.run(['python3','/private/tmp/vm-lab-hid-rig/rig/prepare-target.py',lease,'--account','keypathqa']+(['--secure-test'] if secure else []),check=True)
def discover():
 result=observe('ps -axo pid=,uid=,comm= && echo KEYPATH_PROCESS_SCAN_COMPLETE').splitlines()
 if not result or result[-1]!='KEYPATH_PROCESS_SCAN_COMPLETE':raise RuntimeError('guest process scan not verified')
 rows=result[:-1];found=[]
 for row in rows:
  pieces=row.split(maxsplit=2)
  if len(pieces)==3 and pieces[1]=='501' and pieces[2]==app+'/Contents/MacOS/KeyPath':
   pid=int(pieces[0]);args=observe('ps -p '+str(pid)+' -o args=');found.append((pid,args))
 return found
def child():
 for pid,args in discover():
  if '--session-runtime' in args and '--session-owner '+str(owner)+' ' in args:
   vals=shlex.split(args);path=vals[vals.index('--session-report')+1];nonce=vals[vals.index('--session-nonce')+1]
   v=t.report(lease,path,nonce)
   if v.get('state')=='running' and v.get('tapActive'):return pid,path,nonce,v
 return None
try:
 prepare();assert not discover(),'existing KeyPath process'
 cmd='test -f '+cfg+' && test ! -e '+backup+' && cp -p '+cfg+' '+backup+' && printf %s '+shlex.quote('(defcfg)\n(defsrc q a)\n(deflayer base a a)\n')+' > '+cfg+' && chown keypathqa '+cfg+' && launchctl asuser 501 sudo -H -u keypathqa open -g -n '+shlex.quote(app)+' --args --headless'
 run(cmd)
 for _ in range(30):
  parents=[pid for pid,args in discover() if '--headless' in args and '--session-runtime' not in args]
  if len(parents)==1:owner=parents[0];break
  time.sleep(.2)
 assert owner,'parent launch missing';r['parentPID']=owner
 for _ in range(30):
  c=child()
  if c:worker,path,nonce,v=c;break
  time.sleep(.2)
 assert worker,'parent runtime not ready';r['initialWorker']=v
 for label,secure in ([('parent-remap',False)] if args.remap_only else [('parent-remap',False),('parent-secure',True)]):
  prepare(secure)
  subprocess.run(['python3',str(ROOT/'Scripts/experiments/session-runtime/physical-trial.py'),lease,'--label',label,'--mode','secure' if secure else 'remap','--expected-input','1','--binary-sha',r['binarySHA256'],'--existing-report',path,'--existing-nonce',nonce,'--owner-pid',str(owner),'--expected-worker-pid',str(worker)],check=True)
 if not args.remap_only:
  prepare()
  old=worker
  for _ in range(20):
   c=child()
   if c and c[0]!=old:worker,path,nonce,v=c;break
   time.sleep(.25)
  assert worker!=old,'secure recovery missing';r['resumedWorker']=v
  subprocess.run(['python3',str(ROOT/'Scripts/experiments/session-runtime/physical-trial.py'),lease,'--label','parent-resumed','--mode','remap','--expected-input','1','--binary-sha',r['binarySHA256'],'--existing-report',path,'--existing-nonce',nonce,'--owner-pid',str(owner),'--expected-worker-pid',str(worker)],check=True)
  prepare()
  subprocess.run(['python3',str(ROOT/'Scripts/experiments/session-runtime/physical-trial.py'),lease,'--label','parent-held-crash','--mode','held-crash','--expected-input','1','--binary-sha',r['binarySHA256'],'--existing-report',path,'--existing-nonce',nonce,'--owner-pid',str(owner),'--expected-worker-pid',str(worker)],check=True)
  r['workerCrashAccepted']=True
 r['passed']=True
except Exception as e:r['error']=str(e)
finally:
 if owner:
  try:t.stop(lease,owner)
  except Exception as e:r.update(passed=False,parentCleanupError=str(e))
 if worker and path:
  time.sleep(1)
  try:
   v=t.report(lease,path,nonce,False);r['finalWorker']=v
   if not r.get('workerCrashAccepted') and (v.get('state')!='stopped' or v.get('heldOutputUsages')!=[]):r.update(passed=False,cleanupError='worker not cleanly stopped')
  except Exception as e:r.update(passed=False,cleanupError=str(e))
 try:
  remaining=discover();r['cleanupProcessScanVerified']=True;r['remainingKeyPathPIDs']=[pid for pid,_ in remaining]
  if remaining:r.update(passed=False,cleanupError='KeyPath process remains')
 except Exception as e:r.update(passed=False,cleanupError=str(e))
 if observe('test -f '+backup+' && echo saved').strip()=='saved':
  restored=run('cp -p '+backup+' '+cfg+' && cmp -s '+backup+' '+cfg+' && rm '+backup+' && test ! -e '+backup+' && echo KEYPATH_PROFILE_RESTORED')
  r['profileRestoredVerified']=restored.strip()=='KEYPATH_PROFILE_RESTORED'
  if not r['profileRestoredVerified']:r.update(passed=False,profileCleanupError='profile restoration not independently verified')
 else:r.update(passed=False,profileCleanupError='saved original profile missing')
 destination=ROOT/'evidence/session-runtime'/('parent-campaign-'+str(int(time.time()))+'.json');destination.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r));raise SystemExit(0 if r['passed'] else 79)
