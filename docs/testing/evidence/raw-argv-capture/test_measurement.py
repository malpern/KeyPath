import ast
import json
import pathlib
import types
import hashlib
import tempfile
from unittest import mock
import unittest
import measurement as m

INVENTORY=pathlib.Path('/private/tmp/keypath-runtime-baseline-438d/inventory-python-pinned.json')
SCOPE_VALUE = dict(m.BASE_SCOPE, identityReceipt='/private/tmp/INERT-TEST-IDENTITY.json',identityReceiptSHA256='1'*64,lease='cbx_0123456789ab',providerUUID='889c43d1-54b7-49af-8c07-69380a2ef0a6',bootEpoch=1791118107,deadline=9999999999,baselineInventory=str(INVENTORY),baselineInventorySHA256=m.prepared.BASELINE_SHA)
SCOPE=m.admit_scope(SCOPE_VALUE)

class Fake:
    def __init__(self):
        self.elapsed = 0
        self.calls = []
        self.target_bad = False
        self.stale = False
        self.ready_cost = .1
        self.transport_failure = None
        self.cleanup_errors = []
        self.cleanup_count = 0
        self.worker_none_left = 0
        self.worker_never_ready = False
        self.snapshot_parent_pid = 10
    def wall(self): return 1791118107 + self.elapsed
    def mono(self): return self.elapsed
    def tick(self, label, cost=.1):
        self.calls.append(label)
        self.elapsed += cost
        if self.transport_failure == label: raise RuntimeError('transport255')
    def target(self):
        return dict(pid=50, uid=502, nonce='target', observedAt=self.wall(), active=not self.target_bad,
                    windowKey=True, requestedResponderFocused=True, focusLost=False, focusedMode='normal',
                    secureTest=False, secureInputEnabled=False, held=[], modifiers=0, combinedSessionControl=False,
                    downs=0, ups=0, text='', secureLength=0)
    def report(self):
        return dict(pid=20, uid=502, nonce='worker', timestamp=self.wall()-978307200-(4 if self.stale else 0),
                    state='running', tapActive=True, heldOutputUsages=[], inputCount=0, outputCount=0, accessibility=True,effectiveInputAccess=True,inputAccessSource='current-process.apple-api.modifying-tap-post-event')
    def startup_preflight(self):
        self.tick('preflight')
        return dict(executable=SCOPE.target_executable, binarySHA256=SCOPE.target_sha256)
    def fresh_capture(self, claim):
        self.calls.append('capture');return self.target()
    def start(self):
        self.tick('start')
        return dict(pid=10, uid=502, arguments=['KeyPath','--headless'], binarySHA256=SCOPE.binary_sha256)
    def snapshot(self):
        self.tick('snapshot')
        absent = self.worker_never_ready or self.worker_none_left > 0
        self.worker_none_left = max(0, self.worker_none_left - 1)
        return dict(target=self.target(),
                    processes=[dict(pid=self.snapshot_parent_pid, uid=502,
                                    arguments=['KeyPath','--headless'], binarySHA256=SCOPE.binary_sha256)],
                    worker=None if absent else (dict(pid=20, uid=502, nonce='worker'), self.report()))
    def parent_ready(self, identity):
        self.tick('ready', self.ready_cost)
        return self.report(), dict(parentPID=10, workerPID=20, nonce='worker', readyAt=1791118107,
                                   observedAt=self.wall(), workerReportTimestamp=self.report()['timestamp'],
                                   source='actual-parent-startup-log')
    def verify(self, *args):
        self.tick('identity')
        return dict(account='keypathqa_438d6abc', uid=502, home='/Users/keypathqa_438d6abc', lease=SCOPE.lease,
                    providerUUID=SCOPE.provider_uuid, bootEpoch=1791118107)
    def cleanup(self):
        self.cleanup_count += 1
        return dict(errors=self.cleanup_errors, profileBackup='/Users/keypathqa_438d6abc/original-backup',
                    profileBytewiseRestored=not self.cleanup_errors)
    def sleep(self, seconds): self.elapsed += seconds
    def run(self, scope=SCOPE):
        with mock.patch.object(m,'benchmark_fsync',return_value=[.01,.02,.03]):
            return m.measure(self, self, object(), scope, '2'*64, self.mono, self.wall, self.sleep)

