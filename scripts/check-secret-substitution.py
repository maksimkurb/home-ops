#!/usr/bin/env python3
"""Keep credentials out of non-Secret Kubernetes objects.

Flux postBuild substitution pastes `${SECRET_*}` values from cluster-secrets
into whatever resource references them. When that resource is a HelmRelease,
ConfigMap or Middleware, anyone who can read it sees the credential.

Rules:
  1. A credential `${SECRET_*}` may only appear in a `cluster-secrets.yaml`
     file (a plain Secret whose values are rendered by Flux). Apps then read
     it via secretKeyRef/envFrom/configSecret.
  2. `cluster-secrets.yaml` may contain only `${...}` placeholders as values,
     never literal secrets (it is not SOPS-encrypted).
  3. Non-credential values (domains, public IPs, e-mails) in ALLOWED may still
     be substituted anywhere.
"""
import os
import re
import sys

ALLOWED = {
    "SECRET_DOMAIN",
    "SECRET_PUBLIC_DOMAIN",
    "SECRET_PRIVATE_DOMAIN",
    "SECRET_PARENTS_DOMAIN",
    "SECRET_UNIBOT_DOMAIN",
    "SECRET_PG_DOMAIN",
    "SECRET_EMAIL",
    "SECRET_CLOUDFLARE_EMAIL",
    "SECRET_VPS_IPS",
    "SECRET_ROUTER_OUTBOUND_IP",
    "SECRET_ROUTER_OUTBOUND_HOST",
    "SECRET_ROUTER_CLOUDFLARE_HOST",
    "SECRET_COTURN_PUBLIC_IP",
    "SECRET_CROWDSEC_WHITELISTED_IPS",
}

# Known leftovers, tracked for a follow-up. Do not add new entries casually.
BASELINE = {
    # Traefik v3.7 cannot resolve urn:k8s:secret in plugin config (v3.8+);
    # Gatus bypass tokens are embedded inside rule strings.
    "cluster/apps/networking/traefik/config/middlewares.yaml": {
        "SECRET_CROWDSEC_NGINX_BOUNCER_API_KEY",
        "SECRET_TURNSTILE_SECRET",
        "SECRET_TRAEFIK_OIDC_ENCRYPTION_SECRET",
        "SECRET_GATUS_OIDC_AUTHENTICATED_BEARER_TOKEN",
        "SECRET_GATUS_OIDC_ADMINS_BEARER_TOKEN",
        "SECRET_GATUS_OIDC_PEOPLE_BEARER_TOKEN",
        "SECRET_GATUS_OIDC_DOCUMENTS_BEARER_TOKEN",
        "SECRET_GATUS_OIDC_HOME_BEARER_TOKEN",
        "SECRET_GATUS_OIDC_MEDIA_BEARER_TOKEN",
        "SECRET_GATUS_OIDC_FRIGATE_BEARER_TOKEN",
    },
    # Not deployed (not referenced from cluster/apps/networking/kustomization.yaml).
    "cluster/apps/networking/ingress-nginx/app/helm-release.yaml": {
        "SECRET_CROWDSEC_NGINX_BOUNCER_API_KEY",
        "SECRET_HCAPTCHA_SECRET",
    },
}

VAR_RE = re.compile(r"\$\{(SECRET_[A-Z0-9_]+)\}")
SOPS_RE = re.compile(r"\.sops\.[a-z]+$")
CHECKED_EXT = (".yaml", ".yml", ".json", ".toml", ".conf", ".config")


def check_rendered_secret(path, lines):
    errors = []
    in_data = False
    for no, line in enumerate(lines, 1):
        if re.match(r"^(stringData|data):\s*$", line):
            in_data = True
            continue
        if in_data and re.match(r"^\S", line):
            in_data = False
        if not in_data or not line.strip() or line.strip().startswith("#"):
            continue
        if line.rstrip().endswith(("|", "|-", ">", ">-")):
            continue  # block scalar header; its body lines are checked
        if "${" not in line:
            errors.append(f"{path}:{no}: literal value in rendered Secret; use a ${{...}} placeholder")
    return errors


def main(paths):
    errors = []
    for path in paths:
        norm = os.path.normpath(path)
        if SOPS_RE.search(norm) or not norm.endswith(CHECKED_EXT):
            continue
        try:
            lines = open(norm, encoding="utf-8").read().splitlines()
        except (OSError, UnicodeDecodeError):
            continue
        if os.path.basename(norm) == "cluster-secrets.yaml":
            errors += check_rendered_secret(norm, lines)
            continue
        allowed_here = ALLOWED | BASELINE.get(norm, set())
        for no, line in enumerate(lines, 1):
            if line.lstrip().startswith("#"):
                continue
            for var in VAR_RE.findall(line):
                if var not in allowed_here:
                    errors.append(
                        f"{norm}:{no}: ${{{var}}} inlines a credential; move it to a "
                        "cluster-secrets.yaml Secret and reference it (secretKeyRef/envFrom)"
                    )
    for e in errors:
        print(e)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
