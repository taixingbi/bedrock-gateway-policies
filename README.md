# bedrock-gateway-policies

Canonical tenant/route/IAM-principal policy config for
[bedrock-gateway-app](https://github.com/taixingbi/bedrock-gateway-app),
split out of the original combined repo so a policy change (a rate
limit, a new tenant, a route set) doesn't require an app rebuild or
Terraform apply.

## Layout

```
environments/
  dev/
    tenants.yaml       # tenant state, model allowlist, rate limit, guardrail policy, route set
    route_sets.yaml    # certified model route sets: primary + fallbacks
    iam_tenants.yaml   # AWS_IAM/SigV4 caller -> tenant_id mapping
  prod/
    (same three files, prod's own values)
schemas/                 # JSON Schema for each file, used by scripts/validate.py
scripts/validate.py       # schema + duplicate-key + cross-file consistency checks
```

`dev`/`prod` are directories, not branches — no merge-forward step
needed between them, and it keeps this repo's environment model
consistent with how bedrock-gateway-app/bedrock-gateway-infra already
key off environment name.

## Validating changes

```bash
pip install pyyaml jsonschema
python scripts/validate.py
```

Runs on every PR (`.github/workflows/ci.yml`). Three layers, each
assuming the previous one passed:

1. **Schema conformance** — every file matches its `schemas/*.schema.json`.
2. **Duplicate-key detection** — PyYAML's default loader silently keeps
   the *last* of two duplicate mapping keys (e.g. two `finance:` tenant
   blocks in the same file) with no warning; this loads with a custom
   loader that raises instead. The exact copy-paste mistake this repo
   exists to catch.
3. **Cross-file consistency** — a tenant's `route_set` must actually
   exist in `route_sets.yaml`; a route set's models must all be in the
   allowlist of every tenant assigned to it (otherwise the gateway's
   `enforce_model_allowlist()` would reject that tenant's own assigned
   route on every call); an `iam_tenants.yaml` entry's `tenant_id` must
   exist in `tenants.yaml`.

## Delivery (current -- interim)

Until the gateway has a working S3/DynamoDB-backed `PolicyStore`,
`bedrock-gateway-app` keeps its own **copy** of `environments/dev/*`
baked into the Docker image at build time (see that repo's
`policies/*.yaml` banner comments and `scripts/sync-policies.sh`).
Merging here doesn't automatically reach the app repo yet — run that
sync script by hand and open a PR there. This is intentionally manual
for now; see bedrock-gateway-app's plan notes for why (it's not worth
automating something meant to be replaced).

## Delivery (planned)

A `gha-policy-publish` OIDC role (defined in bedrock-gateway-infra)
will let this repo's CI publish `environments/<env>/*` directly to
DynamoDB on merge, and the gateway's `PolicyStore`/`IamTenantResolver`
will read from there instead of a file baked into the image — no app
rebuild needed for a policy change. Not built yet.

## Releases

Tag a commit on `main` after merge for anything meant to actually ship
(vs. an in-progress PR) — `git tag v<date>.<n>` — and note what changed
in `CHANGELOG.md`. Keeps "what's live in prod right now" answerable
without diffing history.
