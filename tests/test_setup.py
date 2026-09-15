import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.plugin = self.root / 'plugin with spaces'
        (self.plugin / 'bin').mkdir(parents=True)
        (self.plugin / 'contrib').mkdir()
        for name in ('floating-mode-setup', 'floating-mode-state', 'floating-mode-run'):
            shutil.copy2(REPO / 'bin' / name, self.plugin / 'bin' / name)
        self.write(self.plugin / 'bin/floating-mode', '#!/bin/bash\nexit ${FAIL_LUA:-0}\n')
        self.write(self.plugin / 'contrib/install-hyprbars', '''#!/bin/bash
echo install >> "$TEST_ROOT/installs"
[[ "${FAIL_INSTALL:-0}" == 0 ]] || exit 1
mkdir -p "$XDG_CONFIG_HOME/hypr"
touch "$XDG_CONFIG_HOME/hypr/floating-mode.lua"
echo abi1 > "$XDG_STATE_HOME/omarchy-floating-mode/native-abi"
''')
        mocks = self.root / 'mocks'
        mocks.mkdir()
        self.write(mocks / 'Hyprland', '#!/bin/bash\necho \'{"abiHash":"abi1"}\'\n')
        self.write(mocks / 'hyprctl', '''#!/bin/bash
[[ "${UNAVAILABLE:-0}" == 0 ]] || exit 1
case "$1" in
version) printf '{"abiHash":"%s"}\\n' "${RUNNING_ABI:-abi1}";;
plugins) echo "${LOADED_PLUGINS-hyprbars omarchy-windows-snap}";;
esac
''')
        self.write(mocks / 'omarchy', '''#!/bin/bash
echo launch >> "$TEST_ROOT/launches"
[[ "${FAIL_LAUNCH:-0}" == 0 ]] || exit 1
if [[ "${EXECUTE_SETUP:-0}" == 1 ]]; then "$3" "$4"; fi
''')
        self.env = dict(os.environ, TEST_ROOT=str(self.root),
                        XDG_CONFIG_HOME=str(self.root / 'config'),
                        XDG_STATE_HOME=str(self.root / 'state'),
                        PATH=str(mocks) + ':' + os.environ['PATH'])
        for key in ('FLOATING_SETUP_LAUNCH_LOCK', 'FLOATING_SETUP_RUN_LOCK', 'FLOATING_MODE_LOCK_HELD'):
            self.env.pop(key, None)
        self.setup_dir = self.root / 'state/omarchy-floating-mode/setup'

    def write(self, path, text):
        path.write_text(text)
        path.chmod(0o755)

    def run_setup(self, action, **env):
        return subprocess.run([str(self.plugin / 'bin/floating-mode-setup'), action],
                              env=dict(self.env, **env), capture_output=True, text=True, timeout=15)

    def count(self, name):
        p = self.root / name
        return len(p.read_text().splitlines()) if p.exists() else 0

    def test_fresh_install_opens_once_and_rechecks_success(self):
        result = self.run_setup('auto', EXECUTE_SETUP='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.run_setup('status').stdout.strip(), 'ready')
        self.run_setup('auto')
        self.assertEqual(self.count('launches'), 1)
        self.assertEqual(self.count('installs'), 1)

    def test_loaded_modules_and_lua_are_required_even_with_matching_abi(self):
        self.run_setup('auto', EXECUTE_SETUP='1')
        self.assertEqual(self.run_setup('status', LOADED_PLUGINS='hyprbars').stdout.strip(), 'failed')
        self.assertEqual(self.run_setup('status', FAIL_LUA='1').stdout.strip(), 'failed')

    def test_queued_launch_is_not_repeated_and_can_be_retried(self):
        self.run_setup('auto')
        self.run_setup('auto')
        self.assertEqual(self.run_setup('status').stdout.strip(), 'running')
        self.assertEqual(self.count('launches'), 1)
        os.utime(self.setup_dir / 'queued', (1, 1))
        self.assertEqual(self.run_setup('status').stdout.strip(), 'failed')
        self.run_setup('auto')
        self.assertEqual(self.count('launches'), 1)
        self.run_setup('retry', EXECUTE_SETUP='1')
        self.assertEqual(self.count('launches'), 2)
        self.assertEqual(self.run_setup('status').stdout.strip(), 'ready')

    def test_failed_installer_does_not_loop(self):
        self.run_setup('auto', EXECUTE_SETUP='1', FAIL_INSTALL='1')
        self.assertEqual(self.run_setup('status').stdout.strip(), 'failed')
        self.run_setup('auto')
        self.assertEqual(self.count('installs'), 1)
        self.run_setup('retry', EXECUTE_SETUP='1')
        self.assertEqual(self.count('installs'), 2)
        self.assertEqual(self.run_setup('status').stdout.strip(), 'ready')

    def test_unavailable_compositor_does_not_launch_or_mark_attempt(self):
        self.run_setup('auto', UNAVAILABLE='1')
        self.assertEqual(self.count('launches'), 0)
        self.assertFalse((self.setup_dir / 'attempted').exists())

    def test_abi_mismatch_requires_login_instead_of_build(self):
        self.assertEqual(self.run_setup('status', RUNNING_ABI='old').stdout.strip(), 'restart-required')
        self.run_setup('auto', RUNNING_ABI='old')
        self.assertEqual(self.count('launches'), 0)

    def test_terminal_launch_failure_allows_manual_retry(self):
        result = self.run_setup('auto', FAIL_LAUNCH='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.run_setup('status').stdout.strip(), 'failed')
        self.run_setup('retry', EXECUTE_SETUP='1')
        self.assertEqual(self.run_setup('status').stdout.strip(), 'ready')

    def test_running_installer_prevents_another_launch(self):
        self.run_setup('status')
        import fcntl
        with (self.setup_dir / 'run.lock').open('r+') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            self.assertEqual(self.run_setup('status').stdout.strip(), 'running')
            self.run_setup('retry')
            self.assertEqual(self.count('launches'), 0)


if __name__ == '__main__':
    unittest.main()
