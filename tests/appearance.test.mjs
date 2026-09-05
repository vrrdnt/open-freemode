import test from 'node:test';
import assert from 'node:assert/strict';
import { validateAppearance } from '../lib/appearance.mjs';

export const appearance = {version: 1, sex: 0, father: 0, mother: 21, resemblance: 5, skinMix: 5,
  hair: 0, hairColor: 0, hairHighlight: 0, eyes: 0, features: Array(20).fill(0)};

test('appearance rejects arbitrary assets, extra fields, non-finite and malformed values', () => {
  assert.deepEqual(validateAppearance(appearance), appearance);
  for (const bad of [null, [], {...appearance, model: 'arbitrary'}, {...appearance, sex: 2},
    {...appearance, hair: 9999}, {...appearance, eyes: NaN}, {...appearance, father: '1'},
    {...appearance, features: Array(19).fill(0)}, {...appearance, features: Array(20).fill(Infinity)},
    {...appearance, features: Array(20).fill(0.5)}, {...appearance, version: 2}]) {
    assert.throws(() => validateAppearance(bad), /Invalid character appearance/);
  }
});
