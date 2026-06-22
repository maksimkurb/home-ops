# AGENTS.md

## Project Shape

This repository is the source of truth for a home infrastructure GitOps setup.

- `cluster/` is the Flux-managed Kubernetes source of truth.
- Flux load order is `cluster/charts`, `cluster/config`, `cluster/crds`, `cluster/core`, then `cluster/apps`.
- `provision/ansible/` is host provisioning. Do not touch it for ordinary Kubernetes app or service changes.
- `Taskfile.yml` and `.taskfiles/` hold common commands.

## Kubernetes Apps

- Services live under `cluster/apps/<namespace>/<app>/`.
- Namespace parent files, for example `cluster/apps/default/kustomization.yaml`, include each app `ks.yaml`.
- Each `ks.yaml` is a Flux `Kustomization` that points at the app folder, usually `./cluster/apps/<namespace>/<app>/app`.
- `ks.yaml` normally enables SOPS decryption and injects `cluster-settings` plus `cluster-secrets` with `postBuild.substituteFrom`.
- App folders usually contain `app/kustomization.yaml`, `app/helm-release.yaml`, and optional PVC, ConfigMap, certificate, dashboard, or non-secret config files.
- Prefer the existing bjw-s `app-template` HelmRelease pattern before adding new chart structure.

## Service Configuration

- Non-secret shared values live in `cluster/config/cluster-settings.yaml`.
- Static LoadBalancer IPs come from `SVC_*_ADDR` keys in `cluster/config/cluster-settings.yaml`.
- MetalLB pools live in `cluster/apps/networking/metallb/pools/pools.yaml`.
- Public HTTP ingress uses `className: nginx`; private HTTP ingress uses `className: nginx-intra`.
- Use `${SECRET_PUBLIC_DOMAIN}`, `${SECRET_PRIVATE_DOMAIN}`, `${INGRESS_DEFAULT}`, and existing external-dns annotations instead of hardcoding domains or targets.

## Storage

- Default app config PVCs usually use `storageClassName: local-path`.
- `local-path` maps to `/tank/pod-data/` via `cluster/core/local-path-provisioner/helm-release.yaml`.
- Shared NFS roots are defined in `cluster/config/cluster-settings.yaml`: `NFS_PROXMOX_POD_DATA`, `NFS_PROXMOX_MEDIA`, `NFS_PROXMOX_MINIO_DATA`, `NFS_PROXMOX_CCTV`, `NFS_PROXMOX_POSTGRES`, and backup paths.
- For NFS-backed data, copy the closest existing PV/PVC pattern.

## Database

- PostgreSQL is managed by Zalando operator under `cluster/apps/database/zalando/`.
- The main cluster is `homelab-pgsql` in namespace `database`.
- In-cluster host is `homelab-pgsql.database.svc.cluster.local` or `homelab-pgsql.database`.
- Add new database users and databases in `cluster/apps/database/zalando/postgres-cluster.yaml`.
- Cross-namespace credential secrets follow `{username}.homelab-pgsql.credentials.postgresql.acid.zalan.do`.

## SOPS Rules

AI agents must not decrypt or modify encrypted SOPS files.

- Never run `sops -d`, `sops edit`, or equivalent decrypt/edit commands.
- Never modify encrypted files matching `*.sops.yaml`, `*.sops.yml`, `*.sops.json`, `*.sops.toml`, or `*.sops.conf`.
- Reading encrypted SOPS files is allowed only to inspect visible metadata, resource names, keys, and structure.
- If a secret change is needed, leave encrypted files untouched and print the exact cleartext YAML, TOML, JSON, or key-value snippet for the user to apply manually.
- Never commit decrypted temporary files such as `.decrypted~*`.

## Validation

- Run `task cluster:reconcile` only when intentionally applying changes.
- Run `task precommit:run` before handing off broader YAML changes.
- Use `kubectl kustomize cluster/apps/<namespace>` for focused render checks.
