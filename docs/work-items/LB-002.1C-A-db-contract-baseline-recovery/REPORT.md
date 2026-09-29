# LB-002.1C-A - DB CONTRACT BASELINE RECOVERY / STUDENT-GROUP CONTRACT

```text
DB BASE SHA:      6c120ca5b3eea191924163472b1f3a16edc6e2ff  (origin/sergio; el remoto no avanzo tras la apertura de la fase)
DB BASE BRANCH:   sergio
WORKTREE CLEAN AT START: YES
LB-002.1C-A IMPLEMENTATION/CLOSURE COMMIT: 0798b994cc074a4315916a0b45e662d1708c6ab2  (base 6c120ca + 8 archivos de esta fase, ver seccion 10)
PUSHED: YES   (HEAD == origin/sergio al cierre)

RESULT: B
CURRENT PUBLIC CONTRACT IS NOT EQUIVALENT
BACKEND DIRECT ALIGNMENT POSSIBLE: NO
CONTRACT DECISION REQUIRED: YES
DB CONTRACT CHANGE REQUIRED: TO_BE_DETERMINED_AFTER_BACKEND_AS_IS
DB PRODUCTION CHANGE AUTHORIZED: NO
BACKEND PRODUCTION CHANGE AUTHORIZED: NO
STATUS: DECISION_REQUIRED
NEXT AUTHORIZED PHASE: LB-002.1C-B1 - BACKEND AS-IS CONTRACT ANALYSIS (registrarEstudianteEnGrupo)

FINAL CLOSURE (cierre formal de 1C-A):
PUBLIC STUDENT-GROUP WIRE/ABI CHANGED IN 1C-A:   NO
PUBLIC STUDENT-GROUP BEHAVIOR CORRECTED IN 1C-A: YES
  CORRECTED BEHAVIOR: capacity rejection occurs before identity persistence,
  preventing partial Usuario/Estudiante state.
TRANSACTION OWNERSHIP OF PUBLIC STUDENT ENROLLMENT: NOT CERTIFIED
LEGACY CONTRACT EQUIVALENT: NO   (CURRENT PUBLIC CONTRACT IS NOT EQUIVALENT TO LEGACY; STATUS = DECISION_REQUIRED)
BACKEND ALIGNMENT DIRECTLY POSSIBLE: NO
GOLDEN PATH SOURCE CHANGED: NO     GOLDEN PATH CONTRACT CHANGED: NO     DB CONTRACT HASH: MATCH
TD-043: OPEN     GLOBAL -Pintegration: NOT_GREEN_TD043
```

Esta fase NO resuelve el contrato funcional de matricula de estudiantes: solo corrige una regresion de comportamiento y documenta la deriva. No declara TD-043 resuelto ni integracion global verde.

## 1. Pregunta de la fase

`dbo.usp_registrar_estudiante_en_grupo` es hoy el comando publico canonico de la DB para matricular a un estudiante en un grupo?

**Si es el unico comando publico vigente** (el SP legacy `usp_registrar_estudiante_en_grupo_usuario_no_existente` no existe en la DB desde `daeac11`, 2026-09-13). **Pero su contrato no es equivalente al legacy** que el backend historico aun consume, por lo que el backend no puede migrar sin perdida funcional hasta que se tome una decision de contrato.

## 2. Hallazgo critico del BASE SHA (regresion de `6c120ca`)

El gate DB estaba **rojo en el BASE SHA** (desplegado y ejecutado con los runners oficiales en un contenedor efimero):

```text
BASE 6c120ca, sin cambios:  TOTAL_EXPECTED=151  TOTAL_EXECUTED=66  PASSED=61  FAILED=5  SQLCMD_EXIT_CODE=1
TEST FAILED: STUDENT_CAPACITY_EXCEEDED left partial Usuario.   (sqlcmd -b aborta: 90 IDs criticos no llegaron a ejecutarse)
```

Causa: `6c120ca` quito el cupo de `usp_validar_grupo_exista_por_id_interno` (correcto: permite programar sesiones en grupos llenos) y lo reubico **solo** en `usp_registrar_estudiante_en_grupo_interno`. Ese interno corre **despues** de `usp_sincronizar_usuario_interno` / `usp_sincronizar_estudiante_interno` en el SP publico, y el SP publico no tiene transaccion propia. Un grupo lleno rechazaba con `ERR_CUPO_SUPERADO` pero dejaba `Usuario` y `Estudiante` huerfanos.

