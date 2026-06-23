---
name: cc-connect-dev
description: Build, run, stop, and debug the cc-connect Go binary locally. Use when developing or debugging this repository — compiling (make build / go build), starting the service, stopping it, managing config, enabling the web admin, or running tests.
---

# cc-connect Local Dev / Build / Run / Stop

Project-specific commands for developing and debugging cc-connect. All commands run from the cc-connect repository root. Go 1.25+ and Node (for the web UI) required.

## ⚠️ Always build WITH web / 必须带 Web 启动

**Default rule for any build that will be run or restarted (including cron jobs, sync-and-restart, and local dev): use `make build`, never `make build-noweb` or `-tags no_web`.**

| Command | Web UI at `:9820` | When to use |
|---------|-------------------|-------------|
| `make build` | ✅ embedded | **Default** — any binary you start/restart |
| `make build-noweb` / `-tags no_web` | ❌ 404 on `/` | CI/size-only; **never** for running instances |
| `go build ./...` | — | Compile check only; does not produce a runnable binary with web |

A `no_web` binary still serves Management **API** (`/api/v1/*`) but **not** the dashboard — `curl http://<host>:9820/` returns **404** instead of **200**.

**Standard deploy pipeline (sync, rebuild, restart):**

```bash
make build                    # npm run build + go embed web/dist
scripts/ccctl.sh restart      # detached restart; do NOT kill from inside cc-connect
```

**Verify web is embedded after build/restart:**

```bash
go version -m ./cc-connect | grep tags          # must NOT contain no_web
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:9820/   # expect 200
```

## Build / 编译

```bash
# Full build (REQUIRED for running instances): web frontend + Go binary -> ./cc-connect
make build

# Backend only — NO web UI. Do not use for ccctl start/restart or cron deploys.
make build-noweb

# Quick compile check of all Go packages (no binary, no web)
go build ./...
```

Selective compilation via build tags (default = all agents + platforms). **Do not add `no_web` unless explicitly asked for a headless-only binary:**

```bash
make build AGENTS=claudecode PLATFORMS_INCLUDE=feishu,telegram
make build EXCLUDE=discord,dingtalk,qq,qqbot,line
```

After Go-only edits (no web/ changes), you may skip `npm run build` but still need a web-enabled binary — use `make build`, not bare `go build -o cc-connect ./cmd/cc-connect` (that reuses existing `web/dist/` but is easy to get wrong; prefer `make build`).

After Go edits, always run `go build ./...`, `gofmt -l <files>`, and `go vet ./...`.

## Run / 启动 (background — recommended)

The service is a long-running process that hosts the web admin and the
bridge/management servers (`./cc-connect web` only opens a browser, it does NOT
start a server). **Run it detached via the control script** so it survives the
terminal closing — no need to keep a terminal open:

```bash
scripts/ccctl.sh start      # launch detached (setsid); logs -> ~/.cc-connect/cc-connect.log
scripts/ccctl.sh status     # running? prints PID + log path
scripts/ccctl.sh logs       # last 80 log lines  (logs -f to follow, logs 200 for more)
```

`scripts/ccctl.sh` tracks the process via cc-connect's own instance lock file
(`~/.cc-connect/.config.toml.lock`, which always holds the live PID) — this is
robust and never mis-matches the script itself or the agent (e.g. `claude`)
subprocesses that cc-connect spawns. `start` waits for the `cc-connect is
running` log line and prints `cc-connect started (pid …)`. The detached process
runs with `PPID=1` and its own session (no controlling terminal).

A healthy startup logs `cc-connect is running`, `management api started addr=...`,
and `bridge: server started`. Placeholder IM credentials (e.g. default
`your-feishu-app-id`) log a websocket/app_id error but the process keeps running
and the web admin stays up — this is expected in dev.

### Foreground (quick debugging only)

Needs a persistent terminal (Ctrl-C to stop); prefer the script for anything
that should outlive the shell.

```bash
./cc-connect                            # config: --config > ./config.toml > ~/.cc-connect/config.toml
./cc-connect --config /path/to/config.toml
make run                                # make build + run in foreground (includes web)
```

