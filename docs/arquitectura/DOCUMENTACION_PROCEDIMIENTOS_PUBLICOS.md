# Documentación Técnica de Arquitectura: Procedimientos Almacenados Públicos / Orquestadores (Sin Sufijo _interno)

## Generalidades del Estándar Canónico para Procedimientos Públicos

Esta documentación especifica la arquitectura, reglas de negocio, contrato de firma, estructura del resultset unificado y flujo de control para **todos los Procedimientos Almacenados Públicos u Orquestadores** (aquellos sin el sufijo `_interno`) en la base de datos `gestionasistenciadb`.

### Reglas Estructurales Obligatorias (Modelo Canónico)
1. **Firma de Cabecera Sin Parámetros OUTPUT**:
   - Los procedimientos públicos/orquestadores NO llevan parámetros de salida (`OUTPUT`) en su firma de cabecera.
   - Todo parámetro de entrada de tipo `UNIQUEIDENTIFIER` (UUID) inicia obligatoriamente con el prefijo `id` (`@idTipoIdIdentificacion`, `@idGrupo`, `@idCorrelacion`, `@idEstudianteGrupo`, `@idGrupoSesion`, `@idEstadoAsistencia`, `@idEstudiante`, `@idSesion`).
2. **Zona de Declaración e Inicialización (`AS` ... `BEGIN`)**:
   - Declaraciones con `DECLARE` ubicadas **exclusivamente en la cabecera: después del `AS` y antes del primer `BEGIN`**.
   - Inicialización de GUIDs por defecto utilizando `dbo.ufn_obtener_parametro_guid(@variable, 'GENERAL', 'GUID_DEFECTO_CORRELACION')`.
   - Limpieza de texto únicamente mediante `TRIM(@variable)`.
   - **PROHIBIDO EL USO DE `ISNULL` O `COALESCE`**.
   - Variables locales de respuesta inicializadas internamente:
     ```sql
     DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
     DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
     DECLARE @estadoResultado BIT = 1;
     ```
3. **Flujo Lógico Estandarizado de Gestión de Entidades**:
   - Consultar si existe en la vista correspondiente (`uv_...`).
   - Si existe: validar estado activo y actualizar datos pertinentes.
   - Si no existe: invocar al procedimiento interno de sincronización/creación (`*_interno`).
4. **Estructura de Bloques y Documentación Paso a Paso**:
   - Inicio del cuerpo con `BEGIN SET NOCOUNT ON; BEGIN TRY ... END TRY BEGIN CATCH ... END CATCH`.
   - Comentarios estructurados por pasos (`-- PASO 1: ...`, `-- PASO 2: ...`).
   - Todo `IF` lleva explícitamente `BEGIN` y `END`.
5. **Consumo Centralizado del Catálogo de Mensajes**:
   - Invocación a `dbo.usp_obtener_mensaje_catalogo` concatenando `' Correlacion: ' + CAST(@idCorrelacionDefecto AS NVARCHAR(50))` al mensaje técnico.
   - Manejo de excepciones en bloque `CATCH` invocando `'SYS_001'` y capturando la traza mediante `dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto)`.
6. **Bloque Final Obligatorio de Retorno (Resultset Unificado)**:
   ```sql
   SELECT
       idCorrelacion           = @idCorrelacionDefecto,
       mensajeUsuarioResultado = @mensajeUsuarioResultado,
       mensajeTecnicoResultado = @mensajeTecnicoResultado,
       estadoResultado         = @estadoResultado;
   ```

---

## Catálogo de Procedimientos Públicos / Orquestadores (providers DB de la fase de alineación)

---

### 1. `dbo.usp_registrar_estudiante_en_grupo` (provider público de matrícula)
> **Contrato vigente (fase de alineación DB, 2026-10-07).** Es el único nombre público de la unidad de matrícula. `usp_matricula_grupo` **no** es un objeto válido: ese texto solo existe como nombre corto del SAVEPOINT `sp_matricula_grupo`. El nombre `..._usuario_no_existente` fue retirado en LB-002.1C-A.

