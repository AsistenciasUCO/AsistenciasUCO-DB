# DB BASELINE CONTRACT v1

## Authority

El source-of-truth de base de datos esta en:

- `schema/tables/**`
- `schema/views/**`
- `schema/functions/**`
- `schema/stored-procedures/**`
- `schema/seed/**`

Las tablas y columnas no se expanden para acomodar backend/frontend. Cualquier divergencia de shape existente debe reconstruirse desde este baseline, no maquillarse con migraciones silenciosas.

## Public SP Result

Todo SP publico de negocio retorna una unica fila con columnas, en orden exacto:

1. `idCorrelacion` (`UNIQUEIDENTIFIER`)
2. `mensajeUsuarioResultado` (`NVARCHAR`)
3. `mensajeTecnicoResultado` (`NVARCHAR`)
4. `estadoResultado` (`BIT`)

`dbo.usp_obtener_mensaje_catalogo` es helper tecnico y queda excluido del contrato publico.

## Technical Error Code Channel

`mensajeTecnicoResultado` usa el formato contractual:

`DBCODE=<catalog-code>|<technical-detail>`

El prefijo `DBCODE=<catalog-code>|` es machine-readable y contractual. `<catalog-code>` proviene directamente del codigo catalogado recibido por `dbo.usp_obtener_mensaje_catalogo`; no se infiere desde texto.

El contenido posterior a `|` puede cambiar sin cambiar el codigo. El backend NO debe inferir codigos mediante frases del mensaje humano o tecnico.

Si un codigo existe pero no tiene mensaje tecnico configurado, `mensajeTecnicoResultado` conserva el codigo recibido y retorna:

`DBCODE=<catalog-code>|Mensaje técnico no configurado...`

## Security

`idUsuarioEjecutor` representa `Usuario.id`.

Los SP publicos protegidos que ya declaran `@idUsuarioEjecutor` lo requieren obligatoriamente. `NULL` retorna `GEN_002(idUsuarioEjecutor)` y no omite RBAC/titularidad.

Codigos:

- `SEC_001`: usuario inexistente, inactivo o sin perfil activo requerido.
- `SEC_002`: usuario sin titularidad/autorizacion sobre el recurso.

## Catalog Deploy

`CatalogoParametro`, `CatalogoMensajeUsuario` y `CatalogoMensajeTecnico` son no destructivos:

- si la tabla no existe, se crea con el shape vigente;
- si existe y coincide, el deploy continua;
- si existe y difiere, se detiene con `SCHEMA_CONTRACT_CONFLICT`;
- indices faltantes se crean condicionalmente;
- seeds son idempotentes y no duplican codigos/keys.

## AuditoriaEvento

`AuditoriaEvento` es immutable por contrato:

- si la tabla no existe, se crea con el shape vigente;
- si existe y coincide, el deploy continua;
- si existe y difiere, se detiene con `SCHEMA_CONTRACT_CONFLICT`;
- no se permite auto-migrar mediante `DROP INDEX`, `DROP PK` ni `ALTER COLUMN`;
- indices faltantes pueden crearse condicionalmente.

`occurredAt` conserva tipo `DATETIMEOFFSET` y se valida como timestamp UTC `+00:00`.

## Grupo

Shape real: ver `dbo.Grupo`. No existe `aula`.

SPs relevantes:

`usp_crear_grupo(@idGrupo, @idAsignatura, @idPeriodoAcademico, @codigo, @nombre, @idDocente, @idCorrelacion, @idUsuarioEjecutor = NULL)`

`usp_actualizar_grupo(@idGrupo, @codigo, @nombre, @idDocente, @cupoMaximo, @idCorrelacion, @idUsuarioEjecutor = NULL)`

## Sesion

Shape real: `id`, `nombre`, `numero`, `codigo`, `numeroSemana`, `grupo`, `fechaHoraInicio`, `fechaHoraFin`.

No existen `aula`, `descripcion`, `tipo`, `status`, `estado` ni `cerrada`.

Firmas finales:

`usp_crear_sesion(@idGrupo, @nombre, @fechaHoraInicio, @fechaHoraFin, @idCorrelacion, @idUsuarioEjecutor = NULL)`

`usp_actualizar_sesion(@idSesion, @nombre, @fechaHoraInicio, @fechaHoraFin, @idCorrelacion, @idUsuarioEjecutor = NULL)`

Reglas:

