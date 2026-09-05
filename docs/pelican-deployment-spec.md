# Pelican deployment specification

Status: proposed implementation contract, 5 September 2026. This is not an importable egg or a tested operator runbook. It makes the [architecture](design.md) concrete enough to implement and test without depending on one operator's infrastructure.

## Operator workflow

1. Obtain a tagged release containing an egg, an image digest, release metadata, source/build instructions, migrations, licenses and a tested-version matrix. These artifacts do not exist yet.
2. Import the egg and create a **staging** server on a supported Linux amd64 Wings node. Assign a game port for TCP/UDP and a distinct administration TCP port. Give the server one database allowance and a positive backup allowance.
3. Register an existing MySQL/MariaDB service as a Database Host if needed; allocate a dedicated database to the server. The operator enters its generated per-database credentials in private server settings. The initial design uses this manual handoff; Pelican does not automatically supply those values through our proposed egg variables.
4. Enter the server's own Cfx key, public name and player limit. Verify private SQL connectivity from both the panel and game container and administrator access to txAdmin.
5. Run installation, then start. Complete txAdmin's initial account/setup flow against the prepared server-data directory and configuration. Avoid a recipe that independently downloads another framework or tracks latest resources.
6. Complete the foundation tests below before enabling public admission. Production is a separate Pelican server with its own database, storage and credentials, using the same tested release.

An allowance permits creating a database or assigning additional allocations; it is not itself a database or an open port. The database host's provisioning account belongs to the panel and must never reach the game container. [Pelican Database Hosts](https://pelican.dev/docs/guides/database-hosts/)

## Image and persistent files

The deployment runs one game container. Pelican's installation script runs in a separate, temporary installation container; this does not add a permanent service. Pin that installation image too, or test using the same release image for both roles. [Egg installation lifecycle](https://pelican.dev/docs/eggs/creating-a-custom-egg/)

| Path | Owner and lifetime |
|---|---|
| `/opt/open-freemode/runtime/` | Selected Enhanced artifact and bundled txAdmin, immutable release input subject to distribution terms |
| `/opt/open-freemode/resources/` | Built resources and UI, immutable; modifications arrive through a new release |
| `/opt/open-freemode/release.json` | Public versions, checksums and schema/reference compatibility metadata |
| `/home/container/config/operator.cfg` | Persistent operator configuration for documented, non-managed settings |
| `/home/container/server-data/server.cfg` | Generated game configuration, with a header identifying its source settings |
| `/home/container/server-data/resources` | Proposed symlink to the image's resource directory; must pass the actual artifact/sandbox test |
| `/home/container/server-data/cache/` | Rebuildable cache; validate the actual runtime location and exclude from routine backups |
| `/home/container/txData/` | Persistent txAdmin account/configuration/log state; private |
| `/home/container/recovery/` | Private restore/maintenance metadata and backup-set references |

