# DB-GP-001B Final Database Closure

## Status

Closed.

The DB Golden Path is frozen and ready as contract-first input for backend alignment.

## Final Gate Evidence

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

## Final Contract

- Contract: `docs/contracts/DB_BASELINE_CONTRACT.md`
- SHA-256 file: `docs/contracts/DB_BASELINE_CONTRACT.sha256`
- SHA-256: see `docs/contracts/DB_BASELINE_CONTRACT.sha256`

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

## Local Development Baseline

```text
Container: sql_server_asistencias
Database: gestionasistenciadb
State: ALIGNED_WITH_FROZEN_BASELINE
Temporary validation container: REMOVED
DBCODE: ENABLED
Golden Path: FROZEN
Backend integration target: sql_server_asistencias / gestionasistenciadb
```

`sql_server_asistencias` was rebuilt at database level from the baseline source-of-truth. The historical drift state is closed.

```text
DEV_INSTANCE_ALIGNED
```

The container was retained; only `gestionasistenciadb` was recreated. A local pre-sync backup was created outside the repository before recreation.

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

## DB Baseline Seal

`SESSION_SEQUENCE_USES_MAX_NOT_COUNT`, `SESSION_CODE_OVER_99`, `SESSION_CREATE_NO_DUPLICATE_NUMBER_CODE` y el canal tecnico `DBCODE=<codigo>|...` estan promovidos a `$criticalIds` en `test_summary.ps1`. `TOTAL_EXPECTED` vigente: 127.

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

- Contract SHA-256 (final): see `docs/contracts/DB_BASELINE_CONTRACT.sha256`
- GENERATED_FROM_COMMIT: `UNCOMMITTED_WORKTREE`

```text
DB GOLDEN PATH: FROZEN
READY FOR BACKEND ALIGNMENT: YES
```
