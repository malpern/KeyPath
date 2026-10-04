#!/usr/bin/env python3
"""Fixed ESP32 samples against the signed KeyPath session worker, guest only."""
import argparse,hashlib,importlib.machinery,json,os,pathlib,shlex,subprocess,time,uuid,zlib
ROOT=pathlib.Path(__file__).resolve().parents[3]
RIG=pathlib.Path(os.environ.get('VM_LAB_RIG_ROOT','/private/tmp/vm-lab-hid-rig'))
if str(RIG) not in ('/private/tmp/vm-lab-hid-rig','/private/tmp/vm-lab-guest-identity'):raise RuntimeError('unreviewed rig source root')
pilot=importlib.machinery.SourceFileLoader('pilot',str(RIG/'rig/physical-baseline.py')).load_module()
stability=importlib.machinery.SourceFileLoader('stability',str(RIG/'rig/startup-stability.py')).load_module()
identity_module=importlib.machinery.SourceFileLoader('guest_identity',str(pathlib.Path(__file__).with_name('guest-identity.py'))).load_module()
IDENTITY=identity_module.GuestIdentity();APP=IDENTITY.app
def configure_identity(identity):
 global IDENTITY,APP
 IDENTITY=identity;APP=identity.app
def report(lease,path,nonce,fresh=True):
 IDENTITY.verify(pilot,lease)
 values=pilot.objects(pilot.observe(lease,'guest-root','--','/bin/zsh','-lc','true; '+IDENTITY.guard()+' && cat '+shlex.quote(path)+' 2>/dev/null; printf "\\n"; true'))
 if len(values)!=1:raise RuntimeError('session report unavailable')
 value=values[0]
 if value.get('nonce')!=nonce or value.get('uid')!=IDENTITY.uid or type(value.get('pid')) is not int or value['pid']<=0:raise RuntimeError('worker identity mismatch')
 if fresh and not 0<=time.time()-(value.get('timestamp',0)+978307200)<3:raise RuntimeError('stale worker report')
 return value
def stop(lease,pid,nonce=None,owner=None):
 IDENTITY.verify(pilot,lease)
 if type(pid) is not int or pid<=0:raise RuntimeError('invalid owned stop PID')
 process_command='true; rows=$(ps -axo pid=) || exit 79; printf \'%s\\n\' "$rows" | awk -v expected=__PID__ -v observer=$$ \'NF != 1 || $1 !~ /^[1-9][0-9]*$/ {bad=1} $1 == observer {seen=1} $1 == expected {found=1} END {if (bad || !seen) exit 2; exit !found}\'; scan_result=$?; if test "$scan_result" = 0; then ps -p __PID__ -o args= || exit 79; printf \'\\nKEYPATH_PROCESS_PRESENT\\n\'; elif test "$scan_result" = 1; then printf KEYPATH_PROCESS_ABSENT; else exit 79; fi'.replace('__PID__',str(pid))
 process_observation=pilot.observe(lease,'guest-root','--','/bin/zsh','-lc',process_command).strip()
 if process_observation=='KEYPATH_PROCESS_ABSENT':return
 if not process_observation.endswith('\nKEYPATH_PROCESS_PRESENT'):raise RuntimeError('owned stop process observation unavailable')
 process_args_raw=process_observation.removesuffix('\nKEYPATH_PROCESS_PRESENT').strip()
 process_args=shlex.split(process_args_raw)
 if nonce is not None:
  if '--session-nonce' not in process_args or process_args[process_args.index('--session-nonce')+1]!=nonce:raise RuntimeError('owned stop nonce mismatch')
 elif '--headless' not in process_args or '--session-runtime' in process_args:raise RuntimeError('owned parent stop arguments mismatch')
 if owner is not None and ('--session-owner' not in process_args or process_args[process_args.index('--session-owner')+1]!=str(owner)):raise RuntimeError('owned stop parent mismatch')
 pilot.lab(lease,'guest-root','--','/bin/zsh','-lc','true; '+IDENTITY.guard()+' && if test "$(ps -p '+str(pid)+' -o uid= | tr -d " ")" = '+str(IDENTITY.uid)+' && test "$(ps -p '+str(pid)+' -o comm=)" = '+shlex.quote(APP+'/Contents/MacOS/KeyPath')+' && test "$(ps -p '+str(pid)+' -o args=)" = '+shlex.quote(process_args_raw)+'; then kill -TERM '+str(pid)+'; else exit 79; fi')
 for attempt in range(10):
  alive=pilot.observe(lease,'guest-root','--','/bin/zsh','-lc','true; kill -0 '+str(pid)+' 2>/dev/null && echo live; true').strip()
  if not alive:return
  time.sleep(.2)
 raise RuntimeError('owned worker did not exit after graceful stop')
