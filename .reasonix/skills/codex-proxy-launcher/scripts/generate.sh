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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROXY_ICON_ASSET="$SKILL_DIR/assets/codex-proxy.ico"
PROXY_ICON_PNG_ASSET="$SKILL_DIR/assets/codex-proxy.png"
PROXY_ICON_ICNS_ASSET="$SKILL_DIR/assets/codex-proxy.icns"

# ─────────────────────────────────────────────────────────────
# macOS: generate CodexProxy.app bundle
# ─────────────────────────────────────────────────────────────
generate_macos() {
    local target_dir="${1:-.}"
    local app_dir="$target_dir/CodexProxy.app"

    mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

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
  <key>CFBundleIconFile</key>
  <string>codex-proxy</string>
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
    if [[ -f "$PROXY_ICON_ICNS_ASSET" ]]; then
        cp "$PROXY_ICON_ICNS_ASSET" "$app_dir/Contents/Resources/codex-proxy.icns"
    fi
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
    if [[ -f "$PROXY_ICON_PNG_ASSET" ]]; then
        cp "$PROXY_ICON_PNG_ASSET" "$target_dir/codex-proxy.png"
    fi

    # --- .desktop entry ---
    cat > "$target_dir/codex-proxy.desktop" << DESKTOP
[Desktop Entry]
Name=Codex Proxy
Comment=Launch Codex with proxy
Exec=$target_dir/codex-proxy.sh
Icon=$target_dir/codex-proxy.png
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
# Windows: generate CodexProxy.bat + Start-CodexProxy.ps1
# ─────────────────────────────────────────────────────────────
generate_windows() {
    local target_dir="${1:-.}"

    cat > "$target_dir/CodexProxy.bat" << 'BAT'
@echo off
setlocal
title Codex Proxy Launcher

set "SCRIPT_DIR=%~dp0"
set "CONF_FILE=%SCRIPT_DIR%proxy.conf"
set "CHECK_ONLY=0"
set "APP_ID=OpenAI.Codex_2p2nqsd0c76g0!App"
set "BYPASS_CHROMIUM=__BYPASS_CHROMIUM__"
set "NO_PROXY_VALUE=__NO_PROXY__"
if /I "%~1"=="--check" set "CHECK_ONLY=1"

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

:: Check proxy
echo Checking proxy %PROXY_URL% ...
powershell -NoProfile -Command "$t=New-Object Net.Sockets.TcpClient;try{$t.Connect('%PROXY_HOST%',%PROXY_PORT%);$t.Close();exit 0}catch{exit 1}" >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Proxy %PROXY_URL% not reachable. Start your proxy software first.
    if "%CHECK_ONLY%"=="0" pause
    exit /b 1
)

:: Prefer direct GUI launch so child app-server inherits proxy env.
set "CODEX_BIN="
set "HAS_APP_ID=0"
call :FindCodexDirect
if "%CODEX_BIN%"=="" (
    powershell -NoProfile -Command "if (Get-StartApps | Where-Object { $_.AppID -eq '%APP_ID%' }) { exit 0 } else { exit 1 }" >nul 2>&1
    if %errorlevel% equ 0 set "HAS_APP_ID=1"
)
if "%CODEX_BIN%"=="" if "%HAS_APP_ID%"=="0" (
    echo [ERROR] Codex app entry was not found.
    if "%CHECK_ONLY%"=="0" pause
    exit /b 1
)

:: Check Codex not already running
tasklist /FI "IMAGENAME eq Codex.exe" 2>nul | find /I "Codex.exe" >nul
if %errorlevel% equ 0 (
    echo [WARNING] Codex already running. Quit it completely, then re-launch.
    if "%CHECK_ONLY%"=="1" (
        echo Check result: launcher is configured, but proxy flags need a cold start.
        exit /b 0
    )
    pause
    exit /b 0
)

if "%CHECK_ONLY%"=="1" (
    if not "%CODEX_BIN%"=="" (
        echo Check result: OK. Direct Codex path: %CODEX_BIN%
    ) else (
        echo Check result: OK. AppID fallback: %APP_ID%
    )
    exit /b 0
)

:: Launch
set "HTTP_PROXY=%PROXY_URL%" & set "HTTPS_PROXY=%PROXY_URL%" & set "ALL_PROXY=%PROXY_URL%"
set "http_proxy=%PROXY_URL%" & set "https_proxy=%PROXY_URL%" & set "all_proxy=%PROXY_URL%"
set "NO_PROXY=%NO_PROXY_VALUE%" & set "no_proxy=%NO_PROXY_VALUE%"

echo Launching Codex with proxy %PROXY_URL% ...
if not "%CODEX_BIN%"=="" (
    start "" "%CODEX_BIN%" --proxy-server="%PROXY_URL%" --proxy-bypass-list="%BYPASS_CHROMIUM%"
    timeout /t 2 >nul
    exit /b 0
) else (
    echo [WARNING] Direct Codex.exe not found; using AppID fallback. Child app-server may not inherit proxy environment.
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Start-CodexProxy.ps1" -AppId "%APP_ID%" -LaunchArgs "--proxy-server=%PROXY_URL% --proxy-bypass-list=%BYPASS_CHROMIUM%"
)
if %errorlevel% neq 0 (
    echo [ERROR] Failed to launch Codex.
    pause
    exit /b 1
)
timeout /t 2 >nul
exit /b 0

:FindCodexDirect
set "CODEX_BIN="
for /f "delims=" %%p in ('powershell -NoProfile -Command "$pkg=Get-AppxPackage OpenAI.Codex -ErrorAction SilentlyContinue; if($pkg){$p=Join-Path $pkg.InstallLocation 'app\Codex.exe'; if(Test-Path $p){$p}}"') do (
    set "CODEX_BIN=%%p"
    exit /b 0
)
for %%p in (
    "%LOCALAPPDATA%\Programs\Codex\Codex.exe"
    "%ProgramFiles%\Codex\Codex.exe"
    "%USERPROFILE%\AppData\Local\Programs\codex\Codex.exe"
) do (
    if exist "%%~p" (
        set "CODEX_BIN=%%~p"
        exit /b 0
    )
)
for /f "delims=" %%p in ('where codex 2^>nul') do (
    echo %%p | find /I "\WindowsApps\" >nul
    if errorlevel 1 (
        set "CODEX_BIN=%%p"
        exit /b 0
    )
)
exit /b 0
BAT

    cat > "$target_dir/Start-CodexProxy.ps1" << 'PS1'
param(
    [Parameter(Mandatory = $true)]
    [string]$AppId,

    [Parameter(Mandatory = $true)]
    [string]$LaunchArgs
)

$code = @"
using System;
using System.Runtime.InteropServices;

public enum ActivateOptions
{
    None = 0,
    DesignMode = 1,
    NoErrorUI = 2,
    NoSplashScreen = 4
}

[ComImport]
[Guid("2e941141-7f97-4756-ba1d-9decde894a3d")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IApplicationActivationManager
{
    int ActivateApplication(
        [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
        [MarshalAs(UnmanagedType.LPWStr)] string arguments,
        ActivateOptions options,
        out uint processId);
}

[ComImport]
[Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
class ApplicationActivationManager
{
}

public static class PackagedAppLauncher
{
    public static uint Activate(string appId, string args)
    {
        var manager = (IApplicationActivationManager)new ApplicationActivationManager();
        uint processId;
        int hr = manager.ActivateApplication(appId, args, ActivateOptions.None, out processId);
        if (hr < 0)
        {
            Marshal.ThrowExceptionForHR(hr);
        }
        return processId;
    }
}
"@

Add-Type -TypeDefinition $code -ErrorAction Stop
$activatedProcessId = [PackagedAppLauncher]::Activate($AppId, $LaunchArgs)
Write-Host "Activated Codex process $activatedProcessId"
PS1

    # Replace placeholders (sed -i.bak + rm works with both GNU and BSD sed)
    sed -i.bak "s|__NO_PROXY__|$NO_PROXY_VALUE|g" "$target_dir/CodexProxy.bat"
    sed -i.bak "s|__BYPASS_CHROMIUM__|$BYPASS_CHROMIUM|g" "$target_dir/CodexProxy.bat"
    rm -f "$target_dir/CodexProxy.bat.bak"
    if [[ -f "$PROXY_ICON_ASSET" ]]; then
        cp "$PROXY_ICON_ASSET" "$target_dir/codex-proxy.ico"
    fi

    echo "✅ Windows: $target_dir/CodexProxy.bat + Start-CodexProxy.ps1"
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
