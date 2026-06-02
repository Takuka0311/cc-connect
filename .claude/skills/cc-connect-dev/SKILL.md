---
name: cc-connect-dev
description: Build, run, stop, and debug the cc-connect Go binary locally. Use when developing or debugging this repository — compiling (make build / go build), starting the service, stopping it, managing config, enabling the web admin, or running tests.
---

# cc-connect Local Dev / Build / Run / Stop

Project-specific commands for developing and debugging cc-connect. All commands run from the repo root (`/apsara/workspace/cc-connect`). Go 1.25+ and Node (for the web UI) required.

## Build / 编译

```bash
# Full build: builds web frontend (web/ via npm) + Go binary -> ./cc-connect
make build

# Backend only, skip web frontend (faster; embeds a stub web)
make build-noweb

# Quick compile check of all Go packages (no binary, no web)
go build ./...

# Binary only, without rebuilding the web frontend
go build -ldflags "-s -w" -o cc-connect ./cmd/cc-connect
```

Selective compilation via build tags (default = all agents + platforms):

```bash
make build AGENTS=claudecode PLATFORMS_INCLUDE=feishu,telegram
make build EXCLUDE=discord,dingtalk,qq,qqbot,line
go build -tags 'no_discord no_qq' -o cc-connect ./cmd/cc-connect
```

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
make run                                # build + run in foreground
```

> ⚠️ **It is a long-running process — it never exits on its own.** If you do run
> it in a managed background shell, do **one** quick smoke check and move on. Do
> **not** block/poll/await the shell for the command to "finish" — it won't, and
> waiting just stalls you. Smoke-check by waiting for the regex `cc-connect is
> running` (short timeout) or reading the log once.

## Restart / 重启 (apply config or rebuild)

**The running process does NOT hot-reload `config.toml`, and a rebuilt binary
is not picked up by the already-running process.** After editing config or
`make build`, you must **restart**:

```bash
scripts/ccctl.sh restart
```

This gracefully stops the old instance (SIGTERM, releasing the lock), then
starts a fresh detached one and waits for the `cc-connect is running` log line.

Manual fallback (if not using the script): the live PID is in the lock file, so
`kill "$(cat ~/.cc-connect/.config.toml.lock)"`, wait until the process is gone,
then `scripts/ccctl.sh start`. Avoid `./cc-connect --force` — it has hit a
kill/lock race that re-reports "another cc-connect instance is already running"
right after killing.

### First run / config

First run with no config creates a default at `~/.cc-connect/config.toml` and exits with "Please edit this file...". Fill in real agent/platform credentials, then run again. An instance lock (`~/.cc-connect/.config.toml.lock`) prevents duplicate processes for the same config; a stale lock whose PID is dead is treated as stale and auto-acquired on next start.

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

The management server binds to `host:port`; `host` defaults to all interfaces (`0.0.0.0`), so it is externally reachable. To restrict or be explicit, set it in `[management]`:

```toml
[management]
  enabled = true
  host = "0.0.0.0"   # all interfaces (external); use "127.0.0.1" for local-only
  port = 9820
  token = "your-mgmt-secret"
```

Displayed/pushed login URLs use the configured `host`, or auto-detect the machine's outbound LAN IP when `host` is empty/`0.0.0.0` (falls back to `localhost`). Access externally via `http://<server-ip>:9820/login?token=<token>`. If external access fails despite the server listening on `0.0.0.0`, open the port in the firewall / cloud security group — that is not a code issue.

Verify reachability:

```bash
ss -tlnp | grep -E '9820|9810'
curl -s -o /dev/null -w "%{http_code}\n" http://<server-ip>:9820/
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
