"""Pure acceptance predicates for D8; no transport, capture, secrets or input."""
import math


class Refusal(RuntimeError):
    pass


def require(condition, reason):
    if not condition:
        raise Refusal(reason)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def focus(receipt, mode):
    require(receipt.get('active') is True and receipt.get('windowKey') is True
            and receipt.get('focusLost') is False
            and receipt.get('requestedResponderFocused') is True
            and receipt.get('focusedMode') == mode, 'actual target focus lost or wrong responder')


JOURNALS = (('flagsChangedJournal', 'flagsChangedDropped'),
            ('combinedSessionControlJournal', 'combinedSessionControlDropped'),
            ('modeTransitions', 'modeTransitionsDropped'))


class TargetHistory:
    """Track one target and retained phase anchors, including ring drop accounting."""
    def __init__(self, first, now, uid):
        self.identity = tuple(first.get(k) for k in ('pid', 'uid', 'nonce', 'commandPath'))
        require(type(self.identity[0]) is int and self.identity[0] > 0
                and self.identity[1] == uid and isinstance(self.identity[2], str)
                and bool(self.identity[2]), 'invalid target identity')
        self.previous = None
        self.anchors = {}
        self.counts = {}
        self.check(first, now)
        self.anchor(first)

    def anchor(self, snapshot):
        for journal, _ in JOURNALS:
            rows = snapshot[journal]
            if rows:
                self.anchors.setdefault(journal, {})[rows[-1]['sequence']] = rows[-1]

    def check(self, value, now):
        require(tuple(value.get(k) for k in ('pid', 'uid', 'nonce', 'commandPath')) == self.identity,
                'target instance changed')
        require(number(value.get('observedAt')) and 0 <= now - value['observedAt'] < 3,
                'stale target receipt')
        require(number(value.get('monotonicAt')), 'missing target monotonic receipt')
        if self.previous:
            require(value['observedAt'] > self.previous['observedAt']
                    and value['monotonicAt'] > self.previous['monotonicAt'], 'target publication did not advance')
            for key in ('downs', 'ups', 'qDowns', 'aDowns', 'controlA', 'commandSequence'):
                require(type(value.get(key)) is int and value[key] >= self.previous[key],
                        'target cumulative counter regressed')
        require(value.get('commandConsumedSequence') == value.get('commandSequence')
                and type(value.get('commandSequence')) is int, 'ambiguous command sequence')
        mode = 'secure' if value.get('secureTest') is True else 'normal'
        focus(value, mode)
        for journal, dropped in JOURNALS:
            rows, drops = value.get(journal), value.get(dropped)
            require(isinstance(rows, list) and type(drops) is int and drops >= 0, 'missing journal accounting')
            seqs = [row.get('sequence') for row in rows]
            require(all(type(seq) is int and seq > 0 for seq in seqs)
                    and seqs == sorted(set(seqs)), 'unordered journal receipts')
            old = self.counts.get(journal)
            if old:
                require(drops >= old[0] and len(rows) + drops >= old[1], 'journal drop accounting regressed')
            for sequence, anchor in self.anchors.get(journal, {}).items():
                require(next((row for row in rows if row['sequence'] == sequence), None) == anchor,
                        'required phase journal anchor evicted or changed')
            for row in rows:
                require(number(row.get('observedAt')) and number(row.get('monotonicAt'))
                        and row['monotonicAt'] <= value['monotonicAt'], 'invalid journal timestamp')
            require(all(left['monotonicAt'] < right['monotonicAt']
                        and left['observedAt'] <= right['observedAt']
                        for left, right in zip(rows, rows[1:])), 'journal timestamps regressed')
            self.counts[journal] = (drops, len(rows) + drops)
        self.previous = value
        return value


def applied(value, mode, sequence):
    require(value.get('commandStatus') == 'applied'
            and value.get('commandSequence') == sequence
            and value.get('commandConsumedSequence') == sequence, 'mode command not applied exactly once')
    focus(value, mode)
    require(value.get('secureInputEnabled') is (mode == 'secure'), 'Carbon Secure Input state differs')
    transitions = [r for r in value['modeTransitions'] if r['sequence'] == sequence]
    require(len(transitions) == 1 and transitions[0].get('mode') == mode
            and transitions[0].get('responderAccepted') is True, 'mode transition receipt unavailable')
    focus(transitions[0], mode)


def physical_hold(status, run):
    require(status.get('runId') == run and status.get('state') == 'running'
            and status.get('reportsSubmitted') == 1, 'physical q hold not proven before key-up')


def worker(value, identity, now, state='running'):
    require(tuple(value.get(k) for k in ('pid', 'uid', 'nonce')) == identity, 'worker identity changed')
    require(number(value.get('timestamp')) and 0 <= now - (value['timestamp'] + 978307200) < 3,
            'stale worker receipt')
    require(value.get('state') == state and (state != 'running' or value.get('tapActive') is True),
            'unexpected worker state')


def control_down(target, ledger, after_sequence):
    receipts = [r for r in target['flagsChangedJournal'] if r['sequence'] > after_sequence
                and r.get('keyCode') == 59 and r.get('control') is True]
    require(bool(receipts) and ledger.get('heldOutputUsages') == [224],
            'delivered Control down and owned ledger 224 required')
    focus(receipts[-1], 'normal')
    require(receipts[-1].get('secureInputEnabled') is False, 'Control down occurred in Secure Input')
    return receipts[-1]


def control_released(target, stopped, down, command_anchor, old_exited):
    require(old_exited is True and stopped.get('state') == 'secureInput'
            and stopped.get('heldOutputUsages') == [] and stopped.get('tapActive') is False,
            'old worker did not stop and clear its ledger')
    ups = [r for r in target['flagsChangedJournal'] if r['sequence'] > down['sequence']
           and r['monotonicAt'] > command_anchor and r.get('keyCode') == 59
           and r.get('control') is False]
    require(bool(ups), 'no independent delivered Control up before physical release')
    focus(ups[-1], ups[-1]['mode'])
    combined = [r for r in target['combinedSessionControlJournal']
                if r['monotonicAt'] >= ups[-1]['monotonicAt'] and r.get('control') is False
                and r.get('secureInputEnabled') is True]
    require(bool(combined) and target.get('combinedSessionControl') is False,
            'combined-session Control clear did not corroborate delivery')
    return ups[-1]


def no_resurrection(target, ledger, release_sequence):
    require(ledger.get('heldOutputUsages') == [] and target.get('combinedSessionControl') is False,
            'Control resurrected while original q remained held')
    require(not any(r['sequence'] > release_sequence and r.get('control') is True
                    for r in target['flagsChangedJournal']), 'delivered Control resurrected')
    require(not any(r['sequence'] > release_sequence and r.get('control') is True
                    for r in target['combinedSessionControlJournal']), 'combined Control resurrected')
    # Native q key-down repeats are intentionally permitted; no down-count equality here.


def exact_trace(trace, rows, status, run):
    require(status.get('runId') == run and status.get('state') == 'complete'
            and status.get('reportsSubmitted') == len(rows), 'incomplete or foreign physical run')
    require([[r.get('modifiers'), *r.get('keys', [])] for r in trace] == rows,
            'physical trace differs from exact submitted reports')
    require(rows[-1] == [0] * 7, 'physical run lacks terminal all-up')
