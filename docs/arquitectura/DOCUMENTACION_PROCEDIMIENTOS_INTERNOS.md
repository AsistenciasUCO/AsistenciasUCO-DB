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
  3. PASO 3: Validación de formato con UFNs (`ufn_validar_numero`, `ufn_validar_texto`, `ufn_validar_correo`).
  4. PASO 4: Inserción final en `dbo.Usuario`.

---

### 2. `dbo.usp_registrar_docente_en_grupo_interno`

> **ELIMINADO (2026-10-29):** este objeto se borró de `schema/` por no tener uso (migración `migrations/08_eliminar_codigo_sin_uso_up.sql`, work item `docs/work-items/BD-eliminar-codigo-sin-uso/`). El texto siguiente es histórico.
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
  - `@codigoEstado NVARCHAR(5)`: código canónico de `dbo.RazonCausa` (`'AN'`, `'SJC'`, `'EX'`). Alias legacy **solo internos**: `'A'` → `AN` y `'F'` → `SJC` (caller `usp_registrar_asistencia_estudiante_autonomo`); el batch público los rechaza antes de llegar aquí.
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `SES_001`, `EST_004`, `RC_001`, `GEN_004`, `SYS_001`.
- **Catálogo cerrado**: un código inexistente en `dbo.RazonCausa` responde `RC_001` (`estadoResultado = 0`); **no** inserta ni actualiza `RazonCausa`. `asistio = 1` solo para `AN`.
- **Flujo de Ejecución**:
  1. PASO 1: Validación de correlación.
  2. PASO 2: Asignación por defecto de código de estado (`'A'`).
  3. PASO 3: Verificación de existencia de la sesión y franja horaria.
  4. PASO 4: Verificación de la matrícula del estudiante en el grupo.
  5. PASO 5: Resolución de la razón causa **existente** en `dbo.RazonCausa` (sin creación dinámica; `RC_001` si no existe).
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
- **Flujo de Ejecución**: Validación previa de existencia del docente (la del grupo la hace el caller; desde 2026-10-29 no exige que el grupo esté en el período vigente), seguida de consulta de traslape horaria en `uv_horario`: mismo día y período académico, franjas que se traslapan (`inicio1 < fin2 AND fin1 > inicio2`; las horas contiguas no son cruce) con otro grupo del que el docente es titular.
- **Mensaje** (2026-10-29): `HOR_002` nombra el grupo en conflicto y la franja (p. ej. "Grupo 1 (Lunes 08:00-10:00)"); el técnico añade el `idGrupo` evaluado.
- **Callers**: `usp_actualizar_grupo` (PASO 3C, cuando cambia el titular). Regla de John (2026-10-29): un docente no puede tener dos grupos a la misma hora. `usp_crear_grupo` no la invoca porque el grupo nace sin horario (`Horario.grupo` es FK a `Grupo`); el SP que en el futuro guarde horarios debe invocarla.

---

### 8.1. `dbo.usp_guardar_horarios_grupo_interno`
- **Propósito**: Núcleo atómico de F1. Reemplaza todas las franjas de `dbo.Horario` del grupo.
- **Parámetros de Entrada**: `@idGrupo UNIQUEIDENTIFIER`, `@horariosJSON NVARCHAR(MAX)` (arreglo de `{codigoDia, horaInicio, horaFin}` ya validado por el caller), `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `SYS_001`.
- **Flujo de Ejecución**: PASO 1 valida la correlación; PASO 2 hace `DELETE` de las franjas del grupo e `INSERT` de las nuevas (día resuelto por `uv_dia.codigo`). No abre transacción: la controla el caller. Ante un error devuelve `estadoResultado = 0` y el caller deshace lo escrito.
- **Caller**: `usp_guardar_horarios_grupo`, que valida formato (`HOR_004`), traslapes entre franjas (`HOR_003`) y, después de este núcleo, el cruce del docente (`HOR_002`). El runtime no puede ejecutarlo directo (`DENY EXECUTE` en `rol_asistencias_runtime_f1_horario_grupo.sql`).

---

### 8.2. `dbo.usp_precargar_sesiones_grupo_interno`
- **Propósito**: Núcleo atómico de F2. Crea las sesiones futuras que faltan según el horario del grupo y retira las futuras generadas que ya no encajan.
- **Parámetros de Entrada**: `@idGrupo UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@sesionesCreadas INT`, `@sesionesEliminadas INT`, `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `GEN_001` (zona horaria sin configurar), `SES_005` (hora local inexistente), `SYS_001`.
- **Flujo de Ejecución**: PASO 1 valida la correlación; PASO 2 valida la zona horaria institucional; PASO 3 arma las franjas desde hoy (o el inicio del período) hasta el fin del período y las convierte a UTC; PASO 4 elimina las sesiones futuras generadas (`UTC_GENERADOR`) que no encajan, sin asistencia ni clasificación; PASO 5 inserta las que faltan con correlativo protegido (`UPDLOCK, HOLDLOCK`). No abre transacción: la controla el caller.
- **Caller**: `usp_precargar_sesiones_grupo`. El runtime no puede ejecutarlo directo (`DENY EXECUTE` en `rol_asistencias_runtime_f2_precarga_sesiones.sql`).

