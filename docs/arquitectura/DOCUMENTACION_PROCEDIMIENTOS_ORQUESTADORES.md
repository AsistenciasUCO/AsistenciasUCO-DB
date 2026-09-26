# Documentación Técnica de Arquitectura: Procedimientos Almacenados Orquestadores / Públicos (Sin sufijo `_interno`)

## Generalidades del Estándar Canónico Corporativo

Esta documentación especifica la arquitectura, reglas de negocio, contrato de firma, parámetros de catálogo consumidos y flujo de control reactivo para **todos los Procedimientos Almacenados Orquestadores Públicos (sin sufijo `_interno`)** en la base de datos `gestionasistenciadb`.

### Reglas Estructurales Obligatorias para Orquestadores
1. **Nombres de Variables UUID**: Toda variable, parámetro o columna `UNIQUEIDENTIFIER` inicia obligatoriamente con el prefijo `id` (ej. `@idTipoIdIdentificacion`, `@idCorrelacion`, `@idDocente`, `@idGrupo`, `@idEstudiante`, `@idPrograma`, `@idSesion`, `@idPerfil`).
2. **Firma Externa Limpia**: Los orquestadores no reciben parámetros `OUTPUT` en su firma. Reciben únicamente parámetros de negocio de entrada y el parámetro obligatorio `@idCorrelacion UNIQUEIDENTIFIER`.
3. **Zona de Declaración e Inicialización (`AS` ... `BEGIN`)**:
   - `DECLARE` ubicado únicamente entre `AS` y el primer `BEGIN`.
   - Declaración local de variables de resultado:
     ```sql
     DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
     DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
     DECLARE @estadoResultado BIT = 1;
     ```
   - Inicialización de GUIDs mediante `dbo.ufn_obtener_parametro_guid(@variable, 'MODULO/GENERAL', 'NOMBRE_PARAMETRO')`.
   - Limpieza y estandarización de cadenas mediante `TRIM(@variable)`, `UPPER(...)` o `LOWER(...)`.
   - **Prohibido el uso de `ISNULL` o `COALESCE`**.
4. **Respuesta Inicial**: Limpieza e inicialización desde catálogo con `dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA')` y `@estadoResultado = 1`.
5. **Flujo Reactivo (UPSERT)**:
   - Consulta previa de existencia sobre **Vistas (`uv_*`)**.
   - **Si el registro existe**: El orquestador ejecuta directamente la modificación (`UPDATE`) sobre la tabla física correspondiente.
   - **Si el registro NO existe**: El orquestador ejecuta directamente la inserción (`INSERT`) o delega a un procedimiento interno especializado (`usp_sincronizar_*_interno`).
6. **Catálogo de Mensajes Centralizado**: Respuestas gestionadas a través de `dbo.usp_obtener_mensaje_catalogo` concatenando `' Correlacion: ' + CAST(@idCorrelacionDefecto AS NVARCHAR(50))` en el mensaje técnico.
7. **Manejo Centralizado de Excepciones**: En el bloque `CATCH`, se invoca `dbo.usp_obtener_mensaje_catalogo` con el código de error correspondiente y se registra la traza mediante `[dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto)`.
8. **Bloque Final Mandatorio (SELECT de 4 Columnas)**: Termina **SIEMPRE** al final del procedimiento (fuera del bloque TRY/CATCH) con un único `SELECT`:
   ```sql
   SELECT
       idCorrelacion = @idCorrelacionDefecto,
       mensajeUsuarioResultado = @mensajeUsuarioResultado,
       mensajeTecnicoResultado = @mensajeTecnicoResultado,
       estadoResultado = @estadoResultado;
   ```

---

## Catálogo de Procedimientos Almacenados Orquestadores

---

