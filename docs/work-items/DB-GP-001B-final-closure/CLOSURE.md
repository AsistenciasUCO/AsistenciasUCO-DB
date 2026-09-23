# DB-GP-001B Final Database Closure

## Status

Closed.

The DB Golden Path is frozen and ready as contract-first input for backend alignment.

## Final Gate Evidence

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

## Final Contract

- Contract: `docs/contracts/DB_BASELINE_CONTRACT.md`
- SHA-256 file: `docs/contracts/DB_BASELINE_CONTRACT.sha256`
- SHA-256: `1fd728e43d2bdbdc6b395bc5aad9021105117281c7c18b64afc39a6d45937103` (ver `## DB Baseline Seal` para procedencia)

## Shape

```text
ADDED_COLUMNS=0
REMOVED_COLUMNS=0
RENAMED_COLUMNS=0
TYPE_CHANGES=0
NULLABILITY_CHANGES=0
TABLE_SHAPE_HASH=337d39f7997e8b224028e20b194be15918c5136b1fa55ff8b40f9f768efe43d1
```

## Deploy Evidence

```text
FRESH_DEPLOY=PASS
FRESH_GATE=PASS
REPEAT_DEPLOY=PASS
REPEAT_GATE=PASS
CATALOG_FIXTURE_SURVIVES=1
```

## Old Dev Instance

`sql_server_asistencias` has historical drift and requires rebuild from the baseline source-of-truth.

```text
DEV_INSTANCE_REBUILD_REQUIRED
```

No destructive cleanup was run against that instance.

## Remaining Blockers

None.

## DB-GP-001C Session Sequence Hotfix

`Sesion.numero`/`Sesion.codigo` concurrency blocker closed:

- `usp_crear_sesion`: correlativo pasa de `COUNT(*) + 1` a `COALESCE(MAX(numero), 0) + 1`, calculado dentro de la misma transaccion (ownership propia o savepoint) protegida con `UPDLOCK, HOLDLOCK`.
- `usp_generar_sesiones_grupo`: calculo de `MAX(numero)` movido dentro de `BEGIN TRANSACTION` con `UPDLOCK, HOLDLOCK`.
- `codigo`: generado sin truncamiento (`SES-01` ... `SES-99`, `SES-100+`), reemplazando `RIGHT(...,2)`.
- `dbo.Sesion`: `UX_Sesion_Grupo_Numero` y `UX_Sesion_Grupo_Codigo` (indices UNIQUE idempotentes, con validacion previa de duplicados via `DATA_INVARIANT_CONFLICT`).
- Tests agregados: `SESSION_SEQUENCE_USES_MAX_NOT_COUNT`, `SESSION_CODE_OVER_99`, `SESSION_CREATE_NO_DUPLICATE_NUMBER_CODE`.

Fix adicional de arnes de pruebas (no afecta esquema/SPs de negocio):

- `test_summary.ps1` (bloque `ATTENDANCE_CONCURRENT_UPSERT`): el JSON del worker se pasaba a `sqlcmd` via `-Q` con comillas dobles embebidas, las cuales el marshalling de argumentos nativos de Windows/PowerShell corrompia, causando `estadoResultado = 0` silencioso en ambos jobs concurrentes. Se cambio a escribir el query en un archivo temporal ejecutado con `-i` (mismo patron que el resto de la suite), eliminando la dependencia de comillas embebidas en un argumento de proceso nativo.

### Final Gate Evidence (post-hotfix)

```text
TOTAL_EXPECTED=115
TOTAL_EXECUTED=119
PASSED=118
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

## DB Baseline Seal

`SESSION_SEQUENCE_USES_MAX_NOT_COUNT`, `SESSION_CODE_OVER_99` y `SESSION_CREATE_NO_DUPLICATE_NUMBER_CODE` promovidos a `$criticalIds` en `test_summary.ps1`. `TOTAL_EXPECTED` sube de 115 a 118. No se modifico logica de `schema/**` en este paso (docs/gate only).

```text
TOTAL_EXPECTED=118
TOTAL_EXECUTED=119
PASSED=118
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

- Contract SHA-256 (final): `1fd728e43d2bdbdc6b395bc5aad9021105117281c7c18b64afc39a6d45937103`
- GENERATED_FROM_COMMIT: `UNCOMMITTED_WORKTREE`

```text
DB GOLDEN PATH: FROZEN
READY FOR BACKEND ALIGNMENT: YES
```
