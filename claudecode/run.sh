#!/bin/bash
set -e

export HA_TOKEN="$SUPERVISOR_TOKEN"
export HA_URL="http://supervisor/core"
# ha-mcp connects to HA via the Supervisor proxy using the add-on's Supervisor token
# (same pattern as the official ha-mcp add-on). Exported so the MCP subprocess inherits them.
export HOMEASSISTANT_URL="http://supervisor/core"
export HOMEASSISTANT_TOKEN="$SUPERVISOR_TOKEN"
# Make bash the default shell (Claude Code + tooling); the image default resolves to busybox /bin/sh
export SHELL=/bin/bash
PERSIST_DIR=/homeassistant/.claudecode
NPM_GLOBAL_DIR="$PERSIST_DIR/npm-global"
# Prepend writable npm prefix to PATH so any installed update takes priority over the image binary
export PATH="$NPM_GLOBAL_DIR/bin:$PATH"

mkdir -p "$PERSIST_DIR/config" "$NPM_GLOBAL_DIR" /root/.config

# Write the add-on's context/guidance file. It is imported from CLAUDE.md (below) rather
# than written into it: ~/.claude/CLAUDE.md is Claude Code's user-memory file (/memory edits
# land there), so overwriting it every start would destroy the user's saved notes.
cat > "$PERSIST_DIR/CLAUDE.addon.md" << 'CLAUDEMD'
# Claude Code - Home Assistant Add-on

## Path Mapping

In this add-on container, paths are mapped differently than HA Core:
- `/homeassistant` = HA config directory (equivalent to `/config` in HA Core)
- `/config` here is the ADD-ON's private config folder (addon_configs), NOT the HA config

When users mention `/config/...`, they almost always mean HA's config - translate to `/homeassistant/...`

## Available Paths

| Path | Description | Access |
|------|-------------|--------|
| `/homeassistant` | HA configuration | read-write |
| `/share` | Shared folder | read-write |
| `/media` | Media files | read-write |
| `/ssl` | SSL certificates | read-only |
| `/backup` | Backups | read-only |

## Home Assistant Integration

The `homeassistant` MCP server (ha-mcp) gives you ~92 tools to both query and manage HA:
- Read: `ha_get_overview`, `ha_search_entities`, `ha_get_state`, `ha_get_history`, `ha_get_logs`,
  `ha_get_automation_traces`, `ha_eval_template`, `ha_list_services`
- Manage: `ha_call_service`, `ha_bulk_control`, and `ha_config_set_*` / `ha_config_get_*` for
  automations, scripts, scenes, dashboards, helpers, areas, zones, labels, plus backups
- Use `ha_search_tools` (if tool search is enabled) or the tool list to discover the rest

Read-only tools run without confirmation; state-changing tools ask first. Prefer the MCP tools
for entity/automation work; use direct file edits under `/homeassistant` for raw YAML.

## Reading Home Assistant Logs

**Log levels (from most to least verbose):**
- `debug` - Only shown if explicitly enabled in configuration.yaml
- `info` - General information, shown by default
- `warning` - Warnings, always shown
- `error` - Errors, always shown

**Commands to read logs:**
```bash
# View recent logs (ha CLI)
ha core logs 2>&1 | tail -100

# Filter by keyword
ha core logs 2>&1 | grep -i keyword

# Filter errors only
ha core logs 2>&1 | grep -iE "(error|exception)"

# Alternative: read log file directly
tail -100 /homeassistant/home-assistant.log
```

**To enable debug logging for an integration**, add to `configuration.yaml`:
```yaml
logger:
  default: info
  logs:
    custom_components.YOUR_INTEGRATION: debug
```

**Key insight:** `_LOGGER.debug()` calls are invisible unless the logger level is set to debug. Use `_LOGGER.info()` or `_LOGGER.warning()` for logs that should always appear.
CLAUDEMD

# CLAUDE.md itself is created only if missing (it doubles as the user's /memory file, so it
# is never replaced — /memory notes must survive). Existing installs just get the import line
# prepended; any old-template text left behind is the user's to prune (lossless by design).
CLAUDE_IMPORT='@~/.claude/CLAUDE.addon.md'
if [ ! -f "$PERSIST_DIR/CLAUDE.md" ]; then
    printf '%s\n\n# Your notes\n\nAdd project notes here (or via /memory in a session) - the add-on will not overwrite this file.\n' "$CLAUDE_IMPORT" > "$PERSIST_DIR/CLAUDE.md"