class Tests(unittest.TestCase):
    def testScopeRejectsMissingBindingsAndWrongFrozenTuple(self):
        self.assertEqual(m.admit_scope(SCOPE_VALUE), SCOPE)
        for key, bad in (('identityReceiptSHA256',None), ('identityReceiptSHA256','BAD'),
                         ('targetExecutable',None), ('lease','foreign'),
                         ('providerUUID','bad'),
                         ('bootEpoch',True), ('account','keypathqa_883343c6'),
                         ('uid',True), ('deadline',True), ('productSource','0'*40),
                         ('binarySHA256','0'*64), ('targetSHA256','0'*64),
                         ('targetExecutable','/Users/foreign/target'),
                         ('targetExecutable',SCOPE.home+'/../foreign/target'),
                         ('identityReceipt','/tmp/receipt.json')):
            with self.subTest(key=key,bad=bad), self.assertRaises(RuntimeError):
                m.admit_scope(dict(SCOPE_VALUE, **{key:bad}))
        with self.assertRaises(RuntimeError): m.admit_scope(dict(SCOPE_VALUE,extra=1))

    def testBoundScopeIsFrozen(self):
        from dataclasses import FrozenInstanceError
        with self.assertRaises(FrozenInstanceError): SCOPE.deadline=0

    def testTargetDeploymentMismatchCannotStartParent(self):
        f=Fake()
        def different(_): return dict(executable=SCOPE.target_executable+'-foreign',binarySHA256=SCOPE.target_sha256)
        f.startup_preflight=lambda:different(None)
        r=f.run()
        self.assertFalse(r['passed']);self.assertNotIn('start',f.calls)
        self.assertEqual(r['errorStage'],'setup.preflight');self.assertEqual(f.cleanup_count,1)

    def testSourcePinManifestAndDependenciesRemainExact(self):
        m.verify_sources()
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(m,'ROOT',pathlib.Path(directory)):
            (m.ROOT/'source-pins.json').write_text('{}')
            with self.assertRaises(RuntimeError): m.verify_sources()

    def testLocalBindingPinsReceiptAndRefusesOverwriteOrChangedScope(self):
        identity=m.module(m.IDENTITY,'inert_test_identity')
        with tempfile.TemporaryDirectory(dir='/private/tmp',prefix='inert-d8-binding-') as directory:
            root=pathlib.Path(directory)
            receipt=root/'guest-identity.json'
            value=dict(version=1, **SCOPE.identity_tuple())
            # Explicitly synthetic receipt; never dispatched to any guest.
            receipt.write_text(json.dumps(value));receipt.chmod(0o600)
            sha=hashlib.sha256(receipt.read_bytes()).hexdigest()
            try:
                with mock.patch.object(m,'ROOT',root), mock.patch.object(m,'identity_dependency',return_value=identity):
                    destination=root/'bound-scope.json'
                    digest=m.bind_scope(destination,receipt,sha,SCOPE.target_executable,SCOPE.target_sha256,INVENTORY,m.prepared.BASELINE_SHA,SCOPE.deadline)
                    scope, actual=m.read_scope(destination,digest)
                    self.assertEqual(actual,digest);self.assertEqual(scope.receipt_sha256,sha)
                    self.assertEqual(destination.stat().st_mode & 0o777,0o600)
                    with self.assertRaises(FileExistsError):
                        m.bind_scope(destination,receipt,sha,SCOPE.target_executable,SCOPE.target_sha256,INVENTORY,m.prepared.BASELINE_SHA,SCOPE.deadline)
                    with self.assertRaises(RuntimeError): m.read_scope(destination,'0'*64)
                    root.chmod(0o755)
                    with self.assertRaises(RuntimeError):
                        m.bind_scope(root/'unsafe-parent.json',receipt,sha,SCOPE.target_executable,SCOPE.target_sha256,INVENTORY,m.prepared.BASELINE_SHA,SCOPE.deadline)
                    root.chmod(0o700)
                    with self.assertRaises(RuntimeError):
                        m.bind_scope(root/'wrong.json',receipt,'0'*64,SCOPE.target_executable,SCOPE.target_sha256,INVENTORY,m.prepared.BASELINE_SHA,SCOPE.deadline)
                    receipt.write_text(json.dumps(dict(value,bootEpoch=value['bootEpoch']+1)))
                    changed=hashlib.sha256(receipt.read_bytes()).hexdigest()
                    # A new explicit receipt can bind a new boot; the old scope cannot adopt it.
                    m.bind_scope(root/'new-boot.json',receipt,changed,SCOPE.target_executable,SCOPE.target_sha256,INVENTORY,m.prepared.BASELINE_SHA,SCOPE.deadline)
                    with self.assertRaises(RuntimeError):m.bound_identity(scope,identity)
            finally: receipt.unlink()

    def testCLIRefusesUnreleasedIncompleteOrExpiredScopeBeforeDependencies(self):
        runner=hashlib.sha256(pathlib.Path(m.__file__).read_bytes()).hexdigest()
        for argv in (
                ['measurement.py','--runner-sha256',runner],
                ['measurement.py','--runner-sha256',runner,'--root-reviewed-timing-setup',
                 '--attempt-dir','/private/tmp/INERT-NOT-CREATED'],
                ['measurement.py','--runner-sha256','0'*64,'--root-reviewed-timing-setup',
                 '--attempt-dir','/private/tmp/INERT-NOT-CREATED']):
            with mock.patch.object(m.sys,'argv',argv), mock.patch.object(m,'dependencies') as dispatch:
                with self.assertRaises(RuntimeError): m.main()
                dispatch.assert_not_called()
        argv=['measurement.py','--runner-sha256',runner,'--root-reviewed-timing-setup',
              '--attempt-dir','/private/tmp/INERT-NOT-CREATED','--scope','/private/tmp/INERT-SCOPE',
              '--scope-sha256','2'*64]
        with mock.patch.object(m.sys,'argv',argv), mock.patch.object(m,'read_scope',return_value=(SCOPE,'2'*64)), \
                mock.patch.object(m.time,'time',return_value=SCOPE.deadline-179), mock.patch.object(m,'dependencies') as dispatch:
            with self.assertRaises(RuntimeError): m.main()
            dispatch.assert_not_called()

    def testWhitelistedReasonsAreExactStaticSourceLiterals(self):
        whitelist=json.loads((m.ROOT/'refusal-reasons.json').read_text())
        for reason, entry in whitelist.items():
            name,line=entry['source'].rsplit(':',1)
            tree=ast.parse(pathlib.Path(name).read_text())
            literals=[value.value for node in ast.walk(tree)
                      if isinstance(node,ast.Call) and node.lineno==int(line)
                      for value in node.args if isinstance(value,ast.Constant)]
            self.assertEqual(reason,entry['reason'])
            self.assertIn(reason,literals)
    def testSetupSnapshotAndReadyFailuresHaveExactStagesAndStaticReasons(self):
        class Refusal(RuntimeError): pass
        class NotReady(RuntimeError): pass
        for operation, error, stage in (
                ('snapshot', Refusal('incomplete or ambiguous batch receipt'), 'setup.snapshot'),
                ('parent_ready', NotReady('matching current parent startup completion not observed'), 'setup.parent-ready')):
            f=Fake()
            def fail(*args): raise error
            setattr(f,operation,fail)
            r=f.run()
            self.assertFalse(r['passed']);self.assertEqual(r['samples'],[])
            self.assertEqual(r['errorStage'],stage);self.assertEqual(r['refusalReason'],str(error))
            self.assertEqual(f.cleanup_count,1)
    def testSetupValidationFailuresHaveTheirOwnStage(self):
        f=Fake();f.target_bad=True;r=f.run()
        self.assertEqual(r['errorStage'],'setup.target-check')
        self.assertEqual(r['refusalReason'],'normal target focus lost')
        f=Fake();f.stale=True;r=f.run()
        self.assertEqual(r['errorStage'],'setup.ready-worker-check')
        self.assertEqual(r['refusalReason'],'stale worker')
    def testArbitraryTransportTextIsNotReflectedInReason(self):
        class Refusal(RuntimeError): pass
        for message in ('incomplete or ambiguous batch receipt EXTRA_PRIVATE_TEXT', 'PRIVATE_TEXT'):
            f=Fake()
            def fail(*args): raise Refusal(message)
            f.snapshot=fail;r=f.run()
            self.assertNotIn('refusalReason',r);self.assertNotIn('PRIVATE_TEXT',str(r))
            self.assertEqual(f.cleanup_count,1)
    def testThreeSerialSamplesAndOneCleanup(self):
        f=Fake(); r=f.run()
        self.assertTrue(r['passed'])
        self.assertEqual([v['stage'] for v in r['samples']],
                         [str(n)+'.'+operation for n in range(1,4) for operation in ('identity','snapshot','parent_ready')])
        self.assertEqual(f.calls, ['preflight','start','capture','snapshot','ready']+['identity','snapshot','ready']*3+['snapshot','ready'])
        self.assertEqual(f.cleanup_count, 1)
        self.assertNotIn('target', r)
    def testStartupTransientNoneThenReadyKeepsOneLaunch(self):
        f=Fake();f.worker_none_left=2;r=f.run()
        self.assertTrue(r['passed']);self.assertEqual(f.calls.count('start'),1)
        self.assertEqual(f.calls[:7],['preflight','start','capture','snapshot','snapshot','snapshot','ready'])
        self.assertEqual(r['workerIdentity'],dict(pid=20,uid=502,nonce='worker'))
        self.assertEqual(f.cleanup_count,1)
    def testStartupNeverReadyStopsAtEightSecondsWithoutReadinessOrRelaunch(self):
        f=Fake();f.worker_never_ready=True;started=.2;r=f.run()
        self.assertFalse(r['passed']);self.assertEqual(r['refusalReason'],'worker startup deadline')
        self.assertLessEqual(f.elapsed-started,8.000001)
        self.assertNotIn('ready',f.calls);self.assertEqual(f.calls.count('start'),1)
        self.assertEqual(f.cleanup_count,1)
    def testStartupLeaseDeadlineStopsFurtherSnapshotDispatch(self):
        from dataclasses import replace
        f=Fake();f.worker_never_ready=True
        scope=replace(SCOPE,deadline=f.wall()+.45)
        r=f.run(scope)
        self.assertFalse(r['passed']);self.assertEqual(f.calls.count('snapshot'),1)
        self.assertEqual(r['refusalReason'],'lease dispatch cutoff reached')
        self.assertNotIn('ready',f.calls);self.assertEqual(f.cleanup_count,1)
    def testStartupParentChangeAfterAbsentWorkerRefusesWithoutAdoption(self):
        f=Fake();f.worker_none_left=1;original=f.snapshot
        def snapshot():
            if f.calls.count('snapshot') == 1: f.snapshot_parent_pid=11
            return original()
        f.snapshot=snapshot;r=f.run()
        self.assertFalse(r['passed']);self.assertEqual(r['errorStage'],'setup.snapshot-parent-check')
        self.assertEqual(r['refusalReason'],'owned parent identity changed')
        self.assertEqual(f.calls.count('snapshot'),2);self.assertNotIn('ready',f.calls)
        self.assertEqual(f.calls.count('start'),1);self.assertEqual(f.cleanup_count,1)
    def testStartupSnapshotErrorAfterAbsentWorkerHasNoFallback(self):
        f=Fake();f.worker_none_left=1;original=f.snapshot
        def snapshot():
            if f.calls.count('snapshot') == 1: f.transport_failure='snapshot'
            return original()
        f.snapshot=snapshot;r=f.run()
        self.assertFalse(r['passed']);self.assertEqual(r['errorStage'],'setup.snapshot')
        self.assertEqual(f.calls.count('snapshot'),2);self.assertNotIn('ready',f.calls)
        self.assertEqual(f.calls.count('start'),1);self.assertEqual(f.cleanup_count,1)
    def testStartupStaleTargetAfterAbsentWorkerRefusesWithoutAnotherRead(self):
        f=Fake();f.worker_none_left=1;original=f.snapshot
        def snapshot():
            value=original()
            if f.calls.count('snapshot') == 2: value['target']['observedAt']-=4
            return value
        f.snapshot=snapshot;r=f.run()
        self.assertFalse(r['passed']);self.assertEqual(r['refusalReason'],'stale target')
        self.assertEqual(f.calls.count('snapshot'),2);self.assertNotIn('ready',f.calls)
        self.assertEqual(f.cleanup_count,1)
    def testFreshCaptureFocusRefusalStopsBeforeStartupSnapshot(self):
        f=Fake();f.target_bad=True;r=f.run()
        self.assertFalse(r['passed']);self.assertEqual(f.calls,['preflight','start','capture']);self.assertEqual(f.cleanup_count,1)
    def testStaleReportRefusesBeforeMeasurement(self):
        f=Fake();f.stale=True;r=f.run()
        self.assertFalse(r['passed']);self.assertEqual(r['samples'],[]);self.assertEqual(f.cleanup_count,1)
    def testOverrunRefusesWithoutNextReadOrRetry(self):
        f=Fake(); original=f.verify
        def slow(*args): f.elapsed+=21;return original(*args)
        f.verify=slow;r=f.run()
        self.assertFalse(r['passed']);self.assertEqual(r['errorStage'],'1.identity')
        self.assertEqual(f.calls[-1],'identity');self.assertEqual(f.cleanup_count,1)
    def testTransportFailureNeverReplays(self):
        f=Fake();f.transport_failure='identity';r=f.run()
        self.assertFalse(r['passed']);self.assertEqual(f.calls.count('identity'),1);self.assertEqual(f.cleanup_count,1)
    def testParentReadCannotBorrowAStaleTargetFocusSample(self):
        f=Fake();f.ready_cost=3.1;r=f.run()
        self.assertFalse(r['passed']);self.assertEqual(r['errorStage'],'1.parent_ready')
        self.assertEqual(f.cleanup_count,1)
    def testCleanupFailureCannotPass(self):
        f=Fake();f.cleanup_errors=['owned cleanup failed'];r=f.run()
        self.assertFalse(r['passed']);self.assertEqual(r['cleanup']['errorCount'],1)
    def testImportContainsNoFixtureOrSecretEntrypoint(self):
        source=pathlib.Path(m.__file__).read_text()
        for forbidden in ('create_client(', 'selected_token(', 'verify_usb(', '.command(', '.arm(', '.start_input(', 'sops'):
            self.assertNotIn(forbidden,source)