Correccion minima (unico cambio productivo): `usp_registrar_estudiante_en_grupo` valida el cupo (`usp_validar_cupo_disponible_grupo_interno`) en el nuevo PASO 1.9, inmediatamente despues de validar el grupo y antes de cualquier escritura. Restaura el orden de rechazo vigente en `9b2b993`; firma (ABI/wire), resultset, DBCODEs, RBAC y tablas no cambian, pero el comportamiento observable SI se corrige: el rechazo por cupo ocurre antes de persistir identidad, eliminando el estado parcial `Usuario`/`Estudiante`. El control en el interno se conserva como defensa en profundidad.

## 3. Contrato real de `dbo.usp_registrar_estudiante_en_grupo`

Fuente: `schema/stored-procedures/usp_registrar_estudiante_en_grupo.sql` y `sys.parameters` de la DB desplegada.

| # | Parametro | Tipo SQL | Nulabilidad / default |
|---|-----------|----------|-----------------------|
| 1 | `@idGrupo` | `UNIQUEIDENTIFIER` | requerido |
| 2 | `@numeroIdentificacion` | `INT` | requerido |
| 3 | `@primerNombre` | `NVARCHAR(50)` | requerido |
| 4 | `@segundoNombre` | `NVARCHAR(50)` | requerido (puede ser vacio) |
| 5 | `@primerApellido` | `NVARCHAR(50)` | requerido |
| 6 | `@segundoApellido` | `NVARCHAR(50)` | requerido (puede ser vacio) |
| 7 | `@correo` | `NVARCHAR(100)` | requerido |
| 8 | `@password` | `NVARCHAR(500)` | requerido |
| 9 | `@idCorrelacion` | `UNIQUEIDENTIFIER` | requerido |
| 10 | `@idUsuarioEjecutor` | `UNIQUEIDENTIFIER` | `= NULL` en firma; `NULL` retorna `GEN_002(idUsuarioEjecutor)` |

Sin parametros `OUTPUT`. Sin `@idTipoIdIdentificacion`. Resultset: una fila `idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado` (contrato canonico).

Secuencia real (seguida por llamadas): correlacion -> `@idUsuarioEjecutor` no nulo (`GEN_002`) -> `usp_validar_permiso_rbac_usuario_interno` con perfil `ESTUDIANTE` (`SEC_001`) -> `usp_validar_grupo_exista_por_id_interno` -> **`usp_validar_cupo_disponible_grupo_interno` (PASO 1.9, nuevo)** -> usuario por `correo` (`usp_sincronizar_usuario_interno` si no existe) -> perfil `Estudiante` (`usp_sincronizar_estudiante_interno` si no existe) -> `usp_registrar_estudiante_en_grupo_interno` (correlacion, estado `A`, estudiante existe, grupo, cupo, cruce de horario, matricula duplicada, `INSERT EstudiantePrograma` si el grupo tiene programa, `INSERT EstudianteGrupo`).

