# DB-GP-001B Final Database Closure - Validation

## Current Local Development Baseline

```text
Container: sql_server_asistencias
Database: gestionasistenciadb
State: ALIGNED_WITH_FROZEN_BASELINE
Temporary validation container: REMOVED
DBCODE: ENABLED
Golden Path: FROZEN
Backend integration target: sql_server_asistencias / gestionasistenciadb
```

Final official local gate:

```text
TOTAL_EXPECTED=127
TOTAL_EXECUTED=128
PASSED=127
FAILED=0
SKIPPED=1
ALLOWED_SKIPPED=1
CRITICAL_MISSING=0
SQLCMD_EXIT_CODE=0
SQL_ERROR_COUNT=0
UNAUTHORIZED_SKIPS=0
@@TRANCOUNT=0
DB GATE PASS
```

Additional official local checks:

```text
DBCODE SEC_001=PASS
DBCODE SEC_002=PASS
GHOST_COLUMN_COUNT=0
TEMPORARY_CONTAINER_gp001_sql_fresh=REMOVED
```

## Historical Clean-Container Validation

## Environment

- Repository: `gestion-asistencia-db`
- Validation container: `gp001_sql_fresh`
- Database: `gestionasistenciadb`
- Superseded by official local instance: `sql_server_asistencias`

## Final Validation Sequence

1. Recreated clean database inside `gp001_sql_fresh`.
2. Ran fresh deploy:
   - `.\\deploy_schema.ps1 -ContainerName gp001_sql_fresh`
   - Result: PASS
3. Ran full gate:
   - `.\\test_summary.ps1 -ContainerName gp001_sql_fresh`
   - Result: PASS
4. Inserted catalog fixture:
   - `CatalogoParametro(grupo='QA_REDEPLOY', clave='SURVIVES', valor='fixture')`
5. Ran repeat deploy:
   - `.\\deploy_schema.ps1 -ContainerName gp001_sql_fresh`
   - Result: PASS
6. Verified fixture survived repeat deploy:
   - `CATALOG_FIXTURE_SURVIVES=1`
7. Ran final full gate:
   - `.\\test_summary.ps1 -ContainerName gp001_sql_fresh`
   - Result: PASS

## Final Gate Summary

```text
TOTAL_EXPECTED=115
TOTAL_EXECUTED=116
PASSED=115
FAILED=0
SKIPPED=1
ALLOWED_SKIPPED=1
CRITICAL_MISSING=0
SQLCMD_EXIT_CODE=0
SQL_ERROR_COUNT=0
UNAUTHORIZED_SKIPS=0
@@TRANCOUNT=0
DB GATE PASS
```

Only allowed skip:

```text
XACT_STATE_MINUS_ONE_RUNTIME
```

## Contract Evidence

```text
TABLE_SHAPE_HASH=337d39f7997e8b224028e20b194be15918c5136b1fa55ff8b40f9f768efe43d1
CATALOG_FIXTURE_SURVIVES=1
```

## Critical Tests Added Or Frozen

- `PUBLIC_SECURITY_EXECUTOR_REQUIRED`
- `SESSION_IDDOCENTE_REMOVED`
- `DEPLOY_CATALOGS_NON_DESTRUCTIVE`
- `CATALOG_SEEDS_NO_DUPLICATES`
- `AUDIT_SCHEMA_IMMUTABLE`
- `UTC_CATALOG_TIMESTAMPS`
- `UTC_AUDIT_TIMESTAMP`
- `UTC_SESSION_GENERATION`
- `SESSION_REQUIRED_START`
- `SESSION_REQUIRED_END`
- `SESSION_END_AFTER_START`
- `SESSION_EXECUTOR_REQUIRED`
- `SESSION_NOT_FOUND_CODE`
- `ATTENDANCE_BULK_PARTIAL_ALLOWED`
- `ATTENDANCE_BULK_OMITTED_STUDENT_UNCHANGED`
- `ATTENDANCE_BULK_IDEMPOTENT_SAME_STATE`
- `ATTENDANCE_BULK_UPDATE_EXISTING_STATE`
- `ATTENDANCE_NO_DUPLICATE_HEADER`
- `ATTENDANCE_NO_DUPLICATE_DETAIL`
- `ATTENDANCE_STATE_AN_CONSISTENCY`
- `ATTENDANCE_STATE_SJC_CONSISTENCY`
- `ATTENDANCE_STATE_EX_CONSISTENCY`
- `ATTENDANCE_READ_ONLY_PERSISTED_ROWS`
- `ATTENDANCE_READ_CANONICAL_CODE`
- `ATTENDANCE_CONCURRENT_UPSERT`
- `PUBLIC_CANONICAL_RESULTSET`
- `CATALOG_PARAMETER_CACHE_CONTRACT`
- `CATALOG_MESSAGE_CACHE_CONTRACT`
- `NO_HARDCODED_DB_PASSWORD`
- `AULA_ACTIVE_SQL_REFERENCES_ZERO`
- `NORMATIVE_MODEL_GHOST_FIELDS_ZERO`
- `SUITE_TRANCOUNT_ZERO`
