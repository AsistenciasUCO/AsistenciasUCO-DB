---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-27
---

# PLAN — HU051-retirar-estudiante-grupo: el docente titular retira a un estudiante de su grupo

## Identidad y objetivo

- Objetivo: el docente titular retira a un estudiante de su grupo con motivo obligatorio; la matrícula queda "inactivo", se libera el cupo, se conservan las asistencias y se audita el motivo. Se consultan los destinatarios del aviso (estudiante, docente, coordinador del programa).
- Reglas confirmadas por John (2026-10-27): estado existente `I`; se permite con asistencias; motivo obligatorio; bloqueo si el período terminó.
- Contrato HTTP, decisiones y validación de las 3 capas: work item homónimo del backend (`docs/work-items/HU051-retirar-estudiante-grupo/`).

## Objetos de base de datos

| Objeto | Cambio |
|---|---|
| `usp_retirar_estudiante_grupo` | Nuevo (comando, resultset canónico; `UPDLOCK, HOLDLOCK`; auditoría en `AuditoriaEvento`) |
| `usp_consultar_destinatarios_retiro_estudiante_grupo` | Nuevo (READ_QUERY_RESULTSET, solo docente titular) |
| `schema/seed/21_mensajes_retiro_estudiante_grupo.sql` | Mensajes `RET_001..RET_005` (usuario y técnico) |
| `schema/security/rol_asistencias_runtime_hu051.sql` | `GRANT EXECUTE` aditivo (THROW 52181/52182 si faltan los SP) |
| `test/test_usp_retirar_estudiante_grupo.sql` | Nuevo (R-01..R-09), registrado en `test_suite.sql` |
| `test/test_contract_closure.sql` | Exclusión READ_QUERY_RESULTSET de la consulta de destinatarios |

## Reglas aplicadas (AGENTS.md)

- Sin cambios de tablas ni de objetos congelados (`freeze-manifest -Mode Verify` = 0). Se usan `EstadoEstudianteGrupo` (I), `AuditoriaEvento` y `CatalogoParametro` (`TIEMPO.ZONA_HORARIA_SQLSERVER`) existentes.
- Ámbito en el SP: `Grupo.docente → Docente.usuario = @idUsuarioEjecutor` sobre tablas base (más estricto que `uv_auth_grupo`, que admite también admin/decano/coordinador).
- Mensajes por catálogo, sin textos quemados.

## Rollback

`DROP PROCEDURE` de los 2 SP, `REVOKE` de los permisos y borrar los mensajes `RET_*` (sin cambios de tablas). Las matrículas retiradas se pueden reactivar con un `UPDATE` controlado de `EstudianteGrupo.estado`.

## Cambio posterior: INT-HU-01 (2026-10-28)

Decisión de John (opción a): si un estudiante retirado del grupo (HU051, matrícula `I`) vuelve a solicitar el ingreso y el docente lo acepta (HU055), `usp_resolver_solicitud_ingreso_grupo` **reactiva** esa matrícula (`I` → `A`) en lugar de fallar con 409 por duplicado. Cupo y regla ESP de HU008 respetados; una matrícula activa sigue bloqueando (`SIG_004`). Prueba: `test/test_int_hu01_reactivar_matricula_retirada.sql` (RM-01..RM-03). Detalle: `docs/work-items/INT-HU-01-reactivar-matricula-retirada/`.

> **Retirado en CULM-001 A (2026-11-07):** las solicitudes de ingreso (HU053-HU055) se descartaron; la reactivacion de la matricula retirada vive en `usp_internal_reactivar_matricula_retirada` (DEC-009). Ver `docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`, addendum CULM-001 A.
