#!/usr/bin/env python3
"""Validates every environments/{dev,prod}/*.yaml file.

Three layers, in order (each one assumes the previous layer passed):

1. Schema conformance (schemas/*.schema.json via jsonschema).
2. Duplicate-key detection -- PyYAML's default loader silently keeps
   the *last* of two duplicate mapping keys (e.g. two "finance:" tenant
   blocks in the same file) with no warning. That's exactly the kind of
   copy-paste mistake this repo exists to catch, so this loads with a
   custom Loader that raises instead.
3. Cross-file consistency:
   - every tenant's `route_set` (if set) names a route set that exists
     in route_sets.yaml
   - every route set's `primary`/`fallbacks` models are all in a
     tenant's `models` allowlist, for every tenant assigned to that
     route set with a non-empty allowlist -- otherwise
     enforce_model_allowlist() in the gateway would reject that
     tenant's own assigned route on every call
   - every iam_principals entry's `tenant_id` exists in tenants.yaml

Exits non-zero (with every problem found, not just the first) if
anything fails.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parent.parent
ENVIRONMENTS = ["dev", "prod"]
FILES = {
    "tenants.yaml": "tenants.schema.json",
    "route_sets.yaml": "route_sets.schema.json",
    "iam_tenants.yaml": "iam_tenants.schema.json",
}


class _DuplicateKeyLoader(yaml.SafeLoader):
    pass


def _construct_mapping_no_dupes(loader: yaml.SafeLoader, node: yaml.MappingNode) -> dict:
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=True)
        if key in mapping:
            raise ValueError(f"duplicate key {key!r} at line {key_node.start_mark.line + 1}")
        mapping[key] = loader.construct_object(value_node, deep=True)
    return mapping


_DuplicateKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping_no_dupes
)


def load_yaml_no_dupes(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return yaml.load(f, Loader=_DuplicateKeyLoader)


def main() -> int:
    errors: list[str] = []

    for env in ENVIRONMENTS:
        env_dir = ROOT / "environments" / env
        if not env_dir.is_dir():
            errors.append(f"{env_dir}: missing environments/{env}/ directory")
            continue

        docs: dict[str, Any] = {}
        for filename, schema_name in FILES.items():
            path = env_dir / filename
            if not path.exists():
                errors.append(f"{path}: missing")
                continue

            try:
                doc = load_yaml_no_dupes(path)
            except (yaml.YAMLError, ValueError) as exc:
                errors.append(f"{path}: {exc}")
                continue

            schema = json.loads((ROOT / "schemas" / schema_name).read_text())
            for err in sorted(Draft7Validator(schema).iter_errors(doc), key=str):
                errors.append(f"{path}: schema violation at {list(err.path)}: {err.message}")

            docs[filename] = doc

        if len(docs) < len(FILES):
            continue  # missing/unparsable file(s) already reported; skip cross-file checks

        tenants = docs["tenants.yaml"].get("tenants", {})
        route_sets = docs["route_sets.yaml"].get("route_sets", {})
        iam_principals = docs["iam_tenants.yaml"].get("iam_principals", {})

        for tenant_id, tenant in tenants.items():
            route_set_name = tenant.get("route_set")
            if route_set_name is None:
                continue
            if route_set_name not in route_sets:
                errors.append(
                    f"{env}/tenants.yaml: tenant '{tenant_id}' references "
                    f"route_set '{route_set_name}', not found in {env}/route_sets.yaml"
                )
                continue

            allowlist = tenant.get("models") or []
            if not allowlist:
                continue  # empty allowlist = "no restriction", nothing to check
            route_set = route_sets[route_set_name]
            models = [route_set["primary"], *route_set.get("fallbacks", [])]
            for model in models:
                if model not in allowlist:
                    errors.append(
                        f"{env}: tenant '{tenant_id}' is assigned route_set "
                        f"'{route_set_name}', which routes to model '{model}' -- "
                        f"not in tenant '{tenant_id}'s models allowlist {allowlist}"
                    )

        for arn, entry in iam_principals.items():
            tenant_id = entry.get("tenant_id")
            if tenant_id not in tenants:
                errors.append(
                    f"{env}/iam_tenants.yaml: principal '{arn}' maps to tenant_id "
                    f"'{tenant_id}', not found in {env}/tenants.yaml"
                )

    if errors:
        print(f"{len(errors)} problem(s) found:\n", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print("All policy files valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
