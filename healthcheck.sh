#!/usr/bin/env bash
# Server health check: disk, memory, services and HTTP.
# Exit codes (usable from cron or a monitoring agent):
#   0 = OK, 1 = WARNING, 2 = CRITICAL
#
# Usage:
#   ./healthcheck.sh
#   DISK_WARN=70 SERVICES="nginx ssh" ./healthcheck.sh
#
# Environment variables (defaults in brackets):
#   DISK_WARN [80] / DISK_CRIT [90]   root filesystem usage in %
#   MEM_WARN  [85] / MEM_CRIT  [95]   memory usage in % (based on MemAvailable)
#   SERVICES  [nginx]                 systemd services that must be active
#   HTTP_URL  [http://127.0.0.1/]     URL that must return HTTP 2xx/3xx (empty = skip)

set -Euo pipefail

DISK_WARN="${DISK_WARN:-80}"
DISK_CRIT="${DISK_CRIT:-90}"
MEM_WARN="${MEM_WARN:-85}"
MEM_CRIT="${MEM_CRIT:-95}"
SERVICES="${SERVICES:-nginx}"
HTTP_URL="${HTTP_URL-http://127.0.0.1/}"

status=0
report() {
  # $1 = level (OK/WARN/CRIT/UNKNOWN), rest = message
  local level="$1"; shift
  printf '%-8s %s\n' "[$level]" "$*"
  case "$level" in
    WARN|UNKNOWN) (( status < 1 )) && status=1 ;;
    CRIT) status=2 ;;
  esac
}

check_threshold() {
  # $1 = name, $2 = value, $3 = warn, $4 = crit
  if (( $2 >= $4 )); then report CRIT "$1 at $2% (critical >= $4%)"
  elif (( $2 >= $3 )); then report WARN "$1 at $2% (warning >= $3%)"
  else report OK "$1 at $2%"
  fi
}

check_disk() {
  local used
  used="$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')"
  [[ "$used" =~ ^[0-9]+$ ]] || { report UNKNOWN "could not read disk usage"; return; }
  check_threshold "Disk /" "$used" "$DISK_WARN" "$DISK_CRIT"
}

check_memory() {
  local total avail used
  total="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
  avail="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
  [[ -n "$total" && -n "$avail" && "$total" -gt 0 ]] || { report UNKNOWN "could not read memory usage"; return; }
  used=$(( (total - avail) * 100 / total ))
  check_threshold "Memory" "$used" "$MEM_WARN" "$MEM_CRIT"
}

check_services() {
  local svc state
  if ! command -v systemctl >/dev/null 2>&1 || [[ ! -d /run/systemd/system ]]; then
    report UNKNOWN "systemd not available; cannot check services ($SERVICES)"
    return
  fi
  for svc in $SERVICES; do
    state="$(systemctl is-active "$svc" 2>/dev/null || true)"
    if [[ "$state" == "active" ]]; then report OK "Service $svc is active"
    else report CRIT "Service $svc is ${state:-unknown}"
    fi
  done
}

check_http() {
  [[ -z "$HTTP_URL" ]] && return
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$HTTP_URL" || true)"
  if [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then report OK "HTTP $HTTP_URL returned $code"
  else report CRIT "HTTP $HTTP_URL returned ${code:-no response}"
  fi
}

echo "=== Server health check: $(hostname) $(date '+%Y-%m-%d %H:%M:%S') ==="
check_disk
check_memory
check_services
check_http
case "$status" in
  0) overall=OK ;;
  1) overall=WARNING ;;
  *) overall=CRITICAL ;;
esac
echo "=== Overall: $overall ==="
exit "$status"
