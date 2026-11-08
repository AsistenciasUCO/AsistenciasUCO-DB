# DB Develop Freeze Addendum (DB-GP-001C)

Complementa, **sin reemplazar**, `docs/contracts/DB_BASELINE_CONTRACT.md`.

```text
FINAL_DEVELOP_COMMIT: dcc69f19ffe3c246b78fa1996299ad97df229bbf
  (ultimo commit que cambia esquema/tests/gates; los commits posteriores son solo documentacion)
BASE_COMMIT_BEFORE_HARDENING: c30ecc56a070ae9c9de01e02b2f3f43f6a474abd
BASELINE_CONTRACT_SHA: 45e48c5a0ab321d0c8cbffb55ee224e3b6fd29febc39a62ca723b2b209945aec
BASELINE_CONTRACT: UNCHANGED
GOLDEN_PATH: FROZEN

NON_GOLDEN_PATH_EXTENSIONS:
  - uv_auth_*  (12 vistas)
  - ufn_obtener_usuario_ejecutor_contexto
  - ufn_obtener_perfil_usuario_contexto
  - usp_establecer_contexto_usuario_ejecutor
  - usp_consultar_grupos_paginado

AUTH_VIEW_POLICY: FAIL_CLOSED
NULL_CONTEXT: NO_ROWS
UNKNOWN_CONTEXT: NO_ROWS
SESSION_CONTEXT_RESTORE: REQUIRED
PAGINATION: NOT_CONSUMED_BY_GOLDEN_PATH_BACKEND
JPA_PILOT: USES FROZEN BASE VIEWS, NOT uv_auth_*
DB_PRINCIPAL_HARDENING: FUTURE_DECISION
DB SCHEMA CHANGE AFTER FREEZE: REQUIRES NEW WORK ITEM / CONTRACT DECISION
```

## Semantica congelada

- `uv_*` = interna/base (datos completos, mantenimiento). `uv_auth_*` = externa autorizada, **fail closed**.
- `SESSION_CONTEXT` es estado de la conexion fisica: debe restaurarse; el backend/JPA futuro debe disenar su ciclo de vida
  por conexion antes de usar `uv_auth_*`. Ver `docs/arquitectura/DB_SESSION_CONTEXT_Y_VISTAS_AUTORIZADAS.md`.
- `usp_consultar_grupos_paginado`: `NON_GOLDEN_PATH_EXTENSION`, `NOT_BACKEND_CONSUMED`, `NOT_PART_OF_LB002_JPA_PILOT`,
  resultset `READ_QUERY_RESULTSET` (no `MUTATION_COMMAND_RESULTSET`).
- El backend puede depender solo del contrato aprobado; una extension requiere un work item de alineacion que la adopte.

## Manifest

`docs/contracts/DB_DEVELOP_FREEZE_MANIFEST.sha256` registra SHA-256 (CRLF normalizado a LF, igual al blob de Git) del contrato
y de las fuentes Golden Path (5 vistas + 4 SP de sesion/asistencia). Se genera y verifica con:

```powershell
./scripts/freeze-manifest.ps1 -Mode Generate   # solo tras una decision autorizada de contrato/freeze
./scripts/freeze-manifest.ps1 -Mode Verify     # ejecutado por test_summary.ps1 (GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED)
```

Equivalente manual por archivo: `git show <commit>:<ruta> | sha256sum`.

## Revision post-freeze LB-002.1C-A (2026-09-27)

Registro de un avance del tip posterior al freeze. **No reescribe** los valores de arriba (`FINAL_DEVELOP_COMMIT` sigue siendo el ultimo commit de la fase DB-GP-001C).
Detalle y evidencia: `docs/work-items/LB-002.1C-A-db-contract-baseline-recovery/REPORT.md`.

