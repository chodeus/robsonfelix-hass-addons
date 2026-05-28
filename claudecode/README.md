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
- **hass-mcp Integration**: Direct control of HA entities and services
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
3. Follow the authentication prompts
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

With hass-mcp enabled, Claude can:

- Query entity states: "What's the temperature in the living room?"
- Control devices: "Turn off all lights in the bedroom"
- List services: "What services are available for climate control?"
- Debug automations: "Why didn't my morning routine trigger?"

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
| `model` | Model to pin (empty = account default) | "" (empty) |

### Model Selection

Leave `model` **empty** (the default) to use your Claude account/subscription default — you can
then switch models any time inside a session with the `/model` command.

To pin a specific model, set `model` to its id, e.g.:

| Example id | Notes |
|------------|-------|
| `claude-opus-4-7` | Most capable, for complex tasks |
| `claude-sonnet-4-6` | Balanced speed/capability |
| `claude-haiku-4-5-20251001` | Fastest, for simple queries |

Because `model` is a free-text field, **any** model id works — new Anthropic models are usable as
soon as Claude Code supports them, with no add-on update needed (pair with `auto_update_claude`).

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

### hass-mcp not working

1. Verify `enable_mcp` is true in configuration
2. Check add-on logs for connection errors
3. Restart the add-on after configuration changes

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