### 1. `dbo.usp_registrar_o_actualizar_programa_academico`
- **Propósito**: Administra el ciclo de vida del Programa Académico mediante un flujo reactivo (UPSERT). Si el programa existe en `uv_programa`, lo actualiza; de lo contrario, lo registra.
- **Parámetros de Entrada**:
  - `@idPrograma UNIQUEIDENTIFIER`: Identificador opcional del programa.
  - `@idFacultad UNIQUEIDENTIFIER`: Identificador de la facultad asociada.
  - `@idTipoDePrograma UNIQUEIDENTIFIER`: Tipo de programa académico.
  - `@nombre NVARCHAR(50)`: Nombre del programa.
  - `@idCoordinador UNIQUEIDENTIFIER`: Identificador del usuario coordinador.
  - `@idCorrelacion UNIQUEIDENTIFIER`: Identificador de trazabilidad.
- **Conjunto de Resultados Retornado**: `idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`.
- **Códigos de Catálogo Consumidos**: `VAL_001`, `SUC_ACTUALIZACION_PROGRAMA`, `SUC_REGISTRO_PROGRAMA`, `ERR_INESPERADO_REGISTRO_PROGRAMA`.
- **Flujo de Ejecución**:
  1. Validar presencia de `@idCorrelacionDefecto` con `usp_validar_id_correlacion_esta_presente_interno`.
  2. Validar existencia de la facultad mediante la vista `dbo.uv_facultad`.
  3. Evaluar existencia del programa mediante `dbo.uv_programa`.
  4. Ejecutar `UPDATE dbo.Programa` si existe o `INSERT INTO dbo.Programa` si es nuevo.
  5. Retornar bloque final `SELECT`.

---

### 2. `dbo.usp_registrar_o_actualizar_plan_estudio`
- **Propósito**: Administra los Planes de Estudio de manera reactiva (UPSERT).
- **Parámetros de Entrada**:
  - `@idPlanEstudio UNIQUEIDENTIFIER`
  - `@idPrograma UNIQUEIDENTIFIER`
  - `@codigo NVARCHAR(50)`
  - `@nombre NVARCHAR(100)`
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Conjunto de Resultados Retornado**: `idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`.
- **Códigos de Catálogo Consumidos**: `VAL_001`, `SUC_ACTUALIZACION_PLAN_ESTUDIO`, `SUC_REGISTRO_PLAN_ESTUDIO`, `ERR_INESPERADO_REGISTRO_PLAN_ESTUDIO`.
- **Flujo de Ejecución**:
  1. Validar `@idCorrelacionDefecto`.
  2. Validar pertenencia de programa en `dbo.uv_programa`.
  3. Consultar existencia en `dbo.uv_plan_estudio`.
  4. Ejecutar `UPDATE dbo.PlanEstudio` o `INSERT INTO dbo.PlanEstudio`.
  5. Retornar bloque final `SELECT`.

---

### 3. `dbo.usp_registrar_o_actualizar_asignatura`
- **Propósito**: Administra el catálogo de asignaturas institucionales (UPSERT).
- **Parámetros de Entrada**:
  - `@idAsignatura UNIQUEIDENTIFIER`
  - `@nombre NVARCHAR(100)`
  - `@codigo NVARCHAR(50)`
  - `@creditos INT`
  - `@horasSemanales INT`
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Conjunto de Resultados Retornado**: `idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`.
- **Códigos de Catálogo Consumidos**: `SUC_ACTUALIZACION_ASIGNATURA`, `SUC_REGISTRO_ASIGNATURA`, `ERR_INESPERADO_REGISTRO_ASIGNATURA`.
- **Flujo de Ejecución**:
  1. Validar `@idCorrelacionDefecto`.
  2. Consultar existencia por código o ID en `dbo.uv_asignatura`.
  3. Ejecutar `UPDATE dbo.Asignatura` o `INSERT INTO dbo.Asignatura`.
  4. Retornar bloque final `SELECT`.

---

