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
    # Prepend the import line, preserving the user's existing notes. Read into a variable
    # FIRST so a read error (transient FS/mount fault) can't collapse $(cat) to empty and
    # overwrite the file with just the import line — this is the user's /memory file. Write
    # to a temp in the same dir and rename so an interrupt can't truncate the live file.
    if EXISTING=$(cat "$PERSIST_DIR/CLAUDE.md"); then
        printf '%s\n\n%s\n' "$CLAUDE_IMPORT" "$EXISTING" > "$PERSIST_DIR/CLAUDE.md.tmp" \
            && mv "$PERSIST_DIR/CLAUDE.md.tmp" "$PERSIST_DIR/CLAUDE.md" \
            || { rm -f "$PERSIST_DIR/CLAUDE.md.tmp" 2>/dev/null; echo '[WARN] Could not prepend CLAUDE.md import line (leaving your notes untouched)'; }
    else
        echo '[WARN] Could not read CLAUDE.md — leaving it untouched'
    fi
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
    # Temp file in the SAME dir as the target so the mv is an atomic rename, not a
    # cross-device copy+unlink (/tmp is a different filesystem from the /homeassistant
    # bind mount — a SIGKILL mid-copy would truncate the persisted auth/state file).
    if jq -e '(.mcpServers.homeassistant.env // {}) | (has("HOMEASSISTANT_TOKEN") or has("HASS_TOKEN"))' "$f" > /dev/null 2>&1; then
        if jq '.mcpServers.homeassistant.env |= del(.HOMEASSISTANT_TOKEN, .HASS_TOKEN)' \
            "$f" > "$f.tmp.$$" 2>/dev/null && mv "$f.tmp.$$" "$f"; then
            echo "[INFO] Removed legacy Supervisor token from $(basename "$f")"
        else
            rm -f "$f.tmp.$$" 2>/dev/null || true
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

# Report active version (npm-global/bin is first in PATH, so updated version is used automatically).
# timeout-wrapped: a persisted npm-global update that hangs on this host (see the CPU note below)
# would otherwise block startup here, before ttyd ever starts.
if [ -f "$NPM_GLOBAL_DIR/bin/claude" ]; then
    # `|| true`: a broken/hanging persisted binary makes claude exit non-zero (SIGILL 132) or
    # time out (124); without it this bare assignment would abort startup under set -e — the
    # very thing this block warns about. Fall through so the terminal still starts.
    _npm_ver=$(timeout 10 claude --version </dev/null 2>/dev/null || true)
    if [ -n "$_npm_ver" ]; then
        echo "[INFO] Using npm-updated Claude Code: $_npm_ver"
    else
        echo "[WARN] A persisted Claude Code update in $NPM_GLOBAL_DIR is not responding — it may be broken for this CPU"
    fi
fi

# Claude Code ships as a Bun-compiled binary. The Linux x64 builds (glibc and musl) are Bun
# "baseline" builds: they need SSE4.2/POPCNT (Nehalem+), NOT AVX (verified: 2.1.209 embeds
# "Bun v1.4.0 Linux x64 (baseline)"). CPUs that mask SSE4.2 (e.g. Proxmox's default kvm64)
# make claude SIGILL or livelock silently at 100% CPU with no output. Anthropic has shipped
# AVX-requiring x64 builds before (~2.1.126 era; darwin-x64 still is), so a missing AVX2 gets
# an informational note. Warn but still start the terminal so the message is visible.
if [ "$(uname -m)" = "x86_64" ]; then
    if ! grep -qm1 sse4_2 /proc/cpuinfo 2>/dev/null; then
        echo '[WARN] This CPU does not advertise SSE4.2 — Claude Code will crash (SIGILL) or hang silently at 100% CPU.'
        echo '[WARN] Proxmox/QEMU users: set the VM CPU type to "host" (or x86-64-v2+), then fully STOP and START'
        echo '[WARN] the VM (a guest reboot does not repropagate CPU flags). Verify with: grep -m1 -o sse4_2 /proc/cpuinfo'
    elif ! grep -qm1 avx2 /proc/cpuinfo 2>/dev/null; then
        echo '[INFO] CPU lacks AVX2. Current Claude Code Linux builds are Bun "baseline" (SSE4.2-only) and run fine,'
        echo '[INFO] but Anthropic has shipped AVX-requiring builds before. If claude crashes or hangs after an'
        echo '[INFO] update, set the Proxmox VM CPU type to "host" and fully stop/start the VM.'
    fi
fi

