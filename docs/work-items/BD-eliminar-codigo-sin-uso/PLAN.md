---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-29
---

# PLAN — Eliminar código sin uso de la BD

## Decisión

John (2026-10-29): **eliminar 18 objetos** que la aplicación no usa. Salen del análisis de código sin uso (informe `informes/CODIGO_SIN_USO_BD_2026-10-29.md`, fuera del repo). Ese análisis también los cruzó con las HU pendientes y con las observaciones nuevas de asistencia y sesiones.

**Se conservan a propósito:**
- `usp_validar_cruce_horario_docente_interno` y `usp_validar_grupo_exista_para_docente_interno`. La regla de John es que un docente no puede quedar con dos grupos a la misma hora; su integración en el flujo va en un work item aparte.
- `usp_registrar_estudiante_en_programa_interno` (HU171).
- `ufn_obtener_estado_estudiante_grupo` (posible uso en el límite de faltas).

## Evidencia de que no tienen uso

- **Grafo de alcanzabilidad:** las raíces son los objetos que nombra el backend `develop` (`src/main`); se siguieron las dependencias entre objetos. Ninguno de los 18 es alcanzable.
- **Backend y frontend:** ninguno aparece en `src/` del backend ni del frontend. En el backend solo aparecen en documentos históricos de work items.
- **Permisos:** ninguno tiene `GRANT` en `schema/security`.
- **Congelamiento:** ninguno está en `DB_DEVELOP_FREEZE_MANIFEST.sha256` ni en `DB_UTC_D06_POST_FREEZE_MANIFEST.sha256`. `DB_DEVELOP_FREEZE_ADDENDUM.md` nombra `ufn_obtener_perfil_usuario_contexto` en su inventario histórico. No se modifica porque es un registro del congelamiento.

## Objetos eliminados (18)

| Objeto | Tipo | Motivo |
|---|---|---|
| `usp_consultar_asignaturas_paginado` | SP público | Legacy; no filtra por ámbito (`uv_auth_*`) |
| `usp_consultar_asistencias_estudiante_paginado` | SP público | Legacy; el historial del estudiante se lee por vistas JPA |
| `usp_consultar_docente_por_id` | SP público | Legacy; sin ámbito. Vigente: `usp_consultar_docentes_programa` |
| `usp_consultar_docentes_paginado` | SP público | Igual |
| `usp_consultar_estudiante_por_id` | SP público | Legacy; sin ámbito. Vigente: `usp_consultar_estudiante_facultad_detalle` |
| `usp_consultar_estudiantes_paginado` | SP público | Legacy; sin ámbito. Vigente: `usp_consultar_estudiantes_facultad_paginado` |
| `usp_consultar_estudiantes_grupo_paginado` | SP público | Legacy; el listado del grupo se lee por vistas JPA |
| `usp_consultar_facultades_paginado` | SP público | Legacy. Vigente: `usp_consultar_estructura_facultad` |
| `usp_consultar_programas_paginado` | SP público | Legacy. Vigente: `usp_consultar_programas_academicos` |
| `usp_consultar_solicitudes_revision_asistencia_paginado` | SP público | Legacy. Vigentes: `usp_consultar_solicitudes_revision_estudiante` y `_docente` |
| `usp_resolver_solicitud_matricula` | SP público | Stub que siempre fallaba; no existe la tabla `SolicitudMatricula`. Vigente: `usp_resolver_solicitud_ingreso_grupo` (HU053-HU055) |
| `usp_registrar_asistencia_estudiante` | SP público | La asistencia va por `usp_registrar_asistencias_sesion` (Golden Path) |
| `usp_validar_estudiante_grupo_exista_interno` | SP interno | Solo lo llamaba el anterior |
| `usp_registrar_docente_en_grupo` | SP público | El docente se asigna en `usp_crear_grupo` y `usp_actualizar_grupo` |
| `usp_registrar_docente_en_grupo_interno` | SP interno | Solo lo llamaba el anterior |
| `ufn_validar_password` | Función | Las contraseñas las gestiona Keycloak. Además aceptaba la cédula como contraseña válida |
| `ufn_obtener_perfil_usuario_contexto` | Función | Reemplazada por `ufn_obtener_usuario_ejecutor_contexto`. Además usaba `TOP 1` sin orden |
| `fn_diagramobjects` | Función | La genera SSMS para los diagramas; no es de la aplicación |

