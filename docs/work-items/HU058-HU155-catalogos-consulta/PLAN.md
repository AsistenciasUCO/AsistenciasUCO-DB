---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-04
---

# PLAN — HU058-HU155-catalogos-consulta

## Objetivo

- **HU155 y HU167** ("Ver los diferentes tipos de estados que se usan"): consulta de los estados de negocio. Decisión de John (2026-11-04): `Estado` (solicitudes) y `EstadoEstudianteGrupo`; sin `EstadoNotificacion`. Son catálogos de solo consulta (CAT-01).
- **HU058:** el tipo de programa de los cursos del docente sale de `uv_programa`. El backend lo resuelve sin cambiar la BD.

## Cambios

| Objeto | Cambio |
|---|---|
| `uv_estado` | Expone `codigo` (aditivo; la vista no está congelada) |
| `test/test_consolidado_auditoria_catalogos.sql` | T-155-01: `uv_estado` con código y nombre de los 5 estados de solicitud; `uv_estado_estudiante_grupo` con los estados del estudiante |

| `test/test_ses01_ventana_asistencia.sql` | Un `PRINT '';` antes del marcador TECH de `SES01_AUTO_CLOSED`. sqlcmd parte el mensaje con tildes y deja bytes sueltos al inicio de la línea siguiente; la línea vacía los absorbe (el gate local fallaba de forma intermitente). Aviso a José Alejandro en el mensaje del equipo |

Sin SP nuevos ni permisos: el backend lee las vistas de catálogo, que no tienen ámbito ni escritura.

## Rollback

Revertir el commit (quitar `codigo` de `uv_estado`).
