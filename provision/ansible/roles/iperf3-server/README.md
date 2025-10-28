# iPerf3 Server Ansible Role

This Ansible role installs and configures iPerf3 server on both Ubuntu and OpenWRT systems.

## Features

- Automatic OS detection (Ubuntu/Debian and OpenWRT)
- Installs iPerf3 package
- Configures iPerf3 as a system service:
  - Systemd service for Ubuntu/Debian
  - init.d service for OpenWRT
- Enables and starts the service automatically

## Requirements

- Ansible 2.9 or higher
- For OpenWRT: `community.general` collection (for `opkg` module)

## Role Variables

Available variables are listed below, along with default values (see [defaults/main.yml](defaults/main.yml)):

```yaml
# Port for iPerf3 server to listen on
iperf3_server_port: 5201

# Idle timeout in seconds before closing connection
iperf3_server_timeout: 40
```

## Dependencies

None

## Example Playbook

```yaml
- hosts: all
  roles:
    - role: iperf3-server
      vars:
        iperf3_server_port: 5201
        iperf3_server_timeout: 60
```

## Usage

1. Include the role in your playbook
2. Optionally customize variables:
   - `iperf3_server_port`: Change the listening port (default: 5201)
   - `iperf3_server_timeout`: Change idle timeout in seconds (default: 40)

## Service Management

### Ubuntu/Debian (systemd)
```bash
sudo systemctl status iperf3
sudo systemctl restart iperf3
sudo systemctl stop iperf3
```

### OpenWRT (init.d)
```bash
/etc/init.d/iperf3 status
/etc/init.d/iperf3 restart
/etc/init.d/iperf3 stop
```

## Testing

After deployment, you can test the server from a client machine:

```bash
iperf3 -c <server-ip> -p 5201
```

## License

MIT

## Author Information

Created for home-ops infrastructure automation.
