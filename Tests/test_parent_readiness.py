import ast
import datetime
import json
import pathlib
import sys
import subprocess
import types
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Scripts/experiments/session-runtime'
sys.path.insert(0, str(SOURCE))
import parent_readiness as readiness

PARENT, WORKER, UID = 6234, 6293, 502
NONCE = 'AD6B457F-2DBB-4604-8D8C-9DBC4B87D0EF'
PATH = '/var/folders/9d/example/T/keypath-session-' + NONCE + '/report.json'
HOME = '/Users/keypathqa_883343c6'
EXE = HOME + '/Applications/KeyPath.app/Contents/MacOS/KeyPath'
ARGS = EXE + ' --session-runtime --session-report ' + PATH + ' --session-nonce ' + NONCE + ' --session-owner ' + str(PARENT) + ' --session-port 37001'
NOW = 1791111400.5
MARKER = 'KEYPATH_READY_READ_' + 'a' * 32


def report(**changes):
    return dict(dict(pid=WORKER, uid=UID, nonce=NONCE, state='running', tapActive=True,
                     timestamp=NOW - 978307200 - .1), **changes)


def observed(line=None, marker=MARKER, at=NOW):
    stamp = datetime.datetime.fromtimestamp(at - 1, datetime.timezone(datetime.timedelta(hours=-7)))
    if line is None:
        line = (stamp.strftime('[%Y-%m-%d %H:%M:%S.') + '500] [INFO] '
                '[ServiceLifecycleCoordinator+SessionRuntime.swift:91 startSessionRuntime(reason:generation:)] '
                'Session runtime ready (Headless auto-start) parentPID=' + str(PARENT)
                + ' workerPID=' + str(WORKER) + ' nonce=' + NONCE)
    return 'KEYPATH_PARENT_LOG_V1 ' + str(int(at)) + ' -0700\n' + line + '\n\n' + marker + '\n'


