# Documentación Técnica de Arquitectura: Procedimientos Almacenados Internos (*_interno)

## Generalidades del Estándar Canónico Corporativo

Esta documentación especifica la arquitectura, reglas de negocio, contrato de firma, parámetros de catálogo consumidos y flujo de control para **todos los Procedimientos Almacenados con sufijo `_interno`** en la base de datos `gestionasistenciadb`.

### Reglas Estructurales Obligatorias
1. **Nombres de Variables UUID**: Toda variable, parámetro o columna `UNIQUEIDENTIFIER` inicia obligatoriamente con el prefijo `id` (ej. `@idTipoIdIdentificacion`, `@idCorrelacion`, `@idDocente`, `@idGrupo`, `@idEstudiante`, `@idPrograma`, `@idSesion`, `@idPerfil`).
2. **Parámetros de Salida Unificados**: Todo procedimiento expone exactamente:
   - `@mensajeUsuarioResultado NVARCHAR(4000) OUTPUT`
   - `@mensajeTecnicoResultado NVARCHAR(4000) OUTPUT`
   - `@estadoResultado BIT OUTPUT`
3. **Zona de Declaración e Inicialización (`AS` ... `BEGIN`)**:
   - `DECLARE` únicamente ubicado entre el `AS` y el primer `BEGIN`.
   - Inicialización de GUIDs mediante `dbo.ufn_obtener_parametro_guid(@variable, 'MODULO/GENERAL', 'NOMBRE_PARAMETRO')`.
   - Limpieza de cadenas mediante `TRIM(@variable)`.
   - **Prohibido el uso de `ISNULL` o `COALESCE`**.
4. **Respuesta Inicial**: Limpieza e inicialización desde catálogo con `dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA')` y `@estadoResultado = 1`.
5. **Catálogo de Mensajes Centralizado**: Respuestas gestionadas a través de `dbo.usp_obtener_mensaje_catalogo` concatenando `' Correlacion: ' + CAST(@idCorrelacionDefecto AS NVARCHAR(50))` en el mensaje técnico.
6. **Manejo Centralizado de Excepciones**: En el bloque `CATCH`, se invoca `dbo.usp_obtener_mensaje_catalogo` con `'SYS_001'` y se registra la traza mediante `dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto)`.

---

## Catálogo de Procedimientos Internos (25 SPs)

---

### 1. `dbo.usp_sincronizar_usuario_interno`
- **Propósito**: Registra un nuevo usuario en la tabla `dbo.Usuario` tras aplicar validaciones biográficas, unicidad y políticas de complejidad de clave.
- **Parámetros de Entrada**:
  - `@idTipoIdIdentificacion UNIQUEIDENTIFIER`: Identificador del tipo de documento.
  - `@numeroIdentificacion INT`: Número de identificación.
  - `@primerApellido NVARCHAR(255)` / `@segundoApellido NVARCHAR(255)`
  - `@primerNombre NVARCHAR(255)` / `@segundoNombre NVARCHAR(255)`
  - `@correo NVARCHAR(255)`
  - `@password NVARCHAR(500)`: Hash de la contraseña.
  - `@idCorrelacion UNIQUEIDENTIFIER`: ID de trazabilidad.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `VAL_001`, `VAL_003`, `VAL_004`, `VAL_005`, `VAL_007`, `GEN_004`, `SYS_001`.
- **Flujo de Ejecución**:
  1. PASO 1: Validación de `@idCorrelacionDefecto`.
  2. PASO 2: Invocación a `usp_validar_tipo_identificacion_exista_por_id_interno` y `usp_validar_unicidad_usuario_interno`.
  3. PASO 3: Validación de formato con UFNs (`ufn_validar_numero`, `ufn_validar_texto`, `ufn_validar_correo`, `ufn_validar_password`).
  4. PASO 4: Inserción final en `dbo.Usuario`.

---

