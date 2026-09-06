# Contributing

Keep changes aligned with the four activity pillars and the shared Legacy freemode world. Implement one verifiable gameplay slice at a time and use the existing Qbox player, vehicle and permission APIs instead of adding a second framework.

- Pin every downloaded resource and verify its checksum in `resources.lock.json`.
- Preserve upstream licenses and attribution. Do not commit purchased, escrowed or proprietary assets.
- Keep keys, database credentials, player records, infrastructure names and backups out of Git.
- Treat clients as untrusted. Validate activity membership, loadouts, payouts, vehicle ownership and race results on the server.
- Keep fresh installs automatic and migrations repeatable. Never require an operator to restore a prepared backup.
- Add a lifecycle test when a change affects startup, shutdown, persistence or resource replacement.

Before publishing, run the checks in [docs/development.md](docs/development.md) and review `git diff --check` plus the staged diff.
