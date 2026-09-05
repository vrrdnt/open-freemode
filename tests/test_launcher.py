import importlib.util
import base64
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import hashlib
import io
import shutil
import tarfile

SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'
spec = importlib.util.spec_from_file_location('launcher', SCRIPTS / 'launcher.py')
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / 'app'
        (self.app / 'resources').mkdir(parents=True)
        self.data = self.root / 'state'
        launcher.seed(self.data, self.app)
        self.env = dict(os.environ, FIVEM_LICENSE_KEY='synthetic-test-key', DB_HOST='database.example.invalid',
                        DB_USER='test-user', DB_NAME='ofm_test', DB_PASSWORD='test;=:@/ "\\$() value')

    def test_runtime_download_is_verified_atomic_and_cached(self):
        archive = self.root / 'fixture.tar.xz'
        with tarfile.open(archive, 'w:xz') as bundle:
            for name in ['alpine/lib/ld-musl-x86_64.so.1', 'alpine/opt/cfx-server/cfx-server']:
                member = tarfile.TarInfo(name)
                member.size = 7
                bundle.addfile(member, io.BytesIO(b'fixture'))
        (self.app / 'scripts').mkdir()
        shutil.copyfile(SCRIPTS / 'fetch-runtime.py', self.app / 'scripts/fetch-runtime.py')
        lock = {'build': 'fixture', 'url': archive.as_uri(), 'sha256': '0' * 64}
        lockfile = self.app / 'runtime.lock.json'
        lockfile.write_text(json.dumps(lock))
        with self.assertRaisesRegex(ValueError, 'download failed'):
            launcher.runtime_root(self.data, self.app, os.environ)
        self.assertEqual(list((self.data / 'runtime').iterdir()), [])
        lock['sha256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
        lockfile.write_text(json.dumps(lock))
        target = launcher.runtime_root(self.data, self.app, os.environ)
        archive.unlink()
        self.assertEqual(launcher.runtime_root(self.data, self.app, os.environ), target)
        self.assertTrue(Path(launcher.command(target)[0]).is_file())

    def test_reinstall_preserves_operator_files(self):
        operator = self.data / 'config/operator.cfg'
        operator.write_text('# private customization\n')
        (self.data / 'keep.txt').write_text('preserve')
        launcher.seed(self.data, self.app)
        self.assertEqual(operator.read_text(), '# private customization\n')
        self.assertEqual((self.data / 'keep.txt').read_text(), 'preserve')

    def test_structured_credentials_and_allocation_precedence(self):
        self.env.update(SERVER_PORT='31120', GAME_PORT='32120', TXHOST_API_TOKEN='must-not-inherit')
        environment = launcher.configure(self.data, self.env)
        config = json.loads((self.data / 'config/database.json').read_text())
        self.assertEqual(config['password'], self.env['DB_PASSWORD'])
        self.assertIn('0.0.0.0:31120', (self.data / 'server-data/server.cfg').read_text())
        self.assertNotIn('DB_PASSWORD', environment)
        self.assertNotIn('TXHOST_API_TOKEN', environment)
        self.assertNotIn(self.env['DB_PASSWORD'], (self.data / 'server-data/server.cfg').read_text())
        encoded = next(line.split(' ', 2)[2] for line in (self.data / 'server-data/server.cfg').read_text().splitlines()
                       if line.startswith('set ofm_db_options '))
        self.assertEqual(json.loads(base64.b64decode(encoded)), config)
        if os.name == 'posix':
            self.assertEqual((self.data / 'config/database.json').stat().st_mode & 0o777, 0o600)

    def test_invalid_input_does_not_replace_valid_configuration(self):
        launcher.configure(self.data, self.env)
        original = (self.data / 'server-data/server.cfg').read_bytes()
        for field, value in [('SERVER_NAME', 'name\nensure injected'), ('DB_PORT', 'secret-invalid-port'),
                             ('GAME_PORT', '1'), ('FIVEM_LICENSE_KEY', 'secret;command')]:
            with self.subTest(field=field):
                with self.assertRaises(ValueError) as error:
                    launcher.configure(self.data, dict(self.env, **{field: value}))
                self.assertNotIn(value, str(error.exception))
                self.assertEqual((self.data / 'server-data/server.cfg').read_bytes(), original)

    def test_managed_path_conflict_is_preserved(self):
        target = self.data / 'server-data/resources'
        (target / 'operator.lua').write_text('preserve')
        with self.assertRaises(ValueError):
            launcher.seed(self.data, self.app)
        self.assertEqual((target / 'operator.lua').read_text(), 'preserve')

    def test_private_config_symlink_is_rejected(self):
        other = self.root / 'other'
        other.write_text('preserve')
        (self.data / 'config/database.json').symlink_to(other)
        with self.assertRaises(ValueError):
            launcher.configure(self.data, self.env)
        self.assertEqual(other.read_text(), 'preserve')

    @unittest.skipUnless(os.name == 'posix', 'POSIX process groups are required')
    def test_child_exit_status_is_preserved(self):
        self.assertEqual(launcher.supervise([sys.executable, '-c', 'raise SystemExit(7)'], os.environ, self.root), 7)
        self.assertEqual(launcher.supervise([sys.executable, '-c', 'raise SystemExit(0)'], os.environ, self.root), 1)

    @unittest.skipUnless(os.name == 'posix', 'POSIX process groups are required')
    def test_monitor_exit_cannot_leave_a_blocked_child_running(self):
        pid_file = self.root / 'blocked.pid'
        child = (f'import os,signal,time; from pathlib import Path; '
                 f'signal.signal(signal.SIGTERM,signal.SIG_IGN); '
                 f'Path({str(pid_file)!r}).write_text(str(os.getpid())); time.sleep(120)')
        parent = (f'import subprocess,sys,time; subprocess.Popen([sys.executable,"-c",{child!r}]); time.sleep(120)')
        runner = (f'import sys,os; sys.path.insert(0,{str(SCRIPTS)!r}); import launcher; '
                  f'sys.exit(launcher.supervise([sys.executable,"-c",{parent!r}],os.environ,{str(self.root)!r},0.2))')
        process = subprocess.Popen([sys.executable, '-c', runner])
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        deadline = time.monotonic() + 10
        while not pid_file.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertTrue(pid_file.exists(), 'The fixture child must actually stay blocked')
        pid = int(pid_file.read_text())
        process.send_signal(signal.SIGTERM)
        self.assertEqual(process.wait(timeout=5), 0)
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            status = Path(f'/proc/{pid}/stat')
            if not status.exists() or status.read_text().split()[2] == 'Z':
                break
            time.sleep(0.05)
        else:
            self.fail('Blocked child survived supervisor shutdown')


if __name__ == '__main__':
    unittest.main()
