# Plan: DevOps exercise — local Kubernetes with GitOps

Versions checked against official release pages on 2026-10-21.

## Core decisions

1. kind clusters created through Terraform.
2. Traefik as the ingress controller (ingress-nginx was retired in March 2026 and gets no security patches).
3. Argo CD using the app-of-apps pattern.
4. GitHub Actions builds multi-arch images, pushes them to GHCR, and commits the new tag back to git.

## Verified versions and gotchas

| Item | Use | Why / trap |
|---|---|---|
| Terraform | 1.16.6 (latest stable; 1.17 is still RC) | Install with `brew install hashicorp/tap/terraform`. The homebrew-core formula is stuck on an old pre-BSL version. |
| kind provider | `tehcyx/kind ~> 0.11` | Bundles kind 0.31, so pin `kindest/node:v1.35.0@sha256:...` from the kind v0.31 release notes. Newer node images (1.36/1.37) need a newer kind. Always pin by digest. |
| Helm provider | `hashicorp/helm ~> 3.3` | v3 syntax: `kubernetes = {...}` is an object, `set = [{name, value}]` is a list. AI tools often write the old v2 block syntax. |
| Ingress | Traefik chart 41.6.x (42.0.0 is a new major — read notes first) | ingress-nginx is retired. Traefik still serves plain `Ingress`, which the brief asks for. Gateway API is the production answer. |
| Argo CD | chart `argo-cd` 10.10.x, app v3.5.x | Install the root Application with the `argocd-apps` chart (2.0.7), not `kubernetes_manifest` — that needs Argo CRDs at plan time and fails on a fresh `apply`. |
| Actions | `actions/checkout@v7`, `docker/build-push-action@v7` | Pin actions by commit SHA (supply-chain best practice). |
| Arch | Mac arm64, kind nodes arm64 | CI images are amd64-only by default → `exec format error`. Build `linux/amd64,linux/arm64`. |

Still to verify when pinning: current distroless tag (debian12 vs debian13) and latest Go version.

## Time budget (90 min)

| Min | Work | Commit |
|---|---|---|
| 0-10 | Start Docker Desktop download. Meanwhile: `brew install kind kubectl helm gh git jq` + Terraform tap, VS Code, `gh auth login`, create public repo. Plan in `README.md`, start `ai-prompts.md`. | `docs: initial plan` |
| 10-25 | App, Dockerfile, local run | `feat(app): ...` |
| 25-45 | Terraform: cluster, Traefik, Argo CD | `feat(infra): ...` |
| 45-60 | Manifests, Argo app, Ingress opens in browser | `feat(k8s): ...` |
| 60-80 | CI pipeline and zero-downtime proof | `ci: ...` |
| 80-90 | Finish README, push, leave cluster running | `docs: final` |

Bonus only if ahead. Give Docker Desktop 4 CPU / 8 GB RAM (needed for Prometheus/Grafana).

## Part 0: App and Dockerfile

Go: one static binary, ~10 MB image, clean SIGTERM shutdown.

- [x] `GET /` renders HTML with `html/template` (auto-escaped), showing:
  - the message, a constant in code (so changing it goes through full CI);
  - the version, injected with `-ldflags -X main.version=$SHA`;
  - the pod name from `POD_NAME` (Downward API `fieldRef: metadata.name`).
- [x] `/healthz` always 200 (liveness); `/readyz` returns 503 after SIGTERM (readiness).
- [x] On SIGTERM, `http.Server.Shutdown(ctx)` so in-flight requests finish.
- [x] `main_test.go` that CI runs.
- [x] Multi-stage Dockerfile:
  - builder: `FROM --platform=$BUILDPLATFORM golang:<pinned>`, cross-compile with `GOOS/GOARCH=$TARGETARCH CGO_ENABLED=0 -trimpath` (no QEMU);
  - final: distroless `static:nonroot`, `USER 65532:65532` (numeric so k8s can verify `runAsNonRoot`);
  - `.dockerignore`.
- [x] Local test: `docker build`, `docker run -p 8080:8080`, `curl` both endpoints, `docker inspect` for the user.

## Part 1: Terraform

Files by type: `versions.tf`, `providers.tf`, `variables.tf`, `cluster.tf`, `ingress.tf`, `argocd.tf`, `outputs.tf`.

- [ ] `kind_cluster`: 1 control-plane + 2 workers.
  - control-plane label `ingress-ready=true`, `extraPortMappings` host 80/443 → container 80/443;
  - `wait_for_ready = true`.
- [ ] Helm provider configured from `kind_cluster` outputs (endpoint, client cert/key, CA).
  - Tradeoff for review: HashiCorp advises against configuring a provider from a resource in the same state. Fine locally; production splits cluster and add-ons into separate states.
