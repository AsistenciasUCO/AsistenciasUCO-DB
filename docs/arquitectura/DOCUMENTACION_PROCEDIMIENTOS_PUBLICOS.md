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
