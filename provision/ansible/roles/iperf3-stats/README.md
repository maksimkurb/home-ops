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
- Tests both upload and download bandwidth (TCP slow-start dropped with `--omit`)
- Idle and loaded ping: latency, loss, jitter (works with iputils and BusyBox ping)
- Traceroute with [ttl](https://github.com/lance0/ttl) before the load: an ICMP pass
  (per-hop loss/latency/jitter) and a multi-flow UDP pass (ECMP discovery);
  static musl binaries for x86_64 and aarch64 on Debian/Ubuntu and OpenWrt
- Retry logic for both tests and webhook delivery
- Sends results to n8n webhook for monitoring
- Configurable timeouts and retry attempts
- Support for interface binding
- Optional - only enabled when `iperf3_client_enabled: true`

## Requirements

- Ansible 2.9 or higher
- For OpenWRT: `community.general` collection (for `apk` module)
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

# Override the client hostname in webhook payloads (optional)
iperf3_client_hostname: ""

# Client test runs configuration
# Each entry creates a separate cron job
iperf3_client_runs:
  - cron: "*/15 * * * *"           # Cron schedule
    host: "192.168.1.100"          # Target iperf3 server
    port: 5201                      # Target port
    threads: 4                      # Number of parallel streams
    duration_sec: 7                 # Measured seconds per direction
    omit_sec: 1                     # (Optional) Slow-start seconds dropped first (default iperf3_client_omit_sec)
    bind_interface: "eth1"          # (Optional) Network interface to bind to
    client_hostname: "h-3-wan1"     # (Optional) Per-run override of iperf3_client_hostname
    trace: true                     # (Optional) Run the ttl traceroute (default iperf3_client_trace_enabled)
  - cron: "*/15 * * * *"
    host: "game.example.com"
    icmp_only: true                 # Ping (+ traceroute) only, no iperf3
    count: 10

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

# Slow-start seconds iperf3 drops before measuring (default: 1)
iperf3_client_omit_sec: 1

# Traceroute (see defaults/main.yml for the full list)
iperf3_client_trace_enabled: true
iperf3_client_trace_path_rounds: 10     # ICMP probes per hop
iperf3_client_trace_ecmp_flows: 4       # source ports for ECMP discovery
iperf3_client_trace_interval_sec: 1.0   # keep >= 1, see below
iperf3_client_ttl_version: "0.24.1"     # bump together with iperf3_client_ttl_checksums
```

One run takes about `10 s` (traceroute and idle ping in parallel) `+ 2 × (omit_sec + duration_sec)`.
Keep `iperf3_client_trace_interval_sec` at 1 s or more: Linux routers rate-limit ICMP
time-exceeded replies (`net.ipv4.icmp_ratelimit`, 1 s with a burst of ~6), and faster probing
shows up as fake loss on intermediate hops.

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
4. Optionally set `iperf3_client_hostname` when the reported hostname should differ from the system hostname; a run can override it with its own `client_hostname` (e.g. one per WAN interface)
5. Run your playbook
6. Each configured test will run automatically via cron

On Ubuntu/Debian, the role installs Python dependencies into `/opt/iperf3-client-venv` and deploys `/usr/local/bin/iperf3_client.py` with that venv shebang.

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
/usr/local/bin/iperf3_client.py --host 192.168.1.100 --port 5201 --threads 4 --duration 7

# Without the traceroute
/usr/local/bin/iperf3_client.py --host 192.168.1.100 --port 5201 --threads 4 --duration 7 --no-trace

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

Each invocation sends several webhook calls that share a `run_id`; every call carries
`schema_version: 2`, `test_type`, `source_hostname`, `target_hostname`,
`iperf_run_on_hostname`, `timestamp` and, when set, `bind_interface`.

| `test_type` | Body |
|---|---|
| `trace` | `trace.path` / `trace.ecmp`: ttl JSON sessions without the per-probe event log, cut at the destination |
| `download` | raw iperf3 JSON (reverse mode) + `omit_sec`, `duration_sec`, `latency_idle`, `latency_loaded` |
| `upload` | same, normal mode |
| `icmp` | `--icmp-only` runs: empty `intervals`/`end` + `latency_idle` |

`latency_idle` / `latency_loaded`: `loss_pct`, `sent`, `received`, `min_ms`, `avg_ms`,
`max_ms`, `stddev_ms`, `jitter_ms` (mean absolute difference of consecutive RTTs).

## n8n and Postgres

[`n8n/`](n8n/) holds the server side:

- `schema-v2.sql`: migration for the `lab` database (idempotent). Adds `test_type`, `run_id`,
  `peer_host_id` and receiver/sender Mbps to `iperf_logs`, the `iperf_traces`,
  `iperf_trace_hops` and `iperf_trace_responders` tables, `iperf_ingest(jsonb)`
  (atomic, idempotent ingest of any payload above, v1 payloads included) and `iperf_prune()`.
- `workflow-v3.json`: "Send speed results 3.0" (Webhook → validate → `SELECT iperf_ingest(...)`,
  answering only after the insert so failed ingests are retried by the client; the
  kill-switch branch is unchanged; daily prune at 04:00). The webhook path is the
  `__IPERF_WEBHOOK_PATH__` placeholder; use the path from `iperf3_client_webhook_url`.

Rollout order: apply `schema-v2.sql` → import the workflow over "Send speed results 2.0"
(same id, so the webhook URL does not change) → run this role. Old clients keep working
with the new workflow; new clients need it (the v2 workflow would store traces as 0 Mbps rows).

The Grafana dashboard is `cluster/apps/monitoring/grafana/app/dashboards/iperf-n8n-stats.json`.

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
