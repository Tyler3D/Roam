# RoamOpenAPI

Swift types generated from the backend OpenAPI document via [swift-openapi-generator](https://github.com/apple/swift-openapi-generator) (types-only mode).

## Inputs

- **Canonical spec (source of truth):** `../contracts/openapi.json` (FastAPI export).
- **Generator input:** `Sources/RoamOpenAPI/openapi.yaml` — produced by `scripts/normalize_openapi_for_swift.py` (flattens Pydantic `anyOf` + `null` into OpenAPI 3.0 `nullable`, which the generator needs for optional fields).

## Regenerate

From repo root:

```bash
./scripts/export_openapi.sh   # updates contracts/openapi.json + openapi.yaml for Swift
(cd RoamOpenAPI && swift build)
```

Or only re-normalize + compile:

```bash
./scripts/check_openapi_swift.sh
```

## Xcode

The iOS app links this local package. Command-line builds must skip one-time plugin trust:

```bash
xcodebuild -scheme Roam -skipPackagePluginValidation …
```

After opening the project in Xcode, approve the OpenAPIGenerator plugin when prompted.
