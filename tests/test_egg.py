import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class EggTests(unittest.TestCase):
    def test_install_uses_root_capable_pelican_installer(self):
        egg = json.loads((ROOT / 'pelican/egg-open-freemode.json').read_text())
        installation = egg['scripts']['installation']
        self.assertTrue(installation['container'].startswith('ghcr.io/pelican-eggs/installers:debian@sha256:'))
        self.assertEqual(installation['entrypoint'], 'bash')
        self.assertIn('test -d /mnt/server', installation['script'])
        self.assertNotIn('/opt/open-freemode', installation['script'])
        self.assertNotIn(installation['container'], egg['docker_images'].values())


if __name__ == '__main__':
    unittest.main()
