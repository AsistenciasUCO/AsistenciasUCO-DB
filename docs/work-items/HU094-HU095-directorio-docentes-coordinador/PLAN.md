---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-27
---

# PLAN — HU094-HU095-directorio-docentes-coordinador: ficha del docente y consolidado del directorio

## Identidad y objetivo

- **HU094:** ficha de un docente del programa del coordinador con el historial de los grupos que dictó o dicta, en todos los períodos y con filtro opcional, más un resumen de carga.
- **HU095:** consolidado del directorio docente del programa, con los vínculos activos e inactivos por tipo de vinculación.
- **Alcance confirmado por John (2026-10-27):** opción A en HU095; el coordinador solo ve su programa.
- **Referencia:** el contrato HTTP, las decisiones y la validación de las 3 capas están en el work item homónimo del backend (`docs/work-items/HU094-HU095-directorio-docentes-coordinador/`).

## Objetos de base de datos

| Objeto | Cambio |
|---|---|
| `usp_consultar_historial_grupos_docente_programa` | Nuevo (READ_QUERY_RESULTSET + `totalRegistros`; paginación R2) |
| `usp_consultar_resumen_docentes_programa` | Nuevo (READ_QUERY_RESULTSET) |
| `schema/security/rol_asistencias_runtime_hu094_hu095.sql` | `GRANT EXECUTE` aditivo (THROW 52189/52190 si faltan los SP) |
| `test/test_usp_consultar_historial_grupos_docente_programa.sql` | Nuevo (H-01..H-06), registrado en `test_suite.sql` |
| `test/test_usp_consultar_resumen_docentes_programa.sql` | Nuevo (R-01..R-03), registrado en `test_suite.sql` |
| `test/test_contract_closure.sql` | Exclusión READ_QUERY_RESULTSET de los 2 SP |

## Reglas aplicadas (AGENTS.md)

- **Sin cambios de tablas ni de objetos congelados** (`freeze-manifest -Mode Verify` = 0). Se leen objetos existentes:
  - `Grupo`, `PeriodoAcademico`, `Asignatura`, `SemestrePlanEstudio`, `PlanEstudio` y `DocentePrograma`;
  - `TipoVinculacion`, `uv_grupo` (estadísticas) y `uv_docente_programa`;
  - `CatalogoParametro` (`TIEMPO.ZONA_HORARIA_SQLSERVER`).
- **Ámbito:** el programa se resuelve del ejecutor con `usp_resolver_programa_coordinador_interno` (patrón de HU065-HU070) y nunca lo envía el cliente. Si el docente no tiene vínculo con ese programa, el SP lanza `GEN_001`, igual que con un docente inexistente.
- **Mensajes:** solo los códigos existentes del catálogo (`VAL_001`, `KPI_001`, `GEN_001`). No se agregan semillas.

## Rollback

`DROP PROCEDURE` de los 2 SP y `REVOKE` de los permisos. Sin cambios de datos.
