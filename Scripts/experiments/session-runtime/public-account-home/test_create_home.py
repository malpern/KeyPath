import copy
import plistlib
import unittest
from types import SimpleNamespace
import stat
from create_home import CreateHome, Refusal, complete_once
from selected_account import selected_account


def user(name, uid, token, real, missing=False):
    return dict(account=name, uid=uid, home='/Users/'+name, homeOwner=None if missing else uid,
                homeKind='absent' if missing else 'directory', homeSymlink=False,
                realName=real, admin=True, secureToken=token)


def fixture():
    scope = dict(lease='cbx_123456789abc', providerUUID='00000000-0000-4000-8000-000000000001',
                 expiresEpoch=2000, bootEpoch=900, loginwindowPID=197, rootReleasedFreshScope=True)
    baseline = dict(lease=scope['lease'], providerUUID=scope['providerUUID'], observedAt=1000,
                    hostReceivedAt=1000, transportSeconds=0, complete=True, executorUID=0,
                    bootEpoch=900, consoleAccount='root', consoleUID=0, loginwindowUID=0,
                    loginwindowPID=197, usersRootSafe=True, fileVaultOff=True,
                    qa=user('keypathqa',501,'ENABLED','KeyPath QA'), newAccount=None,
                    uid502Accounts=[], newHomeAbsent=True, autoLoginUser=None,
                    autologinToolUser=None, kcpassword=None, otherLoginPreferencesSHA256='a'*64,
                    loginPreferencesFile=None)
    original = dict(scope=scope, plan=dict(phase='creation-attempted',baseline=baseline),
                    pending=dict(action='create',before=copy.deepcopy(baseline),attemptID='original'))
    observed = copy.deepcopy(baseline)
    observed.update(newAccount=user('keypathqa_12345678',502,'DISABLED',
                                   'KeyPath Disposable 12345678',True),
                    uid502Accounts=['keypathqa_12345678'])
    provider=dict(ownedReady=True,lease=scope['lease'],providerUUID=scope['providerUUID'],expiresEpoch=2000)
    return original, provider, observed


