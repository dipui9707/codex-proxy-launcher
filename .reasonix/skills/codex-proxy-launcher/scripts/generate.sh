#!/bin/bash
# ─────────────────────────────────────────────────────────────
# Codex Proxy Launcher — generator
# Reads proxy.conf and writes an OS-native launcher.
#
# This file is NOT meant to be run directly by the user.
# The agent reads it as a template and adapts paths before
# writing the launcher to the user's target directory.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

# ── Shared constants (same across all platforms) ─────────────
# proxy.conf format:
#   PROXY_HOST=127.0.0.1
#   PROXY_PORT=7897
#
# Bypass lists — two formats must both be correct:
#   CLI flag (Chromium): semicolons, <local> token
#   Env var (Unix):      commas, CIDR notation

BYPASS_CHROMIUM='<local>;localhost;127.0.0.1;::1;*.local;10.*;192.168.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*'

NO_PROXY_VALUE='127.0.0.1,localhost,::1,*.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12'

# ─────────────────────────────────────────────────────────────
# macOS: generate CodexProxy.app bundle
# ─────────────────────────────────────────────────────────────
generate_macos() {
    local target_dir="${1:-.}"
    local app_dir="$target_dir/CodexProxy.app"

    mkdir -p "$app_dir/Contents/MacOS"

    # --- Info.plist ---
    # Standard fields. CFBundleExecutable MUST match the script filename.
    cat > "$app_dir/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CodexProxy</string>
  <key>CFBundleIdentifier</key>
  <string>com.codex.proxy-launcher</string>
  <key>CFBundleName</key>
  <string>Codex Proxy</string>
  <key>CFBundleDisplayName</key>
  <string>Codex Proxy</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
</dict>
</plist>
PLIST

    # --- Launcher script ---
    CODEX_BIN="/Applications/Codex.app/Contents/MacOS/Codex"
    cat > "$app_dir/Contents/MacOS/CodexProxy" << 'SCRIPT'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONF_FILE="$APP_DIR/../proxy.conf"
CODEX_BIN="__CODEX_BIN__"

if [[ -f "$CONF_FILE" ]]; then
  source "$CONF_FILE"
else
  PROXY_HOST="127.0.0.1"
  PROXY_PORT="7897"
fi
PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"

# --- preflight ---
if [[ ! -x "$CODEX_BIN" ]]; then
  osascript -e 'display dialog "Codex.app not found.\n\nExpected at: '"$CODEX_BIN"'\n\nReinstall or move Codex.app to /Applications." buttons {"OK"} default button "OK" with icon stop with title "Codex Proxy"'
  exit 1
fi

if ! command -v nc &>/dev/null; then
  osascript -e 'display dialog "nc (netcat) is required but not installed." buttons {"OK"} default button "OK" with icon stop with title "Codex Proxy"'
  exit 1
fi

if ! nc -z -w 2 "$PROXY_HOST" "$PROXY_PORT" 2>/dev/null; then
  osascript -e 'display dialog "Proxy '"$PROXY_URL"' not reachable.\n\nStart your proxy software first, then try again.\n\nEdit proxy.conf to change the proxy address." buttons {"OK"} default button "OK" with icon stop with title "Codex Proxy"'
  exit 1
fi

if pgrep -f "$CODEX_BIN" &>/dev/null; then
  osascript -e 'display dialog "Codex is already running.\n\nQuit Codex completely (Cmd+Q), then open Codex Proxy again.\n\nProxy flags only take effect on a fresh launch." buttons {"OK"} default button "OK" with icon caution with title "Codex Proxy"'
  exit 0
fi

# --- launch ---
export HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL" ALL_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$PROXY_URL"
export NO_PROXY="__NO_PROXY__" no_proxy="__NO_PROXY__"

exec "$CODEX_BIN" \
  --proxy-server="$PROXY_URL" \
  --proxy-bypass-list="__BYPASS_CHROMIUM__"
SCRIPT

    # Replace placeholders (sed -i.bak + rm works with both GNU and BSD sed)
    sed -i.bak "s|__CODEX_BIN__|$CODEX_BIN|g" "$app_dir/Contents/MacOS/CodexProxy"
    sed -i.bak "s|__NO_PROXY__|$NO_PROXY_VALUE|g" "$app_dir/Contents/MacOS/CodexProxy"
    sed -i.bak "s|__BYPASS_CHROMIUM__|$BYPASS_CHROMIUM|g" "$app_dir/Contents/MacOS/CodexProxy"
    rm -f "$app_dir/Contents/MacOS/CodexProxy.bak"

    chmod +x "$app_dir/Contents/MacOS/CodexProxy"
    echo "✅ macOS: $app_dir"
}