- **Consumidor**: backend, `POST /api/v1/grupos/{grupoId}/estudiantes`. El backend invoca únicamente este SP; nunca un `_interno`.
- **Caso de uso**: matrícula completa de un estudiante en un grupo: identidad (reutilizar o crear), `Estudiante`, `EstudiantePrograma` y `EstudianteGrupo`.
- **Parámetros de entrada**:
  - `@idGrupo UNIQUEIDENTIFIER`, `@numeroIdentificacion INT`
  - `@primerNombre`, `@segundoNombre` `NVARCHAR(50)`; `@primerApellido`, `@segundoApellido` `NVARCHAR(50)`
  - `@correo NVARCHAR(100)`, `@password NVARCHAR(500)`
  - `@idCorrelacion UNIQUEIDENTIFIER`
  - `@idUsuarioEjecutor UNIQUEIDENTIFIER`: **obligatorio**. Sin default; si llega `NULL`, `GEN_002` y cero escrituras.
  - `@idTipoIdIdentificacion UNIQUEIDENTIFIER`: **obligatorio**. Sin default ni fallback a `CC`. `NULL` → `GEN_002`; inexistente → `GEN_001`; cero escrituras.
- **Firma**: sin parámetros `OUTPUT`.
- **Resultset**: 1 fila, 4 columnas (`idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`).
- **Roles (RBAC)**: `DOCENTE` o `COORDINADOR`. El `ADMINISTRADOR` **no** está autorizado: no hay bypass administrativo (`SEC_001`).
- **Titularidad (`SEC_002`)**, en OR:
  1. `DOCENTE` titular del grupo → `usp_validar_titularidad_jerarquica_interno` con `tipoEntidadPadre = 'GRUPO'`, `idEntidadPadre = @idGrupo`.
  2. `COORDINADOR` del programa al que pertenece el grupo → mismo helper con `tipoEntidadPadre = 'PROGRAMA'`.
  - Un usuario con ambos perfiles basta con cumplir una de las dos reglas. Ninguna cumplida → `SEC_002`, cero escrituras.
  - El programa del grupo se resuelve por vistas: `uv_grupo` → `uv_asignatura.idSemestrePlanEstudio` → `uv_semestre_plan_estudio.idPrograma`.
- **Identidad (sin sobrescribir credenciales ni fusionar usuarios)**: se busca por correo y por `(idTipoIdIdentificacion, numeroIdentificacion)` en `uv_usuario`.
  - Ambas claves apuntan al mismo usuario → se reutiliza; **no** se modifica su `password`.
  - Ninguna existe → se crea `Usuario` (`usp_sincronizar_usuario_interno`) y `Estudiante` si falta (`usp_sincronizar_estudiante_interno`).
  - Cualquier otro caso (solo una clave coincide, o las claves apuntan a usuarios distintos) → `IDN_001`, cero escrituras.
  - Decisión: un único acierto implica contradicción entre el dato solicitado y el usuario almacenado, por lo que no se reutiliza. Esto cambia el comportamiento previo de reutilizar por correo solamente.
- **Transacción (ownership)**: sin transacción externa, el SP abre y cierra la propia. Con transacción externa, usa `SAVE TRANSACTION sp_matricula_grupo`. Nunca confirma ni revierte una transacción ajena. Si la transacción externa queda condenada (`XACT_STATE() = -1`) y ya no admite savepoint, el SP propaga el error (`THROW`) al propietario para que la revierta completa.
- **Procedimientos internos invocados** (ninguno expuesto): `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_tipo_identificacion_exista_por_id_interno`, `usp_validar_permiso_rbac_usuario_interno`, `usp_validar_grupo_exista_por_id_interno`, `usp_validar_titularidad_jerarquica_interno`, `usp_validar_cupo_disponible_grupo_interno`, `usp_sincronizar_usuario_interno`, `usp_sincronizar_estudiante_interno`, `usp_registrar_estudiante_en_grupo_interno`.
- **Códigos DBCODE usados**: `SEC_001` (rol), `SEC_002` (titularidad), `GEN_002` (parámetro obligatorio), `GEN_001` (tipo de identificación inexistente), `IDN_001` (conflicto de identidad), `EST_001` (estudiante no resoluble), `GEN_004` (éxito, emitido por el `_interno` de matrícula), `SYS_001` (error inesperado).
- **Cambios de contrato respecto de HEAD**: se elimina `ADMINISTRADOR`; `@idUsuarioEjecutor` e `@idTipoIdIdentificacion` pasan a obligatorios; la titularidad se valida antes de la capacidad y de cualquier escritura.

