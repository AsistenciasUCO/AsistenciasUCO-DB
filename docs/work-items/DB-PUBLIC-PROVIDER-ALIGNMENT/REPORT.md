# DB-PUBLIC-PROVIDER-ALIGNMENT: informe de la pasada de base de datos

Fecha: 2026-10-07. Repositorio: `gestion-asistencia-db`. Alcance: solo base de datos. Sin cambios de backend ni de código Java. Sin commit ni push.

```text
BRANCH:              develop
HEAD:                f2871a9 (sin commit nuevo en esta pasada)
WORKTREE_BEFORE:     11 M + 4 ?? (estado inicial del prompt; incluye trabajo previo de LB-008, Plan de Estudio y revisiones)
WORKTREE_AFTER:      ver CHANGED_FILES
```

## CHANGED_FILES (esta pasada)

Esquema y seeds:
- `schema/stored-procedures/usp_registrar_estudiante_en_grupo.sql`: reescrito. Nombre publico restaurado; roles DOCENTE/COORDINADOR; titularidad en OR; identidad; transaccion owner/savepoint; propagacion de transaccion condenada.
- `schema/stored-procedures/usp_registrar_asistencia_estudiante_autonomo.sql`: nombre publico restaurado; propagacion de transaccion condenada.
- `schema/stored-procedures/usp_ejecutar_cierre_masivo_periodo.sql`: nombre publico restaurado (sin fallback de periodo; el trabajo previo se conserva).
- `schema/seed/04_mensaje.sql`: se elimina `PRG_001` (duplicado semantico de `PROG_001`); texto de `IDN_001` ampliado.
- `schema/seed/06_estado.sql` y `usp_radicar_/usp_resolver_solicitud_revision_asistencia.sql`: trabajo previo validado; sin cambios adicionales en esta pasada.

Pruebas:
- `test/test_registrar_estudiante_en_grupo_contrato.sql` (nuevo): contrato de matricula, 13 escenarios.
- `test/test_attendance_review_states.sql` (nuevo): estados P/A/R y catalogo faltante.
- `test/test_attendance_autonomous_atomic.sql` (nuevo): atomicidad de asistencia autonoma.
- `test/test_public_providers_contract.sql` (nuevo): nombres publicos, cero OUTPUT, canonico de usuario, internos de matricula, firma de cerrar sesion.
- `test/test_mass_period_close.sql`: caso de periodo inexistente (TD-058).
- `test/test_usp_registrar_estudiante_en_grupo_usuario_no_existente.sql` y `test/test_transaction_ownership.sql`: fixtures alineados al contrato; se elimina el `TEST_SKIP` incondicional.
- `test_suite.sql`, `test_summary.ps1`: registro de pruebas nuevas, comprobacion estatica `SP_FILENAME_OBJECT_MISMATCH`, y lista blanca de skips eliminada.

Documentacion:
- `docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`: matricula reescrita con el contrato vigente; secciones de sincronizacion, asistencia autonoma, revisiones, cierre masivo y cerrar sesion.
- `docs/contracts/DB_DEVELOP_FREEZE_ADDENDUM.md`: seccion post-freeze de esta pasada.
- `docs/work-items/DB-PUBLIC-PROVIDER-ALIGNMENT/REPORT.md`: este informe.

Sin tocar (congelado o fuera de alcance): `docs/contracts/DB_BASELINE_CONTRACT.md` y su `.sha256`, `DB_DEVELOP_FREEZE_MANIFEST.sha256`, vistas y SPs del golden path (`uv_sesion`, `uv_estudiante_grupo`, `uv_asistencia`, `uv_detalle_asistencia`, `uv_horario_docente`, `usp_crear_sesion`, `usp_actualizar_sesion`, `usp_generar_sesiones_grupo`, `usp_registrar_asistencias_sesion`), `schema/views/uv_estudiante_programa.sql` (trabajo LB-008 previo), `schema/stored-procedures/usp_registrar_o_actualizar_plan_estudio.sql` (Plan de Estudio, fuera de alcance), `docs/work-items/LB-008-*`.

## PUBLIC_PROCEDURES_CHANGED
- `dbo.usp_registrar_estudiante_en_grupo` (renombre restaurado, contrato reescrito).
- `dbo.usp_registrar_asistencia_estudiante_autonomo` (renombre restaurado).
- `dbo.usp_ejecutar_cierre_masivo_periodo` (renombre restaurado).
- `dbo.usp_sincronizar_usuario` (publico, nuevo en el worktree; sin cambios en esta pasada; ahora cubierto por prueba).

## INTERNAL_PROCEDURES_CHANGED
- Ninguno. Los `_interno` existentes se reutilizan sin renombrar ni modificar. Se eliminaron llamadas a `usp_matricula_grupo_interno`, que no existe.