# ─────────────────────────────────────────────────────────────
# Linux: generate codex-proxy.sh + codex-proxy.desktop
# ─────────────────────────────────────────────────────────────
generate_linux() {
    local target_dir="${1:-.}"

    cat > "$target_dir/codex-proxy.sh" << 'SCRIPT'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_FILE="$SCRIPT_DIR/proxy.conf"

# Probe common Codex install paths; fall back to $PATH
CODEX_BIN=""
for c in /opt/Codex/codex /opt/Codex/app/codex \
         "$HOME/.local/share/Codex/codex" \
         /usr/bin/codex /usr/local/bin/codex; do
  [[ -x "$c" ]] && { CODEX_BIN="$c"; break; }
done
[[ -z "$CODEX_BIN" ]] && CODEX_BIN="$(which codex 2>/dev/null || true)"

if [[ -f "$CONF_FILE" ]]; then
  source "$CONF_FILE"
else
  PROXY_HOST="127.0.0.1"
  PROXY_PORT="7897"
fi
PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"

# --- preflight ---
if [[ -z "$CODEX_BIN" ]] || [[ ! -x "$CODEX_BIN" ]]; then
  echo "ERROR: Codex binary not found." >&2
  echo "Searched: /opt/Codex/, ~/.local/share/Codex/, /usr/bin/, /usr/local/bin/" >&2
  echo "Set CODEX_BIN at the top of this script if installed elsewhere." >&2
  notify-send "Codex Proxy" "Codex binary not found." 2>/dev/null || true
  exit 1
fi

NC=""
command -v ncat &>/dev/null && NC="ncat"
command -v nc &>/dev/null && NC="nc"
[[ -z "$NC" ]] && { echo "ERROR: netcat required." >&2; exit 1; }

if ! $NC -z -w 2 "$PROXY_HOST" "$PROXY_PORT" 2>/dev/null; then
  echo "ERROR: Proxy $PROXY_URL not reachable." >&2
  notify-send "Codex Proxy" "Proxy $PROXY_URL not reachable." 2>/dev/null || true
  exit 1
fi

if pgrep -f "codex" &>/dev/null; then
  echo "ERROR: Codex is already running. Quit it first." >&2
  notify-send "Codex Proxy" "Codex already running — quit it first." 2>/dev/null || true
  exit 1
fi

# --- launch ---
export HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL" ALL_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$PROXY_URL"
export NO_PROXY="__NO_PROXY__" no_proxy="__NO_PROXY__"

exec "$CODEX_BIN" \
  --proxy-server="$PROXY_URL" \
  --proxy-bypass-list="__BYPASS_CHROMIUM__"
SCRIPT

    sed -i.bak "s|__NO_PROXY__|$NO_PROXY_VALUE|g" "$target_dir/codex-proxy.sh"
    sed -i.bak "s|__BYPASS_CHROMIUM__|$BYPASS_CHROMIUM|g" "$target_dir/codex-proxy.sh"
    rm -f "$target_dir/codex-proxy.sh.bak"
    chmod +x "$target_dir/codex-proxy.sh"

    # --- .desktop entry ---
    cat > "$target_dir/codex-proxy.desktop" << DESKTOP
[Desktop Entry]
Name=Codex Proxy
Comment=Launch Codex with proxy
Exec=$target_dir/codex-proxy.sh
Type=Application
Categories=Development;
Terminal=false
DESKTOP

    echo "✅ Linux: $target_dir/codex-proxy.sh + codex-proxy.desktop"
    echo "   Install to applications menu:"
    echo "   mkdir -p ~/.local/share/applications"
    echo "   cp $target_dir/codex-proxy.desktop ~/.local/share/applications/"
}

