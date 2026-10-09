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

## Revision post-freeze LB-008 JPA-05 (2026-10-05)

Registro de una correccion semantica NON-GOLDEN posterior al freeze. **No reescribe** las secciones anteriores.
Detalle y evidencia: `docs/work-items/LB-008-JPA05-db-view-identity-alignment/`.

```text
WORK_ITEM:                  LB-008 JPA-05 DB view identity alignment
OBJECT_CHANGED:             dbo.uv_estudiante_programa
TABLES_CHANGED:             NO
SP_CHANGED:                 NO
GOLDEN_PATH_CONTRACT_CHANGED: NO   (DB_BASELINE_CONTRACT.md y su .sha256 sin modificar)
GOLDEN_PATH_MANIFEST_CHANGED: NO   (DB_DEVELOP_FREEZE_MANIFEST.sha256 sin modificar; uv_estudiante_programa no figura en el)
PUBLIC_VIEW_NAME_CHANGED:   NO
PUBLIC_VIEW_SHAPE_CHANGED:  NO     (5 columnas: id, idEstudiante, nombreEstudiante, idPrograma, nombrePrograma)
SEMANTIC_CORRECTION:        YES
BEFORE:                     cardinalidad multiplicada por uv_estudiante (estudiante x grupo x asignatura x programa)
AFTER:                      una fila por EstudiantePrograma.id via uv_estudiante_identidad
BACKEND_REASON:             identidad estable para mapeo JPA @Entity @Immutable
GOLDEN_PATH:                UNAFFECTED
DB_TEST_GATE:               DB GATE PASS (TOTAL_EXPECTED=158, FAILED=0, CRITICAL_MISSING=0, UNAUTHORIZED_SKIPS=0, @@TRANCOUNT=0)
NEW_TEST:                   test/test_uv_estudiante_programa_identity.sql
```

## Revision post-freeze: alineacion de providers publicos DB (2026-10-07)

Correccion de contratos publicos posterior al freeze. **No reescribe** las secciones anteriores ni el baseline congelado.
Detalle y evidencia: `docs/work-items/DB-PUBLIC-PROVIDER-ALIGNMENT/REPORT.md`.

```text
WORK_ITEM:                       DB-PUBLIC-PROVIDER-ALIGNMENT
OBJECTS_CHANGED:                 dbo.usp_registrar_estudiante_en_grupo (contrato), dbo.usp_registrar_asistencia_estudiante_autonomo (nombre), dbo.usp_ejecutar_cierre_masivo_periodo (nombre)
TABLES_CHANGED:                  NO
GOLDEN_PATH_CONTRACT_CHANGED:    NO   (DB_BASELINE_CONTRACT.md y su .sha256 sin modificar)
GOLDEN_PATH_MANIFEST_CHANGED:    NO   (DB_DEVELOP_FREEZE_MANIFEST.sha256 sin modificar; ningun objeto listado en el manifiesto cambio)
PUBLIC_NAMES_CHANGED:            NO   (se restauran los nombres publicos; no se crean alias)
CANONICAL_RESULT_CHANGED:        NO   (1 fila, 4 columnas)
SEMANTIC_CORRECTION:             YES
  - matricula: rol ADMINISTRADOR eliminado; titularidad en OR (DOCENTE titular del GRUPO / COORDINADOR del PROGRAMA); @idUsuarioEjecutor y @idTipoIdIdentificacion obligatorios, sin default
  - matricula: identidad solo se reutiliza si correo y documento apuntan al mismo usuario; conflicto IDN_001
  - matricula y asistencia autonoma: propagacion de transaccion condenada al propietario
  - cierre masivo: sin fallback al periodo mas reciente (PER_001)
  - catalogo: PRG_001 eliminado (duplica PROG_001); IDN_001, CAT_001 y PER_001 incorporados
  - Estado: P (Pendiente), A (Aprobada) y R (Rechazada) sembrados en schema/seed/06_estado.sql
PLAN_ESTUDIO_PROVIDER:           DEFERRED_TO_BACKEND_ALIGNMENT_PHASE
DB_TEST_GATE:                    PASS (desde cero: TOTAL_EXPECTED=188, EXECUTED=190, PASSED=190, FAILED=0, SKIPPED=0, SQL_ERROR_COUNT=0)
BACKEND_IMPACT:                  SI (matricula requiere @idUsuarioEjecutor y @idTipoIdIdentificacion; ADMINISTRADOR ya no autorizado)
```

## Cierre de pendientes: provider de Plan de Estudio y pulido de estandar SQL (2026-10-07)