if __name__ == '__main__': unittest.main()

from contextlib import contextmanager
@contextmanager
def owned_session():
    import uuid,shutil
    nonce=str(uuid.uuid4()).upper();p=pathlib.Path(tempfile.gettempdir())/('keypath-session-'+nonce)
    p.mkdir(mode=0o700)
    try:yield str(p),nonce
    finally:shutil.rmtree(p)

class FsyncTests(unittest.TestCase):
    def testActualPrivateReceiptBenchmarkAndNoReplay(self):
        import subprocess,os,sys,time
        with owned_session()as (directory,nonce):
            root=pathlib.Path(directory);root.chmod(0o700);report=root/'report.json'
            expected=dict(pid=123,uid=os.getuid(),nonce=nonce,ownerPID=122)
            r={k:v for k,v in expected.items()if k!='ownerPID'}|dict(state='running',tapActive=True,heldOutputUsages=[],inputCount=0,outputCount=0,timestamp=time.time()-978307200)
            report.write_text(json.dumps(r));report.chmod(0o600)
            args=[sys.executable,'-I','-B','-c',m.FSYNC_CODE,str(report),json.dumps(expected),'a'*32]
            result=subprocess.run(args,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr);frame=json.loads(result.stdout);self.assertTrue(frame['passed']);samples=frame['samples']
            self.assertEqual(len(samples),3);self.assertTrue(all(x>=0 for x in samples))
            self.assertEqual(len(list(root.glob('timing-fsync-*'))),6)
            self.assertTrue(all(p.stat().st_mode&0o777==0o600 for p in root.glob('timing-fsync-*')))
            self.assertFalse(json.loads(subprocess.run(args,capture_output=True).stdout)['passed'])
            self.assertFalse(list(root.glob('tap-timeout-*')))
    def testFsyncRefusesStaleForeignHeldReportsBeforeWrites(self):
        import subprocess,os,sys,time
        for change in (dict(pid=124),dict(timestamp=0),dict(heldOutputUsages=[4]),dict(inputCount=1),dict(tapActive=False)):
            with owned_session()as (directory,nonce):
                root=pathlib.Path(directory);root.chmod(0o700);report=root/'report.json';expected=dict(pid=123,uid=os.getuid(),nonce=nonce,ownerPID=122)
                report.write_text(json.dumps({k:v for k,v in expected.items()if k!='ownerPID'}|dict(state='running',tapActive=True,heldOutputUsages=[],inputCount=0,outputCount=0,timestamp=time.time()-978307200)|change));report.chmod(0o600)
                result=subprocess.run([sys.executable,'-I','-B','-c',m.FSYNC_CODE,str(report),json.dumps(expected),'b'*32],capture_output=True)
                self.assertEqual(result.returncode,0);frame=json.loads(result.stdout);self.assertFalse(frame['passed']);self.assertIn(frame['stage'],('report-identity-idle','report-freshness'));self.assertEqual(frame['exceptionClass'],'AssertionError');self.assertFalse(list(root.glob('timing-fsync-*')))
    def testExecutorTimingFieldsDerivedFromActualSamples(self):
        f=Fake();r=f.run();self.assertTrue(r['passed']);self.assertEqual(r['callbackFsyncWorstSeconds'],.03)
        self.assertEqual(r['callbackFsyncMeasurement'],dict(method='Python same-volume receipt-pair file-and-directory fsync proxy',sampleCount=3,observedSwiftCallbackLatency=False,guaranteedFutureWorstCase=False))
        self.assertEqual(r['identitySHA256'],SCOPE.receipt_sha256);self.assertEqual(r['delayMillis'],750)
        self.assertEqual(r['triggerMicros'],10000000);self.assertGreater(r['snapshotWorstSeconds'],0);self.assertGreater(r['readyWorstSeconds'],0)