elif ! grep -qF "$CLAUDE_IMPORT" "$PERSIST_DIR/CLAUDE.md"; then
    printf '%s\n\n%s\n' "$CLAUDE_IMPORT" "$(cat "$PERSIST_DIR/CLAUDE.md")" > "$PERSIST_DIR/CLAUDE.md"
fi

# Persistence symlinks — keep Claude auth and config across container rebuilds
[ ! -L /root/.claude ] && { rm -rf /root/.claude; ln -s "$PERSIST_DIR" /root/.claude; }
[ ! -L /root/.config/claude-code ] && { rm -rf /root/.config/claude-code; ln -s "$PERSIST_DIR/config" /root/.config/claude-code; }
[ ! -L /root/.claude.json ] && { touch "$PERSIST_DIR/.claude.json"; rm -f /root/.claude.json; ln -s "$PERSIST_DIR/.claude.json" /root/.claude.json; }

# One-time scrub: older versions (and the since-removed update_mcp_token bashrc helper)
# persisted the Supervisor token into the add-on's "homeassistant" MCP server config. Those
# files are symlinked into /homeassistant, i.e. captured by HA backups — remove the token at
# rest. Scoped to the server this add-on manages; user-added MCP servers are never touched.
# The MCP server gets the token from the exported HOMEASSISTANT_* env vars instead.
for f in "$PERSIST_DIR/settings.json" "$PERSIST_DIR/.claude.json"; do
    [ -s "$f" ] || continue
    if jq -e '(.mcpServers.homeassistant.env // {}) | (has("HOMEASSISTANT_TOKEN") or has("HASS_TOKEN"))' "$f" > /dev/null 2>&1; then
        if jq '.mcpServers.homeassistant.env |= del(.HOMEASSISTANT_TOKEN, .HASS_TOKEN)' \
            "$f" > /tmp/scrub.tmp 2>/dev/null && mv /tmp/scrub.tmp "$f"; then
            echo "[INFO] Removed legacy Supervisor token from $(basename "$f")"
        else
            echo "[WARN] Could not scrub legacy token from $(basename "$f") (continuing)"
        fi
    fi
done

# Persist ~/.local/bin and ~/.local/share/claude across container rebuilds.
# claude update stores symlinks in local-bin and actual version binaries in local-share-claude.
# Without persisting both, the symlink survives but points to a missing binary after rebuild.
mkdir -p "$PERSIST_DIR/local-bin"
[ ! -L /root/.local/bin ] && { rm -rf /root/.local/bin; ln -s "$PERSIST_DIR/local-bin" /root/.local/bin; }
# Remove stale claude from local-bin — AppArmor blocks exec from /root/.local/bin/
rm -f "$PERSIST_DIR/local-bin/claude" 2>/dev/null || true

# Remove native claude installation — causes "multiple installations" conflict with npm-global.
# No longer persisted; npm-global is the sole update path.
rm -rf /root/.local/share/claude 2>/dev/null || true
rm -rf "$PERSIST_DIR/local-share-claude" 2>/dev/null || true

# Report active version (npm-global/bin is first in PATH, so updated version is used automatically)
if [ -f "$NPM_GLOBAL_DIR/bin/claude" ]; then
    echo "[INFO] Using npm-updated Claude Code: $(claude --version 2>/dev/null)"
fi

# Claude Code's bundled runtime (Bun) requires SSE4.2 on x86-64. Virtualized CPUs that
# mask it (e.g. Proxmox's default kvm64 CPU type) make claude crash instantly with SIGILL.
# Warn but still start the terminal so the message is visible.
if [ "$(uname -m)" = "x86_64" ] && ! grep -qm1 sse4_2 /proc/cpuinfo 2>/dev/null; then
    echo '[WARN] This CPU does not advertise SSE4.2 — Claude Code will likely crash on launch.'
    echo '[WARN] Proxmox/QEMU users: set the VM CPU type to "host" (not kvm64) and restart the VM.'
fi