### 2. `dbo.usp_registrar_docente_en_grupo_usuario_no_existente`
- **Caso de Uso de Negocio**: Orquestador principal de gestión de docentes. Administra el registro de un docente y su asignación a un grupo académico. Verifica la existencia previa del usuario (actualizando biografía si existe o creándolo vía sincronización si no), habilita el perfil docente e inscribe al docente en el grupo deseado.
- **Parámetros de Entrada**:
  - `@idTipoIdIdentificacion UNIQUEIDENTIFIER`
  - `@numeroIdentificacion INT`
  - `@primerApellido NVARCHAR(255)` / `@segundoApellido NVARCHAR(255)`
  - `@primerNombre NVARCHAR(255)` / `@segundoNombre NVARCHAR(255)`
  - `@correo NVARCHAR(255)`
  - `@password NVARCHAR(500)`
  - `@idGrupo UNIQUEIDENTIFIER`
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Resultset Devuelto**:
  - `idCorrelacion UNIQUEIDENTIFIER`
  - `mensajeUsuarioResultado NVARCHAR(4000)`
  - `mensajeTecnicoResultado NVARCHAR(4000)`
  - `estadoResultado BIT`
- **Procedimientos Internos y Vistas Invocados**:
  - `dbo.usp_validar_id_correlacion_esta_presente_interno`
  - `dbo.uv_usuario`
  - `dbo.usp_validar_usuario_existe_por_id_interno`
  - `dbo.usp_sincronizar_usuario_interno`
  - `dbo.uv_docente_identidad`
  - `dbo.usp_sincronizar_docente_interno`
  - `dbo.usp_registrar_docente_en_grupo_interno`
- **Códigos del Catálogo Consumidos**: `GEN_004`, `SYS_001`.

---

### 3. `dbo.usp_registrar_asistencia_estudiante`
- **Caso de Uso de Negocio**: Orquestador de registro manual de asistencia por estudiante. Permite a los docentes o administradores registrar o actualizar el estado de asistencia de un estudiante matriculado para una sesión específica.
- **Parámetros de Entrada**:
  - `@idEstudianteGrupo UNIQUEIDENTIFIER`: ID de la matrícula del estudiante en el grupo.
  - `@idGrupoSesion UNIQUEIDENTIFIER`: ID de la sesión de clase.
  - `@idEstadoAsistencia UNIQUEIDENTIFIER`: ID del estado/razón causa de asistencia.
  - `@idCorrelacion UNIQUEIDENTIFIER`: ID de correlación de trazabilidad.
- **Resultset Devuelto**:
  - `idCorrelacion UNIQUEIDENTIFIER`
  - `mensajeUsuarioResultado NVARCHAR(4000)`
  - `mensajeTecnicoResultado NVARCHAR(4000)`
  - `estadoResultado BIT`
- **Procedimientos Internos y Vistas Invocados**:
  - `dbo.usp_validar_id_correlacion_esta_presente_interno`
  - `dbo.usp_validar_estudiante_grupo_exista_interno`
  - `dbo.usp_validar_sesion_exista_por_id_interno`
  - `dbo.EstudianteGrupo`, `dbo.RazonCausa`
  - `dbo.usp_sincronizar_asistencia_estudiante_interno`
- **Códigos del Catálogo Consumidos**: `GEN_004`, `SYS_001`.

---

### 4. `dbo.usp_registrar_asistencia_estudiante_autonomo`
- **Caso de Uso de Negocio**: Endpoint público para la auto-gestión de asistencia estudiantil mediante código dinámico. Permite que un estudiante confirme de forma autónoma su asistencia a una sesión de clase validando el código temporal emitido.
- **Parámetros de Entrada**:
  - `@idEstudiante UNIQUEIDENTIFIER`: ID del estudiante.
  - `@idSesion UNIQUEIDENTIFIER`: ID de la sesión de clase.
  - `@codigoVerificacion NVARCHAR(50)`: Código dinámico ingresado por el estudiante.
  - `@idCorrelacion UNIQUEIDENTIFIER`: ID de correlación de trazabilidad.
- **Resultset Devuelto**:
  - `idCorrelacion UNIQUEIDENTIFIER`
  - `mensajeUsuarioResultado NVARCHAR(4000)`
  - `mensajeTecnicoResultado NVARCHAR(4000)`
  - `estadoResultado BIT`
