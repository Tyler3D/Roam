# OpenAPI → iOS types

## Scripts (what each one is)

Think of **three roles**: generate spec from Python → reshape it for Swift → prove the Swift package still builds.

| File | Role | Needs backend / venv? |
|------|------|------------------------|
| **`export_openapi.sh`** | **Regenerate everything from FastAPI.** Runs `app.openapi()`, writes **`contracts/openapi.json`**, then runs the normalizer to refresh **`RoamOpenAPI/.../openapi.yaml`**. | **Yes** (`backend` + `.venv-export` per script header). |
| **`normalize_openapi_for_swift.py`** | **Not a “check”.** It’s a **transformer**: reads JSON, writes the **flattened YAML** the Swift generator expects (OpenAPI 3.1 `anyOf`+null → 3.0-style `nullable`). Invoked by `export_openapi.sh` and `check_openapi_swift.sh`; you almost never run it alone. | **No** (just `python3`). |
| **`check_openapi_swift.sh`** | **Local sanity check** (optional). Uses **`contracts/openapi.json`** (no FastAPI import), re-runs the normalizer, then **`swift build`** on `RoamOpenAPI`. Fails if the spec and package are out of sync. | **No** backend; **yes** Swift toolchain. |

So: **`export`** = author/update artifacts; **`normalize`** = library step inside the other two; **`check`** = “does our pinned JSON + Swift package still compile?”

## Flow

1. **Export** — `scripts/export_openapi.sh` runs FastAPI `app.openapi()`, writes `contracts/openapi.json`, then runs `scripts/normalize_openapi_for_swift.py` to update `RoamOpenAPI/Sources/RoamOpenAPI/openapi.yaml`.
2. **Normalize** — FastAPI 3.1 schemas use `anyOf: [T, null]` for optionals; swift-openapi-generator omits those properties unless flattened to OpenAPI 3.0-style `nullable`. The TypeScript client can keep using raw **`contracts/openapi.json`** unchanged.
3. **Codegen** — SwiftPM target `RoamOpenAPI` uses the OpenAPIGenerator plugin (`openapi-generator-config.yaml`, `accessModifier: public`).
4. **App models** — `Roam/Models/OpenAPIModels.swift` typealiases `Idea`, `Plan`, `RoamUser`, etc. to `Components.Schemas.*` and adds small extensions (`UserRead.displayName`, `PlanRead.resolvedMembers`, `Identifiable`).

## JSON decoding

`APIClient` uses `JSONDecoder.roam` (`Roam/Utils/JSONCoding.swift`): ISO-8601 with optional fractional seconds, matching typical FastAPI/Pydantic JSON. Generated `Codable` types decode with that decoder.

## Hand-written transport

`APIClient` remains the URLSession + Firebase Bearer layer. **Generated operations `Client`** is not used yet; a future step is middleware for `Authorization` and deleting manual path strings.

## Builds

- **SwiftPM:** `(cd RoamOpenAPI && swift build)`
- **Xcode CLI:** add `-skipPackagePluginValidation` until the OpenAPIGenerator plugin is trusted in your environment (see `RoamOpenAPI/README.md`).
- **CI:** `.github/workflows/openapi-contract.yml` compares FastAPI `app.openapi()` to **`contracts/openapi.json`** when `backend/**` or the contract changes; if it fails, run `./scripts/export_openapi.sh` and commit the updated JSON + `RoamOpenAPI/.../openapi.yaml`.
