---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-05
---

# PLAN — HU005-HU016-categorias-justificacion

## Objetivo

**HU005 y HU016** ("Ver los posibles motivos para justificar una ausencia o llegada tarde"): catálogo de las categorías con las que el estudiante justifica un reclamo.

- Hoy esas 6 categorías están escritas a mano en el formulario del frontend.
- Es un catálogo base de solo consulta (regla de John, 2026-11-04): se carga por seed y no tiene SP de escritura.
- Decisión de John (2026-11-05): las 6 categorías del formulario son las definitivas.

## Cambios

| Objeto | Cambio |
|---|---|
| `schema/tables/CategoriaJustificacion.sql` | Tabla nueva: `id` (PK), `codigo NVARCHAR(5)` único, `nombre NVARCHAR(50)` único, `descripcion NVARCHAR(250) NULL` |
| `schema/seed/30_categoria_justificacion.sql` | MERGE idempotente de MED, CAL, ACA, FMA, LAB y OTR. Los nombres son los que el formulario ya envía en `@categoria`; las descripciones son texto de ayuda |
| `schema/views/uv_categoria_justificacion.sql` | Vista de lectura. El runtime recibe `SELECT` con el bucle de vistas `uv_*` de `rol_asistencias_runtime.sql` |
| `migrations/12_categoria_justificacion_up.sql` / `_down.sql` | Up: tabla, vista y GRANT, idempotente. Down: borra la vista y la tabla (nada las referencia) |
| `test/test_consolidado_auditoria_catalogos.sql` | T-005-01: las 6 categorías con nombre y descripción; el nombre de MED sigue siendo el del formulario; no hay SP de escritura; el runtime tiene `SELECT` sobre la vista |
| `docs/modelos/ModeloEntidadRelacion.md` | Entidad `CategoriaJustificacion` (todavía sin relación) |

## Fuera de alcance (objetos congelados de LB-004D)

No se tocaron `SolicitudRevisionAsistencia` ni `usp_radicar_solicitud_revision_asistencia_v2`, que están en `DB_LB004D_SUPPORT_BINDING_MANIFEST.sha256`. Tampoco se regeneró ningún manifiesto.

La FK de la categoría (TD-060), el plazo de HU026B, el soporte obligatorio por categoría y HU014 quedan diseñados en [DISENO_CAMBIO_COORDINADO.md](DISENO_CAMBIO_COORDINADO.md), para el cambio coordinado con José Alejandro.

## Rollback

`migrations/12_categoria_justificacion_down.sql` y revertir el commit.
