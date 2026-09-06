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
  assert.equal(sql("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='ofm_test' AND table_name IN ('players','playerskins','player_outfits','bans','player_groups','ofm_activity_results','ofm_race_results','ofm_match_results','ofm_vehicle_purchases','ofm_property_purchases','ofm_player_guides')"), '11');
  sql("INSERT INTO playerskins (citizenid,model,skin) VALUES ('fixture','mp_m_freemode_01','{}')");
  sql("INSERT INTO players (citizenid,license,name,money,job,position,metadata) VALUES ('activity-fixture','license:fixture','Fixture','{}','{}','{}','{}')");
  sql("INSERT INTO ofm_activity_results (result_id,citizenid,activity,payout) VALUES ('fixture-result','activity-fixture','pizza',750)");
  sql("INSERT IGNORE INTO ofm_activity_results (result_id,citizenid,activity,payout) VALUES ('fixture-result','activity-fixture','pizza',999)");
  assert.equal(sql("SELECT CONCAT(COUNT(*),':',MAX(payout)) FROM ofm_activity_results WHERE result_id='fixture-result'"), '1:750', 'Activity result was not idempotent');
  sql("INSERT INTO ofm_race_results (result_id,citizenid,race_id,elapsed_ms,payout) VALUES ('race-result','activity-fixture','airport_dash',65432,500)");
  sql("INSERT IGNORE INTO ofm_race_results (result_id,citizenid,race_id,elapsed_ms,payout) VALUES ('race-result','activity-fixture','airport_dash',1,999)");
  assert.equal(sql("SELECT CONCAT(COUNT(*),':',MIN(elapsed_ms),':',MAX(payout)) FROM ofm_race_results WHERE result_id='race-result'"), '1:65432:500', 'Race result was not idempotent');
  sql("INSERT INTO ofm_race_results (result_id,citizenid,race_id,elapsed_ms,payout) VALUES ('public-race-result','activity-fixture','airport_dash_public',70123,1000)");
  assert.equal(sql("SELECT CONCAT(race_id,':',elapsed_ms,':',payout) FROM ofm_race_results WHERE result_id='public-race-result'"), 'airport_dash_public:70123:1000', 'Public race result was not preserved');
  sql("INSERT INTO ofm_match_results (result_id,match_id,citizenid,activity,team,kills,deaths,won,payout) VALUES ('tdm-result','terminal-clash:fixture','activity-fixture','terminal_clash','red',15,4,1,1200)");
  sql("INSERT IGNORE INTO ofm_match_results (result_id,match_id,citizenid,activity,team,kills,deaths,won,payout) VALUES ('tdm-result','terminal-clash:fixture','activity-fixture','terminal_clash','blue',0,99,0,1)");
  assert.equal(sql("SELECT CONCAT(COUNT(*),':',team,':',kills,':',deaths,':',won,':',payout) FROM ofm_match_results WHERE result_id='tdm-result' GROUP BY team,kills,deaths,won,payout"), '1:red:15:4:1:1200', 'TDM result was not idempotent');
  sql("INSERT INTO player_vehicles (license,citizenid,vehicle,hash,mods,plate,state,garage) VALUES ('license:fixture','activity-fixture','blista','-344943009','{\"plate\":\"OFMTEST\"}','OFMTEST',1,'legion_square')");
  sql("INSERT INTO ofm_vehicle_purchases (purchase_id,citizenid,vehicle_id,model,price) SELECT 'vehicle-fixture','activity-fixture',id,'blista',18000 FROM player_vehicles WHERE plate='OFMTEST'");
  sql("INSERT IGNORE INTO ofm_vehicle_purchases (purchase_id,citizenid,vehicle_id,model,price) SELECT 'vehicle-fixture','activity-fixture',id,'sultan',1 FROM player_vehicles WHERE plate='OFMTEST'");
  assert.equal(sql("SELECT CONCAT(COUNT(*),':',model,':',price) FROM ofm_vehicle_purchases WHERE purchase_id='vehicle-fixture' GROUP BY model,price"), '1:blista:18000', 'Vehicle purchase was not idempotent');
  sql("INSERT INTO ofm_property_purchases (purchase_id,citizenid,property_id,price) VALUES ('property-fixture','activity-fixture','alta_street',150000)");
  sql("INSERT IGNORE INTO ofm_property_purchases (purchase_id,citizenid,property_id,price) VALUES ('property-fixture','activity-fixture','del_perro',1)");
  assert.equal(sql("SELECT CONCAT(COUNT(*),':',property_id,':',price) FROM ofm_property_purchases WHERE purchase_id='property-fixture' GROUP BY property_id,price"), '1:alta_street:150000', 'Property purchase was not idempotent');
  sql("INSERT INTO ofm_player_guides (citizenid,onboarding_version,completed_at) VALUES ('activity-fixture',1,CURRENT_TIMESTAMP)");
  sql("INSERT INTO ofm_player_guides (citizenid,onboarding_version,completed_at) VALUES ('activity-fixture',0,CURRENT_TIMESTAMP) ON DUPLICATE KEY UPDATE onboarding_version=GREATEST(onboarding_version,VALUES(onboarding_version))");
  assert.equal(sql("SELECT CONCAT(COUNT(*),':',MAX(onboarding_version),':',completed_at IS NOT NULL) FROM ofm_player_guides WHERE citizenid='activity-fixture'"), '1:1:1', 'Onboarding completion was not monotonic');
  sql("DELETE FROM players WHERE citizenid='activity-fixture'");
  assert.equal(sql("SELECT COUNT(*) FROM ofm_activity_results WHERE result_id='fixture-result'"), '0', 'Activity result did not follow character deletion');
  assert.equal(sql("SELECT COUNT(*) FROM ofm_race_results WHERE result_id='race-result'"), '0', 'Race result did not follow character deletion');
  assert.equal(sql("SELECT COUNT(*) FROM ofm_race_results WHERE result_id='public-race-result'"), '0', 'Public race result did not follow character deletion');
  assert.equal(sql("SELECT COUNT(*) FROM ofm_match_results WHERE result_id='tdm-result'"), '0', 'TDM result did not follow character deletion');
  assert.equal(sql("SELECT COUNT(*) FROM ofm_vehicle_purchases WHERE purchase_id='vehicle-fixture'"), '0', 'Vehicle purchase did not follow character deletion');
  assert.equal(sql("SELECT COUNT(*) FROM ofm_property_purchases WHERE purchase_id='property-fixture'"), '0', 'Property purchase did not follow character deletion');
  assert.equal(sql("SELECT COUNT(*) FROM player_vehicles WHERE plate='OFMTEST'"), '0', 'Owned vehicle did not follow character deletion');
  assert.equal(sql("SELECT COUNT(*) FROM ofm_player_guides WHERE citizenid='activity-fixture'"), '0', 'Guide completion did not follow character deletion');
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
    assert.ok(logs.includes('[ofm_activities] Terminal Clash TDM ready.'), 'TDM readiness missing');
    assert.ok(logs.includes('[ofm_activities] City Escape cops and robbers ready.'), 'Pursuit readiness missing');
    assert.ok(logs.includes('[ofm_vehicles] Owned vehicle dealer, garage and modification service ready.'), 'Owned vehicle readiness missing');
    assert.ok(logs.includes('[ofm_properties] Purchasable apartment garages ready.'), 'Property readiness missing');
    assert.ok(logs.includes('[ofm_hub] Onboarding, activity browser and handbook ready.'), 'Handbook readiness missing');
    assert.ok(!/SCRIPT ERROR|Error loading script|Failed to load script|Error parsing script/.test(logs), 'Resource error; inspect private test log');
    const endpoint = docker('port', game, '30120/tcp');
    const response = await (await fetch(`http://${endpoint}/info.json`)).text();
    const info = JSON.parse(response);
    for (const resource of ['chat','spawnmanager','sessionmanager','hardcap','baseevents','qbx_core','qbx_vehicles','ox_lib','ox_inventory','oxmysql','illenium-appearance','pma-voice','vMenu','ofm_activities','ofm_properties','ofm_vehicles','ofm_hub','ofm_session']) {
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
