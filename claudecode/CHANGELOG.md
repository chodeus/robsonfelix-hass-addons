# Changelog

All notable changes to this project will be documented in this file.

## [2.8.0] - 2026-07-15

### Fixed
- **Disabling `session_persistence` or `enable_mcp` is finally honored.** Both were read with `jq -r '.x // true'`, and jq's `//` falls back on `false` as well as `null` — so an explicit `false` from the add-on config resolved back to `true`. tmux always started and ha-mcp was always registered (and its read-only tools pre-authorized) regardless of the toggle. Now read with an explicit `if .x == null then true else .x end`; the false-defaulted options were future-proofed to the same form
- **A hung or broken Claude Code binary no longer blocks the terminal from starting.** Every `claude` call before `exec ttyd` is now wrapped in `timeout`, and MCP setup is gated on a `CLAUDE_OK` smoke test — if the CLI doesn't respond in 30s (e.g. a persisted update that's incompatible with this CPU, which *hangs* rather than crashes) the add-on skips MCP setup and still starts the web terminal so you can debug from inside
- **Auto-update now smoke-tests each release and rolls back a bad one.** Both the startup check and the hourly checker verify the newly-installed `claude` actually runs; on failure they roll back to the previous version (or remove the persisted install so PATH falls back to the build-verified image binary). A known-bad version is remembered so the hourly loop won't reinstall it every hour, and a broken persisted install is now treated as "repair me", not "up to date". `npm` calls are `timeout`-bounded so a registry stall can't wedge startup
- **settings.json is written atomically and can no longer crash-loop the add-on.** The permission/Remote-Control edits write to a temp file in the same directory and rename (no more cross-`/tmp` copy that a SIGKILL could truncate), the empty-file case is reset (`[ -s ]` not `[ -f ]`), and an unparseable settings.json degrades to a warning instead of aborting startup under `set -e`
- **The CLAUDE.md `/memory` file can no longer be wiped** by a transient read error during the import-line prepend (the read is now checked before the file is rewritten, atomically)
- **The hourly update checker survives transient errors** — it runs under `set +e`, so a one-off filesystem/network hiccup no longer silently kills update checks for the container's lifetime
- **CPU pre-flight message corrected**: the current failure mode on an SSE4.2-less CPU (e.g. Proxmox `kvm64`) is a silent 100%-CPU hang, not only a SIGILL crash, and the fix needs a **full VM stop/start** (a guest reboot doesn't repropagate CPU flags). Added an informational note when AVX2 is absent (current Linux builds are Bun *baseline* / SSE4.2-only and run fine, but Anthropic has shipped AVX-requiring builds before). README Requirements + a new Troubleshooting entry updated to match
- **`ha-logs` no longer cats a multi-hundred-MB log** into your session (it tails the last 200 lines) — a large `home-assistant.log` could otherwise consume an entire Claude context window
- **Docker socket access actually works**: added `/run/docker.sock` to the AppArmor profile, so the `docker_api: true` grant + bundled `docker-cli` are usable instead of blocked
- **AppArmor `/usr/local` widened to `ixmr`** so native Python extensions there (ha-mcp's pydantic-core, cryptography) can `mmap(PROT_EXEC)` — robustness parity with `/usr/lib`
- **tmux session pre-created (detached) at startup** so two simultaneous first connections (e.g. phone + desktop) both attach instead of racing `new-session -A`, which left the loser with a "duplicate session" dead pane

### Added
- **Remote Control** (`enable_remote_control`, default off; `remote_control_session_prefix`, default `HomeAssistant`): auto-starts Claude Code's Remote Control bridge so you can view and steer the add-on's session from [claude.ai/code](https://claude.ai/code) or the Claude mobile app. Requires a claude.ai Pro/Max/Team/Enterprise login (API keys unsupported). Off by default with a security note — the add-on runs as root with full host access. Turning it off removes the persisted setting. Ported from upstream `robsonfelix/robsonfelix-hass-addons` (PR #34)
- **Persistent tmux user overrides**: `~/.tmux.conf` now sources `/homeassistant/.claudecode/tmux.conf` last, so your tmux customizations survive add-on rebuilds — e.g. `echo 'set -g mouse off' > /homeassistant/.claudecode/tmux.conf` to restore native browser copy/paste (at the cost of wheel-scrolling Claude's fullscreen buffer)
- **French translation** (`translations/fr.yaml`)
- **`restrict_terminal_port`** (experimental, default off): firewalls the web terminal port (7681) to HA ingress + loopback via iptables, so other add-on containers on the internal hassio network can't reach the root shell (which carries this add-on's Supervisor token). Resolves the ingress source from the `supervisor` hostname (not a hard-coded IP) and **fails open** — never blocks ingress if iptables is unavailable. Off by default because it touches the container firewall; verify the terminal still loads after enabling. Requires the new `iptables` package and AppArmor `/sbin` + `/run/xtables.lock` rules
- **Troubleshooting: recovering from a `bypassPermissions` root lockout** — because settings persist across reinstalls, a saved bypass-permissions mode locks Claude Code out on every launch; the README now documents how to clear it

### Changed
- **Build-time smoke test**: the image build now runs `claude --version` after install and fails the build if it doesn't work, so a broken npm publish can't ship to GHCR (records the verified version in `/etc/claude-code-version`). GH runners have AVX, so this catches non-CPU breakage; CPU-incompatible releases are still handled at runtime
- **Download resilience**: the `ttyd` and Home Assistant CLI downloads use `curl --retry 5 --retry-delay 2 --retry-all-errors`, so a transient network/DNS blip no longer fails the whole build
- **Healthcheck `start-period` raised to 300s**: on a slow host with `auto_update_claude` on, the pre-ttyd path (npm install + smoke test + MCP setup) can take minutes; the old 10s grace let the Supervisor watchdog kill startup mid-`npm install` and leave a half-written binary
- The manual `claude update` / `claude-update` path now smoke-tests the result and prints a rollback command if the new version doesn't run (and `claude-update` reuses the `claude update` wrapper instead of duplicating it)

## [2.7.2] - 2026-07-08

### Fixed
- **Keyboard refit now actually fires inside Home Assistant ingress** (2.7.1's refit worked only when ttyd was opened directly): the on-screen keyboard never resizes the ingress iframe and never fires the iframe's own `visualViewport` events — only the top HA page's visual viewport shrinks. The shim now measures through `window.top` (same origin) and clips the iframe's rect to the top page's visible region, so the terminal — and the key bar — shrink above the keyboard and the line being typed stays visible. Focus changes also trigger delayed re-measures to cover missed viewport events during the keyboard animation

## [2.7.1] - 2026-07-08

### Added
- **Mobile touch shim** (`mobile.html`, injected into ttyd's page like the OSC 52 bridge; touch devices only). xterm.js has no touch support — on a phone the 2.7.0 scrollable terminal wasn't scrollable at all:
  - **One-finger drag scrolls** (with flick momentum): drags are synthesized into wheel events, which tmux/Claude Code already understand; falls back to viewport scrolling when no app owns the mouse
  - **Long-press-then-drag selects and copies**: synthesized into a mouse drag so tmux/Claude do their own selection and OSC 52 copy on release — the standard iOS gesture, minus native handles
  - **Key bar** (`esc` `tab` `⇧tab` arrows `^c` `paste`) for keys iOS keyboards lack — without Esc you couldn't even interrupt Claude; arrows auto-repeat on hold; paste uses the clipboard-permission gesture
  - **Keyboard-aware refit**: ttyd only refits on window `resize`, which the iOS keyboard doesn't fire — a `visualViewport` listener now shrinks the terminal so the prompt stays above the keyboard
  - **Foreground auto-reconnect**: iOS kills the websocket when the app is backgrounded, and ttyd's stock page can sit at "Press ⏎ to Reconnect" (no Enter key in sight). Returning to a dead socket now reloads the page; tmux restores the session in full

### Fixed
- **OSC 52 copy actually lands on the clipboard on iOS**: Safari refuses clipboard writes that don't stem from a user gesture, and the OSC 52 payload arrives over the websocket — copies silently vanished. A "📋 Tap to copy" toast now appears when the direct write fails; the tap supplies the gesture. Desktop behavior unchanged
- Resize overlay (`80×24` flash) disabled — it fired on every phone-keyboard open/close

## [2.7.0] - 2026-07-07

### Changed
- **Terminal overhaul — Claude output is finally scrollable and survives reconnects.** Root causes: Claude Code's classic renderer erases terminal scrollback on every repaint (`CSI 3 J`), and ttyd resets the browser terminal on every ingress reconnect while dtach replays nothing. Fix is a pairing:
  - `session_persistence` now uses **tmux** instead of dtach — tmux fully re-establishes terminal state (alternate screen, mouse, repaint) on reattach, so the session *and its visible history* survive tab closes and connection blips
  - Claude Code now starts in **fullscreen rendering mode** (`CLAUDE_CODE_NO_FLICKER=1`): mouse-wheel scrolling through the whole conversation, `Ctrl+O` searchable transcript, no more scrollback wipes. Opt out per-session with `/tui default`
  - New tmux config: mouse on (required for wheel scrolling in Claude; use Shift+drag for native browser selection), 50,000-line shell history, OSC 52 clipboard passthrough, hidden status bar. The now-unused `dtach` package is removed from the image
  - `.bashrc` no longer overrides `TERM` inside tmux (tmux's `screen-256color` stays authoritative in panes; unchanged outside tmux)
- Removed the redundant `uart: true` permission — `full_access: true` already maps all host devices, including serial
- Removed explicit Supervisor defaults from config.yaml (`startup: application`, `boot: auto`, `init: true`) — required by the add-on linter, no behavior change (`init` still defaults to `true`/tini)
- **OSC 52 clipboard bridge**: ttyd's page is served with a small script that forwards OSC 52 clipboard writes to the browser, so Claude's in-app copy (drag-select, double-click a URL) and tmux yanks actually land in your clipboard; falls back to the stock page if extraction fails
- **Dropped armv7/armhf/i386**: Claude Code ships x64/arm64 binaries only (verified against the npm package), so those arches never actually worked on current versions
- Dockerfile dotfiles (`.bashrc`, `.profile`, `.claude-notify.sh`, new `.tmux.conf`) moved from `RUN` heredocs to a `rootfs/` `COPY` layout (required by the HA builder for pre-built images)
- **Base image bumped to Alpine 3.24** (`base-python:3.13-alpine3.24`) — Alpine 3.21 leaves security support 2026-11-01; 3.24 is the newest HA-published base (supported into 2028). The `yq` apk package was renamed upstream to `yq-go` (same tool, still installs the `yq` binary)
- Auth instructions updated: double-click the sign-in URL inside Claude to copy it whole (Shift+drag + address-bar paste as fallback)

### Added
- **SSE4.2 pre-flight check** (x86-64): warns at startup when the CPU masks SSE4.2 — Claude Code's runtime crashes without it — with explicit Proxmox "set CPU type to `host`" guidance
- **Pre-built images**: new GitHub Actions builder workflow (lint + amd64/aarch64 image build, `--test` on PRs) publishes `ghcr.io/chodeus/claudecode-{arch}`, and `config.yaml` now points at them — installs/updates pull a ready image instead of building for minutes on-device (verified publicly pullable before enabling)
- Hourly update checker's npm queries now run under a 30s timeout, and a failed registry query can no longer abort add-on startup (when auto-update is on) or silently kill the hourly checker — both were latent `set -e` traps
- README Security section now documents the accepted ttyd trust model (no terminal-level login; protected by HA ingress auth, no published host port; reachable by other add-on containers on the internal network)

### Fixed
- **Finish the 2.6.1 "no token at rest" fix**: removed the `update_mcp_token()` bashrc helper — it re-wrote the Supervisor token into backup-included `settings.json` every time `c`/`cc` was used, undoing 2.6.1. A one-time startup scrub now removes any previously persisted `HOMEASSISTANT_TOKEN`/`HASS_TOKEN` from `settings.json`/`.claude.json` — scoped strictly to the add-on's own `homeassistant` MCP server entry, so user-added MCP servers (e.g. one pointing at a remote HA with its own token) are never touched; the MCP server keeps getting the token from env vars only
- **`/memory` edits no longer lost on restart**: the add-on wrote its guidance directly into `~/.claude/CLAUDE.md` (Claude's user-memory file) on every start, clobbering user notes. Guidance now lives in `CLAUDE.addon.md` (refreshed each start) and is pulled in via an `@~/.claude/CLAUDE.addon.md` import; `CLAUDE.md` itself is created once and then left alone
- README drift: `auto_update_claude` default corrected to `false`; update-notification section now describes the actual behavior (notify when auto-update is off, silent install when on); generated guidance no longer claims `/config` doesn't exist (it's the add-on's private config dir)

## [2.6.1] - 2026-07-03

### Changed
- Default `auto_update_claude` to **off** — Claude Code no longer installs `@latest` as root on startup unless you opt in

### Fixed
- Stop persisting the Supervisor manager token into `settings.json` (it otherwise lands in HA backups / config-mapped add-ons); the exported `HOMEASSISTANT_*` env vars already provide the Home Assistant connection

## [2.6.0] - 2026-06-11

### Added
- **Claude Fable 5 added to the model dropdown** — the new top model tier above Opus, in two flavors:
  - `claude-fable-5` — standard 200K context
  - `claude-fable-5[1m]` — same model with the 1M-token context window (Claude Code reads the `[1m]` suffix; availability/pricing depends on the user's plan)
- No `run.sh` changes needed — model handling is data-driven and passes the id straight through to `ANTHROPIC_MODEL`.

### Changed
- **Haiku dropdown entry switched from the dated id `claude-haiku-4-5-20251001` to the alias `claude-haiku-4-5`** (the alias auto-tracks model snapshots). If you had the dated id selected, re-pick Haiku in the add-on config after updating — the old stored value is no longer in the dropdown list.
- README model table and 1M-context notes updated for Fable 5: Fable 5 is now listed as most capable, Opus 4.8 as latest Opus; the `[1m]` explanation covers both models. The Opus 4.8 5× cost-multiplier note is kept as-is (verified in Claude Code's picker); Fable 5's 1M premium is described without a specific multiplier.
- Model option descriptions (en/es/pt-BR translations) updated to reference `claude-fable-5` and the generic `[1m]` variants.

## [2.5.0] - 2026-05-29

### Added
- **Claude Opus 4.8 added to the model dropdown** as the latest, most capable Opus, in two flavors:
  - `claude-opus-4-8` — standard 200K context
  - `claude-opus-4-8[1m]` — same model with the 1M-token context window (Claude Code reads the `[1m]` suffix and enables the extended window; availability/pricing depends on the user's plan)
- Both are selectable directly in the add-on config — no `custom` field needed. The previous entries (`claude-opus-4-7`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`) and `custom` remain. The `run.sh` model handling is data-driven, so each id is passed straight through to `ANTHROPIC_MODEL`.

### Changed
- README model table and the `model_custom` examples (en/pt-BR/es) updated to reference `claude-opus-4-8`.
- README now documents the 1M-context cost caveat (Claude Code flags it with a 5× cost multiplier / draws from usage credits; plan-gated) and clarifies how the `default` option actually resolves — it leaves the model unpinned, so a model previously chosen via `/model` in `~/.claude/settings.json` takes precedence over the account default.

## [2.4.4] - 2026-05-28

### Changed
- Updated the Dockerfile `maintainer` image label to `chodeus` (cosmetic metadata; matches the fork).

## [2.4.3] - 2026-05-28

### Fixed
- Documentation refresh after the 2.3.x–2.4.x changes:
  - The in-container `CLAUDE.md` (Claude's own context) now describes ha-mcp's ~92 tools (read + manage) instead of "query entities and call services", so the agent knows it can create/edit automations, dashboards, etc. via MCP.
  - README Setup now points first-time users to the select-and-copy sign-in instructions (clicking the long OAuth URL doesn't work).
  - `repository.yaml` URL updated to the current fork.

## [2.4.2] - 2026-05-28

### Changed
- **Model selection is a dropdown again** (`default`, the common models, or `custom`), so the everyday choice is typo-proof — fixing the regression in 2.4.0 where a free-text typo would export an invalid `ANTHROPIC_MODEL` and the API would reject every request. Future-proofing is preserved via a new `model_custom` field: choose `custom` and enter any model id (e.g. a newer release) with no add-on update. `default` leaves the model unset (account default + in-session `/model`). If `custom` is chosen but `model_custom` is empty, the add-on falls back to the account default with a warning.

## [2.4.1] - 2026-05-28

### Changed
- **Replaced `hass-mcp` with [`ha-mcp`](https://github.com/homeassistant-ai/ha-mcp)** as the bundled Home Assistant MCP server. ha-mcp is a superset — it still does everything hass-mcp did (search entities, read state, history, logs, call services) and adds ~92 tools for *managing* HA: create/edit automations, scripts, scenes, dashboards, helpers, areas, zones, labels, backups, traces, and more. It connects via the same Supervisor token (`HOMEASSISTANT_URL=http://supervisor/core`), so no new setup is required. The pre-authorized (no-confirmation) tool list now covers ha-mcp's read-only tools; state-changing tools still prompt.
- Raw file / `configuration.yaml` editing tools in ha-mcp are beta and remain **disabled** (they require ha-mcp's companion custom component + feature flags). Claude Code's own file tools still have direct read/write access to `/homeassistant`.

### Notes
- ha-mcp's dependencies (`pydantic-core`, `cryptography`) are Rust-compiled. They install from prebuilt musl wheels on amd64/aarch64; on armv7/armhf/i386 the image build compiles them from source (a temporary Rust toolchain is installed during build), which is slower and may not succeed on every arch. If a build fails on a rare architecture, consider trimming the `arch` list in `config.yaml`.

## [2.4.0] - 2026-05-28

### Changed
- **Model selection is now future-proof.** The `model` option is a free-text field instead of a fixed dropdown. Leave it **empty** (the new default) to use your Claude account/subscription default and switch models in-session with `/model`; set it to any model id (e.g. `claude-opus-4-7`) to pin one. New Anthropic models work the moment Claude Code supports them — no add-on update needed. Previously the option always forced `ANTHROPIC_MODEL`, overriding `/model` and the subscription default, and the hardcoded list went stale on every model release.
- **Auto-update now keeps Claude Code current without a restart.** When `auto_update_claude` is on, the hourly background checker installs new releases as they land (previously it only posted a notification and updates happened solely at startup). Installing into the npm prefix is safe mid-session — a running `claude` keeps the version it loaded, and the next launch picks up the update. With auto-update off, it still just notifies.

### Fixed
- Startup no longer aborts if `claude mcp add-json` fails — the MCP registration calls are guarded so a transient failure logs a warning instead of killing the add-on (`set -e`).
- Made the add-on source URLs consistent (config.yaml, build.yaml, Dockerfile label, README) — they pointed at three different forks.

## [2.3.15] - 2026-05-28

### Changed
- Replaced **tmux** with **dtach** for session persistence. tmux is a full terminal emulator that reflows long lines into separate rows before redrawing; dtach is a thin detach/attach wrapper that passes output straight through to xterm.js. Practical effects: the long OAuth login URL is now a single soft-wrapped line, so **selecting and copying it yields the complete URL in one piece** (under tmux the wrapped rows were hard-split and copied as broken fragments), and native browser copy/paste (mouse-select + Cmd/Ctrl+C, right-click, Cmd/Ctrl+V) works without special key chords. Session persistence is unchanged — sessions still survive browser refresh/disconnect and background tasks keep running. Scrollback is now provided by xterm.js (`scrollback=20000`).
- Note: **clicking** the OAuth URL still does not work for the full link — ttyd's bundled xterm.js underlines the wrapped URL but its click handler only returns the first visible row, truncating it. This is a ttyd/xterm.js limitation, not something the add-on can configure away. Use select-and-copy (now reliable) for first-launch sign-in. See README → Authenticating Claude Code.

### Removed
- The unauthenticated 220-column width hack in the `claude()` wrapper. Its only purpose was keeping the OAuth URL on one line, which never worked (the URL is far longer than 220) and is now obsolete with dtach. The terminal width always follows the browser viewport.

### Fixed
- Documentation: rewrote the stale tmux sections in the README (the removed mouse/copy-mode instructions and the inaccurate "auth URL on a single line" claim), added a "Terminal Basics (copy, paste, scroll)" section, and corrected the sign-in steps to select-and-copy the URL rather than click it — all to reflect dtach and native copy/paste.

## [2.3.14] - 2026-05-28

### Changed
- The interactive terminal now runs **bash** instead of busybox `/bin/sh`. tmux's shell resolved to `/bin/sh` even though the prompt, aliases, and `claude()` wrapper in `.bashrc` are all bash-specific. Added `set -g default-shell /bin/bash` to the tmux config and `export SHELL=/bin/bash` at startup. This makes the colored prompt render correctly (busybox `sh` mishandles bash's `\[ \]` markers), prevents future "works in bash, breaks in sh" issues, and corrects the shell reported to Claude Code (was `/bin/sh`).

## [2.3.13] - 2026-05-28

### Fixed
- `.bashrc` printed `shopt: not found` on every shell open in 2.3.12. The interactive terminal runs busybox `/bin/sh` (not bash), which sources `.bashrc` via `.profile` but has no `shopt` builtin. The `checkwinsize` call is now guarded behind a `[ -n "$BASH_VERSION" ]` check so it only runs under bash.

## [2.3.12] - 2026-05-28

### Fixed
- Terminal rendering was broken on first open (badly wrapped/clipped output) until the tab was closed and reopened. Root cause: the shell force-pinned the PTY to a fixed 220 columns (`stty cols 220`, `COLUMNS=220`), which didn't match the real browser viewport — Claude Code rendered 220-wide while xterm.js wrapped/clipped at the actual width. The width is now pinned to 220 **only while unauthenticated** (so the one-time OAuth login URL stays on a single clickable line); once credentials exist the terminal follows the browser window size via SIGWINCH (`checkwinsize`), fixing the everyday rendering. Reopening the tab "fixed" it before only because the resize event restored the correct width.
- `working_directory` config option was ignored — startup always `cd`'d to `/homeassistant`. It is now respected (falls back to `/homeassistant` if the path is invalid).
- Possible fresh-install startup crash: `set -e` plus an unguarded `jq` against `settings.json` (which `claude mcp add-json -s user` does not create) could abort startup. The file is now created if missing before the jq edits.
- `/data` (the add-on's private volume) could not be listed — AppArmor granted `/data/** rwk` but not `/data/ r` for the directory itself, so `ls /data` was denied while known paths still worked. Added `/data/ r`.

### Added
- Pre-installed `PyYAML` and `ruamel.yaml` in the image. Runtime `pip install` fails on the read-only root layer, so YAML libraries could not be added on demand — they now ship in the image.
- Added `file`, `fd`, and `yq` command-line utilities.

## [2.3.11] - 2026-05-21

### Fixed
- Running `claude update` from the terminal now works. The built-in updater was detecting a leftover "native" installation at `~/.local/share/claude` and then failing when it tried to update the npm binary in the read-only image layer. The `claude()` wrapper now intercepts `claude update` and routes it through the working npm-prefix method. On startup, any stale native installation is cleaned up to prevent the "multiple installations" conflict from reappearing.

## [2.3.10] - 2026-05-14

### Changed
- Rebuild to bundle latest Claude Code release.

## [2.3.9] - 2026-05-08

### Fixed
- Startup crash: "Permission denied" when executing `/root/.local/bin/claude`. AppArmor allows read/write on `/root/**` but not execute — any `claude` binary left there from a previous `claude update` would be found in PATH before `/usr/local/bin/claude` and fail. Startup now removes the stale binary from the persisted local-bin so bash always falls through to the AppArmor-allowed path.
- In-container updates via `claude-update` now actually work: added AppArmor `ixmr` permission for `/homeassistant/.claudecode/npm-global/**` so the npm-prefix-installed binary can be executed.

## [2.3.8] - 2026-05-08

### Fixed
- Add-on failed to start with "Permission denied" when creating symlink at `/usr/local/bin/claude`. That path is in the read-only Docker image layer and cannot be overwritten at runtime. Removed all `ln -sf /usr/local/bin/claude` calls; instead, the writable npm prefix (`/homeassistant/.claudecode/npm-global/bin`) is now prepended to PATH in both `run.sh` and `.bashrc`, so any installed update automatically takes priority without touching the image layer.

## [2.3.7] - 2026-05-08

### Fixed
- `claude-update` (and auto-update on startup) failed with "read-only filesystem" error. `claude update` detects it was npm-installed and tries to overwrite files in `/usr/local` — a read-only Docker image layer. Now uses `npm install --prefix` to install into the writable persisted directory (`/homeassistant/.claudecode/npm-global/`) and symlinks `/usr/local/bin/claude` to the result. Users can now run `claude-update` from the terminal to get the latest Claude Code without needing a new add-on image.

## [2.3.6] - 2026-05-05

### Changed
- Updated bundled Claude Code to latest release.
- Added `claude-opus-4-7` to the model selector (replaces `claude-opus-4-6`).

### Fixed
- OAuth/auth URL wrapping across multiple lines when connecting to Claude. tmux resets the PTY width via SIGWINCH when a client attaches, overriding the `stty cols 220` set at shell startup. A `claude()` bash wrapper now re-applies the 220-column PTY width immediately before every `claude` invocation, so auth URLs always render as a single unbroken line.

## [2.3.5] - 2026-05-05

### Changed
- Rebuild to bundle latest Claude Code.
- Removed install progress ticker — HA's own popup handles the in-progress state; log output is now clean.

## [2.3.4] - 2026-04-24

### Fixed
- Add-on install/update appeared hung in HA with no output during the Claude Code npm download step (can take 30-60 seconds). Added a background ticker that prints progress every 20 seconds so HA shows the build is still running.

## [2.3.3] - 2026-04-24

### Fixed
- "Claude symlink points to missing or invalid binary" warning on startup. `claude update` stores the actual version binaries in `~/.local/share/claude/versions/` — only `~/.local/bin/` (the symlink) was being persisted, so after a container rebuild the symlink survived but its target was gone. Now `~/.local/share/claude/` is also persisted to persistent storage.

## [2.3.2] - 2026-04-24

### Changed
- Rebuild to bundle latest Claude Code.

## [2.3.1] - 2026-04-24

### Fixed
- After `claude update`, running `claude` still used the old version due to bash's command hash table caching the npm-installed path. On startup, `run.sh` now symlinks `/usr/local/bin/claude` → the persisted binary when one exists, so there is only ever one `claude` in PATH regardless of hash state.

## [2.3.0] - 2026-04-24

### Changed
- Disabled tmux mouse mode (`set -g mouse off`). tmux was intercepting all mouse and touch events, breaking native browser copy/paste and iPad touch scrolling. With mouse off, the browser's xterm.js terminal handles scrolling (20,000 line buffer via ttyd) and copy/paste natively. Session persistence is unchanged — tmux still maintains the session across reconnects.

## [2.2.9] - 2026-04-16

### Fixed
- After `claude update`, running `claude` still used the old version. Login shells (bash --login / tmux) source `/etc/profile` on Alpine which resets PATH to system defaults, dropping `/root/.local/bin`. Added `export PATH="/root/.local/bin:$PATH"` to `.bashrc` so it's always restored for interactive sessions.

## [2.2.8] - 2026-04-16

### Changed
- Rebuild to bundle latest Claude Code at image build time.

## [2.2.7] - 2026-04-15

### Fixed
- AppArmor profile only grants execute permission (`ixr`) to `/bin/**`, `/usr/bin/**`, `/usr/local/**` etc. — not to `/run.sh` at the filesystem root. Moved startup script to `/usr/local/bin/start-addon.sh` which is in the AppArmor-allowed execution path.

## [2.2.6] - 2026-04-15

### Fixed
- `run.sh` was committed without the execute bit (mode 100644), causing tini to fail with "Permission denied". Fixed by setting mode 100755 in git and changing CMD to `["/bin/bash", "/run.sh"]` so bash executes the script directly regardless of the file's permission bits.

## [2.2.5] - 2026-04-15

### Fixed
- Moved all startup logic from an inline Dockerfile CMD bash -c string into a proper `run.sh` shell script. The inline approach caused `\"` quoting to be passed as literal backslashes to jq (breaking the `&&` chain before ttyd started) and shell keywords in the CLAUDE.md content to be misinterpreted as Dockerfile instructions by the linter. The shell script has none of these quoting constraints.

## [2.2.4] - 2026-04-14

### Fixed
- Startup crash: jq filters with string literals (`.terminal_theme // "dark"`, `.model // "claude-sonnet-4-6"`, etc.) were receiving literal backslash-quotes (`\"`) instead of double quotes when run inside the Docker CMD JSON array. Replaced all string literals in jq filters with `--arg` variables which require no quoting.

## [2.2.3] - 2026-04-14

### Fixed
- Add-on failed to start: `claude update` in the startup CMD (no TTY) was hanging waiting for interactive input. Now pipes `yes` and uses `timeout 120` to prevent blocking startup.
- Restored `DISABLE_AUTOUPDATER=1` to prevent Claude Code's background auto-updater from interfering with startup commands (`claude mcp remove/add-json`).

## [2.2.2] - 2026-04-12

### Fixed
- `claude-update` and auto-update now use `claude update` instead of `npm install -g`. Newer Claude Code versions block npm from overwriting the binary and require using the built-in update command.
- Removed `DISABLE_AUTOUPDATER=1` env var so the built-in updater can function correctly.
- `~/.local/bin/` is now symlinked to persistent storage so updates installed via `claude update` survive add-on restarts and rebuilds.

## [2.2.1] - 2026-04-14

### Fixed
- `claude-update` and auto-update failing because Claude Code's postinstall script calls `sudo`, which HA's security profile blocks. Added a passthrough `sudo` wrapper (container already runs as root so elevation is unnecessary).

## [2.2.0] - 2026-04-14

### Added
- `claude-update` terminal alias: run it from the terminal to update Claude Code instantly without restarting the add-on
- Update notification now mentions `claude-update` as an alternative to restarting

### Changed
- No add-on version bump needed to update Claude Code: just restart the add-on (triggers auto-update) or run `claude-update` in the terminal

## [2.1.99] - 2026-04-12

### Fixed
- Auto-update now shows progress in logs: compares installed vs latest version, logs the update action, and confirms completion — no longer silently hangs with no output

## [2.1.98] - 2026-04-12

### Fixed
- OAuth URL still wrapping: previous fix set the shell COLUMNS variable but Claude Code is Node.js and reads PTY width via ioctl. Now also runs `stty cols 220` at shell start and before each `claude`/`cc` invocation to set the actual PTY width that Node.js reads.

## [2.1.97] - 2026-04-12

### Fixed
- Docker cache no longer causes stale Claude Code version in builds: `BUILD_VERSION` (auto-passed by HA) is declared before the npm install, forcing a fresh `@latest` fetch on every version bump

## [2.1.96] - 2026-04-12

### Changed
- Rebuild to pick up latest @anthropic-ai/claude-code release

## [2.1.95] - 2026-04-11

### Fixed
- "sessionstart: startup hook error": HASS_TOKEN is now injected into the hass-mcp server env config at startup, not only when using the `c` alias

## [2.1.94] - 2026-04-11

### Fixed
- Build-time Claude Code install now uses `@latest` so the image always ships with the newest version, not whatever npm cached at build time

## [2.1.93] - 2026-04-11

### Changed
- Version bump above upstream 2.1.92 so HA detects this fork as an upgrade

## [1.2.71] - 2026-04-11

### Fixed
- "ttyd: missing start command" on startup: the `&` operator for the background update checker was splitting the entire preceding `&&` chain into a background subshell, so `$SHELL_CMD` was never set in the foreground process. Fixed by using `;` to terminate the main chain before launching the background loop.

## [1.2.70] - 2026-04-11

### Changed
- Version bump to verify update flow

## [1.2.69] - 2026-04-11

### Added
- HA persistent notification when Claude Code update is available: appears in the HA UI bell/notification area and is automatically dismissed once up-to-date

## [1.2.68] - 2026-04-11

### Added
- Update available notification: background process checks npm hourly and writes a notice file; terminal displays a yellow banner on open when a newer Claude Code version is available

## [1.2.67] - 2026-04-07

### Changed
- Version bump for update flow testing

## [1.2.66] - 2026-04-07

### Fixed
- Claude Code updates now install to the correct location: replaced `npm update -g` with `npm install -g @anthropic-ai/claude-code@latest` to match build-time install behavior
- Set `DISABLE_AUTOUPDATER=1` to prevent Claude Code's built-in self-updater from installing to `~/.local/bin/` (a different path that doesn't persist across container restarts)

## [1.2.65] - 2026-04-07

### Fixed
- OAuth URL displayed as malformed/multi-line in terminal by setting COLUMNS=220 in bash environment, preventing Claude Code from wrapping the auth URL

## [1.2.64] - 2026-04-07

### Added
- Model selection config option: choose between claude-opus-4-6, claude-sonnet-4-6 (default), and claude-haiku-4-5-20251001
- Selected model is applied via ANTHROPIC_MODEL env var at startup
- Auto-update Claude Code (existing feature) keeps new models accessible without add-on updates

## [1.2.63] - 2026-02-23

### Fixed
- Build failure due to `/usr/local/bin/mcp` conflict between hass-mcp (pip) and @playwright/mcp (npm)
- Switched from `npm install -g @playwright/mcp` to npx cache approach (pre-cache during build, `npx --no-install` at runtime)

### Changed
- Playwright Browser add-on: added aarch64 (ARM64) architecture support

## [1.2.62] - 2026-01-26

### Fixed
- MCP token now auto-updates when starting Claude via `c` or `cc` aliases
- Fixes "HTTP error: 500" when SUPERVISOR_TOKEN changes after addon restart

## [1.2.61] - 2026-01-16

### Added
- Full hardware access (`full_access: true`) for Docker socket mounting

## [1.2.60] - 2026-01-16

### Added
- Docker CLI (`docker` command) to use the Docker API

## [1.2.59] - 2026-01-16

### Added
- Docker API access (`docker_api: true`)

## [1.2.58] - 2026-01-16

### Added
- UART/serial port access (`uart: true`)

## [1.2.57] - 2026-01-16

### Added
- `socat` for bidirectional data transfer between channels

## [1.2.56] - 2026-01-16

### Added
- `pyserial` Python library for serial port communication

## [1.2.55] - 2026-01-16

### Fixed
- Removed `unrar` package (not available in Alpine 3.21)
- Use `7z x file.rar` instead for RAR extraction

## [1.2.54] - 2026-01-16

### Added
- Archive tools: `p7zip` for 7-Zip and RAR archives (use `7z` command)
- Modbus tools: `mbpoll` command line Modbus master, `pymodbus` Python library
- Useful for industrial automation and device communication tasks

## [1.2.53] - 2026-01-15

### Added
- Auto-detect Playwright Browser hostname using Supervisor API
- No need to manually configure `playwright_cdp_host` anymore
- Finds any add-on with slug ending in `playwright-browser`

## [1.2.52] - 2026-01-15

### Fixed
- Changed Playwright CDP endpoint from `ws://` to `http://` protocol
- Playwright auto-discovers the WebSocket path via `/json/version`
- Fixes 404 Not Found error when connecting to Chrome CDP

## [1.2.51] - 2026-01-15

### Added
- Configurable `playwright_cdp_host` option for custom Playwright Browser hostname
- Useful when default hostname doesn't resolve (e.g., use `1016f397-playwright-browser`)

## [1.2.50] - 2026-01-15

### Fixed
- Playwright MCP CDP endpoint hostname corrected to `playwright-browser` (was `local-playwright-browser`)
- Fixes "ENOTFOUND local-playwright-browser" connection error

## [1.2.49] - 2026-01-15

### Added
- GitHub CLI (`gh`) for GitHub operations (PRs, issues, repos, etc.)

## [1.2.48] - 2026-01-15

### Changed
- Playwright MCP now connects to external "Playwright Browser" add-on via CDP
- Removed Chromium from this add-on (keeps image small ~100MB vs ~2GB)
- Alpine + Chromium sandbox issues resolved by using separate Ubuntu-based add-on

### Note
- Requires "Playwright Browser" add-on to be installed and running for browser automation

## [1.2.47] - 2026-01-15

### Fixed
- Created `/usr/local/bin/chromium-wrapper` script that always passes `--no-sandbox`
- Playwright MCP config now points to wrapper script
- Should resolve EACCES and sandbox errors when running as root

## [1.2.46] - 2026-01-15

### Fixed
- Playwright MCP now uses config file with system Chromium
- Added `--no-sandbox` and `--disable-dev-shm-usage` flags for container compatibility
- Uses `/usr/bin/chromium-browser` instead of downloaded Chromium

## [1.2.45] - 2026-01-15

### Fixed
- MCP servers now configured at user scope (`-s user`) instead of project scope
- MCPs are now globally available regardless of working directory

## [1.2.44] - 2026-01-14

### Added
- Playwright MCP server for browser automation (opt-in via `enable_playwright_mcp`)
- Headless Chromium browser pre-installed
- Allows Claude to navigate web pages, fill forms, click elements, and take screenshots

## [1.2.43] - 2026-01-14

### Changed
- Upgraded `hassio_role` from `homeassistant` to `manager`
- Enables access to other add-ons' logs via `ha addons logs <slug>`

## [1.2.42] - 2026-01-14

### Added
- `hassio_role: homeassistant` permission for reading core logs
- Fixes 403 error when using `ha core logs`

## [1.2.41] - 2026-01-14

### Added
- Installed Home Assistant CLI (`ha` command) in the container
- `ha core logs`, `ha core restart`, etc. now available

## [1.2.40] - 2026-01-14

### Fixed
- Updated log commands in CLAUDE.md (`ha` CLI not available in add-on containers)
- Now uses `/homeassistant/home-assistant.log` and Supervisor API

## [1.2.39] - 2026-01-14

### Added
- CLAUDE.md now includes Home Assistant logging instructions
  - Log levels explanation (debug, info, warning, error)
  - Commands to read and filter logs
  - How to enable debug logging for integrations

## [1.2.38] - 2026-01-14

### Added
- Pre-authorized read-only hass-mcp tools (no confirmation needed):
  - `get_version`, `get_entity`, `list_entities`, `search_entities_tool`
  - `domain_summary_tool`, `list_automations`, `get_history`, `get_error_log`
- Pre-authorized file read operations:
  - `Read`, `Glob`, `Grep` for `/homeassistant/**`, `/config/**`, `/share/**`, `/media/**`
- Write operations still require confirmation: `entity_action`, `call_service_tool`, `restart_ha`

## [1.2.37] - 2026-01-14

### Added
- Auto-generated `~/.claude/CLAUDE.md` with path mapping instructions
- Claude Code now knows `/config` → `/homeassistant` translation

## [1.2.36] - 2026-01-14

### Fixed
- Reverted `/config` symlink that caused 502 startup errors

## [1.2.35] - 2026-01-14

### Added
- Symlink `/config` → `/homeassistant` for HA path compatibility (reverted in 1.2.36)

## [1.2.34] - 2026-01-14

### Added
- Auto-update Claude Code option (`auto_update_claude`) - checks for updates on startup
- Keeps Claude Code current without requiring add-on version bumps

## [1.2.33] - 2026-01-14

### Added
- Brazilian Portuguese translation (pt-BR)
- Spanish translation (es)

## [1.2.32] - 2026-01-14

### Fixed
- Added .profile to source .bashrc (tmux login shells need this for aliases)

## [1.2.31] - 2026-01-14

### Fixed
- Version bump to force rebuild (1.2.30 may have been cached before alias fix)

## [1.2.30] - 2026-01-14

### Changed
- Reorganized documentation: DOCS.md renamed to README.md
- Simplified root README.md
- Added Quick Start and Requirements sections

### Fixed
- Added .bashrc with aliases (`c`, `cc`, `ha-config`, `ha-logs`) - they were documented but not working

### Removed
- Deleted unused run.sh (Dockerfile CMD has everything inline)

## [1.2.29] - 2026-01-14

### Fixed
- hass-mcp expects `HA_URL` not `HA_HOST`

## [1.2.28] - 2026-01-14

### Changed
- Export HA_TOKEN/HA_HOST as environment variables instead of baking into MCP config
- hass-mcp now reads token from inherited environment (cleaner approach)

## [1.2.27] - 2026-01-14

### Fixed
- hass-mcp expects `HA_TOKEN` and `HA_HOST` (not `HASS_TOKEN`/`HASS_HOST`)

## [1.2.26] - 2026-01-14

### Fixed
- MCP now configured using `claude mcp add-json` command (proper Claude Code API)
- Previous settings.json approach was not recognized by Claude Code

### Documentation
- Added detailed copy/paste instructions for tmux mode (Ctrl+Shift to select, Shift+Insert to paste)

## [1.2.25] - 2026-01-14

### Fixed
- MCP configuration was never created - hass-mcp integration now works
- Added MCP setup to Dockerfile CMD (run.sh was not being executed)
- `/mcp` command now shows Home Assistant MCP server when `enable_mcp: true`

## [1.2.24] - 2026-01-14

### Added
- Improved tmux mouse wheel scrolling support
- Disable alternate screen buffer for better scrollback (`smcup@:rmcup@`)
- Mouse wheel bindings for scrolling in tmux copy mode

### Note
- Mouse scrolling now enabled; use middle-click or Shift+Insert to paste

## [1.2.23] - 2026-01-14

### Added
- Configure tmux with 20,000 line scrollback buffer (`history-limit`)
- Use `Ctrl+b [` then arrow keys/Page Up/Down to scroll in tmux

## [1.2.22] - 2026-01-14

### Added
- Increased terminal scrollback buffer to 20,000 lines (xterm.js)

## [1.2.21] - 2026-01-14

### Reverted
- Removed tmux mouse mode (breaks paste functionality)

### Documentation
- Added section explaining scrolling and session persistence trade-offs

## [1.2.20] - 2026-01-14

### Fixed
- Persist /root/.claude.json file (stores theme/onboarding state)
- Enable tmux mouse support for scroll wheel (`set -g mouse on`)

## [1.2.19] - 2026-01-14

### Fixed
- Store Claude Code data in /homeassistant/.claudecode (truly persistent)
- Survives addon uninstall/reinstall/rebuild
- Symlink ~/.claude and ~/.config/claude-code to HA config directory

## [1.2.18] - 2026-01-14

### Changed
- Sidebar icon changed to mdi:brain

### Fixed
- Persist both ~/.claude and ~/.config/claude-code directories
- Ensures all Claude Code auth and config survives restarts

## [1.2.17] - 2026-01-14

### Fixed
- Persist Claude Code authentication across restarts
- Symlink /root/.claude to /data/claude for persistent storage
- Restored config reading for font size, theme, and session persistence

## [1.2.16] - 2026-01-14

### Fixed
- Restored config reading for font size, theme, and session persistence
- ttyd now applies terminal_font_size, terminal_theme, and session_persistence settings

## [1.2.15] - 2026-01-14

### Fixed
- Refined AppArmor profile with focused permissions for HA config access
- Added dac_read_search capability for directory listing
- Full access to /homeassistant, /share, /media, /config directories
- Read-only access to system files, SSL, backups

## [1.2.14] - 2026-01-14

### Fixed
- Add /etc/** read permissions to AppArmor profile
- Fixes "bash: /etc/profile: Permission denied" error

## [1.2.13] - 2026-01-14

### Fixed
- Add PTY permissions to AppArmor profile (sys_tty_config, /dev/ptmx, /dev/pts/*)
- Fixes "pty_spawn: Permission denied" error when spawning terminal

## [1.2.12] - 2026-01-14

### Fixed
- Use static ttyd binary from GitHub releases instead of Alpine package
- Fixes "failed to load evlib_uv" libwebsockets error

## [1.2.11] - 2026-01-14

### Changed
- Simplified startup: run ttyd directly in CMD without script file
- Minimal configuration for debugging startup issues

## [1.2.10] - 2026-01-14

### Fixed
- Create run.sh inline via heredoc to avoid file permission issues

## [1.2.9] - 2026-01-14

### Fixed
- Add .gitattributes to enforce LF line endings for shell scripts
- Force Docker cache bust for permission fixes

## [1.2.8] - 2026-01-14

### Changed
- Use Docker's tini init system (`init: true`) instead of s6-overlay
- Simplified entrypoint configuration

## [1.2.7] - 2026-01-14

### Fixed
- Use bash instead of bashio in s6-overlay run script
- Add chmod +x /init to fix permission issues

## [1.2.6] - 2026-01-14

### Changed
- Properly configure s6-overlay v3 service structure
- Add service files in /etc/s6-overlay/s6-rc.d/ttyd

## [1.2.5] - 2026-01-14

### Changed
- Attempted switch to pure Alpine base image (reverted due to HA format requirements)

## [1.2.4] - 2026-01-14

### Fixed
- Set `init: false` for s6-overlay v3 compatibility

## [1.2.3] - 2026-01-14

### Fixed
- Force bash entrypoint to bypass s6-overlay init issues

## [1.2.2] - 2026-01-14

### Fixed
- Remove s6-overlay dependency, use plain bash with jq
- Fixes "/init: Permission denied" startup error

## [1.2.1] - 2026-01-14

### Fixed
- Corrected hass-mcp package name (was homeassistant-mcp)
- Upgraded to Python 3.13 base image for hass-mcp compatibility

## [1.2.0] - 2026-01-14

### Changed
- **Security improvement**: Removed API key from add-on config - Claude Code now handles authentication itself
- Simplified Dockerfile - use Alpine's ttyd package instead of architecture-specific downloads
- Removed model selection from config (Claude Code manages this)

### Fixed
- Docker build failure due to BUILD_ARCH variable not being passed correctly

## [1.1.0] - 2026-01-14

### Added
- Model selection option (sonnet, opus, haiku)
- Terminal font size configuration (10-24px)
- Terminal theme selection (dark/light)
- Session persistence using tmux
- s6-overlay service definitions for better process management
- Shell aliases and shortcuts (c, cc, ha-config, ha-logs)
- Welcome banner with configuration info
- Health check for container monitoring

### Changed
- Upgraded to Python 3.12 Alpine base image
- Improved architecture-specific ttyd binary installation
- Enhanced run.sh with better configuration handling
- Better error messages and validation

### Fixed
- Proper ingress base path handling

## [1.0.0] - 2026-01-14

### Added
- Initial release
- Web terminal interface using ttyd
- Claude Code integration via npm package
- Home Assistant MCP server integration for entity/service access
- Read-write access to Home Assistant configuration
- Multi-architecture support (amd64, aarch64, armv7, armhf, i386)
- Ingress support for seamless sidebar integration
