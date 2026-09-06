# Third-party resources

The container downloads the following resources from their upstream releases or source repositories during the image build. Exact URLs, revisions and SHA-256 checksums are authoritative in `resources.lock.json`.

| Resource | Project | Included license/notice |
| --- | --- | --- |
| qbx_core | Qbox Project | GPL-3.0-or-later |
| qbx_vehicles | Qbox Project | GPL-3.0 |
| ox_lib | Overextended | LGPL-3.0 |
| ox_inventory | Overextended | GPL-3.0 |
| oxmysql | Overextended | LGPL-3.0 |
| Illenium Appearance | iLLeniumStudios | MIT; upstream tag license restored by the local overlay |
| pma-voice | AvarianKnight | MIT |
| vMenu | Tom Grobbe / Vespura | Upstream custom notice in `LICENSE.md` |
| Cfx server data resources | CitizenFX | Notices retained from the pinned source and runtime packages |

Each bundled resource remains a separate FiveM resource. Its upstream files and license text are preserved in the built image. Open Freemode's MIT license applies only to original repository material and does not replace these terms.

The Cfx FXServer executable is not redistributed in the image. The build extracts the compiled stock chat resource from the exact pinned runtime artifact; the launcher later downloads that same artifact from the official Cfx runtime service on first start and verifies it against `runtime.lock.json`.
