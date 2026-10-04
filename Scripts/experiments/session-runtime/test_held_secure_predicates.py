"""Synthetic D8 acceptance evidence: negative receipts must never become passes."""
import copy
import unittest

from held_secure_predicates import (Refusal, TargetHistory, applied, control_down,
                                   control_released, exact_trace, no_resurrection,
                                   physical_hold, worker, StoppedWorkerEvidence)


def focused(mode='normal'):
    return dict(active=True, windowKey=True, focusLost=False, focusedMode=mode,
                requestedResponderFocused=True)


def event(sequence, control, at, mode='normal', secure=False):
    return dict(focused(mode), sequence=sequence, control=control, keyCode=59,
                observedAt=1000 + at, monotonicAt=at, mode=mode,
                secureInputEnabled=secure)


def snapshot(at=10):
    return dict(focused(), pid=17, uid=502, nonce='target-nonce',
                commandPath='/Users/owned/rig-target-control-17-target-nonce/command.json',
                observedAt=1000 + at, monotonicAt=at, secureTest=False,
                secureInputEnabled=False, combinedSessionControl=False,
                commandSequence=0, commandConsumedSequence=0, commandStatus='awaitingCommand',
                downs=0, ups=0, qDowns=0, aDowns=0, controlA=0,
                flagsChangedJournal=[], flagsChangedDropped=0,
                combinedSessionControlJournal=[event(1, False, at)],
                combinedSessionControlDropped=40, modeTransitions=[], modeTransitionsDropped=0)


