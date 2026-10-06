"""Host-safe tests for the marker observer's bounded replacement-parent predicate."""
from pathlib import Path
import unittest


def require(value, reason):
    if not value:
        raise ValueError(reason)


SOURCE = Path(__file__).with_name('marker_observe.py')
NAMESPACE = {'require': require}
exec(compile(SOURCE.read_text(), str(SOURCE), 'exec'), NAMESPACE)
admit = NAMESPACE['admit_replacement_parent']
MAIN = '/Users/keypathqa/Applications/KeyPath.app/Contents/MacOS/KeyPath'
OWNER = dict(uid=502, parentPID=100, workerPID=101, nonce='nonce',
             generation='generation', bootSessionUUID='boot')
PARENT = dict(pid=200, uid=502, executable=MAIN, arguments=[MAIN])


class ReplacementParentAdmissionTests(unittest.TestCase):
    def runtime(self, parent=PARENT, workers=None, target=None):
        return dict(parents=[] if parent is None else [parent],
                    workers=[] if workers is None else workers, target=target)

    def test_exact_bound_normal_parent_admitted_after_old_pids_are_gone(self):
        self.assertEqual(admit(OWNER, self.runtime(), {200, 300}, 200, MAIN), PARENT)

    def test_replacement_pid_must_be_distinct_and_old_owner_pids_absent_globally(self):
        for pid, live in ((100, {200}), (101, {200}), (200, {100}), (200, {101})):
            with self.subTest(pid=pid, live=live), self.assertRaises(ValueError):
                admit(OWNER, self.runtime(), live, pid, MAIN)

    def test_only_one_exact_same_main_uid502_ordinary_parent_is_admitted(self):
        bad_parents = (
            None,
            dict(PARENT, uid=501),
            dict(PARENT, executable='/tmp/KeyPath'),
            dict(PARENT, arguments=[MAIN, '--session-runtime']),
            dict(PARENT, pid=201),
        )
        for parent in bad_parents:
            with self.subTest(parent=parent), self.assertRaises(ValueError):
                admit(OWNER, self.runtime(parent), {200}, 200, MAIN)
        with self.assertRaises(ValueError):
            admit(OWNER, dict(parents=[PARENT, PARENT], workers=[], target=None), {200}, 200, MAIN)

    def test_any_worker_or_target_blocks_admission(self):
        with self.assertRaises(ValueError):
            admit(OWNER, self.runtime(workers=[dict(pid=201)]), {200}, 200, MAIN)
        with self.assertRaises(ValueError):
            admit(OWNER, self.runtime(target=dict(pid=202)), {200}, 200, MAIN)

    def test_replacement_pid_requires_strict_positive_integer(self):
        for pid in (True, 0, -1, 2**31, '200'):
            with self.subTest(pid=pid), self.assertRaises(ValueError):
                admit(OWNER, self.runtime(), {200}, pid, MAIN)


if __name__ == '__main__':
    unittest.main()
