import copy,json,time,unittest
from unittest.mock import patch
from types import SimpleNamespace
import executor as E
class Tests(unittest.TestCase):
 def test_real_cause_and_first_terminal_required(self):
  ident=dict(pid=42,uid=502,nonce='inert');r=dict(**ident,state='failed',failure='tap-disabled-by-timeout',tapActive=False,heldOutputUsages=[],timestamp=1000-978307200)
  self.assertEqual(E.terminal(r,ident,999,1001),r)
  for update in [dict(failure='tap-disabled-observed'),dict(failure='tap-disabled-by-user-input'),dict(failure='tap-disabled'),dict(state='secureInput'),dict(pid=43),dict(timestamp=995-978307200),dict(heldOutputUsages=[4])]:
   bad=r|update
   with self.assertRaises(RuntimeError):E.terminal(bad,ident,999,1001)
  with self.assertRaises(RuntimeError):E.terminal(r,ident,999,1001,r|dict(timestamp=1000.1-978307200))
  self.assertIsNone(E.terminal(r|dict(state='running'),ident,999,1001))
 def test_target_delivery_and_physical_prefix_cannot_be_replaced_by_ledger(self):
  before=dict(held=[0],ups=0,aDowns=1)
  t=dict(held=[],ups=1,aDowns=1,observedAt=1001,active=True,windowKey=True,focusLost=False,secureTest=False,secureInputEnabled=False,requestedResponderFocused=True,focusedMode='normal')
  r=dict(timestamp=1000-978307200);s=dict(runId='session-inert',state='running',reportsSubmitted=3)
  E.released(t,before,r,s,'session-inert',True)
  for bad,stat,exited in [(t|dict(held=[0]),s,True),(t|dict(ups=0),s,True),(t|dict(focusLost=True),s,True),(t,s|dict(reportsSubmitted=4),True),(t,s|dict(reportsSubmitted=3.0),True),(t,s,False)]:
   with self.assertRaises(RuntimeError):E.released(bad,before,r,stat,'session-inert',exited)
 def test_measured_budget_and_declared_identity(self):
  v=dict(passed=True,cleanup=dict(errorCount=0,profileBytewiseRestored=True),version=1,binarySHA256='a',identitySHA256='b',delayMillis=750,triggerMicros=10000000,snapshotWorstSeconds=.1,readyWorstSeconds=.2,callbackFsyncWorstSeconds=.1,marginSeconds=.1,measuredAtEpoch=1000)
  E.timing(v,'a','b',1001)
  for bad in [v|dict(passed=False),v|dict(cleanup=dict(errorCount=True,profileBytewiseRestored=True)),v|dict(cleanup=dict(errorCount=1,profileBytewiseRestored=True)),v|dict(cleanup=dict(errorCount=0,profileBytewiseRestored=False)),v|dict(binarySHA256='foreign'),v|dict(delayMillis=1000),v|dict(callbackFsyncWorstSeconds=.7),v|dict(readyWorstSeconds=9),v|dict(snapshotWorstSeconds=float('nan')),v|dict(measuredAtEpoch=1002)]:
   with self.assertRaises(RuntimeError):E.timing(bad,'a','b',1001)
 def test_request_deadline_after_fresh_status_and_durable_no_retry(self):
  calls=[];intent=[]
  class Backend:
   def request(self,m,p,*args,**kw):calls.append((m,p));return {'ok':True}
  c=SimpleNamespace(_client=Backend(),_run='session-owned')
  E.scoped_client(c,100,lambda label,value:intent.append(value))
  with patch.object(E.time,'time',side_effect=[99,99,100]):
   c._client.request('GET','/v1/status')
   with self.assertRaises(RuntimeError):c._client.request('POST','/v1/start')
  self.assertEqual(calls,[('GET','/v1/status')]);self.assertEqual(intent,[])
  def lost(*args,**kw):raise TimeoutError('inert')
  c=SimpleNamespace(_client=SimpleNamespace(request=lost),_run='session-owned');E.scoped_client(c,300,lambda l,v:intent.append(v),lambda:None)
  with patch.object(E.time,'time',return_value=99):
   with self.assertRaises(TimeoutError):c._client.request('POST','/v1/start')
   with self.assertRaises(RuntimeError):c._client.request('POST','/v1/start')
  self.assertEqual(len(intent),1)
 def test_pinned_dependencies_and_exact_script(self):
  H=E.dependencies();run='session-0123456789abcdef';text=H.script(run,E.TIMED);parts=text.splitlines()[0].split()
  self.assertEqual(parts[:5],['KPHID1',run,'4','1','45300000'])
  self.assertEqual(E.TIMED[-1],(45000000,[0]*7));self.assertEqual(E.TIMED[1][1][1:3],[20,5])
  self.assertEqual(E.CONFIG,'(defcfg)\n(defsrc q a)\n(deflayer base a a)\n')
 def test_delay_receipts_same_generation_and_clock(self):
  w=dict(pid=42,uid=502,nonce='inert')
  v={phase:dict(**w,version=1,sequence=1,parentPID=40,durationMillis=750,phase=phase,monotonicNanos=n)for phase,n in [('entered',100),('returned',800)]}
  E.delay_evidence(v,w,40)
  for key,value in [('durationMillis',1000),('parentPID',39),('pid',41),('monotonicNanos',50)]:
   bad=copy.deepcopy(v);bad['returned'][key]=value
   with self.assertRaises(RuntimeError):E.delay_evidence(bad,w,40)
 def test_every_start_rechecks_focus_after_factory_status_and_journal(self):
  events=[];target=dict(active=True,windowKey=True,focusLost=False,secureTest=False,secureInputEnabled=False,requestedResponderFocused=True,focusedMode='normal',held=[],modifiers=0,combinedSessionControl=False,observedAt=99)
  c=SimpleNamespace(_run='session-owned',_client=SimpleNamespace(request=lambda *a,**k:events.append('POST')))
  def save(*args):events.append('journal');target['focusLost']=True
  E.scoped_client(c,300,save,lambda:E.start_target(target,99))
  with patch.object(E.time,'time',return_value=99):
   with self.assertRaises(RuntimeError):c._client.request('POST','/v1/start')
  self.assertEqual(events,['journal'])
  target['focusLost']=False;events=[]
  c=SimpleNamespace(_run='session-owned',_client=SimpleNamespace(request=lambda *a,**k:events.append('POST')))
  E.scoped_client(c,219,lambda *a:events.append('journal'),lambda:E.start_target(target,99))
  with patch.object(E.time,'time',side_effect=[99,100]):
   with self.assertRaises(RuntimeError):c._client.request('POST','/v1/start')
  self.assertEqual(events,['journal'])
 def test_actual_campaign_start_gate_applies_with_and_without_phase(self):
  H=E.dependencies();G,C=E.classes(H)
  for phase in (None,'timeout'):
   actions=[];c=C.__new__(C);c.guest=SimpleNamespace(check_account=lambda:None)
   t=dict(active=True,windowKey=True,focusLost=False,secureTest=False,secureInputEnabled=False,requestedResponderFocused=True,focusedMode='normal',held=[],modifiers=0,combinedSessionControl=False,observedAt=99)
   def arm(run):actions.append('arm');t['held']=[0]
   c.client=SimpleNamespace(status=lambda:dict(state='complete'),load_script=lambda _:actions.append('load'),arm=arm,start=lambda *a:actions.append('start'))
   c.target=lambda:t;c.save=lambda *a:None;c.history=SimpleNamespace(begin=lambda *a:actions.append('begin'))
   with patch.object(E.time,'time',return_value=99):
    with self.assertRaises(RuntimeError):c.start_input(E.TIMED,phase)
   self.assertEqual(actions,['load','arm'])
 def test_real_guest_start_cannot_accept_slow_discovery_or_identity(self):
  H=E.dependencies();G,C=E.classes(H)
  for slow in ('discovery','identity'):
   g=G.__new__(G);g.profile='/owned/profile';g.backup='/owned/backup';g.uid=502;g.account='public';g.app='/owned/KeyPath.app';g.check_account=lambda:None;g.run=lambda _:None
   g.processes=lambda:[(42,502,['/owned/KeyPath','--headless'])];g.identity=lambda *a:dict(pid=42)
   # Start clock 0, loop clock 0, discovery clock 9 (refusal), or discovery 1 then identity 9.
   clock=[0,0,9] if slow=='discovery' else [0,0,1,9]
   with patch.object(E.time,'monotonic',side_effect=clock),patch.object(E.time,'time',return_value=99):
    with self.assertRaisesRegex(RuntimeError,'overran deadline'):g.start()
 def test_focus_freshness_and_all_up(self):
  t=dict(active=True,windowKey=True,focusLost=False,secureTest=False,secureInputEnabled=False,requestedResponderFocused=True,focusedMode='normal',held=[],modifiers=0,combinedSessionControl=False,observedAt=99)
  E.start_target(t,100)
  for change in (dict(held=[0]),dict(modifiers=True),dict(combinedSessionControl=True),dict(observedAt=96),dict(observedAt=101),dict(requestedResponderFocused=False)):
   with self.assertRaises(RuntimeError):E.start_target(t|change,100)