class DiagnosticTests(unittest.TestCase):
    def testExactFiniteTransportAndReadStagesOnly(self):
        guest=types.SimpleNamespace(READ_STAGES=('preflight.signature',),read_stage='preflight.signature.command',read_failure_stage='preflight.signature.command',start_stage='parent.discovery')
        error=RuntimeError('owned guest operation failed: guest-root exit=255; diagnostics suppressed')
        self.assertEqual(m.selected_failure(guest,error),dict(read_stage='preflight.signature.command',read_failure_stage='preflight.signature.command',parentStartStage='parent.discovery',transportVerb='guest-root',transportExitCode=255))
        for text in ('SECRET','owned guest operation failed: guest-root exit=255; diagnostics suppressed SECRET','owned guest operation failed: guest-root exit=2; diagnostics suppressed'):
            self.assertNotIn('transportExitCode',m.selected_failure(guest,RuntimeError(text)))
        guest.read_stage='SECRET';guest.read_failure_stage='SECRET';guest.start_stage='SECRET'
        self.assertEqual(m.selected_failure(guest,RuntimeError('SECRET')),{})
    def testActualStartStagesAtMutationAndSlowDiscoveryWithoutReplay(self):
        class Base:READ_STAGES=()
        G=m.diagnostic_guest(Base,RuntimeError,'inert config')
        for fault,wanted in (('backup','parent.backup-dispatch'),('launch','parent.profile-launch-dispatch'),('discovery','parent.discovery'),('identity','parent.identity')):
            g=G();g.profile='/inert/profile';g.backup='/inert/backup';g.account='inert';g.uid=502;g.app='/inert/app';g.check_account=lambda:None;calls=[]
            def run(command):
                calls.append(command)
                if len(calls)==(1 if fault=='backup'else 2)and fault in('backup','launch'):raise RuntimeError('owned guest operation failed: guest-root exit=79; diagnostics suppressed')
            g.run=run;g.processes=lambda:[(42,502,['KeyPath','--headless'])];g.identity=lambda *a:dict(pid=42)
            clock=[0,0,9]if fault=='discovery'else[0,0,1,9]
            with mock.patch.object(m.time,'monotonic',side_effect=clock):
                with self.assertRaises(RuntimeError)as caught:g.start()
            self.assertEqual(m.selected_failure(g,caught.exception)['parentStartStage'],wanted)
            self.assertEqual(len(calls),1 if fault=='backup'else 2)
    def testFailureFieldsCapturedBeforeCleanupCanChangeReadStage(self):
        f=Fake();f.READ_STAGES=('preflight.signature',)
        def fail(*_):
            f.read_failure_stage='preflight.signature.command';raise RuntimeError('owned guest operation failed: guest-root exit=255; diagnostics suppressed')
        f.startup_preflight=fail;r=f.run();self.assertFalse(r['passed']);self.assertEqual(r['transportExitCode'],255);self.assertEqual(r['read_failure_stage'],'preflight.signature.command');self.assertEqual(f.cleanup_count,1)