# Read options from HA config
FONT_SIZE=$(jq -r '.terminal_font_size // 14' /data/options.json)
THEME=$(jq -r --arg d dark '.terminal_theme // $d' /data/options.json)
SESSION_PERSIST=$(jq -r '.session_persistence // true' /data/options.json)
ENABLE_MCP=$(jq -r '.enable_mcp // true' /data/options.json)
ENABLE_PLAYWRIGHT=$(jq -r '.enable_playwright_mcp // false' /data/options.json)
PLAYWRIGHT_HOST=$(jq -r --arg d '' '.playwright_cdp_host // $d' /data/options.json)
WORKING_DIR=$(jq -r --arg d /homeassistant '.working_directory // $d' /data/options.json)

# Auto-detect Playwright Browser hostname if not explicitly set
if [ -z "$PLAYWRIGHT_HOST" ] && [ "$ENABLE_PLAYWRIGHT" = "true" ]; then
    echo '[INFO] Auto-detecting Playwright Browser hostname...'
    PLAYWRIGHT_HOST=$(curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/addons \
        | jq -r --arg s1 playwright-browser --arg s2 _playwright-browser \
          '.data.addons[] | select(.slug | (endswith($s1) or endswith($s2))) | .hostname' | head -1)
    if [ -n "$PLAYWRIGHT_HOST" ] && [ "$PLAYWRIGHT_HOST" != "null" ]; then
        echo "[INFO] Found Playwright Browser: $PLAYWRIGHT_HOST"
    else
        echo '[WARN] Playwright Browser add-on not found, using default hostname'
        PLAYWRIGHT_HOST="playwright-browser"
    fi
fi

# Auto-update Claude Code on startup if enabled
AUTO_UPDATE=$(jq -r '.auto_update_claude // false' /data/options.json)
if [ "$AUTO_UPDATE" = "true" ]; then
    CURRENT_VER=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    LATEST_VER=$(timeout 30 npm show @anthropic-ai/claude-code version 2>/dev/null || true)
    if [ -n "$LATEST_VER" ] && [ -n "$CURRENT_VER" ] && [ "$CURRENT_VER" != "$LATEST_VER" ]; then
        echo "[INFO] Updating Claude Code from $CURRENT_VER to $LATEST_VER..."
        # Install into the writable persisted prefix — avoids read-only Docker layer restriction
        # that blocks `claude update` (which tries to update the npm global in /usr/local)
        npm install -g "@anthropic-ai/claude-code@$LATEST_VER" \
            --prefix "$NPM_GLOBAL_DIR" --no-fund --no-audit 2>&1 || true
        echo "[INFO] Claude Code update complete: $(claude --version 2>/dev/null)"
    else
        echo "[INFO] Claude Code $CURRENT_VER is up to date"
    fi
fi

# Set Claude model. Pick one from the dropdown, or choose "custom" and put any model id in
# model_custom (so new models work with no add-on update). "default" leaves it unset, so
# Claude Code uses your account/subscription default and in-session /model keeps working.
MODEL=$(jq -r '.model // "default"' /data/options.json)
MODEL_CUSTOM=$(jq -r '.model_custom // ""' /data/options.json)
case "$MODEL" in
    custom)  EFFECTIVE_MODEL="$MODEL_CUSTOM" ;;
    default) EFFECTIVE_MODEL="" ;;
    *)       EFFECTIVE_MODEL="$MODEL" ;;
esac
if [ "$MODEL" = "custom" ] && [ -z "$MODEL_CUSTOM" ]; then
    echo "[WARN] model is 'custom' but model_custom is empty — falling back to the account default"
fi
if [ -n "$EFFECTIVE_MODEL" ]; then
    export ANTHROPIC_MODEL="$EFFECTIVE_MODEL"
    echo "[INFO] Using Claude model: $EFFECTIVE_MODEL"
else
    echo "[INFO] Using Claude Code's default model (pick one in config, or use /model in-session)"
fi

# Configure MCP servers
claude mcp remove homeassistant -s user 2>/dev/null || true
claude mcp remove playwright -s user 2>/dev/null || true

