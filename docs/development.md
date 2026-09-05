# Development package

Status: foundation implementation, 6 September 2026. This is a disposable tester package, not a public gameplay release. Classic onboarding, character appearance storage, money, vehicles, missions and the tutorial remain to be implemented. No starter cash or business portfolio is granted. Test accounts will be reset before the lasting public economy.

## Current architecture

Pelican/Wings runs one non-root game container and controls FXServer directly. A dedicated external database holds accounts. Embedded txAdmin is **deferred**: Enhanced build 139 hung while registering its signal handlers under Docker Desktop's default seccomp profile; `UV_USE_IO_URING=0` did not resolve it. Direct FXServer startup reached resource discovery and license validation in the same image. This matches the [upstream Enhanced Docker report](https://github.com/citizenfx/rfc/discussions/50). The package does not change Docker security profiles or host settings.

The launcher starts the official native executable using an argument array, retaining the `citizen_dir` argument from its `run.sh`, then adds `+exec server.cfg`. A small init reaps children; the launcher forwards stop signals and enforces a five-second shutdown limit. An unsolicited process exit is a service failure, including Cfx's zero exit after an invalid license. Pelican owns crash/restart policy; stop repeated retries while correcting configuration errors.

The generated egg uses `^SIGTERM`. The inspected [Panel converter](https://github.com/pelican-dev/panel/blob/1ddab92795e7611ef54ca3cdf8eb6b7ebe182ba1/app/Services/Eggs/EggConfigurationService.php) maps this to a signal, and the inspected [Wings handler](https://github.com/pelican-dev/wings/blob/65422ff00f60c3e8a37d4b5c725add3d5a4b9a62/environment/docker/power.go) supports SIGTERM. These source inspections are not a test of an installed Pelican instance.

## Build inputs

| Input | Pin |
|---|---|
| Native runtime | Enhanced Linux amd64 build 139; URL and verified SHA-256 in `runtime.lock.json` |
| Bundled txAdmin | 9.0.0-beta-646aba9a; not started |
| Node build/runtime base | Node 22 on Debian Trixie, image digest in `Dockerfile` |
| SQL driver | mysql2 3.24.3; transitive integrity pins in `package-lock.json` |
| Bundler | esbuild 0.25.12 |
| Integration database | MariaDB 11.4 image digest in `scripts/test-database.mjs` |

On first start, the launcher downloads the pinned artifact directly from Cfx and checks its checksum before extraction. It makes Alpine's absolute internal symlinks relative to the bundled Alpine root, then applies Python's safe tar data filter. The verified download is atomically installed under persistent `runtime/SHA256/runtime`; later starts reuse it. Failed downloads do not populate an active cache. The GHCR image does not include Cfx or txAdmin binaries; see [registry setup](registry.md). Base package security updates can change build results; byte-identical reproduction is not claimed.

mysql2 receives structured options. The oxmysql candidate's connection-string parser did not preserve every tested delimiter representation, so this first resource uses the underlying driver directly. It adds only the profile and schema operations needed now; there is no general SQL export available to clients. Third-party licenses remain with their dependencies: the image retains production `node_modules` and their license files, Cfx's attribution file, and the base image notices. Our MIT license covers our original source.

## Build and verify locally

Prerequisites: Docker with Linux amd64 containers and Node 22+. Python 3.12+ and Lua 5.4 on Linux are needed for the host-side tests. Windows users can run those tests through WSL.

```sh
npm ci --ignore-scripts
npm run build
python3 -m unittest discover -s tests -p 'test_*.py' -v
lua tests/core.test.lua
node scripts/test-database.mjs
docker build --platform linux/amd64 -t open-freemode:development .
node scripts/test-image.mjs
node scripts/test-recovery.mjs
npm run egg
```

The database runner creates and removes its own MariaDB container and uses synthetic credentials, including delimiter characters. The image probe uses synthetic credentials and expects Cfx to reject the key; it does not attempt to bypass licensing or establish a game session. The recovery runner restores a matched SQL dump and file archive into a second database and volume, replaces both private credential representations, checks account IDs/timestamps and verifies that restore operations leave the source unchanged. These default tests require no real server key.

For the optional authenticated native test, save an operator-owned test key as `FIVEM_LICENSE_KEY=...` in the ignored `private/server-key.env` file. From PowerShell:

```powershell
$env:OFM_TEST_KEY_FILE = Join-Path $PWD 'private/server-key.env'
node scripts/test-recovery.mjs
Remove-Item Env:OFM_TEST_KEY_FILE
```

This adds native resource startup, console commands, SQL outage/recovery, database resource restart, public-info credential checks and graceful shutdown to the restore fixture. It requires a local Docker socket (Unix socket or Windows named pipe), uses the ordinary Docker security profile, and publishes test ports only on loopback. The Engine console stream supports a TTY container without requiring an interactive host terminal. Raw logs are saved beside the key as `native-test.log`; keep both private. Real keys are never used in CI. This does not launch or test a game client.

## Disposable Pelican installation

This procedure is ready for operator validation; it has not yet passed a real Pelican import/install/client join.

1. Use the [GHCR image](registry.md#use-the-image-in-wings). The checked-in egg refers to `ghcr.io/vrrdnt/open-freemode:dev`; no node-side build is required. Wings must resolve it for both installation and runtime, and the game container needs outbound HTTPS for the initial Cfx download. For a pinned digest or a locally built image, run `npm run egg -- YOUR_IMAGE_REFERENCE` before importing the generated JSON. Use immutable image digests for controlled updates.
2. Import `pelican/egg-open-freemode.json`. Create a staging server using the image; assign its primary game port for TCP and UDP. No txAdmin allocation is needed. Allow one database and provision it through Database Hosts. This does not install a database service: Pelican must already be able to reach a configured MySQL/MariaDB host.
3. Set the egg's private variables: `FIVEM_LICENSE_KEY`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `SERVER_NAME`, and `MAX_PLAYERS`. Use the game's per-database account, never the Database Host provisioning account. The database address must be reachable from the game container; `localhost` refers to that container. Slot count defaults to 30 with a development cap of 48; entitlement and load capacity still require verification.
4. Install. The temporary installer seeds `/mnt/server`; Wings must hand the persistent files back to runtime UID/GID 1000. The image runtime generates configuration at `/home/container`. Installation preserves existing operator files and refuses conflicting resource content.
5. Privately add each authorized tester to `config/operator.cfg`, replacing the placeholder with their actual server-verified license identifier:

   ```cfg
   add_ace identifier.license:YOUR_TESTER_IDENTIFIER ofm.join allow
   ```

6. Start using Pelican. The server rejects players without `ofm.join`. Restrict staging network access to testers: `sv_master1 ""` disables the server-browser connect button but [does not remove the server from the master list](https://docs.fivem.net/docs/server-manual/server-commands/#sv_master1-newvalue). `[ofm_db] Schema 1 ready.` is the egg's proposed readiness marker; it reports database/schema readiness, not proof that a client can load and play. Check that both custom resources start. Run `ofm_status` in the server console to check database readiness and the loaded profile count. The client joins using the game endpoint; there is no txAdmin setup step.
7. Complete the real-client and recovery gates below before admitting public players. Do not widen admission simply to work around a profile or database error.

Hidden Pelican variables are still accessible to sufficiently privileged operators. Restrict panel, console, file and backup access accordingly. Never publish generated settings, SQL dumps or player identifiers.

## Persistent files and resource updates

`/opt/open-freemode` holds immutable build inputs. The launcher copies the bundled resources into the real directory `/home/container/server-data/resources`, then verifies their content against the image on every start. This avoids resource symlinks and outside-resource file reads described as blocked in the [Enhanced sandbox documentation](https://docs.fivem.net/docs/developers/sandbox/). Client resource loading and the temporary airport spawn have passed on the local Enhanced client.

The shared core manifest must not depend on the server-only database resource: Enhanced's client rejected that dependency and never loaded the spawn script. Managed startup already ensures the database before the core; server-side readiness checks govern admission.

`config/operator.cfg` is operator-owned and executes before managed settings. `server-data/server.cfg` and `config/database.json` are generated with mode 0600. The driver receives base64-encoded JSON through a server-only ConVar restricted to `ofm_db`; base64 is transport encoding, **not encryption**. Never print that ConVar. The migration CLI reads the private JSON file outside the game sandbox. Database settings are not inherited by the game process as environment variables.

Resource files are generated deployment copies, not the customization surface. A resource mismatch stops startup without overwriting files. For an intentional image update: stop the staging server, save matched file/SQL backups, move its old `server-data/resources` to a backup location **outside** `server-data/resources`, select the new image, and reinstall/start to seed its exact resources. Keep the old copies for review/rollback. Do not delete the database, configuration or unrelated files. This first implementation deliberately leaves that review step manual. There is no supported automatic schema downgrade.

`txData` and `recovery` directories are reserved persistent paths; txAdmin and a recovery coordinator do not currently run. Pelican file backups do not automatically include the external database.

## Database initialization and recovery

Schema 1 contains `ofm_schema` and `ofm_accounts`. Each account has a unique server-verified `license:` identity and first/last-seen times. Character state and balances do not exist yet. The driver uses parameterized statements, transactions and a unique index to handle concurrent connects.

An empty dedicated database initializes on first resource start. A foreign database, newer schema, missing account table or incomplete initial migration suspends profile admission. A database advisory lock serializes schema initialization. The account requires table creation and ordinary SELECT/INSERT/UPDATE privileges inside its allocated database; it does not require user/database provisioning privileges. The current tests cover MariaDB 11.4, not every MySQL version offered by Pelican.

Initialization advances the schema marker only after the required account columns can be queried. If a partial account table is incompatible, explicit resume fails and leaves version zero for investigation. A stopped or failing database resource also refuses admission instead of leaving an export exception unhandled.

Account admission also tracks connection lifetime. A missing prior player or a repeated completed handshake on the same temporary ID releases an abandoned reservation. Joined sessions remain protected from duplicates. An accepted handshake that never reaches `playerJoining` expires after two minutes; its timer cannot remove a replacement session. This addresses an observed reconnect rejection with zero connected players but one retained profile reservation.

After investigating an interrupted **initial** migration, stop the game and take file/SQL backups. On the Docker host, use a one-shot container with the same image, persistent mount and private environment file:

```sh
docker run --rm --env-file /PRIVATE/PATH/server.env \
  --mount type=bind,src=/PRIVATE/PATH/server-data,dst=/home/container \
  open-freemode:development python3 /opt/open-freemode/scripts/launcher.py migrate
```

Replace the placeholder paths privately, preserving the runtime user's ownership. Success prints `Open Freemode schema 1 ready.`; nonzero exit means stop and investigate. This is not a Pelican console command. Normal server startup does not silently resume an incomplete migration. Schema 1 supports initialization/resume only; future schema upgrades need explicit release migrations.

For restoration, restore matched files and a SQL dump to **separate** storage and a dedicated restore database, supply its new private credentials, and start with the original image. Check the original test account ID after reconnecting. The isolated fixture verifies SQL/file restoration and authenticated native startup; a real Pelican restore with a reconnecting game client remains outstanding. No recovery time or loss guarantee is established.

## Verification

Local evidence, 6 September 2026:

- Image/startup: the application image omits the Cfx runtime; the first-start pinned Enhanced download passed SHA-256 verification and the replacement container reused it.
- Native probe: resource discovery and synthetic-key rejection observed with default Docker security, both ordinary and interactive consoles. The launcher reports this invalid startup as failure.
- Persistent image fixture: replacement containers preserve operator configuration; runtime UID 1000 and private file mode 0600 verified.
- Python launcher fixtures: eight passed, including a real child that ignores SIGTERM and cannot survive supervisor cleanup, rejected checksum mismatch, atomic runtime installation and offline cache reuse.
- Real MariaDB fixture: ten tests passed, covering concurrent profile creation, reconnection, schema locking, interrupted initialization, malformed partial tables, foreign/newer schema rejection and special-character credentials.
- Lua admission harness: authorization, database/resource failure, console-only status, duplicate identity, source-ID transition, spawn replay and reconnect decisions passed with mocked natives.
- Matched backup fixture: SQL and persistent files restored into separate storage; account IDs/timestamps, operator settings, replacement credentials and source isolation verified.
- Authenticated Enhanced build 139: `chat`, `ofm_db` and `ofm_core` loaded with default Docker security and a TTY; the database ConVar worked inside Cfx; console status, SQL outage/recovery, database resource restart and clean shutdown passed. The info endpoint did not expose the tested private settings. No game client was connected.
- Real Enhanced client build 131: tester-only admission rejected the initial unauthorized attempt; after authorization, the client loaded its persisted profile and spawned at the airport. The operator supplied an in-game screenshot confirming the spawn. This test exposed and led to fixes for the server-only manifest dependency and stale handshake reservation. Server logs still distinguish a loaded account from successful client spawning.

Still required: installed Panel/Wings versions and node architecture; real egg installation/ownership; database outage during a real player connection; Pelican console/stop/restart; matched SQL/file restoration through the intended deployment with a reconnecting client; a second independent installation. These remain the P0 acceptance gates. CI cannot substitute for them.

## Community reference leads

The [Cfx server tutorials category](https://forum.cfx.re/c/server-development/server-tutorials/37) includes an [Enhanced game-build report](https://forum.cfx.re/t/game-build-on-fivem-enhanced/5419848) and an [ACE permissions guide](https://forum.cfx.re/t/basic-aces-principals-overview-guide/90917). Use these as investigation leads and verify behavior against official documentation and the pinned runtime. The current generated configuration does not force a Legacy game build; Enhanced DLC availability still needs a real-client check.
