---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-26
---

# PLAN — HU096-HU097-HU098-periodos-academicos: Gestión de períodos académicos por el administrador

## Identidad y objetivo

- Objetivo: que el ADMINISTRADOR de la institución cree, modifique y elimine (sin grupos) los períodos académicos; decano y coordinador solo consultan.
- Integrado en `develop` el 2026-10-26 (PR de la BD #46 para HU081-HU083 y #44 para el resto).
- Contrato HTTP, decisiones y validación de las 3 capas: work item homónimo en el backend (`docs/work-items/HU096-HU097-HU098-periodos-academicos/`).

## Objetos de base de datos

| Objeto | Cambio |
|---|---|
| `usp_crear_periodo_academico` | Reescrito (antes omitía columnas `NOT NULL` y no podía insertar) |
| `usp_actualizar_periodo_academico` | Nuevo (comando) |
| `usp_eliminar_periodo_academico` | Nuevo (comando) |
| `usp_resolver_institucion_gestor_periodo_interno` | Nuevo (interno: RBAC `ADMINISTRADOR` + institución activa) |
| `schema/seed/17_mensajes_periodo_academico.sql` | `PER_001`..`PER_006` |
| `schema/security/rol_asistencias_runtime_hu096_hu098.sql` | `GRANT EXECUTE` aditivo |

## Reglas aplicadas (AGENTS.md)

- Ningún objeto congelado del baseline se relajó: los objetos son nuevos o, en el caso de `usp_crear_periodo_academico`, se reescribió un SP que no podía insertar (omitía columnas `NOT NULL`).
- Mensajes por catálogo (`usp_obtener_mensaje_catalogo`), sin textos quemados.
- `rol_asistencias_runtime` solo recibe `EXECUTE` sobre los SP nuevos, en un archivo de permisos aditivo.
- Ámbito (programa o facultad) forzado dentro del SP.
- Pruebas en `test/` registradas en `test_suite.sql`.

## Rollback

Revertir los commits del work item; los SP nuevos se eliminan con `DROP PROCEDURE` y los permisos con `REVOKE` (sin cambios de tablas).
