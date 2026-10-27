---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-26
---

# PLAN — HU010-HU011-consulta-reclamos-estudiante: Mis Reclamos del estudiante (solo consulta)

## Identidad y objetivo

- Objetivo: el estudiante consulta SOLO sus solicitudes de revisión de asistencia (estado, respuesta del docente y soporte vinculado), paginadas y filtrables por estado.
- Alcance acordado con Alejo: únicamente `GET /api/v1/estudiante/reclamos`. `DELETE /estudiante/reclamos/{id}` espera TD-059 y la categoría (HU014) espera TD-060.
- Contrato HTTP, decisiones y validación de las 3 capas: work item homónimo en el backend (`docs/work-items/HU010-HU011-consulta-reclamos-estudiante/`).

## Objetos de base de datos

| Objeto | Cambio |
|---|---|
| `usp_consultar_solicitudes_revision_estudiante` | Nuevo (READ_QUERY_RESULTSET + `totalRegistros`, paginación acotada como R2) |
| `test/test_consultas_reclamos_estudiante.sql` | Nuevo (E-01..E-08), registrado en `test_suite.sql` |
| `test/test_contract_closure.sql` | Exclusión de lectura (READ_QUERY_RESULTSET) para el SP nuevo |
| `schema/security/rol_asistencias_runtime_hu010_hu011.sql` | `GRANT EXECUTE` aditivo (THROW 52180 si falta el SP) |

## Reglas aplicadas (AGENTS.md)

- Sin cambios de tablas ni de objetos congelados: no se tocó `Sesion`, `SolicitudRevisionAsistencia`, `ArchivoSoporte` ni ningún SP de LB-004D (`usp_consultar_solicitudes_revision_docente`, radicación, archivos).
- Ownership en persistencia: cadena `SolicitudRevisionAsistencia → Asistencia → EstudianteGrupo → Estudiante` con `Estudiante.usuario = @idUsuarioEjecutor`.
- Resultset con las mismas columnas y tipos que R2 (compatibilidad verificada por E-08a).
- Estado del soporte vinculado leído del parámetro `ARCHIVO.ESTADO_ADJUNTO` (sin literal quemado).
- Mensajes por catálogo (`VAL_001`), sin textos quemados.

## Rollback

Revertir los commits del work item: `DROP PROCEDURE dbo.usp_consultar_solicitudes_revision_estudiante` y `REVOKE` del permiso (sin cambios de tablas ni datos).
