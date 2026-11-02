---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-02
---

# PLAN — F2: precarga de las sesiones del grupo

## Decisión

John (2026-11-02): la precarga se hace con un **SP nuevo, sin tocar el congelado** `usp_generar_sesiones_grupo`, y genera **solo desde hoy**. Parte del plan de sesiones y faltas (`informes/PLAN_SESIONES_FALTAS_2026-10-30.md`, fuera del repo): las sesiones se crean al definir el horario y, si el horario cambia, solo se regeneran las futuras.

## Por qué no el SP congelado

- Solo lo ejecuta el docente titular: el coordinador no podría precargar.
- Genera desde el primer día del período: un grupo creado a mitad de período se llenaría de sesiones **pasadas** sin asistencia, y eso contaminaría los avisos de "docente no marcó" y el conteo de faltas.
- No retira las sesiones que dejó un horario anterior.
- Cambiarlo exige aprobación de John y José Alejandro (Golden Path y UTC-D06).

## Cambios en la BD

1. **`usp_precargar_sesiones_grupo`** (público): COORDINADOR del programa o DOCENTE titular (`SEC_002` en otro caso). Exige horario y fechas coherentes del período; controla la transacción (propia o savepoint, sin `XACT_ABORT ON`).
2. **`usp_precargar_sesiones_grupo_interno`** (núcleo de escritura): crea las sesiones que faltan desde hoy (hora institucional) o desde el inicio del período hasta el fin del período, sin duplicar, con marca `UTC_GENERADOR`; elimina las futuras `UTC_GENERADOR` que ya no encajan y no tienen asistencia ni clasificación. Nunca toca el pasado ni las sesiones creadas a mano (`UTC_V2`).
3. **Permiso:** `schema/security/rol_asistencias_runtime_f2_precarga_sesiones.sql` da `EXECUTE` sobre el público y `DENY EXECUTE` sobre el interno.
4. Sin cambios de tablas, vistas ni mensajes (usa `GEN_001`, `GEN_005`, `SES_005`, `SEC_002`, `VAL_002`).

**Qué NO cambia:** los objetos congelados y las tablas. Las sesiones generadas son del mismo tipo y marca que las del generador existente.

## Matriz de pruebas (`test/test_usp_precargar_sesiones_grupo.sql`)

Período futuro fijo (2098) para ser determinista, y un período pasado.

| ID | Escenario | Esperado |
|---|---|---|
| `PRELOAD_CREATES` | Coordinador precarga un grupo con lunes y miércoles 08-10 | Una sesión por cada lunes y miércoles, `UTC_GENERADOR`, correlativo 1..N y horas convertidas a UTC |
| `PRELOAD_IDEMPOTENT` | Repetir la precarga | Sin duplicados |
| `PRELOAD_REGENERATE` | El horario pasa a solo lunes; hay una sesión creada a mano | Se retiran los miércoles generados; la sesión manual se conserva |
| `PRELOAD_SCOPE` | Docente titular y docente ajeno | El titular puede; el ajeno recibe `SEC_002` sin cambios |
| `PRELOAD_REQUIRES_SCHEDULE` | Grupo sin horario | Rechazo, sin sesiones |
| `PRELOAD_NO_PAST` | Grupo de un período ya vencido | No genera sesiones del pasado |

## Backend y frontend (misma rama `feature/F2-precarga-sesiones`)

- **Backend:** `POST` y `PUT /api/v1/grupos` invocan la precarga, en la misma transacción, cuando el grupo queda con franjas; hoy `generarSesionesAutomaticas` responde 501.
- **Frontend:** sin pantalla nueva; se muestran las sesiones creadas.

## Validación

Ver `VALIDATION.md`.
