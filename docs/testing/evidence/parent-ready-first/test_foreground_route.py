import shlex
import unittest
from unittest.mock import patch

import executor as E
import measurement as M


class ForegroundRouteTests(unittest.TestCase):
    def test_both_actual_parent_launch_paths_only_drop_background_flag(self):
        harness = E.dependencies()
        canonical, _ = E.classes(harness)
        diagnostic = M.diagnostic_guest(canonical, harness.Refusal, E.CONFIG)
        for guest_type in (canonical, diagnostic):
            with self.subTest(guest=guest_type.__name__):
                guest = guest_type.__new__(guest_type)
                guest.profile = '/owned/profile'
                guest.backup = '/owned/backup'
                guest.uid = 502
                guest.account = 'keypathqa_438d6abc'
                guest.app = '/Users/keypathqa_438d6abc/Applications/KeyPath.app'
                guest.check_account = lambda: None
                commands = []
                guest.run = commands.append
                guest.processes = lambda: [(42, 502, [guest.app, '--headless'])]
                guest.identity = lambda *args: dict(pid=42, uid=502)
                with patch.object(E.time, 'time', return_value=99), \
                     patch.object(E.time, 'monotonic', return_value=0):
                    self.assertEqual(guest.start()['pid'], 42)
                self.assertEqual(len(commands), 2)
                self.assertIn(' open -n ' + shlex.quote(guest.app) + ' --args --headless', commands[1])
                self.assertNotIn(' open -g ', commands[1])
                self.assertIn('printf %s ' + shlex.quote(E.CONFIG), commands[1])
                self.assertTrue(guest.backed_up)


if __name__ == '__main__':
    unittest.main()
