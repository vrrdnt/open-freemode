import { Database } from '../../lib/database.mjs';
import { CharacterInputError } from '../../lib/appearance.mjs';

let database;
let ready = false;
let stopped = false;
let timer;

// Errors deliberately omit SQL, parameters, identifiers and connection settings.
function unavailable() {
  if (ready) console.error('[ofm_db] Database unavailable; profile admission suspended.');
  ready = false;
}

exports('isReady', () => ready);
exports('openAccount', (identifier, callback) => {
  if (!ready) return callback(false);
  database.openAccount(identifier).then(
    account => callback(true, account),
    () => { unavailable(); callback(false); },
  );
});

for (const name of ['listCharacters', 'createCharacter']) {
  exports(name, (...args) => {
    const callback = args.pop();
    if (!ready) return callback(false);
    database[name](...args).then(
      result => callback(true, result),
      error => { if (!(error instanceof CharacterInputError)) unavailable(); callback(false); },
    );
  });
}

async function check() {
  try {
    await database.initialize();
    if (!ready && !stopped) console.log('[ofm_db] Schema 2 ready.');
    ready = !stopped;
  } catch {
    unavailable();
  } finally {
    if (!stopped) timer = setTimeout(check, 5000);
  }
}

try {
  // Server-only, resource-restricted ConVar. Base64 transports JSON through the
  // console parser without delimiter ambiguity; it is not encryption.
  const encoded = GetConvar('ofm_db_options', '');
  database = new Database(JSON.parse(Buffer.from(encoded, 'base64').toString('utf8')));
  console.log('[ofm_db] Checking database; inspect the private migration command if readiness fails.');
  void check();
} catch {
  console.error('[ofm_db] Invalid private database configuration; admission disabled.');
}

on('onResourceStop', name => {
  if (name !== GetCurrentResourceName()) return;
  stopped = true;
  ready = false;
  clearTimeout(timer);
  void database?.close();
});