- `idUsuarioEjecutor` obligatorio.
- perfil requerido: `DOCENTE`.
- titularidad se resuelve desde `Usuario.id -> Docente.id -> Grupo/Sesion`.
- `fechaHoraInicio` obligatoria.
- `fechaHoraFin` obligatoria.
- `fechaHoraFin > fechaHoraInicio`.
- update es PUT completo para fechas; `NULL` no conserva valor anterior.
- sesion inexistente retorna `SES_001`.
- regla temporal invalida retorna `SES_004`.
- `usp_cerrar_sesion` es legacy no soportado: retorna `SES_003`, `estadoResultado = 0`, sin escrituras.
- `Sesion.numero`: unico dentro de `grupo` (`UX_Sesion_Grupo_Numero`).
- generacion de `numero`: `COALESCE(MAX(numero), 0) + 1` por grupo (no `COUNT(*)`).
- concurrencia: `numero`/`codigo` se calculan dentro de la misma transaccion protegida con `UPDLOCK, HOLDLOCK` sobre `dbo.Sesion`, tanto en `usp_crear_sesion` como en `usp_generar_sesiones_grupo`.

### Sesion.codigo

- unico dentro de `grupo` (`UX_Sesion_Grupo_Codigo`).
- contrato: string opaco. Los consumidores (backend/frontend) deben tratarlo como identificador de correlacion y **no** inferir reglas de negocio a partir de su formato.
- NO se garantiza que todo `codigo` de sesion tenga el formato `SES-*`; el formato depende del SP que lo genera:
  - `usp_crear_sesion` genera actualmente `SES-{numero}` (`SES-01` ... `SES-99` con cero a la izquierda, `SES-100` en adelante sin truncamiento).
  - `usp_generar_sesiones_grupo` puede generar un identificador interno opaco (no necesariamente `SES-*`).

## Temporal

`DATE`: calendario institucional sin timezone.

`TIME`: hora academica local sin timezone.

`DATETIME2`: instante UTC target cuando representa eventos.

`DATETIMEOFFSET`: auditoria tecnica con offset explicito.

Parametros:

- `TIEMPO/ZONA_HORARIA_IANA`
- `TIEMPO/ZONA_HORARIA_SQLSERVER`
- `TIEMPO/ALMACENAMIENTO_INSTANTES`

`usp_generar_sesiones_grupo` combina fecha local de periodo + hora local de horario, convierte con `AT TIME ZONE <TIEMPO/ZONA_HORARIA_SQLSERVER> AT TIME ZONE 'UTC'`, persiste `DATETIME2` UTC y no depende del timezone del host ni de offsets hardcodeados.

## Attendance Golden Path

SP: `usp_registrar_asistencias_sesion`

Request: `idSesion`, `asistenciaJSON`, `idCorrelacion`, `idUsuarioEjecutor`.

Item JSON exacto: `idEstudiante`, `estado`.

Estados validos: `AN`, `SJC`, `EX`.

Reglas:

- JSON no nulo, valido, top-level array.
- Lote no vacio.
- Cada elemento es objeto con exactamente `idEstudiante` y `estado`.
- Sin estudiantes duplicados.
- Lote parcial permitido.
- Estudiante omitido = sin registro automatico.
- Matricula activa: `EstudianteGrupo.estado.codigo = 'A'`.
- Docente ejecutor debe ser titular del grupo de la sesion.
- Validar todo antes de escribir.
- Escritura atomica e idempotente.
- Concurrente sobre la misma sesion/estudiante termina en una sola cabecera y un solo detalle.
- `AN -> asistio = 1`.
- `SJC -> asistio = 0`.
- `EX -> asistio = 0`.

## Read Contract

Lectura via views: `uv_asistencia`, `uv_detalle_asistencia`, `uv_razon_causa`.

El codigo estable para backend es `uv_detalle_asistencia.codigoRazonCausa`.

Las views devuelven filas persistidas; no crean filas para estudiantes sin registro.

La ausencia de fila en las views de asistencia no equivale a `AN`; solamente una fila persistida con razon `AN` representa asistencia.

## Golden Path Read Projections

Shape exacto expuesto por las views de lectura del Golden Path (`SELECT *` debe devolver exactamente estas columnas, en este orden):

`uv_horario_docente`:

- `id`
- `idDocente`
- `idGrupo`
- `codigoMateria`
- `nombreMateria`
- `seccion`
- `dia`
- `horaInicio`
- `horaFin`
- `totalEstudiantes`

NO `aula`.

`uv_sesion`:

- `id`
- `nombre`
- `numero`
- `codigo`
- `numeroSemana`
- `idGrupo`
- `codigoGrupo`
- `nombreGrupo`
- `fechaHoraInicio`
- `fechaHoraFin`

`uv_estudiante_grupo`:

- `id`
- `idEstadoEstudiante`
- `nombreEstadoEstudiante`
- `codigoEstadoEstudiante`
- `idEstudiante`
- `nombreCompletoEstudiante`
- `idGrupo`
- `codigoGrupo`
- `nombreGrupo`

