# GHCR publication and updates

The Pelican egg defaults to:

```text
ghcr.io/vrrdnt/open-freemode:legacy-dev
```

The GitHub Actions **Foundation checks** workflow can publish this tag only from `main` through a manually dispatched run with **publish** enabled. It first runs tests and the repository history secret scan, publishes an immutable `sha-<commit>` tag, verifies an anonymous pull by digest, and then updates `legacy-dev`.

## First installation

Import the checked-in egg. A public GHCR package needs no node-side credentials. If the package is private, configure a read-only GHCR credential for Wings before creating the server.

## Controlled update

1. Open the successful publication run and copy the reported `ghcr.io/...@sha256:...` digest.
2. Generate an egg that names that digest:

   ```powershell
   npm run egg -- ghcr.io/vrrdnt/open-freemode@sha256:REPLACE_WITH_DIGEST
   ```

3. Update the egg/image selection in Pelican during a maintenance window.
4. Back up the database and persistent server volume as one matched set.
5. Pull/reinstall the server image, then start it and watch for the readiness line.
6. Run the client smoke test from [install.md](install.md).

The floating `legacy-dev` tag is convenient for a test server. Pin a digest for any lasting public deployment so a restart cannot silently select a different release.
