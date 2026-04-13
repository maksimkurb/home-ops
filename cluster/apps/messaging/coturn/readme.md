Messaging coturn

Standalone shared coturn deployment.

It reuses:
- the existing `turn.${SECRET_PUBLIC_DOMAIN}` TLS certificate
- the existing shared TURN auth secret `${SECRET_COTURN_KEY}`

Service exposure:
- `3478/TCP` and `3478/UDP` for TURN
- `5349/TCP` and `5349/UDP` for TURN over TLS/DTLS
- `49160-49170/UDP` for relay traffic

Network assumption:
- public `turn.<domain>` continues to resolve to the same public IP
- the router/firewall forwards the ports above to `${SVC_COTURN_ADDR}`
