# DB-GP-001C - Develop hardening + final freeze before JPA

PRIMARY_VARIABLE: DB develop hardening / freeze. Fuera de alcance: JPA, backend, frontend, paginacion API, integracion backend de SESSION_CONTEXT, permisos SQL (GRANT/REVOKE), tablas/columnas/SP Golden Path.

Alcance autorizado:

1. Secret hygiene (`.env.template`, gate `NO_HARDCODED_DB_PASSWORD` ampliado).
2. `uv_auth_*` fail-closed (sin contexto => 0 filas).
3. `usp_consultar_grupos_paginado` restaura el `SESSION_CONTEXT` previo (exito y excepcion).
4. Tests (RED primero), gate de inmutabilidad Golden Path, manifest.
5. Documentacion / provenance / freeze.
6. Deploy real + quality gate real.

## Inventario uv_auth_*

| Vista | Clasificacion |
| --- | --- |
| uv_auth_institucion, facultad, programa, grupo, decano, coordinador, docente, estudiante | DIRECT_CONTEXT_FILTER |
| uv_auth_periodo_academico (<- institucion), sesion (<- grupo), asistencia (<- sesion), solicitud_revision_asistencia (<- asistencia) | INHERITS_AUTH_VIEW |
| (ninguna) | OTHER |

Consumidores reales de `uv_auth_*` en el repo: solo `usp_consultar_grupos_paginado` (siempre establece contexto) y los tests. Ningun consumidor depende del acceso total con `NULL`.

## Decisiones

- Restauracion con `SQL_VARIANT` (valor original) via `sys.sp_set_session_context`, sin `TRY_CAST`, para no alterar un contexto previo no-GUID.
- Falla de prueba (Caso C) inyectada con `ALTER VIEW` transaccional revertido con `ROLLBACK`.
- El addendum no se incluye en el manifest (registra el SHA final, que no puede contenerse a si mismo); el commit final de codigo y el de documentacion se separan.
- `usp_consultar_grupos_paginado` queda sin normalizar al resultset de 4 columnas: es `READ_QUERY_RESULTSET`.