- **Procedimientos Internos y Vistas Invocados**:
  - `dbo.usp_validar_id_correlacion_esta_presente_interno`
  - `dbo.usp_validar_sesion_exista_por_id_interno`
  - `dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno`
  - `dbo.Sesion`
  - `dbo.usp_sincronizar_asistencia_estudiante_interno`
- **Códigos del Catálogo Consumidos**: `VAL_007`, `GEN_004`, `SYS_001`.

---

### 5. `dbo.usp_registrar_asistencias_sesion`
- **Caso de Uso de Negocio**: Orquestador de registro masivo de asistencias por lote JSON. Permite procesar en una sola transacción la lista completa de asistencias para todos los estudiantes matriculados en una sesión de clase.
- **Parámetros de Entrada**:
  - `@idSesion UNIQUEIDENTIFIER`: ID de la sesión de clase.
  - `@asistenciaJSON NVARCHAR(MAX)`: Carga útil en formato JSON con la lista de objetos `[{ "idEstudiante": "...", "estado": "AN|SJC|EX" }]`. **Estados públicos: `AN` (asistencia normal), `SJC` (sin justa causa), `EX` (excusa)**; se normalizan con `TRIM` + `UPPER`. `A`, `F`, `T`, `J`, `ABC`, vacío o ausente son inválidos (`RC_001`); no hay conversión `A → AN` / `F → SJC` en el batch.
  - `@idCorrelacion UNIQUEIDENTIFIER`: ID de correlación de trazabilidad.
  - `@idUsuarioEjecutor UNIQUEIDENTIFIER = NULL`: **`Usuario.id`** del docente autenticado (no `Docente.id`). **Requerido semánticamente**: *opcional en firma ≠ opcional en contrato*. `NULL` u omitido → `estadoResultado = 0` (`GEN_002`, campo `idUsuarioEjecutor`), sin escrituras y sin saltarse RBAC/titularidad.
- **Resultset Devuelto** (una única fila, sin cambios):
  - `idCorrelacion UNIQUEIDENTIFIER`
  - `mensajeUsuarioResultado NVARCHAR(4000)`
  - `mensajeTecnicoResultado NVARCHAR(4000)`
  - `estadoResultado BIT`
- **Seguridad**: RBAC perfil `DOCENTE` y titularidad de la sesión (`Sesion → Grupo → Docente.id → uv_docente_identidad → idUsuario = @idUsuarioEjecutor`).
- **Atomicidad**: el lote se valida completo antes de escribir; un fallo revierte todo el lote (transacción propia o `SAVE TRANSACTION` bajo transacción externa).
- **RazonCausa**: catálogo cerrado; ningún código desconocido crea filas en `dbo.RazonCausa`.
- **Lectura**: el estado se consulta vía `dbo.uv_detalle_asistencia.codigoRazonCausa` (y `dbo.uv_razon_causa.codigo`).
- **Procedimientos Internos y Vistas Invocados**:
  - `dbo.usp_validar_id_correlacion_esta_presente_interno`
  - `dbo.usp_validar_permiso_rbac_usuario_interno`
  - `dbo.usp_validar_sesion_exista_por_id_interno`
  - `dbo.usp_validar_titularidad_jerarquica_interno` (`SESION`)
  - `OPENJSON`
  - `dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno`
  - `dbo.usp_sincronizar_asistencia_estudiante_interno`
- **Códigos del Catálogo Consumidos**: `GEN_002`, `RC_001`, `SES_001`, `VAL_003`, `EST_004`, `GEN_004`, `SYS_001`.
- Detalle completo: [`docs/stored-procedures/usp_registrar_asistencias_sesion.md`](docs/stored-procedures/usp_registrar_asistencias_sesion.md).

---

### 6. `dbo.usp_generar_sesiones_grupo`
- **Caso de Uso de Negocio**: Orquestador masivo de planificación académica. Genera automáticamente el calendario de sesiones de clase recurrentes para un grupo a lo largo de todo su periodo académico, basándose en la configuración de franjas horarias y días de la semana.
- **Parámetros de Entrada**:
  - `@idGrupo UNIQUEIDENTIFIER`: ID del grupo académico.
  - `@idCorrelacion UNIQUEIDENTIFIER`: ID de correlación de trazabilidad.
- **Resultset Devuelto**:
  - `idCorrelacion UNIQUEIDENTIFIER`
  - `mensajeUsuarioResultado NVARCHAR(4000)`
  - `mensajeTecnicoResultado NVARCHAR(4000)`
  - `estadoResultado BIT`
