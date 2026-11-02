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

## Catálogo de Procedimientos Públicos / Orquestadores (6 SPs)

---

### 1. `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente`
> **SUPERSEDED (LB-002.1C-A):** este SP fue eliminado de `schema/` en `daeac11` y no existe en la DB. El comando publico vigente es `dbo.usp_registrar_estudiante_en_grupo` con otra firma (sin `@idTipoIdIdentificacion`, con `@idUsuarioEjecutor`) y sin ownership transaccional. Contrato real y matriz de diferencias: `docs/work-items/LB-002.1C-A-db-contract-baseline-recovery/REPORT.md`. El texto siguiente es historico.

- **Caso de Uso de Negocio**: Orquestador principal de auto-registro e inscripción. Permite el registro completo de un estudiante en un grupo académico cuando el usuario no existe previamente en el sistema (o actualiza datos si ya existe), asegurando la creación del usuario, la asignación del perfil estudiante, la inscripción en el grupo y la vinculación al programa académico correspondiente.
- **Parámetros de Entrada**:
  - `@idTipoIdIdentificacion UNIQUEIDENTIFIER`: ID del tipo de documento.
  - `@numeroIdentificacion INT`: Número de identificación.
  - `@primerApellido NVARCHAR(255)` / `@segundoApellido NVARCHAR(255)`
  - `@primerNombre NVARCHAR(255)` / `@segundoNombre NVARCHAR(255)`
  - `@correo NVARCHAR(255)`: Correo electrónico del usuario.
  - `@password NVARCHAR(500)`: Contraseña.
  - `@idGrupo UNIQUEIDENTIFIER`: ID del grupo académico al que se inscribe.
  - `@idCorrelacion UNIQUEIDENTIFIER`: ID de trazabilidad.
- **Resultset Devuelto**:
  - `idCorrelacion UNIQUEIDENTIFIER`: ID de trazabilidad estandarizado.
  - `mensajeUsuarioResultado NVARCHAR(4000)`: Mensaje amigable para el cliente.
  - `mensajeTecnicoResultado NVARCHAR(4000)`: Traza técnica con ID de correlación.
  - `estadoResultado BIT`: Indica 1 para éxito y 0 para fallo.
- **Procedimientos Internos y Vistas Invocados**:
  - `dbo.usp_validar_id_correlacion_esta_presente_interno`
  - `dbo.uv_usuario`
  - `dbo.usp_validar_usuario_existe_por_id_interno`
  - `dbo.usp_sincronizar_usuario_interno`
  - `dbo.uv_estudiante_identidad`
  - `dbo.usp_sincronizar_estudiante_interno`
  - `dbo.usp_registrar_estudiante_en_grupo_interno`
  - `dbo.uv_grupo`, `dbo.uv_asignatura`, `dbo.uv_semestre_plan_estudio`, `dbo.uv_plan_estudio`
  - `dbo.usp_registrar_estudiante_en_programa_interno`
- **Códigos del Catálogo Consumidos**: `ERR_PROGRAMA_GRUPO_NO_ENCONTRADO`, `SUC_REGISTRO_ESTUDIANTE_GRUPO`, `ERR_INESPERADO_REGISTRO_ESTUDIANTE` (`SYS_001`).

---

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

> **ELIMINADO (2026-10-29):** este objeto se borró de `schema/` por no tener uso (migración `migrations/08_eliminar_codigo_sin_uso_up.sql`, work item `docs/work-items/BD-eliminar-codigo-sin-uso/`). El texto siguiente es histórico.
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

## Addendum CC-003G-01 — proveedores consumidos por el backend

Contrato completo, decisiones y limitaciones: `docs/work-items/CC-003G-01-public-user-plan-providers/CONTRACT.md`.

### 7. `dbo.usp_sincronizar_usuario`
- **Caso de uso**: alta idempotente de usuario base para `POST /api/v1/usuarios` (el backend crea luego la cuenta de identidad). Nunca actualiza un usuario existente ni toca su password.
- **Parametros**: `@idTipoIdIdentificacion`, `@numeroIdentificacion`, `@primerApellido`, `@segundoApellido`, `@primerNombre`, `@segundoNombre`, `@correo`, `@password` (hash), `@idCorrelacion`. Sin `@idUsuarioEjecutor` (el endpoint es AUTENTICADO).
- **Flujo**: correlacion, limites de longitud, transaccion propia/savepoint, barrido serializable de unicidad, reintento exacto => exito sin escribir, si no => `usp_sincronizar_usuario_interno`.

### 8. `dbo.usp_registrar_o_actualizar_plan_estudio`
- **Caso de uso**: alta/actualizacion del `inp` de un plan por el COORDINADOR titular del programa (`/api/v1/coordinador/planes-estudio`).
- **Parametros**: `@idPlanEstudio`, `@idPrograma`, `@inp`, `@idCorrelacion`, `@idUsuarioEjecutor` (obligatorio, fail-closed).
- **Flujo**: correlacion, RBAC `COORDINADOR`, titularidad `PROGRAMA`, validaciones de entrada, transaccion propia/savepoint con bloqueo de la fila del programa, upsert por id con unicidad (programa, inp).

