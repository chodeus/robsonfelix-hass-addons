# Claude Code Instructions

This file contains instructions for Claude Code when working on this repository.

## Before Every Commit

**IMPORTANT:** Update `claudecode/CHANGELOG.md` with the changes being committed before making any commit. Follow the existing format:

```markdown
## [VERSION] - YYYY-MM-DD

### Added/Changed/Fixed
- Description of change
```

## Project Structure

- `repository.yaml` - Add-on repository metadata
- `renovate.json` - Dependency automation (regex manager reads `build.yaml` `build_from`)
- `.github/workflows/builder.yaml` - Lints + publishes GHCR images. Its three jobs
  (`Lint add-on`, `Build amd64`, `Build aarch64`) are the required status checks on `main`,
  so the `pull_request` trigger must stay **unfiltered** — a path-filtered workflow never
  reports a required context and leaves such PRs blocked forever. The `push` trigger keeps
  its path filter, because that one publishes to GHCR. Don't rename these jobs without
  re-registering the branch-protection contexts.
- `claudecode/` - Claude Code add-on
  - `config.yaml` - Add-on configuration (bump version here)
  - `Dockerfile` - Container build instructions
  - `build.yaml` - Multi-architecture build settings
  - `run.sh` - Startup script (copied to `/usr/local/bin/start-addon.sh`)
  - `rootfs/` - Files COPY'd into the image (dotfiles, ttyd page snippets)
  - `translations/` - Config UI strings; en/es/fr/pt-BR must stay key-identical
  - `README.md` - User documentation (rendered as the add-on's Documentation tab)
  - `CHANGELOG.md` - Version history (**update before commits**)
  - `apparmor.txt` - Security profile
- `playwright-browser/` - Optional headless Chromium add-on (own `config.yaml`/`CHANGELOG.md`;
  not built by CI — users build it locally)

## Version Bumping

When making changes that require a new release:
1. Update version in `claudecode/config.yaml`
2. Add entry to `claudecode/CHANGELOG.md`
3. Commit and push

## Home Assistant Add-on Notes

- Rebuild button only rebuilds from cached config
- To pick up config.yaml changes: uninstall/reinstall or bump version and update
- Base images use s6-overlay v3 - be careful with init configuration
- `init: true` uses Docker's tini, `init: false` uses s6-overlay's /init
- **`build_from` must be a two-segment image path.** The Supervisor validates it against
  `^([a-zA-Z\-\.:\d{}]+/)*?([\-\w{}]+)/([\-\w{}]+)(:[\.\-\w{}]+)?$`, so `ghcr.io/home-assistant/base`
  passes but a single-segment repo like `mcr.microsoft.com/playwright` does **not**. On a rejected
  value the Supervisor logs one warning and silently substitutes `ghcr.io/home-assistant/base:latest`
  — the build then fails much later on a distro mismatch (e.g. `apt-get: not found` on Alpine).
  Hardcode `FROM` in the Dockerfile for such images instead of using `build.yaml`.
- **`home-assistant/builder` cannot be SHA-pinned.** It builds its image reference from its own
  ref (`github.action_path`'s last segment) and then pulls
  `ghcr.io/home-assistant/<arch>-builder:<that ref>`. Pinned to a digest it pulls
  `...-builder:<sha>`, which isn't a published tag, and the build dies on `manifest unknown`.
  Keep it on a version tag; `renovate.json` has a `pinDigests: false` rule so Renovate
  stops proposing the pin. Every other action in the workflow is SHA-pinned and should stay so.
