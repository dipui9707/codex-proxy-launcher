---
name: codex-proxy-launcher
description: Load when the user needs Codex to go through a proxy (can't connect from mainland China, behind firewall, "Codex 连不上", "需要代理"), or wants a launcher that forces Codex traffic through Clash/V2Ray/socks proxy on any OS.
---

# Codex Proxy Launcher

## Core insight

Codex is an Electron app (Chromium runtime). Chromium reads `--proxy-server` and `--proxy-bypass-list` CLI flags — this is the only reliable way to force proxy on an Electron app that ignores system proxy settings. Environment variables (`HTTP_PROXY` etc.) are set as a belt-and-suspenders backup, but the CLI flags are what actually matter.

Generate a launcher that: reads proxy settings from `proxy.conf` → checks proxy is reachable → checks Codex isn't already running → launches Codex with proxy flags injected.

Heavy implementation lives in `scripts/generate.sh`. Read it, adapt paths to the user's system, and execute. Do NOT regenerate equivalent scripts from memory — use the template.

## Gotchas

These are the non-obvious edge cases the model would not guess. Read before generating.

### Proxy only takes effect on cold start
`--proxy-server` is read once at process creation. If Codex is already running, the user MUST fully quit (Cmd+Q / Alt+F4 / `kill`, NOT just close the window) and re-launch. The launcher checks for existing Codex processes and warns if found.

### Codex ignores system proxy
On both macOS and Windows, setting the system proxy has zero effect on Codex. That's the entire reason this launcher exists. Do not suggest "just turn on the system proxy."

### Clash "System Proxy" switch is irrelevant
Clash Verge's system proxy toggle only sets macOS/Windows system-wide proxy — which Codex ignores. The launcher connects directly to Clash's mixed port (default 7897). The Clash system proxy switch can stay off.

### Mixed port, not HTTP port
Clash Verge has separate HTTP (7890) and mixed (7897) ports. The launcher defaults to the mixed port because it supports both HTTP and SOCKS5. If the user's proxy only has an HTTP port, they change `PROXY_PORT` in `proxy.conf`.

### Two different bypass formats
- `--proxy-bypass-list` uses **semicolons** (`;`) and `<local>` — Chromium format
- `NO_PROXY` env var uses **commas** and CIDR notation — standard Unix format
Using the wrong separator silently breaks bypass. The template scripts handle both correctly; don't change the separators.

### Upper + lowercase env vars
Some tools read `HTTP_PROXY`, others read `http_proxy`. Set all six variants. The templates already do this.

### macOS .app icon must be declared in Info.plist
For a custom macOS icon, copy `assets/codex-proxy.icns` to `Contents/Resources/codex-proxy.icns` and set `CFBundleIconFile` to `codex-proxy` in `Contents/Info.plist`. Finder/Dock can cache icons, so if the icon does not refresh immediately, remove the old Dock item and re-add the `.app`, or touch the bundle.

### Apple Silicon shell-script launchers can skew Codex shell architecture
On Apple Silicon, a shell-script `.app` wrapper can still launch Codex successfully but leave Codex's PTY/shell environment reporting `arch` as `i386` / `x86_64` under Rosetta-like compatibility. If the user cares about native toolchains, verify with `arch`, `uname -m`, and `file /Applications/Codex.app/Contents/MacOS/Codex`. If the original Codex.app is arm64 but the proxy launcher shell is not, replace the shell-script wrapper with an arm64 Mach-O launcher that sets proxy env vars and execs Codex with `--proxy-server` / `--proxy-bypass-list`.

### Linux Codex path is unpredictable
Unlike macOS (`/Applications/Codex.app` is fixed by convention), Linux Codex paths vary wildly. The script probes common locations; if all fail, tell the user to set `CODEX_BIN` at the top of the generated script.

### Windows Store/MSIX has two Codex executables
If Windows Codex is installed as `OpenAI.Codex` under `C:\Program Files\WindowsApps`, `app\resources\codex.exe` is the backend CLI/app-server and can print "拒绝访问" / "Access is denied" when launched directly. Prefer the GUI entry `app\Codex.exe` discovered via `Get-AppxPackage OpenAI.Codex`, and pass Chromium proxy flags to that executable. Avoid `where codex` results inside `WindowsApps`.

### AppID activation can miss child-process proxy env
`IApplicationActivationManager` can pass `--proxy-server` to the Electron GUI, but it may not inherit `HTTP_PROXY`/`HTTPS_PROXY` into Codex's child `app-server`. If the GUI opens but usage says "reconnecting" until global proxy is enabled, launch `app\Codex.exe` directly from the `.bat` so both Chromium flags and environment variables reach Codex and its children. Use AppID activation only as a fallback when direct GUI launch is unavailable.

### Windows batch `errorlevel` can cause false launch failures
After `tasklist | find` confirms Codex is not running, `%errorlevel%` remains `1`. A later `start "" "%CODEX_BIN%" ...` may successfully launch Codex without resetting that value. In the direct-launch branch, exit immediately after `start` and do not run a generic `%errorlevel%` failure check. Only check `%errorlevel%` for the PowerShell AppID fallback branch.

### Edge case: proxy is reachable but drops traffic
`nc -z` only checks TCP handshake. A proxy that accepts connections but doesn't forward traffic will pass the check but Codex still won't work. If the user reports "launcher says OK but Codex still can't connect," suspect a proxy misconfiguration, not the launcher.

### GNU sed vs BSD sed (script maintainers only)
`generate.sh` uses `sed -i.bak` + `rm .bak` — the only syntax compatible with both GNU sed (Linux/Homebrew) and BSD sed (macOS default). Do not "fix" this to `sed -i` (GNU-only) or `sed -i ''` (BSD-only).

## How to generate

1. **Detect OS** with `uname -s` (macOS=Darwin, Linux=Linux) or `echo %OS%` (Windows).
2. **Read or create `proxy.conf`** — two lines: `PROXY_HOST=127.0.0.1` and `PROXY_PORT=7897`. If the user specifies a different proxy, write their values instead.
3. **Read `scripts/generate.sh`** — it contains the launcher templates for all three platforms. Adapt the Codex binary path to the user's actual installation, then write the launcher file(s).
4. **macOS only**: After writing, `chmod +x` the script inside the .app bundle.
5. **Verify**: `bash -n` the shell scripts. For `.bat`, run `CodexProxy.bat --check` where possible; it should validate proxy reachability and Codex discovery without launching a new Codex instance.
6. **Tell the user** where the files are, that `proxy.conf` is the only file they ever need to edit, and how to create a shortcut (Dock / .desktop / Pin to Start). Use bundled proxy icons when available: `assets/codex-proxy.icns` for macOS `.app`, `assets/codex-proxy.png` for Linux `.desktop`, and `assets/codex-proxy.ico` for Windows shortcuts.
