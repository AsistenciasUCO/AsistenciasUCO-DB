---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-26
---

# PLAN — HU064-HU060-HU061-consultas-coordinador: Consultas del coordinador sobre su programa

## Identidad y objetivo

- Objetivo: aislamiento por programa y permisos del runtime para las consultas existentes de grupos, sesiones y asistencias que ahora consume el backend.
- Integrado en `develop` el 2026-10-26 (PR de la BD #46 para HU081-HU083 y #44 para el resto).
- Contrato HTTP, decisiones y validación de las 3 capas: work item homónimo en el backend (`docs/work-items/HU064-HU060-HU061-consultas-coordinador/`).

## Objetos de base de datos

| Objeto | Cambio |
|---|---|
| `usp_consultar_grupos_paginado`, `usp_consultar_sesiones_grupo_paginado`, `usp_consultar_asistencias_sesion_paginado` | Sin cambios (ya filtraban por ejecutor vía `uv_auth_*`) |
| `schema/security/rol_asistencias_runtime_hu060_hu064.sql` | `GRANT EXECUTE` aditivo |

## Reglas aplicadas (AGENTS.md)

- Ningún objeto congelado del baseline se relajó: los objetos son nuevos o, en el caso de `usp_crear_periodo_academico`, se reescribió un SP que no podía insertar (omitía columnas `NOT NULL`).
- Mensajes por catálogo (`usp_obtener_mensaje_catalogo`), sin textos quemados.
- `rol_asistencias_runtime` solo recibe `EXECUTE` sobre los SP nuevos, en un archivo de permisos aditivo.
- Ámbito (programa o facultad) forzado dentro del SP.
- Pruebas en `test/` registradas en `test_suite.sql`.

## Rollback

Revertir los commits del work item; los SP nuevos se eliminan con `DROP PROCEDURE` y los permisos con `REVOKE` (sin cambios de tablas).
