import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomUUID, randomBytes } from 'node:crypto';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const image = process.argv[2] || 'open-freemode:legacy-development';
const prefix = 'ofm-legacy-' + randomUUID();
const directory = mkdtempSync(join(tmpdir(), 'ofm-legacy-'));
const containers = [];
const docker = (...args) => execFileSync('docker', args, {encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], timeout: 180000, maxBuffer: 16 * 1024 * 1024}).trim();
const privateKey = process.env.OFM_TEST_KEY_FILE;
const key = privateKey ? readFileSync(privateKey, 'utf8').match(/^FIVEM_LICENSE_KEY=([A-Za-z0-9_-]+)\s*$/m)?.[1] : 'synthetic-test-key';
assert.ok(key);
const password = randomBytes(24).toString('hex') + ';=:@/ test';
writeFileSync(join(directory, 'db.env'), `MARIADB_ROOT_PASSWORD=${password}\nMARIADB_DATABASE=ofm_test\nMARIADB_USER=ofm_test\nMARIADB_PASSWORD=${password}\n`);
writeFileSync(join(directory, 'game.env'), `FIVEM_LICENSE_KEY=${key}\nDB_HOST=${prefix}-db\nDB_NAME=ofm_test\nDB_USER=ofm_test\nDB_PASSWORD=${password}\n`);
let network, volume;
try {
  network = docker('network', 'create', prefix);
  volume = docker('volume', 'create', prefix);
  const db = docker('run', '-d', '--name', prefix + '-db', '--network', prefix, '--env-file', join(directory, 'db.env'),
    'mariadb:11.4@sha256:611a2fcc5fa7c6ceb8644c6f74b25ede004ff6c3a6b38c8f8c23d3bbf6c26430');
  containers.push(db);
  for (let attempt = 0; ; attempt++) {
    try { docker('exec', db, 'healthcheck.sh', '--connect', '--innodb_initialized'); break; }
    catch { assert.ok(attempt < 60, 'Database readiness timed out'); await delay(1000); }
  }
  const args = ['--network', prefix, '--mount', `type=volume,src=${volume},dst=/home/container`, '--env-file', join(directory, 'game.env')];
  for (let pass = 0; pass < 2; pass++) {
    docker('run', '--rm', ...args, image, 'python3', '/opt/open-freemode/scripts/launcher.py', 'migrate');
  }
  const sql = query => docker('exec', db, 'sh', '-c', 'exec mariadb -N -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "$1"', 'query', query);
  assert.equal(sql("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='ofm_test' AND table_name IN ('players','playerskins','player_outfits','bans','player_groups')"), '5');
  sql("INSERT INTO playerskins (citizenid,model,skin) VALUES ('fixture','mp_m_freemode_01','{}')");
  const game = docker('run', '-dit', ...args, '--publish', '127.0.0.1::30120/tcp', image);
  containers.push(game);
  let logs = '';
  const deadline = Date.now() + 180000;
  while (Date.now() < deadline) {
    logs = docker('logs', game);
    if (privateKey && process.env.OFM_TEST_LOG_FILE) writeFileSync(process.env.OFM_TEST_LOG_FILE, logs);
    if (privateKey && docker('inspect', '-f', '{{.State.Running}}', game) === 'false') break;
    if (privateKey ? logs.includes('[ofm_session] Legacy foundation started.') : docker('inspect', '-f', '{{.State.Running}}', game) === 'false') break;
    await delay(500);
  }
  if (privateKey) {
    await delay(5000);
    logs = docker('logs', game);
    // Explicit opt-in private log path; never print native log contents automatically.
    if (process.env.OFM_TEST_LOG_FILE) writeFileSync(process.env.OFM_TEST_LOG_FILE, logs);
    assert.ok(logs.includes('[ofm_session] Legacy foundation started.'), 'Legacy resource readiness missing');
    assert.ok(!/SCRIPT ERROR|Error loading script|Failed to load script|Error parsing script/.test(logs), 'Resource error; inspect private test log');
    const endpoint = docker('port', game, '30120/tcp');
    const response = await (await fetch(`http://${endpoint}/info.json`)).text();
    const info = JSON.parse(response);
    for (const resource of ['chat','spawnmanager','sessionmanager','hardcap','baseevents','qbx_core','qbx_vehicles','ox_lib','ox_inventory','oxmysql','illenium-appearance','pma-voice','vMenu','ofm_session']) {
      assert.ok(info.resources.includes(resource), 'Missing resource: ' + resource);
    }
    assert.ok(!response.includes(password) && !response.includes(key), 'Info endpoint exposed a credential');
    docker('stop', '--time', '10', game);
    assert.equal(docker('inspect', '-f', '{{.State.ExitCode}}', game), '0');
    docker('start', game);
    await delay(12000);
    logs = docker('logs', game);
    if (process.env.OFM_TEST_LOG_FILE) writeFileSync(process.env.OFM_TEST_LOG_FILE, logs);
    assert.equal(docker('inspect', '-f', '{{.State.Running}}', game), 'true', 'Restart failed');
    docker('stop', '--time', '10', game);
  } else {
    assert.ok(/Invalid key|license key.*invalid|could not be authenticated/i.test(logs), 'Expected license rejection missing');
    assert.notEqual(docker('inspect', '-f', '{{.State.ExitCode}}', game), '0');
  }
  assert.equal(sql("SELECT COUNT(*) FROM playerskins WHERE citizenid='fixture'"), '1', 'Startup altered saved data');
  console.log(privateKey ? 'Legacy authenticated startup, resources, restart, SQL preservation and info privacy passed. Real-client walkthrough still required.' : 'Legacy fresh database, repeatable migrations, SQL preservation and native license rejection passed.');
} catch (error) {
  console.error(error instanceof assert.AssertionError ? error.message : 'Legacy fixture failed; private database and runtime output withheld.');
  process.exitCode = 1;
} finally {
  for (const container of containers.reverse()) docker('rm', '-fv', container);
  if (volume) docker('volume', 'rm', volume);
  if (network) docker('network', 'rm', network);
  rmSync(directory, {recursive: true, force: true});
}
