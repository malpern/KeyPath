"""Reject stale/foreign identity evidence before any guest operation."""
import argparse
import importlib.machinery
import json
import os
import pathlib
import tempfile
import unittest
module=importlib.machinery.SourceFileLoader('guest_identity',str(pathlib.Path(__file__).with_name('guest-identity.py'))).load_module()

class IdentityEvidenceTests(unittest.TestCase):
 def receipt(self):
  return {'version':1,'lease':'cbx_896c0d2d8565','providerUUID':'62017a62-8774-4bf6-8754-bbafe7c27c1f','account':'keypathqa_896c0d2d','uid':502,'home':'/Users/keypathqa_896c0d2d','bootEpoch':1791077561}
 def load(self,path):
  return module.from_arguments(argparse.Namespace(guest_account=None,guest_uid=None,guest_identity_receipt=str(path)))
 def test_foreign_receipts_are_rejected_before_guest_calls(self):
  with tempfile.TemporaryDirectory() as folder:
   path=pathlib.Path(folder)/'identity.json'
   for override in ({'account':'keypathqa_deadbeef'},{'uid':501},{'home':'/Users/keypathqa'},{'bootEpoch':True},{'providerUUID':'not-a-uuid'},{'version':True},{'lease':'other'}):
    value=self.receipt();value.update(override);path.write_text(json.dumps(value));path.chmod(0o600)
    with self.subTest(override=override),self.assertRaises((ValueError,TypeError)):
     self.load(path)
 def test_foreign_lease_never_reaches_observer(self):
  class NoCalls:
   def observe(self,*args):raise AssertionError('foreign lease reached guest')
  with tempfile.TemporaryDirectory() as folder:
   path=pathlib.Path(folder)/'identity.json';path.write_text(json.dumps(self.receipt()));path.chmod(0o600)
   identity=self.load(path)
   with self.assertRaises(RuntimeError):identity.verify(NoCalls(),'cbx_deadbeef1234')
 def test_missing_or_failed_live_observation_does_not_authorize(self):
  class Observer:
   def observe(self,*args):return 'KEYPATH_GUEST_IDENTITY_VERIFIED\nwrong account'
  with self.assertRaises(RuntimeError):module.GuestIdentity().verify(Observer(),'cbx_896c0d2d8565')
 def test_receipt_link_and_public_permissions_rejected(self):
  with tempfile.TemporaryDirectory() as folder:
   path=pathlib.Path(folder)/'identity.json';path.write_text(json.dumps(self.receipt()));path.chmod(0o644)
   with self.assertRaises(ValueError):self.load(path)
   path.chmod(0o600);link=pathlib.Path(folder)/'linked.json';link.symlink_to(path)
   with self.assertRaises(ValueError):self.load(link)
   link.unlink();os.link(path,link)
   with self.assertRaises(ValueError):self.load(path)
 def test_fifo_and_special_modes_refuse_without_blocking(self):
  with tempfile.TemporaryDirectory() as folder:
   path=pathlib.Path(folder)/'identity.json'
   os.mkfifo(path,0o600)
   with self.assertRaises(ValueError):self.load(path)
   path.unlink();path.write_text(json.dumps(self.receipt()));path.chmod(0o4600)
   with self.assertRaises(ValueError):self.load(path)
 def test_duplicate_keys_and_incomplete_canonical_receipt_refuse(self):
  with tempfile.TemporaryDirectory() as folder:
   path=pathlib.Path(folder)/'identity.json'
   path.write_text(json.dumps(self.receipt())[:-1]+',"uid":502}');path.chmod(0o600)
   with self.assertRaisesRegex(ValueError,'duplicate'):self.load(path)
   for changed in ({'account':'keypathqa','uid':501,'home':'/Users/keypathqa','bootEpoch':True},
                   {'account':'keypathqa','uid':501,'home':'/Users/keypathqa','providerUUID':None}):
    value=self.receipt();value.update(changed);path.write_text(json.dumps(value))
    with self.assertRaises(ValueError):self.load(path)
 def test_changed_receipt_never_reaches_live_transport(self):
  class NoCalls:
   def lab(self,*args):raise AssertionError('changed receipt reached provider')
   def observe(self,*args):raise AssertionError('changed receipt reached guest')
  with tempfile.TemporaryDirectory() as folder:
   path=pathlib.Path(folder)/'identity.json';path.write_text(json.dumps(self.receipt()));path.chmod(0o600)
   identity=self.load(path);value=self.receipt();value['bootEpoch']+=1;path.write_text(json.dumps(value))
   with self.assertRaisesRegex(RuntimeError,'receipt changed'):identity.verify(NoCalls(),identity.lease)
 def test_provider_change_or_expiry_stops_before_guest_observation(self):
  receipt=self.receipt()
  base={'lease_id':receipt['lease'],'owner':'keypath-installer-lab-v1','status':'ready',
        'provider':'parallels','provider_resource':receipt['providerUUID'],'expires_epoch':'9999999999'}
  class Observer:
   def __init__(self,fields):self.fields=fields
   def lab(self,*args):return ''.join(k+'\t'+v+'\n' for k,v in self.fields.items())+'provider_inventory_begin\n'
   def observe(self,*args):raise AssertionError('invalid provider reached guest')
  with tempfile.TemporaryDirectory() as folder:
   path=pathlib.Path(folder)/'identity.json';path.write_text(json.dumps(receipt));path.chmod(0o600);identity=self.load(path)
   for changes in ({'provider_resource':'e2017a62-8774-4bf6-8754-bbafe7c27c1f'},
                   {'expires_epoch':'1'},{'status':'destroyed'},{'lease_id':'cbx_deadbeef1234'}):
    fields=dict(base,**changes)
    with self.subTest(changes=changes),self.assertRaises(RuntimeError):identity.verify(Observer(fields),identity.lease)
 def test_canonical_default_and_complete_owned_receipt_remain_valid(self):
  self.assertEqual((module.GuestIdentity().account,module.GuestIdentity().uid),('keypathqa',501))
  receipt=self.receipt()
  class Observer:
   def lab(self,*args):
    return 'lease_id\t'+receipt['lease']+'\nowner\tkeypath-installer-lab-v1\nstatus\tready\nprovider\tparallels\nprovider_resource\t'+receipt['providerUUID']+'\nexpires_epoch\t9999999999\nprovider_inventory_begin\n'
   def observe(self,*args):
    command=args[-1]
    if '/dev/console' not in command or str(receipt['bootEpoch']) not in command:raise AssertionError('missing live identity guard')
    return 'KEYPATH_GUEST_IDENTITY_VERIFIED'
  with tempfile.TemporaryDirectory() as folder:
   path=pathlib.Path(folder)/'identity.json';path.write_text(json.dumps(receipt));path.chmod(0o600);identity=self.load(path)
   self.assertEqual(identity.verify(Observer(),identity.lease)['uid'],502)
 def tearDown(self):os.environ.pop('KEYPATH_GUEST_IDENTITY_RECEIPT',None)

