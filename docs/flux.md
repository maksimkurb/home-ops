# Flux

Flux is installed from this repository, not with `flux bootstrap github`.

The bootstrap path is intentionally split in two:

1. `cluster/bootstrap/` installs the Flux controllers and CRDs once.
2. `cluster/flux/flux-system/` creates the Git source for this repo and points Flux at `cluster/flux/`.

After that, Flux reconciles the rest of `cluster/` from Git.

## Prerequisites

Install the Flux CLI and make sure `kubectl` already points at the target cluster:

```sh
flux check --pre
kubectl get nodes
```

The install task also requires:

- The local SOPS Age key.

```sh
test -f ~/.config/sops/age/keys.txt
```

## Install From This Repo

Use the task wrapper:

```sh
task cluster:install
```

That task expands to:

```sh
kubectl apply --kustomize ./cluster/bootstrap/

cat ~/.config/sops/age/keys.txt \
  | kubectl -n flux-system create secret generic sops-age \
      --from-file=age.agekey=/dev/stdin \
      --save-config \
      --dry-run=client \
      -o yaml \
  | kubectl apply -f -

kubectl apply --kustomize ./cluster/flux/flux-system/

flux reconcile -n flux-system source git flux-cluster
flux reconcile -n flux-system kustomization flux-cluster
```

## What Gets Installed

`cluster/bootstrap/kustomization.yaml` installs Flux `v2.7.5` from `github.com/fluxcd/flux2/manifests/install` and patches out the built-in Flux NetworkPolicies.

`cluster/flux/flux-system/flux-cluster.yaml` creates:

- `GitRepository/flux-cluster`, pointing at the public `https://github.com/maksimkurb/home-ops` repo, branch `main`.
- `Kustomization/flux-cluster`, pointing at `./cluster/flux`.

`cluster/flux/flux-system/flux-installation.yaml` lets Flux manage its own controller install from Flux upstream after the initial bootstrap.

## GitHub Tokens

There are two GitHub-related credentials, and they are used for notifications/webhooks, not for cloning this public repo.

`GitRepository/flux-cluster` has no `secretRef` because the IaC repository is public. Add a repository fetch Secret only if the repo becomes private.

### GitHub Notification Token

`cluster/apps/flux-system/notifications/github/secret.sops.yaml` creates `Secret/github-token` in `flux-system`.

`cluster/apps/flux-system/notifications/github/notification.yaml` uses it for the Flux GitHub notification provider. This is for reporting events/statuses to GitHub, not for cloning the repo.

### GitHub Webhook Token

`cluster/apps/flux-system/webhook/github/secret.sops.yaml` creates `Secret/github-webhook-token` in `flux-system`.

`cluster/apps/flux-system/webhook/github/receiver.yaml` uses it to validate GitHub webhook events for `GitRepository/flux-cluster` and the top-level Kustomizations.

The webhook ingress is `flux-webhook.${SECRET_PUBLIC_DOMAIN}/hook/`, defined in `cluster/apps/flux-system/webhook/github/ingress.yaml`.

## Reconcile Order

The top-level Flux Kustomizations under `cluster/flux/` apply the cluster in this order:

```text
charts -> config -> crds -> core -> apps
```

- `charts` applies HelmRepository resources from `cluster/charts`.
- `config` applies `cluster/config` and decrypts SOPS data with `sops-age`.
- `crds` applies CRDs from `cluster/crds`.
- `core` waits for `charts`, `config`, and `crds`, then applies `cluster/core`.
- `apps` waits for `core`, then applies `cluster/apps`.

`core` and `apps` both use `postBuild.substituteFrom` with:

- `ConfigMap/cluster-settings`
- `Secret/cluster-secrets`

## Verify

Check Flux controllers:

```sh
kubectl -n flux-system get pods
```

Check sources and top-level reconciliations:

```sh
flux get sources git -A
flux get kustomizations -A
```

Force Flux to pull and apply the current Git state:

```sh
task cluster:reconcile
```

## Useful Commands

Reconcile one top-level Kustomization:

```sh
flux reconcile -n flux-system kustomization apps
```

Reconcile one HelmRelease:

```sh
flux reconcile helmrelease <name> -n <namespace>
```

Reconcile one HelmRepository:

```sh
flux reconcile source helm ingress-nginx-charts -n flux-system
```

Show failed HelmReleases:

```sh
kubectl get hr --all-namespaces | grep False
```

Restart failed HelmReleases with the existing task:

```sh
task cluster:hr-restart
```

## Notes

Do not replace this flow with `flux bootstrap github`; this repo already stores the Flux install and Git source manifests.

Do not decrypt or edit SOPS files while debugging Flux. If `sops-age` is missing, recreate it from `~/.config/sops/age/keys.txt` with the command above.
