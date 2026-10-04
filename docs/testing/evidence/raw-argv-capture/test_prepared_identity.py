import ast,hashlib,json,pathlib,tempfile,time,types,unittest
from unittest import mock
import prepared_identity as P
import executor as E
INVENTORY=pathlib.Path('/private/tmp/keypath-runtime-baseline-438d/inventory-python-pinned.json')
class Tests(unittest.TestCase):
 def value(self):return dict(version=1,lease='cbx_0123456789ab',providerUUID='889c43d1-54b7-49af-8c07-69380a2ef0a6',bootEpoch=123,**P.PROFILE)
 def test_actual_prepared_file_binding_and_legacy_default_remains_strict(self):
  with tempfile.TemporaryDirectory(dir='/private/tmp') as d:
   path=pathlib.Path(d)/'identity.json';value=self.value();raw=json.dumps(value).encode();path.write_bytes(raw);path.chmod(0o600);sha=hashlib.sha256(raw).hexdigest()
   ident=P.load(path,sha,INVENTORY,P.BASELINE_SHA,9999999999)
   self.assertEqual(ident.lease,value['lease']);self.assertEqual(ident.account,P.PROFILE['account']);self.assertIn('9999999999',ident.guard())
   with self.assertRaises(ValueError):P.shared.GuestIdentity(ident.account,502,ident.lease,ident.provider_uuid,123)
   for update in (dict(uid=True),dict(account='keypathqa_01234567'),dict(bootEpoch=True),dict(providerUUID='bad'),dict(home='/Users/foreign')):
    raw=json.dumps(dict(value,**update)).encode();path.write_bytes(raw)
    with self.assertRaises(Exception):P.load(path,hashlib.sha256(raw).hexdigest(),INVENTORY,P.BASELINE_SHA,9999999999)
   path.write_text(json.dumps(value));path.chmod(0o644)
   with self.assertRaisesRegex(RuntimeError,'private metadata'):P.load(path,hashlib.sha256(path.read_bytes()).hexdigest(),INVENTORY,P.BASELINE_SHA,9999999999)
 def test_private_ancestor_and_reviewed_baseline_are_required(self):
  with tempfile.TemporaryDirectory(dir='/private/tmp') as d:
   parent=pathlib.Path(d);p=parent/'data';p.write_text('{}');p.chmod(0o600);parent.chmod(0o755)
   with self.assertRaisesRegex(RuntimeError,'private ancestor'):P.private(p)
  with self.assertRaisesRegex(RuntimeError,'baseline pin'):P.baseline(INVENTORY,'0'*64)
 def test_provider_cutoff_refuses_before_guest_setup_dispatch(self):
  identity=types.SimpleNamespace(lease='cbx_0123456789ab',provider_uuid='889c43d1-54b7-49af-8c07-69380a2ef0a6')
  status='\n'.join(k+'\t'+v for k,v in dict(lease_id=identity.lease,owner='keypath-installer-lab-v1',status='ready',provider='parallels',provider_resource=identity.provider_uuid,expires_epoch='200').items())+'\nprovider_inventory_begin\n'
  P.admit_provider(status,identity,150,100)
  dispatch=mock.Mock()
  with self.assertRaisesRegex(RuntimeError,'exceeds provider'):
   P.admit_provider(status,identity,201,100);dispatch('backup/launch/fsync')
  dispatch.assert_not_called()
 def test_actual_existing_observation_retry_uses_scoped_transport_and_cutoff(self):
  calls=[];namespace=dict(time=time)
  def lab(*args):calls.append(args);return 'read-only'
  namespace['lab']=lab
  source=pathlib.Path('/private/tmp/vm-lab-guest-identity/rig/physical-baseline.py').read_text();tree=ast.parse(source)
  nodes=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='observe']
  exec(compile(ast.Module(body=nodes,type_ignores=[]),'actual-observe','exec'),namespace)
  pilot=types.SimpleNamespace(identity=types.SimpleNamespace(_current=None),lab=lab)
  P.bind_pilot(pilot,object(),200);namespace['lab']=pilot.lab
  with mock.patch.object(time,'time',return_value=200),self.assertRaisesRegex(RuntimeError,'cutoff'):namespace['observe']('lease','guest-root','write')
  self.assertEqual(calls,[])
  with mock.patch.object(time,'time',side_effect=[199,200]),self.assertRaisesRegex(RuntimeError,'crossed cutoff'):namespace['observe']('lease','guest-root','read')
  self.assertEqual(len(calls),1)
 def test_real_preflight_refuses_same_hash_foreign_deployment_path(self):
  class Base:
   READ_STAGES=()
   def preflight(self,target):return target
  H=types.SimpleNamespace(Guest=Base,Campaign=object)
  G,_=E.classes(H);g=object.__new__(G);g.home=P.PROFILE['home']
  target=dict(executable=g.home+'/Applications/VM Lab Rig Target.app/Contents/MacOS/RigTarget',binarySHA256='55c8')
  self.assertEqual(g.preflight(target),target)
  with self.assertRaisesRegex(RuntimeError,'deployment path'):g.preflight(dict(target,executable='/Users/foreign/target'))
