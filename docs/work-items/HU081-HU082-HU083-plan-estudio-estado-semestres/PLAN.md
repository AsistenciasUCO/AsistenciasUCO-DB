---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-26
---

# PLAN — HU081-HU082-HU083-plan-estudio-estado-semestres: Estado y semestres del plan de estudio

## Identidad y objetivo

- Objetivo: permitir al coordinador activar/inactivar un plan y añadir o quitar semestres (máx. 10, solo el último y sin asignaturas).
- Integrado en `develop` el 2026-10-26 (PR de la BD #46 para HU081-HU083 y #44 para el resto).
- Contrato HTTP, decisiones y validación de las 3 capas: work item homónimo en el backend (`docs/work-items/HU081-HU082-HU083-plan-estudio-estado-semestres/`).

## Objetos de base de datos

| Objeto | Cambio |
|---|---|
| `usp_cambiar_estado_plan_estudio` | Nuevo (comando) |
| `usp_agregar_semestre_plan_estudio` | Nuevo (comando) |
| `usp_quitar_semestre_plan_estudio` | Nuevo (comando) |
| `uv_plan_estudio` | El plan es activo solo si el programa y `PlanEstudio.estado` lo están (columnas sin cambio) |
| `schema/seed/17_mensajes_plan_estudio.sql` | `PLA_002`..`PLA_006` |
| `schema/security/rol_asistencias_runtime_hu081_hu083.sql` | `GRANT EXECUTE` aditivo |

## Reglas aplicadas (AGENTS.md)

- Ningún objeto congelado del baseline se relajó: los objetos son nuevos o, en el caso de `usp_crear_periodo_academico`, se reescribió un SP que no podía insertar (omitía columnas `NOT NULL`).
- Mensajes por catálogo (`usp_obtener_mensaje_catalogo`), sin textos quemados.
- `rol_asistencias_runtime` solo recibe `EXECUTE` sobre los SP nuevos, en un archivo de permisos aditivo.
- Ámbito (programa o facultad) forzado dentro del SP.
- Pruebas en `test/` registradas en `test_suite.sql`.

## Rollback

Revertir los commits del work item; los SP nuevos se eliminan con `DROP PROCEDURE` y los permisos con `REVOKE` (sin cambios de tablas).
