"""AST-isolated observer admission tests: never imports campaign or dispatches."""
import ast,time,unittest
from pathlib import Path
P=Path(__file__).with_name('sample_once.py')
class AdmissionTests(unittest.TestCase):
 def setUp(self):
  def require(ok,msg):
   if not ok:raise RuntimeError(msg)
  tree=ast.parse(P.read_text());fns=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ('diagnostic_cg','diagnostic_prestart_equal','ready','retain_sample_evidence')]
  ns=dict(time=time,require=require);exec(compile(ast.Module(body=fns,type_ignores=[]),'isolated','exec'),ns);self.check=ns['diagnostic_cg'];self.equal=ns['diagnostic_prestart_equal'];self.ready=ns['ready'];self.retain=ns['retain_sample_evidence']
 def observation(self,flags=0,down=False):
  return dict(readOnly=True,uid=502,requestEpoch=time.time(),states={n:dict(stateID=i,flags=flags,keys={k:dict(keyCode=c,down=down) for k,c in [('fn',63),('f18',79),('control',59),('caps',57),('q',12),('a',0)]}) for n,i in [('combinedSessionState',0),('hidSystemState',1)]})
 def test_clear_or_function_only(self):
  for flag in (0,0x100,0x800000,0x800100):self.check(self.observation(flag))
 def test_control_otherbit_or_down_refused(self):
  for value in (self.observation(0x40000),self.observation(0x800001),self.observation(0,True)):
   with self.assertRaises(RuntimeError):self.check(value)
 def test_stale_wronguid_missingkey_refused(self):
  values=[self.observation() for _ in range(3)];values[0]['requestEpoch']-=4;values[1]['uid']=501;del values[2]['states']['hidSystemState']['keys']['fn']
  for value in values:
   with self.assertRaises(RuntimeError):self.check(value)
 def target(self,flags=0):
  return dict(parents=[{}],workers=[dict(report=dict(state='running',tapActive=True,heldOutputUsages=[]))],target=dict(uid=502,active=True,focusLost=False,windowKey=True,requestedResponderFocused=True,secureTest=False,secureInputEnabled=False,held=[],modifiers=flags,observedAt=time.time(),text='',downs=0,ups=0),cgState=self.observation(flags))
 def test_default_stays_strict(self):
  self.ready(self.target(),True)
  for flags in (0x100,0x800000,0x800100):
   with self.assertRaises(RuntimeError):self.ready(self.target(flags),True)
  value=self.target();value['target']['text']='prior'
  with self.assertRaises(RuntimeError):self.ready(value,True)
 def test_diagnostic_prior_events_and_exact_prestart(self):
  import copy
  value=self.target(0x800100);value['target'].update(text='prior',downs=3,ups=3)
  self.ready(value,True,True);other=copy.deepcopy(value);self.equal(value,other)
  other['cgState']['states']['hidSystemState']['flags']=0x800000
  with self.assertRaises(RuntimeError):self.equal(value,other)
  other=copy.deepcopy(value);other['target']['modifiers']=0
  with self.assertRaises(RuntimeError):self.equal(value,other)
 def test_alphashift_rejected(self):
  with self.assertRaises(RuntimeError):self.check(self.observation(0x10000))
 def test_postcondition_refusal_retains_physical_evidence(self):
  before=self.target(0x800100);after=self.target(0x20000000)
  after['target'].update(text='a',downs=1,ups=1)
  after['workers'][0]['report'].update(inputCount=2,outputCount=2)
  trace=[dict(sequence=1,keys=[20,0,0,0,0,0]),dict(sequence=2,keys=[0]*6)]
  record=dict(passed=False)
  self.retain(record,before,after,dict(runId='owned',state='complete',reportsSubmitted=2),trace)
  with self.assertRaises(RuntimeError):self.ready(after,function_diagnostic=True)
  self.assertFalse(record['passed']);self.assertEqual(record['trace'],trace)
  self.assertEqual(record['fixture']['state'],'complete')
  self.assertEqual(record['observations']['after']['target']['downs'],1)
  self.assertEqual(record['observations']['after']['workers'][0]['outputCount'],2)
 def test_missing_target_retention_is_safe(self):
  record=dict(passed=False)
  self.retain(record,self.target(),dict(target=None,workers=[]),{},[])
  self.assertIsNone(record['observations']['after']['target']['modifiers'])
 def test_fresh_validation_precedes_network_trace(self):
  source=P.read_text()
  block=source[source.index("        after = observe("):source.index("        expected = ")]
  self.assertLess(block.index('ready(after,'),block.index('client.trace_all('))
  self.assertLess(block.index('retain_sample_evidence('),block.index('ready(after,'))
  self.assertIn('if validation_error is not None:raise validation_error',block)
if __name__=='__main__':unittest.main()
