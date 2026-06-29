# home-ops

Home infrastructure as code, managed with Kubernetes, Flux, SOPS, Renovate, and Ansible.

## Overview

This repository defines a K3s cluster and supporting hosts. Flux watches `cluster/` and applies the Kubernetes manifests. Ansible under `provision/ansible/` handles host setup that sits outside normal Kubernetes app changes.

Most Kubernetes services are configured in `cluster/apps/<namespace>/<app>/` and follow the local Flux `Kustomization` plus HelmRelease pattern. New app manifests should usually copy a nearby app that already uses the bjw-s `app-template` chart.

## Core Components

- K3s: Kubernetes distribution installed through Ansible.
- Flux: GitOps controller installed from `cluster/bootstrap/` and reconciled through `cluster/flux/`.
- SOPS with Age: encrypted secret handling for Flux, Ansible, and app manifests.
- ingress-nginx: public and private HTTP ingress.
- MetalLB: LoadBalancer service addresses.
- external-dns: DNS records from annotated ingresses and services.
- cert-manager: TLS certificates.
- local-path-provisioner and NFS-backed PV/PVCs: persistent app data.
- Zalando Postgres Operator: shared PostgreSQL cluster in `database`.

## Cluster Layout

```text
cluster/
├── bootstrap/  # one-time Flux component bootstrap
├── flux/       # Flux GitRepository and top-level Kustomizations
├── charts/     # HelmRepository resources
├── config/     # shared cluster settings and encrypted cluster secrets
├── crds/       # CRDs loaded before core and apps
├── core/       # cluster services loaded before apps
└── apps/       # namespaced app tree
```

Flux load order is `charts`, `config`, `crds`, `core`, then `apps`.

## App Pattern

Apps live under `cluster/apps/<namespace>/<app>/`.

- Parent namespace kustomizations include each app `ks.yaml`.
- `ks.yaml` points Flux at the app folder and injects `cluster-settings` plus `cluster-secrets`.
- App folders usually contain `app/kustomization.yaml`, `app/helm-release.yaml`, and optional PVC, ConfigMap, certificate, dashboard, or non-secret config files.
- Public ingress uses `className: nginx`; private ingress uses `className: nginx-intra`.

## Shared Configuration

Non-secret substitutions live in `cluster/config/cluster-settings.yaml`; encrypted substitutions live in `cluster/config/cluster-secrets.sops.yaml`.

Important current values:

| Name | Value |
| --- | --- |
| Control plane endpoint | `10.75.40.21` |
| Pod CIDR | `172.22.0.0/16` |
| Service CIDR | `172.24.0.0/16` |
| Static service range | `10.5.0.0/24` |
| Auto-assigned MetalLB range | `10.5.2.0/23` |
| NFS host | `10.75.40.1` |
| Default app data root | `/tank/pod-data` |
| Media root | `/tank/media` |
| MinIO root | `/tank/minio` |
| Postgres NFS root | `/tank/postgres` |

Static LoadBalancer addresses use `SVC_*_ADDR` keys from `cluster/config/cluster-settings.yaml`.

## Common Commands

Task commands are defined in `Taskfile.yml` and `.taskfiles/`.

```sh
task cluster:verify
task cluster:install
task cluster:reconcile
task precommit:run
```

`task precommit:init` bootstraps `pre-commit` into a repo-local `.venv` using `uv`
when available, or `python3 -m venv` as a fallback. The Git hook itself is stored
in `.githooks/`, so no OS-level `pre-commit` package is required.

Use `task cluster:reconcile` only when intentionally applying Git state to the cluster.

## Secrets

SOPS files are encrypted repo state. Do not commit decrypted files or generated `.decrypted~*` files.

AI agents must not decrypt or edit encrypted SOPS files; if a secret change is required, they should print the cleartext snippet for the human operator to apply.

## License

See [LICENSE](./LICENSE).
