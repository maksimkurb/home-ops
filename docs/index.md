# Home Ops Docs

Start with the root [README](../README.md) for the current repo layout and [AGENTS.md](../AGENTS.md) for agent rules.

Useful current runbooks:

- [Flux](flux.md): install and reconcile the GitOps controllers.
- [Restore](restore.md): restore Flux state and orient app data recovery.

Most Kubernetes service configuration lives under `cluster/apps/<namespace>/<app>/`; shared substitutions live in `cluster/config/cluster-settings.yaml`.