class HeldSecureEvidenceTests(unittest.TestCase):
    def test_prephase_lifetime_drops_allowed_but_phase_anchor_eviction_fails(self):
        first = snapshot()
        history = TargetHistory(first, 1010, 502)
        history.begin('held-transition', first)
        next_value = snapshot(11)
        next_value['combinedSessionControlJournal'] = first['combinedSessionControlJournal'] + [event(2, False, 11)]
        history.check(next_value, 1011)
        evicted = snapshot(12)
        evicted['combinedSessionControlDropped'] = 42
        with self.assertRaisesRegex(Refusal, 'anchor evicted'):
            history.check(evicted, 1012)

    def test_stale_publication_or_wrong_actual_focus_is_not_retryable(self):
        for mutation, message in ((lambda r: r.update(observedAt=1000), 'stale'),
                                  (lambda r: r.update(windowKey=False), 'focus'),
                                  (lambda r: r.update(requestedResponderFocused=False), 'focus'),
                                  (lambda r: r.update(uid=501), 'identity')):
            with self.subTest(message=message):
                receipt = snapshot()
                mutation(receipt)
                with self.assertRaisesRegex(Refusal, message):
                    TargetHistory(receipt, 1010, 502)
        history = TargetHistory(snapshot(), 1010, 502)
        with self.assertRaisesRegex(Refusal, 'did not advance'):
            history.check(snapshot(), 1010.1)

    def test_clear_ledger_and_combined_flags_cannot_replace_delivered_control_up(self):
        down = event(2, True, 11)
        receipt = snapshot(14)
        receipt.update(focused('secure'), secureTest=True, secureInputEnabled=True)
        receipt['flagsChangedJournal'] = [down]
        receipt['combinedSessionControlJournal'] = [event(4, False, 14, 'secure', True)]
        stopped = dict(state='secureInput', tapActive=False, heldOutputUsages=[])
        with self.assertRaisesRegex(Refusal, 'delivered Control up'):
            control_released(receipt, stopped, down, 12, True)
        receipt['flagsChangedJournal'].append(event(3, False, 13, 'secure', True))
        self.assertEqual(control_released(receipt, stopped, down, 12, True)['sequence'], 3)
        with self.assertRaisesRegex(Refusal, 'old worker'):
            control_released(receipt, stopped, down, 12, False)
        receipt['flagsChangedJournal'][-1]['monotonicAt'] = 11.5
        with self.assertRaisesRegex(Refusal, 'delivered Control up'):
            control_released(receipt, stopped, down, 12, True)

    def test_hold_evidence_requires_delivery_plus_exact_owned_ledger(self):
        receipt = snapshot(12)
        receipt['flagsChangedJournal'] = [event(2, True, 11)]
        self.assertEqual(control_down(receipt, dict(heldOutputUsages=[224]), 1)['sequence'], 2)
        with self.assertRaises(Refusal):
            control_down(receipt, dict(heldOutputUsages=[]), 1)
        with self.assertRaises(Refusal):
            control_down(receipt, dict(heldOutputUsages=[224]), 2)

    def test_physical_release_tail_is_not_evidence_q_is_still_held(self):
        status = dict(runId='owned-run', state='running', reportsSubmitted=1)
        physical_hold(status, 'owned-run')
        for changed in (dict(reportsSubmitted=2), dict(state='complete'), dict(runId='foreign')):
            with self.assertRaises(Refusal):
                physical_hold(dict(status, **changed), 'owned-run')

    def test_native_q_repeats_allowed_but_control_resurrection_rejected(self):
        receipt = snapshot(20)
        receipt.update(downs=15, qDowns=15, ups=0)
        receipt['flagsChangedJournal'] = [event(3, False, 13)]
        no_resurrection(receipt, dict(heldOutputUsages=[]), 3)
        for journal in ('flagsChangedJournal', 'combinedSessionControlJournal'):
            changed = copy.deepcopy(receipt)
            changed[journal].append(event(5, True, 19))
            with self.assertRaisesRegex(Refusal, 'resurrected'):
                no_resurrection(changed, dict(heldOutputUsages=[]), 3)
        with self.assertRaisesRegex(Refusal, 'resurrected'):
            no_resurrection(receipt, dict(heldOutputUsages=[224]), 3)

    def test_requested_secure_mode_without_carbon_or_responder_is_not_applied(self):
        receipt = snapshot(20)
        receipt.update(focused('secure'), secureTest=True, secureInputEnabled=True,
                       commandSequence=1, commandConsumedSequence=1, commandStatus='applied')
        receipt['modeTransitions'] = [dict(event(1, False, 19, 'secure', True), responderAccepted=True)]
        applied(receipt, 'secure', 1)
        for change in (dict(secureInputEnabled=False), dict(commandSequence=2),
                       dict(commandStatus='responderRejected'), dict(focusedMode='normal')):
            with self.assertRaises(Refusal):
                applied(dict(receipt, **change), 'secure', 1)

    def test_final_physical_trace_must_include_owned_exact_all_up(self):
        rows = [[0, 20, 0, 0, 0, 0, 0], [0] * 7]
        trace = [dict(modifiers=row[0], keys=row[1:]) for row in rows]
        status = dict(runId='r', state='complete', reportsSubmitted=2)
        exact_trace(trace, rows, status, 'r')
        with self.assertRaises(Refusal):
            exact_trace(trace[:-1], rows, status, 'r')
        with self.assertRaises(Refusal):
            exact_trace(trace, rows, dict(status, runId='foreign'), 'r')

    def test_worker_receipt_rejects_old_generation_and_stale_terminal_state(self):
        value = dict(pid=29, uid=502, nonce='generation-2', timestamp=1010 - 978307200,
                     state='running', tapActive=True)
        worker(value, (29, 502, 'generation-2'), 1010)
        with self.assertRaisesRegex(Refusal, 'identity'):
            worker(value, (28, 502, 'generation-1'), 1010)
        with self.assertRaisesRegex(Refusal, 'stale'):
            worker(dict(value, state='secureInput', tapActive=False), (29, 502, 'generation-2'), 1014, 'secureInput')

    def test_retired_phase_can_roll_off_ring_but_live_phase_cannot(self):
        first = snapshot()
        history = TargetHistory(first, 1010, 502)
        history.begin('held-transition', first)
        with self.assertRaisesRegex(Refusal, 'accepted evidence'):
            history.retire('held-transition', None)
        history.retire('held-transition', '0042-accepted-held-transition.json')
        later = snapshot(60)
        later['combinedSessionControlJournal'] = [event(512, False, 60)]
        later['combinedSessionControlDropped'] = 551
        history.check(later, 1060)
        history.begin('fresh-tap', later)
        evicted = snapshot(61)
        evicted['combinedSessionControlJournal'] = [event(513, False, 61)]
        evicted['combinedSessionControlDropped'] = 552
        with self.assertRaisesRegex(Refusal, 'anchor evicted'):
            history.check(evicted, 1061)

    def test_phase_anchors_are_immutable_copies(self):
        first = snapshot()
        history = TargetHistory(first, 1010, 502)
        history.begin('held-transition', first)
        first['combinedSessionControlJournal'][0]['control'] = True
        later = snapshot(11)
        later['combinedSessionControlJournal'] = [first['combinedSessionControlJournal'][0], event(2, False, 11)]
        with self.assertRaisesRegex(Refusal, 'anchor evicted or changed'):
            history.check(later, 1011)

    def test_terminal_transition_is_fresh_once_and_immutable_after_exit(self):
        identity = (29, 502, 'owned-generation')
        value = dict(pid=29, uid=502, nonce='owned-generation', timestamp=1011 - 978307200,
                     state='secureInput', tapActive=False, heldOutputUsages=[])
        terminal = StoppedWorkerEvidence(identity, 1010)
        self.assertEqual(terminal.observe(value, 1012), value)
        # Independent process exit may be observed later. Historical state must
        # stay identical; this is not a current running-ledger proof.
        self.assertEqual(terminal.observe(value, 1020), value)
        with self.assertRaisesRegex(Refusal, 'evidence changed'):
            terminal.observe(dict(value, timestamp=value['timestamp'] + 1), 1020)
        for changed, now in ((value, 1015), (dict(value, timestamp=1009 - 978307200), 1010),
                             (dict(value, heldOutputUsages=[224]), 1012)):
            with self.assertRaises(Refusal):
                StoppedWorkerEvidence(identity, 1010).observe(changed, now)



