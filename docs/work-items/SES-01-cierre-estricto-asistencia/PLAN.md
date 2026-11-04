---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-03
---

# PLAN — SES-01: cierre estricto de la ventana de registro de asistencia

**Estado: PENDIENTE DE APROBACIÓN DEL OWNER DB (John Duque).** Modifica un SP congelado (`usp_registrar_asistencias_sesion`, DEVELOP_FREEZE / Golden Path). No se aplica a ninguna base compartida hasta esa aprobación.

## Requisito (decisión funcional 2026-11-02)

Fuente: backend `docs/work-items/SEC-BASELINE-019-upgrade-performance/PLAN-CORRECCIONES-POR-ROL.md`, decisión 1 y SES-01.

El docente solo registra, corrige o sustituye asistencias ordinarias cuando
`fechaHoraInicio <= instanteActualUtc < fechaHoraFin`. Sesión 08:00–10:00 (Bogotá): 07:59:59 bloqueado, 08:00:00 permitido, 09:59:59 permitido, 10:00:00 bloqueado, 12:00 bloqueado. Sin tolerancia posterior. La restricción se cumple en Frontend, Backend **y** en la persistencia. La rectificación posterior al cierre solo ocurre por el flujo formal de reclamos (SES-04).

## Causa corregida

`usp_registrar_asistencias_sesion` validaba existencia, titularidad, estados AN/SJC/EX, matrícula y atomicidad, pero no el instante de escritura: una sesión cerrada (o futura) aceptaba el lote. `usp_registrar_asistencia_estudiante_autonomo` tampoco validaba la ventana y no tenía transacción propia.

## Contrato

| Elemento | Cambio |
|---|---|
| Firma y resultset de 4 columnas de ambos SP | **Sin cambio** |
| `usp_validar_sesion_ventana_registro_interno` | **Nuevo** SP interno (sin grant runtime) |
| `SES_007` | Sesión no iniciada (`SYSUTCDATETIME() < fechaHoraInicio`) |
| `SES_008` | Sesión cerrada (`SYSUTCDATETIME() >= fechaHoraFin`) |
| `SES_009` | Procedencia temporal INDETERMINADA (`procedenciaTemporal` NULL o desconocida) |
| Esquema (`dbo.Sesion`) | **Sin cambio**: no se agrega columna `cerrada`/`estado`/`status`; el cierre se deriva del instante UTC confirmado (UTC-D06) |

Reglas de implementación:

1. El reloj autoritativo es `SYSUTCDATETIME()` del motor; nunca el del cliente.
2. Solo `UTC_V2`, `UTC_GENERADOR` y `UTC_OWNER` permiten tratar los `DATETIME2` como instantes UTC (misma regla que `uv_sesion_v2`).
3. La validación ocurre **dentro** de la transacción del lote (propia o savepoint), leyendo la fila de `dbo.Sesion` con `UPDLOCK, HOLDLOCK`; se repite justo antes del `COMMIT`. Un lote que llega al punto de escritura después del cierre se revierte completo.
4. Las validaciones previas (correlación, ejecutor, RBAC, existencia, titularidad, JSON, estados, duplicados y matrícula) conservan su orden y prioridad de error.
5. `usp_resolver_solicitud_revision_asistencia` **no** consume la ventana: es el camino extraordinario autorizado (SES-04).
6. `usp_ejecutar_cierre_masivo_periodo` no escribe `DetalleAsistencia` (solo lee inasistencias para cancelar matrícula): fuera de alcance.

## Archivos

- `schema/stored-procedures/usp_validar_sesion_ventana_registro_interno.sql` (nuevo)
- `schema/stored-procedures/usp_registrar_asistencias_sesion.sql` (PASO 4.0 y 4.2)
- `schema/stored-procedures/usp_registrar_asistencia_estudiante_autonomo.sql` (transacción propia/savepoint + ventana)
- `schema/seed/04_mensaje.sql` (`SES_007..009`), `docs/catalogos/catalogo-mensajes.md`
- `docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md` (addendum SES-01)
- `scripts/freeze-manifest.ps1`, `docs/contracts/DB_UTC_D06_POST_FREEZE_MANIFEST.sha256`, `docs/contracts/DB_DEVELOP_FREEZE_ADDENDUM.md`
- Pruebas: `test/test_ses01_ventana_asistencia.sql` (nuevo), `test_suite.sql`, `test_summary.ps1`
- Fixtures ajustados a la regla: `test/test_attendance_commands.sql` (sesiones activas `UTC_V2`), `test_summary.ps1` (upsert concurrente), `test/fixtures/maint_003g_attendance_fixture.sql` (sesión activa vía `usp_crear_sesion_v2`)

## Matriz de pruebas (`test/test_ses01_ventana_asistencia.sql`)

| ID | Caso | Esperado |
|---|---|---|
| `SES01_WINDOW_LOCK_HELD` | La validación retiene bloqueo `U` sobre la fila de `dbo.Sesion` | Bloqueo presente hasta fin de transacción |
| `SES01_BULK_BEFORE_START` | 07:59:59 | `SES_007`, sin filas |
| `SES01_BULK_EXACT_START` | 08:00:00 (inicio = reloj del motor) | Registrado |
| `SES01_BULK_DURING` | Lote de 2 estudiantes en curso | Registrado completo |
| `SES01_BULK_JUST_BEFORE_END` | Fin a 30 s | Registrado |
| `SES01_BULK_EXACT_END` | 10:00:00 (fin = reloj del motor) | `SES_008`, sin filas |
| `SES01_BULK_TWO_HOURS_AFTER` | 12:00, lote de 2 | `SES_008`, sin filas |
| `SES01_BULK_INDETERMINATE` | Procedencia NULL con horas "activas" | `SES_009`, sin filas |
| `SES01_BULK_CLOSED_HISTORY_PRESERVED` | Sesión cerrada con histórico AN; lote SJC/EX | `SES_008`, histórico intacto |
| `SES01_AUTO_CLOSED` / `_BEFORE_START` / `_INDETERMINATE` | Registro autónomo del estudiante | `SES_008` / `SES_007` / `SES_009`, sin filas |

Regresión: `test_attendance_commands.sql`, `ATTENDANCE_CONCURRENT_UPSERT`, golden path (`GOLDEN_PATH_SP_SIGNATURES_FROZEN`, `GOLDEN_PATH_MUTATION_RESULTSET_FROZEN`, `GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED`).

## Rollback

Revertir el PR (los SP vuelven a la versión anterior por `CREATE OR ALTER`). Los mensajes `SES_007..009` pueden permanecer en el catálogo sin efecto. No hay migración de datos.

## Dependencias

- Backend `alejovh12/AsistenciasUCO` rama `fix/ses01-cierre-estricto-asistencia`: clasifica `SES_007/008/009` como 409 y valida la ventana antes de invocar el SP.
- Frontend `shesho22/AsistenciasUCO-Frontend` rama `fix/ses01-cierre-estricto-asistencia`.
- Orden de integración: DB → Backend → Frontend.