## SP_FILENAME_OBJECT_MISMATCH: 0

## MATRICULA
```text
PUBLIC_SP:                    dbo.usp_registrar_estudiante_en_grupo (PASS)
INTERNAL_SP_CALLED:           usp_validar_id_correlacion_esta_presente_interno, usp_validar_tipo_identificacion_exista_por_id_interno,
                              usp_validar_permiso_rbac_usuario_interno, usp_validar_grupo_exista_por_id_interno,
                              usp_validar_titularidad_jerarquica_interno, usp_validar_cupo_disponible_grupo_interno,
                              usp_sincronizar_usuario_interno, usp_sincronizar_estudiante_interno,
                              usp_registrar_estudiante_en_grupo_interno
ALLOWED_ROLES:                DOCENTE, COORDINADOR (ADMINISTRADOR denegado, SEC_001)
DOCENTE_OWNERSHIP:            PASS (titular permitido; no titular -> SEC_002 con cero escrituras)
COORDINADOR_OWNERSHIP:        PASS (coordinador del programa permitido; coordinador de otro programa -> SEC_002 con cero escrituras)
ADMIN_ACCESS:                 DENIED (ENROLL_ADMIN_DENIED)
DUAL_ROLE:                    PASS (docente no titular + coordinador del programa: permitido por la regla OR)
EXPLICIT_DOCUMENT_TYPE:       PASS (NULL -> GEN_002; inexistente -> GEN_001; sin fallback a CC)
EXECUTOR_REQUIRED:            PASS (NULL -> GEN_002; sin escrituras)
IDENTITY_CONFLICT_VALIDATION: PASS (IDN_001; sin escrituras y sin fusion)
EXISTING_USER_PASSWORD:       PASS (password sin modificar; no se duplica Usuario ni Estudiante)
TRANSACTION_OWNER_PATTERN:    owner si @@TRANCOUNT = 0; SAVE TRANSACTION sp_matricula_grupo si hay transaccion externa; condenada -> THROW al propietario
ROLLBACK_TEST:                PASS: savepoint (ENROLL_ATOMIC_SAVEPOINT_ROLLBACK), propia (ENROLL_ATOMIC_OWNER_ROLLBACK), condenada (ENROLL_DOOMED_TX_PROPAGATED); transaccion externa viva en los casos de savepoint
```

## USUARIO
```text
PUBLIC_SYNC_PROVIDER:         dbo.usp_sincronizar_usuario (PASS)
INTERNAL_SYNC_PROVIDER:       dbo.usp_sincronizar_usuario_interno
CANONICAL_RESULT:             PASS (1 fila, 4 columnas; USER_SYNC_PUBLIC_PROVIDER / USER_SYNC_PUBLIC_INVALID)
```

## ASISTENCIA_AUTONOMA
```text
PUBLIC_SP_NAME:               dbo.usp_registrar_asistencia_estudiante_autonomo (PASS)
TRANSACTION_OWNER_PATTERN:    owner / SAVE TRANSACTION sp_asistencia_autonomo; condenada -> THROW al propietario
ROLLBACK_TEST:                PASS: AUTONOMOUS_ATOMIC_SAVEPOINT (residuos 0, transaccion externa viva); AUTONOMOUS_ATOMIC_OWNER (residuos 0)
```

## REVISION
```text
PENDING_CODE:                 P (PASS)
APPROVED_CODE:                A (PASS)
REJECTED_CODE:                R (PASS)
TOP1_FALLBACK:                NONE en radicar y resolver (las consultas TOP 1 son por id unico o por codigo sin ORDER BY; no hay fallback a otro estado)
TEST_RADICAR:                 PASS (REVIEW_STATE_RADICAR_P)
TEST_APROBAR:                 PASS (REVIEW_STATE_APROBAR_A)
TEST_RECHAZAR:                PASS (REVIEW_STATE_RECHAZAR_R)
TEST_MISSING_CATALOG:         PASS (REVIEW_MISSING_P/A/R_CONTROLLED: estado 0, cero escrituras, estado de la solicitud intacto)
```

## CIERRE_MASIVO
```text
PUBLIC_SP_NAME:               dbo.usp_ejecutar_cierre_masivo_periodo (PASS)
UNKNOWN_PERIOD_FALLBACK:      NONE (periodo solicitado o PER_001)
UNKNOWN_PERIOD_WRITES:        0 (verificado con conteos y checksums de PeriodoAcademico, Grupo, EstudianteGrupo, AuditoriaEvento y DetalleAsistencia)
TEST_UNKNOWN_PERIOD:          PASS (MASS_CLOSE_UNKNOWN_PERIOD_ZERO_WRITES)
```

