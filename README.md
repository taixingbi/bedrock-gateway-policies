# platform-policy-definitions

Canonical tenant/route/IAM-principal policy config for
[bedrock-runtime-gateway-app](https://github.com/taixingbi/bedrock-runtime-gateway-app),
split out of the original combined repo so a policy change (a rate
limit, a new tenant, a route set) doesn't require an app rebuild or
Terraform apply.

## Layout

```
environments/
  dev/
    tenants.yaml           # tenant state, model allowlist, rate limit, guardrail policy, route set
    route_sets.yaml        # certified model route sets: primary + fallbacks
    iam_tenants.yaml       # AWS_IAM/SigV4 caller -> tenant_id mapping
    certified_models.yaml  # M9 eval-gate output: which model ids passed certification (written by bedrock-runtime-gateway-app's evals/run_eval.py, never by hand)
    model_registry.yaml    # governance overlay keyed by the same model_id: owner, risk classification, lifecycle status (curated directly, never generated)
  prod/
    (same five files, prod's own values)
schemas/                 # JSON Schema for each file, used by scripts/validate.py
scripts/validate.py       # schema + duplicate-key + cross-file consistency checks
```

`dev`/`prod` are directories, not branches — no merge-forward step
needed between them, and it keeps this repo's environment model
consistent with how bedrock-runtime-gateway-app/bedrock-runtime-gateway-infra already
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

## Delivery (current -- two paths, not yet unified)

`bedrock-runtime-gateway-app` has a real DynamoDB-backed `PolicyStore`
(`DynamoDbPolicyStore`, layered with a file fallback) and it's live
today -- but only for tenants provisioned through the portal's
self-service onboarding/policy-change-request flow (M11, plan 33),
which writes to DynamoDB directly and never touches this repo. For
hand-managed tenants that live only in this repo's `environments/*`
files, `bedrock-runtime-gateway-app` still keeps its own **copy** of
`environments/dev/*` baked into the Docker image at build time (see
that repo's `policies/*.yaml` banner comments and
`scripts/sync-policies.sh`, a manual, human-run script -- merging here
does not automatically reach the app repo). A dry-run-by-default
backfill tool (`scripts/migrate_file_tenants_to_dynamodb.py` in
bedrock-runtime-gateway-app) can move a hand-managed tenant into DynamoDB, but
running it is also manual.

Net effect: two independent ways to change a tenant's live policy
exist today (this repo's Git-reviewed files, and the portal's direct-
to-DynamoDB propose/approve flow) with no reconciliation between them
-- a real, tracked gap, not a design that's considered finished. See
`plan.md` section 35 in the platform root for the fuller writeup and
the proposed direction (Git as the single source of truth: PR ->
validate -> approve -> publish, with the portal generating a change
request against Git rather than writing DynamoDB directly).

## Delivery (planned)

A `gha-policy-publish` OIDC role already exists (this repo's own
`ci_identity/main.tf`, see "Infra & CI" below), scoped to
`dynamodb:PutItem/UpdateItem` -- but it targets a placeholder table
name (`gateway-policies`) that doesn't match any real per-environment
table (`gateway-{dev,prod}-provisioned-tenant-policies`), and no
workflow in this repo assumes it yet. This repo's own
`.github/workflows/ci.yml` is validation-only today
(`scripts/validate.py`, no AWS credentials, no publish step). Closing
this means: fixing the IAM role's table target, adding a real publish
job here triggered on merge to `main`, and deciding how (or whether)
that reconciles with the portal's existing direct-to-DynamoDB write
path above -- not built yet.

## Infra & CI

This repo owns one Terraform root, `ci_identity/`, with its own state
and its own `fmt-validate`/`plan`/`apply-dev` CI jobs
(`.github/workflows/terraform.yml`, triggered only on changes under
`ci_identity/`):

- `gha-policy-publish` -- the (currently inert, see "Delivery
  (planned)" above) DynamoDB publish role.
- `gha-policy-infra-plan` / `gha-policy-infra-apply-dev` -- this root's
  own plan/apply-dev roles, managing only `gha-policy-*`-named roles.

Added 2026-09-21 as part of a platform-wide Terraform-ownership
migration: `gha-policy-publish` used to be defined centrally in
`platform-foundation`, moved here via `terraform import` (never
deleted/recreated, so its ARN never changed). Unlike every other
migrated repo, this one had no pre-existing Terraform plan/apply role
of its own at all (no infra to plan/apply, just the one deploy-style
publish role) -- `gha-policy-infra-plan`/`-apply-dev` were created
fresh here, and this repo's GitHub Environment picked up two brand-new
variables (`AWS_POLICY_INFRA_PLAN_ROLE_ARN`,
`AWS_POLICY_INFRA_APPLY_DEV_ROLE_ARN`) to match. `apply-dev`
auto-applies on push to `main`, same convention as every other
migrated repo; there is no `apply-prod` for this root (`gha-policy-publish`
itself has no prod/dev split -- see the placeholder-table caveat
above).

## Releases

Tag a commit on `main` after merge for anything meant to actually ship
(vs. an in-progress PR) — `git tag v<date>.<n>` — and note what changed
in `CHANGELOG.md`. Keeps "what's live in prod right now" answerable
without diffing history.