---

### 8.3. `dbo.usp_validar_gestion_grupo_coordinador_o_titular_interno`
- **Propósito**: Validación compartida de quién puede gestionar el horario y las sesiones de un grupo (skill `procedimientos-externos-condiciones`, REC4 #5). Se extrajo el 2026-11-02 porque el bloque estaba repetido en dos SP y SonarCloud lo marcaba como duplicación.
- **Parámetros de Entrada**: `@idGrupo UNIQUEIDENTIFIER`, `@idUsuarioEjecutor UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@ejecutorEsCoordinador BIT`, `@idDocenteTitular UNIQUEIDENTIFIER`, `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `GEN_002`, `SEC_001` (vía `usp_validar_permiso_rbac_usuario_interno`), `VAL_002`, `SEC_002`, `SYS_001`.
- **Flujo de Ejecución**: PASO 1 exige ejecutor con perfil COORDINADOR o DOCENTE; PASO 2 valida que el grupo exista; PASO 3 decide el ámbito: el coordinador debe coordinar el programa de la asignatura del grupo y el docente debe ser su titular.
- **Callers**: `usp_guardar_horarios_grupo` (que además aplica `HOR_005` al docente) y `usp_precargar_sesiones_grupo`.

---

### 8.4. `dbo.usp_validar_consulta_paginada_interno`
- **Propósito**: Validación compartida de las consultas paginadas de solo lectura (skill `procedimientos-internos-condiciones`, REC4 #2). Se creó el 2026-11-02 con HU112/HU128/HU143/HU157 para no repetir en cada SP nuevo el bloque de correlación, ejecutor y paginación (SonarCloud falla con más de 3 % de duplicación en código nuevo).
- **Parámetros de Entrada**: `@idUsuarioEjecutor UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`, `@codigoPerfilRequerido NVARCHAR(50)` (lista separada por comas), `@numeroPagina INT`, `@tamanoPagina INT`.
- **Parámetros de Salida**: `@idUsuarioValidado UNIQUEIDENTIFIER` (ejecutor normalizado), `@offset INT` (desplazamiento de la página) y el triplete `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: los de `usp_validar_id_correlacion_esta_presente_interno`, `VAL_001` (ejecutor ausente), `SEC_001` (vía `usp_validar_permiso_rbac_usuario_interno`), `PAG_001` (página < 1, tamaño < 1 o mayor que `PAGINACION.TAMANO_MAXIMO`) y `SYS_001` en el CATCH. El mensaje técnico lleva la correlación.
- **Flujo de Ejecución**: PASO 1 correlación presente; PASO 2 ejecutor obligatorio; PASO 3 perfil exigido; PASO 4 paginación válida; PASO 5 calcula el desplazamiento y fija el `SESSION_CONTEXT` del ejecutor (el caller captura el previo y lo restaura). Ante una falla devuelve `@estadoResultado = 0` y el caller hace `THROW 51000` con el mensaje técnico (lleva `DBCODE=`). Sin transacción ni `XACT_ABORT` (solo lectura). No recibe `GRANT` del runtime.
- **Callers**: `usp_consultar_programas_creditos_facultad_paginado`, `usp_consultar_docentes_facultad_paginado`, `usp_buscar_asignaturas_paginado` y `usp_buscar_estudiantes_institucion_paginado`.

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

> **ELIMINADO (2026-10-29):** este objeto se borró de `schema/` por no tener uso (migración `migrations/08_eliminar_codigo_sin_uso_up.sql`, work item `docs/work-items/BD-eliminar-codigo-sin-uso/`). El texto siguiente es histórico.
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

> **ELIMINADO (2026-10-30):** este interno se borró de `schema/` porque quedó sin callers (migración `migrations/09_eliminar_validar_grupo_docente_up.sql`, work item `docs/work-items/BD-eliminar-validar-grupo-docente/`). Exigía que el grupo estuviera en el período vigente. El texto siguiente es histórico.
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

---

## Addendum HU096-HU098 (2026-10-25)

### `dbo.usp_resolver_institucion_gestor_periodo_interno`
- **Propósito**: resuelve la institución que gestiona períodos para el ejecutor: valida RBAC `ADMINISTRADOR` y toma `dbo.Administrador.institucion` si la institución está activa.
- **Invocado por**: `usp_crear_periodo_academico`, `usp_actualizar_periodo_academico`, `usp_eliminar_periodo_academico`.
- **Códigos de Catálogo Consumidos**: `PER_005` (sin institución activa como administrador).
- Work item: `docs/work-items/HU096-HU097-HU098-periodos-academicos/`.

---

## Addendum REC2 (2026-10-29)

### `dbo.usp_validar_gestion_asignatura_coordinador_interno`
- **Propósito**: validación común para modificar una asignatura existente, en este orden:
  1. ejecutor obligatorio (`GEN_002`);
  2. perfil `COORDINADOR` (`SEC_001`);
  3. existencia de la asignatura (`VAL_002`);
  4. que el ejecutor coordine el programa de la asignatura (`SEC_002`, vía `usp_validar_titularidad_jerarquica_interno` con `PROGRAMA`).
- **Lecturas**: por las vistas `uv_asignatura` y `uv_semestre_plan_estudio`.
- **Parámetros de Entrada**: `@idAsignatura`, `@idUsuarioEjecutor` (puede llegar NULL y entonces responde `GEN_002`), `@idCorrelacion`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Invocado por**: `usp_actualizar_asignatura` y `usp_toggle_estado_asignatura`.
- **Códigos de Catálogo Consumidos**: `GEN_002`, `SEC_001`, `VAL_002`, `SEC_002`, `SYS_001`.
- **Ampliación al decano**: perfil `'COORDINADOR,DECANO'` y titularidad de `FACULTAD`.
- Work item: `docs/work-items/REC2-rbac-asignatura/`.
## Addendum REC5 (2026-10-29): índice de procedimientos internos sin ficha

30 procedimientos `_interno` no tenían ficha en este documento. Propósito tomado del comentario de cabecera del SP; el contrato de salida es el triplete estándar (`@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`), salvo los internos de resolución que lanzan `THROW` (ver work item de su HU).

| SP | Parámetros | Propósito |
|---|---|---|
| `usp_actualizar_area_interno` | `@id, @nombre, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | Procedimiento: [dbo].[usp_actualizar_area_interno] Historias de Usuario: HU151 / HU152 Ambito: operacion atomica de persistencia. Actualiza el nombre de Area de Conocimiento. |
| `usp_actualizar_datos_usuario_interno` | `@idUsuario, @primerNombre, @segundoNombre, @primerApellido, @segundoApellido, @correo, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | HU121/HU122 (habilitador compartido con IAM-001): actualiza nombres, apellidos y correo de un usuario existente. El tipo y el numero de documento NO se editan (el documento es el username del proveedor de identidad). El correo debe ser unico excluyendo al prop… |
| `usp_actualizar_facultad_interno` | `@id, @nombre, @idDecano, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | Procedimiento: [dbo].[usp_actualizar_facultad_interno] Historias de Usuario: HU110 / HU117 Ambito: operacion atomica de persistencia. Un parametro NULL conserva el valor actual. |
| `usp_actualizar_nombres_usuario_interno` | `@idUsuario, @primerNombre, @segundoNombre, @primerApellido, @segundoApellido` | HU092: actualiza solo los nombres/apellidos de un usuario (los parametros NULL no se tocan). No modifica correo, documento, contrasena ni estado. Las fachadas publicas aportan RBAC, titularidad, validacion y transaccion. |
| `usp_actualizar_programa_academico_interno` | `@idPrograma, @idFacultad, @nombre, @idTipoPrograma, @idCoordinador, @idModalidad, @idJornada, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | Procedimiento: [dbo].[usp_actualizar_programa_academico_interno] Historia de Usuario: HU077 Ambito: edicion atomica del programa: valida (con bloqueo del coordinador) y actualiza nombre, tipo, modalidad, jornada y coordinador. La transaccion vive aqui (SET XAC… |
| `usp_actualizar_sesion_interno` | `@idSesion, @nombre, @fechaHoraInicio, @fechaHoraFin, @idCorrelacion, @idUsuarioEjecutor, @procedenciaTemporal, @idCorrelacionResultado, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | UTC-D06-POST-FREEZE: nucleo unico de actualizacion de sesion compartido por * usp_actualizar_sesion    (v1, firma congelada DB-GP-001C) -> @procedenciaTemporal = NULL * usp_actualizar_sesion_v2 (v2, instantes UTC confirmados)   -> @procedenciaTemporal = 'UTC_V… |
| `usp_actualizar_tipo_programa_interno` | `@id, @nombre, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | Procedimiento: [dbo].[usp_actualizar_tipo_programa_interno] Historias de Usuario: HU154 Ambito: operacion atomica de persistencia. Actualiza el nombre de Tipo de Programa. |
| `usp_cambiar_estado_area_interno` | `@id, @estaActiva, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | Procedimiento: [dbo].[usp_cambiar_estado_area_interno] Historias de Usuario: HU151 / HU152 Ambito: operacion atomica de persistencia. Fija el estado de Area de Conocimiento. |
| `usp_cambiar_estado_facultad_interno` | `@id, @estaActiva, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | Procedimiento: [dbo].[usp_cambiar_estado_facultad_interno] Historia de Usuario: HU111 Ambito: operacion atomica de persistencia del estado de la facultad (sin cascada). |
| `usp_cambiar_estado_programa_academico_interno` | `@idPrograma, @estaActivo, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | Procedimiento: [dbo].[usp_cambiar_estado_programa_academico_interno] Historia de Usuario: HU078 Ambito: cambio atomico del estado: rechaza desactivar con grupos habilitados en el periodo vigente (D4) y activar con la facultad inactiva. La transaccion vive aqui… |
| `usp_cambiar_estado_tipo_programa_interno` | `@id, @estaActivo, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | Procedimiento: [dbo].[usp_cambiar_estado_tipo_programa_interno] Historias de Usuario: HU154 Ambito: operacion atomica de persistencia. Fija el estado de Tipo de Programa. |
| `usp_cambiar_estado_usuario_interno` | `@idUsuario, @estaActivo, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | HU121/HU122 (habilitador compartido con IAM-001): cambia Usuario.estado. Idempotente: si ya tiene el estado destino no modifica nada y responde exito. Sin transaccion propia (corre dentro de la fachada publica). |
| `usp_crear_area_interno` | `@codigo, @nombre, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | Procedimiento: [dbo].[usp_crear_area_interno] Historias de Usuario: HU151 / HU152 Ambito: operacion atomica de persistencia. Inserta Area de Conocimiento activo. |
| `usp_crear_facultad_interno` | `@id, @nombre, @idInstitucion, @idDecano, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | Procedimiento: [dbo].[usp_crear_facultad_interno] Historia de Usuario: HU116 (Alta institucional de nueva facultad) Ámbito: Operación atómica de persistencia para Facultad Estándar: Conforme a procedimientos-internos-condiciones y AGENTS.md |
| `usp_crear_sesion_interno` | `@idGrupo, @nombre, @fechaHoraInicio, @fechaHoraFin, @idCorrelacion, @idUsuarioEjecutor, @procedenciaTemporal, @idCorrelacionResultado, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | UTC-D06-POST-FREEZE: nucleo unico de creacion de sesion compartido por * usp_crear_sesion    (v1, firma congelada DB-GP-001C) -> @procedenciaTemporal = NULL * usp_crear_sesion_v2 (v2, instantes UTC confirmados)   -> @procedenciaTemporal = 'UTC_V2' Las horas y … |
| `usp_crear_tipo_programa_interno` | `@codigo, @nombre, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | Procedimiento: [dbo].[usp_crear_tipo_programa_interno] Historias de Usuario: HU154 Ambito: operacion atomica de persistencia. Inserta Tipo de Programa activo. |
| `usp_insertar_programa_academico_interno` | `@idPrograma, @idFacultad, @nombre, @idTipoPrograma, @idCoordinador, @idModalidad, @idJornada, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | Procedimiento: [dbo].[usp_insertar_programa_academico_interno] Historia de Usuario: HU076 Ambito: alta atomica del programa: valida (con bloqueo del coordinador) e inserta con estado activo. La transaccion vive aqui (SET XACT_ABORT ON, transaccion propia o sav… |
| `usp_resolver_facultad_decano_interno` | `@idUsuarioEjecutor, @idCorrelacion, @validarUmbrales, @idFacultad` | Procedimiento: [dbo].[usp_resolver_facultad_decano_interno] HU102/HU103/HU106/HU144: valida correlacion y ejecutor y resuelve la facultad que dirige el decano (ambito). Falla con THROW (DBCODE=...): CORR_001, VAL_001 (ejecutor nulo), KPI_003 (no es decano de u… |
| `usp_resolver_institucion_administrador_interno` | `@idUsuarioEjecutor, @idCorrelacion, @validarUmbrales, @idInstitucion` | Procedimiento: [dbo].[usp_resolver_institucion_administrador_interno] HU133-HU139: valida correlacion y ejecutor y resuelve la institucion del administrador (ambito). Falla con THROW (DBCODE=...): CORR_001, VAL_001 (ejecutor nulo), KPI_004 (no es administrador… |
| `usp_resolver_periodo_kpi_facultad_interno` | `@idFacultad, @idPeriodoSolicitado, @idPeriodo` | Procedimiento: [dbo].[usp_resolver_periodo_kpi_facultad_interno] HU102/HU103/HU106/HU144 (D7): periodo solicitado (PER_001 si no existe) o, por defecto, el mas reciente con grupos habilitados de la facultad. Devuelve NULL si la facultad no tiene grupos habilit… |
| `usp_resolver_periodo_kpi_institucion_interno` | `@idInstitucion, @idPeriodoSolicitado, @idPeriodo` | Procedimiento: [dbo].[usp_resolver_periodo_kpi_institucion_interno] HU133-HU139 (D1): periodo solicitado (PER_001 si no existe) o, por defecto, el mas reciente con grupos habilitados en los programas de la institucion. Devuelve NULL si la institucion no tiene … |
| `usp_resolver_periodo_kpi_interno` | `@idPrograma, @idPeriodoSolicitado, @idPeriodo` | Procedimiento: [dbo].[usp_resolver_periodo_kpi_interno] HU065-HU070 (D8): periodo explicito (debe existir: PER_001) o el vigente del programa (grupo habilitado); NULL si no hay vigente. |
| `usp_resolver_programa_coordinador_interno` | `@idUsuarioEjecutor, @idCorrelacion, @validarUmbrales, @idPrograma` | Procedimiento: [dbo].[usp_resolver_programa_coordinador_interno] HU065-HU070: valida correlacion y ejecutor y resuelve el programa que coordina el usuario (ambito). Falla con THROW (DBCODE=...): VAL_001 (ejecutor nulo), KPI_001 (no es coordinador de un program… |
| `usp_validar_coordinador_de_facultad_interno` | `@idCoordinador, @idFacultad, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | HU121/HU122: valida que el coordinador exista y pertenezca a la facultad indicada. Devuelve GEN_001 ('Coordinador') tanto si no existe como si es de otra facultad, para no revelar su existencia. Sin transaccion propia: corre dentro de la fachada publica que la… |
| `usp_validar_docente_vinculo_activo_programa_interno` | `@idDocente, @idAsignatura, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | HU093 (D12): un docente cuyo vinculo con el programa de la asignatura fue INACTIVADO no puede ser titular de grupos nuevos ni asignarse a un grupo existente (DOC_009). Un docente sin ningun vinculo no se bloquea, para no romper flujos de asignacion previos a l… |
| `usp_validar_estudiante_en_programa_interno` | `@idEstudiante, @idPrograma` | Procedimiento: [dbo].[usp_validar_estudiante_en_programa_interno] HU067/HU069 (CA-06): el estudiante debe tener matricula en un grupo del programa. GEN_001 'Estudiante' tanto si no existe como si es de otro programa (no se revela su existencia). |
| `usp_validar_programa_academico_interno` | `@idPrograma, @idFacultad, @nombre, @idTipoPrograma, @idCoordinador, @idModalidad, @idJornada, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | Procedimiento: [dbo].[usp_validar_programa_academico_interno] Historias de Usuario: HU076 (alta) y HU077 (edicion) Ambito: validaciones de negocio del programa academico. DEBE ejecutarse dentro de la transaccion del llamador: bloquea (UPDLOCK, HOLDLOCK) la fil… |
| `usp_validar_programa_en_facultad_interno` | `@idFacultad, @idPrograma` | Procedimiento: [dbo].[usp_validar_programa_en_facultad_interno] HU144 (CA-05): GEN_001 «Programa» si el programa no existe o pertenece a otra facultad (no se revela cual de los dos). |
| `usp_validar_sesion_operacion_interno` | `@idCorrelacion, @idUsuarioEjecutor, @procedenciaTemporal, @fechaHoraInicio, @fechaHoraFin, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado, @faseValidacion` | Validacion compartida por los nucleos de creacion y actualizacion de sesion. Mantiene en un unico punto las reglas de procedencia, correlacion y seguridad; no abre ni modifica transacciones y deja la gestion transaccional al llamador. |
| `usp_vincular_docente_programa_interno` | `@idDocente, @idPrograma, @idTipoVinculacion, @idCorrelacion, @mensajeUsuarioResultado, @mensajeTecnicoResultado, @estadoResultado` | HU091: operacion atomica de vinculo (docente, programa). La fachada publica aporta RBAC, titularidad, resolucion de modo y transaccion; aqui solo se valida el tipo, la unicidad y se inserta. |

## Addendum SES-01 (2026-11-03, pendiente de aprobación del owner DB)

### `dbo.usp_validar_sesion_ventana_registro_interno`
- **Propósito**: Valida la ventana de registro ordinario de asistencia: `fechaHoraInicio <= SYSUTCDATETIME() < fechaHoraFin` con procedencia temporal confirmada (`UTC_V2`, `UTC_GENERADOR`, `UTC_OWNER`). Sin tolerancia posterior al cierre; `NULL` (INDETERMINADA) nunca se interpreta con una zona supuesta.
- **Concurrencia**: lee la fila de `dbo.Sesion` con `UPDLOCK, HOLDLOCK`. Debe invocarse **dentro** de la transacción (propia o savepoint) del procedimiento público que escribe: el bloqueo se conserva hasta su `COMMIT`/`ROLLBACK`, el horario no cambia entre validación y escritura, y los lotes concurrentes de la misma sesión se serializan y leen el reloj después de obtener el bloqueo.
- **Parámetros de Entrada**: `@idSesion UNIQUEIDENTIFIER`, `@idCorrelacion UNIQUEIDENTIFIER`.
- **Parámetros de Salida**: `@mensajeUsuarioResultado`, `@mensajeTecnicoResultado`, `@estadoResultado`.
- **Códigos de Catálogo Consumidos**: `SES_001`, `SES_007` (no iniciada), `SES_008` (cerrada), `SES_009` (indeterminada), `SYS_001`.
- **Consumidores**: `usp_registrar_asistencias_sesion` (antes de escribir y antes de confirmar) y `usp_registrar_asistencia_estudiante_autonomo`. No lo usa `usp_resolver_solicitud_revision_asistencia`: la rectificación posterior al cierre es el flujo formal de reclamos (SES-04).
- **Work item**: `docs/work-items/SES-01-cierre-estricto-asistencia/PLAN.md`.
