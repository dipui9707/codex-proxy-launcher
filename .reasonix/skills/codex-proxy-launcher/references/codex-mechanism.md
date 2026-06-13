# Why --proxy-server works on Codex

## Codex is Electron → Chromium

Codex.app is built on Electron, which embeds a Chromium browser runtime. Every network request Codex makes — API calls, asset loading, WebSocket connections — goes through Chromium's network stack.

Chromium exposes two CLI flags for proxy configuration:

```
--proxy-server=<scheme>://<host>:<port>
--proxy-bypass-list=<pattern1>;<pattern2>;...
```

These are documented at `chrome://settings` equivalent and are the ONLY proxy mechanism that Electron apps cannot bypass, short of modifying the app binary.

## Why system proxy doesn't work

Electron apps use Chromium's network stack directly. They do NOT automatically respect:

- macOS System Preferences → Network → Proxies
- Windows Settings → Proxy
- `HTTP_PROXY` / `HTTPS_PROXY` environment variables

Some Electron apps explicitly read these; Codex does not. The `--proxy-server` flag is mandatory.

## Why we set environment variables too

Belt and suspenders. Codex might shell out to external tools (git, curl, npm) that DO read `HTTP_PROXY`. Setting both the Chromium flags AND the Unix env vars covers the Electron process AND any child processes it spawns.

## Two bypass formats

| Layer | Format | Example |
|-------|--------|---------|
| `--proxy-bypass-list` (Chromium) | Semicolons, `<local>` token | `<local>;localhost;127.0.0.1;10.*` |
| `NO_PROXY` / `no_proxy` (Unix) | Commas, CIDR blocks | `127.0.0.1,localhost,10.0.0.0/8` |

The `<local>` token in Chromium bypass means "do not proxy any hostname that contains no dots" — equivalent to "local network." This is not standard across all tools, which is why we also set the Unix-style `NO_PROXY`.

## Clash Verge port conventions

Clash Verge (and most Clash GUI forks) expose multiple ports:

| Port | Protocol | Purpose |
|------|----------|---------|
| 7890 | HTTP | HTTP proxy only |
| 7891 | SOCKS5 | SOCKS5 proxy only |
| 7893 | HTTP | controller / REST API |
| 7897 | Mixed | HTTP + SOCKS5 combined |

The launcher defaults to 7897 (mixed) because it handles both protocols. If the user's proxy software only exposes HTTP (e.g., `http://127.0.0.1:10809` for v2rayN on Windows), change `PROXY_PORT` in `proxy.conf`.

## Cold-start constraint

`--proxy-server` is read exactly once during `ChromiumBrowser::AppendExtraCommandLineSwitches`, which runs before the browser process initializes the network stack. There is no runtime API to change the proxy server after launch. This is why the launcher checks for existing Codex processes and warns the user to quit completely.
