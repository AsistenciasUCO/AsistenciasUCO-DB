---
status: VALIDATED_LOCAL_ISOLATED
work_item: CC-003G-01
date: 2026-10-10
---

# CC-003G-01 — Validacion (evidencia real, contenedores aislados)

Todo se ejecuto contra contenedores SQL Server 2022 Developer **nuevos y aislados** (`cc003g01_sqltest`, `127.0.0.1:14334`),
desplegados desde cero con `deploy_schema.ps1`. No se toco la DB principal, ni se desplego a produccion, ni se hizo merge.
No se imprimieron ni versionaron credenciales (password de `sa` generado al vuelo en un archivo temporal fuera del repo).

## Commits exactos ejecutados

| Que | SHA | Arbol |
|---|---|---|
| Baseline DB (antes de cambios), rama `feat/utc-d06-post-freeze` | `3842f70` | limpio |
| Quality gate SQL final (despliegue limpio + `test_summary.ps1`) | `0749c3a1af77ec6879efc70d5e7396054ff58fb1` | limpio (`git status --short` vacio) |
| Gate previo (mismo codigo salvo `USER_SYNC_PUBLIC_INACTIVE_REPLAY`) | `3f2ccf85ad04de230b05db0b5bee5a381c5991a4` | limpio; 217/218 PASS, 1 skip permitido |

Los commits posteriores a `0749c3a` solo agregan documentacion de este directorio (`git diff 0749c3a..HEAD --stat` lo prueba).

## Resultados

| Comprobacion | Baseline `3842f70` | Con CC-003G-01 (`0749c3a`) |
|---|---|---|
| `test_summary.ps1` ejecutadas / PASS / FAILED / SKIPPED | 179 / 178 / 0 / 1 | **219 / 218 / 0 / 1** |
| Skip | `XACT_STATE_MINUS_ONE_RUNTIME` (permitido, igual que antes) | el mismo, sin skips nuevos (`UNAUTHORIZED_SKIPS=0`) |
| Ids criticos faltantes | 0 | 0 (`TOTAL_EXPECTED=216`) |
| SP publicos repo / instancia | 31 / 31 | 33 / 33 (`PUBLIC_SP_INVENTORY`) |
| `PUBLIC_CANONICAL_RESULTSET` (4 columnas exactas, sin errores de descubrimiento) | PASS | PASS (incluye los 2 SP nuevos) |
| `@@TRANCOUNT` final / errores SQL | 0 / 0 | 0 / 0 |
| Regresion UTC-D06 (`UTC_D06_*`, 22 ids) | PASS | PASS (incluye `UTC_D06_RUNTIME_PERMISSIONS`, `_DIRECT_UPDATE_REJECTED`, `_CONCURRENT_V2_CREATE`) |
| Freeze / manifiestos | `FREEZE_MANIFEST_OK entries=10 post_freeze_superseded=3 post_freeze_work_item=10` | identico (no se modificaron archivos congelados ni de D06) |
| `NO_HARDCODED_DB_PASSWORD` y gates de secretos | PASS | PASS |

Pruebas nuevas (todas PASS en el gate final): `USER_SYNC_PUBLIC_*` (METADATA, SUCCESS, NO_SECRET_LEAK, IDEMPOTENT, INACTIVE_REPLAY,
REJECTIONS_PRE_TRANSACTION, DUPLICATE_DOCUMENT, DUPLICATE_EMAIL, CONFLICTING_PROFILE, INVALID_EMAIL, EMPTY_PASSWORD, UNKNOWN_ID_TYPE,
ROLLBACK_SAVEPOINT, COMMIT_OWN_TRANSACTION, ROLLBACK_OWN_TRANSACTION), `PLAN_PUBLIC_*` (METADATA, CREATE, VIEW_CONSISTENT, IDEMPOTENT, UPDATE,
TWO_ACTORS, EXECUTOR_REQUIRED, RBAC, FOREIGN_PROGRAM_SCOPE, INVALID_INPUT, DUPLICATE_BUSINESS_KEY, UPDATE_TO_TAKEN_INP, FOREIGN_PLAN,
ROLLBACK_SAVEPOINT, COMMIT_OWN_TRANSACTION, ROLLBACK_OWN_TRANSACTION), `CC003G01_CONCURRENT_*` (4 carreras reales de dos sesiones) y
`CC003G01_RUNTIME_*` (5 comprobaciones con un login SQL real de minimo privilegio, no `sa`: EXEC publicos permitido; nucleo interno, validadores
internos, DML directo y lectura de tablas base denegados; ejecucion funcional alta/reintento/rechazo y plan alta/reintento/rechazo).

## Hallazgos durante la validacion (corregidos antes de cerrar)

1. `sp_getapplock` dentro de un SP publico hace que `sys.dm_exec_describe_first_result_set_for_object` falle (error 11520) y rompe
   `PUBLIC_CANONICAL_RESULTSET`; se reemplazo por bloqueos `UPDLOCK, HOLDLOCK`.
2. `ROLLBACK` dentro de un SP no puede capturarse con `INSERT ... EXEC` (error 3915): los rechazos posteriores al savepoint se verifican por
   marcadores en `test_summary.ps1`.
3. Un reintento exacto de un usuario **inactivo** no debe reconfirmarse (decision de seguridad tomada tras revisar el diseno; cubierta por
   `USER_SYNC_PUBLIC_INACTIVE_REPLAY`).

## No ejecutado / limitaciones

- Despliegue en la DB institucional/staging y aprobacion del owner DB: **NOT_RUN** (requieren decision humana).
- La rama `CATCH` de `usp_sincronizar_usuario` ante una excepcion propia no se ejercita (el nucleo interno captura la suya); la del plan si.
- SonarCloud/CodeQL del repositorio DB: se ejecutan en CI remoto al abrir el PR; no se presumen.
