# Fresh installation on Pelican

This procedure creates an empty Open Freemode Legacy server. It does not import a backup and does not build Docker images on the node.

## Prerequisites

- A Pelican node on Linux amd64 with Docker and at least one TCP/UDP allocation for port 30120.
- A MariaDB or MySQL service registered under **Admin > Database Hosts** and assigned to the node.
- A Cfx.re server key for the public address that will run the server.
- Permission for Wings to pull `ghcr.io/vrrdnt/open-freemode:legacy-dev`. The package is intended to be public; private packages require registry credentials in Wings.

For an initial small test server, allocate 8–10 GiB RAM, enough CPU for one FXServer process, and at least 20 GiB of persistent disk. Actual public capacity must be measured with representative player and activity load.

## 1. Import the egg

1. Download `pelican/egg-open-freemode.json` from the release or repository.
2. In Pelican administration, choose or create a FiveM nest and import the egg.
3. Confirm that its image is `ghcr.io/vrrdnt/open-freemode:legacy-dev`.

## 2. Create the server

1. Create a server with the imported **Open Freemode Legacy** egg.
2. Assign one game allocation. The same port is used for TCP and UDP.
3. Set at least one database in the server's feature limits.
4. Give the server a fresh, empty data directory. Do not upload files from the retired Enhanced build.
5. Finish server creation and let Pelican run the egg installation script.

The installation script only initializes persistent directories. The image already contains the verified resource bundle.

## 3. Allocate an empty database

1. Open the new server's **Databases** page.
2. Create one database on the Database Host assigned to this node.
3. Record the generated host, port, database name, username and password in a password manager or Pelican's private settings. Do not paste them into Git, Discord or support logs.

Use a database dedicated to this server. Startup deliberately refuses a database containing the retired `ofm_accounts` schema; the Legacy conversion is a clean start rather than an in-place data conversion.

## 4. Configure startup variables

In the server's Startup settings, set:

| Variable | Value |
| --- | --- |
| `SERVER_NAME` | Public server name |
| `MAX_PLAYERS` | `1`–`48`; use a small value for testing |
| `FIVEM_LICENSE_KEY` | Cfx.re server key |
| `DB_HOST` | Database host reachable from the Wings node/container |
| `DB_PORT` | Usually `3306` |
| `DB_NAME` | Pelican-generated database name |
| `DB_USER` | Pelican-generated database user |
| `DB_PASSWORD` | Pelican-generated password |

Pelican's primary allocation overrides the default game port automatically. Database credentials may contain URI punctuation; the launcher encodes them safely.

## 5. Choose who may connect

The development build requires the `ofm.join` ACE. Edit `config/operator.cfg` in the server Files page.

For a closed test, add each verified license identifier:

```cfg
add_ace identifier.license:REPLACE_WITH_IDENTIFIER ofm.join allow
```

For an open public test, use:

```cfg
add_ace builtin.everyone ofm.join allow
```

Keep moderation permissions separate; the bundled vMenu grants only public vehicle and weapon features.

## 6. Start and verify

Start the server. On a fresh volume it will:

1. validate settings and generate private configuration;
2. create or update the Qbox, vehicle and appearance tables;
3. download the pinned Cfx Legacy runtime and verify its SHA-256 checksum;
4. start FXServer and the pinned resources.

Wait for:

```text
[ofm_session] Legacy foundation started.
```

Join with normal FiveM Legacy, create a character, reconnect, and confirm the character persists. Check `M` for the limited freemode menu, `F2` for inventory, `/guide` for the current feature summary, and verify that death returns the player to LSIA after five seconds. Then visit the **Pizza Delivery** blip in Vinewood, complete all five marked doors, confirm the $750 bank deposit, and verify the scooter disappears. `/pizza_cancel` must remove an abandoned route and scooter without paying it.

For racing, spawn or obtain a vehicle, drive to the **Airport Dash** blip at LSIA and enter the marker as the driver. Start the race, confirm the vehicle remains frozen through the three-second countdown, drive through all nine checkpoints in order and verify the finish notification shows elapsed time, personal best, leaderboard rank and a $500 bank deposit. `/race_cancel` must end the run without deleting the player's vehicle or paying a result.

## Updating

Follow [the registry update procedure](registry.md). Image replacement preserves the server volume and database. When the verified image bundle changes, the launcher installs it atomically and moves the previous resources into the persistent `recovery/` directory under a content-derived name. Remove that preserved copy only after the updated server has passed its gameplay checks.
