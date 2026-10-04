import copy
import json
import pathlib
import types
import unittest
from unittest import mock
import executor as E
import capture_lifecycle as L

NOW=1791153000
SCOPE=E.startup().read_scope(pathlib.Path(__file__).with_name('scope-6eed.json'),'33ce1ab2ef9faf90dedc43f68cb5f2553c8f03ad65a44796ef0f0c3fca26f8d0')[0]

def target(pid=50,nonce='12345678-1234-4234-8234-123456789012'):
 return dict(pid=pid,uid=502,nonce=nonce,commandPath=SCOPE.home+'/rig-target-control-'+str(pid)+'-'+nonce+'/command.json',observedAt=NOW,monotonicAt=20.,active=True,windowKey=True,focusLost=False,secureTest=False,secureInputEnabled=False,requestedResponderFocused=True,focusedMode='normal',held=[],modifiers=0,combinedSessionControl=False,downs=0,ups=0,qDowns=0,aDowns=0,controlA=0,commandSequence=0,commandConsumedSequence=0,flagsChangedJournal=[],flagsChangedDropped=0,combinedSessionControlJournal=[],combinedSessionControlDropped=0,modeTransitions=[],modeTransitionsDropped=0,text='',secureLength=0,secureSampleMatches=False,commandStatus='awaitingCommand')

class SequenceTests(unittest.TestCase):
 def campaign(self,t):
  H=E.dependencies();G,C=E.classes(H);c=C.__new__(C);events=[]
  g=types.SimpleNamespace(capture_scope=SCOPE,target_sha=SCOPE.target_sha256,uid=502)
  g.startup_preflight=lambda:events.append('preflight')or dict(executable=SCOPE.target_executable,binarySHA256=SCOPE.target_sha256)
  def start():events.append('parent-start');g.parent=10;return dict(pid=10)
  g.start=start
  def capture(claim):
   events.append('capture');claim(dict(intent=True));g.target_identity={k:t[k]for k in ('pid','uid','nonce')};return t
  g.fresh_capture=capture;c.guest=g;c.history=None;c.save=lambda label,value:events.append(label)or label
  return c,events,H
 def test_initial_starts_parent_then_claim_then_exact_new_history(self):
  c,events,H=self.campaign(target())
  with mock.patch.object(E.time,'time',return_value=NOW):c.start_fresh_owner('initial')
  self.assertEqual(events,['preflight','parent-start','initial-parent','capture','initial-target-launch-intent','initial-fresh-capture'])
  self.assertEqual(c.history.identity[:3],(50,502,target()['nonce']))
 def test_recovery_preserves_old_object_and_counters_requires_retirement(self):
  new=target(51,'22345678-1234-4234-8234-123456789012');c,events,H=self.campaign(new);old=target();history=H.TargetHistory(old,NOW,502);c.history=history
  with mock.patch.object(E.time,'time',return_value=NOW):
   with self.assertRaisesRegex(RuntimeError,'retirement'):c.start_fresh_owner('recovery',old)
  self.assertEqual(events,[]);self.assertIs(c.history,history)
  c.old_capture_retired=dict(target=old);history.anchors['timeout']={}
  with mock.patch.object(E.time,'time',return_value=NOW):
   with self.assertRaisesRegex(RuntimeError,'retirement'):c.start_fresh_owner('recovery',old)
  self.assertEqual(events,[]);history.anchors.clear()
  with mock.patch.object(E.time,'time',return_value=NOW):c.start_fresh_owner('recovery',old)
  self.assertIs(c.retired_histories[0],history);self.assertEqual(history.previous,old);self.assertNotEqual(c.history.identity,history.identity)
  self.assertIn('old-capture-history-retained',events)
 def test_reused_capture_refuses_and_keeps_old_history(self):
  c,events,H=self.campaign(target());old=target();history=H.TargetHistory(old,NOW,502);c.history=history;c.old_capture_retired=dict(target=old)
  with mock.patch.object(E.time,'time',return_value=NOW):
   with self.assertRaisesRegex(RuntimeError,'reused'):c.start_fresh_owner('recovery',old)
  self.assertIs(c.history,history)
 def test_retirement_requires_exact_finished_physical_proof_and_all_up(self):
  for missing in ('timeout_trace_receipt','fail_open_trace_receipt','fail_open_receipt','active_run','held','anchor'):
   t=target();c,events,H=self.campaign(t);c.history=H.TargetHistory(t,NOW,502);c.latest=dict(worker=None);c.active_run=None
   c.timeout_trace_receipt='exact-four-trace';c.fail_open_trace_receipt='exact-tap-trace';c.fail_open_receipt='balanced-q'
   if missing=='active_run':c.active_run='running'
   elif missing=='held':t['held']=[0]
   elif missing=='anchor':c.history.anchors['timeout']={}
   else:setattr(c,missing,None)
   with mock.patch.object(E.time,'time',return_value=NOW),mock.patch.object(L,'retire')as dispatch:
    with self.assertRaises(RuntimeError):c.retire_old_capture(t)
    dispatch.assert_not_called()
 def test_actual_claim_before_retirement_dispatch_and_lost_response_never_replays(self):
  t=target();g=types.SimpleNamespace(parent=10,parent_args=['/parent','--headless'],exe='/parent',account=SCOPE.account,target_identity={k:t[k]for k in ('pid','uid','nonce')});events=[]
  def claim(v):events.append('claim')
  def lost(command):events.append('TERM-dispatch');raise TimeoutError('inert')
  g.run=lost
  with self.assertRaises(TimeoutError):L.retire(g,SCOPE,t,claim)
  with self.assertRaisesRegex(RuntimeError,'replay'):L.retire(g,SCOPE,t,claim)
  self.assertEqual(events,['claim','TERM-dispatch'])
 def test_fixed_physical_protocol_and_limits_preserved(self):
  self.assertEqual(E.DELAY,750);self.assertEqual(E.TIMED,[(0,[0,20,0,0,0,0,0]),(10000000,[0,20,5,0,0,0,0]),(10050000,[0,20,0,0,0,0,0]),(45000000,[0]*7)])
  tree=__import__('ast').parse(pathlib.Path(E.__file__).read_text());calls=[n for n in __import__('ast').walk(tree)if isinstance(n,__import__('ast').Call)]
  waits={n.args[0].value:n.args[2].value for n in calls if isinstance(n.func,__import__('ast').Attribute)and n.func.attr=='wait'and len(n.args)>=3}
  self.assertEqual(waits,{'initial-ready':8,'a-held':7,'actual-timeout-release':15,'new-parent-ready':8})
  self.assertEqual(SCOPE.product_source,'6ed4ea99052c19bc94e99517cfe9827377b17af7');self.assertEqual(SCOPE.deadline,1791154292)

