import { execFileSync, spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { mkdtempSync, writeFileSync, rmSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, basename } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const directory = mkdtempSync(join(tmpdir(), 'open-freemode-test-'));
const password = randomBytes(16).toString('hex') + ';=:@/ "\\$() test';
const envFile = join(directory, 'database.env');
const configFile = join(directory, 'database.json');
writeFileSync(envFile, `MARIADB_ROOT_PASSWORD=${randomBytes(24).toString('hex')}\nMARIADB_DATABASE=ofm_test\nMARIADB_USER=ofm_test\nMARIADB_PASSWORD=${password}\n`, { mode: 0o600 });
const image = 'mariadb:11.4@sha256:611a2fcc5fa7c6ceb8644c6f74b25ede004ff6c3a6b38c8f8c23d3bbf6c26430';
let container;
function docker(...args) { return execFileSync('docker', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim(); }
try {
  container = docker('run', '--detach', '--label', 'org.open-freemode.test=database',
    '--env-file', envFile, '--publish', '127.0.0.1::3306',
    '--health-cmd', 'healthcheck.sh --connect --innodb_initialized', '--health-interval', '1s',
    '--health-timeout', '3s', '--health-retries', '60', image);
  const deadline = Date.now() + 90000;
  while (docker('inspect', '--format', '{{.State.Health.Status}}', container) !== 'healthy') {
    if (Date.now() > deadline || docker('inspect', '--format', '{{.State.Running}}', container) !== 'true') {
      throw new Error('Disposable database did not become healthy');
    }
    await delay(1000);
  }
  const endpoint = docker('port', container, '3306/tcp');
  assertLoopback(endpoint);
  writeFileSync(configFile, JSON.stringify({ host: '127.0.0.1', port: Number(endpoint.split(':').at(-1)),
    user: 'ofm_test', password, database: 'ofm_test' }), { mode: 0o600 });
  const result = spawnSync(process.execPath, ['--test', 'tests/database.test.mjs'], {
    env: { ...process.env, OFM_TEST_DB_CONFIG: configFile }, stdio: 'inherit',
  });
  process.exitCode = result.status ?? 1;
} catch {
  console.error('Database integration runner failed. Check Docker availability; private connection details are not printed.');
  process.exitCode = 1;
} finally {
  if (container) docker('rm', '--force', '--volumes', container);
  const resolved = realpathSync(directory);
  if (dirname(resolved) !== realpathSync(tmpdir()) || !basename(resolved).startsWith('open-freemode-test-')) {
    throw new Error('Refusing cleanup outside the test temporary directory');
  }
  rmSync(resolved, { recursive: true, force: true });
}
function assertLoopback(endpoint) {
  if (!/^127\.0\.0\.1:\d+$/.test(endpoint)) throw new Error('Test database must bind only to loopback');
}
