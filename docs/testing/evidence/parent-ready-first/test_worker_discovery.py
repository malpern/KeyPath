import base64,json,pathlib,shlex,subprocess,time,types,unittest
import worker_discovery as w
import measurement as m
from test_measurement import Fake,SCOPE
NONCE='12345678-1234-4234-8234-123456789012'
class WorkerDiscovery(unittest.TestCase):
 def observe(self,fault=None):
  exe=SCOPE.home+'/Applications/KeyPath.app/Contents/MacOS/KeyPath'
  path='/var/folders/aa/inert/T/keypath-session-'+NONCE+'/report.json'
  parent=exe+' --headless';args=exe+' --session-runtime --session-owner 10 --session-report '+path+' --session-nonce '+NONCE
  report=dict(pid=20,uid=502,nonce=NONCE)
  if fault=='report-owner':report['uid']=501
  if fault=='owner':args=args.replace('--session-owner 10','--session-owner 11')
  if fault=='foreign':args=args.replace('--session-runtime','--foreign-mode')
  guard='false && true' if fault=='guard' else 'true'
  script='''inert_ps() {
 if [[ "$1" == -axo ]]; then printf '10\\n20\\n%s\\n' "$$";
 elif [[ "$1" == -ww && "$2" == -axo ]]; then printf '10 502 %s\\n20 502 %s\\n' "$EXE" "$EXE";
 elif [[ "$2" == -p && "$3" == 10 ]]; then printf '%s\\n' "$PARENT_ARGS";
 elif [[ "$2" == -p && "$3" == 20 ]]; then printf '%s\\n' "$WORKER_ARGS";
 else return 79; fi
}
inert_id(){ [[ "$1" == -un ]] && printf 'keypathqa_438d6abc\n' || printf '502\n'; }
inert_dscl(){ printf 'NFSHomeDirectory: /Users/keypathqa_438d6abc\n'; }
inert_stat(){ [[ "$2" == %Su ]] && printf 'keypathqa_438d6abc\n' || printf '502\n'; }
inert_sysctl(){ printf '{ sec = BOOT, usec = 0 }\n'; }
inert_hash(){ printf 'HASH  inert'; }
inert_cat(){ printf '%s' "$REPORT"; }
'''.replace('BOOT',str(SCOPE.boot_epoch)).replace('HASH',SCOPE.binary_sha256)
  code_seen=[]
  def run(*values):
   expression=values[-1];code_seen.append(expression)
   self.assertNotIn('rig-target',expression)
   self.assertIn('d8before=$(d8processes)',expression);self.assertIn('d8after=$(d8processes)',expression)
   for absolute,inert in (('/bin/ps','inert_ps'),('/usr/bin/id','inert_id'),('/usr/bin/dscl','inert_dscl'),('/usr/bin/stat','inert_stat'),('/usr/sbin/sysctl','inert_sysctl'),('/usr/bin/shasum','inert_hash'),('/bin/cat','inert_cat')):expression=expression.replace(absolute,inert)
   import os
   result=subprocess.run(['/bin/zsh','-lc',script+expression],env=dict(os.environ,EXE=exe,PARENT_ARGS=parent,WORKER_ARGS=args,REPORT=json.dumps(report)),capture_output=True,text=True)
   if result.returncode:raise RuntimeError('inert generated batch exit '+str(result.returncode))
   if fault=='complete':return result.stdout.replace('D8\tcomplete\tRDhfQ09NUExFVEU=','D8\tcomplete\tWA==')
   return result.stdout
  g=types.SimpleNamespace(observation_scope=lambda:None,exe=exe,home=SCOPE.home,account=SCOPE.account,uid=502,parent=10,parent_args=shlex.split(parent),binary_sha=SCOPE.binary_sha256,generations={},pilot=types.SimpleNamespace(observe=run),lease='inert',guest_identity=types.SimpleNamespace(guard=lambda:guard,boot_epoch=SCOPE.boot_epoch,provider_uuid=SCOPE.provider_uuid))
  return w.worker_snapshot(g),code_seen
 def test_actual_generated_worker_batch_has_no_target_dependency_and_retains_exact_proofs(self):
  value,commands=self.observe();self.assertEqual(len(commands),1);self.assertEqual(value['worker'][0]['pid'],20)
  self.assertNotIn('target',value);self.assertEqual(value['identity']['uid'] if 'uid' in value['identity'] else value['identity']['consoleUID'],502)
 def test_actual_generated_guard_owner_foreign_report_and_completion_failures_refuse(self):
  for fault in ('guard','owner','foreign','report-owner','complete'):
   with self.subTest(fault=fault),self.assertRaises(RuntimeError):self.observe(fault)
class Ordering(unittest.TestCase):
 def test_absent_worker_stops_before_capture_claim_or_open(self):
  f=Fake();f.worker_never_ready=True;r=f.run();self.assertFalse(r['passed']);self.assertNotIn('capture',f.calls);self.assertLessEqual(f.elapsed-.2,8.000001)
 def test_canonical_marker_failure_never_launches_target(self):
  f=Fake();f.parent_ready=lambda _:(_ for _ in ()).throw(RuntimeError('missing canonical ready'))
  r=f.run();self.assertFalse(r['passed']);self.assertNotIn('capture',f.calls);self.assertEqual(r['errorStage'],'setup.pre-capture-parent-ready')
 def test_worker_generation_change_after_capture_is_refused_before_samples(self):
  f=Fake();original=f.snapshot
  def changed():
   v=original();v['worker'][0]['nonce']='new-worker';return v
  f.snapshot=changed;r=f.run();self.assertFalse(r['passed']);self.assertEqual(r['samples'],[])
  self.assertEqual(f.calls.count('ready'),1);self.assertEqual(f.cleanup_count,1)
 def test_readiness_crossing_eight_seconds_never_launches_target(self):
  f=Fake();f.ready_cost=8.1;r=f.run();self.assertFalse(r['passed']);self.assertNotIn('capture',f.calls);self.assertEqual(r['refusalReason'],'worker startup deadline')
if __name__=='__main__':unittest.main()
