---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-01
---

# PLAN — F3: el docente crea sus propios grupos

## Decisión

John (2026-11-01): el docente debe poder crear sus grupos, para que esa carga no recaiga toda en el coordinador. Alcance acordado:
- el docente **crea** grupos a su propio nombre y define su **horario inicial**;
- los cambios posteriores del docente irán por la aprobación del coordinador (F6); el coordinador edita directo.

## Riesgo evaluado

La BD ya impide traslapes: el cruce del docente (`HOR_002`) y el de franjas del mismo grupo (`HOR_003`) se validan al guardar el horario, lo haga quien lo haga. El control que se pierde es de gobierno de la oferta (qué grupos abre cada docente); lo acota el vínculo activo del docente con el programa de la asignatura (PASO 2B de `usp_crear_grupo`).

## Cambios en la BD

1. **`usp_crear_grupo`** (de Sergio; no está en el manifiesto congelado): acepta los perfiles `COORDINADOR,DOCENTE`.
   - Ejecutor coordinador: sin cambios (crea y asigna cualquier docente).
   - Ejecutor docente: `@idDocente` debe ser el propio docente y la asignatura debe ser de un programa con el que tiene vínculo activo (`SEC_002` en otro caso, sin crear nada).
2. **`usp_guardar_horarios_grupo`**: acepta `COORDINADOR,DOCENTE`.
   - Coordinador: sin cambios (titular del programa del grupo).
   - Docente: solo el titular del grupo (`SEC_002` si no lo es) y solo si el grupo no tiene horario aún (`HOR_005`).
3. **Mensaje nuevo `HOR_005`** (usuario y técnico) en `schema/seed/04_mensaje.sql`; `docs/catalogos/catalogo-mensajes.md` se regeneró (144 códigos).
4. **`usp_consultar_oferta_creacion_grupo_docente`** (nuevo, de solo lectura): devuelve el `idDocente` y las asignaturas activas de los programas con vínculo activo del docente, para el formulario del frontend. `GRANT EXECUTE` en `schema/security/rol_asistencias_runtime_f3_docente_crea_grupo.sql`.
5. Sin cambios de tablas ni vistas.

## Pruebas

`test/test_usp_guardar_horarios_grupo.sql` se amplía:
- `GROUP_SCHEDULE_SCOPE`: el docente titular con horario ya definido recibe `HOR_005`; un docente que no es titular recibe `SEC_002`.
- `TEACHER_CREATES_GROUP` (nueva): el docente no puede crear un grupo para otro docente (`SEC_002`, sin crearlo); sí lo crea a su nombre, define el horario inicial y un segundo guardado recibe `HOR_005` sin cambios.
- `TEACHER_CREATES_GROUP` también cubre al docente sin vínculo con el programa (`SEC_002`, sin crear el grupo).
- `test/test_usp_consultar_oferta_creacion_grupo_docente.sql` (nueva): `TEACHER_OFFER_LINKED`, `TEACHER_OFFER_NO_LINK` y `TEACHER_OFFER_REJECTS_OTHER_PROFILES`.
- `test_summary.ps1` exige los cuatro IDs nuevos.

## Backend y frontend (ramas aparte)

- **Backend:** `POST /api/v1/grupos` se abre al DOCENTE solo para crear (`SecurityConfig`, `access-catalog.json`, PDP); `PUT` y `DELETE` siguen para COORDINADOR y ADMINISTRADOR; endpoint nuevo `GET /api/v1/docente/oferta-creacion-grupos` (lee `usp_consultar_oferta_creacion_grupo_docente`).
- **Frontend:** vuelve el formulario "Nuevo grupo" del docente, con el contrato real y las franjas.

## Validación

Ver `VALIDATION.md`.