**Inventario resultante:**
- 147 SP: 89 públicos (antes 102) y 58 internos (antes 60);
- 65 vistas, sin cambio;
- 14 funciones (antes 17).

## Cambios

1. **`schema/`:** se borran los 18 archivos.
2. **Migración:**
   - `migrations/08_eliminar_codigo_sin_uso_up.sql` hace `DROP … IF EXISTS` de los 18. Es idempotente y hace falta porque `deploy_schema.ps1` no borra objetos.
   - `_down.sql` restaura las definiciones de `develop` (`b27c865`).
3. **Pruebas:**
   - Se eliminan las suites que solo cubrían estos objetos:
     - `test_usp_consultar_docentes_paginado`;
     - `test_usp_consultar_estudiantes_paginado`;
     - `test_usp_consultar_estudiantes_grupo_paginado`;
     - `test_usp_consultar_catalogos_y_revisiones_paginado`;
     - `test_usp_registrar_docente_en_grupo_usuario_no_existente`;
     - `test_usp_resolver_solicitud_matricula`.

     También se quitan de `test_suite.sql`.
   - En suites compartidas se quitan solo los bloques de estos objetos:
     - en `test_transaction_ownership`, `OWNERSHIP_TEACHER`;
     - en `test_attendance_commands`, `ATTENDANCE_SINGLE_SUCCESS` y `ATTENDANCE_SINGLE_INVALID`.
   - En `test_contract_closure` se quitan de las listas de exclusión los 10 SP legacy eliminados.
   - En `test_summary.ps1` salen de los IDs requeridos `TEACHER_SUCCESS`, `TEACHER_GROUP_NOT_FOUND`, `OWNERSHIP_TEACHER`, `ATTENDANCE_SINGLE_*` y `MATRICULA_NOT_IMPLEMENTED`.
4. **Documentación:**
   - `transaccion-procedimiento.md`: inventario, lista de funciones y fichas marcadas como ELIMINADO.
   - `especificacion_sp_endpoints.md`: filas de la tabla, transacciones 3.3 y 3.4, sección legacy y conteos.
   - Fichas de `DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS/INTERNOS/ORQUESTADORES.md`.
   - Skills `cobertura-pruebas-objetos-bd` y `modelo-jerarquico-rbac`: ejemplos que nombraban objetos eliminados.

   Los work items y reportes históricos no se modifican.
5. **Infra (solo documentación, rama `docs/BD-eliminar-codigo-sin-uso`):**
   - `HU-CATALOG.md`: HU027 y HU033 pasan a `usp_registrar_asistencias_sesion`;
   - `mapa-relacion-archivos.md`: diagrama.

## Fuera de alcance (se deja igual)

- **Mensaje `ERR_INESPERADO_REGISTRO_ASISTENCIA`:** su texto nombra `usp_registrar_asistencia_estudiante` y ningún SP lo usa. Quitarlo cambia el seed del catálogo, así que se deja para una limpieza de mensajes.
- **Usos que requieren coordinación con José Alejandro:**
  - `usp_radicar_solicitud_revision_asistencia` (v1): tiene permiso en un archivo congelado;
  - `uv_usuario_autenticacion`.
- **Objetos que se mantienen:** las vistas `uv_auth_*` sin lector, `usp_registrar_estudiante_en_grupo_autonomo` (HU176B) y la clasificación UTC-D06.

## Validación

Ver `VALIDATION.md`.

> **Retirado en CULM-001 A (2026-11-07):** las solicitudes de ingreso (HU053-HU055) se descartaron; la reactivacion de la matricula retirada vive en `usp_internal_reactivar_matricula_retirada` (DEC-009). Ver `docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`, addendum CULM-001 A.