# ─────────────────────────────────────────────────────────────
# Windows: generate CodexProxy.bat
# ─────────────────────────────────────────────────────────────
generate_windows() {
    local target_dir="${1:-.}"

    cat > "$target_dir/CodexProxy.bat" << 'BAT'
@echo off
setlocal enabledelayedexpansion
title Codex Proxy Launcher

set "SCRIPT_DIR=%~dp0"
set "CONF_FILE=%SCRIPT_DIR%proxy.conf"

:: Load config
set "PROXY_HOST=127.0.0.1"
set "PROXY_PORT=7897"
if exist "%CONF_FILE%" (
    for /f "usebackq tokens=1,2 delims==" %%a in ("%CONF_FILE%") do (
        if "%%a"=="PROXY_HOST" set "PROXY_HOST=%%b"
        if "%%a"=="PROXY_PORT" set "PROXY_PORT=%%b"
    )
)
set "PROXY_URL=http://%PROXY_HOST%:%PROXY_PORT%"

:: Find Codex
set "CODEX_BIN="
for %%p in (
    "%LOCALAPPDATA%\Programs\Codex\Codex.exe"
    "%ProgramFiles%\Codex\Codex.exe"
    "%USERPROFILE%\AppData\Local\Programs\codex\Codex.exe"
) do ( if exist "%%~p" set "CODEX_BIN=%%~p" )
if "%CODEX_BIN%"=="" (
    for /f "delims=" %%p in ('where codex 2^>nul') do (
        set "CODEX_BIN=%%p" & goto :found
    )
    :found
)
if "%CODEX_BIN%"=="" (
    echo [ERROR] Codex.exe not found.
    pause & exit /b 1
)

:: Check proxy
echo Checking proxy %PROXY_URL% ...
powershell -NoProfile -Command "$t=New-Object Net.Sockets.TcpClient;try{$t.Connect('%PROXY_HOST%',%PROXY_PORT%);$t.Close();exit 0}catch{exit 1}" >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Proxy %PROXY_URL% not reachable. Start your proxy software first.
    pause & exit /b 1
)

:: Check Codex not already running
tasklist /FI "IMAGENAME eq Codex.exe" 2>nul | find /I "Codex.exe" >nul
if %errorlevel% equ 0 (
    echo [WARNING] Codex already running. Quit it completely, then re-launch.
    pause & exit /b 0
)

:: Launch
set "HTTP_PROXY=%PROXY_URL%" & set "HTTPS_PROXY=%PROXY_URL%" & set "ALL_PROXY=%PROXY_URL%"
set "http_proxy=%PROXY_URL%" & set "https_proxy=%PROXY_URL%" & set "all_proxy=%PROXY_URL%"
set "NO_PROXY=__NO_PROXY__" & set "no_proxy=__NO_PROXY__"

echo Launching Codex with proxy %PROXY_URL% ...
start "" "%CODEX_BIN%" --proxy-server="%PROXY_URL%" --proxy-bypass-list="__BYPASS_CHROMIUM__"
timeout /t 2 >nul
exit
BAT

    # Replace placeholders (sed -i.bak + rm works with both GNU and BSD sed)
    sed -i.bak "s|__NO_PROXY__|$NO_PROXY_VALUE|g" "$target_dir/CodexProxy.bat"
    sed -i.bak "s|__BYPASS_CHROMIUM__|$BYPASS_CHROMIUM|g" "$target_dir/CodexProxy.bat"
    rm -f "$target_dir/CodexProxy.bat.bak"

    echo "✅ Windows: $target_dir/CodexProxy.bat"
}

# ── proxy.conf template ───────────────────────────────────────
generate_config() {
    local target_dir="${1:-.}"
    if [[ -f "$target_dir/proxy.conf" ]]; then
        echo "⚠️  proxy.conf already exists, skipping."
        return
    fi
    cat > "$target_dir/proxy.conf" << 'EOF'
# Codex Proxy Config
# Edit this file to change proxy settings.
# Launcher picks up changes on next launch — no need to regenerate.

PROXY_HOST=127.0.0.1
PROXY_PORT=7897
EOF
    echo "✅ proxy.conf: $target_dir/proxy.conf"
}

# ── Main (called by agent with explicit platform) ─────────────
if [[ "${1:-}" == "--help" ]] || [[ $# -eq 0 ]]; then
    echo "Usage: $0 <macos|linux|windows> [target-dir]"
    echo "Generates a Codex proxy launcher for the given platform."
    exit 0
fi

PLATFORM="$1"
TARGET="${2:-.}"

generate_config "$TARGET"

case "$PLATFORM" in
    macos|darwin)   generate_macos "$TARGET" ;;
    linux)          generate_linux "$TARGET" ;;
    windows|win)    generate_windows "$TARGET" ;;
    *)
        echo "Unknown platform: $PLATFORM"
        echo "Use: macos, linux, or windows"
        exit 1
        ;;
esac