Completa el `PLAN_ESTUDIO_PROVIDER` dejado `DEFERRED_TO_BACKEND_ALIGNMENT_PHASE` arriba. **No reescribe** las secciones anteriores; no se modifico la logica ya validada de matricula, revisiones, asistencia autonoma, cierre masivo ni sincronizacion de usuario.

```text
WORK_ITEM:                       DB-PUBLIC-PROVIDER-ALIGNMENT (cierre)
OBJECTS_CHANGED:                 dbo.usp_registrar_o_actualizar_plan_estudio (nuevo), dbo.usp_sincronizar_usuario (nuevo)
TABLES_CHANGED:                  NO  (dbo.PlanEstudio ya existia: id, programa, inp, estado; sin columnas codigo/nombre)
GOLDEN_PATH_CONTRACT_CHANGED:    NO
GOLDEN_PATH_MANIFEST_CHANGED:    NO
PLAN_ESTUDIO_PROVIDER_CONTRACT:  usp_registrar_o_actualizar_plan_estudio(@idPlanEstudio, @idPrograma, @inp, @idCorrelacion);
                                  upsert deterministico por @idPlanEstudio; 1 fila / 4 columnas canonicas; sin OUTPUT.
PRG_001_REMAINING:                0 (solo usaba PRG_001 el propio SP sin trackear; migrado a PROG_001)
PROG_001_USED:                    SI (programa inexistente)
SQL_STANDARD_FIXES:               DECLARE dentro de BEGIN CATCH movido a la zona de declaracion (SET en el CATCH);
                                  IF de una linea nuevos envueltos en BEGIN/END. Solo en los archivos tocados en esta
                                  fase (cierre masivo, radicar/resolver revision, asistencia autonoma, matricula,
                                  plan de estudio). Sin cambios de logica.
IDENTITY_RULE:                   documentada (sin cambios de logica) en docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md,
                                  seccion 1 (`usp_registrar_estudiante_en_grupo`): correo+documento del mismo usuario -> reutilizar;
                                  una sola clave coincide o claves en usuarios distintos -> conflicto IDN_001; ninguna existe -> crear.
DB_TEST_GATE:                     DB GATE PASS (TOTAL_EXPECTED=193, EXECUTED=195, PASSED=195, FAILED=0, SKIPPED=0,
                                  CRITICAL_MISSING=0, SQL_ERROR_COUNT=0, @@TRANCOUNT=0)
NEW_TESTS:                        test/test_usp_registrar_o_actualizar_plan_estudio.sql (crear, actualizar, programa
                                  inexistente, inp invalido, resultado canonico)
PLAN_ESTUDIO_PROVIDER:            PASS
READY_FOR_BACKEND_ALIGNMENT:      YES
```

## ADDENDUM FINAL: eliminacion de la regla (programa, inp) y pulido quirurgico (2026-10-07)

Cierra los pendientes de la seccion anterior. **No reescribe** nada de lo ya registrado arriba; agrega el estado final verificado.

```text
PLAN_ESTUDIO_PROVIDER:           PASS
DBCODE_PROGRAMA:                 PROG_001
PRG_001:                         NOT_USED
PLA_002:                         NOT_USED (regla (programa, inp) eliminada: no estaba respaldada por una restriccion
                                  UNIQUE del esquema ni por un contrato previo validado; se retira del SP y del
                                  catalogo de mensajes)
READS_FROM_VIEW:                 dbo.uv_plan_estudio (comprobaciones de existencia del SP)
WRITES_TO_TABLE:                 dbo.PlanEstudio (UPDATE / INSERT, sin cambios de modelo)
NEW_TEST:                        PLAN_ESTUDIO_INP_NULL (inp = NULL -> PLA_001, cero escrituras)
SQL_STANDARD_FIXES:              DECLARE reubicado despues de AS y antes de BEGIN en
                                  usp_sincronizar_usuario.sql y usp_registrar_o_actualizar_plan_estudio.sql;
                                  2 IF de una linea envueltos en BEGIN/END en usp_registrar_estudiante_en_grupo.sql
                                  (sin cambios de logica ni de condiciones)
OLD_MATRICULA_TEST_FILENAME:     test/test_usp_registrar_estudiante_en_grupo_usuario_no_existente.sql renombrado a
                                  test/test_usp_registrar_estudiante_en_grupo.sql (referencia actualizada en test_suite.sql)
GOLDEN_PATH_CONTRACT_CHANGED:    NO
GOLDEN_PATH_MANIFEST_CHANGED:    NO
```