if [ "$ENABLE_MCP" = "true" ]; then
    claude mcp add-json homeassistant '{"command":"ha-mcp"}' -s user \
        || echo '[WARN] Failed to register Home Assistant MCP server (continuing)'
    SETTINGS_FILE=/root/.claude/settings.json
    # add-json writes user-scope config to ~/.claude.json, not settings.json — ensure it exists
    # before the jq edits below, otherwise jq exits non-zero and `set -e` aborts startup
    [ -f "$SETTINGS_FILE" ] || echo '{}' > "$SETTINGS_FILE"
    # Pre-authorize ha-mcp's read-only tools (no confirmation). Write/management tools
    # (ha_call_service, ha_config_set_*, ha_bulk_control, ha_restart, ha_remove_*, etc.)
    # are deliberately NOT listed, so they still prompt for confirmation.
    ALLOWED_TOOLS='[
      "mcp__homeassistant__ha_get_overview",
      "mcp__homeassistant__ha_search_entities",
      "mcp__homeassistant__ha_get_state",
      "mcp__homeassistant__ha_deep_search",
      "mcp__homeassistant__ha_list_services",
      "mcp__homeassistant__ha_get_history",
      "mcp__homeassistant__ha_get_logs",
      "mcp__homeassistant__ha_get_automation_traces",
      "mcp__homeassistant__ha_eval_template",
      "Read(/homeassistant/**)",
      "Read(/config/**)",
      "Read(/share/**)",
      "Read(/media/**)",
      "Glob(/homeassistant/**)",
      "Glob(/config/**)",
      "Grep(/homeassistant/**)",
      "Grep(/config/**)"
    ]'
    jq --argjson tools "$ALLOWED_TOOLS" \
        '.permissions.allow = ($tools + (.permissions.allow // []) | unique)' \
        "$SETTINGS_FILE" > /tmp/settings.tmp && mv /tmp/settings.tmp "$SETTINGS_FILE"
    # The ha-mcp subprocess gets the HA connection from the exported HOMEASSISTANT_* env vars
    # (lines 8-9), which it inherits. We deliberately do NOT persist the Supervisor token into
    # settings.json: that file is symlinked into the backed-up/shared HA config dir, so a written
    # token would leak into HA backups and any add-on mapping homeassistant_config:ro.
    echo '[INFO] MCP configured with Home Assistant integration (ha-mcp)'
    echo '[INFO] Pre-authorized read-only MCP tools'
else
    echo '[INFO] MCP disabled'
fi

if [ "$ENABLE_PLAYWRIGHT" = "true" ]; then
    claude mcp add-json playwright \
        '{"command":"npx","args":["--no-install","@playwright/mcp","--cdp-endpoint","http://'"$PLAYWRIGHT_HOST"':9222"]}' \
        -s user \
        || echo '[WARN] Failed to register Playwright MCP server (continuing)'
    echo "[INFO] Playwright MCP enabled (CDP: http://${PLAYWRIGHT_HOST}:9222)"
    echo '[INFO] Make sure the Playwright Browser add-on is installed and running'
else
    echo '[INFO] Playwright MCP disabled'
fi

# Set terminal colors based on theme
if [ "$THEME" = "dark" ]; then
    COLORS='background=#1e1e2e,foreground=#cdd6f4,cursor=#f5e0dc'
else
    COLORS='background=#eff1f5,foreground=#4c4f69,cursor=#dc8a78'
fi

# Set shell command based on session persistence setting.
# tmux (not dtach): ttyd's frontend resets the browser-side terminal on every ingress
# reconnect, and dtach's winch redraw restores neither content nor terminal modes — every
# websocket blip left a blank screen. tmux fully re-establishes terminal state on reattach
# (alternate screen, mouse tracking, complete repaint), so Claude's fullscreen UI survives
# tab closes and reconnects with its scrollable history intact.
if [ "$SESSION_PERSIST" = "true" ]; then
    SHELL_CMD='tmux -u new-session -A -s claude bash --login'
else
    SHELL_CMD='bash --login'
fi

# Fullscreen rendering (research preview, Claude Code >= 2.1.89): the conversation lives in
# an in-app mouse-wheel-scrollable buffer instead of terminal scrollback — which the classic
# renderer erases on every repaint (CSI 3 J), the root cause of "can't scroll back" reports.
# Ctrl+O opens the full searchable transcript. Opt out per-session with /tui default.
export CLAUDE_CODE_NO_FLICKER=1
# Convention shared with other HA terminal add-ons for ttyd-conditional shell config
export TTYD=1

