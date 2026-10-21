# AI usage log

Tool: Kiro (AI agent). Every prompt is listed with what it produced and what I
checked or corrected.

## 1. Planning

Prompt: "help me to plan all of this task — everything should be best practice,
do not execute anything only plan, verify everything is best practice and up to
date (check the web)" + the exercise PDF.

Output: `PLAN.md` — tool choices, pinned versions checked against release pages.

Notable: ingress-nginx is retired (March 2026), so Traefik was chosen.

## 2. App + Dockerfile

Prompt: "ok lets run on it"

Output: `app/` — Go server, tests, multi-stage distroless Dockerfile.

Verified: `go vet`, `go test -race`, local `docker run` + curl, image runs as
UID 65532, 18.8 MB.

## 3. Terraform

Output: `terraform/` — kind cluster, Traefik, Argo CD, root Application.

AI mistake caught: the Traefik values used `service.type = ClusterIP`. Chart
42.x moved it to `service.spec.type`; the old key was silently ignored and the
Service rendered as `LoadBalancer`. Caught by `helm template` before apply.
Also: the plan said Traefik 41.6.x, but 42.x already had patch releases
(42.1.2), so the newer line was used after checking its values schema.
