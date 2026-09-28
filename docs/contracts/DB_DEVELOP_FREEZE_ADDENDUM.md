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
CURRENT REVIEWED TIP:  6c120ca5b3eea191924163472b1f3a16edc6e2ff (+ cambios sin commit de LB-002.1C-A)
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
CURRENT PUBLIC CONTRACT IS NOT EQUIVALENT TO LEGACY: STATUS = DECISION_REQUIRED (LB-002.1C-B)
```