`uv_asistencia`:

- `id`
- `idEstudianteGrupo`
- `idSesion`

`uv_detalle_asistencia`:

- `id`
- `codigo`
- `idAsistencia`
- `asistio`
- `idRazonCausa`
- `nombreRazonCausa`
- `codigoRazonCausa`
- `fechaHoraInicio`
- `fechaHoraFin`

## Persistence Invariants

Una `Asistencia` maxima por `(estudianteGrupo, sesion)`.

Un `DetalleAsistencia` maximo por `asistencia`.

`RazonCausa.codigo` unico.

## Error/Catalog

- `ATT_001`: payload JSON invalido.
- `ATT_002`: lote vacio.
- `ATT_003`: estudiante duplicado en lote.
- `RC_001`: estado de asistencia invalido.
- `SES_001`: sesion inexistente.
- `SES_003`: cierre de sesion no soportado.
- `SES_004`: ventana temporal de sesion invalida.
- `GEN_002`: input obligatorio ausente/invalido.
- `EST_004`: estudiante no pertenece activamente al grupo de la sesion.

## Cache Source Contract

`uv_parametro` expone al menos:

- `grupo`
- `clave`
- `valor`
- `estaActivo`
- `fechaModificacion`

`uv_mensaje_usuario` y `uv_mensaje_tecnico` exponen al menos:

- `codigo`
- `contenido`
- `estaActivo`
- `fechaModificacion`

`fechaModificacion` se valida con semantica UTC target. Este contrato no implementa Redis; solo congela el source-of-truth DB para cache futura.

## Traceability

Todos los SP publicos retornan `idCorrelacion`.

Auditoria DB mantiene shape de `AuditoriaEvento`; el Golden Path no duplica auditoria dentro del SP.

## Golden Path Object Inventory

SPs:

- `usp_registrar_asistencias_sesion`
- `usp_sincronizar_asistencia_estudiante_interno`
- `usp_validar_permiso_rbac_usuario_interno`
- `usp_validar_titularidad_jerarquica_interno`
- `usp_validar_sesion_exista_por_id_interno`
- `usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno`
- `usp_obtener_mensaje_catalogo`

Views:

- `uv_asistencia`
- `uv_detalle_asistencia`
- `uv_razon_causa`
- `uv_docente_identidad`
- `uv_grupo`
- `uv_sesion`
- `uv_parametro`
- `uv_mensaje_usuario`
- `uv_mensaje_tecnico`

Functions:

- `ufn_obtener_parametro`
- `ufn_obtener_parametro_guid`
- `ufn_obtener_parametro_texto`
- `ufn_obtener_parametro_int`
- `ufn_obtener_detalle_error`

## Local Development Baseline

Container:

`sql_server_asistencias`

Database:

`gestionasistenciadb`

State:

`ALIGNED_WITH_FROZEN_BASELINE`

Temporary validation container:

`REMOVED`

DBCODE:

`ENABLED`

Golden Path:

`FROZEN`

Backend integration target:

`sql_server_asistencias / gestionasistenciadb`

## Validation

Final DB gate on official local development database `sql_server_asistencias / gestionasistenciadb`:

- `TOTAL_EXPECTED=127`
- `TOTAL_EXECUTED=128`
- `PASSED=127`
- `FAILED=0`
- `SKIPPED=1`
- `ALLOWED_SKIPPED=1`
- `CRITICAL_MISSING=0`
- `SQLCMD_EXIT_CODE=0`
- `SQL_ERROR_COUNT=0`
- `UNAUTHORIZED_SKIPS=0`
- `@@TRANCOUNT=0`

Only allowed skip: `XACT_STATE_MINUS_ONE_RUNTIME`.

Additional final checks on official local development database:

- `DBCODE SEC_001=PASS`
- `DBCODE SEC_002=PASS`
- `GHOST_COLUMN_COUNT=0`
- `ATTENDANCE_CONCURRENT_UPSERT=PASS`
- `SESSION_SEQUENCE_USES_MAX_NOT_COUNT=PASS`

Table shape report:

- `ADDED_COLUMNS=0`
- `REMOVED_COLUMNS=0`
- `RENAMED_COLUMNS=0`
- `TYPE_CHANGES=0`
- `NULLABILITY_CHANGES=0`

---

DB_CONTRACT_VERSION: v1

GENERATED_FROM_COMMIT: UNCOMMITTED_WORKTREE

GENERATED_AT_UTC: 2026-09-23T18:52:28Z

DB_GATE_RESULT: PASS_ON_OFFICIAL_LOCAL_DB

TABLE_SHAPE_HASH: 337d39f7997e8b224028e20b194be15918c5136b1fa55ff8b40f9f768efe43d1
