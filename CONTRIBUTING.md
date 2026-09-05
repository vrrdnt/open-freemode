# Contributing

The project is developing its server foundation. Keep proposals aligned with current GTA Online behavior, normal economy/unlock rules, Enhanced-first compatibility, and reproducible Pelican deployment.

- Make the smallest change that serves the requested behavior. Explain assumptions and record departures from the reference experience.
- Include dated reference evidence for prices, rewards and prerequisites. Mark unknown values rather than inventing them.
- Reuse suitable dependencies after checking compatibility and licensing. Preserve original attribution; do not publish proprietary or purchased assets.
- Keep production credentials, deployment hostnames, screenshots, player data and backups out of commits. Follow the [publication checks](docs/reproducibility.md).
- Test meaningful failure and concurrency cases when implementing persistence or lifecycle behavior. Passing static checks does not prove a working server.
- Document fresh-install and upgrade behavior whenever changing an egg, image, startup script or migration.

Before publishing, install the pinned Gitleaks version used in CI and run these commands from the repository root:

```sh
gitleaks dir --redact --no-banner .
gitleaks git --redact --no-banner --log-opts="--all" .
git diff --check
git diff --cached
```

Original contributions are provided under the repository's MIT License. Identify third-party material and its applicable license explicitly.
