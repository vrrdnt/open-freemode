# Development and verification

## Local requirements

- Docker Desktop or Docker Engine with Linux containers
- Node.js 22
- Python 3.11 or newer

Install JavaScript dependencies and build the exact image:

```powershell
npm ci --ignore-scripts
docker build -t open-freemode:legacy-development .
```

Resource downloads occur inside the build. Each archive URL, source revision and SHA-256 checksum is recorded in `resources.lock.json`. The Cfx runtime is recorded separately in `runtime.lock.json`: the build extracts its compiled stock chat, while the final image omits the runtime and downloads it into the persistent server volume on first start.

## Checks

Run launcher unit tests on Linux so process-group and symlink behavior is exercised:

```powershell
docker run --rm -v "${PWD}:/work" -w /work python:3.13-slim `
  python -m unittest discover -s tests -p 'test_*.py' -v
```

Build and run the public CI fixture:

```powershell
docker build -t open-freemode:legacy-development .
node scripts/test-legacy.mjs
```

That fixture creates disposable MariaDB, network and volume objects; applies migrations twice; verifies the schema and persistence; and starts the real native runtime far enough to receive the expected rejection for a synthetic license key. It always removes its temporary Docker objects.

An authenticated maintainer can opt into the additional lifecycle check without placing a key in the repository:

```powershell
$env:OFM_TEST_KEY_FILE = (Resolve-Path private/server-key.env).Path
$env:OFM_TEST_LOG_FILE = Join-Path (Resolve-Path private).Path 'legacy-native.log'
node scripts/test-legacy.mjs
```

The key file contains one `FIVEM_LICENSE_KEY=...` line and stays ignored. This path verifies that every required resource starts, the info endpoint omits credentials, graceful stop succeeds, the same container restarts against immutable resources, and SQL data persists. It still does not replace a real FiveM client walkthrough.

The pure activity state machine also runs outside FiveM:

```sh
lua5.4 tests/activity_state.test.lua legacy-resources/ofm_activities/server/state.lua
lua5.4 tests/race_queue.test.lua legacy-resources/ofm_activities/server/matchmaking.lua
lua5.4 tests/combat_score.test.lua legacy-resources/ofm_activities/server/combat_score.lua
```

It covers activity reservation, pizza and race starts, forged tokens, wrong checkpoint order, proximity limits, timing limits, completion replay, cancellation, queue capacity, queue removal, lobby locking, TDM deaths, friendly fire, duplicate death suppression, respawning and score-limit victory. Native integration verifies every activity result schema and resource startup.

Regenerate the Pelican egg and prove the checked-in artifact is current:

```powershell
npm run egg
git diff --exit-code -- pelican/egg-open-freemode.json
```

## Adding a resource

1. Confirm Legacy, Qbox and OneSync compatibility from the upstream project.
2. Check its license and distribution terms.
3. Pin an immutable release or commit and SHA-256 in `resources.lock.json`.
4. Add deterministic configuration in `scripts/fetch-resources.py` or a small local overlay under `legacy-resources`.
5. Add it in dependency order in `scripts/launcher.py`.
6. Extend the native fixture's resource assertion when it is required for startup.
7. Update `THIRD_PARTY.md` and the operator-facing install notes.

Do not edit generated `build/legacy-resources`; it is deleted and recreated on every fetch.
