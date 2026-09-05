import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { Database } from '../lib/database.mjs';
const appearance = {version: 1, sex: 0, father: 0, mother: 21, resemblance: 5, skinMix: 5,
  hair: 0, hairColor: 0, hairHighlight: 0, eyes: 0, features: Array(20).fill(0)};

test('missing database fields are rejected without printing values', () => {
  assert.throws(() => new Database({ host: 'private-host' }), { message: 'Missing database setting: user' });
});

test('MariaDB persistence and schema safety', { skip: !process.env.OFM_TEST_DB_CONFIG }, async t => {
  const options = JSON.parse(await readFile(process.env.OFM_TEST_DB_CONFIG, 'utf8'));
  assert.equal(options.database, 'ofm_test', 'Integration tests may only use the disposable ofm_test database');
  let database = new Database(options);
  t.after(async () => database.close());
  await database.initialize();
  const identity = 'license:' + 'a'.repeat(40);
  let id;

  await t.test('concurrent requests create exactly one durable profile', async () => {
    const accounts = await Promise.all(Array.from({ length: 20 }, () => database.openAccount(identity)));
    id = accounts[0].id;
    assert.ok(accounts.every(account => account.id === id));
    const [[row]] = await database.pool.query('SELECT COUNT(*) AS count FROM ofm_accounts');
    assert.equal(row.count, '1');
  });

  await t.test('reopening the pool preserves the profile', async () => {
    await database.close();
    database = new Database(options);
    await database.initialize();
    assert.equal((await database.openAccount(identity)).id, id);
  });

  await t.test('invalid identities cannot reach SQL', async () => {
    await assert.rejects(database.openAccount("'; DROP TABLE ofm_accounts;--"), /Invalid server identity/);
    assert.equal((await database.openAccount(identity)).id, id);
  });

  await t.test('concurrent creation and retry preserve the first character in each slot', async () => {
    const results = await Promise.all(Array.from({ length: 20 }, () => database.createCharacter(id, 1, appearance)));
    const character = results[0][0];
    assert.ok(results.every(result => result.length === 1 && result[0].id === character.id));
    const retry = await database.createCharacter(id, 1, {...appearance, sex: 1});
    assert.deepEqual(retry[0], character, 'Retry must not overwrite a committed character');
    const both = await database.createCharacter(id, 2, {...appearance, sex: 1});
    assert.equal(both.length, 2);
    assert.equal(both[1].appearance.sex, 1);
    await assert.rejects(database.createCharacter(id, 3, appearance), /Invalid character slot/);
    await assert.rejects(database.createCharacter(id, 1, {...appearance, hair: 999}), /Invalid character appearance/);
    await database.close();
    database = new Database(options);
    await database.initialize();
    assert.deepEqual(await database.listCharacters(id), both, 'Restart must retain both characters and their appearance');
    const other = await database.openAccount('license:' + 'b'.repeat(40));
    assert.deepEqual(await database.listCharacters(other.id), [], 'Another account must not see these slots');
  });

  await t.test('schema 1 upgrades without changing existing accounts, and interrupted upgrade retries', async () => {
    await database.pool.query('DROP TABLE ofm_characters');
    await database.pool.query('UPDATE ofm_schema SET version = 1');
    await database.initialize();
    assert.equal((await database.openAccount(identity)).id, id);
    assert.deepEqual(await database.listCharacters(id), []);
    await database.createCharacter(id, 1, appearance);
    await database.pool.query('UPDATE ofm_schema SET version = 1');
    await database.initialize();
    assert.equal((await database.listCharacters(id)).length, 1);
    const [[marker]] = await database.pool.query('SELECT version FROM ofm_schema');
    assert.equal(marker.version, 2);
  });

  await t.test('another migrator excludes initialization', async () => {
    const held = await database.pool.getConnection();
    try {
      await held.query('SELECT GET_LOCK(?, 0)', [database.lock]);
      await assert.rejects(database.initialize(), /Another schema operation/);
    } finally {
      await held.query('SELECT RELEASE_LOCK(?)', [database.lock]);
      held.release();
    }
  });

  await t.test('newer schemas are refused without mutation', async () => {
    await database.pool.query('UPDATE ofm_schema SET version = 3');
    await assert.rejects(database.initialize({ resume: true }), /newer application/);
    const [[row]] = await database.pool.query('SELECT version FROM ofm_schema');
    assert.equal(row.version, 3);
    await database.pool.query('UPDATE ofm_schema SET version = 2');
  });

  await t.test('an interrupted initial migration requires explicit resume', async () => {
    await database.pool.query('DROP TABLE IF EXISTS ofm_characters');
    await database.pool.query('DROP TABLE ofm_accounts');
    await database.pool.query('UPDATE ofm_schema SET version = 0');
    await assert.rejects(database.initialize(), /Incomplete schema/);
    await database.initialize({ resume: true });
    assert.ok((await database.openAccount(identity)).id);
  });

  await t.test('a malformed partial table cannot advance the schema marker', async () => {
    await database.pool.query('DROP TABLE IF EXISTS ofm_characters');
    await database.pool.query('DROP TABLE ofm_accounts');
    await database.pool.query('CREATE TABLE ofm_accounts (id BIGINT PRIMARY KEY)');
    await database.pool.query('UPDATE ofm_schema SET version = 0');
    await assert.rejects(database.initialize({ resume: true }), { code: 'ER_BAD_FIELD_ERROR' });
    const [[marker]] = await database.pool.query('SELECT version FROM ofm_schema WHERE id = 1');
    assert.equal(marker.version, 0, 'Failed migration must remain incomplete');
    await database.pool.query('DROP TABLE IF EXISTS ofm_characters');
    await database.pool.query('DROP TABLE ofm_accounts');
    await database.initialize({ resume: true });
  });

  await t.test('an unrelated database is not initialized', async () => {
    await database.pool.query('DROP TABLE IF EXISTS ofm_characters');
    await database.pool.query('DROP TABLE ofm_accounts');
    await database.pool.query('DROP TABLE ofm_schema');
    await database.pool.query('CREATE TABLE operator_data (id INT)');
    await assert.rejects(database.initialize({ resume: true }), /not an Open Freemode database/);
    const [tables] = await database.pool.query('SHOW TABLES');
    assert.deepEqual(tables.map(row => Object.values(row)[0]), ['operator_data']);
  });
});
