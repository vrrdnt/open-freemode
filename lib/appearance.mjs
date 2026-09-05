export class CharacterInputError extends Error {}

// Versioned, bounded creation inputs. No client-supplied model hashes or assets.
export function validateAppearance(value) {
  const fail = () => { throw new CharacterInputError('Invalid character appearance'); };
  const ranges = {
    version: [1, 1], sex: [0, 1], father: [0, 20], mother: [21, 41],
    resemblance: [0, 10], skinMix: [0, 10], hair: [0, 22],
    hairColor: [0, 63], hairHighlight: [0, 63], eyes: [0, 30],
  };
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail();
  if (Object.keys(value).length !== Object.keys(ranges).length + 1) fail();
  const result = {};
  for (const [key, [low, high]] of Object.entries(ranges)) {
    if (!Number.isInteger(value[key]) || value[key] < low || value[key] > high) fail();
    result[key] = value[key];
  }
  if (!Array.isArray(value.features) || value.features.length !== 20) fail();
  result.features = Array.from(value.features, feature => {
    if (!Number.isInteger(feature) || feature < -10 || feature > 10) fail();
    return feature;
  });
  return result;
}

export function validateCharacterOwner(account, slot) {
  if (typeof account !== 'string' || !/^[1-9][0-9]{0,19}$/.test(account) ||
      (slot !== undefined && slot !== 1 && slot !== 2)) {
    throw new CharacterInputError('Invalid character slot');
  }
}
