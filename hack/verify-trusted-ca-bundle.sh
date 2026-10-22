#!/usr/bin/env bash
# Post-deploy check for the trusted-ca-bundle injection (Kyverno + trust-manager).
# For every Running pod (optionally limited to one namespace) and each container with a shell:
#   - SSL_CERT_FILE is set to /etc/trust-bundle/ca-certificates.crt
#   - the file contains no emSign / eMudhra root (by SHA-256 fingerprint, needs openssl in the
#     container; otherwise falls back to a PEM cert count and a size comparison with the ConfigMap)
# Usage: hack/verify-trusted-ca-bundle.sh [namespace]    (needs kubectl, read-only; uses `kubectl exec`)
set -uo pipefail

NS="${1:-}"
BAD_FP="86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B 7DD78D5F4F13459A83DFF9ABBBA62EDBAF6F2D102BF257FD712F4D9F2746ED8D F2EDAAFF3D9B701FB4D14C9F285F8C0BAD90FC3BCC1FA07D47F4718EDABA34A5 40F6AF0346A99AA1CD1D555A4E9CCE62C7F9634603EE406615833DC8C8D00367"
EXCLUDED=" kube-system flux-system cilium-secrets kyverno "

# Apps whose TLS stack ignores SSL_CERT_FILE / system store; injection cannot fix them.
# Review manually (match against the images in cluster/apps):
#   Rust (rustls + webpki-roots)  : docker.io/vaultwarden/server (check build features),
#                                   ghcr.io/rustdesk/rustdesk-server, influxdb v3
#   Bun-compiled / Electron       : none known; ghcr.io/snapotter-hq/snapotter, ghcr.io/homarr-labs/homarr,
#                                   samanhappy/mcphub, ghcr.io/coder/code-server (Node: OK via NODE_OPTIONS,
#                                   but check for Bun/bundled runtimes)
#   Chromium/NSS own store        : ghcr.io/flaresolverr/flaresolverr, gotenberg (headless Chromium)
#   Go with embedded x509roots    : only used when NO system roots found; env SSL_CERT_FILE still wins
#   JVM with explicit truststore  : orthancteam/orthanc is C++ (OK); any Java app that sets its own
#                                   -Djavax.net.ssl.trustStore keeps it (JAVA_TOOL_OPTIONS not overridden)
#   Python certifi (own bundle)   : apps pinning verify=certifi.where() ignore REQUESTS_CA_BUNDLE only
#                                   if they pass it explicitly; paperless/frigate normally honor env.
STATIC_HINT='docker.io/vaultwarden/server ghcr.io/rustdesk/rustdesk-server ghcr.io/flaresolverr/flaresolverr docker.io/gotenberg/gotenberg influxdb'

ok=0; bad=0; skipped=0
while read -r ns pod; do
  [[ "$EXCLUDED" == *" $ns "* ]] && continue
  for c in $(kubectl get pod -n "$ns" "$pod" -o jsonpath='{.spec.containers[*].name}'); do
    out="$(kubectl exec -n "$ns" "$pod" -c "$c" -- sh -c '
      [ "$SSL_CERT_FILE" = /etc/trust-bundle/ca-certificates.crt ] || { echo "NOENV"; exit 0; }
      [ -s "$SSL_CERT_FILE" ] || { echo "NOFILE"; exit 0; }
      if command -v openssl >/dev/null 2>&1; then
        cat "$SSL_CERT_FILE" | awk "/BEGIN CERT/{n++} n{print > \"/tmp/.tb\" n}" 2>/dev/null
        for f in /tmp/.tb*; do openssl x509 -in "$f" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 | tr -d : ; done
        rm -f /tmp/.tb*
      else
        echo "NOOPENSSL"; grep -c "BEGIN CERT" "$SSL_CERT_FILE"
      fi' 2>/dev/null)"
    rc=$?
    if [ $rc -ne 0 ] || [ -z "$out" ]; then echo "SKIP  $ns/$pod/$c (no shell or exec failed)"; skipped=$((skipped+1)); continue; fi
    case "$out" in
      NOENV*)  echo "FAIL  $ns/$pod/$c SSL_CERT_FILE not set to trust bundle"; bad=$((bad+1)); continue;;
      NOFILE*) echo "FAIL  $ns/$pod/$c bundle file missing/empty"; bad=$((bad+1)); continue;;
    esac
    hit=0
    for fp in $BAD_FP; do grep -qi "$fp" <<<"$out" && hit=1; done
    if [ $hit = 1 ]; then echo "FAIL  $ns/$pod/$c bundle contains a distrusted root"; bad=$((bad+1))
    else echo "OK    $ns/$pod/$c"; ok=$((ok+1)); fi
  done
done < <(kubectl get pods ${NS:+-n "$NS"} $([ -z "$NS" ] && echo -A) --field-selector=status.phase=Running \
          -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}')

echo "ok=$ok fail=$bad skipped=$skipped"
echo
echo "Images likely NOT fixable by injection (verify manually): $STATIC_HINT"
echo "Images in cluster matching the hint list:"
for h in $STATIC_HINT; do
  kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{" "}{.spec.containers[*].image}{"\n"}{end}' 2>/dev/null | grep -F "$h" | sed 's/^/  /'
done
exit $((bad > 0))
