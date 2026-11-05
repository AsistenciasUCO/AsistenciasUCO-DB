---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-04
---

# PLAN — CAT-01-catalogos-solo-consulta

## Regla (John, 2026-11-04)

Perfil, TipoIdentificacion, TipoPrograma, Semestre, Componente, Area, EstadoEstudianteGrupo, RazonCausa, Estado y Dia son **catálogos de solo consulta**. Sus valores vienen de la carga inicial (`schema/seed/*.sql`, que sigue siendo válida). La app no los crea, edita, cambia de estado ni borra.

## Inventario en `develop` (25f79b2)

- Escribían en tiempo de ejecución solo TipoIdentificacion (HU153, PR #84), TipoPrograma (HU154) y Area (HU151 y HU152).
- Las demás entidades no tenían escritura.
- Los SP que hacen `SET estado = …` cambian la columna `estado` de otras tablas, no la tabla `Estado`.
- `usp_agregar_semestre_plan_estudio` y `usp_quitar_semestre_plan_estudio` escriben en `SemestrePlanEstudio` (la malla del plan), no en el catálogo `Semestre`.

## Cambios

| Objeto | Cambio |
|---|---|
| `usp_guardar_tipo_identificacion` + `_interno` (HU153) | Eliminados de `schema/` |
| `usp_crear_tipo_programa`, `usp_actualizar_tipo_programa`, `usp_cambiar_estado_tipo_programa` + sus 3 `_interno` (HU154) | Eliminados de `schema/` |
| `usp_crear_area`, `usp_actualizar_area`, `usp_cambiar_estado_area` + sus 3 `_interno` (HU151 y HU152) | Eliminados de `schema/` |
| `migrations/11_catalogos_solo_consulta_up.sql` / `_down.sql` | `DROP PROCEDURE` idempotente de los 14 SP en las bases ya desplegadas (`deploy_schema.ps1` no borra objetos). El rollback los restaura como estaban en `develop`, junto con sus `GRANT` |
| `rol_asistencias_runtime_inventario_backend.sql` | Se retiran las 6 concesiones de áreas y tipos de programa (34 → 28) |
| `rol_asistencias_runtime_hu061_hu172.sql` | Se retira la concesión de `usp_guardar_tipo_identificacion` |
| `test/test_usp_*_area.sql`, `test/test_usp_*_tipo_programa.sql` (6) | Eliminados y retirados de `test_suite.sql` |
| `test/test_runtime_grants_backend_inventory.sql` | Inventario sin los 6 SP |
| `test/test_consolidado_auditoria_catalogos.sql` | T-153-01 ahora comprueba que no existen SP de escritura de catálogos base y que las vistas listan el seed |
| Docs de arquitectura | Fichas marcadas como eliminadas, filas de inventario retiradas y conteo actualizado: 169 procedimientos (105 públicos y 64 `_interno`) |

**Se conservan:**
- Las vistas `uv_tipo_identificacion`, `uv_tipo_programa` y `uv_area`, y sus pruebas de contrato.
- La columna `estado` de `Area` y `TipoPrograma`, sin DDL: la fija el seed y el filtro "solo activos" sigue funcionando.
- Los mensajes `ARE_*` y `TPR_*` del catálogo: son datos de seed.

## Ampliación 2026-11-05: Institución

Decisión de John: `Institucion` también es un catálogo de solo consulta. Se carga por seed y la consulta HU163 sigue igual. HU161, HU162 y HU164 (crear, editar y activar instituciones) quedan DESCARTADAS. En la BD nunca existieron SP de escritura de `Institucion`. El backend retira los endpoints que respondían 501 (work item `HU136-docentes-institucion`).

## Rollback

Ejecutar `migrations/11_catalogos_solo_consulta_down.sql` y revertir el commit.
