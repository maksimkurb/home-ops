# openwrt-rpc-ro: read-only RPC access to an OpenWrt router

This guide is for an agent (Hermes and similar) that diagnoses network, VPN and DNS problems on OpenWrt routers.
There is no shell. Access is HTTP JSON-RPC to `ubus`, read-only, from the EasyTier overlay and from the LAN. It is protected by a login and an ACL.

## How to connect

| Parameter | Value |
|---|---|
| URL | `http://<router-ip>/ubus` (port 80, the same uhttpd that serves LuCI) |
| Login | `hermes` (`rpc_ro_username`) |
| Password | `rpc_ro_password`, stored in `inventory/group_vars/openwrt-rpc-ro/rpc-ro.sops.yaml` |
| From where | the EasyTier network and the LAN (`rpc_ro_allow_zones`). The role does not open the port on the WAN |

There is no TLS. EasyTier encrypts the traffic inside the overlay, but over the LAN the password travels in clear text, so connect from trusted LAN hosts only.
Use the router's overlay IP (see the EasyTier panel) or its LAN address (for example `192.168.x.1`).

The port and the list of views are set by the `rpc_ro_*` variables in `defaults/main.yaml`.

### 1. Log in

The all-zero SID `00000000000000000000000000000000` means "not logged in".

```sh
R=http://<router-ip>/ubus
curl -s $R -d '{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"hermes","password":"PASSWORD"}]}'
# -> {"result":[0,{"ubus_rpc_session":"<SID>", ...}]}
```

A session lives for 300 seconds. If a call that should be allowed returns `-32002` (or `[6]`), log in again.

### 2. Make a call

The format is always the same: `params = [SID, object, method, {arguments}]`.

```sh
SID=<ubus_rpc_session>
call() { curl -s $R -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"call\",\"params\":[\"$SID\",$1]}"; }

call '"system","board",{}'
call '"network.interface","dump",{}'
call '"file","read",{"path":"/proc/loadavg"}'
call '"file","exec",{"command":"/usr/libexec/rpc-ro-view","params":["dns-probe"]}'
```

The reply is `{"result":[0, {...}]}`, where `0` means success. For `file exec` the output is in `result[1]`: `code`, `stdout`, `stderr`.
"Access denied" comes in two forms, and both are expected for anything not listed below: `{"error":{"code":-32002,...}}`
(the ubus object or method is not allowed) and `{"result":[6]}` (ubus status 6, `PERMISSION_DENIED`: the object is allowed,
but not this file path or command line, for example a `file exec` outside the views).

## Diagnostic views

The main tool is `file exec` with the command `/usr/libexec/rpc-ro-view` and exactly one argument, `params: ["<view>"]`.
The ACL rejects any other command and any extra argument. The one exception is `test-routing`, see below.
Every view finishes in under 10 s except `delta` (about 6 s); the whole call must stay under 30 s.

