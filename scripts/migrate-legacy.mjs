import mysql from 'mysql2/promise';
import { readFile } from 'node:fs/promises';

let connection;
try {
  const options = JSON.parse(await readFile(process.argv[2], 'utf8'));
  connection = await mysql.createConnection({ ...options, multipleStatements: true, charset: 'utf8mb4' });
  const [old] = await connection.query("SHOW TABLES LIKE 'ofm_accounts'");
  if (old.length) throw new Error('Use a separate empty database for the Legacy conversion.');
  const [[lock]] = await connection.query("SELECT GET_LOCK('ofm_legacy_migrate', 30) AS acquired");
  if (lock.acquired !== 1) throw new Error('Migration lock unavailable');
  await connection.query(await readFile(new URL('../resources/qbx_core/qbx_core.sql', import.meta.url), 'utf8'));
  await connection.query(await readFile(new URL('../resources/qbx_vehicles/vehicles.sql', import.meta.url), 'utf8'));
  for (const file of ['playerskins', 'player_outfits', 'player_outfit_codes', 'management_outfits']) {
    const sql = await readFile(new URL(`../resources/illenium-appearance/sql/${file}.sql`, import.meta.url), 'utf8');
    await connection.query(sql.replaceAll('DEFAULT CHARSET=latin1', 'DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'));
  }
  console.log('Open Freemode Legacy database ready.');
} catch {
  console.error('Legacy migration failed. Use a dedicated MariaDB database; verify private credentials and inspect schema compatibility. Enhanced databases are not converted in place.');
  process.exitCode = 1;
} finally {
  await connection?.end();
}