# Read options from HA config
FONT_SIZE=$(jq -r '.terminal_font_size // 14' /data/options.json)
THEME=$(jq -r --arg d dark '.terminal_theme // $d' /data/options.json)
# jq's `//` falls back on BOTH null and false, so it silently swallows an explicit `false`
# for a true-defaulted boolean — use an explicit null test for those. `//` is only safe when
# the default is false / a string / a nonzero number (all truthy-or-idempotent in jq).
SESSION_PERSIST=$(jq -r 'if .session_persistence == null then true else .session_persistence end' /data/options.json)
ENABLE_MCP=$(jq -r 'if .enable_mcp == null then true else .enable_mcp end' /data/options.json)
ENABLE_PLAYWRIGHT=$(jq -r 'if .enable_playwright_mcp == null then false else .enable_playwright_mcp end' /data/options.json)
PLAYWRIGHT_HOST=$(jq -r --arg d '' '.playwright_cdp_host // $d' /data/options.json)
WORKING_DIR=$(jq -r --arg d /homeassistant '.working_directory // $d' /data/options.json)
ENABLE_REMOTE_CONTROL=$(jq -r 'if .enable_remote_control == null then false else .enable_remote_control end' /data/options.json)
RC_SESSION_PREFIX=$(jq -r --arg d HomeAssistant '.remote_control_session_prefix // $d' /data/options.json)
RESTRICT_PORT=$(jq -r 'if .restrict_terminal_port == null then false else .restrict_terminal_port end' /data/options.json)

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