- **Procedimientos Internos y Vistas Invocados**:
  - `dbo.usp_validar_id_correlacion_esta_presente_interno`
  - `dbo.usp_validar_grupo_exista_por_id_interno`
  - `dbo.usp_validar_horarios_grupo_interno`
  - `dbo.usp_validar_fechas_periodo_academico_interno`
  - `dbo.Grupo`, `dbo.PeriodoAcademico`, `dbo.Horario`, `dbo.Dia`, `dbo.Sesion`
- **Códigos del Catálogo Consumidos**: `GEN_004`, `SYS_001`.

---

## Verificación de Integridad y Despliegue

Todos los procedimientos listados en esta documentación han sido compilados y probados exitosamente en la base de datos `gestionasistenciadb` mediante la ejecución del script `deploy_schema.ps1`.

---

## Alineación de providers públicos (fase DB, 2026-10-07)

**Regla de arquitectura.** `BACKEND → SP público → SP _interno (si aplica) → tablas / vistas / funciones`. Los procedimientos `_interno` son composición SQL y nunca son contrato del backend. El nombre del archivo debe coincidir con el único objeto que crea (`SP_FILENAME_OBJECT_MISMATCH = 0`, comprobado en `test_summary.ps1`).

**Nombres exactos** (`PUBLIC_SP_NAMES_CORRECT`): `usp_registrar_estudiante_en_grupo`, `usp_sincronizar_usuario`, `usp_registrar_asistencia_estudiante_autonomo`, `usp_radicar_solicitud_revision_asistencia`, `usp_resolver_solicitud_revision_asistencia`, `usp_ejecutar_cierre_masivo_periodo`, `usp_cerrar_sesion`, `usp_registrar_o_actualizar_plan_estudio`. Los nombres cortos (`usp_matricula_grupo`, `usp_asistencia_autonomo`, `usp_cierre_masivo`) solo pertenecen a SAVEPOINTs o variables locales.

### Sincronización pública de usuario: `dbo.usp_sincronizar_usuario`
- Orquestador sobre `dbo.usp_sincronizar_usuario_interno`. Sin parámetros `OUTPUT`. Resultset canónico de 1 fila y 4 columnas.
- Parámetros: `@idTipoIdIdentificacion`, `@numeroIdentificacion`, `@primerApellido`, `@segundoApellido`, `@primerNombre`, `@segundoNombre`, `@correo`, `@password`, `@idCorrelacion`.
- Verificado por `USER_SYNC_PUBLIC_PROVIDER` (éxito revertido dentro de transacción externa) y `USER_SYNC_PUBLIC_INVALID` (correo inválido: estado 0, cero escrituras).

### Asistencia autónoma: `dbo.usp_registrar_asistencia_estudiante_autonomo`
- Atomicidad de la unidad `Asistencia` + `DetalleAsistencia` (TD-056). Patrón owner/savepoint: `BEGIN TRANSACTION` si no hay transacción externa; `SAVE TRANSACTION sp_asistencia_autonomo` si la hay. Nunca confirma ni revierte una transacción ajena.
- Verificado por `AUTONOMOUS_ATOMIC_SAVEPOINT` y `AUTONOMOUS_ATOMIC_OWNER`: fallo forzado después de insertar la cabecera y antes del detalle (un `CHECK`, no un trigger), con residuos `Asistencia = 0` y `DetalleAsistencia = 0`.

### Solicitudes de revisión de asistencia (TD-057)
- Estados de `dbo.Estado.codigo` (`CHAR(1)`), sembrados idempotentemente en `schema/seed/06_estado.sql`: **`P` = Pendiente**, **`A` = Aprobada/Aceptada**, **`R` = Rechazada**. Ningún código de cuatro letras (`PEND`, `APRO`, `RECH`).
- `usp_radicar_solicitud_revision_asistencia`: busca **exclusivamente** `codigo = 'P'`. Si falta → `CAT_001`, estado 0, cero inserciones. Sin fallback `TOP 1`.
- `usp_resolver_solicitud_revision_asistencia`: `APROBADA → A`, `RECHAZADA → R`. Si falta el código → `CAT_001`, estado 0; la solicitud conserva su estado.
- Verificado por `REVIEW_STATE_RADICAR_P`, `REVIEW_STATE_APROBAR_A`, `REVIEW_STATE_RECHAZAR_R`, `REVIEW_MISSING_P_CONTROLLED`, `REVIEW_MISSING_A_CONTROLLED`, `REVIEW_MISSING_R_CONTROLLED`.

