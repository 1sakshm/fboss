#!/usr/bin/env bash
# Validation-only diagnostics; never included in the upstream source PR.
set -uo pipefail

if (( $# == 0 )); then
  printf 'Usage: %s command [arguments...]\n' "$0" >&2
  exit 2
fi

"$@" &
build_pid=$!
(
  while kill -0 "$build_pid" 2>/dev/null; do
    printf '\n[build heartbeat] %s command_pid=%s\n' "$(date -u +%FT%TZ)" "$build_pid"
    free -m
    df -h "${RUNNER_TEMP:-/tmp}"
    ps -eo pid,ppid,stat,etimes,pcpu,pmem,rss,comm --sort=-pcpu | head -n 16
    if command -v docker >/dev/null 2>&1; then
      docker stats --no-stream --format '{{.Name}} CPU={{.CPUPerc}} MEM={{.MemUsage}} PIDS={{.PIDs}}' || true
    fi
    if [[ -n ${RUNNER_TEMP:-} ]]; then
      latest_log="$RUNNER_TEMP/fboss-613/logs/latest.log"
      if [[ -f $latest_log ]]; then
        stat -L --format='build_log_bytes=%s modified=%y' "$latest_log"
        tail -n 1 "$latest_log" | cut -c 1-240
      fi
    fi
    sleep 60
  done
) &
monitor_pid=$!

cleanup() {
  kill "$monitor_pid" 2>/dev/null || true
  wait "$monitor_pid" 2>/dev/null || true
}
trap cleanup EXIT
trap 'kill "$build_pid" 2>/dev/null || true; exit 143' TERM
trap 'kill "$build_pid" 2>/dev/null || true; exit 130' INT

wait "$build_pid"
build_status=$?
printf '\n[build finished] exit=%s at %s\n' "$build_status" "$(date -u +%FT%TZ)"
exit "$build_status"
