# Fresh installation on Pelican

This is the primary installation path. Start with a **new Pelican server, new persistent files and an empty database**. No backup, SQL import, local test directory, pre-existing account or node-side image build is required.

The current release provides Enhanced client access, persistent accounts, an initial character creator and a temporary airport spawn. The full creator, classic GTA Online tutorial, money and missions are still being developed. Keep this installation tester-only.

## 1. Prepare the prerequisites

You need:

- Administrator access to an installed Pelican Panel and a working Linux **amd64** Wings node.
- FiveM for GTA V Enhanced on the testing PC.
- A Cfx server key created in your own [Cfx Portal](https://portal.cfx.re/) account for this deployment. Keep it private.
- A reachable MySQL/MariaDB service. MariaDB **11.4** is the tested version. If you do not have a database service, use the appendix below first.
- One available game port, such as **30120**, reachable over **TCP and UDP**. If the node is behind a router, forward both protocols to the node. Use the externally reachable address when connecting from another PC.
- Outbound HTTPS from Wings to GHCR and from the game container to Cfx. The first start downloads the pinned Cfx runtime and caches it; it does not compile anything.

This guide assumes Panel/Wings are already installed. A fresh installation has been reported working by the operator. Exact Panel/Wings versions remain to be recorded; this is not a claim that every Pelican version is supported.

## 2. Register a database host in Pelican

If Database Hosts already contains a working host available to this node, proceed to step 3.

1. Open the Panel's **Admin → Database Hosts** page and choose **Create / +**.
2. In the preparation wizard, choose the Panel/database topology correctly. The database must allow connections from the Panel's actual network source, including container networking if applicable.
3. Choose a dedicated **provisioning username and password** for Pelican. This account creates per-server databases and users; it is not the account FiveM will use.
4. Follow the wizard's Database Setup instructions on the database service using its administrator account. The wizard supplies the provisioning-user SQL. Run it there, not in the FiveM console.
5. In Panel Setup, enter a descriptive name, database host address, port (normally `3306`), and those provisioning credentials. Associate the intended Wings node if the form offers node restrictions, then save.
6. Confirm the host saves successfully. The hostname must be reachable from both the Panel and game containers. Do not use `localhost` as a cross-container database address.

Restrict database network access to the Panel and Wings sources that need it. A successful Panel connection alone does not prove game-container access. Pelican's [Database Hosts guide](https://pelican.dev/docs/guides/database-hosts/) explains provisioning and common connection errors.

## 3. Import the fresh-install egg

1. Download [egg-open-freemode.json](https://raw.githubusercontent.com/vrrdnt/open-freemode/main/pelican/egg-open-freemode.json). Save the raw JSON file; do not save the GitHub HTML page.
2. Open **Admin → Eggs** and use the import/upload action. Import that JSON.
3. Open the imported **Open Freemode Enhanced (development)** egg.
4. Confirm the runtime image and installation image are both `ghcr.io/vrrdnt/open-freemode:dev`.
5. Leave its startup command and stop configuration as supplied. No txAdmin port or setup is used.

For an exact repeatable build, use the digest-pinned egg supplied with the installation handoff. Its two image fields point to the same immutable digest. The `dev` tag moves when an update is published; a digest does not.

## 4. Create a completely new server

1. Open **Admin → Servers → Create**.
2. Choose the server owner, a name such as `Open Freemode Staging`, and your intended node.
3. Select the imported Open Freemode egg and its GHCR image.
4. Select an unused primary game allocation, for example port `30120`. Ensure TCP and UDP reach that allocation. Extra allocations are not needed for txAdmin.
5. Set **Databases = 1** under Feature Limits. File-backup capacity is optional for initial installation; it is not an installation input.
6. For a small initial test, an **8192 MiB memory limit and 20 GiB disk allowance** are provisional starting allocations, not measured capacity guarantees. Use a CPU limit appropriate to available node capacity. Adjust based on observed use.
7. Set Server name, Player limit (`30` is the package default), and your Cfx server key. Leave the database host/name/user/password blank for now. Database port can remain `3306`.
8. Disable **start after installation / automatic first start**, if offered. Create the server and allow the installer to run.

The current egg permits blank database fields during creation because the per-server database does not exist yet. The launcher still refuses to start gameplay without them. If creation demands database credentials, re-import the current egg rather than entering fake credentials.

Expected installation result: Pelican reports installation complete, and its file manager shows `config`, `server-data`, `txData` and `recovery`. The empty `txData`/`recovery` directories are reserved paths; they do not indicate that a restore is required. The runtime cache appears after the first start.

## 5. Allocate an empty database to this server

1. Open the new server's **Databases** page.
2. Choose **Create database** and select the database host from step 2.
3. Use a descriptive name, such as `open_freemode`. Pelican may prefix the actual database name and username; use the exact generated values.
4. If a connections-from/allowed-host field is offered, allow the database-visible source of this Wings/game container. Docker/NAT may make that different from the game server's public address.
5. Create it and open its connection details.

**Leave it empty. Do not import SQL.** The application creates its own tables on first successful connection.

## 6. Enter the database connection details

As administrator, open the server's startup/environment settings. These variables are intentionally not exposed to ordinary subusers, so use the admin server editor if the user-facing Startup page hides them.

| Variable | Value to enter |
|---|---|
| `DB_HOST` | Reachable address of the registered database host |
| `DB_PORT` | Database service port, normally `3306` |
| `DB_NAME` | Exact database name generated in step 5 |
| `DB_USER` | Exact per-server username generated in step 5 |
| `DB_PASSWORD` | Password for that per-server user |
| `FIVEM_LICENSE_KEY` | Your own Cfx server key |
| `SERVER_NAME` | Display name for this server |
| `MAX_PLAYERS` | Initial slot limit, e.g. `30` |

Save the settings. Do not put the Database Host provisioning account into these fields. Do not manually edit `server-data/server.cfg` or `config/database.json`; startup generates them from these variables. Pelican's primary allocation supplies the game port through `SERVER_PORT`.

## 7. Start and let the empty database initialize

1. Open the server console and select **Start**.
2. On the first start, wait for the runtime download and checksum verification. Future starts with that runtime pin reuse the cache.
3. Wait for `[ofm_db] Schema 2 ready.` and confirm `ofm_core` starts.
4. Enter `ofm_status` in the **Pelican server console**. Expect `database=ready profiles=0` before any tester has joined.

The first start creates `ofm_schema`, `ofm_accounts` and `ofm_characters`. You do not need a migration command or a database administration tool for a clean installation. An account row is created only after an authorized player's first connection.

If a required setting is missing, stop the retry loop and correct it. Do not enable general player access to work around a database failure.

## 8. Authorize your first tester from scratch

1. In FiveM Enhanced, enter `> YOUR_SERVER_ADDRESS:PORT` in the server search/direct-connect field and connect.
2. The first connection is expected to be rejected with the development access notice. With the current image, the message includes **Your tester identifier: `license:...`**. This is the connecting player's own server-verified identifier.
3. Copy that identifier privately. It is not your Cfx account name, server key, display name, or the internal numeric profile ID.
4. In Pelican's file manager, open `config/operator.cfg` and add a line using the complete identifier:

   ```cfg
   add_ace identifier.license:YOUR_40_HEX_CHARACTERS ofm.join allow
   ```

   For example, prepend `identifier.` to the complete `license:...` value. Do not duplicate the `license:` prefix.

5. Save the file, then **restart the server** to apply it.
6. Reconnect from FiveM. The database should create your new account, then character selection opens. Create and save a character, then select it to spawn at the airport. See the [character walkthrough](characters.md).

Repeat for each tester. Keep identifiers private and do not authorize `builtin.everyone`. No tester data is copied from another installation.

## 9. Verify the independent installation

Confirm each result:

- Initial unauthorized connection was rejected.
- Authorized connection spawned a character at the airport, with normal movement.
- `ofm_status` reports `database=ready profiles=1` while that tester is connected.
- Disconnect/reconnect works. The client log's `Open Freemode character N (slot S) loaded` message retains the same character number for that slot.
- Pelican stop/start works, and a subsequent reconnect retains that account.

Record the image digest, Panel/Wings versions, Linux architecture and database version with these results. That is the evidence for a reproducible fresh deployment. Recovery testing can follow after this baseline works; it is not a prerequisite or an input to installation.

## Troubleshooting

| Symptom | Check |
|---|---|
| Image pull denied/not found | Both egg image fields use the published GHCR reference. The public package needs no GitHub token. Check registry connectivity and stale Wings registry credentials. |
| `DB_* is missing or invalid` | Fill the admin startup variables after allocating the database. |
| Database unavailable | Check the full generated database/user names, password, allowed connection source and network reachability from the game container. |
| Runtime download failed | Check outbound Cfx HTTPS access, available disk and volume write permissions. Retry; a failed download is not installed as a valid cache. |
| No tester identifier in rejection | Check that the image includes the fresh-install change and the client is authenticated. Use the current egg/image, not an older digest. |
| Still unauthorized after editing | Check `identifier.license:` prefix, full identifier, `ofm.join allow`, and restart after saving. |
| Profile loaded but no character | Inspect the client log for resource errors; a server-side profile count does not prove a spawn. |
| Resources differ from image on a supposedly new server | Confirm this is a new server volume with no uploaded runtime files. Preserve any existing files and investigate; do not import a backup. |

## Appendix: if no database service exists

This optional example starts a separate MariaDB 11.4 service on a Docker host you administer. Skip it if a suitable service already exists. It is infrastructure for Pelican Database Hosts, not a second game container inside the FiveM server.

1. Choose a private host interface address reachable by the Panel and Wings. Replace `DB_PRIVATE_IP` below before running anything. Restrict inbound port 3306 to those sources.
2. Create a private configuration directory and open an environment file:

   ```sh
   sudo install -d -m 700 /opt/pelican-game-db
   sudo install -m 600 /dev/null /opt/pelican-game-db/mariadb.env
   sudo nano /opt/pelican-game-db/mariadb.env
   ```

3. Put `MARIADB_ROOT_PASSWORD=YOUR_NEW_RANDOM_PASSWORD` on one line, using your own strong password, and save. This example is for a new service; do not overwrite an existing database service's files.
4. Start the pinned service:

   ```sh
   sudo docker run -d --name pelican-game-db --restart unless-stopped \
     --env-file /opt/pelican-game-db/mariadb.env \
     --publish DB_PRIVATE_IP:3306:3306 \
     --mount type=volume,src=pelican-game-db-data,dst=/var/lib/mysql \
     mariadb:11.4@sha256:611a2fcc5fa7c6ceb8644c6f74b25ede004ff6c3a6b38c8f8c23d3bbf6c26430
   ```

5. For step 2's provisioning SQL, open a database administrator session with `sudo docker exec -it pelican-game-db mariadb -u root -p`. Enter the root password at its prompt. Run the SQL generated by Pelican's Database Hosts wizard, then enter `exit`.
6. Register this host in Pelican, then follow steps 3–9. Do not manually create or import game tables.

The database volume and environment file must survive service replacement. See the [official MariaDB container guidance](https://mariadb.com/kb/en/installing-and-using-mariadb-via-docker/) for service administration beyond this fresh setup.