### 2. `dbo.usp_registrar_docente_en_grupo_interno`
- **Propósito**: Vincula o actualiza el docente asignado a un grupo académico.
- **Parámetros de Entrada**:
  - `@idDocente UNIQUEIDENTIFIER`
  - `@idGrupo UNIQUEIDENTIFIER`
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `GEN_005`, `SYS_001`.
- **Flujo de Ejecución**:
  1. PASO 1: Validación de `@idCorrelacionDefecto`.
  2. PASO 2: Invocación a `usp_validar_docente_exista_por_id_interno`, `usp_validar_grupo_exista_para_docente_interno`, `usp_validar_cruce_horario_docente_interno`.
  3. PASO 3: `UPDATE dbo.Grupo SET docente = @idDocenteDefecto WHERE id = @idGrupoDefecto`.

---

### 3. `dbo.usp_registrar_estudiante_en_grupo_interno`
- **Propósito**: Inscribe a un estudiante en un grupo de clase específico con estado activo (`'A'`).
- **Parámetros de Entrada**:
  - `@idEstudiante UNIQUEIDENTIFIER`
  - `@idGrupo UNIQUEIDENTIFIER`
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `GEN_001`, `GEN_004`, `SYS_001`.
- **Flujo de Ejecución**:
  1. PASO 1: Validación de correlación.
  2. PASO 2: Obtención del ID del Estado Activo `'A'` desde `uv_estado_estudiante_grupo`.
  3. PASO 3: Ejecución secuencial de validaciones (`usp_validar_estudiante_exista_por_id_interno`, `usp_validar_grupo_exista_por_id_interno`, `usp_validar_cruce_horario_estudiante_interno`, `usp_validar_registro_estudiante_en_grupo_interno`).
  4. PASO 4: Inserción en `dbo.EstudianteGrupo`.

---

### 4. `dbo.usp_registrar_estudiante_en_programa_interno`
- **Propósito**: Vincula un estudiante a un programa académico verificando pertenencia institucional.
- **Parámetros de Entrada**:
  - `@idEstudiante UNIQUEIDENTIFIER`
  - `@idPrograma UNIQUEIDENTIFIER`
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `GEN_002`, `INST_001`, `EST_003`, `GEN_004`, `SYS_001`.
- **Flujo de Ejecución**:
  1. PASO 1: Validación de correlación.
  2. PASO 2: Verificación de coincidencia institucional cruzada (Estudiante vs Programa vs Facultad).
  3. PASO 3: Validación de inscripción previa en `dbo.EstudiantePrograma` e inserción en caso de no existir.

---

### 5. `dbo.usp_sincronizar_asistencia_estudiante_interno`
- **Propósito**: Registra o actualiza la asistencia/asistencia tardía/falta/justificación de un estudiante en una sesión.
- **Parámetros de Entrada**:
  - `@idEstudiante UNIQUEIDENTIFIER`
  - `@idSesion UNIQUEIDENTIFIER`
  - `@codigoEstado NVARCHAR(5)`: `'A'`, `'F'`, `'T'`, `'J'`.
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `SES_001`, `EST_004`, `GEN_004`, `SYS_001`.
- **Flujo de Ejecución**:
  1. PASO 1: Validación de correlación.
  2. PASO 2: Asignación por defecto de código de estado (`'A'`).
  3. PASO 3: Verificación de existencia de la sesión y franja horaria.
  4. PASO 4: Verificación de la matrícula del estudiante en el grupo.
  5. PASO 5: Resolución de razón causa (`dbo.RazonCausa`).
  6. PASO 6: Inserción/actualización de cabecera (`dbo.Asistencia`) y detalle (`dbo.DetalleAsistencia`).

---