class HomeTests(unittest.TestCase):
    def setUp(self):
        self.original,self.provider,self.value=fixture()
        self.plan=CreateHome(self.original,'b'*64)

    def test_unknown_create_exit_preserved_and_exact_home_command_claimed_once(self):
        before=copy.deepcopy(self.original)
        state=self.plan.reconcile(self.provider,self.value,1001)
        self.assertEqual(state['phase'],'account-created')
        state,operation=self.plan.claim_home(self.provider,self.value,1001)
        self.assertEqual(operation['argv'],['/usr/sbin/createhomedir','-c','-l','-u','keypathqa_12345678'])
        self.assertIsNone(state['originalCreateExit'])
        self.assertEqual(self.original,before)
        restored=CreateHome(self.original,'b'*64,state)
        restored.reconcile(self.provider,self.value,1001)
        with self.assertRaises(Refusal): restored.claim_home(self.provider,self.value,1001)

    def test_lost_home_response_reconciles_actual_state_without_replay(self):
        self.plan.reconcile(self.provider,self.value,1001)
        state,_=self.plan.claim_home(self.provider,self.value,1001)
        self.value['newAccount'].update(homeKind='directory',homeOwner=502)
        self.value['newHomeAbsent']=False
        restored=CreateHome(self.original,'b'*64,state)
        self.assertEqual(restored.reconcile(self.provider,self.value,1001)['phase'],'home-ready')
        self.assertIsNone(restored.state['homeAttempt']['commandExit'])
        with self.assertRaises(Refusal): restored.claim_home(self.provider,self.value,1001)

    def test_already_complete_home_requires_no_mutation(self):
        self.value['newAccount'].update(homeKind='directory',homeOwner=502)
        self.value['newHomeAbsent']=False
        state=self.plan.reconcile(self.provider,self.value,1001)
        self.assertEqual(state['phase'],'home-ready')
        self.assertIsNone(state['homeAttempt'])
        with self.assertRaises(Refusal): self.plan.claim_home(self.provider,self.value,1001)

    def test_owned_account_home_identity_and_preservation_refusals(self):
        changes=[('uid502Accounts',['foreign']),('consoleUID',502),('bootEpoch',901),
                 ('loginwindowPID',198),('complete',False),('hostReceivedAt',900),
                 ('autoLoginUser','foreign'),('otherLoginPreferencesSHA256','c'*64)]
        for key,value in changes:
            with self.subTest(key=key):
                bad=copy.deepcopy(self.value);bad[key]=value
                with self.assertRaises(Refusal): self.plan.reconcile(self.provider,bad,1001)
        for key,value in [('homeSymlink',True),('homeOwner',501),('secureToken','ENABLED'),
                          ('uid',True),('realName','Foreign'),('home','/Users/foreign')]:
            with self.subTest(key=key):
                bad=copy.deepcopy(self.value);bad['newAccount'][key]=value
                with self.assertRaises(Refusal): self.plan.reconcile(self.provider,bad,1001)
        bad=copy.deepcopy(self.value);bad['qa']['admin']=False
        with self.assertRaises(Refusal): self.plan.reconcile(self.provider,bad,1001)

    def test_expiry_and_provider_refusal_before_home_claim(self):
        self.plan.reconcile(self.provider,self.value,1001)
        for bad,now in [(self.provider,2000),({**self.provider,'ownedReady':False},1001),
                        ({**self.provider,'providerUUID':'foreign'},1001)]:
            with self.assertRaises(Refusal): self.plan.claim_home(bad,self.value,now)
        self.assertIsNone(self.plan.state['homeAttempt'])

    def test_no_adoption_without_original_absence_and_pending_create(self):
        for field,value in [('phase','fresh')]:
            bad=copy.deepcopy(self.original);bad['plan'][field]=value
            with self.assertRaises(Refusal): CreateHome(bad,'b'*64)
        bad=copy.deepcopy(self.original);bad['pending']['action']='activate'
        with self.assertRaises(Refusal): CreateHome(bad,'b'*64)

    def test_durable_claim_failure_and_expired_second_read_send_nothing(self):
        sent=[]; saved=[]
        def persist(state):
            saved.append(copy.deepcopy(state))
            if state['homeAttempt'] is not None: raise OSError('inert persistence failure')
        with self.assertRaises(OSError):
            complete_once(self.plan,lambda:self.provider,lambda:self.value,lambda:1001,
                          persist,sent.append)
        self.assertEqual(sent,[])
        self.assertEqual(self.plan.state['phase'],'home-attempted')
        other=CreateHome(self.original,'b'*64)
        times=iter([1001,1001,2000])
        with self.assertRaises(Refusal):
            complete_once(other,lambda:self.provider,lambda:self.value,lambda:next(times),
                          saved.append,sent.append)
        self.assertEqual(sent,[])
        self.assertEqual(saved[-1]['phase'],'home-attempted')

    def test_mutator_lost_response_retains_claim_across_reconstruction(self):
        saved=[]; sent=[]
        def dispatch(operation):
            sent.append(operation)
            raise TimeoutError('inert lost response')
        with self.assertRaises(TimeoutError):
            complete_once(self.plan,lambda:self.provider,lambda:self.value,lambda:1001,
                          lambda state:saved.append(copy.deepcopy(state)),dispatch)
        self.assertEqual(len(sent),1)
        restored=CreateHome(self.original,'b'*64,saved[-1])
        with self.assertRaises(Refusal):
            complete_once(restored,lambda:self.provider,lambda:self.value,lambda:1001,
                          saved.append,sent.append)
        self.assertEqual(len(sent),1)
        bad=copy.deepcopy(self.original);bad['plan']['baseline']['newHomeAbsent']=False
        with self.assertRaises(Refusal): CreateHome(bad,'b'*64)


class AccountObserverTests(unittest.TestCase):
    def query(self,argv,allowed):
        if argv[0].endswith('dscl'):
            value={'dsAttrTypeStandard:UniqueID':['502'],
                   'dsAttrTypeStandard:NFSHomeDirectory':['/Users/keypathqa_12345678'],
                   'dsAttrTypeStandard:RealName':['KeyPath Disposable 12345678']}
            return 0,plistlib.dumps(value).decode(),''
        if argv[0].endswith('dseditgroup'): return 0,'yes member',''
        return 0,'','Secure token is DISABLED for user KeyPath Disposable 12345678\n'

    def test_missing_home_still_observes_account_and_token(self):
        calls=[]
        def query(argv,allowed): calls.append(argv);return self.query(argv,allowed)
        def absent(path): raise FileNotFoundError
        value=selected_account('keypathqa_12345678',{'keypathqa_12345678':502},query,absent,
                               allow_missing_home=True)
        self.assertEqual(value['homeKind'],'absent')
        self.assertEqual(value['secureToken'],'DISABLED')
        self.assertEqual(len(calls),3)
        with self.assertRaises(Refusal):
            selected_account('keypathqa_12345678',{'keypathqa_12345678':502},query,absent)

    def test_permission_error_is_not_missing_and_symlink_remains_visible(self):
        def denied(path): raise PermissionError
        with self.assertRaises(PermissionError):
            selected_account('keypathqa_12345678',{'keypathqa_12345678':502},self.query,denied,
                             allow_missing_home=True)
        value=selected_account('keypathqa_12345678',{'keypathqa_12345678':502},self.query,
                               lambda path:SimpleNamespace(st_mode=stat.S_IFLNK,st_uid=502),
                               allow_missing_home=True)
        self.assertTrue(value['homeSymlink'])
        self.assertEqual(value['homeKind'],'other')


if __name__=='__main__': unittest.main()