---

## Addendum HU081-HU083 / HU096-HU098 / HU060-HU064 / HU104-HU145 (2026-10-25)

Work items: `docs/work-items/HU081-HU082-HU083-plan-estudio-estado-semestres/`, `HU096-HU097-HU098-periodos-academicos/`, `HU064-HU060-HU061-consultas-coordinador/` y `HU104-HU105-HU109-HU119-HU145-lecturas-decano/`. Mensajes en `schema/seed/17_mensajes_plan_estudio.sql` (`PLA_002`..`PLA_006`) y `schema/seed/17_mensajes_periodo_academico.sql` (`PER_001`..`PER_006`).

### Comandos (resultset canónico de 4 columnas, `@idUsuarioEjecutor` obligatorio)

| SP | Caso de uso | RBAC / ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_cambiar_estado_plan_estudio` | HU081 activar/inactivar el plan (`PlanEstudio.estado`) | `COORDINADOR` titular del programa | `PLA_002` |
| `dbo.usp_agregar_semestre_plan_estudio` | HU082 añadir el siguiente semestre (máx. 10) | `COORDINADOR` titular | `PLA_002`, `PLA_003` |
| `dbo.usp_quitar_semestre_plan_estudio` | HU083 quitar el último semestre sin asignaturas | `COORDINADOR` titular | `PLA_002`, `PLA_004`, `PLA_005`, `PLA_006` |
| `dbo.usp_crear_periodo_academico` (reescrito) | HU096 crear período (`codigo`/`anio` derivados de `fechaInicio`) | `ADMINISTRADOR` de institución activa | `PER_002`, `PER_003`, `PER_005` |
| `dbo.usp_actualizar_periodo_academico` | HU097 modificar nombre y fechas | `ADMINISTRADOR` | `PER_001`, `PER_002`, `PER_003`, `PER_005` |
| `dbo.usp_eliminar_periodo_academico` | HU098 eliminar si no tiene grupos | `ADMINISTRADOR` | `PER_001`, `PER_004`, `PER_005`, `PER_006` |

### Consultas (READ_QUERY_RESULTSET; fallas por `THROW`; `SESSION_CONTEXT` capturado y restaurado)

| SP | Caso de uso | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_consultar_estudiantes_facultad_paginado` | HU104/HU105 directorio y búsqueda de estudiantes | facultad del decano ejecutor (`uv_auth_estudiante`) | `VAL_001`, `PAG_001` |
| `dbo.usp_consultar_estudiante_facultad_detalle` | HU105 ficha (matrículas) del estudiante | facultad del decano | `VAL_001` |
| `dbo.usp_consultar_estructura_facultad` | HU109/HU119 Facultad → Programa → Plan | facultad del decano (`uv_auth_facultad`, `uv_auth_programa`) | `VAL_001` |
| `dbo.usp_consultar_sesiones_facultad_paginado` | HU145 cronograma de sesiones por rango | facultad del decano (`uv_auth_sesion`, `uv_auth_grupo`) | `VAL_001`, `PAG_001` |

HU064/HU060/HU061 consumen los SP existentes `usp_consultar_grupos_paginado`, `usp_consultar_sesiones_grupo_paginado` y `usp_consultar_asistencias_sesion_paginado` (sin cambios; ámbito por programa vía `uv_auth_grupo`/`uv_auth_sesion`).

Permisos aditivos: `schema/security/rol_asistencias_runtime_hu081_hu083.sql`, `_hu096_hu098.sql`, `_hu060_hu064.sql` y `_hu104_hu145.sql`. Pruebas: `test/test_usp_plan_estudio_estado_semestres.sql`, `test/test_usp_periodo_academico_gestion.sql`, `test/test_consultas_coordinador_programa.sql` y `test/test_consultas_decano_facultad.sql`, registradas en `test_suite.sql`.

## Addendum HU010/HU011 — consulta de solicitudes de revisión del estudiante (2026-10-26)

Work item: `docs/work-items/HU010-HU011-consulta-reclamos-estudiante/` (contrato HTTP en el work item homónimo del backend).

