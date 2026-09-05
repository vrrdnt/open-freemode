import { readFile } from 'node:fs/promises';
import { Database } from '../lib/database.mjs';

let database;
try {
  const options = JSON.parse(await readFile(process.argv[2] || '/home/container/config/database.json', 'utf8'));
  database = new Database(options);
  await database.initialize({ resume: true });
  console.log('Open Freemode schema 2 ready.');
} catch {
  console.error('Migration failed. Check the private settings, database access and schema compatibility. No credentials are logged.');
  process.exitCode = 1;
} finally {
  await database?.close();
}