def main():
 global IDENTITY,APP
 p=argparse.ArgumentParser();p.add_argument('lease');p.add_argument('--label',required=True);p.add_argument('--mode',choices=['remap','hrm-tap','hrm-hold','unmapped','secure','denied','repeat','held-crash'],default='remap');p.add_argument('--binary-sha',required=True);p.add_argument('--expected-input',type=int,choices=[0,1]);p.add_argument('--caps-via-f18',action='store_true');p.add_argument('--existing-report');p.add_argument('--existing-nonce');p.add_argument('--owner-pid',type=int);p.add_argument('--expected-worker-pid',type=int);identity_module.add_arguments(p);a=p.parse_args();configure_identity(identity_module.from_arguments(a))
 external=bool(a.existing_report or a.existing_nonce or a.owner_pid)
 if external:
  import re
  if not (a.existing_report and a.existing_nonce and a.owner_pid and a.owner_pid>0 and a.expected_worker_pid and a.expected_worker_pid>0) or a.mode not in ('remap','secure','held-crash') or a.caps_via_f18:raise RuntimeError('invalid parent trial')
  if not re.fullmatch(r'/var/folders/[A-Za-z0-9_/-]+/T/keypath-session-'+re.escape(a.existing_nonce)+r'/report.json',a.existing_report):raise RuntimeError('invalid parent report path')
  uuid.UUID(a.existing_nonce)
 if a.mode=='held-crash' and not external:raise RuntimeError('held crash requires a previously observed parent-owned worker')
 if a.caps_via_f18 and a.mode not in ('remap','hrm-tap','hrm-hold'):raise RuntimeError('invalid Caps Lock sample mode')
 if not a.label.replace('-','').isalnum() or len(a.binary_sha)!=64:raise RuntimeError('invalid provenance')
 nonce=str(uuid.uuid4());run='session-'+uuid.uuid4().hex[:16];path=IDENTITY.home+'/session-'+nonce+'.json';config=IDENTITY.home+'/session-'+nonce+'.kbd'
 if external:nonce=a.existing_nonce;path=a.existing_report
 record={'passed':False,'lease':a.lease,'mode':a.mode,'runId':run,'nonce':nonce,'binarySHA256':a.binary_sha,'physicalUSB':True,'capsViaF18':a.caps_via_f18};client=None;pid=None;owned=False
 destination=ROOT/'evidence/session-runtime'/f'{a.lease}-{a.label}-{run}.json';destination.parent.mkdir(parents=True,exist_ok=True)
 try:
  record['stage']='identity';record['guestIdentity']=IDENTITY.verify(pilot,a.lease);boot=stability.require(a.lease,IDENTITY.account);record['bootEpoch']=boot;record['usb']=pilot.verify_usb(a.lease)
  digest=pilot.observe(a.lease,'guest-root','--','/bin/zsh','-lc','true; shasum -a 256 "'+APP+'/Contents/MacOS/KeyPath"; codesign --verify --strict "'+APP+'" 2>/dev/null').split()[0]
  if digest!=a.binary_sha:raise RuntimeError('signed app binary mismatch')
  before=pilot.state(a.lease,IDENTITY.account)
  if not pilot.ready(before) or before.get('downs') or before.get('ups') or before.get('text') or before.get('secureLength') or bool(before.get('secureTest'))!=(a.mode=='secure'):raise RuntimeError('fresh independent target required')
  record['before']=before
  fixture=importlib.machinery.SourceFileLoader('fixture',str(pathlib.Path.home()/'local-code/keypath-pico-hid-fixture/Scripts/lab/pico-hid-fixture-client')).load_module()
  if a.mode=='hrm-hold':
   payload='0 0 20 0 0 0 0 0\n300000 0 20 4 0 0 0 0\n340000 0 20 0 0 0 0 0\n400000 0 0 0 0 0 0 0\n';script=f'KPHID1 {run} 4 1 700000 {zlib.crc32(payload.encode())&0xffffffff:08x}\n'+payload
  else:script=fixture.compile_text(run,'qaz123' if a.mode=='secure' else ('b' if a.mode=='unmapped' else 'q'),10000 if a.mode=='held-crash' else (1400 if a.mode=='repeat' else 120),8000 if a.mode=='held-crash' else (1100 if a.mode=='repeat' else 40),1,200)
  if a.caps_via_f18:
   # Physical fixture reports still contain Caps Lock usage 57. F18 is only
   # the guest's explicitly staged, fixture-scoped hidutil destination.
   lines=script.splitlines();payload='\n'.join(line.replace(' 20 ', ' 57 ') for line in lines[1:])+'\n'
   header=lines[0].split();header[-1]=f'{zlib.crc32(payload.encode())&0xffffffff:08x}';script=' '.join(header)+'\n'+payload
  scoped_fixture=importlib.machinery.SourceFileLoader('d7_fixture',str(pathlib.Path(__file__).with_name('d7-fixture.py'))).load_module()
  client=scoped_fixture.create_client()
  if client.status().get('state') not in ('idle','complete','aborted'):raise RuntimeError('foreign fixture campaign')
  owned=True;client.load_script(script);client.arm(run)
  text='(defcfg)\n(defsrc '+('f18' if a.caps_via_f18 else 'q')+' a)\n(deflayer base '+('(tap-hold 200 200 q lctl) a' if a.mode.startswith('hrm') else 'a a')+')\n'
  command='true; '+IDENTITY.guard()+' && printf %s '+shlex.quote(text)+' > '+config+' && chown '+IDENTITY.account+' '+config+' && launchctl asuser '+str(IDENTITY.uid)+' sudo -H -u '+IDENTITY.account+' open -g -n "'+APP+'" --args --session-runtime --session-report '+path+' --session-nonce '+nonce+' --session-config '+config+' --session-port 37001'
  if not external:IDENTITY.verify(pilot,a.lease);pilot.lab(a.lease,'guest-root','--','/bin/zsh','-lc',command)
  record['stage']='worker-start'
  for attempt in range(30):
   time.sleep(.2)
   try:value=report(a.lease,path,nonce,fresh=not(external and a.mode=='secure'))
   except RuntimeError:continue
   if value.get('state') in ('running','secureInput','failed'):pid=value['pid'];break
  else:raise RuntimeError('worker did not report')
  if external and a.mode=='secure' and not 0<=time.time()-(value.get('timestamp',0)+978307200)<90:raise RuntimeError('expired parent secure transition')
  record['workerBefore']=value
  if external:
   if pid!=a.expected_worker_pid:raise RuntimeError('parent worker PID changed')
   record['parentPID']=a.owner_pid
   parent=pilot.observe(a.lease,'guest-root','--','/bin/zsh','-lc','true; ps -p '+str(a.owner_pid)+' -o uid=,comm=; ps -p '+str(pid)+' -o args=; true')
   if parent.splitlines()[0].split(maxsplit=1)!=[str(IDENTITY.uid),APP+'/Contents/MacOS/KeyPath']:raise RuntimeError('parent executable/UID mismatch')
   if '--session-owner '+str(a.owner_pid)+' ' not in parent:
    dead=pilot.observe(a.lease,'guest-root','--','/bin/zsh','-lc','true; kill -0 '+str(pid)+' 2>/dev/null && echo live; true').strip()==''
    if not (a.mode=='secure' and value.get('state')=='secureInput' and dead):raise RuntimeError('worker owner mismatch')
    record['secureWorkerExited']=True
  if a.expected_input is not None and value.get('effectiveInputAccess')!=bool(a.expected_input):raise RuntimeError('effective input capability differs from expected state')
  expected='secureInput' if a.mode=='secure' else ('failed' if a.mode=='denied' else 'running')
  if value['state']!=expected or (expected=='running' and not value['tapActive']):raise RuntimeError('unexpected tap state')
  if expected=='failed' and value.get('accessibility'):raise RuntimeError('denied trial has AX')
  pilot.verify_usb(a.lease)
  if not pilot.ready(pilot.state(a.lease,IDENTITY.account),before['pid']) or stability.require(a.lease,IDENTITY.account)!=boot:raise RuntimeError('focus or boot changed')
  IDENTITY.verify(pilot,a.lease)
  record['stage']='physical-input';client.start(run,500)
  if a.mode=='held-crash':
   deadline=time.monotonic()+3
   while time.monotonic()<deadline:
    held=pilot.state(a.lease,IDENTITY.account);ledger=report(a.lease,path,nonce)
    if held.get('pid')==before['pid'] and held.get('active') and not held.get('focusLost') and 0<=time.time()-held.get('observedAt',0)<3 and held.get('held')==[0] and held.get('modifiers')==0 and ledger.get('heldOutputUsages')==[4]:break
    time.sleep(.1)
   else:raise RuntimeError('owned held-output state not independently verified')
   record['heldBeforeCrash']=held;record['ledgerBeforeCrash']=ledger
   args=pilot.observe(a.lease,'guest-root','--','/bin/zsh','-lc','true; ps -p '+str(pid)+' -o uid=,comm=; ps -p '+str(pid)+' -o args=; true')
   if args.splitlines()[0].split(maxsplit=1)!=[str(IDENTITY.uid),APP+'/Contents/MacOS/KeyPath'] or '--session-nonce '+nonce+' ' not in args or '--session-owner '+str(a.owner_pid)+' ' not in args:raise RuntimeError('owned worker crash guard failed')
   IDENTITY.verify(pilot,a.lease)
   command='true; '+IDENTITY.guard()+' && test "$(ps -p '+str(pid)+' -o uid= | tr -d " ")" = '+str(IDENTITY.uid)+' && test "$(ps -p '+str(pid)+' -o comm=)" = '+shlex.quote(APP+'/Contents/MacOS/KeyPath')+' && test "$(ps -p '+str(pid)+' -o args=)" = '+shlex.quote(args.splitlines()[1])+' && kill -KILL '+str(pid)
   pilot.lab(a.lease,'guest-root','--','/bin/zsh','-lc',command)
   deadline=time.monotonic()+2
   while time.monotonic()<deadline:
    released=pilot.state(a.lease,IDENTITY.account)
    if released.get('pid')==before['pid'] and released.get('active') and not released.get('focusLost') and 0<=time.time()-released.get('observedAt',0)<3 and 0 not in released.get('held',[]) and released.get('ups',0)>=1:break
    time.sleep(.1)
   else:raise RuntimeError('parent did not release held output after worker crash')
   status=client.status()
   # Running includes the post-release cycle tail. Exactly the first submitted
   # report proves q is still physically down when the independent a-up is seen.
   if status.get('runId')!=run or status.get('state')!='running' or status.get('reportsSubmitted')!=1:raise RuntimeError('physical hold ended before parent cleanup proof')
   record['releasedDuringPhysicalHold']=released;record['fixtureDuringRelease']=status
  deadline=time.monotonic()+12
  while time.monotonic()<deadline:
   current=client.status()
   if current.get('runId')!=run:raise RuntimeError('fixture ownership changed')
   if current.get('state')=='complete':break
   time.sleep(.1)
  else:raise RuntimeError('fixture timeout')
  time.sleep(.7);after=pilot.state(a.lease,IDENTITY.account);target_ready=pilot.ready(after,before['pid']);value=report(a.lease,path,nonce,fresh=expected=='running' and a.mode!='held-crash')
  trace=client.trace_all(limit=8,retry_seconds=0);rows=[list(map(int,row.split()[1:])) for row in script.splitlines()[1:]];actual=[[e.get('modifiers'),*e.get('keys',[])] for e in trace]
  outcome=(after.get('controlA')==1 and after.get('aDowns')==1 and value.get('inputCount')==4 and value.get('outputCount')==4) if a.mode=='hrm-hold' else (after.get('text')=={'remap':'a','hrm-tap':'q','unmapped':'b','denied':'q'}.get(a.mode) and after.get('downs')==1 and after.get('ups')==1)
  if external and a.mode=='remap':outcome=outcome and value.get('inputCount',0)-record['workerBefore'].get('inputCount',0)==2 and value.get('outputCount',0)-record['workerBefore'].get('outputCount',0)==2
  if a.mode=='held-crash':outcome=bool(record.get('releasedDuringPhysicalHold')) and after.get('text','').startswith('a') and after.get('aDowns',0)>=1
  if a.mode=='repeat':outcome=after.get('text','').startswith('aa') and after.get('downs',0)>1 and after.get('ups')==1 and value.get('inputCount',0)>2
  if a.mode=='secure':outcome=after.get('secureLength')==6 and after.get('secureSampleMatches')==1 and value.get('inputCount')==(record['workerBefore'].get('inputCount') if external else 0)
  checks={'targetReady':target_ready,'productOutcome':outcome,'exactTrace':actual==rows,'reportsSubmitted':current.get('reportsSubmitted')==len(rows),'outputReleased':value.get('heldOutputUsages')==[]}
  if a.mode=='held-crash':checks['outputReleased']=0 not in after.get('held',[])
  if expected=='running' and a.mode!='held-crash':checks['workerLive']=pilot.observe(a.lease,'guest-root','--','/bin/zsh','-lc','true; kill -0 '+str(pid)+' 2>/dev/null && echo live; true').strip()=='live'
  pilot.verify_usb(a.lease);checks['sameBoot']=stability.require(a.lease,IDENTITY.account)==boot
  record.update(after=after,workerAfter=value,fixtureAfter=current,trace=trace,acceptanceChecks=checks,passed=all(checks.values()),stage='complete')
 except Exception as error:record.update(error=str(error),failureType=type(error).__name__)
 finally:
  if client:
   try:
    current=client.status()
    if owned and current.get('runId')==run and current.get('state') in ('loaded','armed','running'):client.abort()
   except Exception:record.update(passed=False,fixtureCleanupError='fixture cleanup failed; diagnostics suppressed')
   finally:
    try:client.close()
    except Exception:record.update(passed=False,fixtureCleanupError='fixture transport close failed')
  if pid and not external:
   try:stop(a.lease,pid,nonce)
   except Exception as cleanup_error:
    # A paired retry is confined to this PID and repeats the UID/executable
    # guards. No fixture input, grant or credential operation is replayed.
    try:stop(a.lease,pid,nonce)
    except Exception as retry_error:record.update(passed=False,cleanupError=str(retry_error))
   if record.get('workerBefore',{}).get('state')=='running':
    try:
     final=report(a.lease,path,nonce,fresh=False);record['workerStopped']=final
     if final.get('state')!='stopped' or final.get('heldOutputUsages')!=[]:
      record.update(passed=False,cleanupError='worker exited without a verified clean shutdown report')
    except Exception as error:record.update(passed=False,cleanupError=str(error))
  destination.write_text(json.dumps(record,indent=2)+'\n');print(json.dumps({'passed':record['passed'],'stage':record.get('stage'),'error':record.get('error'),'evidence':str(destination),'after':record.get('after')}))
 return 0 if record['passed'] else 79
if __name__=='__main__':raise SystemExit(main())
