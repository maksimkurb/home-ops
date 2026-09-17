---
name: add-app-template-service
description: Add or migrate Kubernetes services in this home-ops repository using Flux Kustomizations, Kustomize resources, and the existing bjw-s app-template HelmRelease pattern. Use for new apps, namespaces, routes, persistence, and namespace-local secret wiring; do not use for Ansible provisioning or non-Kubernetes services.
---

# Add App Template Service

Build the smallest service definition consistent with the repository. Preserve the user's requested topology; do not add optional databases, caches, dashboards, observability, or high availability without a demonstrated requirement.

## Discover the local pattern

1. Read the root `AGENTS.md` and obey its SOPS and validation rules.
2. If `.codegraph/` exists, use CodeGraph before text search when locating relevant code.
3. Inspect the closest existing app by runtime shape: single container, multiple controllers, TCP/UDP service, public/private HTTP route, PVC, NFS, database, or local Secret.
4. Reuse the repository's current chart version and field conventions. Do not copy an older Ingress or app-template schema when nearby apps use `HTTPRoute` or newer fields.
5. Verify current upstream image, entrypoint, ports, health endpoint, UID/GID, and required configuration from primary sources when they are not already established in the repository.

## Create the service

For `cluster/apps/<namespace>/<app>/`, normally create only:

- `ks.yaml`: Flux `Kustomization` targeting the namespace and app folder, with SOPS decryption and `cluster-settings`/`cluster-secrets` substitution.
- `app/kustomization.yaml`: includes the HelmRelease and only the extra resources actually required.
- `app/helm-release.yaml`: bjw-s `app-template` HelmRelease matching the nearest maintained example.

When creating a namespace, also create `namespace.yaml` and the namespace-level `kustomization.yaml`, then include that namespace from `cluster/apps/kustomization.yaml`. When adding an app to an existing namespace, include its `ks.yaml` in the existing namespace kustomization.

In the HelmRelease:

- Pin an explicit image version or digest when upstream publishes stable releases.
- Add minimal requests/limits and probes supported by a real endpoint or socket.
- Use `${TIMEZONE}`, `${SECRET_PUBLIC_DOMAIN}`, `${SECRET_PRIVATE_DOMAIN}`, `${INGRESS_DEFAULT}`, and existing annotations instead of hardcoded shared values.
- Use the public Gateway parent for public routes and the private parent for private routes, following the closest current app.
- Use `local-path` for ordinary configuration/data PVCs unless the user requests shared storage; copy an existing NFS PV/PVC pattern when shared storage is required.
- Prefer a namespace-local Kubernetes Secret for app-specific credentials. Reference it with `secretKeyRef` or `envFrom`.

## Secrets

Never decrypt, create plaintext under, or modify a `*.sops.*` file. If a new secret is required:

1. Wire the workload to the intended Secret name and keys.
2. Print the exact cleartext Secret manifest for the user to encrypt and add manually.
3. Do not add the missing encrypted file to `app/kustomization.yaml` until it exists, because that would make local rendering fail. Clearly tell the user which resource line to add afterward.

Do not move app-specific credentials into `cluster-secrets` unless the user explicitly wants shared substitution values.

## Authentication

Prefer native community-edition OIDC/OAuth support. Follow the existing Authelia client and authorization-policy conventions, including the requested group restriction. Use the existing Traefik OIDC middleware only for browser UIs that lack native SSO; never place browser-login middleware in front of S3, WebDAV, API, webhook, or other machine-client endpoints unless protocol compatibility is verified.

## Validate and hand off

Run:

```bash
kubectl kustomize cluster/apps/<namespace>
kubectl kustomize cluster/apps/<namespace>/<app>/app
scripts/pre-commit exec run --files <changed-files>
git diff --check
```

Use `task precommit:run` only when intentionally validating and potentially formatting the whole repository. Never reconcile or apply the cluster unless the user explicitly requests it.

Report the created routes and storage briefly, any secret manifest the user must encrypt, and validation results. Preserve unrelated working-tree changes.
