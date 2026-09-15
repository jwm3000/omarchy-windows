"""Exercise real helpers against isolated state and a simulated compositor."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class ActivationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name in ('runtime', 'config', 'bin'):
            (self.root / name).mkdir(mode=0o700)
        self.state = self.root / 'runtime/omarchy-floating-mode'
        mock = self.root / 'bin/hyprctl'
        mock.write_text('''#!/bin/bash
case "$1" in
activeworkspace) echo '{"id":1}';;
eval)
  if [[ "$2" == *assert* && "$MOCK_FAILURE" == missing ]]; then
    echo 'Lua integration missing'; exit 1
  fi
  if [[ "$2" == 'omarchy_floating_mode_opaque_rule:set_enabled(false)' ]]; then
    if [[ "$MOCK_FAILURE" == late ]]; then echo 'Lua runtime failure'; exit 1; fi
    if [[ "$MOCK_FAILURE" == timeout ]]; then sleep 20; fi
  fi
  echo ok;;
getoption) echo '{"gradient":"ff333333"}';;
plugins) echo '';;
--batch) echo ok;;
*) echo '[]';;
esac
''')
        mock.chmod(0o755)
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(self.root / 'runtime'),
                        XDG_CONFIG_HOME=str(self.root / 'config'),
                        PATH=str(mock.parent) + ':' + os.environ['PATH'])
        for key in ('FLOATING_MODE_LOCK_HELD', 'FLOATING_MODE_TARGET_WORKSPACE'):
            self.env.pop(key, None)

    def run_action(self, failure='', timeout='10'):
        return subprocess.run([str(REPO / 'bin/floating-mode-run'), timeout,
                               '1048576', '65536', '--',
                               str(REPO / 'bin/floating-mode'), 'on'],
                              env=dict(self.env, MOCK_FAILURE=failure),
                              capture_output=True, text=True, timeout=15)

    def test_missing_integration_is_actionable_and_does_not_enable(self):
        result = self.run_action('missing')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Lua integration missing', result.stderr)
        self.assertIn('contrib/install-hyprbars', result.stderr)
        self.assertFalse((self.state / 'enabled').exists())

    def test_late_failure_resets_status_and_preserves_ledger(self):
        result = self.run_action('late')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Lua runtime failure', result.stderr)
        self.assertIn('status was reset', result.stderr)
        self.assertFalse((self.state / 'enabled').exists())
        self.assertTrue((self.state / 'managed').exists())

    def test_other_workspace_remains_enabled(self):
        self.state.mkdir(mode=0o700)
        for name in ('enabled', 'managed', 'workspace.2'):
            (self.state / name).touch(mode=0o600)
        settings = self.root / 'config/omarchy-floating-mode'
        settings.mkdir(mode=0o700)
        (settings / 'current-workspace-only').touch(mode=0o600)
        result = self.run_action('late')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.state / 'enabled').exists())
        self.assertTrue((self.state / 'workspace.2').exists())
        self.assertFalse((self.state / 'workspace.1').exists())

    def test_success_keeps_enabled_status(self):
        result = self.run_action()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.state / 'enabled').exists())

    def test_timeout_resets_new_status(self):
        result = self.run_action('timeout', '1')
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertFalse((self.state / 'enabled').exists())


if __name__ == '__main__':
    unittest.main()