> ⚠️ **It is a long-running process — it never exits on its own.** If you do run
> it in a managed background shell, do **one** quick smoke check and move on. Do
> **not** block/poll/await the shell for the command to "finish" — it won't, and
> waiting just stalls you. Smoke-check by waiting for the regex `cc-connect is
> running` (short timeout) or reading the log once.

## Restart / 重启 (apply config or rebuild)

**The running process does NOT hot-reload `config.toml`, and a rebuilt binary
is not picked up by the already-running process.** After editing config or
rebuilding, you must **restart**:

```bash
make build                  # if binary changed — always with web
scripts/ccctl.sh restart
```

This gracefully stops the old instance (SIGTERM, releasing the lock), then
starts a fresh detached one and waits for the `cc-connect is running` log line.

**Cron / agent tasks:** never restart cc-connect by killing the process from
inside cc-connect (the agent session dies with the parent). Use
`scripts/ccctl.sh restart` from a subprocess that survives shutdown, or run
the script from outside cc-connect entirely.

Manual fallback (if not using the script): the live PID is in the lock file, so
`kill "$(cat ~/.cc-connect/.config.toml.lock)"`, wait until the process is gone,
then `scripts/ccctl.sh start`. Avoid `./cc-connect --force` — it has hit a
kill/lock race that re-reports "another cc-connect instance is already running"
right after killing.

### First run / config

First run with no config creates a default at `~/.cc-connect/config.toml` and exits with "Please edit this file...". Fill in real agent/platform credentials, then run again. An instance lock (`~/.cc-connect/.config.toml.lock`) prevents duplicate processes for the same config; a stale lock whose PID is dead is treated as stale and auto-acquired on next start.

Ensure `[management] enabled = true` for the web dashboard. Example:

```toml
[management]
  enabled = true
  host = "0.0.0.0"
  port = 9820
  token = "your-mgmt-secret"
```

## Stop / 停止

```bash
scripts/ccctl.sh stop       # graceful SIGTERM, then SIGKILL if it doesn't exit
scripts/ccctl.sh status     # verify -> prints "stopped"
```

Manual fallback: `kill "$(cat ~/.cc-connect/.config.toml.lock)"`. A foreground
instance stops with Ctrl-C (SIGINT).

## Web admin / Ports / 外部访问

| Service | Default port | Config section |
|---------|--------------|----------------|
| Management API + Web UI | 9820 | `[management]` |
| Bridge (WebSocket) | 9810 | `[bridge]` |
| Webhook | 9111 | `[webhook]` |
| Internal API | unix socket `~/.cc-connect/run/api.sock` | — |

Enable + open the web admin:

```bash
./cc-connect web                 # configure (if needed) + open browser
./cc-connect web --no-browser    # just print URL + token
```

The management server binds to `host:port`; `host` defaults to all interfaces (`0.0.0.0`), so it is externally reachable.

Displayed/pushed login URLs use the configured `host`, or auto-detect the machine's outbound LAN IP when `host` is empty/`0.0.0.0` (falls back to `localhost`). Access externally via `http://<server-ip>:9820/login?token=<token>`. If external access fails despite the server listening on `0.0.0.0`, open the port in the firewall / cloud security group — that is not a code issue.

Verify reachability **and** that web assets are embedded:

```bash
ss -tlnp | grep -E '9820|9810'
curl -s -o /dev/null -w "%{http_code}\n" http://<server-ip>:9820/    # 200 = OK, 404 = no_web binary
go version -m ./cc-connect | grep tags                                 # must not show no_web
```

## Tests / 测试

```bash
go test ./...                    # all unit tests
go test -race ./...              # with race detector (CI)
go test ./core/ -run TestName -v # single test
make test-fast                   # unit + smoke (< 2 min)
make test-full                   # unit + smoke + regression (PR gate)
```

## Run as a service (optional) / 守护进程

```bash
cc-connect daemon install --work-dir /path/to/config-dir
cc-connect daemon status | start | stop | restart | logs | uninstall
```

## Useful subcommands

`./cc-connect <cmd>`: `web`, `doctor`, `send`, `cron`, `daemon`, `config`, `config-example`, `provider`, `sessions`, `update`, `--version`.