| SP | Caso de uso | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_consultar_solicitudes_revision_estudiante` | HU010/HU011 "Mis Reclamos": solicitudes propias con estado, respuesta del docente y soporte vinculado; READ_QUERY_RESULTSET + `totalRegistros`, paginación acotada (1..100, sin `PAG_001`) | ownership en tablas base: `SolicitudRevisionAsistencia → Asistencia → EstudianteGrupo → Estudiante.usuario = @idUsuarioEjecutor` | `VAL_001` |

Parámetros: `@idUsuarioEjecutor`, `@idCorrelacion`, `@codigoEstado` (P/A/R, opcional), `@numeroPagina`, `@tamanoPagina`. Resultset con las mismas columnas y tipos que `usp_consultar_solicitudes_revision_docente` (LB-004D, R2); el soporte se resuelve con el parámetro `ARCHIVO.ESTADO_ADJUNTO`. Permiso aditivo: `schema/security/rol_asistencias_runtime_hu010_hu011.sql`. Prueba: `test/test_consultas_reclamos_estudiante.sql` (E-01..E-08). Sin cambios de tablas ni de objetos congelados.

## Addendum HU051 — retiro de un estudiante del grupo por el docente titular (2026-10-27)

Work item: `docs/work-items/HU051-retirar-estudiante-grupo/` (contrato HTTP en el work item homónimo del backend).

| SP | Caso de uso | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_retirar_estudiante_grupo` | Comando (resultset canónico): matrícula activa → `I` (inactivo), auditoría `RETIRO_ESTUDIANTE_GRUPO` con el motivo en `AuditoriaEvento.metadata`; asistencias intactas; cupo liberado | docente titular (`Grupo.docente → Docente.usuario`) | `GEN_002`, `RET_001` grupo inexistente o ajeno, `RET_002` sin matrícula activa, `RET_003` período terminado (fecha local `TIEMPO.ZONA_HORARIA_SQLSERVER`), `RET_004` motivo 1..500, `RET_005` éxito |
| `dbo.usp_consultar_destinatarios_retiro_estudiante_grupo` | Lectura: ESTUDIANTE, DOCENTE y COORDINADOR del programa con nombre, correo y contexto del grupo para el aviso | docente titular (otro ejecutor ⇒ 0 filas) | `VAL_001` (THROW) |

Permiso aditivo: `schema/security/rol_asistencias_runtime_hu051.sql`. Mensajes: `schema/seed/21_mensajes_retiro_estudiante_grupo.sql`. Prueba: `test/test_usp_retirar_estudiante_grupo.sql` (R-01..R-09). Sin cambios de tablas ni de objetos congelados.

## Addendum HU053/HU054/HU055 — solicitudes de ingreso a un grupo (2026-10-27)

Work item: `docs/work-items/HU053-HU054-HU055-solicitudes-ingreso-grupo/` (tabla nueva `SolicitudIngresoGrupo` aprobada por John; análisis de impacto en el PLAN).

| SP | Caso de uso | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_registrar_solicitud_ingreso_grupo` | Comando: el estudiante solicita el ingreso (P) | estudiante ejecutor (`Estudiante.usuario`) | `GEN_002`, `SIG_001..SIG_006` |
| `dbo.usp_resolver_solicitud_ingreso_grupo` | Comando + `codigoEstadoResultante`: ACEPTAR (con cupo A y matrícula vía `usp_registrar_estudiante_en_grupo_interno`; sin cupo E) o RECHAZAR con motivo (R); bloqueo `UPDLOCK, HOLDLOCK` del grupo | docente titular | `SIG_003`, `SIG_004`, `SIG_007..SIG_014` |
| `dbo.usp_retirar_solicitud_ingreso_grupo` | Comando: el estudiante retira su solicitud abierta (X) | estudiante propietario | `SIG_007`, `SIG_008`, `SIG_015` |
| `dbo.usp_consultar_solicitudes_ingreso_grupo_docente` | Lectura paginada: bandeja del grupo en orden de llegada con `posicionEspera` y cupo | docente titular | `VAL_001` (THROW) |
| `dbo.usp_consultar_solicitudes_ingreso_estudiante` | Lectura paginada: mis solicitudes | estudiante | `VAL_001` (THROW) |
| `dbo.usp_consultar_destinatarios_solicitud_ingreso_grupo` | Lectura: ESTUDIANTE y DOCENTE para los avisos | estudiante propietario o docente titular | `VAL_001` (THROW) |

Permiso aditivo: `schema/security/rol_asistencias_runtime_hu053_hu055.sql`. Semillas: `22_estados_solicitud_ingreso_grupo.sql`, `23_mensajes_solicitud_ingreso_grupo.sql`. Prueba: `test/test_solicitud_ingreso_grupo.sql` (S-01..S-12).

## Addendum HU006 — perfil del usuario autenticado (2026-10-27)

Work item: `docs/work-items/HU006-perfil-usuario/` (contrato HTTP en el work item homónimo del backend). Solo lectura; sin tablas nuevas.

| SP | Caso de uso | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_consultar_perfil_usuario` | Lectura: datos personales (de `uv_usuario`, sin contraseña) y una fila por vínculo: ESTUDIANTE→programa, DOCENTE→programa (tipo de vinculación), COORDINADOR→programa, DECANO→facultad, ADMINISTRADOR→institución; sin vínculos devuelve 1 fila con el vínculo en NULL | solo el usuario ejecutor (no recibe otro id) | `VAL_001` (THROW) |

Permiso aditivo: `schema/security/rol_asistencias_runtime_hu006.sql`. Prueba: `test/test_usp_consultar_perfil_usuario.sql` (P-01..P-03).

## Addendum HU094/HU095 — ficha del docente y consolidado del directorio docente del coordinador (2026-10-27)

Work item: `docs/work-items/HU094-HU095-directorio-docentes-coordinador/` (contrato HTTP en el work item homónimo del backend). Solo lectura; sin cambios de tablas.

