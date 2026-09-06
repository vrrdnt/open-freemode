import { mkdirSync, writeFileSync } from 'node:fs';

const image = process.argv[2] || 'ghcr.io/vrrdnt/open-freemode:legacy-dev';
if (!/^[a-zA-Z0-9][a-zA-Z0-9._/:@-]*$/.test(image)) throw new Error('Supply a Docker image reference');
const settings = [
  ['SERVER_NAME', 'Server name', 'Open Freemode Development', ['required', 'string', 'max:128']],
  ['MAX_PLAYERS', 'Player limit', '30', ['required', 'integer', 'between:1,48']],
  ['FIVEM_LICENSE_KEY', 'Cfx server key', '', ['required', 'string', 'max:128']],
  ['DB_HOST', 'Database host reachable from Wings', '', ['nullable', 'string']],
  ['DB_PORT', 'Database port', '3306', ['required', 'integer', 'between:1,65535']],
  ['DB_NAME', 'Dedicated database name', '', ['nullable', 'string']],
  ['DB_USER', 'Dedicated database user', '', ['nullable', 'string']],
  ['DB_PASSWORD', 'Dedicated database password', '', ['nullable', 'string']],
];
const egg = {
  _comment: 'Generated with npm run egg -- IMAGE. Configure Wings registry access before installation. Pin a published digest for controlled updates.',
  meta: { version: 'PLCN_v1', update_url: null },
  name: 'Open Freemode Legacy (development)',
  author: '13125677+vrrdnt@users.noreply.github.com',
  uuid: '49b03c85-cc59-4a27-99d5-3d87c4e106ba',
  description: 'Tester-only Legacy Qbox freemode foundation. Racing, TDM, pursuits and pizza delivery are planned. See docs/install.md.',
  features: null,
  docker_images: { [image]: image },
  file_denylist: [],
  startup: 'python3 /opt/open-freemode/scripts/launcher.py',
  config: {
    files: '{}',
    startup: JSON.stringify({ done: '[ofm_session] Legacy foundation started.', strip_ansi: true }),
    stop: '^SIGTERM',
  },
  scripts: { installation: {
    script: '#!/bin/bash\nset -eu\npython3 /opt/open-freemode/scripts/launcher.py install --data-dir /mnt/server\n',
    container: image,
    entrypoint: 'bash',
  } },
  variables: settings.map(([env_variable, name, default_value, rules], index) => ({
    name, description: name + (['DB_HOST', 'DB_NAME', 'DB_USER', 'DB_PASSWORD'].includes(env_variable)
      ? '. May be blank during server creation; required before starting. Copy from the database allocated to this server.'
      : '. Configure privately; never paste credentials into Git or support logs.'),
    env_variable, default_value, user_viewable: false, user_editable: false, rules, sort: index + 1,
  })),
};
mkdirSync('pelican', { recursive: true });
writeFileSync('pelican/egg-open-freemode.json', JSON.stringify(egg, null, 2) + '\n');
console.log('Generated pelican/egg-open-freemode.json. No image was published.');