### Cierre masivo: `dbo.usp_ejecutar_cierre_masivo_periodo` (TD-058)
- Opera **exclusivamente** sobre el periodo solicitado. Sin fallback al periodo más reciente.
- Código ausente → `GEN_002`; código inexistente → `PER_001`; en ambos casos estado 0 y cero escrituras.
- Verificado por `MASS_CLOSE_UNKNOWN_PERIOD_ZERO_WRITES` (conteos y checksums de `PeriodoAcademico`, `Grupo`, `EstudianteGrupo`, `AuditoriaEvento`, `DetalleAsistencia` antes y después).

### Cierre de sesión: `dbo.usp_cerrar_sesion` (TD-039)
- Firma confirmada: `(@idSesion UNIQUEIDENTIFIER, @idDocente UNIQUEIDENTIFIER, @idCorrelacion UNIQUEIDENTIFIER, @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL)`.
- Contrato vigente: legacy / no soportado → `SES_003`, estado 0, cero escrituras. No implementa cierre funcional en esta fase.
- Verificado por `SESSION_CLOSE_SIGNATURE`.

### Plan de estudio: `dbo.usp_registrar_o_actualizar_plan_estudio` (TD-043 STUDY_PLAN_PROVIDER)
- **Modelo real de `dbo.PlanEstudio`**: `(id UNIQUEIDENTIFIER, programa UNIQUEIDENTIFIER, inp INT, estado BIT)`. **No** existen columnas `codigo` ni `nombre`; el plan se identifica por `inp` (número de plan), no por un texto. El SP público queda alineado exactamente con este modelo: no se inventan campos que no existen físicamente.
- **Parámetros**: `@idPlanEstudio UNIQUEIDENTIFIER` (obligatorio, sin fallback a GUID por defecto), `@idPrograma UNIQUEIDENTIFIER`, `@inp INT`, `@idCorrelacion UNIQUEIDENTIFIER`. Sin parámetros `OUTPUT`.
- **Lecturas**: `dbo.uv_plan_estudio` (vista pública). **Escrituras**: `dbo.PlanEstudio`.
- **Upsert determinista** por `@idPlanEstudio`: si el id existe, `UPDATE`; si no, `INSERT` (`estado = 1`). Idempotente: repetir la misma llamada produce el mismo estado final.
- **Validaciones**: `idPlanEstudio` ausente → `GEN_002`; `inp` ausente o no positivo → `PLA_001`; programa inexistente en `uv_programa` → `PROG_001`. Todas con estado 0 y cero escrituras. Sin regla de unicidad `(programa, inp)`: no está respaldada por una restricción `UNIQUE` del esquema ni por un contrato previo validado.
- **Resultset**: 1 fila, 4 columnas canónicas (`idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`).
- **Transacción**: una única sentencia de escritura (`UPDATE` o `INSERT`), atómica por sí misma; sin transacción propia ni savepoint.
- Verificado por `PLAN_ESTUDIO_CREATE`, `PLAN_ESTUDIO_UPDATE`, `PLAN_ESTUDIO_PROGRAM_NOT_FOUND`, `PLAN_ESTUDIO_INP_INVALID`, `PLAN_ESTUDIO_INP_NULL`, `PLAN_ESTUDIO_CANONICAL_RESULT` (`test/test_usp_registrar_o_actualizar_plan_estudio.sql`).
- **Backend**: contrato DB listo; el backend se adapta a esta firma en una fase posterior (no se modifica en esta fase).

### Catálogo de mensajes usado por esta fase
- Nuevos o confirmados: `CAT_001` (contrato de catálogo incompleto), `PER_001` (periodo inexistente), `IDN_001` (conflicto de identidad), `PLA_001` (`inp` inválido).
- Reutilizados sin duplicar: `PROG_001` (programa inexistente), `GRUP_003` (grupo sin programa asociado), `SEC_001`, `SEC_002`, `GEN_001`, `GEN_002`, `GEN_004`, `EST_001`, `SYS_001`.
- Eliminado por duplicado: `PRG_001` (semánticamente igual a `PROG_001`). `usp_registrar_o_actualizar_plan_estudio` usa exclusivamente `PROG_001`; no queda ninguna referencia a `PRG_001` en el repositorio.