class ReadinessTests(unittest.TestCase):
    def admit(self, output=None, value=None):
        return readiness.admit(output or observed(), MARKER, PARENT, WORKER, NONCE, UID,
                               value or report(), NOW - 20, NOW)

    def testActualMatchingCompletionAdmitsFreshWorker(self):
        evidence = self.admit()
        self.assertEqual(evidence['source'], 'actual-parent-startup-log')
        self.assertEqual(evidence['workerPID'], WORKER)

    def testHealthyWorkerWithoutCompletionDoesNotAdmit(self):
        with self.assertRaises(readiness.NotReady):
            self.admit(observed('parent launch returned workerPID=' + str(WORKER)))

    def testWrongParentWorkerOrNonceCannotBorrowReadyLog(self):
        for old, new in [('parentPID=6234', 'parentPID=6235'), ('workerPID=6293', 'workerPID=6294'),
                         (NONCE, 'BD6B457F-2DBB-4604-8D8C-9DBC4B87D0EF')]:
            with self.subTest(field=old), self.assertRaises(readiness.NotReady):
                self.admit(observed().replace(old, new))

    def testHistoricalCompletionCannotAdmitNewCampaign(self):
        old = observed(at=NOW - 60).splitlines()[1]
        with self.assertRaises(readiness.NotReady):
            self.admit(observed(old))

    def testMalformedIncompleteOrStaleLogObservationRefused(self):
        for output in [observed().replace(' -0700', ' +9960'), observed().replace(MARKER, ''),
                       observed().replace(str(int(NOW)), str(int(NOW - 4)), 1),
                       observed().replace('[2026-', '[not-a-date-', 1)]:
            with self.subTest(output=output[:80]), self.assertRaises(readiness.NotReady):
                self.admit(output)

    def testWrongIdentityTerminalAndStaleWorkerCannotAdmit(self):
        for changes in [dict(uid=501), dict(pid=6294), dict(nonce='other'), dict(state='secureInput'),
                        dict(tapActive=False), dict(timestamp=NOW - 978307200 - 3), dict(pid=True)]:
            with self.subTest(changes=changes), self.assertRaises(RuntimeError):
                self.admit(value=report(**changes))

    def testCombinedActualReportRequiresCompleteUniqueBoundedJSON(self):
        log = observed().removesuffix('\n' + MARKER + '\n')
        frame = log + '\n' + MARKER + '_WORKER_REPORT\n' + json.dumps(report()) + '\n' + MARKER + '\n'
        split_log, value = readiness.split_observation(frame, MARKER)
        self.assertEqual(self.admit(split_log, value)['workerPID'], WORKER)
        for broken in [frame.removesuffix('\n'), frame.replace(json.dumps(report()), '{"pid":1,"pid":2}'),
                       frame.replace(json.dumps(report()), '[]'), frame.replace(json.dumps(report()), 'x' * 16385)]:
            with self.assertRaises(readiness.NotReady):
                readiness.split_observation(broken, MARKER)

    def testExactlyOneKnownProviderExtraNewlineIsAccepted(self):
        log = observed().removesuffix('\n' + MARKER + '\n')
        frame = log + '\n' + MARKER + '_WORKER_REPORT\n' + json.dumps(report()) + '\n' + MARKER + '\n'
        for ending in ['', '\n']:
            parsed, value = readiness.split_observation(frame + ending, MARKER)
            self.assertEqual(self.admit(parsed, value)['workerPID'], WORKER)
        for ending in ['\n\n', '\r\n', '\n' + MARKER + '\n', 'noise']:
            with self.assertRaises(readiness.NotReady):
                readiness.split_observation(frame + ending, MARKER)

    def testReadCommandRequiresExactWorkerLaunchBinding(self):
        identity = types.SimpleNamespace(app=HOME + '/Applications/KeyPath.app', home=HOME, uid=UID, guard=lambda: 'test OWNED = OWNED')
        command = readiness.log_command(identity, PARENT, WORKER, NONCE, PATH, ARGS, MARKER)
        self.assertIn('/usr/bin/tail -c 65536', command)
        self.assertIn('/usr/bin/tail -n 128', command)
        for args in [ARGS.replace('--session-owner 6234', '--session-owner 6235'),
                     ARGS + ' --session-nonce ' + NONCE, ARGS.replace('--session-runtime', '--session-capabilities')]:
            with self.assertRaises(ValueError):
                readiness.log_command(identity, PARENT, WORKER, NONCE, PATH, args, MARKER)

    def testActualPSAndProviderNewlinesCompareCanonicalArguments(self):
        identity = types.SimpleNamespace(app=HOME + '/Applications/KeyPath.app', home=HOME, uid=UID,
                                         guard=lambda: 'test OWNED = OWNED')
        query = '$(/bin/ps -p ' + str(WORKER) + ' -o args=)'
        for suffix in ['', '\n', '\n\n']:
            command = readiness.log_command(identity, PARENT, WORKER, NONCE, PATH, ARGS + suffix, MARKER)
            check = next(piece for piece in command.split('; ') if piece.startswith('test "' + query + '"'))
            # Exercise the exact generated comparison using inert ps stdout,
            # without querying any actual host or guest process.
            simulated = check.replace(query, "$(printf '%s\\n' " + __import__('shlex').quote(ARGS) + ')')
            for shell in ['/bin/bash', '/bin/zsh']:
                result = subprocess.run([shell, '-c', simulated], capture_output=True, text=True, timeout=3)
                self.assertEqual(result.returncode, 0, result.stderr)

    def testProcessArgumentFramingRejectsNoiseAndAdditionalRows(self):
        for raw in [ARGS + '\n\n\n', ARGS + '\r\n', ARGS + '\nnoise\n', '\n' + ARGS + '\n']:
            with self.subTest(raw=raw[-20:]), self.assertRaises(ValueError):
                readiness.normalize_worker_args(raw)

    def testFailedEarlyIdentityCheckStopsBeforeObservation(self):
        identity = types.SimpleNamespace(app=HOME + '/Applications/KeyPath.app', home=HOME, uid=UID,
                                         guard=lambda: 'false && true')
        command = readiness.log_command(identity, PARENT, WORKER, NONCE, PATH, ARGS, MARKER)
        # Run only the generated identity prefix plus an inert sentinel; never
        # execute its actual process queries or read a real host/guest log.
        prefix = command.split('; test "$(/bin/ps', 1)[0]
        for shell in ['/bin/bash', '/bin/zsh']:
            result = subprocess.run([shell, '-c', prefix + '; echo OBSERVER_REACHED'],
                                    capture_output=True, text=True, timeout=3)
            self.assertEqual(result.returncode, 79)
            self.assertNotIn('OBSERVER_REACHED', result.stdout)

    def production_namespace(self):
        # Execute the actual production admission functions with read-only fake
        # observers; never import the CLI or reach fixture/guest actions.
        tree = ast.parse((SOURCE / 'parent-acceptance.py').read_text())
        functions = [node for node in tree.body if isinstance(node, ast.FunctionDef)
                     and node.name in ('staged_call', 'verify_identity', 'child', 'require_parent_ready')]
        calls = []
        identity = types.SimpleNamespace(app=HOME + '/Applications/KeyPath.app', home=HOME, uid=UID,
                                         guard=lambda: 'test OWNED = OWNED', verify=lambda *args: calls.append('identity'))
        state = {'complete': False, 'report_error': None, 'combined_report': None}
        def read_report(*args):
            if state['report_error']:
                raise RuntimeError(state['report_error'])
            return report()
        def observe(*args):
            calls.append('read-log')
            command = args[-1]
            marker = command.rsplit(' ', 1)[-1]
            log = observed(None if state['complete'] else 'worker physically running', marker=marker).removesuffix('\n' + marker + '\n')
            return log + '\n' + marker + '_WORKER_REPORT\n' + json.dumps(state['combined_report'] or report()) + '\n' + marker + '\n'
        pilot = types.SimpleNamespace(observe=observe)
        namespace = dict(parent_readiness=readiness, identity=identity, p=pilot, lease='cbx_883343c6fafd',
                         owner=PARENT, launch_requested_at=NOW - 20, r={},
                         uuid=types.SimpleNamespace(uuid4=lambda: types.SimpleNamespace(hex='a' * 32)),
                         time=types.SimpleNamespace(time=lambda: NOW),
                         t=types.SimpleNamespace(report=read_report),
                         discover=lambda *args: [(WORKER, ARGS)], shlex=__import__('shlex'))
        exec(compile(ast.Module(body=functions, type_ignores=[]), 'production-admission', 'exec'), namespace)
        return namespace, state, calls

    def testProductionChildWaitsForRealBoundMarker(self):
        namespace, state, calls = self.production_namespace()
        self.assertIsNone(namespace['child']())
        state['complete'] = True
        self.assertEqual(namespace['child']()[:3], (WORKER, PATH, NONCE))
        self.assertEqual(calls, ['identity', 'read-log', 'identity', 'read-log'])

    def testProductionChildMissingStaleThenValidReport(self):
        namespace, state, calls = self.production_namespace()
        state['complete'] = True
        for error in ['session report unavailable', 'stale worker report']:
            state['report_error'] = error
            self.assertIsNone(namespace['child']())
        self.assertEqual(calls, [])
        state['report_error'] = None
        self.assertEqual(namespace['child']()[:3], (WORKER, PATH, NONCE))

    def testProductionChildDoesNotSwallowIdentityOrOtherErrors(self):
        namespace, state, calls = self.production_namespace()
        for error in ['worker identity mismatch', 'guest account/home/UID/console identity mismatch',
                      'session report unavailable: wrong nonce', 'transport unavailable']:
            state['report_error'] = error
            with self.subTest(error=error), self.assertRaisesRegex(RuntimeError, error):
                namespace['child']()
        self.assertEqual(calls, [])

    def testCombinedReportIdentityMismatchAlsoPropagates(self):
        namespace, state, calls = self.production_namespace()
        state['complete'] = True
        for changes in [dict(uid=501), dict(pid=6294), dict(nonce='other')]:
            state['combined_report'] = report(**changes)
            with self.subTest(changes=changes), self.assertRaisesRegex(RuntimeError, 'worker identity mismatch') as caught:
                namespace['child']()
            self.assertNotIsInstance(caught.exception, readiness.NotReady)


    def diagnostic_namespace(self, **values):
        tree = ast.parse((SOURCE / 'parent-acceptance.py').read_text())
        names = {'staged_call', 'verify_identity', 'observe', 'run', 'discover', 'prepare'}
        functions = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in names]
        namespace = dict(r={'launchMutationAttempted': False}, lease='owned-test',
                         app=HOME + '/Applications/KeyPath.app', identity=None, p=None)
        namespace.update(values)
        exec(compile(ast.Module(body=functions, type_ignores=[]), 'production-diagnostics', 'exec'), namespace)
        return namespace

    def testIdentityProviderAndGuestReadsHaveDistinctFailureStages(self):
        class Identity:
            def verify(self, pilot, lease):
                pilot.lab(lease, 'status')
                return pilot.observe(lease, 'guest-root', '--', 'PUBLIC-GUARD')
        for failure, expected in [('status', 'launch.identity.provider-status'),
                                  ('guest-root', 'launch.identity.guest-identity')]:
            calls = []
            def operation(*args):
                calls.append(args[1])
                if args[1] == failure:
                    raise RuntimeError('exit=255; diagnostics suppressed')
                return 'PUBLIC'
            namespace = self.diagnostic_namespace(identity=Identity(),
                                                  p=types.SimpleNamespace(lab=operation, observe=operation))
            with self.assertRaises(RuntimeError):
                namespace['verify_identity']('launch.identity')
            self.assertEqual(namespace['r']['stage'], expected)
            self.assertNotIn('mutationDispatchAttempts', namespace['r'])
            self.assertEqual(calls, ['status'] if failure == 'status' else ['status', 'guest-root'])

    def testUnknownMutationResponseRecordsIntentAndDoesNotReplay(self):
        calls = []
        identity = types.SimpleNamespace(verify=lambda *args: None, guard=lambda: 'PUBLIC-GUARD')
        def fail(*args):
            calls.append(args)
            raise RuntimeError('exit=255; diagnostics suppressed')
        namespace = self.diagnostic_namespace(identity=identity, p=types.SimpleNamespace(lab=fail))
        with self.assertRaises(RuntimeError):
            namespace['run']('PUBLIC-COMMAND', 'launch')
        self.assertEqual(len(calls), 1)
        self.assertEqual(namespace['r']['stage'], 'launch.dispatch')
        self.assertTrue(namespace['r']['launchMutationAttempted'])
        self.assertEqual(namespace['r']['mutationDispatchAttempts'], ['launch'])
        self.assertEqual(calls[0][-1], 'true; PUBLIC-GUARD && PUBLIC-COMMAND')

    def testProcessAndReadyReadsIdentifyTheirExactCall(self):
        identity = types.SimpleNamespace(verify=lambda *args: None)
        def fail(*args):
            raise RuntimeError('exit=255; diagnostics suppressed')
        namespace = self.diagnostic_namespace(identity=identity, p=types.SimpleNamespace(observe=fail))
        with self.assertRaises(RuntimeError):
            namespace['discover']('parent.discovery')
        self.assertEqual(namespace['r']['stage'], 'parent.discovery.process-scan')
        namespace, state, calls = self.production_namespace()
        namespace['p'].observe = fail
        with self.assertRaises(RuntimeError):
            namespace['require_parent_ready'](WORKER, PATH, NONCE, ARGS)
        self.assertEqual(namespace['r']['stage'], 'ready.log-and-report')

    def testPrimaryFailureStageSurvivesCleanupStage(self):
        tree = ast.parse((SOURCE / 'parent-acceptance.py').read_text())
        campaign = next(node for node in tree.body if isinstance(node, ast.Try))
        handler = campaign.handlers[0]
        namespace = self.diagnostic_namespace(e=RuntimeError('read failed'))
        namespace['r']['stage'] = 'child.worker-report'
        exec(compile(ast.Module(body=handler.body, type_ignores=[]), 'production-failure-receipt', 'exec'), namespace)
        namespace['staged_call']('cleanup.profile-backup-read', lambda: 'PUBLIC')
        self.assertEqual(namespace['r']['errorStage'], 'child.worker-report')
        self.assertEqual(namespace['r']['error'], 'read failed')
        self.assertEqual(namespace['r']['stage'], 'cleanup.profile-backup-read')


if __name__ == '__main__':
    unittest.main()
