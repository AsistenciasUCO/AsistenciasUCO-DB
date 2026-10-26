---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-26
---

# PLAN — HU104-HU105-HU109-HU119-HU145-lecturas-decano: Consultas del decano sobre su facultad

## Identidad y objetivo

- Objetivo: consultas de solo lectura del decano: directorio y ficha de estudiantes, estructura Facultad → Programa → Plan y cronograma de sesiones, limitadas a su facultad.
- Integrado en `develop` el 2026-10-26 (PR de la BD #46 para HU081-HU083 y #44 para el resto).
- Contrato HTTP, decisiones y validación de las 3 capas: work item homónimo en el backend (`docs/work-items/HU104-HU105-HU109-HU119-HU145-lecturas-decano/`).

## Objetos de base de datos

| Objeto | Cambio |
|---|---|
| `usp_consultar_estudiantes_facultad_paginado` | Nuevo (consulta paginada, `PAG_001`) |
| `usp_consultar_estudiante_facultad_detalle` | Nuevo (consulta) |
| `usp_consultar_estructura_facultad` | Nuevo (consulta; columna `clave` única por fila) |
| `usp_consultar_sesiones_facultad_paginado` | Nuevo (consulta paginada, `PAG_001`) |
| `test/test_contract_closure.sql` | Exclusiones de lectura (READ_QUERY_RESULTSET) para los 4 SP |
| `schema/security/rol_asistencias_runtime_hu104_hu145.sql` | `GRANT EXECUTE` aditivo |

## Reglas aplicadas (AGENTS.md)

- Ningún objeto congelado del baseline se relajó: los objetos son nuevos o, en el caso de `usp_crear_periodo_academico`, se reescribió un SP que no podía insertar (omitía columnas `NOT NULL`).
- Mensajes por catálogo (`usp_obtener_mensaje_catalogo`), sin textos quemados.
- `rol_asistencias_runtime` solo recibe `EXECUTE` sobre los SP nuevos, en un archivo de permisos aditivo.
- Ámbito (programa o facultad) forzado dentro del SP.
- Pruebas en `test/` registradas en `test_suite.sql`.

## Rollback

Revertir los commits del work item; los SP nuevos se eliminan con `DROP PROCEDURE` y los permisos con `REVOKE` (sin cambios de tablas).