### 6. `dbo.usp_sincronizar_docente_interno`
- **Propósito**: Convierte o asocia un usuario existente como Docente (`dbo.Docente`).
- **Parámetros de Entrada**: `@idUsuario UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `VAL_006`, `GEN_004`, `SYS_001`.
- **Flujo de Ejecución**:
  1. PASO 1: Validación de correlación.
  2. PASO 2: Validación de existencia del perfil docente (`'DO'`).
  3. PASO 3: Validación de existencia de usuario activo.
  4. PASO 4: Validación de no duplicidad en `dbo.Docente`.
  5. PASO 5: Inserción en `dbo.Docente`.

---

### 7. `dbo.usp_sincronizar_estudiante_interno`
- **Propósito**: Convierte o asocia un usuario existente como Estudiante (`dbo.Estudiante`).
- **Parámetros de Entrada**: `@idUsuario UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `VAL_006`, `GEN_004`, `SYS_001`.
- **Flujo de Ejecución**:
  1. PASO 1: Validación de correlación.
  2. PASO 2: Validación de existencia del perfil estudiante (`'ES'`).
  3. PASO 3: Validación de existencia de usuario activo.
  4. PASO 4: Validación de no duplicidad en `dbo.Estudiante`.
  5. PASO 5: Inserción en `dbo.Estudiante`.

---

### 8. `dbo.usp_validar_cruce_horario_docente_interno`
- **Propósito**: Detecta traslapes u homologaciones de horario para un docente entre sus grupos asignados.
- **Parámetros de Entrada**: `@idDocente UNIQUEIDENTIFIER`, `@idGrupo UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `HOR_002`, `SYS_001`.
- **Flujo de Ejecución**: Validaciones previas de existencia de docente y grupo, seguida de consulta de traslape horaria en `uv_horario`.

---

### 9. `dbo.usp_validar_cruce_horario_estudiante_interno`
- **Propósito**: Detecta traslapes de horario para un estudiante en los grupos matriculados.
- **Parámetros de Entrada**: `@idEstudiante UNIQUEIDENTIFIER`, `@idGrupo UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `HOR_001`, `SYS_001`.
- **Flujo de Ejecución**: Validaciones previas de existencia e inserción en consulta cruzada de traslape horaria.

---

### 10. `dbo.usp_validar_docente_exista_por_id_interno`
- **Propósito**: Valida que un identificador de docente exista y su usuario asociado se encuentre activo.
- **Parámetros de Entrada**: `@idDocente UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `DOC_001`, `USU_002`, `SYS_001`.

---

### 11. `dbo.usp_validar_estudiante_exista_por_id_interno`
- **Propósito**: Valida que un estudiante exista en la vista `uv_estudiante_identidad` y tenga usuario activo.
- **Parámetros de Entrada**: `@idEstudiante UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `EST_001`, `USU_002`, `SYS_001`.

---

### 12. `dbo.usp_validar_estudiante_grupo_exista_interno`
- **Propósito**: Valida la existencia y estado activo (`'A'`) de un registro de matrícula `EstudianteGrupo`.
- **Parámetros de Entrada**: `@idEstudianteGrupo UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `VAL_001`, `GEN_001`, `USU_002`, `SYS_001`.

---

### 13. `dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno`
- **Propósito**: Verifica que el estudiante pertenezca de forma activa al grupo asociado a una sesión.
- **Parámetros de Entrada**: `@idEstudiante UNIQUEIDENTIFIER`, `@idSesion UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `SES_001`, `EST_004`, `SYS_001`.

---

### 14. `dbo.usp_validar_fechas_periodo_academico_interno`
- **Propósito**: Comprueba la coherencia y vigencia de las fechas (`fechaInicio < fechaFin`) del periodo académico de un grupo.
- **Parámetros de Entrada**: `@idGrupo UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `GEN_001`, `GEN_002`, `VAL_002`, `SYS_001`.

---

### 15. `dbo.usp_validar_grupo_exista_para_docente_interno`
- **Propósito**: Valida que un grupo exista en `uv_grupo`, tenga un periodo académico asignado y esté habilitado para docentes.
- **Parámetros de Entrada**: `@idGrupo UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `VAL_001`, `GRUP_001`, `GRUP_003`, `SYS_001`.

