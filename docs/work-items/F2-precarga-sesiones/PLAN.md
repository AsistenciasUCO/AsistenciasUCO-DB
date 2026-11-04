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

## Continuación SES-02 (2026-11-04)

Se conserva el contrato F2 y no se cambia la firma pública ni la del procedimiento interno. Se amplía la cobertura del mismo flujo y se corrige el caso límite en el que el período terminó antes de la fecha civil de hoy: la CTE de fechas queda vacía cuando su fecha inicial supera el fin del período. `usp_generar_sesiones_grupo` continúa congelado y sin cambios.

El calendario sigue siendo semanal por días y franjas definidos en `Horario`, con conversión desde hora civil institucional a UTC. No hay una fuente contractual de feriados, recesos o suspensiones académicas en este flujo; su exclusión requiere una regla institucional antes de ampliar el generador.

El Backend ya incluye la llamada al precargador en el flujo de alta/edición de grupo en `origin/develop`; no se requiere un cambio adicional en Backend para esta continuación. La interfaz consulta las sesiones existentes y no calcula la cantidad de semanas ni fabrica sesiones.

**Qué NO cambia:** los objetos congelados y las tablas. Las sesiones generadas son del mismo tipo y marca que las del generador existente.

## Matriz de pruebas (`test/test_usp_precargar_sesiones_grupo.sql`)

Período futuro fijo (2098) para ser determinista, y un período pasado.

| ID | Escenario | Esperado |
|---|---|---|
| `PRELOAD_CREATES` | Coordinador precarga un grupo con lunes y miércoles 08-10 | Una sesión por cada lunes y miércoles, `UTC_GENERADOR`, correlativo 1..N y horas convertidas a UTC |
| `PRELOAD_IDEMPOTENT` | Repetir la precarga | Sin duplicados |
| `PRELOAD_PRESERVES_ATTENDANCE` | Cambia el horario y una sesión generada ya tiene asistencia | Se conserva la sesión y su detalle de asistencia |
| `PRELOAD_PRESERVES_CLASSIFICATION` | Cambia el horario y existe una clasificación `UTC_OWNER` | Se conserva la sesión clasificada |
| `PRELOAD_PRESERVES_HISTORY` | Cambia el horario y existe una sesión histórica generada | No se altera la sesión histórica |
| `PRELOAD_REGENERATE` | El horario pasa a solo lunes; hay evidencia protegida y una sesión creada a mano | Se retiran los slots futuros elegibles del horario anterior; evidencia y sesión manual se conservan |
| `PRELOAD_NO_PAST` | Período terminado ayer; horario coincide con hoy en una franja futura | No se genera una sesión de hoy fuera del período |
| `PRELOAD_SCOPE` | Docente titular y docente ajeno | El titular puede; el ajeno recibe `SEC_002` sin cambios |
| `PRELOAD_CROSS_PROGRAM_DENIED` | Coordinador de otro programa | `SEC_002`; no crea sesiones |
| `PRELOAD_NO_PRIVILEGE_DENIED` | Estudiante intenta precargar | `SEC_001`; no cambia sesiones |
| `PRELOAD_REQUIRES_SCHEDULE` | Grupo sin horario | Rechazo, sin sesiones |
| `PRELOAD_VARIABLE_*` | Períodos de 8, 12, 16 y 18 semanas con uno o dos días por semana | Cantidad, correlativos, códigos, límites civiles y unicidad correctos |
| `PRELOAD_CONCURRENT_IDEMPOTENT` | Dos conexiones precargan el mismo grupo y luego se reintenta | Una sesión por slot, sin duplicados ni huecos en correlativos |
| `PRELOAD_RUNTIME_LEAST_PRIVILEGE` | Metadatos del rol de ejecución | `EXECUTE` público, `DENY EXECUTE` interno y sin DML directo en `Sesion` |

## Integración existente en Backend y Frontend

- **Backend:** en `origin/develop`, `POST` y `PUT /api/v1/grupos` invocan la precarga, en la misma transacción, cuando el grupo queda con franjas. La bandera heredada `generarSesionesAutomaticas` conserva su respuesta 501 según el contrato F2.
- **Frontend:** en `origin/develop`, las vistas consumen las sesiones devueltas por la API; no generan un número fijo de sesiones.
- Esta continuación no requiere cambios de código ni ramas adicionales en Backend o Frontend.

## Validación

Ver `VALIDATION.md`.
