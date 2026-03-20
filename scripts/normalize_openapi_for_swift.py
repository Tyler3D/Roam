#!/usr/bin/env python3
"""
Flatten FastAPI/Pydantic OpenAPI 3.1 schemas of the form
  { "anyOf": [ { "type": "..." , ... }, { "type": "null" } ] }
into OpenAPI 3.0-style { "type": "...", "nullable": true, ... }

swift-openapi-generator otherwise omits many optional object properties.
"""
from __future__ import annotations

import copy
import json
import sys
from typing import Any


def _is_null_only(x: Any) -> bool:
    return isinstance(x, dict) and x.get("type") == "null"


def simplify(node: Any) -> Any:
    if isinstance(node, list):
        return [simplify(x) for x in node]
    if not isinstance(node, dict):
        return node

    if "anyOf" in node:
        parts = node["anyOf"]
        if isinstance(parts, list):
            non_null = [p for p in parts if not _is_null_only(p)]
            if len(non_null) == 1 and len(parts) == 2:
                inner = simplify(copy.deepcopy(non_null[0]))
                if isinstance(inner, dict):
                    inner["nullable"] = True
                    for k in ("title", "description", "default", "readOnly", "writeOnly"):
                        if k in node and k not in inner:
                            inner[k] = copy.deepcopy(node[k])
                    return inner

    out = {k: simplify(v) for k, v in node.items()}
    if "properties" in out and isinstance(out["properties"], dict):
        out["properties"] = {k: simplify(v) for k, v in out["properties"].items()}
    if "items" in out:
        out["items"] = simplify(out["items"])
    return out


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: normalize_openapi_for_swift.py <input.json> <output.json>", file=sys.stderr)
        sys.exit(2)
    inp, outp = sys.argv[1], sys.argv[2]
    with open(inp) as f:
        spec = json.load(f)
    spec["openapi"] = "3.0.3"
    spec = simplify(spec)
    with open(outp, "w") as f:
        json.dump(spec, f, indent=2)
    print(f"Wrote {outp} (openapi 3.0.3, flattened null anyOf)")


if __name__ == "__main__":
    main()
