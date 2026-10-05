#!/usr/bin/env bash
# Provision an Ubuntu/Debian web server: system updates, nginx, UFW firewall,
# custom homepage. Safe to run more than once (idempotent).
#
# Usage:
#   sudo ./provision.sh                 # provision
#   sudo ./provision.sh --dry-run       # print what would be done, change nothing
#   sudo SSH_SOURCE_CIDR=203.0.113.4/32 ./provision.sh   # allow SSH only from one IP
#
# Environment variables:
#   SSH_SOURCE_CIDR  CIDR allowed to reach SSH (port 22). Default: anywhere (with a warning).
#   LOG_FILE         Log file path. Default: /var/log/provision.log

set -Eeuo pipefail

LOG_FILE="${LOG_FILE:-/var/log/provision.log}"
SSH_SOURCE_CIDR="${SSH_SOURCE_CIDR:-}"
WEB_ROOT="/var/www/html"
HOMEPAGE="${WEB_ROOT}/index.html"
DRY_RUN=false

log()  { printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" | tee -a "$LOG_FILE" >&2; }
info() { log INFO "$*"; }
warn() { log WARN "$*"; }
die()  { log ERROR "$*"; exit 1; }

# Print the failing command and line number instead of exiting silently.
trap 'die "Command failed (exit $?) at line ${LINENO}: ${BASH_COMMAND}"' ERR

# Run a command, or only print it in dry-run mode.
run() {
  if "$DRY_RUN"; then
    info "[dry-run] $*"
  else
    info "+ $*"
    "$@"
  fi
}

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=true ;;
      -h|--help) usage; exit 0 ;;
      *) usage; die "Unknown argument: $1" ;;
    esac
    shift
  done
}

preflight() {
  if "$DRY_RUN"; then
    # Dry run must work without root, so log to a temp file if needed.
    if ! touch "$LOG_FILE" 2>/dev/null; then LOG_FILE="$(mktemp -t provision.XXXX.log)"; fi
  else
    [[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0" >&2; exit 1; }
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
  fi

  [[ -r /etc/os-release ]] || die "Cannot detect the OS (/etc/os-release missing)."
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) info "Detected ${PRETTY_NAME:-$ID}" ;;
    *) die "Unsupported OS '${ID:-unknown}'. This script supports Ubuntu and Debian." ;;
  esac

  if [[ -n "$SSH_SOURCE_CIDR" ]] && ! [[ "$SSH_SOURCE_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]]; then
    die "SSH_SOURCE_CIDR '$SSH_SOURCE_CIDR' is not a valid IPv4 CIDR (e.g. 203.0.113.4/32)."
  fi
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  run apt-get update -y
  run apt-get upgrade -y
  local pkg missing=()
  for pkg in nginx ufw curl; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      info "$pkg already installed"
    else
      missing+=("$pkg")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    run apt-get install -y --no-install-recommends "${missing[@]}"
  fi
}

configure_firewall() {
  run ufw default deny incoming
  run ufw default allow outgoing

  # Allow SSH BEFORE enabling the firewall, otherwise the current session is locked out.
  if [[ -n "$SSH_SOURCE_CIDR" ]]; then
    run ufw allow from "$SSH_SOURCE_CIDR" to any port 22 proto tcp comment 'SSH (restricted)'
  else
    warn "SSH_SOURCE_CIDR not set: SSH (22) is allowed from anywhere. Restrict it in production."
    run ufw allow 22/tcp comment 'SSH'
  fi
  run ufw allow 80/tcp comment 'HTTP'
  run ufw --force enable
}

deploy_homepage() {
  local content
  content="<!doctype html>
<html lang=\"en\"><head><meta charset=\"utf-8\"><title>Provisioned</title></head>
<body><h1>Provisioned by Asadbek's script</h1><p>Host: $(hostname)</p></body></html>"

  if [[ -f "$HOMEPAGE" ]] && [[ "$(cat "$HOMEPAGE")" == "$content" ]]; then
    info "Homepage already up to date"
    return
  fi
  if "$DRY_RUN"; then
    info "[dry-run] write $HOMEPAGE"
  else
    install -d -m 755 "$WEB_ROOT"
    printf '%s\n' "$content" > "${HOMEPAGE}.tmp"
    chmod 644 "${HOMEPAGE}.tmp"
    mv "${HOMEPAGE}.tmp" "$HOMEPAGE"   # atomic replace
    info "Homepage written to $HOMEPAGE"
  fi
}

start_nginx() {
  run nginx -t                         # validate config before (re)starting
  run systemctl enable --now nginx
  run systemctl reload nginx
}

verify() {
  "$DRY_RUN" && { info "[dry-run] skip verification"; return; }
  local _
  for _ in 1 2 3 4 5; do
    if curl -fsS --max-time 3 http://127.0.0.1/ >/dev/null; then
      info "nginx responds on http://127.0.0.1/"
      return
    fi
    sleep 1
  done
  die "nginx is not responding on port 80"
}

main() {
  parse_args "$@"
  preflight
  info "Starting provisioning (dry-run=$DRY_RUN, log=$LOG_FILE)"
  install_packages
  configure_firewall
  deploy_homepage
  start_nginx
  verify
  info "Provisioning complete"
}

main "$@"