| Aspecto | Comportamiento actual | Evidencia |
|---|---|---|
| Autorizacion | Ejecutor activo con perfil `ESTUDIANTE` (`LIKE %ESTUDIANTE%` sobre `uv_usuario_perfil`). **Sin titularidad.** Un COORDINADOR obtiene `SEC_001` | probe P2; codigo del RBAC |
| Ownership transaccional | **No certificado / ninguno propio**: 0 `BEGIN TRAN / SAVE TRAN / XACT_STATE / COMMIT / ROLLBACK` en el publico, el interno y `usp_registrar_docente_en_grupo` | `grep` (0/0/0) |
| Rollback | No hay. Cualquier escritura previa a un fallo tardio/excepcion persiste (`CATCH` solo formatea `SYS_001`) | codigo; regresion de `6c120ca` |
| Auditoria | Ninguna escritura en `AuditoriaEvento` (tampoco en el legacy) | `grep`; solo `usp_ejecutar_cierre_masivo_periodo` audita |
| Catalogo / DBCODE | Exito `GEN_004`; error inesperado `SYS_001`; validaciones `GEN_002`, `SEC_001`, `ERR_GRUPO_NO_EXISTE`, `GRUP_003`, `ERR_GRUPO_NO_HABILITADO`, `ERR_CUPO_SUPERADO`, `ERR_MATRICULA_DUPLICADA`; unicidad `ERR_UNICIDAD_DOCUMENTO` | tests + probes P1-P5 |
| Grupo inexistente | `ERR_GRUPO_NO_EXISTE`, sin escrituras | `STUDENT_GROUP_NOT_FOUND` |
| Grupo deshabilitado / fuera de periodo | `ERR_GRUPO_NO_HABILITADO` (habilitado = fecha local institucional dentro del periodo), sin escrituras | `STUDENT_GROUP_DISABLED` |
| Cupo | `ERR_CUPO_SUPERADO` (`cuposDisponibles <= 0`), sin escrituras | `STUDENT_CAPACITY_EXCEEDED` |
| Duplicado | `ERR_MATRICULA_DUPLICADA`; no modifica usuario ni conteos | `STUDENT_DUPLICATE`, probe P4 |
| Usuario existente (por correo) | Se reutiliza; **no** se actualizan datos biograficos | probe P4 (doc/nombre intactos) |
| Usuario inexistente | Se crea con tipo de identificacion **`CC` fijo** (o el primero de `TipoIdentificacion`) | probe P3 (`CC`) |
| Mismo documento, otro correo | `ERR_UNICIDAD_DOCUMENTO`, sin usuario nuevo | probe P5 (1/1) |
| Estudiante existente / inexistente | Reutiliza perfil / lo crea antes de matricular | codigo (`STUDENT_SUCCESS` cubre inexistente) |

## 4. Estado del comando legacy

```text
usp_registrar_estudiante_en_grupo_usuario_no_existente
  schema/**, migrations/**, deploy scripts:   AUSENTE
  DB desplegada (sys.objects):                0 objetos
  eliminado en:                               daeac11 (2026-09-13), reemplazado por usp_registrar_estudiante_en_grupo
  aun referenciado en (solo texto):           docs/arquitectura/{DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS,DOCUMENTACION_PROCEDIMIENTOS_ORQUESTADORES,backend_specification}.md,
                                              docs/catalogos/prioridades-desarrollo.md, prompt_transacciones_reactivas_y_documentacion.md,
                                              schema/seed/04_mensaje.sql (texto del mensaje ERR_INESPERADO_REGISTRO_ESTUDIANTE),
                                              nombre de archivo de test test/test_usp_registrar_estudiante_en_grupo_usuario_no_existente.sql (que ejercita el SP NUEVO)
STATUS: REMOVED_FROM_DB / DOCUMENTATION_STALE
```

## 5. Matriz de contratos (legacy `@daeac11^` vs actual)

| CAPABILITY | LEGACY CONTRACT | CURRENT PUBLIC CONTRACT | EQUIVALENT | DIFFERENCE | IMPACT FOR CONSUMER |
|---|---|---|---|---|---|
| Resultset canonico | 4 columnas | 4 columnas | YES | - | ninguno |
| Tipo de documento | `@idTipoIdIdentificacion` explicito | no existe; `CC` fijo | **NO** | se pierde CE/TI/pasaporte | el backend no puede registrar no-CC |
| Orden / limites de parametros | 255 en nombres y correo; orden distinto; `@idGrupo` al final | 50 nombres, 100 correo; `@idGrupo` primero | **NO** | firma incompatible | reescritura de llamada; truncamientos |
| Ejecutor / seguridad | sin ejecutor | `@idUsuarioEjecutor` obligatorio + perfil `ESTUDIANTE` | **NO** | RBAC nuevo, sin titularidad; el operador de la spec (COORDINADOR) es rechazado | flujo del coordinador bloqueado; cualquier estudiante activo matricula a cualquiera |
| Busqueda de usuario | `correo` **o** (tipo+documento); actualiza datos biograficos | solo `correo`; sin actualizar | **NO** | conflicto de documento => `ERR_UNICIDAD_DOCUMENTO` | flujos de "actualizar y matricular" cambian |
| Perfil estudiante | crea si falta | crea si falta | YES | - | ninguno |
| Grupo existe / periodo / habilitado | via interno | via interno (+ publico) | YES | - | ninguno |
| Cupo | `ERR_CUPO_SUPERADO` desde el interno (tras sincronizar identidad); la transaccion propia hace `ROLLBACK` | `ERR_CUPO_SUPERADO` antes de escribir (tras esta fase) | YES (resultado observable) | mecanismo distinto (rollback vs. rechazo previo); en `6c120ca` NO era equivalente (escrituras parciales) | ninguno tras el fix |
| Matricula duplicada | `ERR_MATRICULA_DUPLICADA` | igual | YES | - | ninguno |
| Cruce de horario | via interno | via interno | YES | - | ninguno |
| Programa academico | `usp_registrar_estudiante_en_programa_interno`; sin programa => `ERR_PROGRAMA_GRUPO_NO_ENCONTRADO` | `INSERT EstudiantePrograma` en el interno; sin programa se omite **sin error** | **NO** | validacion de trazabilidad perdida | matriculas sin programa pasan silenciosamente |
| Codigo de exito (DBCODE) | `SUC_REGISTRO_ESTUDIANTE_GRUPO` | `GEN_004` | **NO** | cambia el `DBCODE=` | mapeo de errores/exitos del backend |
| Codigo de error inesperado | `ERR_INESPERADO_REGISTRO_ESTUDIANTE` | `SYS_001` | **NO** | cambia el `DBCODE=` | idem |
| Ownership transaccional | `BEGIN TRAN` / `SAVE TRAN`, `COMMIT`/`ROLLBACK`, `XACT_STATE` | ninguno | **NO** | escrituras parciales ante fallo tardio/excepcion | riesgo de `Usuario`/`Estudiante` huerfanos |
| Auditoria | ninguna | ninguna | YES | - | ninguno |