| SP | Caso de uso | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_consultar_historial_grupos_docente_programa` | Lectura paginada (HU094): grupos del docente en el programa del coordinador, todos los períodos (filtro opcional), con `estadoPeriodo` VIGENTE/FINALIZADO/PROXIMO (fecha local) y columnas `resumen*` de todo el historial + `totalRegistros` | programa del coordinador ejecutor (`usp_resolver_programa_coordinador_interno`); el docente debe tener vínculo (activo o inactivo) con ese programa | `VAL_001`, `KPI_001`, `GEN_001` (THROW) |
| `dbo.usp_consultar_resumen_docentes_programa` | Lectura (HU095): vínculos activos e inactivos por tipo de vinculación (criterio `uv_docente_programa.estaActivoDocentePrograma`), incluidos los tipos activos sin docentes | programa del coordinador ejecutor | `VAL_001`, `KPI_001` (THROW) |

Permiso aditivo: `schema/security/rol_asistencias_runtime_hu094_hu095.sql`. Pruebas: `test/test_usp_consultar_historial_grupos_docente_programa.sql` (H-01..H-06) y `test/test_usp_consultar_resumen_docentes_programa.sql` (R-01..R-03).

## Addendum HU008 — oferta de grupos del estudiante y regla de inscripción en el programa (2026-10-27)

Work item: `docs/work-items/HU008-oferta-grupos-estudiante/` (contrato HTTP en el work item homónimo del backend). Sin tablas nuevas.

| Objeto | Cambio | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_consultar_oferta_grupos_estudiante` | Lectura paginada nueva: grupos ESP de los programas del estudiante y, si `OFERTA.INCLUIR_TRANSVERSALES = 1`, BAS/INS de su institución, en períodos vigentes/próximos; docente, horario, cupos, `matriculado`, solicitud abierta y `codigoComponente` | estudiante ejecutor (`Estudiante.usuario`; otro rol = 0 filas) | `VAL_001` (THROW) |
| `dbo.usp_registrar_estudiante_en_grupo_interno` / `_autonomo` | Regla de John: solo una asignatura **ESP** crea `EstudiantePrograma`; BAS/INS matriculan sin inscribir en el programa (JOIN a `Componente` con `codigo = 'ESP'`) | sin cambio | sin cambio |
| `CatalogoParametro` `OFERTA.INCLUIR_TRANSVERSALES` | Parámetro nuevo (1 por defecto). `UPDATE ... SET valor = '0'` oculta las transversales de la oferta (solo enlace del docente) | — | — |

Permiso aditivo: `schema/security/rol_asistencias_runtime_hu008.sql`. Seed: `24_parametro_oferta_grupos.sql`. Pruebas: `test/test_usp_consultar_oferta_grupos_estudiante.sql` (O-01..O-05) y `test/test_hu008_regla_inscripcion_programa.sql` (RI-01..RI-03).

## Addendum INT-HU-01 — reactivación de la matrícula retirada al aceptar una solicitud de ingreso (2026-10-28)

`dbo.usp_resolver_solicitud_ingreso_grupo`, ACEPTAR con cupo: si el estudiante tiene una matrícula `I` (retirado, HU051) en el grupo, se reactiva (`I` → `A`), se enlaza en la solicitud y responde `SIG_011` (antes: 409 por duplicado desde la matrícula interna). Sin cambios de firma, resultset ni mensajes. Work item: `docs/work-items/INT-HU-01-reactivar-matricula-retirada/`. Prueba: `test/test_int_hu01_reactivar_matricula_retirada.sql` (RM-01..RM-03).

---

## Addendum REC5 (2026-10-29): índice de SP públicos sin ficha en este documento

La auditoría BD 2026-10-28 encontró 48 SP públicos sin ficha aquí; 10 de ellos (los paginados y por id legacy) se eliminaron el 2026-10-29 por no tener uso, así que el índice lista 38. El endpoint y el rol de cada uno están en `especificacion_sp_endpoints.md` (Addendum REC5). El detalle de reglas y códigos, en el work item de su HU. Propósito tomado del comentario de cabecera del SP.