## TECHNICAL_DEBT
```text
TD-039:                       CLOSED (solo contrato). Firma confirmada; legacy/no soportado -> SES_003. El cierre funcional no se implementa en esta fase.
TD-043_STUDENT_ENROLLMENT:    CLOSED (PASS)
TD-043_USER_SYNC:             CLOSED (PASS)
TD-043_PLAN_ESTUDIO:          DEFERRED_TO_BACKEND_ALIGNMENT_PHASE
TD-043 global:                PARTIALLY_RESOLVED (PLAN_ESTUDIO_PROVIDER pendiente; no declarar TD-043 CLOSED)
TD-046:                       CLOSED (documentacion de las vistas de contrato; ver VISTAS_CONTRATO)
TD-056:                       CLOSED (AUTONOMOUS_ATOMIC_SAVEPOINT y AUTONOMOUS_ATOMIC_OWNER PASS)
TD-057:                       CLOSED (pruebas REVIEW_* en verde)
TD-058:                       CLOSED (MASS_CLOSE_UNKNOWN_PERIOD_ZERO_WRITES PASS)
```

## PLAN_ESTUDIO_STATUS
```text
PLAN_ESTUDIO_PROVIDER: DEFERRED_TO_BACKEND_ALIGNMENT_PHASE
- schema/stored-procedures/usp_registrar_o_actualizar_plan_estudio.sql (sin trackear, sin validar) usa PRG_001.
  PRG_001 se elimina del catalogo porque duplica PROG_001. Ese archivo debe migrar a PROG_001 en la fase de Plan de Estudio.
- No se amplio, no se valido y no se usa para declarar TD-043 cerrado.
- Mensajes PLA_001, PLA_002, SUC_REGISTRO_PLAN_ESTUDIO y SUC_ACTUALIZACION_PLAN_ESTUDIO: sin cambios.
```

## VISTAS_CONTRATO (TD-046)
Columnas obtenidas del catalogo de la BD desplegada desde cero. No se modificaron las vistas.

| Vista | Columnas expuestas (tipo) | PK logica | Joins relevantes | Consumidor conocido |
|---|---|---|---|---|
| `uv_estudiante_grupo` | id uniqueidentifier; idEstadoEstudiante uniqueidentifier; nombreEstadoEstudiante nvarchar(50); codigoEstadoEstudiante nvarchar(50); idEstudiante uniqueidentifier; nombreCompletoEstudiante nvarchar(203); idGrupo uniqueidentifier; codigoGrupo int; nombreGrupo nvarchar(50) | `id` = `EstudianteGrupo.id` | `EstudianteGrupo` -> `uv_estudiante_identidad` (estudiante), `uv_estado_estudiante_grupo` (estado), `uv_grupo` (grupo) | Backend (listado de matriculas y estado); pruebas de cierre masivo y matricula |
| `uv_estudiante_identidad` | id uniqueidentifier (= `Estudiante.id`); idUsuario uniqueidentifier; numeroIdentificacion int; nombreCompleto nvarchar(203); estaActivoUsuario bit | `id` = `Estudiante.id`; `idUsuario` = `Usuario.id` | `Estudiante` -> `uv_usuario` (`e.usuario = u.id`) | Backend (identidad de estudiante); validaciones RBAC; matricula (`idUsuario` a `id` de estudiante) |
| `uv_usuario` | id uniqueidentifier; idTipoIdentificacion uniqueidentifier; TipoIdentificacion nvarchar(5); nombreTipoIdentificacion nvarchar(50); numeroIdentificacion int; primerApellido, segundoApellido, primerNombre, segundoNombre nvarchar(50); nombreCompleto nvarchar(203); correo nvarchar(100); correoConfirmado bit; correoConfirmadoTexto varchar(2); estaActivoUsuario bit; estaActivoTextoUsuario varchar(2); password varchar(5) (siempre '*****') | `id` = `Usuario.id` | `Usuario` -> `uv_tipo_identificacion` (`u.tipoIdIdentificacion = ti.id`) | Backend (perfil); unicidad de usuario; matricula (resolucion de identidad) |

Notas de contrato: `uv_usuario.password` devuelve siempre `'*****'`; el hash nunca sale por vista. `uv_estudiante_grupo` no se usa para resolver identidad en matricula.

## VALIDATION_EVIDENCE
Entorno: SQL Server 2022 Developer en un contenedor aislado creado para esta pasada (`sql_validacion_asistencias`, puerto 14333, limite de memoria 1.5 GB). La base de desarrollo (`sql_server_asistencias`, puerto 1433) no se modifico.

Secuencia: linea base en rojo (24 de 158 ejecutadas; `Msg 51908` por la llamada a `usp_matricula_grupo_interno`, inexistente; 3 SPs publicos faltantes) -> correcciones -> redespliegue **desde cero** (BD eliminada, esquema completo) -> suite completa.