**Conclusion:** el contrato publico actual **no es equivalente** al contrato que esperaba el backend historico (`..._usuario_no_existente`), por lo que el backend no puede migrar directamente a `usp_registrar_estudiante_en_grupo` sin perder reglas funcionales (tipo de documento, actualizacion por documento, atomicidad, validacion de programa, codigos `DBCODE`, operador COORDINADOR). Esto **no** afirma que el contrato DB actual sea incorrecto por si mismo: primero debe investigarse que capability requiere el consumidor productivo actual. No se alinea el backend ni se cambia el contrato en esta fase.

Puntos de decision de contrato (no ejecutados aqui; a resolver con el insumo de `LB-002.1C-B1`): (a) tipo de documento explicito o `CC` fijo; (b) modelo de autorizacion (perfil de ejecutor, titularidad); (c) ownership transaccional del SP publico; (d) `ERR_PROGRAMA_GRUPO_NO_ENCONTRADO` y `DBCODE` de exito; (e) actualizacion de datos de usuario existente.

Siguiente paso autorizado: **`LB-002.1C-B1` - BACKEND AS-IS CONTRACT ANALYSIS (`registrarEstudianteEnGrupo`)**. Su finalidad es solo determinar: consumer productivo real; endpoint; use case; port; adapter; firma SQL esperada; parametros realmente utilizados; reglas de negocio que el backend aun espera; pruebas de integracion que fallan; minimo cambio contractual necesario. B1 **no** implica automaticamente cambiar la DB. TD-043 sigue abierto.

## 6. Regresion de cupo (cambio `6c120ca`)

```text
GRUPO EXISTENTE, HABILITADO Y LLENO
  |-- crear/programar sesion      PERMITIDO   (SESSION_CREATE_ALLOWED_ON_FULL_GROUP, CAPACITY_GROUP_VALIDATOR_ALLOWS_FULL_GROUP)
  '-- registrar nuevo estudiante  RECHAZADO   ERR_CUPO_SUPERADO (STUDENT_CAPACITY_EXCEEDED, CAPACITY_VALIDATOR_REJECTS_FULL_GROUP)
```

Cobertura previa a la fase: la parte "rechazo" existia (`STUDENT_CAPACITY_EXCEEDED`) y estaba **fallando** en el BASE; la parte "sesion permitida en grupo lleno" **no tenia ningun test** (los tests de sesion eligen `ORDER BY cuposDisponibles DESC`).

Test agregado (minimo): `test/test_group_capacity_decoupling.sql`, 3 IDs criticos, sobre un unico grupo lleno (fixture en transaccion con `ROLLBACK`):

