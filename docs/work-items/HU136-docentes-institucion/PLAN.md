---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-05
---

# PLAN — HU136-docentes-institucion

## Objetivo

- **HU136**, según el texto original del plan: "Ver la lista de todos los profesores de la universidad". Decisión de John (2026-11-05): es un directorio de solo consulta para el ADMINISTRADOR. Se descarta el "contador en tiempo real".
- **HU135** ("Ver la lista de todos los estudiantes") queda cubierta por el buscador de estudiantes del administrador (HU157). No cambia la BD.
- **HU161, HU162 y HU164** quedan DESCARTADAS: `Institucion` es un catálogo de solo consulta (ampliación de CAT-01). La BD no tenía SP de escritura.

## Cambios

| Objeto | Cambio |
|---|---|
| `usp_consultar_docentes_facultad_paginado` | Perfil `DECANO,ADMINISTRADOR`. El administrador ve los docentes con vínculo activo en las facultades de su institución (`uv_administrador.idInstitucion`). Nuevo filtro opcional `@idFacultad`. Ajuste aprobado por John: solo para el administrador, `@estadoVinculo` = `ACTIVO` (por defecto), `SIN_VINCULO` (docentes de la institución que tuvieron vínculo y hoy no tienen ninguno activo) o `TODOS`. Un docente que nunca tuvo vínculo no se puede atribuir a una institución y no aparece (fail-closed). Programas, grupos y filtros cuentan solo vínculos activos. Columna nueva al final, `tieneVinculoActivo`. El modo DECANO (HU128) no cambia |
| `test/test_consultas_transversales_hu112_hu157.sql` | T-136-01: el administrador ve al docente de su institución y solo de ella; el filtro por facultad funciona; un decano ajeno no ve nada aunque filtre por otra facultad; T-136-02: por defecto no aparecen docentes sin vínculo, `SIN_VINCULO` trae al docente retirado con programa vacío, `TODOS` trae ambos, y el decano nunca ve docentes sin vínculo (marcador crítico `HU136_ADMIN_TEACHERS_INSTITUTION`) |
| `docs/work-items/CAT-01-catalogos-solo-consulta/PLAN.md` | Ampliación: `Institucion` es de solo consulta |

Sin DDL, sin permisos nuevos (el SP ya tenía `GRANT`) y sin objetos congelados.

## Rollback

Revertir el commit. El parámetro nuevo es opcional y el resultset no cambia.
