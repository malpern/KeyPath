"""Synthetic D8 acceptance evidence: negative receipts must never become passes."""
import copy
import unittest

from held_secure_predicates import (Refusal, TargetHistory, applied, control_down,
                                   control_released, exact_trace, no_resurrection,
                                   physical_hold, worker)


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


if __name__ == '__main__':
    unittest.main()
