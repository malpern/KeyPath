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
                     timestamp=NOW - 978307200 - .1, heldOutputUsages=[]), **changes)


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



class D8ReadinessBoundaryTests(unittest.TestCase):
    def setUp(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('d8_test_harness', SOURCE / 'held-secure-acceptance.py')
        self.harness = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.harness)
        self.ready = self.harness.readiness_module()

    def testTransientClassIsStableAcrossBothWorkerGenerations(self):
        # Pollers and the guest observer must recognize the same transient failure.
        self.assertIs(self.ready, self.harness.readiness_module())
        guest = object.__new__(self.harness.Guest)
        guest.parent = PARENT
        guest.parent_launch_requested_at = NOW - 20
        guest.lease = 'inert-owned-lease'
        guest.guest_identity = types.SimpleNamespace(app=HOME + '/Applications/KeyPath.app', home=HOME,
                                                     uid=UID, guard=lambda: 'OWNED')
        guest.uid = UID
        calls = []
        guest.observation_scope = lambda: calls.append('identity')
        state = {'complete': False, 'value': report()}
        def observe(*args):
            calls.append('combined-read')
            marker = args[-1].rsplit(' ', 1)[-1]
            line = None if state['complete'] else 'worker tap active without parent completion'
            log = observed(line, marker=marker).removesuffix('\n' + marker + '\n')
            return log + '\n' + marker + '_WORKER_REPORT\n' + json.dumps(state['value']) + '\n' + marker + '\n'
        guest.pilot = types.SimpleNamespace(observe=observe)
        identity = dict(pid=WORKER, uid=UID, nonce=NONCE, reportPath=PATH, rawArguments=ARGS)
        from unittest.mock import patch
        with patch.object(self.harness.time, 'time', return_value=NOW):
            with self.assertRaises(self.ready.NotReady):
                guest.parent_ready(identity)
            state['complete'] = True
            actual, evidence = guest.parent_ready(identity)
            self.assertEqual(actual, report())
            self.assertEqual(evidence['nonce'], NONCE)
            # A resumed worker cannot borrow the old generation's actual ready log.
            new_nonce = 'BD6B457F-2DBB-4604-8D8C-9DBC4B87D0EF'
            resumed = dict(identity, pid=WORKER + 1, nonce=new_nonce,
                           reportPath=PATH.replace(NONCE, new_nonce),
                           rawArguments=ARGS.replace(NONCE, new_nonce))
            state['value'] = report(pid=WORKER + 1, nonce=new_nonce)
            with self.assertRaises(self.ready.NotReady):
                guest.parent_ready(resumed)
        self.assertEqual(calls, ['identity', 'combined-read'] * 3)

    def testActualInitialAndResumedPredicatesWaitAndPropagateHardFailures(self):
        # Exercise the actual nested production predicates with inert observers.
        tree = ast.parse((SOURCE / 'held-secure-acceptance.py').read_text())
        campaign = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'Campaign')
        execute = next(n for n in campaign.body if isinstance(n, ast.FunctionDef) and n.name == 'execute')
        predicates = [n for n in execute.body if isinstance(n, ast.FunctionDef) and n.name in ('ready', 'resumed')]
        identity = dict(pid=WORKER, uid=UID, nonce=NONCE)
        old = {'identity': dict(identity, pid=WORKER - 1, nonce='old')}
        state = {'error': self.ready.NotReady('not yet'), 'calls': 0}
        def parent_ready(value):
            state['calls'] += 1
            if state['error']:
                raise state['error']
            return report(), {'nonce': value['nonce']}
        owner = types.SimpleNamespace(latest={'worker': (identity, report())},
                                      guest=types.SimpleNamespace(parent_ready=parent_ready),
                                      client=types.SimpleNamespace(status=lambda: {}))
        ns = dict(self=owner, readiness=self.ready, old=old, release={'up': {'sequence': 1}}, run='inert',
                  time=types.SimpleNamespace(time=lambda: NOW), worker=lambda *a: None,
                  require=self.harness.require, no_resurrection=lambda *a: None, physical_hold=lambda *a: None)
        exec(compile(ast.Module(body=predicates, type_ignores=[]), 'actual-d8-predicates', 'exec'), ns)
        for name in ('ready', 'resumed'):
            with self.subTest(generation=name):
                state['error'] = self.ready.NotReady('not yet')
                self.assertIsNone(ns[name]({}))
                state['error'] = RuntimeError('worker identity mismatch')
                with self.assertRaisesRegex(RuntimeError, 'identity mismatch'):
                    ns[name]({})
                state['error'] = None
                self.assertEqual(ns[name]({})['parentReadiness']['nonce'], NONCE)
        self.assertEqual(state['calls'], 6)


if __name__ == '__main__':
    unittest.main()