if __name__=='__main__':unittest.main()


class VarAliasTests(unittest.TestCase):
 def testKnownVarAliasOnlyAndMetadataRefusals(self):
  import pathlib,tempfile,os,shutil,uuid
  nonce=str(uuid.uuid4()).upper();raw=pathlib.Path(tempfile.gettempdir())/('keypath-session-'+nonce);raw.mkdir(mode=0o700)
  ns={};exec(E.SCOPED_DIRECTORY_CODE,ns);uid=os.getuid()
  try:
   original=str(raw);d,metadata=ns['scoped_directory'](raw,uid,nonce)
   self.assertEqual(str(raw),original);self.assertEqual(d,raw.resolve());self.assertEqual(ns['scoped_directory'](d,uid,nonce),(d,metadata))
   for u,n in ((uid+1,nonce),(uid,str(uuid.uuid4()).upper())):
    with self.assertRaises(AssertionError):ns['scoped_directory'](raw,u,n)
   raw.chmod(0o755)
   with self.assertRaises(AssertionError):ns['scoped_directory'](raw,uid,nonce)
   raw.chmod(0o700)
   # Final directory symlink is an additional alias and must be refused.
   moved=raw.with_name('owned-inert-'+uuid.uuid4().hex);raw.rename(moved);raw.symlink_to(moved,target_is_directory=True)
   try:
    with self.assertRaises(AssertionError):ns['scoped_directory'](raw,uid,nonce)
   finally:raw.unlink();moved.rename(raw)
   # Same spelling with replacement inode cannot satisfy the retained identity.
   raw.rename(moved);raw.mkdir(mode=0o700)
   try:
    with self.assertRaises(AssertionError):ns['recheck_directory'](raw,uid,nonce,d,metadata)
   finally:raw.rmdir();moved.rename(raw)
  finally:shutil.rmtree(raw)