class StopBoundaryTests(unittest.TestCase):
 def setUp(self):
  self.trial=importlib.machinery.SourceFileLoader('identity_stop_trial',str(pathlib.Path(__file__).with_name('physical-trial.py'))).load_module()
  self.old_identity,self.old_pilot=self.trial.IDENTITY,self.trial.pilot
  class Identity:
   def verify(self,*args):pass
  self.trial.IDENTITY=Identity()
 def tearDown(self):self.trial.IDENTITY,self.trial.pilot=self.old_identity,self.old_pilot
 def pilot(self,output):
  class Pilot:
   def observe(self,*args):
    assert args[-1].startswith('true; '),'missing provider no-op prefix'
    return output
   def lab(self,*args):raise AssertionError('refused/absent PID reached signal operation')
  self.trial.pilot=Pilot()
 def test_already_exited_worker_never_signaled(self):
  self.pilot('KEYPATH_PROCESS_ABSENT')
  self.trial.stop('cbx_896c0d2d8565',123,'known-owned-nonce')
 def test_unverified_process_scan_is_not_absence(self):
  self.pilot('')
  with self.assertRaises(RuntimeError):self.trial.stop('cbx_896c0d2d8565',123,'known-owned-nonce')
 def test_foreign_worker_nonce_never_signaled(self):
  self.pilot('/Users/keypathqa/Applications/KeyPath.app/Contents/MacOS/KeyPath --session-runtime --session-nonce other-nonce\nKEYPATH_PROCESS_PRESENT')
  with self.assertRaises(RuntimeError):self.trial.stop('cbx_896c0d2d8565',123,'known-owned-nonce')

if __name__=='__main__':unittest.main()