### 4. `dbo.usp_registrar_o_actualizar_grupo`
- **Propósito**: Administra los grupos de cursos de asignaturas por período académico (UPSERT legacy). Para consumidores externos nuevos, los contratos públicos vigentes son `dbo.usp_crear_grupo` y `dbo.usp_actualizar_grupo`, donde `@codigo` es `INT`.
- **Parámetros de Entrada**:
  - `@idGrupo UNIQUEIDENTIFIER`
  - `@idAsignatura UNIQUEIDENTIFIER`
  - `@idPeriodoAcademico UNIQUEIDENTIFIER`
  - `@idDocente UNIQUEIDENTIFIER`
  - `@nombre NVARCHAR(50)`
  - `@codigo NVARCHAR(50)` en este orquestador legacy; se normaliza internamente a `INT` para `dbo.Grupo.codigo`. En `dbo.usp_crear_grupo` y `dbo.usp_actualizar_grupo`, `@codigo` es `INT`.
  - `@cupo INT`
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Conjunto de Resultados Retornado**: `idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`.
- **Códigos de Catálogo Consumidos**: `VAL_001`, `SUC_ACTUALIZACION_GRUPO`, `SUC_REGISTRO_GRUPO`, `ERR_INESPERADO_REGISTRO_GRUPO`.
- **Flujo de Ejecución**:
  1. Validar `@idCorrelacionDefecto`.
  2. Validar existencia de asignatura y período académico en `dbo.uv_asignatura` y `dbo.uv_periodo_academico`.
  3. Consultar existencia en `dbo.uv_grupo`.
  4. Ejecutar `UPDATE dbo.Grupo` o `INSERT INTO dbo.Grupo`.
  5. Retornar bloque final `SELECT`.

---

### 5. `dbo.usp_sincronizar_usuario`
- **Propósito**: Punto de entrada externo para registrar o sincronizar usuarios institucionales.
- **Parámetros de Entrada**:
  - `@idTipoIdIdentificacion UNIQUEIDENTIFIER`
  - `@numeroIdentificacion INT`
  - `@primerApellido NVARCHAR(255)` / `@segundoApellido NVARCHAR(255)`
  - `@primerNombre NVARCHAR(255)` / `@segundoNombre NVARCHAR(255)`
  - `@correo NVARCHAR(255)`
  - `@password NVARCHAR(500)`
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Conjunto de Resultados Retornado**: `idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`.
- **Códigos de Catálogo Consumidos**: `SUC_SINCRONIZACION_USUARIO`, `ERR_INESPERADO_SINCRONIZACION_USUARIO`.
- **Flujo de Ejecución**:
  1. Validar `@idCorrelacionDefecto`.
  2. Delegar sincronización a `dbo.usp_sincronizar_usuario_interno`.
  3. Retornar bloque final `SELECT`.

---

### 6. `dbo.usp_registrar_estudiante_en_programa`
- **Propósito**: Punto de entrada externo para matricular un estudiante a un programa académico.
- **Parámetros de Entrada**:
  - `@idEstudiante UNIQUEIDENTIFIER`
  - `@idPrograma UNIQUEIDENTIFIER`
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Conjunto de Resultados Retornado**: `idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`.
- **Códigos de Catálogo Consumidos**: `SUC_REGISTRO_ESTUDIANTE_PROGRAMA`, `ERR_INESPERADO_REGISTRO_ESTUDIANTE_PROGRAMA`.
- **Flujo de Ejecución**:
  1. Validar `@idCorrelacionDefecto`.
  2. Delegar a `dbo.usp_registrar_estudiante_en_programa_interno`.
  3. Retornar bloque final `SELECT`.

---

### 7. `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente`
- **Propósito**: Orquesta el flujo completo de registro de un nuevo estudiante en un grupo académico cuando el usuario no existe previamente en la plataforma.
- **Parámetros de Entrada**:
  - `@idTipoIdIdentificacion UNIQUEIDENTIFIER`, `@numeroIdentificacion INT`
  - `@primerApellido NVARCHAR(255)`, `@segundoApellido NVARCHAR(255)`
  - `@primerNombre NVARCHAR(255)`, `@segundoNombre NVARCHAR(255)`
  - `@correo NVARCHAR(255)`, `@password NVARCHAR(500)`
  - `@idGrupo UNIQUEIDENTIFIER`
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Conjunto de Resultados Retornado**: `idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`.
- **Flujo de Ejecución**:
  1. Validar `@idCorrelacionDefecto`.
  2. Buscar usuario en `dbo.uv_usuario`. Si existe lo actualiza, si no existe delega en `usp_sincronizar_usuario_interno`.
  3. Buscar perfil estudiante en `dbo.uv_estudiante_identidad`. Si no existe delega en `usp_sincronizar_estudiante_interno`.
  4. Inscribir estudiante en grupo mediante `usp_registrar_estudiante_en_grupo_interno`.
  5. Vincular a programa académico en `usp_registrar_estudiante_en_programa_interno`.
  6. Retornar bloque final `SELECT`.