| ID | Verifica |
|---|---|
| `CAPACITY_GROUP_VALIDATOR_ALLOWS_FULL_GROUP` | `usp_validar_grupo_exista_por_id_interno` acepta el grupo lleno (base de crear/generar sesiones y registrar docente) |
| `CAPACITY_VALIDATOR_REJECTS_FULL_GROUP` | `usp_validar_cupo_disponible_grupo_interno` rechaza con `DBCODE=ERR_CUPO_SUPERADO|` y mensaje de catalogo |
| `SESSION_CREATE_ALLOWED_ON_FULL_GROUP` | `usp_crear_sesion` exitoso en el grupo lleno, sesion persistida, matricula intacta |

Prueba roja: con `usp_validar_grupo_exista_por_id_interno` de `9b2b993` (cupo acoplado) el test falla en `52002`; con el actual pasa. El rechazo por el SP **publico** sin residuos lo garantiza `STUDENT_CAPACITY_EXCEEDED` (no se duplico).

## 7. Regresiones que permanecen (tests existentes, todos PASS)

| Regla | Test(s) |
|---|---|
| grupo inexistente `ERR_GRUPO_NO_EXISTE` | `STUDENT_GROUP_NOT_FOUND` |
| grupo deshabilitado `ERR_GRUPO_NO_HABILITADO` | `STUDENT_GROUP_DISABLED` |
| matricula duplicada `ERR_MATRICULA_DUPLICADA` | `STUDENT_DUPLICATE` |
| cupo `ERR_CUPO_SUPERADO` | `STUDENT_CAPACITY_EXCEEDED` (+3 nuevos) |
| usuario/estudiante existente | `STUDENT_DUPLICATE`; alta completa en `STUDENT_SUCCESS` |
| conteos sin residuos en rechazos por validacion | asserts de conteos en cada `STUDENT_*` |
| DBCODE estable | `TECHNICAL_CODE_CHANNEL*`, `*_PREFIX`, comparacion de mensaje canonico en cada `STUDENT_*` |
| `@@TRANCOUNT = 0` | `SUITE_TRANCOUNT_ZERO` |
| auditoria | no aplica: estos SP no auditan |

**Precision sobre `OWNERSHIP_STUDENT`** (`test/test_transaction_ownership.sql`): invoca el SP publico con un grupo inexistente, por lo que el SP rechaza en validacion **antes de cualquier escritura**. Demuestra solo que ese escenario no deja efectos laterales ni altera `@@TRANCOUNT` de una transaccion externa. **No** demuestra ownership transaccional completo:

```text
TRANSACTION OWNERSHIP OF PUBLIC STUDENT ENROLLMENT: NOT CERTIFIED
CURRENT TEST: does not prove rollback after an actual intermediate write
              (fallo posterior a una escritura, SAVEPOINT, transaccion externa, rollback propio)
FOLLOW-UP:    requires separate contractual decision / work item (no se implementa en 1C-A)
```

Brecha conocida, sin test dedicado: "estudiante ya existente **no** matriculado en el grupo" (solo cubierto por lectura de codigo). No se agrego test: no es objeto de esta fase.

## 8. Reconciliacion de freeze / baseline

```text
PREVIOUS FROZEN TIP:   9b2b993 (docs) / dcc69f1 (FINAL_DEVELOP_COMMIT, ultimo cambio de esquema/tests/gates)
BASE SHA:              6c120ca5b3eea191924163472b1f3a16edc6e2ff
LB-002.1C-A COMMIT:    0798b994cc074a4315916a0b45e662d1708c6ab2 (implementacion/cierre; PUSHED: YES; HEAD == origin/sergio al cierre)
POST-FREEZE REVIEWED TIP: ADVANCED BY LB-002.1C-A (0798b99)
DB-GP-001C ORIGINAL FREEZE: UNCHANGED (FINAL_DEVELOP_COMMIT dcc69f1 no se reescribe)
REASON FOR ADVANCE:    6c120ca desacopla cupo de grupo (sesiones en grupos llenos); esta fase corrige su regresion en la matricula
GOLDEN PATH CONTRACT CHANGED: NO
PUBLIC STUDENT-GROUP WIRE/ABI CHANGED IN 1C-A: NO   (firma, resultset, DBCODEs y RBAC identicos a 9b2b993)
PUBLIC STUDENT-GROUP BEHAVIOR CORRECTED IN 1C-A: YES (rechazo por cupo antes de persistir identidad; sin Usuario/Estudiante parciales)
TABLES CHANGED: NO
GOLDEN PATH SOURCE CHANGED: NO
FREEZE CONTRACT UNCHANGED: YES / REVIEWED REPOSITORY TIP ADVANCED (motivo: correccion NON-GOLDEN/interna)
BASELINE/FREEZE DOCUMENTATION UPDATED: YES  (addendum: seccion de revision; DB_BASELINE_CONTRACT.md y manifest NO se tocan)
```

