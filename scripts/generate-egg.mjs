import { mkdirSync, writeFileSync } from 'node:fs';

const image = process.argv[2] || 'ghcr.io/vrrdnt/open-freemode:dev';
if (!/^[a-zA-Z0-9][a-zA-Z0-9._/:@-]*$/.test(image)) throw new Error('Supply a Docker image reference');
const settings = [
  ['SERVER_NAME', 'Server name', 'Open Freemode Development', ['required', 'string', 'max:128']],
  ['MAX_PLAYERS', 'Player limit', '30', ['required', 'integer', 'between:1,48']],
  ['FIVEM_LICENSE_KEY', 'Cfx server key', '', ['required', 'string', 'max:128']],
  ['DB_HOST', 'Database host reachable from Wings', '', ['required', 'string']],
  ['DB_PORT', 'Database port', '3306', ['required', 'integer', 'between:1,65535']],
  ['DB_NAME', 'Dedicated database name', '', ['required', 'string']],
  ['DB_USER', 'Dedicated database user', '', ['required', 'string']],
  ['DB_PASSWORD', 'Dedicated database password', '', ['required', 'string']],
];
const egg = {
  _comment: 'Generated with npm run egg -- IMAGE. Configure Wings registry access before installation. Pin a published digest for controlled updates.',
  meta: { version: 'PLCN_v1', update_url: null },
  name: 'Open Freemode Enhanced (development)',
  author: '13125677+vrrdnt@users.noreply.github.com',
  uuid: '49b03c85-cc59-4a27-99d5-3d87c4e106ba',
  description: 'Tester-only foundation. One Enhanced runtime image and one external database. See docs/development.md.',
  features: null,
  docker_images: { [image]: image },
  file_denylist: [],
  startup: 'python3 /opt/open-freemode/scripts/launcher.py',
  config: {
    files: '{}',
    startup: JSON.stringify({ done: '[ofm_db] Schema 1 ready.', strip_ansi: true }),
    stop: '^SIGTERM',
  },
  scripts: { installation: {
    script: '#!/bin/bash\nset -eu\npython3 /opt/open-freemode/scripts/launcher.py install --data-dir /mnt/server\n',
    container: image,
    entrypoint: 'bash',
  } },
  variables: settings.map(([env_variable, name, default_value, rules], index) => ({
    name, description: name + '. Configure privately; never paste credentials into Git or support logs.',
    env_variable, default_value, user_viewable: false, user_editable: false, rules, sort: index + 1,
  })),
};
mkdirSync('pelican', { recursive: true });
writeFileSync('pelican/egg-open-freemode.json', JSON.stringify(egg, null, 2) + '\n');
console.log('Generated pelican/egg-open-freemode.json. No image was published.');
