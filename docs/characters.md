# Character creation test release

6 September 2026. This release adds two saved character slots and an initial native appearance editor. It is a tester milestone, not the completed GTA Online creator or tutorial.

## Included behavior

- Every connection opens character selection. An account has two independently saved slots.
- Empty slots open a preview with male/female freemode models, base heritage parents, resemblance/skin blend, 20 facial features, base hairstyles, hair colors/highlights and eye color.
- Creation requires a separate save confirmation. Backing out before confirmation writes nothing. After saving, select that character to enter the temporary airport spawn.
- Saving an occupied slot returns its existing character. Repeated confirmations and a lost save response cannot overwrite it or create another character in that slot.
- Selection reads only the admitted account's characters. The client supplies a slot, never an account ID. The server keeps each selecting player in a separate routing bucket with population disabled, returning to freemode after selection.
- No money, RP, assets or tutorial completion are awarded by creation. Existing test accounts gain two empty slots on upgrade.

The controls use the game's frontend bindings: arrow keys / controller D-pad to browse and change, Enter / A to select, Backspace / B to go back (default bindings). On-screen prompts follow the active device. Reconnect to select the other slot in this release.

Not yet included: the full heritage/cosmetic/clothing catalogue, character naming/deletion, post-creation appearance changes, mouse pointing, the original lineup scene, tutorial, finances or second-character rank copying. Default clothing is temporary. The editor's numeric IDs and native styling are development presentation, not a claim of exact GTA Online UI fidelity. Both real keyboard and controller use and Enhanced visual results still require an operator test.

## Reference record CHAR-01

Sources checked 6 September 2026; source evidence rather than a captured GTA Online playthrough. Rockstar's character-management article, updated 18 June 2025, explicitly covers PC Enhanced and two character slots. Its appearance article, updated 20 April 2024, establishes that sex is fixed after creation and distinguishes later appearance changes. It predates PC Enhanced, so current fees and the complete Enhanced creator catalogue remain unverified. [Character management](https://support.rockstargames.com/articles/3BqkY8ZYieMTTgdKmSez7U/how-to-delete-characters-in-grand-theft-auto-online), [Appearance changes](https://support.rockstargames.com/articles/6vinToa2yR1WxY2tEgwRTd/appearance-and-gender-changes-in-gta-online).

Implementation uses Cfx's documented [head blend](https://github.com/citizenfx/natives/blob/master/PED/SetPedHeadBlendData.md), [20 facial feature controls](https://github.com/citizenfx/natives/blob/master/PED/SetPedFaceFeature.md) and [frontend inputs](https://docs.fivem.net/docs/game-references/controls/). The version-1 appearance format limits selection to base parents and hairstyles; these are bounded test inputs, not a verified complete catalogue. It stores no financial fields, so ACCOUNT-01's unresolved shared-bank and rank-copy rules are still open.

## Upgrade an existing Pelican test server

No database import or rebuild on the node is required. Use the published image and egg from this release's handoff.

1. Stop the game in Pelican. Record the current image digest. Keep a matched copy of its SQL and files for rollback; this is a precaution for an existing installation, not an installation input.
2. Import this release's egg (or update the existing egg) and assign it to the server. Retain the existing allocation, limits, startup values, database and tester authorization. The new egg expects `Schema 2 ready.`.
3. Select the new published image. For a pinned egg, both the runtime and installer image fields must use its digest. Confirm the existing server itself uses the new image; changing only the egg's defaults may not change it.
4. In the file manager, rename `server-data/resources` to `server-data/resources-before-characters`. Use a different suffix if that name already exists. Preserve this old directory, `config`, `runtime`, and the database.
5. Start the server. The launcher copies its bundled resources into a new `server-data/resources`. The database adds `ofm_characters` and advances schema 1 to 2 automatically, preserving account IDs and tester access. No reinstall or manual SQL command is needed.
6. Wait for `[ofm_db] Schema 2 ready.`, then run `ofm_status` in the console. Connect and follow the test below.

A failed or interrupted schema-1 upgrade retries on start. An incomplete initial schema-0 installation still requires the documented migration investigation/resume path. Schema 2 is rejected by the older foundation image; rolling back requires restoring the matched pre-upgrade SQL/files together with that image. Do not manually lower the version marker.

For a brand-new server, follow [fresh installation](install.md). Its empty database initializes directly to schema 2. Do not use the upgrade steps to import someone else's data.

## In-game acceptance check

1. Connect with an authorized tester. Expect two empty slots for an existing foundation account.
2. Open slot 1, change appearance, then cancel back to selection. Reconnect: the slot should still be empty.
3. Create slot 1, vary heritage, at least one facial feature, hair and eye color, and confirm the save. Select it and verify the airport spawn, normal movement, normal camera and visible appearance.
4. Reconnect. Confirm slot 1's appearance is unchanged. Create a different character in slot 2 and enter with it.
5. Stop/start through Pelican, reconnect, and select each saved slot. Both must retain their own appearance and character ID from the client log.
6. Repeat navigation with a controller. With a second tester, confirm their slots are empty and creators cannot see/interact with each other. Verify normal visibility after both select characters.

Local automation covers input validation, concurrent slot creation, retry preservation, account isolation, schema upgrade/retry, database persistence, admission and menu state transitions. Mocked client natives do not prove the actual camera, assets, input prompts or controller behavior; record those results from this walkthrough before calling the milestone playable.
