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

## Run / 启动

The service is a long-running foreground process. The web admin and bridge/management servers are hosted **by this main process** — `./cc-connect web` only opens a browser, it does NOT start a server.

```bash
# Foreground (Ctrl-C to stop). Config resolution: --config > ./config.toml > ~/.cc-connect/config.toml
./cc-connect

# Explicit config
./cc-connect --config /path/to/config.toml

# Build + run in one step
make run

# Kill any existing instance with the same config, then start
./cc-connect --force
```

For local debugging, run in the background and tail logs:

```bash
./cc-connect > /tmp/cc-connect.log 2>&1 &
sleep 3 && tail -30 /tmp/cc-connect.log
```

A healthy startup logs `cc-connect is running`, `management api started addr=...`, and `bridge: server started`. Placeholder IM credentials (e.g. default `your-feishu-app-id`) log a websocket/app_id error but the process keeps running and the web admin stays up — this is expected in dev.

### First run / config

First run with no config creates a default at `~/.cc-connect/config.toml` and exits with "Please edit this file...". Fill in real agent/platform credentials, then run again. An instance lock (`~/.cc-connect/.config.toml.lock`) prevents duplicate processes for the same config.

## Stop / 停止

```bash
# Foreground: Ctrl-C (SIGINT)

# Background / by name
pkill -f './cc-connect'        # or: pkill -x cc-connect

# Graceful (the process handles SIGINT/SIGTERM)
kill <pid>

# Stale lock but no process? --force on next start kills the old instance
./cc-connect --force
```

Verify it stopped: `pgrep -af cc-connect | grep -v grep` (no output = stopped).

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