| View | What it shows | When to use it |
|---|---|---|
| `snapshot` | `time` + `conntrack` + `dns-probe` + `links` + `kernel` + `keen-pbr` + `resolver dnsmasq detect` in one call | first, at the moment of a failure: one call instead of seven, about 2 s |
| `delta` | what the counters grew by in the last 5 s: bytes and drops per interface, bytes per AWG peer (`<-- no traffic` if both directions are 0), conntrack and DNS flows, softnet drops, TCP retransmits, UDP errors, dnsmasq `forwarded`/`unanswered` | "what is happening right now": every other view shows totals since boot, in which a 3-minute outage is invisible |
| `time` | local time, UTC, timezone, uptime, NTP servers, `ntpd` running | compare clocks first when logs and reports disagree |
| `tunnel-path` | ping x5 to every AWG peer endpoint over the outer path, TCP connect to the endpoint port and to 443, and a control TCP to `1.1.1.1:443` | "is the path to the VPS dead, or is the VPS not answering": loss and the failing step are visible |
| `mtu` | interface MTUs, MSS clamping in nft, a DF ping sweep (100 is the control, then 1200 to 1500) to every endpoint and inside the tunnel | "hangs for a minute and recovers" looks like a PMTU black hole. The line `largest DF size that passed` is the usable size |
| `agh-stats` | AdGuardHome query log, last 20000 entries: per-upstream queries, avg/p95/max ms and rcodes, top domains, top clients | which upstream is failing or slow (SERVFAIL, high p95), and whether the load is real traffic or a flood of `stun-*` queries |
| `dns-probe` | for every resolver in `rpc_ro_dns_probe_servers` (the router's own 127.0.0.1, 8.8.8.8, 77.88.8.8, 9.9.9.10, ...): an A query for the probe domain over UDP (2 tries) and over TCP, plus a control name over UDP. Prints rcode, number of answers and time for each, and a verdict | "DNS does not work": separates a resolver that does not answer from one that answers NXDOMAIN, and spots UDP/53 being tampered with |
| `conntrack` | count/max, number of DNS flows, top `dst` and `dport`, `sockstat`, `softnet_stat`, memory, load, `top` | conntrack or UDP memory exhaustion suspected |
| `egress` | external IP and a direct TCP request to `77.88.8.8` | which exit the router's own traffic uses |
| `links` | `ip -d -s link`: counters, errors and drops of every interface | packet loss, errors, links that went down |
| `routing` | `ip rule` v4/v6, routes of all tables, addresses | where traffic goes, keen-pbr tables, fwmark |
| `vpn` | `awg show all` (handshake, endpoint, traffic) and tun/vpn links | is the tunnel alive, when was the last handshake |
| `keen-pbr` | `keen-pbr status` and `test-routing` for the configured domains (`rpc_ro_pbr_test_domains`) | state of the outbounds and routing rules |
| `keen-pbr-status` | `keen-pbr status` only, in full | state of the outbounds |
| `keen-pbr-dnsmasq` | `keen-pbr resolver dnsmasq detect` and `print-config`: which dnsmasq keen-pbr uses, and the config it generates | DNS rules (which domains go to which resolver), hook and drop-in state |
| `kernel` | `dmesg` filtered for conntrack, drop, oom, table full | the kernel is complaining |
| `procs` | PID and process name, no arguments | which daemons are running |
| `easytier` | `easytier-cli` `node`, `peer`, `route`, `connector list`, `proxy`, `acl stats`: own address, peers, latency and loss, routes, connectors | the overlay is down or a peer is unreachable |
| `easytier-stats` | `easytier-cli stats`: traffic and connection counters | overlay throughput and error counters |
| `config-adguardhome` | `adguardhome.yaml` without passwords and keys | DNS filter settings |
| `config-keen-pbr` | keen-pbr `config.json` without password and token hashes | routing settings |
| `syslog` | the last 200 lines of the system log | "what just happened", including logs that are not shipped to VictoriaLogs (amneziawg) |
| `syslog-errors` | the last 150 lines of the log that match error, warning, handshake, awg, dnsproxy, keen-pbr, easytier, netifd, l2tp | the same, filtered |

Secrets are masked in the views (`<redacted>`). That is expected, do not try to get them another way.

### `test-routing`: the one view with arguments

```sh
call '"file","exec",{"command":"/usr/libexec/rpc-ro-view","params":["test-routing","youtube.com","--proto","tcp","--dest-port","443"]}'
```

`test-routing <ip-or-domain> [--proto tcp|udp|other] [--src-addr IP] [--src-port N] [--dest-port N] [--dscp 0-63]` runs
`keen-pbr test-routing`: expected against actual outbound for an IP or a domain (resolved through the router's dnsmasq), with the
packet you describe, for example to check the rule for one client (`--src-addr`) or one service (`--dest-port`).
Every option is optional, takes exactly one value and may appear once. Anything else (another option, a shell fragment,
a host name with spaces) is refused with exit code 2 and a usage line.

### Reading the system log

`log read` is allowed. Pass `{"lines":N,"stream":false}`: without `"stream":false` it answers with an empty body, because the
default is to stream the log. The `syslog` views above need no arguments.

## What can be read directly

`file read {"path": ...}`:

- `/proc/loadavg`, `/proc/uptime`, `/proc/meminfo`, `/proc/softirqs`
- `/proc/net/dev`, `/proc/net/sockstat`, `/proc/net/softnet_stat`, `/proc/net/route`, `/proc/net/arp`
- `/proc/sys/net/netfilter/nf_conntrack_count`, `/proc/sys/net/netfilter/nf_conntrack_max`
- `/etc/resolv.conf`, `/tmp/resolv.conf.d/resolv.conf.auto`
- `/etc/dnsmasq.conf`, `/var/etc/dnsmasq.conf.*`, `/tmp/dnsmasq.*.d/*`. The last one includes `keen-pbr.conf`, and the `cfgXXXXXX` part of the path can be any number
- `/tmp/dhcp.leases`
- `/tmp/keen-pbr-crash.log.current`, `/tmp/keen-pbr-cmdfail.log`

ubus calls:

| Object | Methods |
|---|---|
| `system` | `board`, `info` |
| `log` | `read` |
| `network.interface` | `dump` |
| `network.device` | `status` |
| `luci-rpc` | `getDHCPLeases`, `getNetworkDevices`, `getHostHints`, `getBoardJSON` |
| `dnsmasq` | `metrics` |
| `iwinfo` | `devices`, `info`, `assoclist` |
| `luci` | `getVersion`, `getUnixtime`, `getFeatures` |
| `luci.pbr` | `getInitStatus`, `getInterfaces` |
| `luci.netbird` | `get_status`, `list_peers`, `list_networks`, `get_connection_info` |
| `luci.amneziawg` | `getAwgInstances` |
| `rc` | `list` |

The actual list of permissions is in `/usr/share/rpcd/acl.d/rpc-ro.json` on the router. If a call returns `-32002`, it is not in there.

## Where to start

- **"Everything is down", "DNS does not work".** Call `snapshot` right away.
  - In `dns-probe`, `127.0.0.1` with `no answer` or `SERVFAIL` while the others are `ok`: AdGuard, dnsmasq or the keen-pbr DNS proxy on the router is the culprit. Look at `keen-pbr-dnsmasq`, `config-adguardhome`, `agh-stats`, `dnsmasq metrics` and `syslog-errors`.
  - **`NXDOMAIN` is an answer, not an outage.** If a resolver answers `NXDOMAIN` or no answers over UDP while TCP and the control name are fine (the verdict says "UDP/53 answers are rewritten or dropped on the path"), the provider's path is tampering with plain UDP DNS for that name. Resolver 8.8.8.8 does this to `youtube.com` on routers behind the Saratov provider (router-3sad, router-tkh2), router-kaz is not affected. Do not raise an alert for it: alert on `no answer` over both UDP and TCP, on the router's own resolver failing, or on `delta`/`tunnel-path` showing real loss.
  - Several resolvers say `no answer` at once, including ones that go through a tunnel (the `routing` view shows which interface each target uses): check `tunnel-path` and `delta` for that tunnel.
  - In `conntrack`, `count` close to `max`: the table is full. Look at the top `dst` and `dport` and at `kernel` (`table full`).
- **"It was down for a few minutes and now it is fine".** The totals hide it, so catch it live: call `delta` while it happens (or right after, together with `syslog-errors` and `agh-stats` for the history). A peer with `<-- no traffic`, growing `drop` or `softnet.dropped`, or `dnsmasq.dns_unanswered` growing as fast as `forwarded` points at the cause.
- **"The VPN does not work".** `vpn`: for the peer, check `latest handshake` (it keeps updating while anything gets through, so a fresh one does not prove the path is fine) and `transfer`. Then `tunnel-path`: the ping loss and the TCP lines separate "the path to the VPS is dead" from "the VPS does not answer". Then `mtu` (`largest DF size that passed`) and `keen-pbr`: the outbound state is `UNAVAILABLE` or `HEALTHY`. Then `routing`: are the rules and routes of the right table there.
- **"DNS is slow or fails for some names".** `agh-stats`: which upstream has SERVFAIL or a high p95. `dns-probe` for who answers. `keen-pbr-dnsmasq` for which resolver a domain is sent to.
- **"The overlay / a peer is unreachable".** `easytier`: is the peer in `peer` and `route`, its `cost`, `lat(ms)` and `loss`, are connectors up. Then `links` for `tun0` and `routing`.
- **"Wrong exit, wrong IP".** `egress`, then `test-routing <domain-or-ip>` with the client's address and port, and `routing`.
- **"Packet loss, slowness".** `links`: are `errors` and `dropped` growing. `conntrack`: `softnet_stat` (the second column is drops) and load.

## What is not available, and will not be

This is deliberate, do not try to work around it:

- Any write or action: `uci`, `system reboot`, `service`, restarting anything.
- Configs with keys: `/etc/config/*`, `network.wireless status` (Wi-Fi passwords), `service list` and process lists with arguments (they hold tokens), `awg showconf`.
- Arbitrary commands: `file exec` is allowed only for the views above. This includes `easytier-cli`: only the fixed read-only subcommands of the `easytier` views run, never `connector add`, `port-forward`, `credential`, `service`, `logger`, `dns`, `whitelist` or `vpn-portal`.
- The whole of `/proc/net/nf_conntrack` (every LAN connection). The `conntrack` view has the aggregates.

If the view you need does not exist, tell the human. New views are added to the role, not by working around the restrictions.

## For the administrator

- Install: `task ansible:playbook:openwrt-rpc-ro-install`. Hosts are in the `openwrt-rpc-ro` group in `inventory/hosts.yaml`.
- The `cubly_et` interface over `tun0` and the `easytier` zone are created if they are missing (`easytier/tasks/openwrt-network.yaml`).
- Password: `sops -d provision/ansible/inventory/group_vars/openwrt-rpc-ro/rpc-ro.sops.yaml`.
- The views are one Python 3 file, `files/rpc-ro-view` (no shell; every command runs as an argument list with a fixed environment), installed to `/usr/libexec/rpc-ro-view`. Its settings (probe domains and servers, tunnel ports, MTU sizes, ...) are the `rpc_ro_*` variables, rendered to `/etc/rpc-ro/view.json`.
- A new view is a `v_<name>` function and an entry in `VIEWS`, plus its name in `rpc_ro_views`. The ACL is built from that list automatically and the role fails if the script and the list disagree (`rpc-ro-view --list`). Do not add a view that prints secrets.
- A view with arguments goes into `rpc_ro_views_with_args` and gets an ACL pattern (`<view> *`), so the script must validate every argument itself. Only `test-routing` does this today; copy its checks.
- Some settings are per router and live in `inventory/host_vars/<host>/<host>.yaml`, not in the role defaults: `rpc_ro_tunnel_ifaces` (the AWG interfaces that `tunnel-path` and `mtu` probe; a hub such as router-3sad lists only its client tunnel, otherwise it would probe every client endpoint) and `rpc_ro_mtu_inner_targets` (the far end of each tunnel, `{host, dev}`; it must answer `ping -I <dev> <host>` on that router). A router without them is probed on every AWG endpoint and has no in-tunnel DF test. All three routers are filled in; for a new one run `awg show all endpoints` and `ping -I <iface> <peer address>` on it first.
- Python 3 is required on the router (the playbook installs it for Ansible). A view that needs a tool the router lacks says so and does not fail the others.
- At the end of every run the role checks over HTTP: login, an allowed call, denial of `uci get`, denial of `exec` of another command or with an extra argument, and that `test-routing` refuses a bad target and an unknown option.
