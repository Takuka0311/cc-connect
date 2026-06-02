#!/usr/bin/env bash
# cc-connect background process control.
#
# Runs the cc-connect binary fully detached from the terminal (survives the
# terminal closing) and provides start / stop / restart / status / logs.
#
# Process identity is taken from cc-connect's own instance lock file, which
# always contains the PID of the live process. This avoids fragile `pgrep -f`
# matching that would otherwise also match this script or the agent (e.g.
# claude) subprocesses spawned by cc-connect.
#
# Usage:
#   scripts/ccctl.sh start      # launch detached in the background
#   scripts/ccctl.sh stop       # graceful stop (SIGTERM, then SIGKILL)
#   scripts/ccctl.sh restart    # stop + start (apply config / rebuilt binary)
#   scripts/ccctl.sh status     # running? print PID + log path
#   scripts/ccctl.sh logs [N]   # print last N log lines (default 80)
#   scripts/ccctl.sh logs -f    # follow the log
#
# Overridable via env:
#   CC_BIN   path to the cc-connect binary (default: <repo>/cc-connect)
#   CC_LOG   log file (default: ~/.cc-connect/cc-connect.log)
#   CC_LOCK  instance lock file (default: ~/.cc-connect/.config.toml.lock)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${CC_BIN:-$REPO_DIR/cc-connect}"
LOG="${CC_LOG:-$HOME/.cc-connect/cc-connect.log}"
LOCK="${CC_LOCK:-$HOME/.cc-connect/.config.toml.lock}"

mkdir -p "$(dirname "$LOG")"

running_pid() {
  [ -f "$LOCK" ] || return 1
  local pid
  pid="$(cat "$LOCK" 2>/dev/null || true)"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  echo "$pid"
}

is_running() { running_pid >/dev/null 2>&1; }

launch() {
  cd "$REPO_DIR"
  # setsid detaches into a new session (no controlling terminal); nohup is the
  # fallback. stdin from /dev/null so it never blocks on a tty.
  if command -v setsid >/dev/null 2>&1; then
    setsid "$BIN" >>"$LOG" 2>&1 </dev/null &
  else
    nohup "$BIN" >>"$LOG" 2>&1 </dev/null &
  fi
}

start() {
  local pid
  if pid="$(running_pid)"; then
    echo "cc-connect already running (pid $pid)"
    return 0
  fi
  if [ ! -x "$BIN" ]; then
    echo "error: binary not found or not executable: $BIN (run: make build)" >&2
    exit 1
  fi
  # Only scan log content appended after this point, so the health check is not
  # fooled by an earlier run's "cc-connect is running" line.
  local off=0
  [ -f "$LOG" ] && off="$(wc -c <"$LOG" 2>/dev/null || echo 0)"
  launch
  local i
  for i in $(seq 1 30); do
    sleep 0.5
    if tail -c "+$((off + 1))" "$LOG" 2>/dev/null | grep -q "cc-connect is running"; then
      echo "cc-connect started (pid $(running_pid)); log: $LOG"
      return 0
    fi
  done
  echo "warning: started but did not see 'cc-connect is running' within ~15s; recent log:" >&2
  tail -n 20 "$LOG" >&2 || true
  return 1
}

stop() {
  local pid
  if ! pid="$(running_pid)"; then
    echo "cc-connect not running"
    return 0
  fi
  kill "$pid" 2>/dev/null || true
  local i
  for i in $(seq 1 30); do
    is_running || { echo "cc-connect stopped"; return 0; }
    sleep 0.5
  done
  echo "graceful stop timed out, sending SIGKILL" >&2
  kill -9 "$pid" 2>/dev/null || true
  echo "cc-connect killed"
}

status() {
  local pid
  if pid="$(running_pid)"; then
    echo "running (pid $pid)"
    echo "log:  $LOG"
    echo "lock: $LOCK"
  else
    echo "stopped"
  fi
}

logs() {
  if [ "${1:-}" = "-f" ]; then
    tail -n 80 -f "$LOG"
  else
    tail -n "${1:-80}" "$LOG"
  fi
}

case "${1:-}" in
  start)   start ;;
  stop)    stop ;;
  restart) stop; start ;;
  status)  status ;;
  logs)    shift; logs "$@" ;;
  *)
    echo "usage: $0 {start|stop|restart|status|logs [N|-f]}" >&2
    exit 2
    ;;
esac
