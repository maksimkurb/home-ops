# LucX-UI Ansible role

Deploys LucX-UI as a single Docker container. The host is intentionally kept
minimal: Docker Engine/Compose is installed, while Xray, AmneziaWG userspace,
routing helpers, and panel state stay inside the container.

## State

Persistent state is stored below `/opt/lucx-ui`:

- `db/` — LucX-UI SQLite database (inbounds, clients, routing, settings).
- `cert/` — panel-managed certificates.
- `acme/` — ACME state.
- `backups/` — timestamped local backup archives.

Before an existing installation is redeployed, the role stops the container,
archives those directories, starts it again, and optionally fetches the archive
to the Ansible controller.

Controller backups default to:

```text
~/.local/share/home-ops/lucx-ui/<inventory_hostname>/
├── latest.tar.gz
└── lucx-ui-YYYYMMDDTHHMMSSZ.tar.gz
```

A fresh host automatically restores `latest.tar.gz` for the same
`inventory_hostname` before LucX-UI starts. Existing state is never overwritten
unless `lucx_ui_restore_force=true`.

## Commands

Install or update:

```sh
task ansible:playbook:lucx-ui-install -- --limit vps-1
```

Create an off-host backup:

```sh
task ansible:playbook:lucx-ui-backup -- --limit vps-1
```

Restore the controller's latest backup:

```sh
task ansible:playbook:lucx-ui-restore -- --limit vps-1
```

Restore a specific controller-side archive:

```sh
task ansible:playbook:lucx-ui-restore -- \
  --limit vps-1 \
  -e lucx_ui_restore_archive=/path/to/lucx-ui-20260921T120000Z.tar.gz
```

For a replacement VPS, keep the same Ansible inventory hostname if you want
automatic restore from its `latest.tar.gz`.
