# Claude Code for Home Assistant

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code), Anthropic's AI-powered coding assistant, directly in your Home Assistant sidebar with full access to your configuration.

## Quick Start

```bash
claude "List all my automations"
claude "Turn off all lights in the living room"
claude "Create an automation to turn on lights at sunset"
claude "Why isn't my motion sensor automation working?"
```

## Requirements

- Home Assistant OS or Supervised installation
- [Anthropic account](https://console.anthropic.com/) (authentication handled in terminal)
- On x86-64: a CPU with **SSE4.2** (any hardware from ~2009+). Claude Code's bundled runtime
  (Bun) is a "baseline" build needing SSE4.2 — not AVX. Virtual machines matter here:
  Proxmox/QEMU's default `kvm64` CPU type masks SSE4.2, and Claude Code then crashes (SIGILL)
  or hangs silently at 100% CPU. Set the VM CPU type to `host` (or `x86-64-v2`+) and then
  **fully stop and start the VM** — an in-guest reboot does not repropagate CPU flags. The
  add-on warns in its log if SSE4.2 is missing. See [Troubleshooting](#add-on-wont-start-or-the-log-stops-early)
  if the add-on won't start.

## Features

- **Web Terminal**: Access Claude Code through a browser-based terminal
- **Config Access**: Read and write Home Assistant configuration files
- **Home Assistant MCP (ha-mcp)**: ~92 tools to query state and *manage* HA — entities, services, automations, scripts, scenes, dashboards, helpers, areas, backups, and more
- **Session Persistence**: tmux-based persistence — sessions *and their scrollable history* survive page refreshes, tab closes, and connection blips
- **Scrollable Claude output**: Claude Code runs in fullscreen rendering mode — scroll the whole conversation with the mouse wheel, search it with `Ctrl+O`
- **Customizable Theme**: Choose between dark and light terminal themes
- **Multi-Architecture**: Supports amd64 and aarch64 (Claude Code has no 32-bit builds)
- **Secure Authentication**: Claude Code handles its own authentication securely

## Setup

### 1. Install the Add-on

1. Add the repository to Home Assistant
2. Install the "Claude Code" add-on
3. Start the add-on
4. Open the Web UI from the sidebar

### 2. Authenticate with Claude Code

On first launch, Claude Code will prompt you to authenticate:

1. Open the terminal from the HA sidebar
2. Type `claude` to start
3. Follow the authentication prompts — see [Authenticating Claude Code (first launch)](#authenticating-claude-code-first-launch) for how to get the long sign-in URL into your browser (double-click it to copy the whole URL)
4. Your credentials are stored securely by Claude Code

**Note**: The add-on does NOT require you to enter API keys in the configuration. Claude Code handles authentication itself, storing credentials securely in its own configuration directory. This is more secure than storing keys in Home Assistant's add-on config.

## Using Claude Code

### Basic Usage

Once authenticated, Claude Code is ready to help with:

- Editing Home Assistant YAML configurations
- Creating automations and scripts
- Debugging configuration issues
- Writing custom integrations

### Home Assistant Integration

The add-on bundles [ha-mcp](https://github.com/homeassistant-ai/ha-mcp), a Home Assistant MCP
server (~92 tools) that connects automatically via the Supervisor token — no setup needed. With
it, Claude can both **query** and **manage** Home Assistant:

- Query state: "What's the temperature in the living room?"
- Control devices: "Turn off all lights in the bedroom"
- Create/edit automations & scripts: "Add an automation to turn on the porch light at sunset"
- Manage dashboards, scenes, helpers, areas, zones, labels
- Debug automations from execution traces: "Why didn't my morning routine trigger?"
- Backups, history, statistics, logs, and more

Read-only tools (search, state, history, logs, template eval) run without confirmation;
state-changing tools (calling services, editing automations, restarting HA, etc.) ask first.

> **Editing raw config files / `configuration.yaml`:** ha-mcp's file and YAML-editing tools are
> *beta* and disabled by default — they need ha-mcp's companion custom component installed in HA
> plus feature flags. The 80+ management tools above work without it. (Claude Code also has direct
> read/write access to `/homeassistant` files via its normal file tools.)

### Example Commands

```bash
# Start interactive session
claude

# One-off commands
claude "Add a new automation that turns on the porch light at sunset"
claude "Check my configuration.yaml for errors"
claude "List all unavailable entities"

# Continue previous conversation
claude --continue
```

### Keyboard Shortcuts

| Shortcut | Command |
|----------|---------|
| `c` | `claude` |
| `cc` | `claude --continue` |
| `ha-config` | Navigate to config directory |
| `ha-logs` | View Home Assistant logs |

### Terminal Basics (copy, paste, scroll)

Claude Code runs in **fullscreen rendering mode** inside a tmux session: the conversation is
scrolled by Claude itself (like `vim` or `htop`), which is what makes long output actually
scrollable — the classic renderer erases terminal scrollback on every repaint.

| Action | How |
|--------|-----|
| **Scroll Claude's conversation** | Mouse wheel, or `PgUp`/`PgDn` |
| **Search / review the whole conversation** | `Ctrl+O` opens transcript mode: `/` to search, `[` to write it out as ordinary terminal text (scroll/search it with the wheel via tmux's 50,000-line history), `v` to open in an editor, `q` to exit |
| **Scroll shell output** (outside Claude) | Wheel up enters tmux copy-mode over 50,000 lines of history; `q` to exit |
| **Copy inside Claude** | Just drag-select (or double-click a word/URL) — it copies automatically on release |
| **Copy anywhere (always works)** | Hold **Shift** and drag-select, then `Cmd/Ctrl+C` — Shift bypasses the app's mouse capture for a native browser selection |
| **Paste** | `Cmd+V` / `Ctrl+V`, or right-click → Paste |
| **Interrupt Claude** | `Esc` (or `Ctrl+C` at the shell) |

> **If the wheel feels slow**, set `CLAUDE_CODE_SCROLL_SPEED=3` (run `export CLAUDE_CODE_SCROLL_SPEED=3`
> before `claude`, or use `/scroll-speed` in a session). **If you prefer native selection everywhere**,
> `export CLAUDE_CODE_DISABLE_MOUSE=1` keeps the flicker-free renderer but releases the mouse to the
> browser (keyboard-only scrolling). **To go back to the classic renderer** for a session, run
> `/tui default` inside Claude.
>
> On the shell prompt, `Ctrl+C` cancels the current command rather than copying — use `Cmd/Ctrl+C`
> only when text is selected.

### Mobile (touch) support

On phones and tablets the terminal page loads a touch shim (xterm.js has no touch support of
its own):

| Action | How |
|--------|-----|
| **Scroll** | One-finger drag (with flick momentum) — works in Claude's conversation and tmux history |
| **Select & copy** | Long-press, then drag; release to copy. Claude/tmux highlight the selection and copy it on release — if a **"Tap to copy"** toast appears, tap it (iOS requires a tap before anything may touch the clipboard) |
| **Keys the on-screen keyboard lacks** | Bottom key bar: `esc`, `tab`, `⇧tab`, arrows (hold to repeat), `^c`, `paste` |
| **Paste** | `paste` on the key bar (Safari will ask for permission the first time) |

The terminal also refits itself when the on-screen keyboard opens (so the prompt stays
visible) and reconnects automatically when you return to the app after iOS suspended it —
the tmux session keeps everything intact meanwhile.

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `enable_mcp` | Enable HA integration | true |
| `terminal_font_size` | Font size (10-24) | 14 |
| `terminal_theme` | dark or light | dark |
| `working_directory` | Start directory | /homeassistant |
| `session_persistence` | Keep the session alive across reconnects (uses tmux) | true |
| `auto_update_claude` | Auto-update Claude Code (startup + hourly). When off, you get an update notification instead | false |
| `model` | Model to use (dropdown; `default` = account default) | default |
| `model_custom` | Model id used only when `model` is `custom` | "" (empty) |
| `enable_remote_control` | Auto-start Claude Code's Remote Control bridge (view/steer from claude.ai or the mobile app) | false |
| `remote_control_session_prefix` | Prefix for auto-generated Remote Control session names | HomeAssistant |
| `restrict_terminal_port` | *(experimental)* Firewall the terminal port to HA ingress only — see [Container Security](#container-security) | false |

### Model Selection

Pick a model from the `model` dropdown:

| Option | Meaning |
|--------|---------|
| `default` | Don't pin a model — let Claude Code decide (see the precedence note below); switch any time with `/model` in a session |
| `claude-fable-5` | Most capable — the new top tier above Opus, standard 200K context |
| `claude-fable-5[1m]` | Same Fable 5 with the **1M-token context window** (see note below) |
| `claude-opus-4-8` | Latest Opus, standard 200K context |
| `claude-opus-4-8[1m]` | Same Opus 4.8 with the **1M-token context window** (see note below) |
| `claude-opus-4-7` | Previous Opus generation |
| `claude-sonnet-4-6` | Balanced speed/capability |
| `claude-haiku-4-5` | Fastest, for simple queries |
| `custom` | Use whatever id you put in `model_custom` |

> **About the 1M context window (`[1m]`):** the `[1m]` suffix is a Claude Code notation — it
> selects the same model but enables the 1-million-token context window (works for both
> `claude-fable-5[1m]` and `claude-opus-4-8[1m]`). Claude Code strips the suffix before calling
> the API. Pick the plain id for the standard 200K context. You can also set this in
> `model_custom` (enter e.g. `claude-fable-5[1m]`) or switch in-session with `/model`.
>
> **⚠️ Cost / availability:** the 1M-context variants are plan-gated and **more expensive** —
> Claude Code's model picker flags Opus 4.8's 1M variant with a **5× cost multiplier** and a note
> that it **draws from your usage credits**; expect a similar premium on Fable 5's 1M variant.
> Fable 5 is also priced above Opus 4.8 even at standard context. 1M context is included on
> Max/Team/Enterprise (subject to that usage), standard pay-as-you-go pricing on Pro/API. If your
> plan isn't entitled, a request may return a 4xx error or silently fall back to the 200K context.
> Use it deliberately for genuinely large-context work; stick with the plain id otherwise.

> **How `default` resolves:** `default` simply leaves the model unpinned (the add-on doesn't set
> `ANTHROPIC_MODEL`). Claude Code then picks the model by its own precedence: a model in
> `~/.claude/settings.json` (e.g. one you previously chose with `/model`) wins over the account
> default. So if you've set a model in-session before, `default` may use *that*, not your
> subscription default — pin a model in this dropdown if you want a guaranteed choice.

The dropdown keeps the common choices typo-proof. For a model that isn't listed yet (a newer
release), choose **`custom`** and enter its id in `model_custom` — no add-on update needed. If
`custom` is selected but `model_custom` is empty, the add-on leaves the model unpinned (same as
`default`).

### Remote Control

Set `enable_remote_control: true` to have Claude Code auto-start its **Remote Control** bridge
each session, so you can view and steer the add-on's session from [claude.ai/code](https://claude.ai/code)
or the Claude mobile app. `remote_control_session_prefix` sets the prefix of the auto-generated
session name shown there (default `HomeAssistant` → e.g. `HomeAssistant-graceful-unicorn`).

- Requires the add-on's Claude Code to be signed into a **claude.ai Pro, Max, Team, or
  Enterprise** account — API-key auth does not support Remote Control.
- **⚠️ Security:** this add-on runs as root with full access to your Home Assistant host, so
  anyone who can sign in to the linked Claude account can drive it. Leave this **off** unless you
  need it, and see [Container Security](#container-security).

## Update Notifications

The add-on checks for newer versions of Claude Code in the background every hour, regardless of the `auto_update_claude` setting:

- **`auto_update_claude: false` (default):** if an update is available, a **persistent notification** appears in the HA UI notification bell ("Claude Code Update Available") and a **yellow banner** is shown each time you open a new terminal session. Install it with `claude-update` (or `claude update`) in the terminal — no restart needed.
- **`auto_update_claude: true`:** new releases are installed automatically in the background (a running session keeps its current version until you start a new `claude`). The notification is cleared automatically.

The default is off so that you decide when new code runs on your Home Assistant box.

## File Locations

| Path | Description | Access |
|------|-------------|--------|
| `/homeassistant` | HA configuration directory | read-write |
| `/share` | Shared folder | read-write |
| `/media` | Media folder | read-write |
| `/ssl` | SSL certificates | read-only |
| `/backup` | Backups | read-only |

## Session Persistence

When `session_persistence` is enabled (the default), the add-on wraps your shell in a
[tmux](https://github.com/tmux/tmux) session (the status bar is hidden, so it's invisible in
normal use). This means:

- Your session survives browser refreshes, tab closes, and connection blips
- **Your on-screen state survives too** — after a reconnect, tmux repaints the full terminal
  state, so Claude's conversation is still there and still scrollable (the previous dtach-based
  persistence came back to a blank screen after every reconnect)
- Long-running Claude tasks keep running in the background while the tab is closed
- Reopening the terminal reattaches you to the same session automatically

- **Detach**: just close the tab (the session keeps running)
- **Reattach**: reopen the terminal from the sidebar

> Note: the session lives only while the add-on is running. Restarting the add-on starts a fresh
> session (Claude's `claude --continue` / `cc` picks the conversation back up).

### Authenticating Claude Code (first launch)

On first launch Claude Code prints a sign-in URL. It is very long (~450 characters) and **wraps
across several lines** in the terminal. **Don't try to click it** — copy it instead:

1. **Double-click anywhere on the URL.** Claude Code selects the entire URL (all wrapped lines,
   including `https://`) and copies it to your clipboard automatically on release.
2. **Paste into your browser's address bar** (`Cmd/Ctrl+V`) and press Enter.
3. Complete authentication in the browser, **copy the auth code** it gives you, click back into the
   terminal, and **paste** the code (`Cmd/Ctrl+V` or right-click) at the `Paste code here` prompt.

> **If double-click copy doesn't land in your clipboard** (some browser/security setups block
> programmatic clipboard writes): hold **Shift** and drag-select the whole URL from `https` through
> its last character, press `Cmd/Ctrl+C`, and paste it into the **address bar** — browsers strip the
> line breaks that tmux's hard wrapping introduces when pasting there. This is a one-time step —
> once authenticated, credentials persist.

### Trade-offs

**With persistence (`session_persistence: true`, default):**
- ✅ Session **and visible history** survive refresh, tab close, and connection blips
- ✅ Long-running Claude tasks continue in the background
- ✅ Mouse-wheel scrolling through Claude's whole conversation; 50,000 lines of shell history
- ⚠️ tmux hard-wraps long lines; use double-click (in Claude) or Shift+drag for copying

**Without persistence (`session_persistence: false`):**
- ✅ Plain bash with the browser's native soft-wrap selection
- ❌ Session lost on browser refresh or any connection blip
- ❌ Session lost if the add-on restarts

**Recommendation:** leave `session_persistence: true` (the default) — losing your session (and
Claude's output) to every ingress reconnect is exactly the problem this release fixes.

## Security

### Authentication
- **No API keys in add-on config**: Claude Code handles authentication itself
- Credentials are stored securely in Claude Code's own directory (`~/.claude/`)
- This is more secure than storing keys in Home Assistant's configuration

### Container Security
- The Supervisor token is automatically managed, passed to the MCP server via environment
  variables only, and never written to disk (a startup scrub removes tokens persisted by
  older versions)
- File access is limited to mapped directories
- The add-on runs in an isolated container
- **Accepted risk:** the web terminal (ttyd) itself has no login of its own — it relies on
  Home Assistant's ingress authentication, and no host port is published. Like other HA
  terminal add-ons, this means another *add-on container* on the internal hassio network
  could reach the terminal port directly. Only install add-ons you trust.
- **Optional mitigation (`restrict_terminal_port`, experimental, default off):** enable it to
  firewall port 7681 to Home Assistant's ingress (plus loopback for the healthcheck) using
  iptables inside the container, so other add-on containers can't reach the shell. It resolves
  the ingress source from the `supervisor` hostname and **fails open** (never blocks ingress) if
  iptables isn't available — but because it touches the container's firewall, **verify the
  terminal still loads after enabling it** before relying on it.

## Troubleshooting

### Authentication issues

Claude Code manages its own authentication. If you have issues:
1. Type `claude` to start the authentication flow
2. Follow the prompts to log in or enter your API key
3. Credentials are saved automatically for future sessions

**Can't copy the URL or paste the auth code?** Double-click the URL inside Claude to copy it whole; for anything else hold **Shift** while drag-selecting, then `Cmd/Ctrl+C`. Paste with `Cmd/Ctrl+V` or right-click. See [Authenticating Claude Code (first launch)](#authenticating-claude-code-first-launch).

### Home Assistant MCP (ha-mcp) not working

1. Verify `enable_mcp` is true in configuration
2. In a session, run `claude mcp list` — `homeassistant` should show as connected
3. Check add-on logs for connection errors
4. Restart the add-on after configuration changes

### Terminal not loading

1. Check that the add-on is running (green indicator)
2. Try refreshing the page
3. Check browser console for errors
4. Review add-on logs for ttyd errors

### Session not persisting

1. Ensure `session_persistence` is set to true
2. The session is named "claude" - it will auto-attach on reconnect

### Configuration changes not applying

After changing configuration:
1. Save the configuration
2. Restart the add-on completely

### Add-on won't start, or the log stops early

If the add-on shows as running but the terminal never loads, or the log stops shortly after
startup, the most common cause is a **CPU without SSE4.2** — Claude Code's bundled Bun runtime
either crashes (SIGILL) or hangs silently at 100% CPU. This almost always happens in a VM whose
CPU type masks SSE4.2:

- **Proxmox / QEMU:** set the VM's CPU type to `host` (or `x86-64-v2`+), then **fully stop and
  start the VM from Proxmox** — a reboot from inside the guest does not repropagate the new CPU
  flags. Verify inside the add-on terminal with `grep -m1 -o sse4_2 /proc/cpuinfo`.
- **libvirt:** use `<cpu mode="host-passthrough"/>` (or `host-model`), then stop/start the domain.
- **ESXi / other:** enable CPU/host passthrough for the VM.

The add-on now keeps the terminal reachable even when Claude Code itself can't run, so you can
open it and check `grep -m1 -o sse4_2 /proc/cpuinfo` from inside.

### Claude Code exits immediately with a "root/sudo" error

If `claude` quits at launch complaining that `--dangerously-skip-permissions` cannot be used with
root privileges, a `bypassPermissions` mode got saved into your settings (this add-on runs as
root). Because settings persist across restarts and reinstalls, removing/reinstalling the add-on
won't clear it. Fix it from the terminal:

```bash
grep -l bypassPermissions /homeassistant/.claudecode/settings.json /homeassistant/.claudecode/.claude.json 2>/dev/null
# then edit that file and remove the "defaultMode": "bypassPermissions" entry, e.g.:
jq 'del(.permissions.defaultMode)' /homeassistant/.claudecode/settings.json > /tmp/s && mv /tmp/s /homeassistant/.claudecode/settings.json
```

## Support

- [GitHub Issues](https://github.com/chodeus/robsonfelix-hass-addons/issues)
- [Home Assistant Community](https://community.home-assistant.io/)
