import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';

const image = process.argv[2] || 'open-freemode:development';
const volume = 'ofm-smoke-' + randomUUID();
let container;
const docker = (...args) => execFileSync('docker', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
const fixtures = ['FIVEM_LICENSE_KEY=synthetic-test-key', 'DB_HOST=database.example.invalid',
  'DB_NAME=synthetic', 'DB_USER=synthetic', 'DB_PASSWORD=synthetic-test-password'];
const mount = `type=volume,src=${volume},dst=/home/container`;
try {
  docker('volume', 'create', '--label', 'org.open-freemode.test=image', volume);
  // Docker populates a new named volume from the image, preserving UID 1000 ownership.
  for (let pass = 0; pass < 2; pass++) {
    docker('run', '--rm', '--mount', mount, ...fixtures.flatMap(value => ['--env', value]),
      image, 'python3', '/opt/open-freemode/scripts/launcher.py', 'configure');
    const inspect = (...args) => docker('run', '--rm', '--mount', mount, image, ...args);
    assert.equal(inspect('id', '-u'), '1000');
    assert.equal(inspect('stat', '-c', '%a', '/home/container/config/database.json'), '600');
    assert.equal(inspect('stat', '-c', '%F', '/home/container/server-data/resources'), 'directory');
    inspect('cmp', '/home/container/server-data/resources/ofm_core/server.lua', '/opt/open-freemode/resources/ofm_core/server.lua');
    if (pass === 0) {
      inspect('python3', '-c', "from pathlib import Path; Path('/home/container/config/operator.cfg').write_text('# preserved smoke marker\\n')");
    } else {
      assert.equal(inspect('cat', '/home/container/config/operator.cfg'), '# preserved smoke marker');
    }
    // No real key is available in CI. Prove discovery and fail closed at license
    // validation under Docker's default security profile, with and without TTY.
    container = docker('run', '--detach', ...(pass ? ['--interactive', '--tty'] : []), '--mount', mount,
      ...fixtures.flatMap(value => ['--env', value]), image);
    const deadline = Date.now() + 120000;
    while (docker('inspect', '--format', '{{.State.Running}}', container) === 'true') {
      assert.ok(Date.now() < deadline, 'Native process did not finish the invalid-key probe');
      await delay(250);
    }
    const logs = docker('logs', container);
    assert.ok(/Found \d+ resources/.test(logs), 'Native resource discovery not observed');
    assert.ok(logs.includes('Invalid key format'), 'Expected synthetic key rejection not observed');
    assert.equal(docker('inspect', '--format', '{{.State.ExitCode}}', container), '1');
    docker('rm', container);
    container = undefined;
    console.log(`Image smoke pass ${pass + 1}: non-root runtime, private files, replacement persistence, resource discovery and invalid-key rejection verified.`);
  }
} catch (error) {
  console.error(error instanceof assert.AssertionError ? error.message : 'Image smoke failed; runtime logs were withheld.');
  process.exitCode = 1;
} finally {
  if (container) docker('rm', '--force', container);
  docker('volume', 'rm', volume);
}
