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

## Features

- **Web Terminal**: Access Claude Code through a browser-based terminal
- **Config Access**: Read and write Home Assistant configuration files
- **Home Assistant MCP (ha-mcp)**: ~92 tools to query state and *manage* HA — entities, services, automations, scripts, scenes, dashboards, helpers, areas, backups, and more
- **Session Persistence**: Optional dtach-based persistence to keep sessions alive across page refreshes
- **Customizable Theme**: Choose between dark and light terminal themes
- **Multi-Architecture**: Supports amd64, aarch64, armv7, armhf, and i386
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
3. Follow the authentication prompts — see [Authenticating Claude Code (first launch)](#authenticating-claude-code-first-launch) for how to get the long sign-in URL into your browser (select-and-copy, don't click it)
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

The terminal uses your browser's native text handling — there are no special key chords to learn.

| Action | How |
|--------|-----|
| **Copy** | Select text with the mouse, then `Cmd+C` (macOS) / `Ctrl+C` (Windows/Linux), or right-click → Copy |
| **Paste** | `Cmd+V` / `Ctrl+V`, or right-click → Paste |
| **Scroll** | Mouse wheel or the scrollbar (20,000-line buffer) |
| **Interrupt Claude** | `Esc` (or `Ctrl+C` at the shell) |

> **Copying long lines (e.g. the sign-in URL):** a long line that *looks* wrapped across several
> rows is still a single line — drag-select the whole thing and copy, and it comes out as one
> piece with no line breaks. Don't try to click long URLs; the terminal's link handler only grabs
> the first row. See [Authenticating Claude Code](#authenticating-claude-code-first-launch).
>
> On the shell prompt, `Ctrl+C` cancels the current command rather than copying — use `Cmd/Ctrl+C`
> only when text is selected.

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `enable_mcp` | Enable HA integration | true |
| `terminal_font_size` | Font size (10-24) | 14 |
| `terminal_theme` | dark or light | dark |
| `working_directory` | Start directory | /homeassistant |
| `session_persistence` | Keep the session alive across reconnects (uses dtach) | true |
| `auto_update_claude` | Auto-update Claude Code (startup + hourly) | true |
| `model` | Model to use (dropdown; `default` = account default) | default |
| `model_custom` | Model id used only when `model` is `custom` | "" (empty) |

### Model Selection

Pick a model from the `model` dropdown:

| Option | Meaning |
|--------|---------|
| `default` | Don't pin a model — let Claude Code decide (see the precedence note below); switch any time with `/model` in a session |
| `claude-opus-4-8` | Most capable (latest Opus), standard 200K context |
| `claude-opus-4-8[1m]` | Same Opus 4.8 with the **1M-token context window** (see note below) |
| `claude-opus-4-7` | Previous Opus generation |
| `claude-sonnet-4-6` | Balanced speed/capability |
| `claude-haiku-4-5-20251001` | Fastest, for simple queries |
| `custom` | Use whatever id you put in `model_custom` |

> **About the 1M context window (`[1m]`):** the `[1m]` suffix is a Claude Code notation — it
> selects the same `claude-opus-4-8` model but enables the 1-million-token context window. Claude
> Code strips the suffix before calling the API. Pick the plain `claude-opus-4-8` for the standard
> 200K context. You can also set this in `model_custom` (enter `claude-opus-4-8[1m]`) or switch
> in-session with `/model`.
>
> **⚠️ Cost / availability:** the 1M-context Opus is plan-gated and **more expensive** — Claude
> Code's own model picker flags it with a **5× cost multiplier** and a note that it **draws from
> your usage credits**. It's included on Max/Team/Enterprise (subject to that usage), standard
> pay-as-you-go pricing on Pro/API. If your plan isn't entitled, a request may return a 4xx error
> or silently fall back to the 200K context. Use it deliberately for genuinely large-context work;
> stick with plain `claude-opus-4-8` otherwise.

> **How `default` resolves:** `default` simply leaves the model unpinned (the add-on doesn't set
> `ANTHROPIC_MODEL`). Claude Code then picks the model by its own precedence: a model in
> `~/.claude/settings.json` (e.g. one you previously chose with `/model`) wins over the account
> default. So if you've set a model in-session before, `default` may use *that*, not your
> subscription default — pin a model in this dropdown if you want a guaranteed choice.

The dropdown keeps the common choices typo-proof. For a model that isn't listed yet (a newer
release), choose **`custom`** and enter its id in `model_custom` — no add-on update needed. If
`custom` is selected but `model_custom` is empty, the add-on leaves the model unpinned (same as
`default`).

## Update Notifications

When `auto_update_claude` is enabled, the add-on checks for newer versions of Claude Code in the background every hour. If an update is available:

- A **persistent notification** appears in the HA UI notification bell with the title "Claude Code Update Available"
- A **yellow banner** is shown in the terminal each time you open a session

Both clear automatically after restarting the add-on, which installs the latest version on startup.

## File Locations

| Path | Description | Access |
|------|-------------|--------|
| `/homeassistant` | HA configuration directory | read-write |
| `/share` | Shared folder | read-write |
| `/media` | Media folder | read-write |
| `/ssl` | SSL certificates | read-only |
| `/backup` | Backups | read-only |

## Session Persistence

When `session_persistence` is enabled (the default), the add-on wraps your shell in
[dtach](https://github.com/crigler/dtach), a lightweight detach/attach tool. This means:

- Your session survives browser refreshes and disconnects
- Long-running Claude tasks keep running in the background while the tab is closed
- Reopening the terminal reattaches you to the same session automatically

Unlike a full terminal multiplexer, dtach does not capture the mouse or reflow output, so the
browser handles scrolling and copy/paste natively (see [Terminal Basics](#terminal-basics-copy-paste-scroll)).

- **Detach**: just close the tab (the session keeps running)
- **Reattach**: reopen the terminal from the sidebar

> Note: the session lives only while the add-on is running. Restarting the add-on starts a fresh
> session (the same as before — the previous tool used an in-memory session too).

### Authenticating Claude Code (first launch)

On first launch Claude Code prints a sign-in URL. It is very long (~450 characters) and **wraps
across several lines** in the terminal. **Don't click it** — the web terminal's link handler only
captures the first line, so you'll get a truncated, broken URL. Copy the whole thing instead:

1. **Drag-select the entire URL** with your mouse — from `https` on the first line down through the
   last characters on the final line.
2. **Copy** it (`Cmd/Ctrl+C`, or right-click → Copy). Because the line is soft-wrapped, this copies
   the full URL as one piece with no line breaks.
3. **Paste into your browser's address bar** (`Cmd/Ctrl+V`) and press Enter.
4. Complete authentication in the browser, **copy the auth code** it gives you, click back into the
   terminal, and **paste** the code (`Cmd/Ctrl+V` or right-click) at the `Paste code here` prompt.

> Why not just click the link? The terminal (ttyd/xterm.js) underlines the full wrapped URL but its
> click handler only returns the first visible row, truncating long URLs. Selecting and copying is
> the reliable method. This is a one-time step — once authenticated, credentials persist.

### Trade-offs

**With persistence (`session_persistence: true`, default):**
- ✅ Session survives browser refresh/disconnect
- ✅ Long-running Claude tasks continue in the background
- ✅ Native scrolling and copy/paste
- ✅ 20,000-line scrollback buffer

**Without persistence (`session_persistence: false`):**
- ✅ Native scrolling and copy/paste
- ✅ Slightly simpler (no detach layer)
- ❌ Session lost on browser refresh
- ❌ Session lost if the add-on restarts

**Recommendation:** leave `session_persistence: true` (the default) unless you have a specific reason
to disable it — copy/paste and scrolling are native either way.

## Security

### Authentication
- **No API keys in add-on config**: Claude Code handles authentication itself
- Credentials are stored securely in Claude Code's own directory (`~/.claude/`)
- This is more secure than storing keys in Home Assistant's configuration

### Container Security
- The Supervisor token is automatically managed and not exposed
- File access is limited to mapped directories
- The add-on runs in an isolated container

## Troubleshooting

### Authentication issues

Claude Code manages its own authentication. If you have issues:
1. Type `claude` to start the authentication flow
2. Follow the prompts to log in or enter your API key
3. Credentials are saved automatically for future sessions

**Can't copy the URL or paste the auth code?** Copy/paste is native: select with the mouse and press `Cmd/Ctrl+C`, then paste with `Cmd/Ctrl+V` or right-click. See [Authenticating Claude Code (first launch)](#authenticating-claude-code-first-launch).

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

## Support

- [GitHub Issues](https://github.com/chodeus/robsonfelix-hass-addons/issues)
- [Home Assistant Community](https://community.home-assistant.io/)
