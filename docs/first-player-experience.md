# First player experience and public release scope

Status: design, updated 5 September 2026. No gameplay in this document is implemented. This specification extends the [server design](design.md).

## Selected experience

Use **classic GTA Online onboarding on the Enhanced client**, followed by current, ordinary prices, payouts, and unlocks. A newcomer builds up through the tutorial and earned progression. Do not grant a Career Builder budget, a starter business/property portfolio, or purchased starter-pack benefits.

This is an intentional difference from current Enhanced onboarding. Rockstar describes Career Builder as a one-time setup budget and career selection; we are not reproducing that opening. Its four business families remain in the long-term feature scope and are acquired through normal progression. They are not all prerequisites for the first public release. [Current Enhanced opening](https://support.rockstargames.com/articles/1UfYjMN0NnpJcoC5DLZkf4/gta-online-career-builder-overview)

“Starting with nothing” describes the progression, not a verified starting balance of GTA$0. Rockstar's January 2021 starter guide says the tutorial yields cash, rank progress, and a personal vehicle. That historical guide is evidence for the classic opening, not evidence for current reward amounts. Verify the starting cash, equipment, individual rewards, and vehicle rules before fixing numeric defaults. [Classic starter guide](https://www.rockstargames.com/newswire/article/o349k5525534k7/gta-online-starter-tips)

**Test progression resets before the lasting public economy starts.** Test accounts, starter eligibility, purchases, rewards and tutorial completion must not carry over. Announce this before testers create characters. Prepare production with a fresh game database and separate persistent volume; do not make deleting a running test database the launch procedure. Moderation records and operator access are separate decisions, not economy migration inputs.

## Account and character boundaries

Support two character slots per server account; Rockstar documents two characters and an explicit deletion confirmation. Use a comparable deliberate confirmation in our interface. [Character management](https://support.rockstargames.com/articles/3BqkY8ZYieMTTgdKmSez7U/how-to-delete-characters-in-grand-theft-auto-online)

Create an internal account ID from a server-verified game identity. Never key ownership by display name, IP address, client-provided account ID, or transient FiveM player source. The exact Enhanced identifier to bind is a foundation-test decision. Prevent concurrent active sessions for the same account, so two connections cannot act as the same character. These are our implementation rules, not claims about Rockstar's account backend.

Separate account-scoped records from character-scoped records. Appearance, tutorial checkpoints and personal ownership belong to a character. The precise cash/bank sharing rules, second-character rank-copy offer, and effects of deletion on shared balances require reference observation before schema approval. Do not copy a typical RP framework's per-character bank model without checking it. Deleting a character must not delete other characters or erase account-level claim/audit records.

## Playthrough specification

The ordered steps below describe the intended complete opening. Exact mission names, dialogue, scene presentation and numeric rewards need the reference capture below and the content review already described in the main design.

| Step | Player experience | Durable result / completion evidence |
|---|---|---|
| Connect | See the actual release's availability and, during testing, its reset policy; join using Enhanced | Authentication binds the correct account; maintenance or incompatible state prevents joining gameplay |
| Choose or create | Select one of two characters; create and preview appearance with keyboard/mouse or controller | Reconnecting loads the same character and appearance; no accidental duplicate slot |
| Begin the opening | Enter the classic newcomer/tutorial sequence, without Career Builder purchases | Starting state comes from the dated reference; no business or promotional grant |
| Learn and earn | Complete the introductory driving/combat/service lessons in their verified order | Each objective and reward advances once; failure, retry and reconnect resume at the appropriate point |
| Obtain the first personal vehicle | Follow the tutorial's eligible-vehicle and ownership steps | Ownership, tracker/insurance where applicable, and customization survive a restart |
| Enter freemode | Use the map, phone, interaction menu and weapon wheel; encounter traffic, pedestrians and NPC police | Tutorial completion persists; legitimate wanted/respawn behavior does not lose owned progression |
| Complete a repeatable activity | Accept and finish a contact mission; enter and finish a race with another player | Correct prerequisites and reference reward calculation; repeat delivery cannot pay twice |
| Make a purchase | Earn enough for a released vehicle or garage and buy it through the appropriate interface | Server commits charge and ownership together; insufficient funds cannot create an asset |
| Return later | Store/retrieve a vehicle, reconnect, and repeat after a server restart | Stored modifications and money agree with SQL; retrieval does not duplicate the vehicle |

Tutorial skips and second-character shortcuts are not automatically free-reward buttons. Observe the reference outcome before implementing each path. Canceling creation before a grant commits must leave no owned assets. If the connection fails after a committed reward, reconnecting resolves the existing operation rather than rewarding again.

Purchased vehicles and eligible stolen vehicles need distinct ownership/insurance paths. Rockstar's current vehicle guide describes insurance with purchased vehicles, loss/theft protection for stolen vehicles, and delivery/claim services. It does not establish every eligibility rule or fee; capture those separately. [Vehicle services](https://www.rockstargames.com/gta-online/guides/333k)

## Reference capture required before gameplay coding

Keep reference evidence in small, reviewable records. Each record needs an ID, edition/build, observation date, source or sanitized observation notes, prerequisites, ordinary value/formula, rounding, result, and uncertainty. An unobserved value is **unknown**, never zero. An old article can establish historical behavior without establishing today's price.

| Record | Required observation | Current evidence |
|---|---|---|
| START-01 | Initial cash/bank, rank/RP, clothes, weapons/ammunition before the first tutorial reward | Unknown numeric state; classic opening selected |
| START-02 | Tutorial stages, sequence, failure/restart/skip outcomes and each cash/RP reward | Historical official guide establishes rewards and a personal vehicle, not amounts |
| START-03 | Eligible first vehicles, tracker/insurance, customization and storage before owning a garage | Broad current vehicle-service behavior documented; tutorial-specific rules unknown |
| ACCOUNT-01 | Shared bank vs character cash, second slot creation, rank copy and deletion effects | Two slots documented; detailed financial behavior unverified |
| SHOP-01 | First release vehicle/garage catalogue, normal prices, trade prices, prerequisites and capacity | Capture required; no substitute prices selected |
| SHOP-02 | Weapon/ammo/armor and vehicle-modification prices and rank requirements | Capture required |
| ACTIVITY-01 | First contact mission: eligibility, objectives, participants, difficulty, timing, failure and reward formula | Mission selection and complete capture required |
| ACTIVITY-02 | First race: course, class/settings, checkpoints, finish/DNF, participants and payout/RP formula | Race selection and complete capture required |
| WORLD-01 | Wanted escalation/escape, death/respawn fees and losses, passive-mode restrictions | Capture required |
| SERVICE-01 | Delivery cooldowns, vehicle loss, insurance and impound rules/fees | Service existence documented; exact rules require capture |

Use a clean reference character and separate experiments where one action changes later eligibility. Record actual payouts before and after a known action and the applicable event status. Never infer ordinary rates from a promotional week. Keep account names, identifiers, chats and credentials out of published evidence. Record gaps and differences instead of claiming a reconstructed mission is exact based only on a similar objective.

## First public release gate

Public launch requires the complete opening and earn/buy/store/retrieve loop above, plus the main design's operational gate. Test each path with two or more real clients and both control methods. Verify duplicate confirmations, disconnects after a committed purchase/payout, simultaneous retrieval, insufficient funds, and a restart during an activity. The test should compare durable results as well as what the player sees.

The launch catalogue must contain the items and activities needed to complete the loop, including a reachable route to the first purchasable vehicle/garage at normal rates. Set its exact breadth after the reference capture; do not publish an empty shop, a permanently locked progression step, or a business storefront whose gameplay is absent. This release is an explicitly described phase of the full target, not a claim of full current GTA Online parity.

Later phases add property/social depth, CEO/MC systems, businesses and heists as listed in the main design. Players earn access when each complete system releases. No Career Builder entitlement is held back for a later retroactive grant. Future introduction of any starter benefit would be a separate gameplay decision.

Before launch, rehearse creating the clean production environment and restoring its first backup. Disable synthetic test grants and debug rewards in the public release, and verify that a new production account starts from the selected classic baseline. The reset decision does not promise that production progression will be wiped on subsequent normal updates.