class ReadyFilterTests(unittest.TestCase):
    def testGeneratedBoundedCollectorPreservesReadyBefore187NoiseRows(self):
        import subprocess,datetime
        old=m.module(m.HARNESS.with_name('parent_readiness.py'),'inert_original_readiness')
        fixed=m.module(m.ROOT/'parent_readiness.py','inert_fixed_readiness')
        nonce='912D0000-0000-4000-8000-000000000000';parent=27838;worker=27947;now=1791123600
        stamp=datetime.datetime.fromtimestamp(now-1,datetime.timezone.utc).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
        line=f'[{stamp}] [INFO] [KeyPath] Session runtime ready (test) parentPID={parent} workerPID={worker} nonce={nonce}'
        identity=types.SimpleNamespace(app='/Users/public/Applications/KeyPath.app',home='/Users/public',uid=502,guard=lambda:'true')
        exe=identity.app+'/Contents/MacOS/KeyPath';path=f'/var/folders/inert/T/keypath-session-{nonce}/report.json';args=f'{exe} --session-runtime --session-owner {parent} --session-nonce {nonce} --session-report {path}'
        marker='KEYPATH_READY_READ_'+'a'*32
        report=dict(pid=worker,uid=502,nonce=nonce,state='running',tapActive=True,timestamp=now-978307200)
        with tempfile.TemporaryDirectory(dir='/private/tmp')as directory:
            log=pathlib.Path(directory)/'log';log.write_text('prefix\n'+line+'\n'+'noise row\n'*187)
            for module,passes in ((old,False),(fixed,True)):
                command=module.log_command(identity,parent,worker,nonce,path,args,marker)
                start=command.index('/usr/bin/tail -c 65536');end=command.index('; ',start)
                pipeline=command[start:end].replace(m.shlex.quote(identity.home+'/Library/Logs/KeyPath/keypath-debug.log'),m.shlex.quote(str(log)))
                result=subprocess.run(['/bin/zsh','-c','set -euo pipefail; '+pipeline],capture_output=True,text=True)
                self.assertEqual(result.returncode,0)
                output=f'KEYPATH_PARENT_LOG_V1 {now} +0000\n'+result.stdout+'\n'+marker+'\n'
                if passes:
                    evidence=module.admit(output,marker,parent,worker,nonce,502,report,now-2,now)
                    self.assertEqual(evidence['workerPID'],worker)
                    with self.assertRaises(module.NotReady):module.admit(output,marker,parent,worker+1,nonce,502,report|dict(pid=worker+1),now-2,now)
                else:
                    with self.assertRaises(module.NotReady):module.admit(output,marker,parent,worker,nonce,502,report,now-2,now)