# OSC 52 clipboard bridge: serve ttyd's own index page with a small script appended that
# forwards OSC 52 clipboard writes (Claude's in-app copy, tmux set-clipboard) to the browser
# clipboard — stock ttyd drops them. Extracted from a throwaway ttyd instance so the page
# always matches the running binary; on any failure we fall back to the stock page.
TTYD_INDEX_ARGS=""
TMP_SOCK=/tmp/ttyd-extract.sock
rm -f "$TMP_SOCK"
ttyd -i "$TMP_SOCK" sh -c 'sleep 30' > /dev/null 2>&1 &
TTYD_TMP_PID=$!
for _ in $(seq 1 20); do
    [ -S "$TMP_SOCK" ] && curl -sf --unix-socket "$TMP_SOCK" http://localhost/ -o /tmp/ttyd-index.orig.html && break
    sleep 0.25
done
kill "$TTYD_TMP_PID" 2>/dev/null || true
rm -f "$TMP_SOCK"
if [ -s /tmp/ttyd-index.orig.html ] && grep -q '</body>' /tmp/ttyd-index.orig.html; then
    if python3 - << 'PYEOF'
snippet = open('/usr/local/share/claudecode/osc52.html').read()
orig = open('/tmp/ttyd-index.orig.html').read()
open('/tmp/ttyd-index.html', 'w').write(orig.replace('</body>', snippet + '</body>', 1))
PYEOF
    then
        TTYD_INDEX_ARGS="-I /tmp/ttyd-index.html"
        echo '[INFO] OSC 52 clipboard bridge enabled'
    fi
fi
[ -z "$TTYD_INDEX_ARGS" ] && echo '[WARN] OSC 52 clipboard bridge unavailable — using stock ttyd page (Shift+drag copy still works)'

# Background update checker — runs hourly. When auto_update_claude is on it installs new
# Claude Code releases as they land (no restart needed); otherwise it just notifies.
# Installing into the npm prefix is safe mid-session: an already-running `claude` keeps the
# code it loaded at startup, and the next `claude` invocation picks up the new version.
(while true; do
    IV=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    LV=$(timeout 30 npm show @anthropic-ai/claude-code version 2>/dev/null || true)
    if [ -n "$LV" ] && [ -n "$IV" ] && [ "$IV" != "$LV" ]; then
        if [ "$AUTO_UPDATE" = "true" ]; then
            echo "[INFO] Auto-updating Claude Code $IV -> $LV (active sessions keep $IV until restarted)..."
            npm install -g "@anthropic-ai/claude-code@$LV" \
                --prefix "$NPM_GLOBAL_DIR" --no-fund --no-audit 2>&1 || true
            echo "[INFO] Claude Code now at: $(claude --version 2>/dev/null)"
            rm -f "$PERSIST_DIR/.update_notice" 2>/dev/null
            printf '{"notification_id":"claude_code_update"}' \
                | curl -sf -X POST \
                  -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
                  -H "Content-Type: application/json" \
                  -d @- http://supervisor/core/api/services/persistent_notification/dismiss 2>/dev/null || true
        else
            echo "$LV" > "$PERSIST_DIR/.update_notice"
            echo "[INFO] Claude Code update available: $LV (installed: $IV)"
            printf '{"title":"Claude Code Update Available","message":"Version %s is available (installed: %s). Restart the add-on or run claude-update to install.","notification_id":"claude_code_update"}' "$LV" "$IV" \
                | curl -sf -X POST \
                  -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
                  -H "Content-Type: application/json" \
                  -d @- http://supervisor/core/api/services/persistent_notification/create 2>/dev/null || true
        fi
    else
        rm -f "$PERSIST_DIR/.update_notice" 2>/dev/null
        printf '{"notification_id":"claude_code_update"}' \
            | curl -sf -X POST \
              -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
              -H "Content-Type: application/json" \
              -d @- http://supervisor/core/api/services/persistent_notification/dismiss 2>/dev/null || true
    fi
    sleep 3600
done) &

# Start web terminal
cd "$WORKING_DIR" 2>/dev/null || cd /homeassistant
exec ttyd --port 7681 --writable --ping-interval 30 --max-clients 5 \
    $TTYD_INDEX_ARGS \
    -t fontSize="$FONT_SIZE" \
    -t fontFamily=Monaco,Consolas,monospace \
    -t scrollback=20000 \
    -t disableLeaveAlert=true \
    -t "theme=$COLORS" \
    $SHELL_CMD