```text
PREVIOUS FROZEN TIP:   9b2b993 (docs)  /  dcc69f19ffe3c246b78fa1996299ad97df229bbf (FINAL_DEVELOP_COMMIT)
BASE SHA:              6c120ca5b3eea191924163472b1f3a16edc6e2ff
LB-002.1C-A IMPLEMENTATION/CLOSURE COMMIT: 0798b994cc074a4315916a0b45e662d1708c6ab2
PUSHED:                YES
REVIEWED REMOTE STATE AT CLOSURE: HEAD == origin/sergio
DB-GP-001C ORIGINAL FREEZE:       UNCHANGED   (FINAL_DEVELOP_COMMIT historico no se reescribe)
POST-FREEZE REVIEWED TIP:         ADVANCED BY LB-002.1C-A
REASON FOR ADVANCE:    6c120ca desacopla "grupo valido" de "cupo para matricular" (sesiones programables en grupos llenos);
                       LB-002.1C-A corrige su regresion (cupo validado antes de escribir en usp_registrar_estudiante_en_grupo)
GOLDEN PATH CONTRACT CHANGED:          NO   (DB_BASELINE_CONTRACT.md sha 45e48c5a... y manifest de 10 archivos intactos)
FREEZE CONTRACT UNCHANGED:             YES  (DB_BASELINE_CONTRACT.md y manifest sin modificar; el tip revisado avanzo por correccion NON-GOLDEN/interna)
GOLDEN PATH SOURCE CHANGED:            NO
PUBLIC STUDENT-GROUP WIRE/ABI CHANGED IN 1C-A:   NO   (firma, resultset, DBCODEs, RBAC y tablas identicos a 9b2b993)
PUBLIC STUDENT-GROUP BEHAVIOR CORRECTED IN 1C-A: YES  (rechazo por cupo antes de persistir identidad;
                                                       evita estado parcial Usuario/Estudiante)
TRANSACTION OWNERSHIP OF PUBLIC STUDENT ENROLLMENT: NOT CERTIFIED
                                       (OWNERSHIP_STUDENT usa un grupo inexistente: no prueba rollback tras una escritura intermedia;
                                        requiere decision/work item de contrato aparte)
TD-043:                                OPEN   (GLOBAL -Pintegration = NOT_GREEN_TD043)
TABLES CHANGED:                        NO
GOLDEN PATH EFFECTIVE BEHAVIOR:        usp_crear_sesion y usp_generar_sesiones_grupo llaman usp_validar_grupo_exista_por_id_interno;
                                       desde 6c120ca un grupo lleno pero habilitado ya no bloquea (fuente y firma de los SP congelados sin cambio)
GATE ACTUAL:                           TOTAL_EXPECTED=154 (151 + 3 de test_group_capacity_decoupling.sql); las cifras 127/128 del contrato son historicas v1
STUDENT-GROUP CANONICAL COMMAND:       dbo.usp_registrar_estudiante_en_grupo (el legacy ..._usuario_no_existente fue eliminado en daeac11)
CURRENT PUBLIC CONTRACT IS NOT EQUIVALENT TO THE CONTRACT THE HISTORICAL BACKEND EXPECTED: STATUS = DECISION_REQUIRED
CONTRACT DECISION REQUIRED:            YES
DB CONTRACT CHANGE REQUIRED:           TO_BE_DETERMINED_AFTER_BACKEND_AS_IS
DB / BACKEND PRODUCTION CHANGE AUTHORIZED: NO / NO
NEXT AUTHORIZED PHASE:                 LB-002.1C-B1 - BACKEND AS-IS CONTRACT ANALYSIS (registrarEstudianteEnGrupo); no implica cambiar la DB
```

## Revisión post-freeze REC3 (2026-10-29)

- **Objeto:** `schema/stored-procedures/usp_generar_sesiones_grupo.sql`, congelado en DB-GP-001C y ya reemplazado por UTC-D06.
- **Aprobación:** explícita de John Duque (2026-10-29), para este único SP congelado. Los otros congelados que la auditoría señaló (`usp_registrar_asistencias_sesion`, `usp_clasificar_procedencia_sesion` y `usp_crear_sesion_interno`) **no se modifican**.
- **Cambio:**
  - `SET XACT_ABORT ON`;
  - el CATCH pasa de `IF @@TRANCOUNT > 0 ROLLBACK` a `IF XACT_STATE() <> 0 ROLLBACK`.
  - No cambian la firma, el resultset ni las reglas.
- **Manifiesto:** `DB_UTC_D06_POST_FREEZE_MANIFEST.sha256` actualiza solo el hash de ese archivo, de `099a5cf4…` a `ef9de7e9…`. La cadena de reemplazo sigue apuntando al hash DB-GP-001C (`f4c71c7b…`).
- **Prueba:** `test_rec3_falla_intermedia_transaccion.sql`, caso TX-04.
- **Work item:** `docs/work-items/REC3-transacciones/PLAN.md`.

## Revisión post-freeze SES-01 (2026-11-03) — EXCEPCIÓN AUTORIZADA

- **Objeto:** `schema/stored-procedures/usp_registrar_asistencias_sesion.sql` (DB-GP-001C, Golden Path). La revisión REC3 dejó constancia de que este SP **no** se modificaba; SES-01 lo propone de nuevo por una decisión funcional posterior (2026-11-02: cierre estricto a la hora de fin).
- **Aprobación:** excepción de congelamiento **autorizada expresamente por el responsable funcional del proyecto** (instrucción del 2026-11-03, «Finalización integral de SES-01 a SES-05»). La autorización cubre desarrollar, probar y proponer el cambio; la **revisión formal del owner DB (John Duque)** se solicita en el PR y es requisito para fusionar y para aplicarlo en bases compartidas, que se hace solo con el mecanismo oficial de despliegue.
- **Cambio:**
  - PASO 4.0: dentro de la transacción (propia o savepoint) llama a `usp_validar_sesion_ventana_registro_interno` antes de escribir;
  - PASO 4.2: repite la validación antes del `COMMIT`;
  - fuera de ventana devuelve `SES_007` / `SES_008` / `SES_009` y no escribe.
  - No cambian la firma, el resultset, la prioridad de las validaciones previas ni el patrón savepoint/`XACT_STATE()` (sin `XACT_ABORT ON`, ver REC3).