Pelican's persistent mount hides image files placed at `/home/container`. Seed persistent data through installation at `/mnt/server`, then use the mounted path at runtime. Run the game as the image's non-root `container` user. Test ownership through both installation and runtime; do not solve permission failures with world-writable directories. [Pelican image requirements](https://pelican.dev/docs/eggs/creating-a-custom-yolk/)

The resource symlink is a proposed arrangement, not established Enhanced compatibility. Check resource discovery, client downloads, resource sandbox reads and any resource writes. Bundled resources must keep mutable data in the documented state paths or SQL. If the artifact cannot use this arrangement, revise the layout before publishing an egg; never silently replace it with independently editable old copies on the volume.

Installation creates missing seed directories/files only. It does not start SQL migrations, reset a database, replace txAdmin administrators or overwrite existing operator settings. If a managed symlink location contains unexpected files, stop and explain the conflict without deleting or moving them automatically. Reinstallation must pass a fixture containing pre-existing configuration and unrelated operator files.

## Configuration authority

The egg startup should invoke a fixed launcher without embedding secrets in the command. The launcher reads validated environment settings, constructs arguments as arguments, and writes properly escaped configuration. It must not evaluate settings as shell code. Real `.env` files are optional operator tooling, not files that Pelican automatically imports.

| Input | Source | Planned consumer |
|---|---|---|
| Game port | Pelican's built-in `SERVER_PORT` allocation | Launcher derives the game endpoint; `GAME_PORT` in the example is for a future standalone invocation |
| Administration port | `TXADMIN_PORT`, matching an assigned allocation | `TXHOST_TXA_PORT` |
| Player cap | `MAX_PLAYERS`, within entitlement and tested capacity | `TXHOST_MAX_SLOTS` and game slot configuration |
| Persistent admin path | Fixed package path | `TXHOST_DATA_PATH=/home/container/txData` |
| Interface and game restriction | Package defaults | `TXHOST_INTERFACE=0.0.0.0`, `TXHOST_GAME_NAME=fivem` |
| Game endpoint enforcement | Derived game port | `TXHOST_FXS_PORT` |
| Public identity | `SERVER_NAME` and documented operator metadata | Properly escaped game configuration |
| Cfx server key | Private `FIVEM_LICENSE_KEY` setting | Server-only generated configuration |
| Database | Private `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` | Selected driver's verified connection format; never client-replicated settings |

The current txAdmin source documents `TXHOST_*` settings from v8 and deprecates the former port/interface/data-path ConVars. Its port validation also reserves 30120 from use as the admin port and 40120 from use as the game port. The first package should target this configuration interface and pin the actual bundled version; do not copy an older egg's arguments uncritically. [txAdmin configuration at inspected commit](https://github.com/citizenfx/txAdmin/blob/8a9a41410000fd92a527fe11bae2b8eeeb8b10e0/docs/env-config.md)

Leave optional txAdmin host API tokens, provider identity, deployer-default credentials and automatic administrator creation unset unless a defined feature requires them. Ordinary txAdmin setup is sufficient for the initial package. Launch in monitor mode as required by txAdmin; the game configuration is selected for its child game process. [Monitor-mode startup](https://docs.fivem.net/docs/resources/txAdmin/)

Regenerate managed settings on each container start. Operators edit their source settings or `operator.cfg`; edits to the generated configuration through txAdmin are not persistent customization. Define and test include ordering and conflicting-setting rejection so manual edits cannot accidentally select a different database or port. Restrict generated files to the runtime user. Secrets must not be printed in startup diagnostics, sent through replicated ConVars, or bundled in client resources.

Validate credentials without weakening them to suit a naive parser. Test passwords containing connection-string delimiters, spaces, quotes and shell metacharacters using synthetic credentials. A connection URI is not safe merely because values were percent-encoded: the selected parser must actually decode them correctly. Reject an unsupported representation with a redacted error before opening gameplay.

## Lifecycle and readiness

Treat container/administration availability and gameplay readiness separately. A first start may need txAdmin setup while no game is ready. The proposed egg's running marker reports a verified healthy txAdmin monitor, and the operator instructions must explain that meaning. A separate gamemode readiness state gates client admission after SQL, schema, required resources and world initialization succeed. Select the exact marker and health observation from the tested artifact; neither marker is implemented yet.

| Event | Required behavior |
|---|---|
| Container start | Validate configuration and persistent paths; run monitor; game admits players only after compatibility and state checks |
| Routine game restart | txAdmin announces and manages the game process; durable operations reconcile on reconnect |
| Pelican console input | Route documented commands to the intended console; verify with a harmless command on the selected artifact |
| Pelican stop | Stop monitor and all its children; suppress restart during shutdown; terminate within the configured Wings grace period |
| Monitor/game crash | Preserve evidence and use the documented restart owner; prevent two supervisors repeatedly restarting the same failure |
| Missing/wrong SQL or schema | Keep gameplay unavailable; show an operator-actionable, redacted error; never initialize fallback player money |
| Database loss during play | Suspend durable mutations and affected activities; reconcile committed operations before reopening |

Use a minimal init/process arrangement for signal forwarding and child reaping. Test the actual stop command rather than assuming `quit` sent to the game also stops the monitor. Include a genuinely blocked child in the local lifecycle fixture, then repeat the behavior on Wings. Increasing memory or disabling the OOM killer is not a lifecycle fix.

## Schema, updates and recovery

The game release owns a schema version inside its allocated database. Serialize initialization/migration using a database lock and reject another active migration. Use the per-database account's available privileges; do not require creating database users or other databases. Record successful migrations individually and handle partial DDL failures explicitly.

An empty database may initialize on first game start. A normal start of an existing deployment checks compatibility but does not silently perform an incompatible upgrade. For an upgrade, the operator explicitly starts the release's migration mode on staging, then on the stopped production deployment after a matched backup. Define the exact invocation during implementation and expose it through a documented egg startup choice; no invented console command is runnable today.

Restore uses the procedure in the main design: stop writes, verify SQL and file backups completed, identify image/schema/reference revisions, and rehearse restoration on separate storage. Pelican schedules can dispatch console/power/file-backup actions; they do not by themselves wait for our external SQL backup to finish. The initial runbook therefore uses an explicit maintenance procedure with completion checks. [Schedule behavior and backup evidence](design.md#what-pelican-providesand-what-we-add)

Publication includes release metadata without endpoints or credentials. Private backup metadata identifies the actual deployment. The recovery test must prove that restored configuration targets the restore database rather than production, and that a new container can reconstruct owned state without a private application directory or stale image files.

## Foundation acceptance record

Every row needs an observed result, versions/digest, date and sanitized evidence. All rows are currently **not run**.

| ID | Scenario | Required result |
|---|---|---|
| DEP-01 | Fresh egg import, empty volume and newly allocated database | Installation completes; admin setup is reachable; real Enhanced client joins and saves a test profile |
| DEP-02 | Invalid/missing credential, closed SQL route, unsupported schema | Useful redacted failure; no player admitted and no unintended database initialized |
| DEP-03 | Restart, reinstall and replace the container | Configuration, profile and txAdmin account persist; bundled resources match the selected image |
| DEP-04 | Console command, graceful stop, forced child hang and crash | Correct command routing, no orphan/restarting game after stop; recovered state remains consistent |
| DEP-05 | Resource path and permissions | Symlink/resource sandbox/downloads work on Enhanced; runtime works without root; sensitive config never reaches a client |
| DEP-06 | Update previous schema, interrupt migration and retry | No partial state admitted; lock and migration journal resolve the interruption; supported rollback behavior documented |
| DEP-07 | Restore matched SQL/files into a separate deployment | Profile/ownership recover; production credentials and SQL are not used; recovery time/loss measured |
| DEP-08 | Another operator follows only public release instructions | Fresh settings suffice; no private repository, pre-existing txAdmin profile or original-node path required |

Local tests should cover the launcher, quoting, migration and lifecycle failure paths. A green CI job cannot substitute for DEP-01 through DEP-08; specifically, a SQL fixture cannot prove a real Enhanced client join.