# Auto-update Claude Code on startup if enabled.
# Every step is timeout-wrapped (npm and claude can both hang on an incompatible host), the
# new binary is smoke-tested before we trust it, and a failed update is rolled back to the
# previous version (or removed so PATH falls back to the build-verified image binary). The
# CURRENT_VER guard is intentionally NOT required: if the installed binary is broken (empty
# version) we still try to update, since that may be the only path back to a working claude.
AUTO_UPDATE=$(jq -r 'if .auto_update_claude == null then false else .auto_update_claude end' /data/options.json)
if [ "$AUTO_UPDATE" = "true" ]; then
    CURRENT_VER=$(timeout 30 claude --version </dev/null 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    LATEST_VER=$(timeout 30 npm show @anthropic-ai/claude-code version 2>/dev/null || true)
    BAD_VER=$(cat "$PERSIST_DIR/.claude_bad_version" 2>/dev/null || true)
    if [ -n "$LATEST_VER" ] && [ "$CURRENT_VER" != "$LATEST_VER" ] && [ "$LATEST_VER" = "$BAD_VER" ]; then
        # We already installed this exact release and it did not run here — don't churn through
        # install→smoke-fail→rollback on every restart. Run `claude-update` manually to retry.
        echo "[INFO] Claude Code $LATEST_VER is available but a prior update to it did not run on this host — skipping"
    elif [ -n "$LATEST_VER" ] && [ "$CURRENT_VER" != "$LATEST_VER" ]; then
        [ -n "$CURRENT_VER" ] || echo '[WARN] Installed Claude Code is not responding — attempting update as a repair'
        echo "[INFO] Updating Claude Code from ${CURRENT_VER:-unknown} to $LATEST_VER..."
        # Install into the writable persisted prefix — avoids the read-only Docker layer
        # restriction that blocks `claude update` (which targets the npm global in /usr/local).
        timeout 300 npm install -g "@anthropic-ai/claude-code@$LATEST_VER" \
            --prefix "$NPM_GLOBAL_DIR" --foreground-scripts --no-fund --no-audit 2>&1 || true
        hash -r 2>/dev/null || true
        if timeout 30 claude --version </dev/null >/dev/null 2>&1; then
            rm -f "$PERSIST_DIR/.claude_bad_version" 2>/dev/null || true
            echo "[INFO] Claude Code update complete: $(timeout 30 claude --version </dev/null 2>/dev/null)"
        elif [ -n "$CURRENT_VER" ]; then
            echo "[ERROR] Claude Code $LATEST_VER does not run here — rolling back to $CURRENT_VER"
            echo "$LATEST_VER" > "$PERSIST_DIR/.claude_bad_version" 2>/dev/null || true
            timeout 300 npm install -g "@anthropic-ai/claude-code@$CURRENT_VER" \
                --prefix "$NPM_GLOBAL_DIR" --foreground-scripts --no-fund --no-audit 2>&1 || echo '[ERROR] Rollback failed'
            hash -r 2>/dev/null || true
        else
            echo '[ERROR] Update does not run and no previous version known — removing it so PATH falls back to the image binary'
            echo "$LATEST_VER" > "$PERSIST_DIR/.claude_bad_version" 2>/dev/null || true
            npm uninstall -g @anthropic-ai/claude-code --prefix "$NPM_GLOBAL_DIR" 2>/dev/null || rm -f "$NPM_GLOBAL_DIR/bin/claude"
            hash -r 2>/dev/null || true
        fi
    else
        echo "[INFO] Claude Code ${CURRENT_VER:-unknown} is up to date"
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

# Bootstrap the user-scope settings file up front — the MCP pre-authorization AND the Remote
# Control toggle below both edit it, and it is needed even when MCP is disabled. `[ -s ]` (not
# `[ -f ]`) also resets an EMPTY file: jq reads empty input as nothing and the &&mv would
# otherwise silently overwrite settings.json with an empty file on every boot.
SETTINGS_FILE=/root/.claude/settings.json
[ -s "$SETTINGS_FILE" ] || echo '{}' > "$SETTINGS_FILE"

# Health-gate the claude CLI: on a host where the binary hangs or crashes (a broken update, or
# a CPU without SSE4.2) claude invocations must not block startup. If it does not respond within
# 30s, skip MCP setup but still fall through to exec ttyd so the terminal is reachable to debug.
if timeout 30 claude --version </dev/null >/dev/null 2>&1; then
    CLAUDE_OK=true
else
    CLAUDE_OK=false
    echo '[ERROR] claude CLI did not respond within 30s — skipping MCP setup'
    echo '[ERROR] The terminal will still start so you can debug from inside the add-on'
fi

# Configure MCP servers (only when the CLI is healthy)
if [ "$CLAUDE_OK" = "true" ]; then
    timeout 30 claude mcp remove homeassistant -s user </dev/null 2>/dev/null || true
    timeout 30 claude mcp remove playwright -s user </dev/null 2>/dev/null || true
fi

if [ "$CLAUDE_OK" = "true" ] && [ "$ENABLE_MCP" = "true" ]; then
    timeout 30 claude mcp add-json homeassistant '{"command":"ha-mcp"}' -s user </dev/null \
        || echo '[WARN] Failed to register Home Assistant MCP server (continuing)'
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
      "Read(/media/**)"
    ]'
    # NOTE: a Read(path) rule covers ALL file-reading tools (Read, Glob, Grep) — separate
    # Glob(path)/Grep(path) rules are not a valid permission form and current Claude Code
    # warns about them. The strip filter below also removes any left over from older versions.
    # Write to a temp in the same dir and rename (atomic); guard the whole thing so a corrupt
    # or unparseable settings.json degrades to "tools still prompt" instead of aborting startup
    # under set -e (which would crash-loop the add-on — and this terminal is the recovery tool).
    if jq --argjson tools "$ALLOWED_TOOLS" \
        '.permissions.allow = ($tools + ((.permissions.allow // []) | map(select(test("^(Glob|Grep)\\(") | not))) | unique)' \
        "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"; then
        # The ha-mcp subprocess gets the HA connection from the exported HOMEASSISTANT_* env
        # vars, which it inherits. We deliberately do NOT persist the Supervisor token into
        # settings.json: that file is symlinked into the backed-up/shared HA config dir, so a
        # written token would leak into HA backups and any add-on mapping homeassistant_config:ro.
        echo '[INFO] MCP configured with Home Assistant integration (ha-mcp)'
        echo '[INFO] Pre-authorized read-only MCP tools'
    else
        rm -f "$SETTINGS_FILE.tmp" 2>/dev/null || true
        echo '[WARN] Could not pre-authorize MCP tools — settings.json unparseable (continuing)'
    fi
elif [ "$ENABLE_MCP" = "true" ]; then
    echo '[WARN] MCP is enabled but was skipped: the claude CLI is not responding'
else
    echo '[INFO] MCP disabled'
fi

if [ "$CLAUDE_OK" = "true" ] && [ "$ENABLE_PLAYWRIGHT" = "true" ]; then
    timeout 30 claude mcp add-json playwright \
        '{"command":"npx","args":["--no-install","@playwright/mcp","--cdp-endpoint","http://'"$PLAYWRIGHT_HOST"':9222"]}' \
        -s user </dev/null \
        || echo '[WARN] Failed to register Playwright MCP server (continuing)'
    echo "[INFO] Playwright MCP enabled (CDP: http://${PLAYWRIGHT_HOST}:9222)"
    echo '[INFO] Make sure the Playwright Browser add-on is installed and running'