if __name__=='__main__':unittest.main()

class ActualRetirementBodyTests(unittest.TestCase):
 def test_actual_retirement_preserves_archive_before_report_removal_after_dead(self):self.exercise()
 def test_actual_retirement_refuses_hash_held_foreign_process_and_unknown_exit(self):
  for fault in ('hash','held','foreign','reused','timeout','archive-present','oversize','extra-field','malformed-journal','bounded-large','orphan-physical-up','target-extra','target-quoted'):
   with self.subTest(fault=fault):self.exercise(fault)
 def exercise(self,fault=None):
  import hashlib,os,signal,stat,subprocess,tempfile,io
  from contextlib import redirect_stdout
  with tempfile.TemporaryDirectory(dir='/private/tmp')as tmp:
   home=pathlib.Path(tmp);exe=home/'Applications/VM Lab Rig Target.app/Contents/MacOS/RigTarget';exe.parent.mkdir(parents=True);exe.write_bytes(b'inert');exe.chmod(0o755)
   for p in (home/'Applications',exe.parents[2],exe.parents[1],exe.parent):p.chmod(0o755)
   t=target();t['commandPath']=str(home/('rig-target-control-50-'+t['nonce'])/'command.json');report=home/'rig-target.json';raw=json.dumps(t).encode();report.write_bytes(raw);report.chmod(0o644)
   archive=home/('rig-target-retired-50-'+t['nonce']+'.json');events=[];alive=[True];elapsed=[0];killed=[False]
   if fault=='orphan-physical-up':t['ups']=1;raw=json.dumps(t).encode();report.write_bytes(raw)
   if fault=='held':bad=dict(t,held=[0]);report.write_text(json.dumps(bad))
   if fault=='archive-present':archive.write_bytes(b'old archive')
   if fault=='oversize':
    t['text']='q'*262144;raw=json.dumps(t).encode();report.write_bytes(raw)
   if fault=='bounded-large':
    t['combinedSessionControlJournal']=[dict(sequence=n+1,observedAt=NOW,monotonicAt=19.+n/1024,source='CGEventSourceCombinedSessionState',control=False,flags=0,secureInputEnabled=False,localDowns=0,localUps=0,localHeld=[],active=True,windowKey=True,focusLost=False,focusedMode='normal',requestedResponderFocused=True,mode='normal')for n in range(512)]
    raw=json.dumps(t,separators=(',',':')).encode();self.assertGreater(len(raw),65536);self.assertLess(len(raw),262144);report.write_bytes(raw)
   if fault=='extra-field':report.write_text(json.dumps(dict(t,unreviewed=True)))
   if fault=='malformed-journal':report.write_text(json.dumps(dict(t,combinedSessionControlJournal=[1])))
   original_lstat=pathlib.Path.lstat;original_stat=os.stat;original_fstat=os.fstat;original_unlink=os.unlink
   def owned(s):return types.SimpleNamespace(**{name:(502 if name=='st_uid'else getattr(s,name))for name in ('st_dev','st_ino','st_mode','st_uid','st_gid','st_nlink','st_size','st_mtime_ns','st_ctime_ns')})
   def osstat(p,*args,**kw):return types.SimpleNamespace(st_uid=502)if str(p)=='/dev/console'else original_stat(p,*args,**kw)
   def run(args,**kw):
    if args[0]=='/usr/sbin/sysctl':out='{ sec = 90, usec = 0 }'
    elif args[0]=='/usr/bin/codesign':out=''
    elif args[:3]==['/bin/ps','-ww','-axo']:
     comm='/foreign'if fault=='foreign'or fault=='reused'and killed[0]else str(exe)
     out='10 502 /parent\n'+('50 502 '+comm+'\n'if alive[0]else'')
    elif args[:3]==['/bin/ps','-ww','-p']:out='/parent --headless'if args[3]=='10'else (str(exe)+' --foreign' if fault=='target-extra' else (__import__('shlex').quote(str(exe)) if fault=='target-quoted' else str(exe)))
    else:raise AssertionError(args)
    return types.SimpleNamespace(stdout=out,returncode=0)
   def kill(pid,sig):
    self.assertEqual((pid,sig),(50,signal.SIGTERM));events.append('TERM');killed[0]=True
    if fault not in ('reused','timeout'):alive[0]=False
   def unlink(p,*args,**kw):
    self.assertEqual(pathlib.Path(p),report);self.assertFalse(alive[0]);self.assertEqual(archive.read_bytes(),raw);self.assertEqual(archive.stat().st_mode&0o777,0o600)
    events.append('unlink-after-archive');return original_unlink(p,*args,**kw)
   v=dict(home=str(home),bootEpoch=90,deadline=NOW+600,targetExecutable=str(exe),targetSHA256=hashlib.sha256(exe.read_bytes()).hexdigest(),parent=dict(pid=10,arguments=['/parent','--headless']),parentExecutable='/parent',oldTarget={k:t[k]for k in ('pid','uid','nonce','commandPath','observedAt','downs','ups','qDowns','aDowns')})
   if fault=='hash':v['targetSHA256']='0'*64
   output=io.StringIO()
   with mock.patch.dict(os.environ,HOME=str(home)),mock.patch.object(os,'getuid',return_value=502),mock.patch.object(os,'stat',side_effect=osstat),mock.patch.object(os,'fstat',side_effect=lambda fd:owned(original_fstat(fd))),mock.patch.object(pathlib.Path,'lstat',side_effect=lambda p:owned(original_lstat(p)),autospec=True),mock.patch.object(os,'kill',side_effect=kill),mock.patch.object(os,'unlink',side_effect=unlink),mock.patch.object(subprocess,'run',side_effect=run),mock.patch('time.time',return_value=NOW),mock.patch('time.monotonic',side_effect=lambda:elapsed[0]),mock.patch('time.sleep',side_effect=lambda seconds:elapsed.__setitem__(0,elapsed[0]+max(seconds,.01))),mock.patch('sys.argv',['inert',json.dumps(v),'retire']),redirect_stdout(output):
    if fault and fault not in ('bounded-large','orphan-physical-up'):
     with self.assertRaises(RuntimeError):exec(compile(L.RETIRE_CODE,'actual-owned-retirement','exec'),{})
    else:exec(compile(L.RETIRE_CODE,'actual-owned-retirement','exec'),{})
   if fault and fault not in ('bounded-large','orphan-physical-up'):
    self.assertTrue(report.exists());self.assertNotIn('unlink-after-archive',events);self.assertEqual(events, ['TERM']if fault in ('reused','timeout')else[])
   else:
    result=json.loads(output.getvalue());self.assertEqual(result['target'],t);self.assertTrue(result['exited']);self.assertFalse(report.exists());self.assertEqual(events,['TERM','unlink-after-archive'])
