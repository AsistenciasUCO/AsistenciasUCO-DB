---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-01
---

# VALIDATION — F3: el docente crea sus propios grupos

## Evidencia ejecutada (2026-11-01, BD local `sql_server_asistencias`)

| Comando | Resultado |
|---|---|
| `./deploy_schema.ps1` | Exit 0 |
| `test/test_usp_guardar_horarios_grupo.sql` (sqlcmd, solo) | Pasan los 8 escenarios de F1 (con `GROUP_SCHEDULE_SCOPE` actualizado para F3) y `TEACHER_CREATES_GROUP` |
| `test/test_usp_consultar_oferta_creacion_grupo_docente.sql` (sqlcmd, solo) | Pasan `TEACHER_OFFER_LINKED`, `TEACHER_OFFER_NO_LINK` y `TEACHER_OFFER_REJECTS_OTHER_PROFILES` |
| `test/test_cruce_horario_docente.sql` | Pasan los 6 escenarios |
| `test/test_usp_cambiar_estado_docente_programa.sql`, `test/test_reactive_academic.sql`, `test/test_public_objects.sql` | Pasan (usan `usp_crear_grupo`) |
| `./scripts/generar-catalogo-mensajes.ps1 -Check` | `CATALOGO_MENSAJES_OK codigos=144` |

## Pendiente

- **Gate completo (`test_summary.ps1`):** no se corrió completo. En esa BD local la suite se corta antes por objetos viejos sin borrar (migraciones 08 y 09), y en una BD desechable nueva la suite se detuvo en `test_usp_retirar_estudiante_grupo` (HU051), incluso en la versión de `develop`, sin relación con este cambio. Lo confirmará el job "DB Quality Gate" del PR.
- `test/test_usp_crear_actualizar_grupo.sql` da un conflicto de intercalación (`Msg 468`) solo en la BD local (tempdb y base con intercalaciones distintas); no se analizó contra la BD nueva.
- Backend y frontend: pendientes de F3.

## Estado

`PARCIAL`: BD lista y probada en local; falta el gate completo en CI, el backend y el frontend.
