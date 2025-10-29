# iPerf3 Stats Ansible Role

This Ansible role provides comprehensive iPerf3 network testing capabilities for both Ubuntu and OpenWRT systems. It supports both **server mode** (to act as an iPerf3 target) and **client mode** (to run automated bandwidth tests and send results to n8n webhook).

## Features

### Server Mode
- Automatic OS detection (Ubuntu/Debian and OpenWRT)
- Installs and configures iPerf3 server as a system service
- Systemd service for Ubuntu/Debian
- init.d service for OpenWRT
- Optional - only enabled when `iperf3_server_enabled: true`

### Client Mode
- Python-based automated testing client using libiperf3
- Scheduled tests via cron jobs
- Tests both upload and download bandwidth
- Retry logic for both tests and webhook delivery
- Sends results to n8n webhook for monitoring
- Configurable timeouts and retry attempts
- Support for interface binding
- Optional - only enabled when `iperf3_client_enabled: true`

## Requirements

- Ansible 2.9 or higher
- For OpenWRT: `community.general` collection (for `opkg` module)
- For client mode: Python 3, pip, and internet access for Python packages

## Role Variables

Available variables are listed below, along with default values (see [defaults/main.yml](defaults/main.yml)):

### Server Configuration

```yaml
# Enable iperf3 server (default: false)
iperf3_server_enabled: false

# Port for iPerf3 server to listen on
iperf3_server_port: 5201

# Idle timeout in seconds before closing connection
iperf3_server_timeout: 40
```

### Client Configuration

```yaml
# Enable iperf3 client script (default: false)
iperf3_client_enabled: false

# Client test runs configuration
# Each entry creates a separate cron job
iperf3_client_runs:
  - cron: "*/15 * * * *"           # Cron schedule
    host: "192.168.1.100"          # Target iperf3 server
    port: 5201                      # Target port
    threads: 4                      # Number of parallel streams
    duration_sec: 30                # Test duration in seconds
    bind_interface: "eth1"          # (Optional) Network interface to bind to

# n8n webhook URL for sending test results
iperf3_client_webhook_url: "https://n8n.example.com/webhook/your-webhook-id"

# Number of retry attempts for iperf3 tests (default: 3)
iperf3_client_test_attempts: 3

# Number of retry attempts for webhook delivery (default: 5)
iperf3_client_webhook_attempts: 5

# Connection timeout for iperf3 tests in seconds (default: 20)
iperf3_client_test_connect_timeout_sec: 20

# Connection timeout for webhook HTTP requests in seconds (default: 20)
iperf3_client_webhook_connect_timeout_sec: 20
```

## Dependencies

None

## Example Playbooks

### Server Only

```yaml
- hosts: iperf_servers
  roles:
    - role: iperf3-stats
      vars:
        iperf3_server_enabled: true
        iperf3_server_port: 5201
        iperf3_server_timeout: 60
```

### Client Only

```yaml
- hosts: monitoring_clients
  roles:
    - role: iperf3-stats
      vars:
        iperf3_client_enabled: true
        iperf3_client_webhook_url: "https://n8n.example.com/webhook/abcd-1234"
        iperf3_client_runs:
          - cron: "*/15 * * * *"
            host: "speedtest-1.example.com"
            port: 5201
            threads: 4
            duration_sec: 30
            bind_interface: "eth1"
          - cron: "0 * * * *"
            host: "speedtest-2.example.com"
            port: 19644
            threads: 1
            duration_sec: 10
```

### Both Server and Client

```yaml
- hosts: all
  roles:
    - role: iperf3-stats
      vars:
        # Enable both server and client
        iperf3_server_enabled: true
        iperf3_client_enabled: true

        # Server config
        iperf3_server_port: 5201

        # Client config
        iperf3_client_webhook_url: "https://n8n.example.com/webhook/xyz-789"
        iperf3_client_runs:
          - cron: "*/30 * * * *"
            host: "peer.example.com"
            port: 5201
            threads: 2
            duration_sec: 20
```

## Usage

### Server Mode

1. Enable the server in your playbook with `iperf3_server_enabled: true`
2. Optionally customize server variables
3. Run your playbook

### Client Mode

1. Enable the client in your playbook with `iperf3_client_enabled: true`
2. Configure your n8n webhook URL
3. Define test runs with schedule, target hosts, and parameters
4. Run your playbook
5. Each configured test will run automatically via cron

## Service Management

### Server - Ubuntu/Debian (systemd)
```bash
sudo systemctl status iperf3
sudo systemctl restart iperf3
sudo systemctl stop iperf3
```

### Server - OpenWRT (init.d)
```bash
/etc/init.d/iperf3 status
/etc/init.d/iperf3 restart
/etc/init.d/iperf3 stop
```

### Client - Manual Test
```bash
# Run a manual test
/usr/local/bin/iperf3_client.py --host 192.168.1.100 --port 5201 --threads 4 --duration 30

# Run with interface binding
/usr/local/bin/iperf3_client.py --host 192.168.1.100 --port 5201 --threads 4 --duration 30 --bind-interface eth1
```

### Client - Cron Management

```bash
# Ubuntu - View cron jobs
crontab -l

# OpenWRT - View cron jobs
cat /etc/crontabs/root
```

## Webhook Payload Format

The client sends the following JSON payload to the n8n webhook:

```json
{
  "start": {
    "connected": [{
      "socket": 1,
      "local_host": "10.0.1.5",
      "local_port": 54321,
      "remote_host": "192.168.1.100",
      "remote_port": 5201
    }],
    "test_start": {
      "protocol": "TCP",
      "num_streams": 4,
      "duration": 30,
      "reverse": 0
    }
  },
  "end": {
    "sum_sent": {
      "bytes": 3750000000,
      "bits_per_second": 1000000000
    },
    "sum_received": {
      "bytes": 0,
      "bits_per_second": 0
    }
  },
  "sent_Mbps": 953.67,
  "received_Mbps": 0.0,
  "sent_bytes": 3750000000,
  "received_bytes": 0,
  "retransmits": 0,
  "node_host": "192.168.1.100",
  "test_type": "upload",
  "timestamp": "2025-01-15T10:30:00.123456",
  "bind_interface": "eth1"
}
```

Each test execution sends **two** webhook calls:
1. One for download test (`test_type: "download"`)
2. One for upload test (`test_type: "upload"`)

## Testing

### Test Server

After deploying a server, test from a client machine:

```bash
iperf3 -c <server-ip> -p 5201
```

### Test Client

After deploying a client, check logs in syslog or run manually:

```bash
# Manual run
/usr/local/bin/iperf3_client.py --host <server-ip> --port 5201 --threads 4 --duration 10

# Check cron execution logs (Ubuntu)
grep iperf3_client /var/log/syslog

# Check cron execution logs (OpenWRT)
logread | grep iperf3
```

## License

MIT

## Author Information

Created for home-ops infrastructure automation.
