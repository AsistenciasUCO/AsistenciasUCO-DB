---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-04
---

# PLAN — HU061-HU147-HU153-HU172-consolidado-auditoria-catalogos

> **Actualización (2026-11-04):** por la regla de John de catálogos base de solo consulta, la escritura de HU153 se retiró en CAT-01 (`docs/work-items/CAT-01-catalogos-solo-consulta/`). El resto de este work item sigue vigente.

## Identidad y objetivo

- **HU061:** consolidado de asistencia por cohorte, materia y docente. Decisión de John (2026-11-04): la cohorte es el **período académico** del grupo, porque el modelo no tiene cohorte de ingreso.
- **HU172:** consulta de la auditoría de cambios de asistencia. Muestra el rastro que ya existe en `AuditoriaEvento` (quién, cuándo, acción, recurso y resultado), solo para el ADMINISTRADOR. No hay valores antes y después.
- **HU147:** consultar los componentes de formación (BAS, INS, ESP).
- **HU153:** administrar los tipos de documento. Solo crear y editar el nombre: sin columna de estado y sin DDL (decisión de John).
- **P5 (defecto):** crear o editar una asignatura asignaba un área, un componente o un semestre "cualquiera" (`TOP 1` sin orden) cuando el valor no coincidía. Decisión de John: se asigna uno que exista en la tabla; si no existe, se rechaza.
- **Reglas de asignatura (John, 2026-11-04):** los créditos son obligatorios y mayores que cero (sin valor por defecto); el semestre debe existir en el plan (no se crea desde aquí); el coordinador solo crea y edita asignaturas de planes de su propio programa.
- **Fuera de alcance:** HU148 queda **DESCARTADA** (los componentes son fijos BAS/INS/ESP por regla de negocio; la oferta no cambia) y HU006 (queda solo como consulta, ya en `develop`).
- Contrato HTTP y validación de las 3 capas: work item homónimo del backend.

## Regla de negocio confirmada (John, 2026-11-04)

Las asignaturas son BAS, INS o ESP. Un estudiante solo entra a un programa por una asignatura ESP. BAS e INS son transversales. Los SP de oferta y matrícula no cambian.

## Objetos de base de datos

| Objeto | Cambio |
|---|---|
| `usp_consultar_consolidado_asistencia_grupos_paginado` | Nuevo (HU061). Una fila por grupo; COORDINADOR, DECANO o ADMINISTRADOR con su ámbito (`uv_auth_grupo`). Los grupos se materializan en una variable de tabla antes de agregar el resumen, para evitar un plan con reserva de memoria desproporcionada (Msg 701). |
| `uv_auditoria_evento` | Vista base nueva sobre `AuditoriaEvento` (tabla inmutable, sin cambios): nombre del usuario y marca `esAccionAsistencia`. |
| `usp_consultar_auditoria_eventos_paginado` | Nuevo (HU172). Solo ADMINISTRADOR; rango `[desdeUtc, hastaUtc)` obligatorio (`GEN_002`); filtros por acción, tipo e id de recurso, usuario y resultado; por defecto solo asistencia. |
| `uv_componente` | Agrega la columna `codigo` (aditivo; la vista no está congelada). |
| `usp_consultar_componentes_formacion` | Nuevo (HU147). ADMINISTRADOR, DECANO o COORDINADOR. |
| `usp_guardar_tipo_identificacion` + `_interno` | Nuevos (HU153). Solo ADMINISTRADOR; alta con código de 1 a 5 letras único y nombre de 3 a 50 único; edición solo del nombre (el código es inmutable); salida canónica de 4 columnas. |
| `usp_resolver_area_componente_asignatura_interno` | Nuevo (P5). Coincidencia exacta con código o nombre; `GEN_001` si no existe. |
| `usp_crear_asignatura` | P5: usa el interno (área y componente obligatorios) en lugar de `TOP 1`. Créditos nulos o ≤ 0 se rechazan con `ASI_001` (antes ponía 3). El plan debe existir (`PLA_002`) y ser del programa del coordinador (`SEC_002`, `usp_validar_titularidad_jerarquica_interno`). El semestre debe existir en el plan (`PLA_004`); ya no inserta `SemestrePlanEstudio`. |
| `usp_actualizar_asignatura` | P5: aplica el área y el componente si llegan (antes los ignoraba) y rechaza los inexistentes. Créditos ≤ 0 se rechazan con `ASI_001`; nulos conservan los actuales (actualización parcial). La titularidad ya la validaba `usp_validar_gestion_asignatura_coordinador_interno` (REC2). |
| `schema/seed/29_mensajes_asignatura.sql` | Mensaje nuevo `ASI_001` (usuario y técnico); `docs/catalogos/catalogo-mensajes.md` regenerado. |
| `schema/security/rol_asistencias_runtime_hu061_hu172.sql` | `GRANT EXECUTE` sobre los 4 SP públicos nuevos. |
| `test/test_consolidado_auditoria_catalogos.sql` | Pruebas nuevas (registradas en `test_suite.sql`). |
| `test/test_subject_catalog.sql` | Ajuste por P5: crear asignatura envía un área y un componente reales y un semestre que existe en el plan. |
| `test/test_rec2_rbac_asignatura.sql` | RA-05: crear en el plan de otro programa da `SEC_002`; el coordinador titular sí crea. |
| `test/test_contract_closure.sql` | Exclusiones READ_QUERY_RESULTSET de las 3 consultas nuevas. |

## Reglas aplicadas (skills del repo)

- `procedimientos-externos-condiciones`: DECLARE en la cabecera, `-- PASO n`, `IF` con `BEGIN/END`, READ_QUERY_RESULTSET con `THROW`, salida canónica en el comando de HU153, `ISNULL` solo sobre agregaciones.
- `procedimientos-internos-condiciones`: internos con triplete OUTPUT, correlación en el mensaje técnico y `SYS_001` en el CATCH; transacción propia o savepoint sin `XACT_ABORT` en el interno de escritura.
- `consulta-a-bd`: lecturas por vistas (`uv_auth_grupo`, `uv_resumen_asistencia_estudiante_grupo`, `uv_auditoria_evento`, `uv_componente`, `uv_tipo_identificacion`, `uv_area`).
- `modelo-jerarquico-rbac`: `usp_validar_permiso_rbac_usuario_interno` con la lista exacta de perfiles.
- Sin DDL de tablas; nada congelado (oferta, matrícula, asignatura y `AuditoriaEvento` fuera de los manifiestos).

## Decisiones resueltas

- Créditos ≤ 0, semestre inexistente en el plan y dueño del programa: resueltos arriba (John, 2026-11-04).

## Rollback

Revertir los commits del work item: los SP y la vista nuevos se eliminan con `DROP`, `uv_componente` vuelve a dos columnas y los permisos con `REVOKE`. Sin cambios de tablas ni datos.