class SharedIdentityBoundaryTests(unittest.TestCase):
    """Exercise the actual shared receipt reader at the D8 transport boundary."""
    @classmethod
    def setUpClass(cls):
        import importlib.machinery
        import pathlib
        cls.harness = importlib.machinery.SourceFileLoader(
            'held_secure_harness_test', str(pathlib.Path(__file__).with_name('held-secure-acceptance.py'))).load_module()
        cls.shared = cls.harness.load_module(cls.harness.IDENTITY_MODULE, 'held_identity_boundary_test')

    def receipt(self):
        return dict(version=1, lease='cbx_896c0d2d8565',
                    providerUUID='62017a62-8774-4bf6-8754-bbafe7c27c1f',
                    account='keypathqa_896c0d2d', uid=502,
                    home='/Users/keypathqa_896c0d2d', bootEpoch=1791077561)

    def load(self, path):
        import argparse
        return self.shared.from_arguments(argparse.Namespace(
            guest_account=None, guest_uid=None, guest_identity_receipt=str(path)))

    def pilot(self, provider=None, live_result='KEYPATH_GUEST_IDENTITY_VERIFIED'):
        fields = self.receipt()
        class Pilot:
            mutations = []
            observations = []
            def lab(self, lease, verb, *args):
                if verb == 'status':
                    return ('lease_id\t' + fields['lease'] + '\nowner\tkeypath-installer-lab-v1\n'
                            'status\tready\nprovider\tparallels\nprovider_resource\t'
                            + (provider or fields['providerUUID'])
                            + '\nexpires_epoch\t9999999999\nprovider_inventory_begin\n')
                self.mutations.append(args[-1])
                return ''
            def observe(self, lease, verb, *args):
                self.observations.append(args[-1])
                return live_result
        return Pilot()

    def test_foreign_lease_or_provider_cannot_reach_d8_mutation(self):
        import json
        import pathlib
        import tempfile
        import unittest.mock
        with tempfile.TemporaryDirectory() as folder, unittest.mock.patch.dict('os.environ', {}, clear=False):
            path = pathlib.Path(folder) / 'identity.json'
            path.write_text(json.dumps(self.receipt()))
            path.chmod(0o600)
            identity = self.load(path)
            for lease, provider in (('cbx_deadbeef1234', None),
                                    (identity.lease, 'e2017a62-8774-4bf6-8754-bbafe7c27c1f')):
                pilot = self.pilot(provider)
                guest = self.harness.Guest(lease, pilot, 'a' * 64, 'b' * 64, identity)
                with self.assertRaises(RuntimeError):
                    guest.run('printf unauthorized')
                self.assertEqual(pilot.mutations, [])
                self.assertEqual(pilot.observations, [])

    def test_live_console_or_boot_refusal_cannot_reach_d8_mutation(self):
        import json
        import pathlib
        import tempfile
        import unittest.mock
        with tempfile.TemporaryDirectory() as folder, unittest.mock.patch.dict('os.environ', {}, clear=False):
            path = pathlib.Path(folder) / 'identity.json'
            path.write_text(json.dumps(self.receipt()))
            path.chmod(0o600)
            identity = self.load(path)
            for failure in ('wrong console', 'changed boot'):
                pilot = self.pilot(live_result=failure)
                guest = self.harness.Guest(identity.lease, pilot, 'a' * 64, 'b' * 64, identity)
                with self.assertRaises(RuntimeError):
                    guest.run('printf unauthorized')
                self.assertEqual(pilot.mutations, [])
                guard = pilot.observations[-1]
                self.assertIn('/dev/console', guard)
                self.assertIn(str(identity.boot_epoch), guard)
                self.assertIn(str(identity.uid), guard)
                self.assertIn(identity.home, guard)

    def test_replaced_receipt_refuses_before_provider_or_guest_calls(self):
        import json
        import pathlib
        import tempfile
        import unittest.mock
        with tempfile.TemporaryDirectory() as folder, unittest.mock.patch.dict('os.environ', {}, clear=False):
            path = pathlib.Path(folder) / 'identity.json'
            path.write_text(json.dumps(self.receipt()))
            path.chmod(0o600)
            identity = self.load(path)
            replacement = pathlib.Path(folder) / 'replacement.json'
            changed = self.receipt()
            changed['bootEpoch'] += 1
            replacement.write_text(json.dumps(changed))
            replacement.chmod(0o600)
            replacement.replace(path)
            pilot = self.pilot()
            guest = self.harness.Guest(identity.lease, pilot, 'a' * 64, 'b' * 64, identity)
            with self.assertRaisesRegex(RuntimeError, 'receipt changed'):
                guest.run('printf unauthorized')
            self.assertEqual(pilot.mutations, [])
            self.assertEqual(pilot.observations, [])

    def test_noncanonical_account_cannot_be_freely_declared_without_receipt(self):
        import argparse
        with self.assertRaises(ValueError):
            self.shared.from_arguments(argparse.Namespace(guest_account='keypathqa_896c0d2d',
                                                          guest_uid=502, guest_identity_receipt=None))
        default = self.shared.from_arguments(argparse.Namespace(guest_account=None, guest_uid=None,
                                                               guest_identity_receipt=None))
        self.assertEqual((default.account, default.uid), ('keypathqa', 501))

    def test_transport_noop_does_not_mask_a_failed_guard_or_final_command(self):
        # Evaluate only a harmless synthetic shell expression locally, never a
        # guest/OS identity command. This checks grouped list/pipeline semantics.
        import subprocess
        class Identity:
            account, uid, home = 'keypathqa', 501, '/Users/keypathqa'
            app = home + '/Applications/KeyPath.app'
            def verify(self, *_):
                return {}
            def guard(self):
                return 'false'
        pilot = self.pilot()
        guest = self.harness.Guest('cbx_896c0d2d8565', pilot, 'a' * 64, 'b' * 64, Identity())
        guest.run('printf unauthorized; printf tail')
        expression = pilot.mutations[-1]
        self.assertTrue(expression.startswith('true; '))
        result = subprocess.run(['/bin/sh', '-c', expression], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        result = subprocess.run(['/bin/sh', '-c', 'true; true && { false; }'], capture_output=True)
        self.assertNotEqual(result.returncode, 0)


class BatchBoundaryTests(unittest.TestCase):
    setUpClass = SharedIdentityBoundaryTests.__dict__['setUpClass']
    receipt = SharedIdentityBoundaryTests.receipt
    pilot = SharedIdentityBoundaryTests.pilot
    def batch_guest(self, changes=None):
        import base64
        import json
        identity = self.shared.GuestIdentity('keypathqa_896c0d2d', 502, 'cbx_896c0d2d8565',
                   '62017a62-8774-4bf6-8754-bbafe7c27c1f', 1791077561)
        pilot = self.pilot()
        guest = self.harness.Guest(identity.lease, pilot, 'a' * 64, 'b' * 64, identity)
        guest.parent, guest.parent_args = 17, [guest.exe, '--headless']
        nonce = '6c83293b-38bc-4ea1-af44-86c1647d3d7a'
        path = '/var/folders/ab/owned/T/keypath-session-' + nonce + '/report.json'
        args = [guest.exe, '--session-runtime', '--session-owner', '17', '--session-report', path,
                '--session-nonce', nonce]
        process = '17 502 ' + guest.exe + ' ' + ' '.join(guest.parent_args) + '\n'
        process += '29 502 ' + guest.exe + ' ' + ' '.join(args)
        report = dict(pid=29, uid=502, nonce=nonce, timestamp=1010 - 978307200,
                      state='running', tapActive=True, heldOutputUsages=[])
        fields = dict(identity='\n'.join([identity.account, str(identity.uid), identity.home, identity.account,
                                         str(identity.uid), str(identity.boot_epoch)]) + '\n',
                      processes=process, pids='17\n29\n33', target=json.dumps(snapshot()),
                      binaryHash='a' * 64 + '  ' + guest.exe, complete='D8_COMPLETE',
                      **{'report-29': json.dumps(report)})
        if changes:
            changes(fields, guest)
        output = '\n'.join('D8\t' + key + '\t' + base64.b64encode(value.encode()).decode()
                             for key, value in fields.items())
        def observe(lease, verb, *args):
            pilot.observations.append(args[-1])
            return output
        pilot.observe = observe
        return guest, pilot

    def test_one_batch_uses_one_provider_and_one_guarded_guest_read(self):
        guest, pilot = self.batch_guest()
        status = []
        original = pilot.lab
        def lab(lease, verb, *args):
            status.append(verb)
            return original(lease, verb, *args)
        pilot.lab = lab
        batch = guest.snapshot()
        self.assertEqual(batch['worker'][0]['pid'], 29)
        self.assertEqual(status, ['status'])
        self.assertEqual(len(pilot.observations), 1)
        self.assertEqual(pilot.mutations, [])
        self.assertIn('/dev/console', pilot.observations[0])
        self.assertIn(str(guest.guest_identity.boot_epoch), pilot.observations[0])
        self.assertIn('test "$d8before" = "$d8after"', pilot.observations[0])
        self.assertNotIn('python', pilot.observations[0])

    def test_batch_shell_parses_and_a_failed_read_cannot_emit_completion(self):
        import subprocess
        guest, pilot = self.batch_guest()
        guest.snapshot()
        # Parse the complete guest expression without executing OS operations.
        parsed = subprocess.run(['/bin/zsh', '-n', '-c', pilot.observations[-1]], capture_output=True)
        self.assertEqual(parsed.returncode, 0, parsed.stderr.decode())
        # Execute only inert booleans to check the grouped guard/errexit contract.
        failed = subprocess.run(['/bin/zsh', '-c', 'true; true && { set -e; set -o pipefail; false; printf D8_COMPLETE; }'],
                                capture_output=True)
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(failed.stdout, b'')

    def test_missing_batch_completion_or_worker_report_cannot_pass(self):
        for field in ('complete', 'report-29', 'target', 'pids', 'identity'):
            guest, _ = self.batch_guest(lambda fields, _: fields.pop(field))
            with self.subTest(field=field), self.assertRaisesRegex(Refusal, 'incomplete'):
                guest.snapshot()

    def test_parent_arguments_worker_nonce_and_binary_changes_refuse(self):
        mutations = (
            lambda fields, _: fields.update(processes=fields['processes'].replace('--headless', '--different')),
            lambda fields, _: fields.update(binaryHash='c' * 64),
            lambda fields, _: fields.update(identity=fields['identity'].replace('1791077561', '1791077562')),
            lambda fields, _: fields.update(**{'report-29': fields['report-29'].replace('6c83293b', '7c83293b')}),
        )
        for mutation in mutations:
            guest, _ = self.batch_guest(mutation)
            with self.assertRaises(Refusal):
                guest.snapshot()

    def test_target_process_and_hash_are_required_in_the_same_batch(self):
        import json
        def target_fields(fields, guest):
            executable = guest.home + '/rig-target/capture-target'
            guest.target_identity = dict(pid=33, uid=502, nonce='target-nonce',
                                        executable=executable, arguments=[executable])
            target = json.loads(fields['target'])
            target['pid'] = 33
            fields.update(target=json.dumps(target), targetProcess='33 502 ' + executable + ' ' + executable,
                          targetHash='b' * 64)
        guest, _ = self.batch_guest(target_fields)
        self.assertEqual(guest.snapshot()['target']['pid'], 33)
        for field, value in (('targetHash', 'c' * 64), ('targetProcess', '33 501 /wrong /wrong')):
            def mutate(fields, guest):
                target_fields(fields, guest)
                fields[field] = value
            guest, _ = self.batch_guest(mutate)
            with self.assertRaisesRegex(Refusal, 'target process or hash'):
                guest.snapshot()

    def test_batch_target_focus_loss_is_fatal_without_retry(self):
        import json
        import pathlib
        import tempfile
        import unittest.mock
        def mutate(fields, _):
            target = snapshot()
            target['requestedResponderFocused'] = False
            fields['target'] = json.dumps(target)
        guest, pilot = self.batch_guest(mutate)
        with tempfile.TemporaryDirectory() as folder, unittest.mock.patch.object(self.harness.time, 'time', return_value=1010):
            campaign = self.harness.Campaign(guest, None, pathlib.Path(folder))
            with self.assertRaisesRegex(Refusal, 'focus'):
                campaign.target()
        self.assertEqual(len(pilot.observations), 1)

    def test_client_close_failure_still_restores_owner_and_fails_campaign(self):
        import pathlib
        import tempfile
        class Client:
            def status(self):
                return {'state': 'complete'}
            def close(self):
                raise RuntimeError('synthetic close failure')
        class Guest:
            restored = False
            def cleanup(self):
                self.restored = True
                return {'errors': [], 'profileBytewiseRestored': True}
        guest = Guest()
        with tempfile.TemporaryDirectory() as folder:
            campaign = self.harness.Campaign(guest, Client(), pathlib.Path(folder))
            campaign.record['passed'] = True
            campaign.cleanup()
        self.assertTrue(guest.restored)
        self.assertFalse(campaign.record['passed'])
        self.assertIn('fixture client close failed', campaign.record['cleanupErrors'][0])

    def test_acceptance_file_precedes_phase_retirement(self):
        import pathlib
        import tempfile
        guest, _ = self.batch_guest()
        with tempfile.TemporaryDirectory() as folder:
            campaign = self.harness.Campaign(guest, None, pathlib.Path(folder))
            campaign.history = TargetHistory(snapshot(), 1010, 502)
            campaign.history.begin('held-transition', snapshot())
            campaign.accept_phase('held-transition', {'physicalAllUpVerified': True})
            records = sorted(pathlib.Path(folder).glob('*.json'))
            self.assertEqual(len(records), 2)
            self.assertEqual(campaign.history.anchors, {})
            self.assertIn('accepted-held-transition', records[0].name)


if __name__ == '__main__':
    unittest.main()
