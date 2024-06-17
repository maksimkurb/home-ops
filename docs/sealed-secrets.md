# Sealed Secrets

!!! note "Work in progress"
    This document is a work in progress.

## Install the CLI tool

```sh
brew install kubeseal
```

## Install the cluster components

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/helmrelease-helm-v2beta1.json
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: sealed-secrets
  namespace: kube-system
spec:
  interval: 30m
  chart:
    spec:
      chart: sealed-secrets
      version: 1.13.2
      sourceRef:
        kind: HelmRepository
        name: sealed-secrets-charts
        namespace: flux-system
  values:
    ingress:
      enabled: false
```

## Fetch the Sealed Secrets public certificate

```sh
kubeseal \
    --controller-name sealed-secrets \
    --fetch-cert > ./sealed-secrets-public-cert.pem
```
