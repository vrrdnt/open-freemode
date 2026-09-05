# Reproducibility and publication plan

Status: release design contract. An operator-buildable foundation now exists; see the [development runbook](development.md). No authenticated Enhanced/Pelican deployment or public production release has been certified. Embedded txAdmin is deferred; the current launcher runs FXServer directly.

## What belongs in the public repository

Publish all original resources and interfaces, Dockerfiles and launcher scripts, the custom Pelican egg, versioned schema migrations, non-sensitive default configuration, dependency references, build instructions, test fixtures, and release notes. Include the source needed to reproduce our own code and the deployment package without access to the original operator's infrastructure.

Keep exact dependency versions, upstream locations, licenses, checksums where supplied, and any local changes in the release record. Preserve attribution when modifying existing resources or an upstream egg. Do not copy paid resources, escrow payloads, or game data into a public repository or container registry merely because the running server can access them.

## Source and runtime packaging

The published application image contains our resources and dependencies. The launcher retrieves the checksum-pinned FXServer artifact directly from Cfx on first start and reuses a persistent cache. Cfx and txAdmin binaries are not redistributed in GHCR layers. This keeps one game container without requiring node-side builds. Our complete build/download definitions remain public.

The first image will target Linux amd64 and FiveM Enhanced. Pin the application release, dependencies, and verified upstream artifacts. A reproducible build means another operator can resolve the declared inputs and obtain the tested package; do not claim byte-for-byte deterministic images until that has also been verified.

Operators supply runtime identity and credentials independently. A public image must not contain an operator's hostname, license key, database credentials, txAdmin account data, backups, or player records. Keep immutable application files outside the persistent mount and make the documented configuration contract the supported customization surface.

## Settings contract

The example file describes the implemented launcher fields. Secrets are empty and hostnames use reserved example domains. Real configuration belongs in ignored files or private Pelican settings. The generated egg exposes private settings; Pelican does not automatically import a standalone `.env` file.

The game receives credentials scoped to its allocated database. It does not receive Pelican administrator credentials or the Database Host provisioning account. Use separate database users, database names, txAdmin directories and ports for staging and production.

Hiding a Pelican variable does not prevent a sufficiently privileged server operator from reading the environment. Limit subuser access and keep the trust model documented.

## Publication checks

Before each push:

1. Inspect the complete staged diff and new file list. Confirm examples contain placeholders and documentation/screenshots do not reveal private hostnames, local paths, topology or player information.
2. Run Gitleaks against the working files and Git history, with redaction enabled. Check every finding. A scanner does not detect all sensitive information and does not replace the review above.
3. Verify the requested change with appropriate checks. For implementation, include the affected runtime behavior; for documentation, verify sources and internal links.
4. Commit only the intended files. If a credential was accidentally committed, remove it from the pending history and rotate it if it may have been exposed before publishing.

CI repeats the history scan on pushes and pull requests. CI executes after publication, so it supplements the local review and scan. The workflow uses read-only repository permissions and a pinned, checksum-verified scanner. Do not store real deployment credentials in this repository's test fixtures or CI outputs.

## Release evidence

Every deployable release should identify:

- Source commit, image digest, egg version and supported Panel/Wings versions actually tested.
- Enhanced artifact, game-content baseline and selected resource/dependency versions.
- Required database version/schema and supported upgrade paths.
- Which gameplay features are implemented, which are tested, and which remain planned.
- Clean installation, upgrade, restart and restore evidence from an operator-like environment.

The key reproducibility test is a fresh deployment on a separate Pelican server using only public instructions and newly supplied operator settings. It must not depend on a private database dump, an unpublished resource, an existing txAdmin session or a hard-coded original-node path.

Release publication should use least-privilege CI permissions. Image publishing, when implemented, should occur only for explicitly selected releases. Normal CI should not connect to a production server.

## Planned operator experience

An operator can import the egg, select the published application image, allocate the game port, provision a dedicated database and enter their own settings. The foundation initializes an empty deployment and preserves its account data on replacement. txAdmin is deferred. Installed Pelican behavior still requires operator verification; see the registry and development runbooks.