---

### 16. `dbo.usp_validar_grupo_exista_por_id_interno`
- **Propósito**: Valida existencia, habilitación del periodo académico y cupo máximo de estudiantes disponibles en un grupo.
- **Parámetros de Entrada**: `@idGrupo UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `VAL_001`, `GRUP_001`, `GRUP_002`, `GRUP_003`, `SYS_001`.

---

### 17. `dbo.usp_validar_horarios_grupo_interno`
- **Propósito**: Verifica que el grupo especificado posea franjas horarias registradas en la tabla `dbo.Horario`.
- **Parámetros de Entrada**: `@idGrupo UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `GRUP_001`, `SYS_001`.

---

### 18. `dbo.usp_validar_id_correlacion_esta_presente_interno`
- **Propósito**: Validador transversal que verifica la presencia obligatoria de un GUID de correlación en peticiones.
- **Parámetros de Entrada**: `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `CORR_001`, `SYS_001`.

---

### 19. `dbo.usp_validar_id_interno`
- **Propósito**: Comprueba que un identificador `UNIQUEIDENTIFIER` no corresponda al GUID por defecto (`'00000000-0000-0000-0000-000000000000'`).
- **Parámetros de Entrada**: `@id UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `VAL_001`, `SYS_001`.

---

### 20. `dbo.usp_validar_perfil_existe_por_codigo_interno`
- **Propósito**: Recupera el identificador único del perfil a partir de su código (ej. `'DO'`, `'ES'`, `'AD'`) desde `uv_perfil`.
- **Parámetros de Entrada**: `@codigoPerfil NVARCHAR(10)`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@idPerfilEncontrado UNIQUEIDENTIFIER OUTPUT`, `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `VAL_003`, `GEN_001`, `SYS_001`.

---

### 21. `dbo.usp_validar_registro_estudiante_en_grupo_interno`
- **Propósito**: Previene registros duplicados del mismo estudiante en un mismo grupo académico.
- **Parámetros de Entrada**: `@idGrupo UNIQUEIDENTIFIER`, `@idEstudiante UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `EST_002`, `SYS_001`.

---

### 22. `dbo.usp_validar_sesion_exista_por_id_interno`
- **Propósito**: Valida que una sesión de clase exista en la vista `uv_sesion`.
- **Parámetros de Entrada**: `@idSesion UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `VAL_001`, `SES_001`, `SYS_001`.

---

### 23. `dbo.usp_validar_tipo_identificacion_exista_por_id_interno`
- **Propósito**: Valida la existencia de un tipo de documento en la vista `uv_tipo_identificacion`.
- **Parámetros de Entrada**: `@idTipoId UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `VAL_001`, `GEN_001`, `SYS_001`.

---

### 24. `dbo.usp_validar_unicidad_usuario_interno`
- **Propósito**: Valida que no exista duplicidad por tipo/número de documento ni por correo electrónico en `uv_usuario`.
- **Parámetros de Entrada**: `@idTipoIdIdentificacion UNIQUEIDENTIFIER`, `@numeroIdentificacion INT`, `@correo NVARCHAR(255)`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `ERR_UNICIDAD_DOCUMENTO`, `VAL_006`, `SYS_001`.

---

### 25. `dbo.usp_validar_usuario_existe_por_id_interno`
- **Propósito**: Valida que un usuario exista en `uv_usuario` y se encuentre en estado activo (`estaActivoUsuario = 1`).
- **Parámetros de Entrada**: `@idUsuario UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `VAL_001`, `USU_001`, `USU_002`, `SYS_001`.

---

## Verificación de Integridad y Despliegue

Todos los procedimientos listados en esta documentación han sido compilados y probados en la base de datos `gestionasistenciadb` mediante la ejecución del script `deploy_schema.ps1`.
