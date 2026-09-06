"""Build a pinned resource bundle; downloads are verified before extraction."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

root = Path(__file__).resolve().parents[1]
destination = root / 'build/legacy-resources'
if destination.exists():
    shutil.rmtree(destination)
destination.mkdir(parents=True)
cache = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'build/downloads'
cache.mkdir(parents=True, exist_ok=True)
for item in json.loads((root / 'resources.lock.json').read_text(encoding='utf-8-sig')):
    archive = cache / (item['name'] + '.zip')
    if not archive.exists():
        with urllib.request.urlopen(item['url'], timeout=60) as response, archive.open('wb') as output:
            shutil.copyfileobj(response, output)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != item['sha256']:
        raise ValueError('Checksum mismatch: ' + item['name'])
    with tempfile.TemporaryDirectory() as temporary:
        with zipfile.ZipFile(archive) as bundle:
            for entry in bundle.infolist():
                path = PurePosixPath(entry.filename)
                if path.is_absolute() or '..' in path.parts or '\\' in entry.filename or ':' in entry.filename:
                    raise ValueError('Unsafe archive path')
                if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError('Resource archive symlinks are unsupported')
            bundle.extractall(temporary)
        source = Path(temporary) / item['archive_root']
        if item['name'] == 'cfx-server-data':
            for name in ['spawnmanager', 'sessionmanager', 'hardcap', 'baseevents']:
                matches = list((source / 'resources').rglob(name))
                assert len(matches) == 1
                shutil.copytree(matches[0], destination / name)
            shutil.copytree(source, root / 'build/cfx-source', dirs_exist_ok=True)
        else:
            shutil.copytree(source, destination / item['name'])
    print('Verified ' + item['name'])

# The source-data chat directory expects runtime build tools. Use the compiled
# copy shipped in the same pinned FXServer artifact instead, without carrying
# the runtime itself into the application image.
with tempfile.TemporaryDirectory() as temporary:
    runtime = Path(temporary) / 'runtime'
    subprocess.run([sys.executable, str(root / 'scripts/fetch-runtime.py'),
                    str(root / 'runtime.lock.json'), str(runtime)], check=True)
    compiled_chat = runtime / 'alpine/opt/cfx-server/citizen/system_resources/chat'
    if not (compiled_chat / 'dist/ui.html').is_file():
        raise ValueError('Pinned runtime does not contain compiled chat')
    shutil.copytree(compiled_chat, destination / 'chat')
print('Verified compiled chat from pinned runtime')

# Explicit, version-checked configuration changes, never heuristic source patching.
def replace(path, before, after):
    text = path.read_text()
    if text.count(before) != 1:
        raise ValueError('Upstream configuration changed: ' + str(path))
    path.write_text(text.replace(before, after))

core = destination / 'qbx_core'
replace(core / 'config/client.lua', 'startingApartment = true', 'startingApartment = false')
replace(core / 'config/client.lua', 'enableDeleteButton = true', 'enableDeleteButton = false')
replace(core / 'config/client.lua', 'enabled = true, -- This will enable', 'enabled = false, -- This will enable')
replace(core / 'config/server.lua', 'hungerRate = 4.2', 'hungerRate = 0')
replace(core / 'config/server.lua', 'thirstRate = 3.8', 'thirstRate = 0')
for optional_table in ['properties', 'bank_accounts_new', 'player_mails',
                       'npwd_calls', 'npwd_darkchat_channel_members',
                       'npwd_marketplace_listings', 'npwd_messages_participants',
                       'npwd_notes', 'npwd_phone_contacts', 'npwd_phone_gallery',
                       'npwd_twitter_profiles', 'npwd_match_profiles']:
    replace(core / 'config/server.lua', "        {'" + optional_table + "', ",
            "        -- {'" + optional_table + "', ")
(core / 'config/shared.lua').write_text("""-- Open Freemode configuration; Qbox retains its upstream license.
return {
    serverName = 'Open Freemode',
    defaultSpawn = vec4(-1037.6, -2737.8, 20.17, 330.0),
    notifyPosition = 'top-right',
    starterItems = {},
}
""")
# oxmysql's URI parser does not decode escaped credentials. Pelican-generated
# passwords can contain URI delimiters, so preserve them through URL encoding.
replace(destination / 'oxmysql/dist/build.js',
        'user: authTarget[0] || void 0,\n    password: authTarget[1] || void 0,',
        'user: authTarget[0] ? decodeURIComponent(authTarget[0]) : void 0,\n    password: authTarget[1] ? decodeURIComponent(authTarget[1]) : void 0,')
shutil.copytree(root / 'legacy-resources', destination, dirs_exist_ok=True)
shutil.copyfile(root / 'resources.lock.json', root / 'build/resources.lock.json')