| SP | Parámetros | Propósito |
|---|---|---|
| `usp_actualizar_area` | `@id, @nombre, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_actualizar_area] Historias de Usuario: HU151 / HU152 Ambito: Administrador Institucional. Modifica el nombre de Area de Conocimiento; el codigo es inmutable. Salida Canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResu… |
| `usp_actualizar_coordinador` | `@idCoordinador, @primerNombre, @segundoNombre, @primerApellido, @segundoApellido, @correo, @idFacultad, @idCorrelacion, @idUsuarioEjecutor` | HU121: edita nombres, apellidos y correo de un coordinador de la facultad del decano ejecutor. Fachada transaccional: valida RBAC y titularidad, y delega la escritura en usp_actualizar_datos_usuario_interno. El documento no se edita. Devuelve idUsuario para qu… |
| `usp_actualizar_docente_programa` | `@idDocente, @idPrograma, @idTipoVinculacion, @primerNombre, @segundoNombre, @primerApellido, @segundoApellido, @idCorrelacion, @idUsuarioEjecutor` | HU092: edita (a) el tipo de vinculacion del vinculo docente-programa y (b) los nombres/apellidos de la persona. Solo se actualizan los parametros no nulos (''/vacio en un segundo nombre o apellido lo limpia). Correo y documento NO se editan aqui (el correo exi… |
| `usp_actualizar_facultad` | `@id, @nombre, @idDecano, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_actualizar_facultad] Historias de Usuario: HU110 (modificar denominacion) y HU117 (reasignar decano) Ambito: Administrador Institucional (Nivel 1 de custodia jerarquica) Semantica: un parametro NULL no se modifica. Al menos uno es obl… |
| `usp_actualizar_programa_academico` | `@idPrograma, @nombre, @idTipoPrograma, @idCoordinador, @idModalidad, @idJornada, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_actualizar_programa_academico] Historia de Usuario: HU077 Ambito: Decano de Facultad. Edicion de nombre, tipo, modalidad, jornada y coordinador de un programa de la facultad del decano. Salida Canonica: (idCorrelacion, mensajeUsuarioR… |
| `usp_actualizar_sesion_v2` | `@idSesion, @nombre, @fechaHoraInicio, @fechaHoraFin, @idCorrelacion, @idUsuarioEjecutor` | UTC-D06-POST-FREEZE: actualizacion v2 (PATCH de reemplazo completo de horas). El backend solo invoca este SP con instantes normalizados a UTC desde RFC3339 con offset explicito (UTC-D02): horas y marca UTC_V2 se escriben en el MISMO UPDATE. Mismos parametros n… |
| `usp_actualizar_tipo_programa` | `@id, @nombre, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_actualizar_tipo_programa] Historias de Usuario: HU154 Ambito: Administrador Institucional. Modifica el nombre de Tipo de Programa; el codigo es inmutable. Salida Canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResulta… |
| `usp_cambiar_estado_area` | `@id, @estaActiva, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_cambiar_estado_area] Historias de Usuario: HU151 / HU152 Ambito: Administrador Institucional. Fija el estado deseado de Area de Conocimiento (idempotente, sin cascada). Salida Canonica: (idCorrelacion, mensajeUsuarioResultado, mensaje… |
| `usp_cambiar_estado_coordinador` | `@idCoordinador, @estaActivo, @idFacultad, @idCorrelacion, @idUsuarioEjecutor` | HU122: activa o desactiva el rol de coordinador de la facultad del decano ejecutor. Regla D3: no se puede desactivar a quien coordina un programa activo (COO_001). Regla D1: Usuario.estado pasa a 0 solo si la persona no conserva otro rol activo; al reactivar v… |
| `usp_cambiar_estado_docente_programa` | `@idDocente, @idPrograma, @estaActivo, @idCorrelacion, @idUsuarioEjecutor` | HU093 (D12): activa o inactiva el VINCULO del docente con el programa del coordinador (DocentePrograma.estado). No toca Usuario.estado, ni el rol Docente, ni los grupos ya asignados, ni la cuenta de identidad. Idempotente. RBAC COORDINADOR + titularidad PROGRA… |
| `usp_cambiar_estado_facultad` | `@id, @estaActiva, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_cambiar_estado_facultad] Historia de Usuario: HU111 (alternar estado operativo de la facultad) Ambito: Administrador Institucional. Recibe el estado deseado (idempotente), sin cascada. Salida Canonica: (idCorrelacion, mensajeUsuarioRe… |
| `usp_cambiar_estado_programa_academico` | `@idPrograma, @estaActivo, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_cambiar_estado_programa_academico] Historia de Usuario: HU078 Ambito: Decano de Facultad. Activa o desactiva un programa de la facultad del decano. Recibe el estado destino (idempotente). Salida Canonica: (idCorrelacion, mensajeUsuari… |
| `usp_cambiar_estado_tipo_programa` | `@id, @estaActivo, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_cambiar_estado_tipo_programa] Historias de Usuario: HU154 Ambito: Administrador Institucional. Fija el estado deseado de Tipo de Programa (idempotente, sin cascada). Salida Canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTec… |
| `usp_clasificar_procedencia_sesion` | `@idSesion, @ambiente, @idManifiesto, @hashEvidencia, @fechaHoraInicioVerificada, @fechaHoraFinVerificada, @fechaHoraInicioUtc, @fechaHoraFinUtc, @idUsuarioAprobador, @idCorrelacion, @idUsuarioEjecutor` | UTC-D06-POST-FREEZE: UNICO camino administrativo para marcar una sesion historica como UTC_OWNER. No es un endpoint del backend: lo ejecuta el owner funcional/DBA con un manifiesto aprobado, sesion por sesion y ambiente por ambiente. Fail-closed: * el ejecutor… |
| `usp_consultar_aforo_grupos_facultad` | `@idUsuarioEjecutor, @idCorrelacion, @numeroPagina, @tamanoPagina, @idPeriodoAcademico, @idPrograma, @soloHabilitados` | usp_consultar_aforo_grupos_facultad (HU144). READ_QUERY_RESULTSET paginado. Solo lectura. Aforo = matriculados activos / cupo maximo (D4); NULL si el cupo es 0. No se recorta por encima de 100 %. @soloHabilitados = 1 (defecto) lista solo grupos habilitados en … |
| `usp_consultar_alerta_temprana_programa` | `@idUsuarioEjecutor, @idCorrelacion, @numeroPagina, @tamanoPagina, @idPeriodoAcademico, @semaforo, @filtroTexto` | usp_consultar_alerta_temprana_programa (HU066, HU070). READ_QUERY_RESULTSET paginado. Solo lectura. Una fila por persona: % = el mayor de sus matriculas activas, faltas = suma, clasificacion = la peor (D6). |
| `usp_consultar_archivo_soporte_autorizado` | `@idArchivoSoporte, @idCorrelacion, @idUsuarioEjecutor` | usp_consultar_archivo_soporte_autorizado  (LB-004D, R1) Clasificacion (DB-GP-001C): NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md Resultset: READ_QUERY_RESULTSET (0..1 fila de datos). NO es un MUTATION_COMMAND_RESULTSET: … |
| `usp_consultar_bitacora_estudiante_programa` | `@idUsuarioEjecutor, @idCorrelacion, @idEstudiante, @numeroPagina, @tamanoPagina, @idPeriodoAcademico` | usp_consultar_bitacora_estudiante_programa (HU067). READ_QUERY_RESULTSET paginado. Solo lectura. Sesiones vencidas de los grupos del programa en los que el estudiante esta (o estuvo) matriculado, la mas reciente primero. asistio = NULL cuando la sesion vencida… |
| `usp_consultar_candidatos_docente_programa` | `@idUsuarioEjecutor, @idCorrelacion, @idPrograma, @busqueda` | usp_consultar_candidatos_docente_programa (HU091, picker de docentes existentes) Resultset: READ_QUERY_RESULTSET con datos MINIMOS (D4, sin correo): idDocente, idUsuario, codigoTipoIdentificacion, numeroIdentificacion, nombreCompleto. Candidato = docente activ… |
| `usp_consultar_comparativa_facultades` | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico` | usp_consultar_comparativa_facultades (HU139). READ_QUERY_RESULTSET sin paginar. Solo lectura. Una fila por facultad de la institucion (activas e inactivas, D4). Mismas definiciones que usp_consultar_kpis_institucion. Orden: ausentismo descendente (NULL al fina… |
| `usp_consultar_comparativa_programas_facultad` | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico` | usp_consultar_comparativa_programas_facultad (HU103). READ_QUERY_RESULTSET sin paginar (D6). Solo lectura. Una fila por programa de la facultad (activos e inactivos, D5). Mismas definiciones que usp_consultar_kpis_decano. Orden: ausentismo descendente (NULL al… |
| `usp_consultar_detalle_solicitud_revision_docente` | `@idSolicitud, @idUsuarioEjecutor, @idCorrelacion` | usp_consultar_detalle_solicitud_revision_docente  (HU035/HU036) Clasificacion (DB-GP-001C): NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md Resultset: READ_QUERY_RESULTSET (0..1 fila con el detalle y la causal de una solici… |
| `usp_consultar_docentes_programa` | `@idUsuarioEjecutor, @idCorrelacion, @idPrograma, @numeroPagina, @tamanoPagina, @busqueda, @estaActivo, @idTipoVinculacion, @idDocente, @idUsuario` | usp_consultar_docentes_programa (HU062 / HU089 / HU063) Resultset: READ_QUERY_RESULTSET (filas de uv_auth_docente_programa + totalRegistros). NO es un MUTATION_COMMAND_RESULTSET. Las fallas de RBAC/titularidad se propagan con THROW (mensaje tecnico de catalogo… |
| `usp_consultar_ficha_estudiante_programa` | `@idUsuarioEjecutor, @idCorrelacion, @idEstudiante` | usp_consultar_ficha_estudiante_programa (HU069). READ_QUERY_RESULTSET (1 fila). Solo campos que existen en la DB (sin telefono, D5). |
| `usp_consultar_kpis_coordinador` | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico` | usp_consultar_kpis_coordinador (HU065, HU070). READ_QUERY_RESULTSET (1 fila). Solo lectura: sin XACT_ABORT. Ambito: el programa que coordina el ejecutor. Todas las cifras salen de las vistas de resumen (ver CONTRACT §1). |
| `usp_consultar_kpis_decano` | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico` | usp_consultar_kpis_decano (HU102, HU106, HU144). READ_QUERY_RESULTSET de una fila. Solo lectura. Estudiante = persona con la peor clasificacion de sus matriculas activas de la facultad (D3). Retencion = (regular + riesgo) / total (D2). Ausentismo = faltas / se… |
| `usp_consultar_kpis_institucion` | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico` | usp_consultar_kpis_institucion (HU133, HU135, HU136, HU138). READ_QUERY_RESULTSET de una fila. Solo lectura. Mismas definiciones que las olas 1 y 2: persona = peor clasificacion de sus matriculas activas; ausentismo ponderado por matricula activa (sesionesEjec… |
| `usp_consultar_programas_academicos` | `@idUsuarioEjecutor, @idCorrelacion, @numeroPagina, @tamanoPagina, @nombre, @estaActivo, @idTipoPrograma` | usp_consultar_programas_academicos (HU108, solo listado de programas) Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas de los comandos. Las fallas de paginacion se propagan con THROW (DBCODE=PAG_001). Ambito: las… |
| `usp_consultar_resumen_asistencia_estudiante_programa` | `@idUsuarioEjecutor, @idCorrelacion, @idEstudiante, @idPeriodoAcademico` | usp_consultar_resumen_asistencia_estudiante_programa (HU069). READ_QUERY_RESULTSET (una fila por matricula). Solo lectura. |
| `usp_consultar_tendencia_ausentismo` | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico, @granularidad` | usp_consultar_tendencia_ausentismo (HU134). READ_QUERY_RESULTSET sin paginar. Solo lectura. Serie temporal del ausentismo del periodo por SEMANA (calendario, inicia el lunes) o MES, segun la hora local institucional (parametro TIEMPO/ZONA_HORARIA_SQLSERVER) de… |
| `usp_crear_area` | `@codigo, @nombre, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_crear_area] Historias de Usuario: HU151 / HU152 Ambito: Administrador Institucional. Alta de Area de Conocimiento. Salida Canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado) |
| `usp_crear_sesion_v2` | `@idGrupo, @nombre, @fechaHoraInicio, @fechaHoraFin, @idCorrelacion, @idUsuarioEjecutor` | UTC-D06-POST-FREEZE: creacion v2. El backend solo invoca este SP despues de normalizar un RFC3339 con offset explicito (perfil UTC-D02) al instante UTC, por lo que las horas recibidas son instantes UTC confirmados: se marcan UTC_V2 en el MISMO INSERT (usp_crea… |
| `usp_crear_tipo_programa` | `@codigo, @nombre, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_crear_tipo_programa] Historias de Usuario: HU154 Ambito: Administrador Institucional. Alta de Tipo de Programa. Salida Canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado) |
| `usp_radicar_solicitud_revision_asistencia_v2` | `@idEstudiante, @idSesion, @categoria, @justificacion, @idArchivoSoporte, @idCorrelacion, @idUsuarioEjecutor` | usp_radicar_solicitud_revision_asistencia_v2  (LB-004D, W2) Radica la solicitud de revision y, si se indica @idArchivoSoporte, vincula el soporte (DRAFT -> ATTACHED) en la MISMA transaccion. La v1 permanece intacta. * Sin @soporteNombre/@soporteUrl: la v2 no c… |
| `usp_registrar_archivo_soporte` | `@idArchivoSoporte, @nombreOriginal, @tipoContenido, @tamanioBytes, @checksumSha256, @idCorrelacion, @idUsuarioEjecutor` | usp_registrar_archivo_soporte  (LB-004D, W1) Registra en estado DRAFT la metadata de un soporte ya almacenado por el backend. El propietario es SIEMPRE @idUsuarioEjecutor (no existe parametro de propietario). El fileId lo genera el backend; la DB no lo genera … |
| `usp_revocar_identidad_externa` | `@emisor, @sujeto, @idCorrelacion` | SEC-BASELINE-017: revoca el vinculo (emisor, sujeto) -> Usuario.id. Idempotente: revocar un vinculo ya revocado responde exito sin cambios. La fila se conserva (estado = 0) para que la identidad revocada no pueda reutilizarse ni reasignarse a otra cuenta sin u… |
| `usp_vincular_docente_programa` | `@idDocente, @idUsuario, @idTipoIdentificacion, @numeroIdentificacion, @primerNombre, @segundoNombre, @primerApellido, @segundoApellido, @correo, @password, @idTipoVinculacion, @idPrograma, @idCorrelacion, @idUsuarioEjecutor` | HU091: vincula un docente al programa del coordinador. Tres modos excluyentes: (a) @idDocente        docente existente (p. ej. de otro programa de la misma institucion) (b) @idUsuario        usuario existente que aun no es docente (c) datos de persona  alta nu… |
| `usp_vincular_identidad_externa` | `@emisor, @sujeto, @idUsuario, @correoVinculacion, @idCorrelacion` | SEC-BASELINE-017: registra el vinculo estable (emisor, sujeto) -> Usuario.id. Reglas (todas atomicas bajo UPDLOCK/HOLDLOCK; los indices unicos son la ultima barrera ante carreras): * El usuario debe existir y estar activo. * Repetir el mismo vinculo vigente es… |

## Addendum F1 — horario semanal del grupo (2026-10-30)

### `dbo.usp_consultar_oferta_creacion_grupo_docente`
- **Caso de uso (F3):** alimenta el formulario "Nuevo grupo" del docente: devuelve su propio `idDocente` y las asignaturas activas (de planes activos) de los programas con los que tiene vínculo activo. No expone nada fuera de esos programas. El período no se elige: `usp_crear_grupo` toma el más reciente si no se envía.
- **Parámetros:** `@idUsuarioEjecutor`, `@idCorrelacion`.
- **Resultset:** `READ_QUERY_RESULTSET` (una fila por asignatura: `idDocente`, `idAsignatura`, `codigoAsignatura`, `nombreAsignatura`, `idPrograma`, `nombrePrograma`). Un ejecutor ausente (`GEN_002`) o que no es DOCENTE (`SEC_001`) se rechaza con `THROW` y el código de catálogo.
- **Permiso:** `GRANT EXECUTE` al runtime en `schema/security/rol_asistencias_runtime_f3_docente_crea_grupo.sql`.
- **Pruebas:** `test/test_usp_consultar_oferta_creacion_grupo_docente.sql`. Work item: `docs/work-items/F3-docente-crea-grupo/`.

---

### `dbo.usp_precargar_sesiones_grupo`
- **Caso de uso (F2):** alinea las sesiones **futuras** del grupo con su horario: crea las que faltan y retira las generadas que ya no encajan. El backend lo invoca en la misma transacción que crea el grupo y guarda el horario (y al cambiar el horario). No sustituye a `usp_generar_sesiones_grupo` (congelado, solo docente titular, genera desde el inicio del período); no lo modifica ni lo invoca.
- **Parámetros:** `@idGrupo`, `@idCorrelacion`, `@idUsuarioEjecutor`.
- **Quién:** el COORDINADOR del programa de la asignatura del grupo, o el DOCENTE titular del grupo (`SEC_002` en otro caso, sin cambios); cualquier otro perfil recibe `SEC_001`. Lo valida `usp_validar_gestion_grupo_coordinador_o_titular_interno`, compartido con `usp_guardar_horarios_grupo`.
- **Reglas:**
  - el grupo debe tener horario (`usp_validar_horarios_grupo_interno`) y su período, fechas coherentes (`usp_validar_fechas_periodo_academico_interno`);
  - solo se generan sesiones desde hoy (hora institucional) o desde el inicio del período si aún no empieza, hasta el fin del período; el pasado no se genera ni se toca;
  - no duplica: una sesión del mismo grupo, inicio y fin ya existente se respeta (idempotente);
  - se retiran las sesiones futuras con `procedenciaTemporal = UTC_GENERADOR` que ya no encajan en el horario y no tienen asistencia ni clasificación; las creadas a mano (`UTC_V2`) nunca se borran;
  - una hora local inexistente por cambio de horario de verano aborta antes de escribir (`SES_005`).
- **Escritura:** la hace `usp_precargar_sesiones_grupo_interno`; este SP controla la transacción (propia, o savepoint si ya hay una abierta) sin `XACT_ABORT ON`. El runtime solo tiene `EXECUTE` sobre el SP público (`rol_asistencias_runtime_f2_precarga_sesiones.sql`).
- **Resultset:** canónico de 4 columnas (`GEN_005` en éxito; el mensaje técnico trae las sesiones creadas y eliminadas).
- **Pruebas:** `test/test_usp_precargar_sesiones_grupo.sql`. Work item: `docs/work-items/F2-precarga-sesiones/`.

---

### `dbo.usp_guardar_horarios_grupo`
- **Caso de uso:** el COORDINADOR del programa define o reemplaza el horario semanal de un grupo (varias franjas). El backend lo invoca en la misma transacción que `usp_crear_grupo` y `usp_actualizar_grupo` cuando el comando trae `franjas`.
- **Parámetros:** `@idGrupo`, `@horariosJSON` (arreglo no vacío de `{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"}` con códigos de `dbo.Dia`), `@idCorrelacion`, `@idUsuarioEjecutor`.
- **Reglas:**
  - formato, día existente y `horaFin > horaInicio` (`HOR_004`);
  - las franjas del grupo no se traslapan entre sí; las contiguas sí se permiten (`HOR_003`);
  - el docente titular no tiene otro grupo a la misma hora en el período (`HOR_002`, vía `usp_validar_cruce_horario_docente_interno`);
  - ejecutor COORDINADOR: el grupo debe pertenecer al programa que coordina (`SEC_002`);
  - ejecutor DOCENTE (F3): solo el titular del grupo (`SEC_002` si no lo es) y solo para definir el horario inicial; si el grupo ya tiene horario recibe `HOR_005` (los cambios posteriores los hace el coordinador);
  - cualquier otro perfil recibe `SEC_001`.
- **Escritura:** la hace `usp_guardar_horarios_grupo_interno` (`DELETE` + `INSERT` sobre `dbo.Horario`); este SP controla la transacción: propia, o savepoint si ya hay una abierta, sin `XACT_ABORT ON`. Un rechazo después de escribir deshace todo lo escrito. El runtime solo tiene `EXECUTE` sobre el SP público (`DENY` sobre el interno) y no puede escribir `dbo.Horario` directamente (`rol_asistencias_runtime_f1_horario_grupo.sql`).
- **Resultset:** canónico de 4 columnas (`GEN_005` en éxito).
- **Pruebas:** `test/test_usp_guardar_horarios_grupo.sql`. Work item: `docs/work-items/F1-horario-grupo/`.
