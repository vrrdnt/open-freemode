# Server design

Open Freemode uses one persistent character and shared world across all activities. Money, owned vehicles, identity and appearance remain in Qbox. Each activity temporarily owns player routing, rules, loadout and scoring, then returns the player safely to freemode.

## Shared activity contract

Every activity resource will use the same lifecycle:

1. **Queue**: validate the player, party, vehicle and requested mode on the server.
2. **Prepare**: save the freemode position and relevant state, assign a routing bucket, and issue the activity loadout or vehicle.
3. **Play**: keep score and authoritative state on the server; clients report inputs and observations only.
4. **Resolve**: calculate rewards once using an idempotent match/result record.
5. **Restore**: remove temporary equipment, return the player to the shared world and recover correctly after death, disconnect or resource restart.

This contract prevents four separate scripts from fighting over death, inventory, vehicles, routing buckets and rewards.

## Milestones

### 1. Foundation and owned vehicles

Complete the client walkthrough, then add a Qbox-compatible garage and vehicle shop. vMenu cars remain temporary; purchases create persistent `player_vehicles` records. LSC-style modification needs a shop/resource that validates ownership and stores vehicle properties. Property garages can initially be activated locations tied to a character before a full housing system is chosen.

### 2. Pizza delivery vertical slice — implemented, client validation pending

Pizza delivery is the first end-to-end activity. The current slice provides five randomized stops, a temporary scooter, server-side order/proximity/timing checks, an idempotent result ledger, bank payment and cleanup on cancellation, death, disconnect or resource shutdown. Its map placement, door coordinates, animation and driving feel still need a real-client pass.

### 3. Racing — first playable slice implemented, client validation pending

Airport Dash provides the first curated point-to-point route. Solo mode locks the current vehicle for a three-second start and records a time-trial leaderboard. Public mode queues 2–8 nearby drivers, locks the lobby after ten seconds, moves entrants into an isolated match bucket, synchronizes a five-second start, records server-side finish order and pays $1,000/$750/$600 for the first three places and $500 for later finishers. Both modes validate the same driver and vehicle at every ordered checkpoint and restore the vehicle and player on finish, cancellation, death or disconnect. Class-specific vehicles and player route creation wait until this first multiplayer flow is client-validated.

### 4. Team deathmatch

Add team assignment, instanced arenas, approved loadouts, round state, score limits, death/respawn rules and post-match restoration. Freemode inventory must not leak into match loadouts or vice versa.

### 5. Cops and robbers

Build this on the shared activity contract with asymmetric teams, pursuit objectives, wanted/escape state, vehicle rules and round resolution. Police roleplay jobs are a separate concern from this match mode.

## Interface direction

Use game-native scaleform and menus where they fit moment-to-moment play, and focused NUI surfaces for rich content such as onboarding, activity browsing, rules and a searchable handbook. Keep the pause map useful by adding only stable destinations; move dense or temporary activity listings into the activity browser.
