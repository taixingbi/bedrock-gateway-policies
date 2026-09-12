# Changelog

## Unreleased

- Split out of the original `bedrock-gateway-platform` monorepo.
  `tenants.yaml`, `route_sets.yaml`, `iam_tenants.yaml` moved here
  unchanged (history preserved via `git filter-repo`), duplicated into
  `environments/dev/` and `environments/prod/` (identical at the point
  of the split — diverge them as dev/prod needs actually differ).
- Added `schemas/`, `scripts/validate.py`, and CI to catch schema
  violations, duplicate YAML keys, and route/tenant/IAM-principal
  cross-file inconsistencies on every PR.