- [ ] Traefik `helm_release`: `hostPort` 80/443, `nodeSelector ingress-ready=true` + control-plane toleration, IngressClass `traefik` as default.
- [ ] Argo CD `helm_release`: `dex.enabled=false`, `configs.params."server.insecure"=true` (UI behind plain-HTTP Ingress), `timeout.reconciliation` ~30s (no webhook to localhost).
- [ ] Root Application via `argocd-apps` → `argocd/` in the repo, `depends_on` Argo CD release, `wait = true` + timeouts.
- [ ] Hygiene: commit `.terraform.lock.hcl`; `.gitignore` `*.tfstate*` and `.terraform/`; `terraform fmt -check` + `validate`; local state, documented.
- [ ] Acceptance: `apply` → `destroy` → `apply` once.

## Part 2: GitOps

```
app/            main.go, main_test.go, go.mod, Dockerfile
k8s/            kustomization.yaml (images: newTag), deployment, service, ingress, pdb, hpa
argocd/         hello.yaml (+ monitoring.yaml for the bonus)
terraform/
.github/workflows/ci.yaml
scripts/rollout-check.sh
README.md  ai-prompts.md
```

- [ ] Argo Application: `automated: {prune: true, selfHeal: true}`, `CreateNamespace=true`, public repo (no credentials).
- [ ] Deployment:
  - rollout: 2 replicas, `RollingUpdate` `maxUnavailable: 0, maxSurge: 1`, `minReadySeconds: 5`;
  - probes: readiness `/readyz`, liveness `/healthz`;
  - resources: requests 50m/64Mi, limits 200m/128Mi (be ready to explain CPU-limit throttling);
  - shutdown: `lifecycle.preStop.sleep.seconds: 5` (native sleep — distroless has no shell), `terminationGracePeriodSeconds: 30`;
  - hardening: `runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`, `automountServiceAccountToken: false`;
  - placement: `topologySpreadConstraints` across workers + PDB `minAvailable: 1`.
- [ ] Ingress host `hello.127.0.0.1.nip.io` (fallback: `/etc/hosts`).
- [ ] Bootstrap image before CI exists:
  1. `gh auth token | docker login ghcr.io`;
  2. push the image once by hand;
  3. set GHCR package public (no `imagePullSecret`).

## Part 3: CI/CD

- [ ] Trigger: `push` to `main`, `paths-ignore: [k8s/**, '**.md']` (GITHUB_TOKEN pushes don't retrigger anyway; filter is belt and braces).
- [ ] `permissions: {contents: write, packages: write}` + `concurrency` group.
- [ ] Steps:
  1. checkout;
  2. `go test`;
  3. setup-buildx;
  4. login-action to `ghcr.io`;
  5. build-push `platforms: linux/amd64,linux/arm64`, tag `ghcr.io/<user>/<repo>:${{ github.sha }}` (immutable, never `latest`), `cache-from/to: type=gha`, provenance/SBOM on;
  6. update `newTag` in `k8s/kustomization.yaml` with `yq` (verify preinstalled on first run);
  7. commit as `github-actions[bot]`, `git pull --rebase && git push`.
- [ ] No `kubectl` in CI — Argo CD rolls the change out.
- [ ] Zero-downtime proof `scripts/rollout-check.sh` (`#!/usr/bin/env bash`):
  - loop `curl -s -o /dev/null -w '%{http_code}' --max-time 2` with timestamp;
  - `tee` to a log;
  - count non-200 at the end.
  - Run it, change the message, push, show 0 failures with pod names and version changing.

## Bonus

- [ ] HPA (`autoscaling/v2`, min 2, max 5, CPU 70%):
  - remove `replicas` from the Deployment (else Argo and HPA fight);
  - metrics-server via Argo CD with `--kubelet-insecure-tls` (kind needs it).
- [ ] `kube-prometheus-stack` as an Argo Helm-source app:
  - pin chart version;
  - `ServerSideApply=true` (CRDs too big for client-side);
  - disable etcd, scheduler, controller-manager, proxy scraping (down on kind);
  - Grafana on an Ingress.
- [ ] EKS production section in README:
  - infra/nodes: split Terraform states; S3 remote state with native `use_lockfile` (no DynamoDB); Karpenter or managed node groups across 3 AZs;
  - ingress/secrets: AWS Load Balancer Controller or Gateway API with ACM TLS + ExternalDNS; EKS Pod Identity; External Secrets;
  - images: ECR immutable tags + scanning; cosign signing;
  - CI/delivery: GitHub OIDC to AWS (no static keys); PR-based promotion via overlays or ApplicationSets;
  - Argo CD: HA, SSO, AppProject RBAC;
  - security/observability: PSA `restricted` or Kyverno; NetworkPolicies; AMP/AMG.

## Review prep

- Log every prompt in `ai-prompts.md`, committed with the change it produced.
- Note AI mistakes as they actually happen (likely: ingress-nginx, Helm v2 syntax, `kubernetes_manifest` on a fresh cluster, amd64-only images). Only report ones really caught.
- "One decision and why": Traefik over retired ingress-nginx, or `argocd-apps` over `kubernetes_manifest`.
