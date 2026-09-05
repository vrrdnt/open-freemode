import { build } from 'esbuild';
import { cp, mkdir } from 'node:fs/promises';

await mkdir('build/resources', { recursive: true });
await cp('resources', 'build/resources', { recursive: true });
await build({
  entryPoints: ['resources/ofm_db/server.js'],
  outfile: 'build/resources/ofm_db/server.js',
  bundle: true,
  platform: 'node',
  target: 'node22',
  format: 'iife',
  legalComments: 'eof',
});
