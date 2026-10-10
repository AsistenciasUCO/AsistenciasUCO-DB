---
status: EXECUTED
work_item: CC-003G-01
---

# CC-003G-01 — Plan de pruebas

Todas las pruebas viven en el gate `test_summary.ps1` (ids criticos obligatorios: un id faltante o duplicado falla el gate).

| Requisito de la auditoria MAINT-003H | Prueba (id) | Archivo |
|---|---|---|
| Metadata: `OBJECT_ID(...,'P')`, firma, orden, tipos, salida canonica de 4 columnas | `USER_SYNC_PUBLIC_METADATA`, `PLAN_PUBLIC_METADATA`, `PUBLIC_CANONICAL_RESULTSET`, `PUBLIC_SP_INVENTORY` | `test/test_usp_sincronizar_usuario.sql`, `test/test_usp_registrar_o_actualizar_plan_estudio.sql`, gates existentes |
| Usuario: alta valida, normalizacion, hash protegido, correlacion | `USER_SYNC_PUBLIC_SUCCESS`, `USER_SYNC_PUBLIC_NO_SECRET_LEAK` | usuario |
| Usuario: idempotencia (reintento exacto no escribe ni toca el password) | `USER_SYNC_PUBLIC_IDEMPOTENT` | usuario |
| Usuario: duplicados (documento, correo, perfil distinto), invalidaciones, tipo inexistente | `USER_SYNC_PUBLIC_DUPLICATE_DOCUMENT/_EMAIL`, `_CONFLICTING_PROFILE`, `_INVALID_EMAIL`, `_EMPTY_PASSWORD`, `_UNKNOWN_ID_TYPE`, `_REJECTIONS_PRE_TRANSACTION` | usuario |
| Usuario: carreras | `CC003G01_CONCURRENT_USER_IDENTICAL`, `CC003G01_CONCURRENT_USER_CONFLICT_EMAIL` (dos sesiones sqlcmd reales) | `test_summary.ps1` |
| Usuario: atomicidad / rollback (transaccion propia y savepoint) | `USER_SYNC_PUBLIC_ROLLBACK_SAVEPOINT`, `_ROLLBACK_OWN_TRANSACTION`, `_COMMIT_OWN_TRANSACTION` | usuario |
| Plan: alta, actualizacion, idempotencia, vista `uv_plan_estudio` consistente | `PLAN_PUBLIC_CREATE`, `_UPDATE`, `_IDEMPOTENT`, `_VIEW_CONSISTENT` | plan |
| Plan: dos actores / programa ajeno / plan ajeno | `PLAN_PUBLIC_TWO_ACTORS`, `_FOREIGN_PROGRAM_SCOPE`, `_FOREIGN_PLAN` | plan |
| Plan: ejecutor obligatorio y RBAC (NULL, estudiante, decano, inexistente, inactivo) | `PLAN_PUBLIC_EXECUTOR_REQUIRED`, `PLAN_PUBLIC_RBAC` | plan |
| Plan: entrada invalida, programa inexistente, duplicado de negocio | `PLAN_PUBLIC_INVALID_INPUT`, `_DUPLICATE_BUSINESS_KEY`, `_UPDATE_TO_TAKEN_INP` | plan |
| Plan: carreras e idempotencia concurrente | `CC003G01_CONCURRENT_PLAN_DUPLICATE_KEY`, `CC003G01_CONCURRENT_PLAN_IDEMPOTENT` | `test_summary.ps1` |
| Plan: rollback | `PLAN_PUBLIC_ROLLBACK_SAVEPOINT`, `_ROLLBACK_OWN_TRANSACTION`, `_COMMIT_OWN_TRANSACTION` | plan |
| Login SQL de minimo privilegio (no sa): EXEC publicos permitido, internos y DML directo denegados, lectura de tablas base denegada, ejecucion funcional | `CC003G01_RUNTIME_EXECUTE_GRANTS`, `_INTERNAL_EXEC_DENIED`, `_DIRECT_DML_DENIED`, `_BASE_TABLE_READ_DENIED`, `_PROVIDERS_FUNCTIONAL` | `test/verify_runtime_role_cc003g01.ps1` |
| Regresion UTC / D06 / freeze | ids existentes `UTC_D06_*`, `GOLDEN_PATH_*` sin cambios y manifiesto `FREEZE_MANIFEST_OK` | gate existente |

Los rechazos posteriores al savepoint ejecutan `ROLLBACK` dentro del SP y no pueden capturarse con `INSERT ... EXEC`
(error 3915); se verifican entre marcadores `TEST_RESULT_BEGIN/END` en `test_summary.ps1`, que ademas comprueba que el
resultado no contenga el marcador de password (`SECRET_MARKER`) y compara mensajes con el catalogo.

No cubierto (declarado): la rama `CATCH` de `usp_sincronizar_usuario` ante una excepcion propia (el nucleo interno captura
sus propios errores y devuelve `estadoResultado = 0`); la del plan SI se ejercita con el CHECK temporal (error 547 en el
INSERT propio).