elif [ "$ENABLE_PLAYWRIGHT" = "true" ]; then
    echo '[WARN] Playwright MCP is enabled but was skipped: the claude CLI is not responding'
else
    echo '[INFO] Playwright MCP disabled'
fi

# Remote Control (opt-in): write remoteControlAtStartup into user settings so Claude Code
# auto-starts its remote-control bridge — view/steer this session from claude.ai/code or the
# Claude mobile app. Requires the add-on's Claude Code to be signed into a claude.ai Pro/Max/
# Team/Enterprise account; API-key auth does not support remote control. This edits settings.json
# directly (not via the claude CLI), so it applies even when CLAUDE_OK is false. The del() branch
# runs unconditionally: settings.json persists across restarts (symlinked into /homeassistant),
# so turning the option off must remove the stale key.
if [ "$ENABLE_REMOTE_CONTROL" = "true" ]; then
    if jq '.remoteControlAtStartup = true' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
        && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"; then
        export CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX="$RC_SESSION_PREFIX"
        echo '[INFO] Remote Control enabled — Claude Code will auto-start with remote control'
    else
        rm -f "$SETTINGS_FILE.tmp" 2>/dev/null || true
        echo '[WARN] Could not enable Remote Control — settings.json unparseable (continuing)'
    fi
else
    jq 'del(.remoteControlAtStartup)' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
        && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE" || rm -f "$SETTINGS_FILE.tmp" 2>/dev/null || true
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

# Injected page snippets: serve ttyd's own index page with scripts appended — the OSC 52
# clipboard bridge (forwards Claude's in-app copy and tmux set-clipboard to the browser
# clipboard; stock ttyd drops them) and the mobile touch shim (touch scrolling, long-press
# selection, key bar, keyboard-aware refit, foreground reconnect). Extracted from a throwaway
# ttyd instance so the page always matches the running binary; on any failure we fall back
# to the stock page.
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
snippets = ''
for path in ('/usr/local/share/claudecode/osc52.html',
             '/usr/local/share/claudecode/mobile.html'):
    try:
        snippets += open(path).read()
    except OSError:
        pass
assert snippets
orig = open('/tmp/ttyd-index.orig.html').read()
open('/tmp/ttyd-index.html', 'w').write(orig.replace('</body>', snippets + '</body>', 1))
PYEOF
    then
        TTYD_INDEX_ARGS="-I /tmp/ttyd-index.html"
        echo '[INFO] OSC 52 clipboard bridge + mobile touch shim enabled'
    fi
fi
[ -z "$TTYD_INDEX_ARGS" ] && echo '[WARN] Page snippets unavailable — using stock ttyd page (no touch scrolling; Shift+drag copy still works)'

