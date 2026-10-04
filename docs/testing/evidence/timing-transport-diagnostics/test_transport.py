import pathlib,tempfile,unittest,json,subprocess,os
from unittest import mock
import diagnostic_transport as t
class Transport(unittest.TestCase):
 def test_selected_receipt_persisted_before_original_255_error_no_retry(self):
  with tempfile.TemporaryDirectory(dir='/private/tmp') as d:
   lab=t.Lab(d,'inert');nonce='a'*32
   frame='\n'.join('VM_LAB_DIAG_V1 '+nonce+' '+s+' '+str(rc) for s,rc in [('guest-root.enter',0),('owned-guard.passed',0),('provider.exec.enter',0),('provider.exec.exit',255),('outer.producer.exit',0),('outer.ssh.exit',255),('outer.pipeline.exit',255)])+'\nRAW_AUTH\n'
   with mock.patch.object(t.uuid,'uuid4',return_value=type('U',(),{'hex':nonce})()),mock.patch.object(t,'collect',return_value=(255,'selected stdout',frame)) as c:
    with self.assertRaisesRegex(RuntimeError,'exit=255;'):lab('cbx_inert','guest-root','--','PUBLIC')
    self.assertEqual(c.call_count,1)
   raw=(pathlib.Path(d)/'transport-000001.json').read_bytes();self.assertNotIn(b'RAW_AUTH',raw);self.assertEqual(json.loads(raw)['classification'],'provider-or-guest-exit255-unresolved')
   self.assertEqual((pathlib.Path(d)/'transport-000001.json').stat().st_mode&0o777,0o600)
 def test_bounded_collector_drains_nonreflecting_stderr_preserves_stdout_and_rc(self):
  r=t.collect(['/bin/sh','-c','printf SELECTED; printf RAW_PRIVATE >&2; exit 255'],os.environ,limit=4)
  self.assertEqual(r,(255,'SELECTED',None))
 def test_actual_existing_observe_retries255_once_with_separate_durable_receipts(self):
  import ast,time
  tree=ast.parse(pathlib.Path('/private/tmp/vm-lab-guest-identity/rig/physical-baseline.py').read_text())
  observe=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='observe')
  with tempfile.TemporaryDirectory(dir='/private/tmp') as d:
   lab=t.Lab(d,'inert');ns={'lab':lab,'time':type('Clock',(),{'sleep':staticmethod(lambda _:None)})()}
   exec(compile(ast.Module(body=[observe],type_ignores=[]),'actual-observe','exec'),ns)
   with mock.patch.object(t,'collect',side_effect=[(255,'',''),(0,'SELECTED','')]) as c:
    self.assertEqual(ns['observe']('cbx_inert','guest-root','--','PUBLIC'),'SELECTED')
    self.assertEqual(c.call_count,2)
   self.assertEqual(len(list(pathlib.Path(d).glob('transport-*.json'))),2)
 def test_timeout_is_unknown_no_255_retry_trigger_and_persisted(self):
  with tempfile.TemporaryDirectory(dir='/private/tmp') as d:
   lab=t.Lab(d,'inert')
   with mock.patch.object(t,'collect',side_effect=subprocess.TimeoutExpired('PRIVATE_ARG',30)) as c:
    with self.assertRaisesRegex(RuntimeError,'incomplete; no replay'):lab('cbx_inert','status')
   self.assertEqual(c.call_count,1);raw=(pathlib.Path(d)/'transport-000001.json').read_bytes();self.assertNotIn(b'PRIVATE_ARG',raw)
if __name__=='__main__':unittest.main()
