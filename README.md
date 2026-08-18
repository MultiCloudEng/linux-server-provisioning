# Linux Server Provisioning

Bash automation scripts to provision and monitor an Ubuntu web server on AWS EC2.

## Scripts

### provision.sh
Automates full server setup:
- Updates system packages
- Installs and configures nginx
- Sets up UFW firewall (allows SSH and HTTP)
- Deploys a custom homepage

### healthcheck.sh
Monitors server health:
- Disk usage
- Memory usage
- Nginx service status

## Usage
```bash
chmod +x provision.sh
./provision.sh
```

## Skills
Linux administration, bash scripting, nginx, UFW firewall, AWS EC2, automation.