```text
DB_TESTS_TOTAL:       190 ejecutadas (188 criticas esperadas)
DB_TESTS_PASSED:      190
DB_TESTS_FAILED:      0
DB_TESTS_SKIPPED:     0 (UNAUTHORIZED_SKIPS=0; se elimino el TEST_SKIP XACT_STATE_MINUS_ONE_RUNTIME)
SQL_ERROR_COUNT:      0
FINAL_TRANCOUNT:      0 (SUITE_TRANCOUNT_ZERO)
PUBLIC_SP_MISSING:    0
GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED: PASS
GLOBAL_DB_STATUS:     PASS (alcance de esta pasada; Plan de Estudio DEFERRED / OUT_OF_SCOPE)
```

## VALIDACIONES_ESTATICAS
- `usp_matricula_grupo`, `usp_asistencia_autonomo`, `usp_cierre_masivo`, `usp_matricula_grupo_interno`: solo aparecen en las guardas de prueba y en el comentario del harness. Ningun objeto se crea con esos nombres.
- `PEND`, `APRO`, `RECH`: sin resultados.
- `TOP 1`: revisado. Los restantes en matricula, radicar, resolver y cierre masivo son consultas por id unico o por codigo; ninguna actua como fallback a otro estado o periodo.
- `ORDER BY id`: revisado. Aparece en `usp_crear_coordinador` y `usp_crear_decano` dentro de un fallback a "el primer tipo de identificacion" (ver pendientes).
- `COALESCE` e `ISNULL`: ausentes en los SPs publicos de esta pasada.

## DECISIONES
1. Identidad de matricula: se reutiliza solo si correo y documento apuntan al mismo usuario. Un unico acierto da `IDN_001`. Antes se reutilizaba por correo solamente. Requiere confirmacion del backend.
2. Ejecutor y tipo de identificacion obligatorios, sin default. El backend debe enviarlos explicitamente.
3. `ADMINISTRADOR` denegado en matricula, sin bypass. Cambio de contrato: el backend no debe usar una cuenta administrativa para esta operacion.
4. `PRG_001` eliminado (duplica `PROG_001`). Grupo sin programa asociado usa `GRUP_003`, que ya existe.
5. Fallos forzados con `CHECK` (error 547), no con `THROW` en trigger: un `THROW` en trigger condena la transaccion (`XACT_STATE() = -1`) y no permite `ROLLBACK TO SAVEPOINT`. Se verifico en la BD aislada, y el SP lo propaga en lugar de devolver estado 0 silencioso.
6. El baseline congelado no se reescribe. Los cambios de contrato se documentan en el addendum post-freeze, siguiendo el patron de LB-008.

## PENDIENTES_FUERA_DE_ALCANCE
- `usp_crear_coordinador` y `usp_crear_decano`: fallback a `TOP 1 ... ORDER BY id` sobre `TipoIdentificacion` cuando falta `CC`. Viola el principio de tipo explicito. Requiere pasada aparte.
- ~~`usp_registrar_o_actualizar_plan_estudio`: migrar `PRG_001` a `PROG_001` en la fase de Plan de Estudio.~~ Cerrado; ver `ADDENDUM FINAL` abajo.
- La unicidad de `Estado.codigo` y de `EstadoEstudianteGrupo.codigo` no esta forzada por esquema; el seed mantiene la unicidad en la practica.
- Backend: adaptar la llamada de matricula a la firma nueva (ejecutor y tipo obligatorios; sin ADMINISTRADOR).

## ADDENDUM FINAL: cierre de Plan de Estudio (2026-10-07)

Completa el `PLAN_ESTUDIO_STATUS` registrado arriba como `DEFERRED_TO_BACKEND_ALIGNMENT_PHASE`. **No borra evidencia
historica**; agrega el estado final verificado tras cerrar el provider. Detalle: `docs/contracts/DB_DEVELOP_FREEZE_ADDENDUM.md`
(seccion "ADDENDUM FINAL: eliminacion de la regla (programa, inp) y pulido quirurgico").

```text
PLAN_ESTUDIO_PROVIDER:   PASS
DBCODE_PROGRAMA:         PROG_001
PRG_001:                 NOT_USED
PLA_002:                 NOT_USED (regla (programa, inp) eliminada; no estaba respaldada por una restriccion UNIQUE
                          del esquema ni por un contrato previo validado)
TD-043_PLAN_ESTUDIO:     CLOSED
TD-043 global:           CLOSED
```

Tambien se renombro `test/test_usp_registrar_estudiante_en_grupo_usuario_no_existente.sql` (mencionado en `CHANGED_FILES`
arriba) a `test/test_usp_registrar_estudiante_en_grupo.sql`, con la referencia actualizada en `test_suite.sql`. El contenido
funcional de los casos de prueba no cambio.