`git diff 9b2b993 -- <5 vistas + 4 SP Golden Path>`, `-- schema/tables migrations`: vacios. `6c120ca` toco solo 3 SP internos NON-GOLDEN (`usp_registrar_estudiante_en_grupo_interno`, `usp_validar_cupo_disponible_grupo_interno`, `usp_validar_grupo_exista_por_id_interno`). Pero `usp_validar_grupo_exista_por_id_interno` es **llamado por `usp_crear_sesion` y `usp_generar_sesiones_grupo`** (SP Golden Path congelados): su comportamiento efectivo cambio (grupo lleno ya no bloquea) sin cambiar su fuente ni su firma. Esto es coherente con el requisito ("sesion permitida en grupo lleno") y queda cubierto por el test nuevo; no invalida el manifest, pero el addendum debe registrarlo. Sin bloqueo en `DB_BASELINE_CONTRACT.md` (no menciona el cupo).

Hashes SHA-256 (LF, equivalentes al blob de Git), recalculados desde los archivos reales:

```text
45e48c5a0ab321d0c8cbffb55ee224e3b6fd29febc39a62ca723b2b209945aec  docs/contracts/DB_BASELINE_CONTRACT.md           (UNCHANGED; == BASELINE_CONTRACT_SHA)
FREEZE_MANIFEST_OK entries=10                                                                                        (10 archivos congelados sin cambios)
cde75ba2dcef8be87f3ddda6ee5625269bfca2013c859efefae281a02c167914  usp_registrar_estudiante_en_grupo.sql @6c120ca
b1e53be6ce06b3331c297c67a9d5b38b444266ceef07537ea955cefaa8471413  usp_registrar_estudiante_en_grupo.sql @worktree
1a304cc7096ed58ca896db2f958d5ce4a39aeff724777c975749673c272edc65  usp_registrar_estudiante_en_grupo_interno.sql
1e305c635eb579828f2710e625a083c74b7a00a0287d65855af93084741a5b17  usp_validar_cupo_disponible_grupo_interno.sql
b43581a2c8c8f1c51be5977adfd6127bb858b43a3d26edb25ee4b6ec4a6a2848  usp_validar_grupo_exista_por_id_interno.sql
6d91945187e2aa4c206ccfdd2cfd483c92cd727e8d13390ebdfa7a3ea39d35a2  test/test_group_capacity_decoupling.sql
```

## 9. Validacion DB real

Entorno: SQL Server 2022 Developer en **contenedor efimero** (`sql_lb0021ca_tmp`, removido al terminar); no se toco `sql_server_asistencias`. Runners oficiales: `deploy_schema.ps1` y `test_summary.ps1`.

```text
BASE 6c120ca (antes del fix):   TOTAL_EXPECTED=151 TOTAL_EXECUTED=66 PASSED=61 FAILED=5  -> DB GATE INCOMPLETE (exit 1)
WORKTREE (con fix + test):      DEPLOY: PASS
                                TOTAL_EXPECTED=154
                                TOTAL_EXECUTED=155
                                PASSED=154
                                FAILED=0
                                SKIPPED=1   (XACT_STATE_MINUS_ONE_RUNTIME, unico skip autorizado; UNAUTHORIZED_SKIPS=0)
                                CRITICAL_MISSING=0  SQLCMD_EXIT_CODE=0  SQL_ERROR_COUNT=0
                                @@TRANCOUNT=0
                                DB GATE PASS
```

Identico en **FRESH** (`DROP DATABASE` + `deploy_schema.ps1` + gate) y **REDEPLOY** (segundo deploy + gate sobre la misma DB, idempotencia): deploy exit 0, gate exit 0.

`154 = 151 (dcc69f1) + 3 IDs nuevos`. Las cifras `127/128` de `DB_BASELINE_CONTRACT.md` son historicas del baseline v1 y no se reutilizan.

## 10. Cambios de la fase

