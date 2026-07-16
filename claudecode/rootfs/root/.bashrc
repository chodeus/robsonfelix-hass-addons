# Inside tmux, keep the TERM tmux sets (screen-256color) — overriding it desyncs
# terminfo between apps and tmux. Outside tmux (session_persistence: false), set it.
if [ -z "$TMUX" ]; then
    export TERM=xterm-256color
fi
export LANG=C.UTF-8
export PATH="/homeassistant/.claudecode/npm-global/bin:/root/.local/bin:$PATH"
# In bash, track the window size on resize so COLUMNS/LINES follow the browser.
# Guarded: this rc is also sourced by the busybox /bin/sh login shell, which has no `shopt`.
if [ -n "$BASH_VERSION" ]; then
    shopt -s checkwinsize
fi
PS1='\[\033[1;36m\]claude-code\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ '

# Wrapper: intercept `claude update` (built-in updater fails on read-only image layer)
claude() {
    if [ "$1" = "update" ]; then
        local _prefix=/homeassistant/.claudecode/npm-global
        local _stub="$_prefix/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
        local _free _err _v _rc
        echo "Updating Claude Code via add-on method (npm --prefix)..."

        # Claude Code ships the ~256MB native binary as a separate platform package and npm
        # keeps the outgoing copy until the new one lands, so check for room up front rather
        # than half-install into a full config partition. Skipped if df can't be read — this
        # is a convenience pre-flight, not a guard worth blocking a good update over.
        _free=$(df -Pm /homeassistant 2>/dev/null | awk 'NR==2 {print $4}')
        if [ -n "$_free" ] && [ "$_free" -lt 600 ]; then
            echo "[ERROR] Only ${_free}MB free on /homeassistant; this update needs ~600MB. Aborting."
            return 1
        fi

        # --foreground-scripts: the postinstall (install.cjs) is what puts the native binary
        # in place. npm hides lifecycle output, so without this a failed placement still
        # prints "changed 2 packages" and reads as a clean install.
        npm install -g @anthropic-ai/claude-code@latest \
            --prefix "$_prefix" \
            --foreground-scripts --no-fund --no-audit 2>&1
        hash -r 2>/dev/null

        # Never put `command` between timeout and claude: `timeout` is an external binary, so
        # it execs the shell builtin as a program (ENOENT, exit 127) and EVERY update reports
        # failure. timeout resolves claude from PATH, which cannot re-enter this function.
        # Declare _v before assigning: `local _v=$(...)` would capture local's status, not the
        # command's. _err must never be empty either — `2>""` fails the redirect and fakes a
        # failed update the same way.
        _err=$(mktemp 2>/dev/null) || _err=/tmp/claude-update.err
        _v=$(timeout 30 claude --version </dev/null 2>"$_err")
        _rc=$?
        if [ "$_rc" -eq 0 ] && [ -n "$_v" ]; then
            echo "Done: $_v"
            rm -f "$_err"
            return 0
        fi

        # Report what actually happened; only name a cause that the host confirms.
        echo "[ERROR] Claude Code was installed but does not run (exit $_rc)."
        [ -s "$_err" ] && sed 's/^/[ERROR]   /' "$_err"
        rm -f "$_err"
        if [ -f "$_stub" ] && [ "$(stat -c %s "$_stub" 2>/dev/null || echo 0)" -lt 4096 ]; then
            echo "[ERROR] The native binary is not installed — postinstall did not complete."
            echo "[ERROR] The npm output above has the reason."
        elif [ "$_rc" -eq 132 ] || [ "$_rc" -eq 124 ] || ! grep -qm1 sse4_2 /proc/cpuinfo 2>/dev/null; then
            echo "[ERROR] This host's CPU may lack SSE4.2, which Claude Code requires (Nehalem+)."
            echo "[ERROR] Proxmox/QEMU: set the VM CPU type to \"host\", then fully STOP and START the VM."
        fi
        echo "[ERROR] Roll back to the built-in version with:"
        echo "        npm uninstall -g @anthropic-ai/claude-code --prefix $_prefix; hash -r"
        return 1
    fi
    command claude "$@"
}

# Aliases
alias ll='ls -la'
alias c='claude'
alias cc='claude --continue'
alias ha-config='cd /homeassistant'
# tail, not cat: home-assistant.log can be tens/hundreds of MB and a full read into a Claude
# session can burn an entire context window. Use `ha core logs` or a bigger tail for more.
alias ha-logs='tail -n 200 /homeassistant/home-assistant.log 2>/dev/null || echo "Log not found"'
# Reuses the claude() wrapper above (npm --prefix install + smoke test + recovery hint)
alias claude-update='claude update'

source /root/.claude-notify.sh