class BenchmarkFrameTests(unittest.TestCase):
    def testFailedFrameCannotBecomeSamplesOrPassedReceipt(self):
        guest=types.SimpleNamespace(parent=10,identity=lambda *a:None,run=lambda _:json.dumps(dict(passed=False,stage='report-freshness',exceptionClass='AssertionError',errno=None)))
        worker=dict(pid=20,uid=502,nonce='inert',arguments=['inert'],reportPath='/inert/report.json')
        with self.assertRaisesRegex(RuntimeError,'benchmark refused'):m.benchmark_fsync(guest,worker,SCOPE)
        self.assertEqual(guest.benchmark_failure['stage'],'report-freshness')
        for frame in (dict(passed=False,stage='SECRET',exceptionClass='AssertionError',errno=None),dict(passed=True,samples=[1,2]),dict(passed=1,samples=[1,2,3])):
            guest.run=lambda _,value=frame:json.dumps(value)
            with self.assertRaises(RuntimeError):m.benchmark_fsync(guest,worker,SCOPE)

class AliasBenchmarkTests(unittest.TestCase):
    def testActualCodeRefusesAdditionalSymlinkBeforeReceiptWrites(self):
        import subprocess,os,sys,time,uuid
        with owned_session()as (directory,nonce):
            raw=pathlib.Path(directory);moved=raw.with_name('inert-moved-'+uuid.uuid4().hex)
            raw.rename(moved);raw.symlink_to(moved,target_is_directory=True)
            try:
                report=moved/'report.json';expected=dict(pid=123,uid=os.getuid(),nonce=nonce,ownerPID=122)
                report.write_text(json.dumps({k:v for k,v in expected.items()if k!='ownerPID'}|dict(state='running',tapActive=True,heldOutputUsages=[],inputCount=0,outputCount=0,timestamp=time.time()-978307200)));report.chmod(0o600)
                result=subprocess.run([sys.executable,'-I','-B','-c',m.FSYNC_CODE,str(raw/'report.json'),json.dumps(expected),'c'*32],capture_output=True,text=True)
                frame=json.loads(result.stdout);self.assertFalse(frame['passed']);self.assertEqual(frame['stage'],'directory-metadata');self.assertFalse(list(moved.glob('timing-fsync-*')))
            finally:raw.unlink();moved.rename(raw)
