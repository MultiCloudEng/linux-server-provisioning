# Linux Server Provisioning

Bash scripts that turn a fresh Ubuntu/Debian server (e.g. an AWS EC2 instance) into an nginx web server behind a UFW firewall, plus a health-check script with monitoring-friendly exit codes.

## Scripts

### `provision.sh`

| Step | What it does |
|---|---|
| Preflight | Requires root (except `--dry-run`), checks the OS is Ubuntu/Debian, validates `SSH_SOURCE_CIDR` |
| Packages | `apt-get update/upgrade`, installs `nginx`, `ufw`, `curl` only if missing |
| Firewall | Default deny incoming. Allows SSH **before** enabling UFW, so the current session is not locked out. SSH can be restricted to one CIDR. HTTP 80 open |
| Homepage | Writes `/var/www/html/index.html` atomically; skipped if already up to date |
| nginx | Validates config with `nginx -t`, enables and reloads the service |
| Verify | Checks that `http://127.0.0.1/` responds |

Built for safe repeated runs: `set -Eeuo pipefail`, an error trap that logs the failing line and command, timestamped logs to `/var/log/provision.log`, and idempotent steps.

### `healthcheck.sh`

Checks root disk usage, memory (based on `MemAvailable`), systemd services and an HTTP endpoint. Thresholds are configurable. Exit codes: `0` OK, `1` WARNING, `2` CRITICAL, so it can run from cron or a monitoring agent.

## Usage

```bash
chmod +x provision.sh healthcheck.sh

sudo ./provision.sh --dry-run                               # show what would happen
sudo SSH_SOURCE_CIDR=203.0.113.4/32 ./provision.sh          # SSH only from your IP
./healthcheck.sh
DISK_WARN=70 SERVICES="nginx ssh" ./healthcheck.sh
```

| Variable | Default | Script |
|---|---|---|
| `SSH_SOURCE_CIDR` | empty = SSH from anywhere (logs a warning) | provision |
| `LOG_FILE` | `/var/log/provision.log` | provision |
| `DISK_WARN` / `DISK_CRIT` | 80 / 90 (%) | healthcheck |
| `MEM_WARN` / `MEM_CRIT` | 85 / 95 (%) | healthcheck |
| `SERVICES` | `nginx` | healthcheck |
| `HTTP_URL` | `http://127.0.0.1/` (empty = skip) | healthcheck |

## Security notes

- Restrict SSH with `SSH_SOURCE_CIDR`, or better, use AWS Systems Manager Session Manager and close port 22 completely (see my [aws-terraform-infrastructure](https://github.com/MultiCloudEng/aws-terraform-infrastructure) project).
- Only HTTP (80) is opened. For production, add TLS (e.g. certbot) and allow 443.

## What was tested

- The original version was run on an Ubuntu EC2 instance.
- The current version was tested on Ubuntu 24.04 (not EC2): `--dry-run` as a non-root user, rejection of an invalid CIDR, an unknown argument and a non-root real run, and `healthcheck.sh` including forced WARNING/CRITICAL thresholds. ShellCheck reports no findings.
- A full real provisioning run of the current version (package install, UFW, systemd) has not been repeated yet. Run it on a fresh EC2 instance before relying on it.

## Skills

Linux administration, Bash (strict mode, traps, idempotency), nginx, UFW, systemd, monitoring basics.
