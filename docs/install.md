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

The separate, pinned Pelican installer only validates that the server volume is mounted. The first normal start initializes persistent directories as the runtime container user, and the application image already contains the verified resource bundle.

If installation reports `bash: /mnt/install/install.sh: Permission denied`, the egg still uses the application image as its installation container. Reimport the current egg, or edit its install-script container to the pinned `ghcr.io/pelican-eggs/installers:debian` digest from `pelican/egg-open-freemode.json`, keep the script entrypoint set to `bash`, save, and reinstall the server. This repair does not require replacing its database or server volume.

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

Join with normal FiveM Legacy and create a character. After saving appearance, confirm the three-step Open Freemode orientation appears and does not overlap the appearance editor. Complete it, reconnect, and verify it does not appear again for that character. Check that F7 and `/guide` open the searchable handbook, `/activities` opens the four activity cards, Escape closes cleanly, and each card sets a route to its matching world marker. Then confirm `M` opens the limited freemode menu, `F2` opens inventory, and death returns the player to LSIA after five seconds. Visit the **Pizza Delivery** blip in Vinewood, complete all five marked doors, confirm the $750 bank deposit, and verify the scooter disappears. `/pizza_cancel` must remove an abandoned route and scooter without paying it.

For owned vehicles, visit the **Premium Deluxe Motorsport** blip and purchase a starter car using bank funds. Confirm the charge happens once and the new plate appears at **Legion Square Garage**. Retrieve it, reconnect while it is out and verify the garage offers recovery when no matching vehicle exists. Drive it back into the garage marker and store it; a vMenu car with the same visible plate must still be rejected. Retrieve the owned car again, visit **Burton Customs**, buy a repair, upgrade or respray, store it and retrieve it once more to confirm the properties persist. Purchases and modifications must be rejected while the player is in an activity.

For racing, spawn or obtain a vehicle, drive to the **Airport Dash** blip at LSIA and enter the marker as the driver. Choose **Solo time trial**, confirm the vehicle remains frozen through the three-second countdown, drive through all nine checkpoints in order and verify the finish notification shows elapsed time, personal best, leaderboard rank and a $500 bank deposit. `/race_cancel` must end the run without deleting the player's vehicle or paying a result.

With at least two testers, choose **Public race queue**. Keep every queued driver and their original vehicle inside the LSIA staging marker until the lobby locks. Confirm cars move into separate queue-ordered grid slots, all entrants receive the synchronized five-second countdown, cars do not collide during the countdown or first three seconds, only racers appear in the isolated match, and everyone receives finish positions and returns to normal freemode with their vehicles afterward. Cancelling during the countdown must restore the car to its original staging position. First through third pay $1,000, $750 and $600; later finishers receive $500.

For combat, take at least two testers on foot to the **Terminal Clash TDM** blip outside Maze Bank Arena and join the marker. Confirm the ten-second lobby produces balanced red and blue teams in an isolated Terminal arena, the five-second countdown keeps players frozen and invincible, and each player receives only the temporary carbine, pistol and armor. Inventory and vMenu controls must remain unavailable during the match. Confirm enemy kills change the team score once, suicides and friendly kills do not score, death respawns at a rotating team spawn after four seconds, and the first team to 15 kills ends the match. Winners should receive $1,200 and losers $600 exactly once before everyone returns to the original queue location with no match weapons and with their previous health and armor. `/tdm_cancel`, disconnecting, and leaving one team empty must clean up the match without an unearned payout.

For cops and robbers, take 2–6 testers on foot to the **City Escape Cops & Robbers** blip at Mission Row. Confirm the first queued player receives the wanted robber role and a Sultan while everyone else receives the police role and separate cruisers. After the protected five-second countdown, the robber should see five ordered yellow checkpoints and police should see a live getaway target. Confirm checkpoints accept only the assigned getaway vehicle with its robber driving, police deaths produce a replacement cruiser after five seconds, and the round resolves for police when the robber dies, the getaway car is destroyed or five minutes expire. Completing all checkpoints must resolve for the robber. Winners receive $1,500 and losers $700 exactly once. All temporary weapons and vehicles must disappear afterward while each player returns to Mission Row with their previous routing, health, armor and wanted level. `/pursuit_cancel`, disconnecting, and leaving either team empty must cancel without an unearned payout.

## Updating

Follow [the registry update procedure](registry.md). Image replacement preserves the server volume and database. When the verified image bundle changes, the launcher installs it atomically and moves the previous resources into the persistent `recovery/` directory under a content-derived name. Remove that preserved copy only after the updated server has passed its gameplay checks.