---

### 8. `dbo.usp_registrar_docente_en_grupo_usuario_no_existente`
- **Propósito**: Orquesta la alta y vinculación de docentes a grupos de clase.
- **Parámetros de Entrada**:
  - Datos biográficos de usuario + `@idGrupo UNIQUEIDENTIFIER` + `@idCorrelacion UNIQUEIDENTIFIER`.
- **Conjunto de Resultados Retornado**: `idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`.
- **Flujo de Ejecución**:
  1. Validar `@idCorrelacionDefecto`.
  2. Sincronizar usuario y perfil docente en `dbo.uv_docente_identidad` / `usp_sincronizar_docente_interno`.
  3. Asignar docente al grupo con `usp_registrar_docente_en_grupo_interno`.
  4. Retornar bloque final `SELECT`.

---

### 9. `dbo.usp_generar_sesiones_grupo`
- **Propósito**: Genera masivamente las sesiones de clase programadas para un grupo según su horario.
- **Parámetros de Entrada**:
  - `@idGrupo UNIQUEIDENTIFIER`
  - `@fechaInicio DATE`, `@fechaFin DATE`
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Conjunto de Resultados Retornado**: `idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`.
- **Flujo de Ejecución**:
  1. Validar `@idCorrelacionDefecto`.
  2. Validar grupo y horarios en `dbo.uv_horario`.
  3. Generar sesiones en `dbo.Sesion` en bloque transaccional.
  4. Retornar bloque final `SELECT`.

---

### 10. `dbo.usp_registrar_asistencia_estudiante`
- **Propósito**: Registra la marca de asistencia de un estudiante a una sesión de clase presencial u homologada.
- **Parámetros de Entrada**:
  - `@idSesion UNIQUEIDENTIFIER`, `@idEstudiante UNIQUEIDENTIFIER`, `@idEstadoAsistencia UNIQUEIDENTIFIER`
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Conjunto de Resultados Retornado**: `idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`.
- **Flujo de Ejecución**:
  1. Validar `@idCorrelacionDefecto`.
  2. Delega la validación y registro en `usp_sincronizar_asistencia_estudiante_interno`.
  3. Retornar bloque final `SELECT`.

---

### 11. `dbo.usp_registrar_asistencia_estudiante_autonomo`
- **Propósito**: Permite el auto-registro de asistencia del estudiante con validación de ventana temporal y código QR / Token de sesión.
- **Parámetros de Entrada**:
  - `@idSesion UNIQUEIDENTIFIER`, `@idEstudiante UNIQUEIDENTIFIER`, `@tokenSesion NVARCHAR(100)`
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Conjunto de Resultados Retornado**: `idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`.
- **Flujo de Ejecución**:
  1. Validar `@idCorrelacionDefecto`.
  2. Validar token y ventana horaria de la sesión en `dbo.uv_sesion`.
  3. Delega en `usp_sincronizar_asistencia_estudiante_interno`.
  4. Retornar bloque final `SELECT`.

---

### 12. `dbo.usp_registrar_asistencias_sesion`
- **Propósito**: Registra masivamente la asistencia de todos los estudiantes inscritos en una sesión de clase dada.
- **Parámetros de Entrada**:
  - `@idSesion UNIQUEIDENTIFIER`
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Conjunto de Resultados Retornado**: `idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`.
- **Flujo de Ejecución**:
  1. Validar `@idCorrelacionDefecto`.
  2. Obtener lista de estudiantes activos del grupo desde `dbo.uv_estudiante_grupo`.
  3. Procesar iterativamente o masivamente con `usp_sincronizar_asistencia_estudiante_interno`.
  4. Retornar bloque final `SELECT`.
