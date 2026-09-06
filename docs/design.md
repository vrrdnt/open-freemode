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

### 1. Foundation and owned vehicles — first playable slice implemented, client validation pending

Premium Deluxe Motorsport sells three server-priced starter cars from bank funds and records each request once. Purchases create persistent Qbox `player_vehicles` records stored at Legion Square. That garage retrieves only the current character's vehicles, recovers vehicles left marked out after a restart, and saves health and dirt when storing. Burton Customs validates the driver and Qbox vehicle identity on the server before charging for repairs, performance upgrades or resprays and saving the resulting properties. vMenu and activity cars have no owned vehicle identity, so they cannot enter this persistent loop. Property garages can initially be activated locations tied to a character before a full housing system is chosen.

### 2. Pizza delivery vertical slice — implemented, client validation pending

Pizza delivery is the first end-to-end activity. The current slice provides five randomized stops, a temporary scooter, server-side order/proximity/timing checks, an idempotent result ledger, bank payment and cleanup on cancellation, death, disconnect or resource shutdown. Its map placement, door coordinates, animation and driving feel still need a real-client pass.

### 3. Racing — first playable slice implemented, client validation pending

Airport Dash provides the first curated point-to-point route. Solo mode locks the current vehicle for a three-second start and records a time-trial leaderboard. Public mode queues 2–8 nearby drivers, locks the lobby after ten seconds, places cars into queue-ordered grid slots in an isolated match bucket, synchronizes a five-second start, ghosts racers against each other for the first three seconds, records server-side finish order and pays $1,000/$750/$600 for the first three places and $500 for later finishers. Cancelling during staging restores the vehicle's original position. Both modes validate the same driver and vehicle at every ordered checkpoint and restore routing on finish, cancellation, death or disconnect. Class-specific vehicles and player route creation wait until this first multiplayer flow is client-validated.

### 4. Team deathmatch — first playable slice implemented, client validation pending

Terminal Clash queues 2–10 players outside Maze Bank Arena, assigns balanced red and blue teams, and moves them to an isolated Terminal arena. The first team to 15 validated enemy kills wins. Direct match weapons and armor are temporary, inventory access is locked during play, deaths respawn after four seconds, and persistent inventory is never modified. Results and payouts are recorded once per participant; winners receive $1,200 and losers $600. Suicides and friendly kills do not score, duplicate death events are ignored, and a team becoming empty cancels the match without rewards. Finish, forfeit, disconnect, character unload and resource shutdown restore routing and freemode state.

### 5. Cops and robbers — first playable slice implemented, client validation pending

City Escape queues 2–6 players on foot at Mission Row. The first queued player becomes the wanted robber with a temporary Sultan; the others become police with temporary cruisers. The robber has five minutes to drive the assigned vehicle through five server-validated checkpoints. Police win by killing the robber, destroying the getaway vehicle or running out the clock, while police deaths respawn with a replacement cruiser after five seconds. Both teams receive temporary pistols and armor, one-time match results and $1,500/$700 winner/loser payouts. An empty team cancels without rewards. Finish, cancellation, disconnect, character unload and resource shutdown remove activity vehicles and restore routing, controls, health, armor and the prior wanted level. Police roleplay jobs remain separate from this match mode.

## Interface direction

Use game-native scaleform and menus where they fit moment-to-moment play, and focused NUI surfaces for rich content such as onboarding, activity browsing, rules and a searchable handbook. Keep the pause map useful by adding only stable destinations; move dense or temporary activity listings into the activity browser.
