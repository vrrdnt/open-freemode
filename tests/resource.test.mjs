import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { runInNewContext } from 'node:vm';

test('bundled server resource registers its API and rejects missing configuration', () => {
  const api = {}, handlers = {}, errors = [];
  runInNewContext(readFileSync('build/resources/ofm_db/server.js', 'utf8'), {
    require: createRequire(import.meta.url), Buffer, process, URL,
    setTimeout, clearTimeout, setInterval, clearInterval, setImmediate, clearImmediate,
    exports: (name, callback) => { api[name] = callback; },
    on: (name, callback) => { handlers[name] = callback; },
    GetConvar: () => '', GetCurrentResourceName: () => 'ofm_db',
    console: { log() {}, error(message) { errors.push(message); } },
  });
  assert.equal(api.isReady(), false);
  let result;
  api.openAccount('license:' + 'a'.repeat(40), ok => { result = ok; });
  assert.equal(result, false);
  assert.equal(errors.length, 1);
  assert.match(errors[0], /Invalid private database configuration/);
  handlers.onResourceStop('ofm_db');
});
