# Changelog

All notable changes to this project will be documented in this file.

## [0.1.14] - 2026-08-08

### Fixed
- **The add-on could not be built at all — broken since 0.1.11 (2026-02-23).** That release moved the base image from a hardcoded `FROM` into `build.yaml`'s `build_from`. The Supervisor validates `build_from` against `^([a-zA-Z\-\.:\d{}]+/)*?([\-\w{}]+)/([\-\w{}]+)(:[\.\-\w{}]+)?$`, which requires a **two-segment** repo path — `mcr.microsoft.com/playwright` is single-segment, so the value was rejected on every install. The Supervisor logs one warning, silently substitutes `ghcr.io/home-assistant/base:latest` (Alpine), and the build then ran on for several layers before dying on `apt-get: not found`, because Alpine has no apt. The base image is hardcoded in the `Dockerfile` again and `build.yaml` is removed. Verified against the regex as it appears in Supervisor `2025.12.0`, `2026.02.0`, `2026.07.0` and `main` — unchanged in all four

### Changed
- Base image updated to `mcr.microsoft.com/playwright:v1.62.1-noble` (from `v1.61.1-noble`). The tag is multi-arch, so a single `FROM` serves both amd64 and aarch64 — no per-arch table needed
- Renovate now tracks the base image through its native Dockerfile manager instead of the custom `build.yaml` regex manager, which had been dutifully raising bumps against a file the Supervisor never read
- README no longer names a base-image tag inline; it pointed at `v1.50.0-noble`, three releases behind what was actually configured

## [0.1.13] - 2026-05-28

### Changed
- Updated the Dockerfile `maintainer` image label to `chodeus`.

## [0.1.12] - 2026-05-28

### Changed
- Updated the add-on source URL / image label to the current fork (`chodeus`).

## [0.1.11] - 2026-02-23

### Added
- aarch64 (ARM64) architecture support for Raspberry Pi 4/5, ODROID, etc.
- `build.yaml` for multi-architecture builds via HA builder
- Dockerfile now uses `BUILD_FROM` arg pattern (consistent with other add-ons)

## [0.1.10] - 2026-01-15

### Fixed
- Use nginx `sub_filter` to rewrite WebSocket URLs in Chrome's responses
- Chrome returns `ws://localhost/...` which doesn't work across containers
- Now rewrites to `ws://{container-hostname}:{port}/...` for proper cross-container access

## [0.1.9] - 2026-01-15

### Fixed
- Replace `wait -n` with proper process monitoring loop
- Add sleep after nginx start and check both processes every 5 seconds
- Better error reporting (shows which process exited)

## [0.1.8] - 2026-01-15

### Fixed
- Run nginx in foreground mode (`daemon off`) to prevent immediate exit
- Fixes add-on starting then immediately stopping

## [0.1.7] - 2026-01-15

### Fixed
- Use nginx reverse proxy instead of socat
- nginx rewrites Host header to 'localhost' (Chrome v66+ security requirement)
- Fixes "Host header is specified and is not an IP address or localhost" error
- Full WebSocket support with proper upgrade headers

## [0.1.6] - 2026-01-15

### Fixed
- Use socat TCP forwarder to expose CDP port externally
- Chrome ignores all attempts to bind to 0.0.0.0, so we forward port 9222 to Chrome's localhost:9223
- Should definitively fix connection refused errors from other containers

## [0.1.5] - 2026-01-15

### Fixed
- Added `--remote-debugging-bind-to-all-interfaces` flag for newer Chrome versions
- Fixes Chrome ignoring `--remote-debugging-address=0.0.0.0` and binding only to localhost

## [0.1.4] - 2026-01-15

### Changed
- Upgraded to Playwright v1.57.0 (from v1.50.0)

## [0.1.3] - 2026-01-15

### Changed
- Added more Chromium flags to reduce noise from dbus/GCM errors
- Disabled notifications, permissions API, background mode, and other unused features
- Added info message explaining dbus errors are harmless in containerized environments

## [0.1.2] - 2026-01-15

### Fixed
- Reverted to `--headless` (without `=new`) for compatibility
- Added `--remote-allow-origins=*` to allow cross-origin CDP connections
- Removed `about:blank` URL that may have caused early exit
- Added more flags to reduce noise and disable unnecessary features

## [0.1.1] - 2026-01-15

### Fixed
- Hardcode Playwright base image in Dockerfile (HA's build_from regex doesn't support MCR format)
- Removed build.yaml, using direct FROM instruction
- Limited to amd64 architecture for now

## [0.1.0] - 2026-01-15

### Added
- Initial release
- Headless Chromium browser with CDP endpoint
- Based on official Microsoft Playwright Docker image
- Exposes Chrome DevTools Protocol on configurable port
- Designed for use with Claude Code's Playwright MCP
