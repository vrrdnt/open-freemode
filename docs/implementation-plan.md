# Implementation plan and dependency decisions

Status: foundation development, 5 September 2026. The [development runbook](development.md) records implemented behavior and local evidence. P0 remains incomplete until real Enhanced/Pelican and recovery gates pass. The work packages below remain the full backlog.

Implementation decisions superseding the original proposal below: use mysql2 with structured options; run FXServer directly under Pelican while embedded txAdmin compatibility is deferred; copy and verify real resource files rather than using symlinks. The pinned runtime, driver, local tests and remaining live checks are recorded in the runbook. The following oxmysql evaluation is retained as decision context, not as the installed driver.

## First implementation approach

Use a small custom Lua gamemode for the game rules and native presentation where suitable, adding bundled HTML/CSS/JavaScript NUI only where the interaction needs it. Cfx documents Lua 5.4 and separate client/server resource scripts. Start with one core resource and split vehicle/activity code as those systems become substantial. Do not introduce a separate web application server for the in-game UI. [Cfx resource manifests](https://docs.fivem.net/docs/scripting-reference/resource-manifest/)

A full RP framework is not the default: its money, inventories, character assumptions and job rules would first need reconciling with the selected GTA Online behavior. This is an architectural choice, not a claim that a particular framework cannot run on Enhanced. Reuse a library when it saves work without adding unwanted gameplay; do not rebuild general database access simply to avoid dependencies.

Evaluate **Overextended's oxmysql first** for SQL access. At inspection, `overextended/oxmysql` is not archived and `CommunityOx/oxmysql` is archived; neither status establishes maintenance quality. The inspected Overextended source targets Node 22, generates its resource manifest during the build, and includes a connection-bound transaction callback. None of that proves Enhanced runtime compatibility. [Inspected build](https://github.com/overextended/oxmysql/blob/030d3bda11098fc4a78f1940545b674c374daa45/build.js), [transaction implementation](https://github.com/overextended/oxmysql/blob/030d3bda11098fc4a78f1940545b674c374daa45/src/database/startTransaction.ts), [repository status](https://github.com/overextended/oxmysql), [archived fork](https://github.com/CommunityOx/oxmysql)

Keep this as a candidate until the selected release passes: build from pinned source/lockfiles, Enhanced load, parameterized read/write, transaction rollback, concurrent purchase/claim tests, disconnect after commit, special-character credentials, and failure-log review. Preserve its LGPL terms and notices separately from our MIT material. Also review its optional external logging/update behavior before packaging. Exact artifact and driver release pins follow the test, rather than being presented here as known-compatible versions.

For money operations, an SQL statement that affects zero rows can be a successful query but a failed purchase. A transaction API returning success is therefore insufficient: a debit that finds insufficient funds must prevent the ownership insert. Check the business condition within the same transaction/connection, and reject the entire operation when it fails. The same applies to a starter grant or inventory claim that was already consumed.

Character appearance, phone/menus, voice and interiors need individual Enhanced checks. First prove native appearance persistence and the phone/menu interactions required by the opening. Choose additional resources only when a concrete requirement needs them. Cfx's Enhanced changes include different voice/networking behavior and unavailable Asset Escrow; names containing “enhanced” do not establish platform support. [Enhanced changes](https://docs.fivem.net/docs/developers/legacy-vs-enhanced/)

## Work packages

These are implementation tasks for the agreed design. Their tests are future acceptance requirements, not completed work in the documentation repository.

| ID | Work | Depends on | Done when |
|---|---|---|---|
| P0-A | Record supported host/artifact inputs and distribution route | Operator version/architecture information; current Cfx artifact/terms | Exact Panel/Wings, Linux/architecture, SQL and artifact candidates recorded without private topology; embedding or operator retrieval route resolved |
| P0-B | Implement image, egg and launcher | P0-A; [deployment specification](pelican-deployment-spec.md) | Fixed startup, initial setup, ports, persistence, secrets and graceful-stop tests pass locally and on a disposable Pelican server |
| P0-C | Test/select SQL driver and implement profile storage/migrations | P0-B | Driver gates above pass; real Enhanced client profile survives restart and replacement; no production data used |
| P0-D | Prove update, restore and independent installation | P0-C | All DEP acceptance rows have actual evidence; another deployment works from public release instructions |
| P1-A | Capture classic opening and first-loop reference rules | [Reference records](first-player-experience.md#reference-capture-required-before-gameplay-coding) | Starting state, character boundaries, tutorial, first catalogue and activities have dated evidence; unknown numeric defaults resolved before their features ship |
| P1-B | Implement characters, tutorial state and authoritative economy | P0-C, P1-A | Correct character/financial boundaries; rewards and purchases settle once across retry/concurrency/restart; both control methods work |
| P2-A | Implement complete freemode/vehicle/activity loop | P1-B | Full walkthrough in the first-player specification passes with multiple players; NPC police and vehicle services work at reference rules |
| RELEASE-A | Prepare clean public economy and operational launch | P0-D, P2-A | Fresh production start; test grants absent; multiplayer/load/moderation/recovery gates pass; available-content statement is accurate |
| P3-6 | Expand property/social/business/heist/current-content coverage | Applicable preceding systems | Each main-design phase's fidelity and recovery gates pass; remaining catalogue stays visible |

P1-A reference work can run alongside foundation work. Classic onboarding allows the first public phase to precede the business phases, while those businesses remain part of the full catalogue. Reference capture and foundation testing both contribute to the public release.

## Decisions that require execution evidence

| Question | How to resolve it | Boundary until resolved |
|---|---|---|
| Which Enhanced artifact works with the image/layout and selected libraries? | Pin a candidate and execute DEP-01/04/05 and driver checks | No compatible image or resource claim |
| Which database version/privileges are supported? | Inspect allocated database account, run migrations and concurrency/recovery tests | Pelican's broad MySQL/MariaDB support is not our tested support matrix |
| What does the node actually provide? | Operator supplies installed versions, architecture, available storage and allocations privately | No capacity promise based on a screenshot or “scalable” CPU/RAM |
| What are exact classic starter amounts and current first-loop rates? | Complete reference records, separating historical onboarding from current economics | No arbitrary balances, free assets or flat replacement payouts |
| Which authored content/presentation can the public project distribute? | Apply the main design's specific content review to each selected activity/asset | Source availability is not a license to redistribute someone else's work |

## Release outputs

Every deployable release ships public source, documented build inputs, the image distribution route, importable egg, migrations, generic operator instructions, release notes and its acceptance record. Publish original work through the existing repository and [publication checks](reproducibility.md#publication-checks). Private test/deployment records may establish the original operator's result, but public reproduction must not require those records or their credentials.

The repository contains the architecture, first-player specification, deployment contract and initial foundation implementation. Current in-game reference capture, host inspection and completion of the live acceptance gates remain outstanding. Passing local foundation tests must never be described as a verified public server deployment.
