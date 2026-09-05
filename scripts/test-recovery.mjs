import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { request } from 'node:http';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { mkdtempSync, writeFileSync, readFileSync, realpathSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { Database } from '../lib/database.mjs';

// Exercise real SQL/file backup and restore with separate databases and volumes.
// No persistent game runs here: authenticated client recovery is a separate gate.
const image = process.argv[2] || 'open-freemode:development';
const keyFile = process.env.OFM_TEST_KEY_FILE;
const serverKey = keyFile ? readFileSync(keyFile, 'utf8').replace(/^\uFEFF/, '').match(/^FIVEM_LICENSE_KEY=([A-Za-z0-9_-]{8,128})\s*$/m)?.[1] : undefined;
if (keyFile && !serverKey) throw new Error('Private key file is missing a valid FIVEM_LICENSE_KEY entry');
const databaseImage = 'mariadb:11.4@sha256:611a2fcc5fa7c6ceb8644c6f74b25ede004ff6c3a6b38c8f8c23d3bbf6c26430';
const directory = mkdtempSync(join(tmpdir(), 'open-freemode-recovery-'));
const networkName = 'ofm-recovery-' + randomUUID();
const containers = [], volumes = [], pools = [];
let network;
let attachment;
const run = (args, options = {}) => execFileSync('docker', args, {
  stdio: ['pipe', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024, timeout: 120000, ...options,
});
const docker = (...args) => run(args).toString('utf8').trim();
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

// Docker CLI rejects piped stdin for TTY containers. Use the same Engine attach
// stream directly, without changing the game container's terminal or security.
async function attachConsole(container) {
  const host = process.env.DOCKER_HOST || docker('context', 'inspect', '--format', '{{.Endpoints.docker.Host}}');
  assert.match(host, /^(unix|npipe):\/\//, 'Native console fixture requires a local Docker socket');
  return new Promise((resolve, reject) => {
    const req = request({ socketPath: host.replace(/^(unix|npipe):\/\//, ''), method: 'POST',
      path: `/containers/${container}/attach?stream=1&stdin=1&stdout=1&stderr=1`,
      headers: { Connection: 'Upgrade', Upgrade: 'tcp' }, timeout: 5000 });
    req.on('upgrade', (_response, socket) => { socket.setTimeout(0); socket.resume(); resolve(socket); });
    req.on('response', response => { response.resume(); reject(new Error('Docker did not upgrade console stream')); });
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('Docker console attachment timed out')));
    req.end();
  });
}

async function deployment(label) {
  const name = `${networkName}-${label}`;
  const password = randomBytes(24).toString('hex') + ';=:@/ "\\$() test';
  const dbName = `ofm_${label}`;
  const dbEnv = join(directory, `${label}-db.env`);
  writeFileSync(dbEnv, `MARIADB_ROOT_PASSWORD=${randomBytes(24).toString('hex')}\nMARIADB_DATABASE=${dbName}\nMARIADB_USER=${dbName}\nMARIADB_PASSWORD=${password}\n`, { mode: 0o600 });
  const container = docker('run', '--detach', '--name', name, '--network', networkName,
    '--env-file', dbEnv, '--publish', '127.0.0.1::3306',
    '--health-cmd', 'healthcheck.sh --connect --innodb_initialized', '--health-interval', '1s',
    '--health-timeout', '3s', '--health-retries', '60', databaseImage);
  containers.push(container);
  const deadline = Date.now() + 90000;
  while (docker('inspect', '--format', '{{.State.Health.Status}}', container) !== 'healthy') {
    assert.ok(Date.now() < deadline, 'Disposable database startup timed out');
    assert.equal(docker('inspect', '--format', '{{.State.Running}}', container), 'true');
    await delay(500);
  }
  const endpoint = docker('port', container, '3306/tcp');
  assert.match(endpoint, /^127\.0\.0\.1:\d+$/);
  const database = new Database({ host: '127.0.0.1', port: Number(endpoint.split(':').at(-1)),
    user: dbName, database: dbName, password });
  pools.push(database);
  const volume = docker('volume', 'create', '--label', 'org.open-freemode.test=recovery', name);
  volumes.push(volume);
  const gameEnv = join(directory, `${label}-game.env`);
  writeFileSync(gameEnv, `FIVEM_LICENSE_KEY=${label === 'restore' && serverKey ? serverKey : 'synthetic-test-key'}\nDB_HOST=${name}\nDB_PORT=3306\nDB_NAME=${dbName}\nDB_USER=${dbName}\nDB_PASSWORD=${password}\n`, { mode: 0o600 });
  const gameArgs = ['run', '--rm', '--network', networkName, '--mount', `type=volume,src=${volume},dst=/home/container`,
    '--env-file', gameEnv, image];
  return { container, database, volume, gameArgs, dbName, password, name };
}

const rows = async database => (await database.pool.query(
  'SELECT CAST(id AS CHAR) AS id, HEX(identifier) AS identity_hex, first_seen, last_seen FROM ofm_accounts ORDER BY id'))[0];
try {
  network = docker('network', 'create', '--label', 'org.open-freemode.test=recovery', networkName);
  const source = await deployment('source');
  const target = await deployment('restore');
  docker(...source.gameArgs, 'python3', '/opt/open-freemode/scripts/launcher.py', 'migrate');
  const identity = 'license:' + 'a'.repeat(40);
  const account = await source.database.openAccount(identity);
  const characters = await source.database.createCharacter(account.id, 1, {
    version: 1, sex: 1, father: 2, mother: 23, resemblance: 4, skinMix: 6,
    hair: 3, hairColor: 4, hairHighlight: 5, eyes: 6, features: Array(20).fill(2),
  });
  await source.database.openAccount('license:' + 'b'.repeat(40));
  docker(...source.gameArgs, 'python3', '-c',
    "from pathlib import Path; Path('/home/container/config/operator.cfg').write_text('# recovery fixture operator settings\\n')");
  const snapshot = await rows(source.database);

  // There are no game processes or concurrent writers during this matched backup.
  // Fixed shell programs quote container environment values; only synthetic secrets are used.
  const sql = run(['exec', source.container, 'sh', '-c',
    'exec mariadb-dump --single-transaction --skip-lock-tables --skip-add-locks --hex-blob --no-tablespaces --skip-comments -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"']);
  const files = run(['run', '--rm', '--mount', `type=volume,src=${source.volume},dst=/home/container,readonly`,
    image, 'tar', '-C', '/home/container', '-cf', '-', 'config', 'server-data', 'txData', 'recovery']);
  const manifest = { image: docker('image', 'inspect', '--format', '{{.Id}}', image),
    schema: 2, sqlSha256: digest(sql), filesSha256: digest(files) };
  writeFileSync(join(directory, 'database.sql'), sql, { mode: 0o600 });
  writeFileSync(join(directory, 'files.tar'), files, { mode: 0o600 });
  writeFileSync(join(directory, 'manifest.json'), JSON.stringify(manifest), { mode: 0o600 });

  // Subsequent source changes must not appear in the backup or in the restored database.
  await source.database.openAccount('license:' + 'c'.repeat(40));
  const sourceAfterBackup = await rows(source.database);
  const savedManifest = JSON.parse(readFileSync(join(directory, 'manifest.json'), 'utf8'));
  const savedSql = readFileSync(join(directory, 'database.sql'));
  const savedFiles = readFileSync(join(directory, 'files.tar'));
  assert.equal(digest(savedSql), savedManifest.sqlSha256);
  assert.equal(digest(savedFiles), savedManifest.filesSha256);
  assert.equal(docker('image', 'inspect', '--format', '{{.Id}}', image), savedManifest.image);
  const [emptyTables] = await target.database.pool.query('SHOW TABLES');
  assert.equal(emptyTables.length, 0, 'Restore must start with a separate empty database');
  run(['exec', '-i', target.container, 'sh', '-c',
    'exec mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'], { input: savedSql });
  run(['run', '--rm', '-i', '--mount', `type=volume,src=${target.volume},dst=/home/container`, image,
    'tar', '-C', '/home/container', '--no-same-owner', '-xf', '-'], { input: savedFiles });

  // Regenerate both secret representations before any restored application operation.
  docker(...target.gameArgs, 'python3', '/opt/open-freemode/scripts/launcher.py', 'configure');
  const config = JSON.parse(docker(...target.gameArgs, 'cat', '/home/container/config/database.json'));
  assert.ok(config.host === target.name && config.database === target.dbName && config.password === target.password,
    'Restore configuration must use the new database credentials');
  const cfg = docker(...target.gameArgs, 'cat', '/home/container/server-data/server.cfg');
  const encoded = cfg.split('\n').find(line => line.startsWith('set ofm_db_options ')).split(' ')[2];
  assert.ok(JSON.stringify(JSON.parse(Buffer.from(encoded, 'base64').toString())) === JSON.stringify(config),
    'The restored game ConVar must match the new private configuration');
  assert.equal(docker(...target.gameArgs, 'cat', '/home/container/config/operator.cfg'), '# recovery fixture operator settings');
  assert.equal(docker(...target.gameArgs, 'stat', '-c', '%a', '/home/container/config/database.json'), '600');
  await target.database.initialize();
  assert.deepEqual(await rows(target.database), snapshot, 'Restored account IDs and timestamps must match the backup');
  assert.equal((await target.database.openAccount(identity)).id, account.id, 'Reconnect must retain the account ID');

  // Run the shipped CLI in another fresh application container, then confirm isolation.
  docker(...target.gameArgs, 'python3', '/opt/open-freemode/scripts/launcher.py', 'migrate');
  assert.deepEqual(await target.database.listCharacters(account.id), characters, 'Restoration must retain character appearance');
  await target.database.openAccount('license:' + 'd'.repeat(40));
  assert.deepEqual(await rows(source.database), sourceAfterBackup, 'Restore operations must not mutate the source');
  if (serverKey) {
    const game = docker('run', '--detach', '--interactive', '--tty', '--network', networkName,
      '--mount', `type=volume,src=${target.volume},dst=/home/container`, '--env-file', join(directory, 'restore-game.env'),
      '--publish', '127.0.0.1::30120/tcp', '--publish', '127.0.0.1::30120/udp', image);
    containers.push(game);
    console.log('Restored deployment verified; checking authenticated native startup.');
    const deadline = Date.now() + 120000;
    let logs;
    do {
      logs = docker('logs', game);
      writeFileSync(join(dirname(keyFile), 'native-test.log'), logs, { mode: 0o600 });
      assert.equal(docker('inspect', '--format', '{{.State.Running}}', game), 'true', 'Native server exited early');
      if (logs.includes('[ofm_db] Schema 2 ready.')) break;
      assert.ok(Date.now() < deadline, 'Native resources did not reach database readiness');
      await delay(500);
    } while (true);
    const endpoint = docker('port', game, '30120/tcp');
    assert.match(endpoint, /^127\.0\.0\.1:\d+$/);
    const response = await fetch(`http://${endpoint}/info.json`, { signal: AbortSignal.timeout(5000) });
    assert.ok(response.ok, 'Native server info endpoint failed');
    const info = await response.text();
    const published = JSON.parse(info);
    for (const resource of ['chat', 'ofm_db', 'ofm_core']) {
      assert.ok(published.resources.includes(resource), `Required resource ${resource} is not running`);
    }
    assert.ok(!info.includes(target.password) && !info.includes(encoded) && !info.includes(serverKey) && !info.includes('ofm_db_options'),
      'Private configuration must not be exposed in server info');
    attachment = await attachConsole(game);
    let attachError = false;
    attachment.on('error', () => { attachError = true; });
    const waitForNewLog = async (marker, count) => {
      const deadline = Date.now() + 30000;
      while (true) {
        const logs = docker('logs', game);
        writeFileSync(join(dirname(keyFile), 'native-test.log'), logs, { mode: 0o600 });
        if (logs.split(marker).length - 1 > count) return;
        assert.ok(Date.now() < deadline, 'Native transition not observed: ' + marker);
        assert.ok(!attachError, 'Console attachment failed');
        await delay(250);
      }
    };
    const status = async ready => {
      const marker = `[ofm_core] database=${ready ? 'ready' : 'unavailable'} profiles=0`;
      for (const ending of ['\n', '\r', '\r\n']) {
        const count = docker('logs', game).split(marker).length - 1;
        attachment.write('ofm_status' + ending);
        await waitForNewLog(marker, count);
      }
    };
    await status(true);
    // Exercise the actual Lua -> JS export boundary, including nested arrays.
    // Installed only after startup in this disposable fixture; never bundled.
    const probe = `CreateThread(function()
      SetRoutingBucketPopulationEnabled(999999, false)
      local features = {}; for i = 1, 20 do features[i] = 2 end
      exports.ofm_db:createCharacter('${account.id}', 2, {
        version=1, sex=1, father=2, mother=23, resemblance=4, skinMix=6,
        hair=3, hairColor=4, hairHighlight=5, eyes=6, features=features
      }, function(ok, result)
        assert(ok and #result == 2 and result[2].slot == 2)
        assert(result[2].appearance.features[20] == 2)
        exports.ofm_db:listCharacters('${account.id}', function(loaded, saved)
          assert(loaded and saved[2].id == result[2].id)
          print('Character export bridge passed.')
        end)
      end)
    end)`;
    run(['exec', '-i', game, 'python3', '-c',
      "import sys; from pathlib import Path; root=Path('/home/container/server-data/resources/ofm_character_probe'); root.mkdir(); (root/'fxmanifest.lua').write_text(\"fx_version 'cerulean'\\ngame 'gta5'\\nserver_script 'server.lua'\\n\"); (root/'server.lua').write_text(sys.stdin.read())"], { input: probe });
    attachment.write('refresh\r');
    await delay(500);
    attachment.write('ensure ofm_character_probe\r');
    await waitForNewLog('Character export bridge passed.', 0);
    const unavailable = '[ofm_db] Database unavailable; profile admission suspended.';
    const unavailableCount = docker('logs', game).split(unavailable).length - 1;
    docker('stop', '--time', '10', target.container);
    await waitForNewLog(unavailable, unavailableCount);
    await status(false);
    const readiness = '[ofm_db] Schema 2 ready.';
    let readyCount = docker('logs', game).split(readiness).length - 1;
    docker('start', target.container);
    await waitForNewLog(readiness, readyCount);
    await status(true);
    const stopped = 'Stopped resource ofm_db';
    const stoppedCount = docker('logs', game).split(stopped).length - 1;
    attachment.write('stop ofm_db\r');
    await waitForNewLog(stopped, stoppedCount);
    await status(false);
    readyCount = docker('logs', game).split(readiness).length - 1;
    attachment.write('ensure ofm_db\r');
    await waitForNewLog(readiness, readyCount);
    await status(true);
    const stoppedAt = Date.now();
    docker('stop', '--time', '10', game);
    assert.ok(Date.now() - stoppedAt < 10000, 'Native shutdown exceeded Wings grace period');
    assert.equal(docker('inspect', '--format', '{{.State.ExitCode}}', game), '0', 'Native stop was not clean');
    console.log('Authenticated runtime passed: resources, console, SQL outage/recovery, resource restart, info privacy and clean shutdown verified.');
  }
  console.log('Recovery passed: matched SQL/files restored into separate storage; accounts, operator settings, private credentials and source isolation verified.');
} catch (error) {
  console.error(error instanceof assert.AssertionError ? 'Recovery assertion failed: ' + error.message.split('\n')[0]
    : 'Recovery fixture failed; private SQL, configuration and runtime output were withheld.');
  process.exitCode = 1;
} finally {
  attachment?.destroy();
  await Promise.allSettled(pools.map(pool => pool.close()));
  for (const container of containers.reverse()) docker('rm', '--force', '--volumes', container);
  for (const volume of volumes) docker('volume', 'rm', volume);
  if (network) docker('network', 'rm', network);
  const resolved = realpathSync(directory);
  if (dirname(resolved) !== realpathSync(tmpdir()) || !basename(resolved).startsWith('open-freemode-recovery-')) {
    throw new Error('Refusing cleanup outside the recovery fixture directory');
  }
  rmSync(resolved, { recursive: true, force: true });
}