- **Manifiesto:** `DB_UTC_D06_POST_FREEZE_MANIFEST.sha256` agrega la supersesión de ese archivo, de `a0372fd6…` (DB-GP-001C) a `7217604b…`; `scripts/freeze-manifest.ps1` lo incluye en `$postFreezeSuperseded`.
- **Prueba:** `test/test_ses01_ventana_asistencia.sql` (12 IDs `SES01_*`).
- **Work item:** `docs/work-items/SES-01-cierre-estricto-asistencia/PLAN.md`.

## CULM-001 D.4 — admisión de estudiantes por el administrador (HU156) (2026-11-07)

- **Objetos nuevos:** `usp_admitir_estudiante`, `usp_consultar_programas_institucion_paginado`, mensajes `ADS_001`..`ADS_006`, parámetros `IDENTIDAD/PERFILES_CORRECCION_ESTUDIANTE` y `_DECANO`, permisos `rol_asistencias_runtime_culm001_d4.sql` y la migración `23_culm001_d4_admision_estudiantes`. Ningún archivo congelado cambia; las fuentes nuevas se registran como `WORK_ITEM` en `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256`.
- **Cambio de comportamiento:** `usp_corregir_identidad_usuario` lee los perfiles permitidos de los parámetros; el `ADMINISTRADOR` ahora corrige estudiantes con `EstudiantePrograma` en un programa de su institución (antes solo el `COORDINADOR` del programa). Coordinador y decano conservan su regla.
- **Desviación del contrato:** el vínculo con el programa se inserta en `usp_admitir_estudiante` y no con `usp_registrar_estudiante_en_programa_interno` (resuelve la institución desde `uv_estudiante`, que exige un programa previo); `Programa` no tiene columna `codigo`, por eso la consulta de programas no la devuelve.
- **Pruebas:** `test/test_culm001_d4_admision.sql` (D4-01..D4-11) y `test/test_culm001_d4.ps1` (D4-12 up→down→up).
## CULM-001 D.1 — plazo de excusas (HU026B) (2026-11-07)

- **Objetos nuevos:** `ufn_calcular_fecha_limite_justificacion`, `usp_internal_validar_plazo_justificacion`, `uv_sesion_estudiante_reclamo`, `usp_consultar_sesiones_materia_estudiante` y la migración `20_culm001_d1_plazo_justificacion`. Ningún archivo congelado cambia (`uv_sesion` no se toca, DEC-044 (2)); las fuentes nuevas se registran como `WORK_ITEM` en `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256`.
- **Radicación:** `usp_radicar_solicitud_revision_asistencia` (v1) y `_v2` rechazan con `REV_020` cuando `SYSUTCDATETIME() >= límite` y con `REV_025` cuando faltan `ASISTENCIA/DIAS_LIMITE_JUSTIFICACION` o `TIEMPO/ZONA_HORARIA_SQLSERVER`. El límite es la medianoche local del día `fecha local de fin + N + 1`. En la v2 el plazo se valida **después** de la reejecución idempotente por correlación (un reintento legítimo tras el vencimiento sigue devolviendo el éxito original) y antes de cualquier escritura.
- **Fecha de radicación (F-EST-S16):** `SolicitudRevisionAsistencia.fecha` pasa de `CAST(CURRENT_TIMESTAMP AS DATE)` (fecha del servidor, UTC) a la **fecha local** (`TIEMPO/ZONA_HORARIA_SQLSERVER`). Las filas anteriores conservan su fecha (sin migración de datos).
- **Cambio de comportamiento de lectura (DEC-022 §3):** la lista de sesiones de la materia del estudiante solo devuelve grupos con la matrícula `MATRICULA/ESTADO_INSCRITA`; con `I`, `CI`, `CVP` o `F` devuelve 0 filas.
- **LB-004D:** cambian `usp_radicar_solicitud_revision_asistencia_v2.sql`, `test_lb004d_support_binding.sql` (la fixture usa «ayer» en lugar de una fecha fija ya vencida) y `test_lb004d_concurrency.ps1` (crea y elimina una sesión reciente propia); sus líneas del manifiesto se regeneran en el mismo commit (DEC-044 (11)).
- **Pruebas:** `test/test_culm001_d1_plazo_justificacion.sql` (D1-01…D1-10, D1-12), `test/test_culm001_d1.ps1` (D1-11 up→down→up y D-RB-01).
