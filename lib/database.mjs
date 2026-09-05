import mysql from 'mysql2/promise';
import { createHash } from 'node:crypto';
import { validateAppearance, validateCharacterOwner } from './appearance.mjs';

export class Database {
  constructor(options) {
    for (const field of ['host', 'user', 'password', 'database']) {
      if (typeof options[field] !== 'string' || !options[field]) {
        throw new Error(`Missing database setting: ${field}`);
      }
    }
    this.pool = mysql.createPool({
      ...options,
      connectionLimit: 4,
      queueLimit: 32,
      connectTimeout: 5000,
      enableKeepAlive: true,
      multipleStatements: false,
      supportBigNumbers: true,
      bigNumberStrings: true,
      dateStrings: true,
    });
    this.lock = 'ofm_schema_' + createHash('sha256').update(options.database).digest('hex').slice(0, 32);
  }

  async initialize({ resume = false } = {}) {
    const connection = await this.pool.getConnection();
    let locked = false;
    try {
      const [[lock]] = await connection.query('SELECT GET_LOCK(?, 0) AS acquired', [this.lock]);
      if (Number(lock.acquired) !== 1) throw new Error('Another schema operation is running');
      locked = true;
      const [tables] = await connection.query('SHOW TABLES');
      const names = tables.map(row => Object.values(row)[0]);
      const fresh = names.length === 0;
      if (!fresh && !names.includes('ofm_schema')) {
        throw new Error('Database is not an Open Freemode database');
      }
      if (fresh) {
        await connection.query(`CREATE TABLE ofm_schema (
          id TINYINT UNSIGNED PRIMARY KEY,
          product VARCHAR(32) NOT NULL,
          version INT UNSIGNED NOT NULL
        ) ENGINE=InnoDB`);
      }
      const [versions] = await connection.query('SELECT product, version FROM ofm_schema WHERE id = 1');
      if (versions.length && versions[0].product !== 'open-freemode') throw new Error('Wrong database product');
      const version = versions.length ? versions[0].version : 0;
      if (version > 2) throw new Error('Database requires a newer application release');
      if (version === 0) {
        if (!fresh && !resume) throw new Error('Incomplete schema; run the documented migration command');
        await connection.query("INSERT IGNORE INTO ofm_schema VALUES (1, 'open-freemode', 0)");
        await connection.query(`CREATE TABLE IF NOT EXISTS ofm_accounts (
          id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
          identifier VARBINARY(128) NOT NULL UNIQUE,
          first_seen TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
          last_seen TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ) ENGINE=InnoDB`);
      }
      // Also detects a missing or incompatible table even if the version marker survived.
      await connection.query('SELECT id, identifier, first_seen, last_seen FROM ofm_accounts LIMIT 0');
      if (version < 2) {
        await connection.query(`CREATE TABLE IF NOT EXISTS ofm_characters (
          id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
          account_id BIGINT UNSIGNED NOT NULL,
          slot TINYINT UNSIGNED NOT NULL CHECK (slot IN (1, 2)),
          appearance JSON NOT NULL,
          created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
          UNIQUE KEY account_slot (account_id, slot),
          FOREIGN KEY (account_id) REFERENCES ofm_accounts(id)
        ) ENGINE=InnoDB`);
      }
      await connection.query('SELECT id, account_id, slot, appearance, created_at FROM ofm_characters LIMIT 0');
      if (version < 2) await connection.query('UPDATE ofm_schema SET version = 2 WHERE id = 1');
    } finally {
      if (locked) await connection.query('SELECT RELEASE_LOCK(?)', [this.lock]).catch(() => {});
      connection.release();
    }
  }

  async openAccount(identifier) {
    if (typeof identifier !== 'string' || !/^license:[a-f0-9]{40}$/.test(identifier)) {
      throw new Error('Invalid server identity');
    }
    const connection = await this.pool.getConnection();
    try {
      await connection.beginTransaction();
      await connection.execute(`INSERT INTO ofm_accounts (identifier) VALUES (?)
        ON DUPLICATE KEY UPDATE last_seen = CURRENT_TIMESTAMP(3)`, [identifier]);
      const [[account]] = await connection.execute(`SELECT CAST(id AS CHAR) AS id, first_seen, last_seen
        FROM ofm_accounts WHERE identifier = ?`, [identifier]);
      await connection.commit();
      return account;
    } catch (error) {
      await connection.rollback().catch(() => {});
      throw error;
    } finally {
      connection.release();
    }
  }

  async listCharacters(account) {
    validateCharacterOwner(account);
    const [rows] = await this.pool.execute(`SELECT CAST(id AS CHAR) AS id, slot, appearance
      FROM ofm_characters WHERE account_id = ? ORDER BY slot`, [account]);
    return rows.map(row => ({ id: row.id, slot: row.slot,
      appearance: validateAppearance(typeof row.appearance === 'string' ? JSON.parse(row.appearance) : row.appearance) }));
  }

  async createCharacter(account, slot, appearance) {
    validateCharacterOwner(account, slot);
    const checked = validateAppearance(appearance);
    // A lost response or competing confirmation returns the committed slot;
    // it cannot replace its appearance or create a second character there.
    await this.pool.execute(`INSERT INTO ofm_characters (account_id, slot, appearance) VALUES (?, ?, ?)
      ON DUPLICATE KEY UPDATE id = id`, [account, slot, JSON.stringify(checked)]);
    return this.listCharacters(account);
  }

  async ping() { await this.pool.query('SELECT 1'); }
  async close() { await this.pool.end(); }
}
