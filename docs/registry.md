# GitHub Container Registry

The operator image is published privately as `ghcr.io/vrrdnt/open-freemode`. It includes the pinned Enhanced runtime and requires no node-side build. Source remains public; private image access does not grant third-party redistribution rights.

## Publish an update

In GitHub Actions, run **Foundation checks** on `main` with **publish** selected, or use:

```sh
gh workflow run foundation.yml --ref main -f publish=true
```

Ordinary pushes and pull requests only test. Explicit publication requires the foundation tests and secret scan to pass. The publishing job tests its exact image before uploading, verifies private package visibility and a registry pull, then updates `:dev`. It uses GitHub's temporary workflow token; no personal registry password belongs in repository secrets.

Each publication produces `:sha-FULL_SOURCE_COMMIT` and records the image digest in the workflow summary. `:dev` tracks the most recently completed publication. Tags can move on a repeated build; use `ghcr.io/vrrdnt/open-freemode@sha256:...` from the successful run for an exact deployment.

## Give Wings read access

Create a GitHub personal access token **classic** with `read:packages` for an account allowed to read this package. Keep it private. Merge the following into the existing `docker` section of `/etc/pelican/config.yml`, preserving other settings:

```yaml
docker:
  registries:
    ghcr.io:
      username: YOUR_GITHUB_USERNAME
      password: YOUR_READ_PACKAGES_TOKEN
```

Apply the Wings configuration using the node's normal service procedure. This credential is for Wings image pulls, not a FiveM startup variable. A Docker CLI login by itself does not establish that Wings has the required registry configuration. See [Pelican private registries](https://pelican.dev/docs/wings/optional-config/#private-registries) and [GitHub registry authentication](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-with-a-personal-access-token-classic).

The included egg uses `ghcr.io/vrrdnt/open-freemode:dev` for both installation and runtime. For a pinned deployment, generate an egg using the published digest:

```sh
npm ci --ignore-scripts
npm run egg -- ghcr.io/vrrdnt/open-freemode@sha256:YOUR_PUBLISHED_DIGEST
```

Node is needed only to generate this JSON if changing the reference; the pre-generated egg can be imported directly. The server node only pulls the container image.

## Update an existing deployment

Stop the staging game, take matched SQL/file backups, and record the old image digest. Select the new image in Pelican. Also update the egg's installer image when changing a pinned reference.

The launcher intentionally refuses resource files from another image. Move the old `server-data/resources` directory into a backup location outside that directory, then reinstall/start to seed the new image's resources. Preserve configuration and the database. This is the existing resource update procedure from the [development runbook](development.md#persistent-files-and-resource-updates); pulling a new tag alone is not sufficient when resources changed.

Verify database readiness, client spawn/reconnect and Pelican stop/start on staging before using the update publicly. Rolling back an image does not downgrade a database schema; follow release-specific migration guidance.
