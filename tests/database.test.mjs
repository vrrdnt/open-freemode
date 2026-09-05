import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { Database } from '../lib/database.mjs';

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
    await database.pool.query('UPDATE ofm_schema SET version = 2');
    await assert.rejects(database.initialize({ resume: true }), /newer application/);
    const [[row]] = await database.pool.query('SELECT version FROM ofm_schema');
    assert.equal(row.version, 2);
    await database.pool.query('UPDATE ofm_schema SET version = 1');
  });

  await t.test('an interrupted initial migration requires explicit resume', async () => {
    await database.pool.query('DROP TABLE ofm_accounts');
    await database.pool.query('UPDATE ofm_schema SET version = 0');
    await assert.rejects(database.initialize(), /Incomplete schema/);
    await database.initialize({ resume: true });
    assert.ok((await database.openAccount(identity)).id);
  });

  await t.test('an unrelated database is not initialized', async () => {
    await database.pool.query('DROP TABLE ofm_accounts');
    await database.pool.query('DROP TABLE ofm_schema');
    await database.pool.query('CREATE TABLE operator_data (id INT)');
    await assert.rejects(database.initialize({ resume: true }), /not an Open Freemode database/);
    const [tables] = await database.pool.query('SHOW TABLES');
    assert.deepEqual(tables.map(row => Object.values(row)[0]), ['operator_data']);
  });
});