| Archivo | Por que |
|---|---|
| `schema/stored-procedures/usp_registrar_estudiante_en_grupo.sql` | PASO 1.9: cupo antes de escrituras (fix de la regresion de `6c120ca`) |
| `test/test_group_capacity_decoupling.sql` (nuevo) | cobertura faltante: sesion permitida en grupo lleno + contraste con el validador de cupo |
| `test_suite.sql`, `test_summary.ps1` | registrar el test nuevo y sus 3 IDs criticos |
| `docs/contracts/DB_DEVELOP_FREEZE_ADDENDUM.md` | registrar la revision post-freeze (tip previo/actual, motivo, banderas) |
| `docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`, `..._ORQUESTADORES.md` | nota "SUPERSEDED": el SP legacy documentado ya no existe |
| este `REPORT.md` | evidencia de la fase |

NO se modificaron: backend, frontend, tablas, Golden Path, `DB_BASELINE_CONTRACT.md`, manifest.

## 11. Cierre formal y revalidacion (2026-09-27)

Revalidacion ejecutada de nuevo al cierre (no se reutilizaron resultados previos): contenedor efimero SQL Server 2022 Developer nuevo (removido al terminar), `deploy_schema.ps1` + `test_summary.ps1` oficiales.

```text
FRESH DEPLOY:   PASS (exit 0)
FULL DB GATE:   TOTAL_EXPECTED=154 TOTAL_EXECUTED=155 PASSED=154 FAILED=0 SKIPPED=1 (XACT_STATE_MINUS_ONE_RUNTIME, autorizado; UNAUTHORIZED_SKIPS=0)
                CRITICAL_MISSING=0 SQLCMD_EXIT_CODE=0 SQL_ERROR_COUNT=0 @@TRANCOUNT=0  -> DB GATE PASS
REDEPLOY:       PASS (exit 0, misma DB)
REDEPLOY GATE:  identico al anterior (154/155/154/0/1, CRITICAL_MISSING=0, exit 0, @@TRANCOUNT=0)
RED EVIDENCE:   BASE 6c120ca sin fix: TOTAL_EXECUTED=66 PASSED=61 FAILED=5, "STUDENT_CAPACITY_EXCEEDED left partial Usuario" (seccion 9)
GREEN EVIDENCE: lo anterior con el fix de PASO 1.9 + test_group_capacity_decoupling (3 IDs PASS)
```

Verificaciones de freeze/hashes (calculadas sobre blobs de Git; la copia de trabajo usa CRLF por `core.autocrlf`, por eso el hash del archivo en disco difiere del blob):

```text
DB_BASELINE_CONTRACT.md blob sha256 = 45e48c5a0ab321d0c8cbffb55ee224e3b6fd29febc39a62ca723b2b209945aec == DB_BASELINE_CONTRACT.sha256   -> DB GOLDEN PATH CONTRACT HASH: MATCH
DB_DEVELOP_FREEZE_MANIFEST.sha256: 10/10 entradas coinciden con los blobs; ninguna modificada en el worktree
git diff 9b2b993 sobre las 5 vistas y 4 SP Golden Path, schema/views, schema/tables, migrations: vacio
  -> GOLDEN PATH SOURCE CHANGED: NO   GOLDEN PATH CONTRACT CHANGED: NO   TABLES CHANGED: NO
El test invoca usp_crear_sesion; no lo modifica.
```

Estado final de la fase:

```text
LB-002.1C-A = PASS  (alcance: correccion de regresion de cupo + evidencia; NO resuelve el contrato funcional de matricula)
capacity regression fixed = YES                       partial Usuario/Estudiante on capacity failure = FIXED
full group allows session = VERIFIED                  full group rejects enrollment = VERIFIED (ERR_CUPO_SUPERADO, sin residuos)
public SP ABI/wire changed = NO                       public SP behavior corrected = YES
legacy/current contract equivalence = NO              transaction ownership fully certified = NO
backend alignment directly possible = NO              CONTRACT DECISION REQUIRED = YES (DB change: TO_BE_DETERMINED_AFTER_BACKEND_AS_IS; next: LB-002.1C-B1)
TD-043 = OPEN                                         GLOBAL -Pintegration = NOT_GREEN_TD043
```

No se declara TD-043 resuelto, integracion global verde ni contrato de matricula de estudiantes completo.
