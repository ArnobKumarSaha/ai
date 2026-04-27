# Changes — Ingress → Gateway migration hardening

Scope: `charts/ace`. Aimed at making the parallel ingress + gateway story safe to run
end-to-end (phase 1 → phase 4 in `CLAUDE.md`).

## Hostname / routing

- `templates/_helpers.tpl` — added `ace.gateway.fqdn` (resolves to
  `<release>.<namespace>.<global.platform.host>`, e.g. `ace.ace.dbaas.kubedb.cloud`) and
  `ace.gateway.migrationActive` (true only when both `ingress-nginx.enabled` and
  `gateway.enabled`). The migration FQDN is added to manifests **only** during the
  parallel-running window so new gateway-only installs and pure ingress installs stay
  clean.
- `templates/gateway/route-main.yaml` — extra hostname `ace.gateway.fqdn` is appended
  during migration so phase-2 testers can reach the gateway via its own FQDN before the
  CNAME flip.
- `templates/gateway/route-home.yaml`, `templates/gateway/route-nats.yaml` — same
  migration-only hostname extension for the landing page and the `/nats` route.
- `templates/gateway/route-api.yaml` (new) — restores the missing `api.<host>` /
  `api.byte.builders` HTTPRoute that was present in the ingress but not in the gateway.
  Restricted to `/api` only, mirroring the original ingress semantics.

## TLS / certificates

- `templates/gateway/certificate.yaml` — `dnsNames` includes the gateway-native FQDN
  during migration only, so phase-2 TLS handshakes against the gateway succeed without
  inflating SANs for steady-state deployments.

## Gateway listeners

- `templates/gateway/gateway.yaml` — added an HTTP listener on port 80. ingress-nginx
  redirects 80→443 by default; without this listener, bookmarks like
  `http://dbaas.kubedb.cloud` would refuse connections after phase 4.
- `templates/gateway/route-http-redirect.yaml` (new) — attaches to the new HTTP listener
  with a `RequestRedirect` filter (scheme HTTPS, status 301).

## Operator guidance

- `templates/NOTES.txt` — preflight warning printed when `gateway.enabled=true` but
  `global.infra.tls.acme.solver=Ingress`. After the CNAME flip, HTTP-01 challenges land
  on envoy not nginx, so the next renewal silently fails. Note tells the operator to
  switch to `Gateway` (or DNS-01) and force a renewal **before** the cutover.

## Out of scope (intentionally not changed)

These are runbook / per-deployment ops items, not chart code:

- Cookie / OIDC redirect-URI domain mismatch during phase 2 — surface in the migration
  runbook; operators may need to register the gateway-native FQDN as an additional OIDC
  redirect URI for phase-2 auth-flow testing.
- Cloud LB exposure for NATS native TCP (port 4222) and s3proxy (4224) — must be set on
  the envoy service in `service-gateway` values per environment.
- LB health-check port — confirm it points at 443 (or 80 if the new HTTP listener is
  reachable from the LB).
- DNS TTL guidance — lower the existing A-record TTL to ~60s 24–48h before the CNAME
  flip; raise back after a stable week.
- Body-size / timeout parity between ingress-nginx and envoy — load-test upload paths
  before disabling ingress.