# Background update checker — runs hourly. When auto_update_claude is on it installs new
# Claude Code releases as they land (no restart needed) and smoke-tests each one, rolling back
# a release that will not run on this host; otherwise it just notifies. `set +e` so one transient
# FS/curl error (e.g. /homeassistant briefly unwritable) can't kill the loop for the container's
# lifetime. Installing into the npm prefix is safe mid-session: a running `claude` keeps the code
# it loaded at startup, and the next invocation picks up the new version.
(set +e
while true; do
    IV=$(timeout 30 claude --version </dev/null 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    LV=$(timeout 30 npm show @anthropic-ai/claude-code version 2>/dev/null || true)
    BAD_VER=$(cat "$PERSIST_DIR/.claude_bad_version" 2>/dev/null)
    if [ -n "$LV" ] && [ "$IV" != "$LV" ]; then
        if [ "$AUTO_UPDATE" = "true" ] && [ "$LV" = "$BAD_VER" ]; then
            # Already installed this exact release and it did not run here — don't retry it hourly.
            :
        elif [ "$AUTO_UPDATE" = "true" ]; then
            echo "[INFO] Auto-updating Claude Code ${IV:-unknown} -> $LV (active sessions keep the running version until restarted)..."
            timeout 300 npm install -g "@anthropic-ai/claude-code@$LV" \
                --prefix "$NPM_GLOBAL_DIR" --foreground-scripts --no-fund --no-audit 2>&1 || true
            hash -r 2>/dev/null
            if timeout 30 claude --version </dev/null >/dev/null 2>&1; then
                echo "[INFO] Claude Code now at: $(timeout 30 claude --version </dev/null 2>/dev/null)"
                rm -f "$PERSIST_DIR/.claude_bad_version" "$PERSIST_DIR/.update_notice" 2>/dev/null
                printf '{"notification_id":"claude_code_update"}' \
                    | curl -sf -X POST \
                      -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
                      -H "Content-Type: application/json" \
                      -d @- http://supervisor/core/api/services/persistent_notification/dismiss 2>/dev/null
            elif [ -n "$IV" ]; then
                echo "[ERROR] Claude Code $LV does not run here — rolling back to $IV"
                echo "$LV" > "$PERSIST_DIR/.claude_bad_version"
                timeout 300 npm install -g "@anthropic-ai/claude-code@$IV" \
                    --prefix "$NPM_GLOBAL_DIR" --foreground-scripts --no-fund --no-audit 2>&1 || echo '[ERROR] Rollback failed'
                hash -r 2>/dev/null
            else
                echo '[ERROR] Update does not run and no previous version — removing it so PATH falls back to the image binary'
                echo "$LV" > "$PERSIST_DIR/.claude_bad_version"
                npm uninstall -g @anthropic-ai/claude-code --prefix "$NPM_GLOBAL_DIR" 2>/dev/null || rm -f "$NPM_GLOBAL_DIR/bin/claude"
                hash -r 2>/dev/null
            fi
        else
            echo "$LV" > "$PERSIST_DIR/.update_notice"
            echo "[INFO] Claude Code update available: $LV (installed: ${IV:-not responding})"
            printf '{"title":"Claude Code Update Available","message":"Version %s is available (installed: %s). Restart the add-on or run claude-update to install.","notification_id":"claude_code_update"}' "$LV" "${IV:-not responding}" \
                | curl -sf -X POST \
                  -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
                  -H "Content-Type: application/json" \
                  -d @- http://supervisor/core/api/services/persistent_notification/create 2>/dev/null
        fi
    else
        rm -f "$PERSIST_DIR/.update_notice" 2>/dev/null
        printf '{"notification_id":"claude_code_update"}' \
            | curl -sf -X POST \
              -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
              -H "Content-Type: application/json" \
              -d @- http://supervisor/core/api/services/persistent_notification/dismiss 2>/dev/null
    fi
    sleep 3600
done) &

# Optional hardening (opt-in, default off): the web terminal (ttyd, port 7681) has no login
# of its own — it trusts HA's ingress auth, and no host port is published. But other add-on
# containers on the internal hassio network can reach 7681 directly and get a root shell that
# carries this add-on's Supervisor token. When restrict_terminal_port is on, firewall 7681 to
# loopback (the healthcheck) + the ingress source only. The ingress source is resolved from the
# `supervisor` hostname — the exact address ingress connects from — so the rule can't be defeated
# by a stale hard-coded IP. Fail OPEN on any error (never brick ingress); the DROP rule is only
# ever added after BOTH ACCEPT rules succeed (the && chain), so a partial failure stays open.
if [ "$RESTRICT_PORT" = "true" ]; then
    INGRESS_SRC=$(python3 -c "import socket; print(socket.gethostbyname('supervisor'))" 2>/dev/null || echo 172.30.32.2)
    if iptables -A INPUT -i lo -j ACCEPT 2>/dev/null \
        && iptables -A INPUT -p tcp --dport 7681 -s "$INGRESS_SRC" -j ACCEPT 2>/dev/null \
        && iptables -A INPUT -p tcp --dport 7681 -j DROP 2>/dev/null; then
        echo "[INFO] Terminal port 7681 restricted to loopback + ingress ($INGRESS_SRC)"
    else
        echo '[WARN] Could not restrict port 7681 (iptables unavailable or blocked) — left open on the internal hassio network'
    fi
fi

# Start web terminal
cd "$WORKING_DIR" 2>/dev/null || cd /homeassistant

# Pre-create the tmux session (detached) so simultaneous first connections all attach to it
# instead of racing `new-session -A` to create it — the loser of that race would otherwise get a
# "duplicate session" dead pane. Clients still run `new-session -A` (SHELL_CMD), which now attaches.
if [ "$SESSION_PERSIST" = "true" ]; then
    tmux -u new-session -d -s claude bash --login 2>/dev/null || true
fi

exec ttyd --port 7681 --writable --ping-interval 30 --max-clients 5 \
    $TTYD_INDEX_ARGS \
    -t fontSize="$FONT_SIZE" \
    -t fontFamily=Monaco,Consolas,monospace \
    -t scrollback=20000 \
    -t disableLeaveAlert=true \
    -t disableResizeOverlay=true \
    -t "theme=$COLORS" \
    $SHELL_CMD
