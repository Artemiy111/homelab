# Homelab

**A home Kubernetes platform run like production: sixty services, one operator, no manual deploys.**
Photos and media, files, mail, chat and video calls, identity, Git with CI, secrets and monitoring run on
a single-node k0s cluster. Every change reaches it through Git and Argo CD, with the same checks a
product team applies before release.

> Russian version: [`README.ru.md`](README.ru.md)

[![services](docs/status/badges/en/services.svg)](docs/status/README.md)
[![manifests](docs/status/badges/en/manifests.svg)](docs/status/README.md)
[![images pinned](docs/status/badges/en/images-pinned.svg)](docs/status/README.md)
[![netpol coverage](docs/status/badges/en/netpol-coverage.svg)](docs/status/README.md)
[![ADRs](docs/status/badges/en/adr.svg)](docs/adr/)
[![postmortems](docs/status/badges/en/postmortems.svg)](docs/incidents/)

Every number above is computed from git and checked by a CI gate, so it cannot drift from the code
([how they are counted](docs/status/README.md)).

## What it demonstrates

- **Platform engineering, not a pile of containers.** One gateway with wildcard TLS in front and one
  identity provider behind it: Zitadel over OIDC, or oauth2-proxy for apps without their own login.
  When the DNS provider offered neither a cert-manager solver nor working RFC2136, I wrote
  [a cert-manager webhook](packages/cert-manager-webhook-dns01/) and publish its image and chart to an
  OCI registry on tag.
- **GitOps with pull-request review.** Argo CD reconciles the cluster from Git. A dozen CI gates check
  commit messages, secrets, linting, manifest schemas and security, Argo prune policy, and alert
  documentation. The same set runs in the cluster and on the public GitHub mirror. Local hooks catch
  most problems before a commit.
- **Observability.** Metrics, logs, traces and profiles are linked in Grafana. eBPF provides traces and
  off-CPU profiles for applications that were never instrumented.
- **Learning from incidents.** ADRs record decisions, blameless postmortems end in tracked issues, and
  an alert rule without a RUNBOOK entry fails the build.
- **Secrets and supply-chain hygiene.** Images are pinned by digest, secrets come only from Vault, and
  gitleaks runs on every push. This is why the repository can be published as it is.

## Stack

- **Platform and storage:** k0s, Argo CD, Traefik, cert-manager, Longhorn, Technitium DNS
- **Identity and secrets:** Zitadel, Vault
- **Data:** CloudNativePG, MariaDB, RustFS
- **Git:** Forgejo
- **Monitoring:** Grafana
- **Applications:** Immich, Jellyfin, Navidrome, Nextcloud, Element, Stalwart,
  Paperless, Home Assistant, Open WebUI

Each unit has a README and a RUNBOOK under [`apps/casa/`](apps/casa/) and
[`platform/casa/`](platform/casa/).

## Known gaps

- **No HA.** One machine and no quorum, so PodDisruptionBudgets would be theatre. For the same reason,
  environments are not split by namespace ([ADR 0001](docs/adr/0001-namespace-ownership.md)).
- **No restore drill yet.** Snapshots exist and backup is documented, but no restore has been rehearsed.
- **No SLOs.** Alerting is symptom-based rather than driven by error budgets.
- **No admission policy controller.** NetworkPolicies are hand-written, and nothing stops a manifest from
  shipping without one.
- **Terraform state is local**, with no lock and no drift detection.
- **Images are pinned but unsigned.** No SBOM, no signature check, and trivy runs in report-only mode.

Deeper: [`docs/adr/`](docs/adr/) for decisions, [`docs/incidents/`](docs/incidents/) for what broke,
[`docs/research/`](docs/research/) for the standards behind the choices.
