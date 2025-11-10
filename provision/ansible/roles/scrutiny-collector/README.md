# Scrutiny Collector Role

This Ansible role installs and configures the Scrutiny collector for monitoring disk health without Docker.

## Requirements

- Ubuntu/Debian system
- Root access
- smartmontools installed (handled by role)

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

```yaml
# Scrutiny collector version (GitHub release tag)
scrutiny_collector_version: "v0.8.1"

# Scrutiny API endpoint (the web interface URL)
scrutiny_collector_api_endpoint: "http://localhost:8080"

# Cron schedule for collector runs (default: every 15 minutes)
scrutiny_collector_cron_minute: "*/15"
scrutiny_collector_cron_hour: "*"
scrutiny_collector_cron_day: "*"
scrutiny_collector_cron_month: "*"
scrutiny_collector_cron_weekday: "*"

# List of devices to monitor (e.g., ["/dev/sda", "/dev/nvme0"])
scrutiny_collector_devices: []

# Installation directory
scrutiny_collector_install_dir: "/opt/scrutiny-collector"

# Configuration directory
scrutiny_collector_config_dir: "/etc/scrutiny"
```

## Example Inventory

```yaml
all:
  children:
    scrutiny-collector:
      hosts:
        server1:
          scrutiny_collector_api_endpoint: "http://scrutiny.example.com:8080"
          scrutiny_collector_devices:
            - /dev/sda
            - /dev/nvme0
```

## Example Playbook

```yaml
- hosts: scrutiny-collector
  become: true
  roles:
    - scrutiny-collector
```

## Usage

Run the playbook:

```bash
ansible-playbook playbooks/scrutiny-collector-install.yaml
```

## What This Role Does

1. Installs required packages (smartmontools, curl, cron)
2. Downloads the scrutiny-collector binary from GitHub releases
3. Creates configuration directory and file
4. Sets up a cron job to run the collector periodically
5. Logs output to `/var/log/scrutiny-collector.log`

## Manual Testing

After installation, you can manually run the collector:

```bash
/opt/scrutiny-collector/scrutiny-collector-metrics run --config /etc/scrutiny/collector.yaml
```

## License

MIT
