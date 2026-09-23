# DB-GP-001B Final Database Closure - Plan

## Scope

Work limited to the `gestion-asistencia-db` repository and database artifacts.

Out of scope:

- backend inspection
- frontend inspection
- OpenAPI alignment
- JPA alignment
- Redis/cache implementation
- serverless infrastructure
- silent migration of the old drifted dev instance

## Work Items

1. Make catalog table deploys non-destructive and shape-validating.
2. Make `AuditoriaEvento` immutable by contract, with conflict detection instead of auto-migration.
3. Persist generated sessions as real UTC instants from institutional timezone metadata.
4. Require `idUsuarioEjecutor` for protected public write SPs that already expose it.
5. Remove public `idDocente` from session create/update SP signatures.
6. Enforce required session start/end inputs and temporal ordering.
7. Add explicit Golden Path attendance tests, including real concurrent upsert.
8. Freeze public canonical result sets and cache source views.
9. Refresh normative DB documentation and baseline contract only after passing final validation.

## Shape Guard

No domain shape change is allowed in this work item:

- `ADDED_COLUMNS=0`
- `REMOVED_COLUMNS=0`
- `RENAMED_COLUMNS=0`
- `TYPE_CHANGES=0`
- `NULLABILITY_CHANGES=0`

Indexes are allowed and reported separately by the schema scripts/tests.
