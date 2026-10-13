# Especificación Técnica de Procedimientos, Vistas y Funciones (`gestionasistenciadb`)

---

## 🏛️ Introducción Arquitectónica

El presente documento define la especificación técnica completa y actualizada de la capa lógica de la base de datos **`gestionasistenciadb`**. 

Contiene la documentación oficial de:
1. **57 Procedimientos Almacenados (SPs)**: Transacciones públicas de negocio y procedimientos internos de validación y sincronización.
2. **55 Vistas (Views)**: Vistas de catálogo, vistas de proyección de identidad y vistas autorizadas por seguridad RBAC dinámicas (`uv_auth_*`).
3. **15 Funciones (Functions)**: Funciones auxiliares de validación, consulta de parámetros y lectura de `SESSION_CONTEXT`.

---

# 1. ⚙️ PROCEDIMIENTOS ALMACENADOS (STORED PROCEDURES)

---

### [SP-001] - `dbo.usp_actualizar_asignatura`
- **Módulo / Alcance:** Gestión Académica - Asignaturas
- **Propósito de Negocio:** Permite actualizar el código, nombre, créditos, horas semanales y estado de una asignatura existente en la institución.
- **Entidades del MER Involucradas:** `Asignatura`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la obligatoriedad de `@idUsuarioEjecutor` e `@idCorrelacion`.
  2. Validar permisos RBAC del usuario ejecutor (roles permitidos: COORDINADOR, ADMINISTRADOR).
  3. Verificar que la asignatura a actualizar exista en `dbo.Asignatura`.
  4. Validar la unicidad del código de la asignatura para evitar duplicados en la misma institución.
  5. Ejecutar `UPDATE` atómico sobre `dbo.Asignatura` con los nuevos valores de código, nombre, créditos, horas semanales y estado.
  6. Retornar respuesta estructurada `(idCorrelacion, mensajeUsuario, mensajeTecnico, estadoResultado)`.
- **Reglas de Negocio y Validaciones Específicas:**
  * El código de la asignatura debe ser único dentro de la institución.
  * No se permite dejar vacíos los campos obligatorios como el nombre o código.
- **Estado Resultante en la BD:** Registro de `dbo.Asignatura` actualizado.

---

### [SP-002] - `dbo.usp_actualizar_grupo`
- **Módulo / Alcance:** Gestión Académica - Oferta de Grupos
- **Propósito de Negocio:** Permite modificar los datos básicos de un grupo académico (código, nombre, docente asignado, cupo máximo).
- **Entidades del MER Involucradas:** `Grupo`, `Docente`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar `@idUsuarioEjecutor` e `@idCorrelacion`.
  2. Verificar autorización RBAC del ejecutor.
  3. Validar existencia del `idGrupo` en `dbo.Grupo`.
  4. Si se especifica `@idDocente`, validar que el docente exista y esté activo en la institución.
  5. Validar que el cupo máximo no sea inferior a la cantidad de estudiantes actualmente matriculados en estado activo.
  6. Ejecutar `UPDATE` sobre `dbo.Grupo`.
  7. Retornar respuesta estructurada.
- **Reglas de Negocio y Validaciones Específicas:**
  * El cupo máximo no puede reducirse por debajo del número de estudiantes con matrícula activa.
- **Estado Resultante en la BD:** Datos del registro en `dbo.Grupo` modificados atómicamente.

---

### [SP-003] - `dbo.usp_actualizar_sesion`
- **Módulo / Alcance:** Control de Asistencia - Sesiones de Clase
- **Propósito de Negocio:** Actualiza el nombre y las fechas/horas de inicio y fin de una sesión de clase específica.
- **Entidades del MER Involucradas:** `Sesion`, `Grupo`, `Docente`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar ejecutor, correlación y permisos (DOCENTE titular, COORDINADOR o ADMINISTRADOR).
  2. Verificar existencia de la sesión en `dbo.Sesion`.
  3. Validar consistencia temporal: `fechaHoraFin > fechaHoraInicio`.
  4. Actualizar los campos `nombre`, `fechaHoraInicio` y `fechaHoraFin` en `dbo.Sesion`.
  5. Retornar respuesta estándar.
- **Reglas de Negocio y Validaciones Específicas:**
  * La fecha de fin debe ser posterior a la fecha de inicio.
  * Si la ejecuta un docente, debe ser el titular asignado al grupo correspondiente.
- **Estado Resultante en la BD:** Registro en `dbo.Sesion` actualizado.

---

### [SP-004] - `dbo.usp_cerrar_sesion`
- **Módulo / Alcance:** Control de Asistencia - Sesiones de Clase (Legacy)
- **Propósito de Negocio:** Procedimiento legacy de cierre de sesión. El modelo actual utiliza sesiones dinámicas continuas.
- **Entidades del MER Involucradas:** `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar parámetros de entrada.
  2. Retornar la respuesta contractual de no soportado (`SES_003`, `estadoResultado = 0`).
- **Reglas de Negocio y Validaciones Específicas:**
  * No realiza escrituras en la BD.
- **Estado Resultante en la BD:** Sin cambios.

---

### [SP-005] - `dbo.usp_consultar_grupos_paginado`
- **Módulo / Alcance:** Consultas Generales - Paginación
- **Propósito de Negocio:** Realiza consultas paginadas de la oferta de grupos académicos filtrando por período, asignatura, docente o texto.
- **Entidades del MER Involucradas:** `Grupo`, `Asignatura`, `Docente`, `PeriodoAcademico`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar parámetros de paginación (`@numeroPagina`, `@tamanoPagina`).
  2. Aplicar filtros condicionales según los parámetros recibidos.
  3. Ejecutar consulta paginada utilizando `OFFSET ... FETCH NEXT`.
  4. Retornar el conjunto de resultados junto con el conteo total de registros.
- **Reglas de Negocio y Validaciones Específicas:**
  * Retorna datos paginados eficientemente.
- **Estado Resultante en la BD:** Consulta de solo lectura.

---

### [SP-006] - `dbo.usp_crear_asignatura`
- **Módulo / Alcance:** Gestión Académica - Asignaturas
- **Propósito de Negocio:** Registra una nueva asignatura en el catálogo institucional.
- **Entidades del MER Involucradas:** `Asignatura`, `Institucion`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar ejecución y permisos RBAC.
  2. Validar que el código de la asignatura no exista previamente en la institución.
  3. Insertar nuevo registro en `dbo.Asignatura`.
  4. Retornar respuesta exitosa con el ID creado y trazabilidad.
- **Reglas de Negocio y Validaciones Específicas:**
  * Unicidad de código por institución.
- **Estado Resultante en la BD:** Nueva fila en `dbo.Asignatura`.

---

### [SP-007] - `dbo.usp_crear_coordinador`
- **Módulo / Alcance:** Administración Institucional - Coordinadores
- **Propósito de Negocio:** Registra o asigna a un usuario como Coordinador de Programa.
- **Entidades del MER Involucradas:** `Usuario`, `Coordinador`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar ejecutor y rol ADMINISTRADOR / DECANO.
  2. Sincronizar/verificar existencia del usuario.
  3. Insertar el perfil en `dbo.Coordinador`.
  4. Retornar respuesta contractual.
- **Reglas de Negocio y Validaciones Específicas:**
  * Requiere usuario activo.
- **Estado Resultante en la BD:** Fila creada en `dbo.Coordinador`.

---

### [SP-008] - `dbo.usp_crear_decano`
- **Módulo / Alcance:** Administración Institucional - Decanos
- **Propósito de Negocio:** Registra o asigna el rol de Decano a un usuario institucional.
- **Entidades del MER Involucradas:** `Usuario`, `Decano`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar ejecutor (ADMINISTRADOR).
  2. Sincronizar datos del usuario ejecutor/candidato.
  3. Crear el registro en `dbo.Decano`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Unicidad de decano activo según reglas institucionales.
- **Estado Resultante en la BD:** Fila creada en `dbo.Decano`.

---

### [SP-009] - `dbo.usp_crear_facultad`
- **Módulo / Alcance:** Estructura Orgánica - Facultades
- **Propósito de Negocio:** Crea una nueva facultad académica en la institución.
- **Entidades del MER Involucradas:** `Facultad`, `Institucion`, `Decano`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar permisos administrativos.
  2. Validar la unicidad del código y nombre de facultad.
  3. Insertar en `dbo.Facultad`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Código único de facultad por institución.
- **Estado Resultante en la BD:** Registro en `dbo.Facultad`.

---

### [SP-010] - `dbo.usp_crear_grupo`
- **Módulo / Alcance:** Oferta Académica - Grupos
- **Propósito de Negocio:** Crea un nuevo grupo académico para una asignatura y período específico.
- **Entidades del MER Involucradas:** `Grupo`, `Asignatura`, `PeriodoAcademico`, `Docente`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar ejecutor y RBAC.
  2. Verificar existencia y estado de la asignatura y período académico.
  3. Validar unicidad del código de grupo en el período.
  4. Insertar la nueva tupla en `dbo.Grupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Código único de grupo dentro del mismo período académico y asignatura.
- **Estado Resultante en la BD:** Fila creada en `dbo.Grupo`.

---

### [SP-011] - `dbo.usp_crear_periodo_academico`
- **Módulo / Alcance:** Calendario Académico - Períodos
- **Propósito de Negocio:** Registra un nuevo período o semestre académico (ej. 2026-1).
- **Entidades del MER Involucradas:** `PeriodoAcademico`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar fechas de inicio y fin del período.
  2. Validar que no exista un período con el mismo código.
  3. Insertar en `dbo.PeriodoAcademico`.
- **Reglas de Negocio y Validaciones Específicas:**
  * `fechaFin > fechaInicio`.
- **Estado Resultante en la BD:** Nuevo período registrado.

---

### [SP-012] - `dbo.usp_crear_programa_academico`
- **Módulo / Alcance:** Estructura Orgánica - Programas
- **Propósito de Negocio:** Registra un nuevo programa académico (carrera) en una facultad.
- **Entidades del MER Involucradas:** `Programa`, `Facultad`, `TipoPrograma`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia de la facultad y tipo de programa.
  2. Insertar en `dbo.Programa`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Código único de programa.
- **Estado Resultante en la BD:** Fila creada en `dbo.Programa`.

---

### [SP-013] - `dbo.usp_crear_sesion`
- **Módulo / Alcance:** Control de Asistencia - Sesiones
- **Propósito de Negocio:** Crea manualmente una sesión de clase individual dentro de un grupo.
- **Entidades del MER Involucradas:** `Sesion`, `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar permisos del ejecutor (Docente titular del grupo).
  2. Calcular el número consecutivo dentro del grupo usando `COALESCE(MAX(numero), 0) + 1` bajo bloqueos `UPDLOCK, HOLDLOCK`.
  3. Generar el código de sesión `SES-{numero}`.
  4. Insertar en `dbo.Sesion`.
- **Reglas de Negocio y Validaciones Específicas:**
  * `numero` y `codigo` únicos por grupo.
- **Estado Resultante en la BD:** Fila creada en `dbo.Sesion`.

---

### [SP-014] - `dbo.usp_ejecutar_cierre_masivo_periodo`
- **Módulo / Alcance:** Cierre Académico - Períodos
- **Propósito de Negocio:** Ejecuta el proceso administrativo de cierre de un período académico concluyendo grupos y bloqueando modificaciones tardías.
- **Entidades del MER Involucradas:** `PeriodoAcademico`, `Grupo`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el período esté en estado activo y su fecha fin haya concluido.
  2. Actualizar el estado del período a inactivo/cerrado.
  3. Registrar auditoría del proceso.
- **Reglas de Negocio y Validaciones Específicas:**
  * Proceso atómico de cierre.
- **Estado Resultante en la BD:** Período y grupos asociados marcados como cerrados.

---

### [SP-015] - `dbo.usp_establecer_contexto_usuario_ejecutor`
- **Módulo / Alcance:** Seguridad y Auditoría - Contexto
- **Propósito de Negocio:** Configura en la sesión de SQL Server (`SESSION_CONTEXT`) la identidad y rol del usuario ejecutor para la evaluación de vistas autorizadas `uv_auth_*`.
- **Entidades del MER Involucradas:** `SESSION_CONTEXT`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir `@idUsuarioEjecutor` y `@codigoPerfil`.
  2. Ejecutar `EXEC sp_set_session_context` para las claves `idUsuarioEjecutor` y `codigoPerfil`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Utilizado por la capa de aplicación antes de consultar vistas autorizadas.
- **Estado Resultante en la BD:** `SESSION_CONTEXT` de la conexión actualizado.

---

### [SP-016] - `dbo.usp_generar_sesiones_grupo`
- **Módulo / Alcance:** Oferta Académica - Programación
- **Propósito de Negocio:** Genera automáticamente todas las sesiones de clase de un grupo a lo largo del período académico según la intensidad horaria y días configurados.
- **Entidades del MER Involucradas:** `Sesion`, `Grupo`, `Horario`, `PeriodoAcademico`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar el período académico y los días/horas configurados en `Horario` para el grupo.
  2. Iterar desde la fecha de inicio hasta la fecha de fin del período.
  3. Para cada fecha coincidente con el día de clase, calcular las fechas UTC convirtiendo desde la zona horaria de SQL Server (`TIEMPO/ZONA_HORARIA_SQLSERVER`).
  4. Insertar masivamente las sesiones en `dbo.Sesion`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Conversión de zona horaria garantizada en UTC.
- **Estado Resultante en la BD:** Múltiples registros insertados en `dbo.Sesion`.

---

### [SP-017] - `dbo.usp_obtener_mensaje_catalogo`
- **Módulo / Alcance:** Utilidades de Sistema - Mensajes
- **Propósito de Negocio:** Obtiene el mensaje traducido de usuario y técnico a partir de un código de catálogo (`DBCODE`).
- **Entidades del MER Involucradas:** `CatalogoMensajeUsuario`, `CatalogoMensajeTecnico`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Buscar el código en las tablas de catálogo.
  2. Retornar los textos formateados.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si no existe mensaje técnico, devuelve mensaje por defecto.
- **Estado Resultante en la BD:** Consulta de solo lectura.

---

### [SP-018] - `dbo.usp_radicar_solicitud_revision_asistencia`
- **Módulo / Alcance:** Solicitudes y Excusas - Estudiantes
- **Propósito de Negocio:** Permite a un estudiante radicar una solicitud de revisión o excusa sobre una inasistencia registrada.
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`, `Asistencia`, `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el estudiante sea el titular de la asistencia.
  2. Validar que la asistencia esté en estado no asistió (`SJC` o `EX`).
  3. Insertar la solicitud en `dbo.SolicitudRevisionAsistencia`.
- **Reglas de Negocio y Validaciones Específicas:**
  * No se puede solicitar revisión sobre una asistencia confirmada (`AN`).
- **Estado Resultante en la BD:** Fila creada en `dbo.SolicitudRevisionAsistencia`.

---

### [SP-019] - `dbo.usp_registrar_asistencia_estudiante`
- **Módulo / Alcance:** Control de Asistencia - Faltas Individuales
- **Propósito de Negocio:** Registra la asistencia o inasistencia individual de un estudiante en una sesión.
- **Entidades del MER Involucradas:** `Asistencia`, `DetalleAsistencia`, `EstudianteGrupo`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar pertenencia activa del estudiante al grupo.
  2. Insertar/actualizar la cabecera en `Asistencia` y el detalle en `DetalleAsistencia`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Operación atómica por estudiante.
- **Estado Resultante en la BD:** Fila en `Asistencia` y `DetalleAsistencia`.

---

### [SP-020] - `dbo.usp_registrar_asistencia_estudiante_autonomo`
- **Módulo / Alcance:** Control de Asistencia - Registro QR / Token
- **Propósito de Negocio:** Permite la auto-registración de asistencia por parte del estudiante escaneando un QR/token dinámico de sesión.
- **Entidades del MER Involucradas:** `Asistencia`, `DetalleAsistencia`, `Sesion`, `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la vigencia del token/QR de la sesión.
  2. Validar que la sesión esté en curso.
  3. Registrar la asistencia del estudiante con código `AN`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Falla si el token ha expirado.
- **Estado Resultante en la BD:** Registro de asistencia confirmado.

---

### [SP-021] - `dbo.usp_registrar_asistencias_sesion` (Golden Path Main SP)
- **Módulo / Alcance:** Control de Asistencia - Golden Path Lote
- **Propósito de Negocio:** Proceso principal de toma de lista masiva por lote en formato JSON por parte del docente.
- **Entidades del MER Involucradas:** `Asistencia`, `DetalleAsistencia`, `Sesion`, `EstudianteGrupo`, `RazonCausa`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar ejecutor (DOCENTE titular del grupo).
  2. Descomprimir y parsear el arreglo JSON de asistencias.
  3. Validar de forma atómica: no duplicados, JSON válido, matrícula activa de cada estudiante.
  4. Ejecutar UPSERT atómico en `Asistencia` y `DetalleAsistencia` para cada ítem (`AN`, `SJC`, `EX`).
  5. Retornar respuesta en formato contractual.
- **Reglas de Negocio y Validaciones Específicas:**
  * Escritura atómica de todo el lote o rollback completo.
- **Estado Resultante en la BD:** Cabeceras y detalles de asistencia actualizados.

---

### [SP-022] - `dbo.usp_registrar_docente_en_grupo`
- **Módulo / Alcance:** Matrícula y Asignación - Docentes
- **Propósito de Negocio:** Asigna un docente a un grupo académico resolviendo cruces y validaciones de perfil.
- **Entidades del MER Involucradas:** `Grupo`, `Docente`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el usuario sea docente activo.
  2. Validar que no tenga cruce de horarios en otros grupos activos.
  3. Asignar `idDocente` en `dbo.Grupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Sin cruces de horario.
- **Estado Resultante en la BD:** `Grupo.idDocente` actualizado.

---

### [SP-023] - `dbo.usp_registrar_docente_en_grupo_autonomo`
- **Módulo / Alcance:** Asignación Autónomas - Docentes
- **Propósito de Negocio:** Asigna un docente a un grupo bajo modalidad autónoma o de auto-servicio con estado pendiente de confirmación.
- **Entidades del MER Involucradas:** `Grupo`, `Docente`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del docente y grupo.
  2. Asignar el docente en estado pendiente/inactivo hasta aprobación.
- **Reglas de Negocio y Validaciones Específicas:**
  * Requiere resolución posterior.
- **Estado Resultante en la BD:** Docente asignado en estado inactivo.

---

### [SP-024] - `dbo.usp_registrar_docente_en_grupo_interno`
- **Módulo / Alcance:** Asignación Interna - Helper
- **Propósito de Negocio:** Procedimiento interno auxiliar para vincular la clave foránea del docente al grupo.
- **Entidades del MER Involucradas:** `Grupo`, `Docente`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Ejecutar actualización directa de FK bajo transacciones controladas.
- **Reglas de Negocio y Validaciones Específicas:**
  * Uso interno de SPs compuestos.
- **Estado Resultante en la BD:** Actualización de `dbo.Grupo`.

---

### [SP-025] - `dbo.usp_registrar_estudiante_en_grupo`
- **Módulo / Alcance:** Matrícula - Estudiantes
- **Propósito de Negocio:** Registra formalmente a un estudiante en un grupo académico respetando cupos y prerrequisitos.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Estudiante`, `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar cupo disponible en el grupo.
  2. Validar que el estudiante no esté matriculado activamente en el mismo grupo.
  3. Insertar la matrícula en `dbo.EstudianteGrupo` con estado 'A' (Activo).
- **Reglas de Negocio y Validaciones Específicas:**
  * Control estricto de cupo máximo.
- **Estado Resultante en la BD:** Nueva fila en `dbo.EstudianteGrupo`.

---

### [SP-026] - `dbo.usp_registrar_estudiante_en_grupo_autonomo`
- **Módulo / Alcance:** Auto-matrícula - Estudiantes
- **Propósito de Negocio:** Permite la inscripción autónoma de un estudiante en un grupo en estado inactivo/pendiente de aprobación por el docente.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Grupo`, `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar datos de entrada.
  2. Insertar en `dbo.EstudianteGrupo` con estado de matrícula pendiente.
- **Reglas de Negocio y Validaciones Específicas:**
  * Requiere resolución mediante `usp_resolver_solicitud_matricula`.
- **Estado Resultante en la BD:** Fila en `EstudianteGrupo` en estado pendiente.

---

### [SP-027] - `dbo.usp_registrar_estudiante_en_grupo_interno`
- **Módulo / Alcance:** Matrícula Interna - Helper
- **Propósito de Negocio:** Helper interno para realizar la inserción física del registro de matrícula.
- **Entidades del MER Involucradas:** `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Insertar tupla en `EstudianteGrupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Invocado por SPs de nivel superior.
- **Estado Resultante en la BD:** Registro insertado.

---

### [SP-028] - `dbo.usp_registrar_estudiante_en_programa_interno`
- **Módulo / Alcance:** Inscripción Programa - Helper
- **Propósito de Negocio:** Helper interno para inscribir a un estudiante en un programa académico si aún no está vinculado.
- **Entidades del MER Involucradas:** `EstudiantePrograma`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Verificar si existe la relación estudiante-programa.
  2. Si no existe, crear la tupla en `EstudiantePrograma`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Garantiza la coherencia curricular.
- **Estado Resultante en la BD:** Registro en `EstudiantePrograma`.

---

### [SP-029] - `dbo.usp_resolver_solicitud_matricula`
- **Módulo / Alcance:** Solicitudes de Matrícula - Aprobación
- **Propósito de Negocio:** Permite al docente o coordinador aprobar o rechazar una solicitud de matrícula autónoma de estudiante.
- **Entidades del MER Involucradas:** `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar permisos del ejecutor.
  2. Si se aprueba, cambiar estado a 'A' (Activo) verificando cupo.
  3. Si se rechaza, actualizar el estado a inactivo/rechazado.
- **Reglas de Negocio y Validaciones Específicas:**
  * Control de cupo al momento de la aprobación.
- **Estado Resultante en la BD:** Estado en `EstudianteGrupo` modificado.

---

### [SP-030] - `dbo.usp_resolver_solicitud_revision_asistencia`
- **Módulo / Alcance:** Solicitudes y Excusas - Resolución
- **Propósito de Negocio:** Permite al docente aprobar o rechazar una solicitud de excusa/revisión de asistencia presentada por un estudiante.
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`, `DetalleAsistencia`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el ejecutor sea el docente titular de la sesión.
  2. Actualizar el estado de la solicitud (Aprobada / Rechazada).
  3. Si se aprueba, modificar atómicamente la razón/causa en `DetalleAsistencia` (ej. a `EX` o `AN`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Modificación atómica del detalle de asistencia en caso de aprobación.
- **Estado Resultante en la BD:** `SolicitudRevisionAsistencia` y `DetalleAsistencia` actualizados.

---

### [SP-031] - `dbo.usp_sincronizar_asistencia_estudiante_interno`
- **Módulo / Alcance:** Sincronización Interna - Asistencia
- **Propósito de Negocio:** Sincroniza o actualiza la asistencia de un estudiante garantizando las invariantes de persistencia.
- **Entidades del MER Involucradas:** `Asistencia`, `DetalleAsistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia de cabecera.
  2. Realizar `UPSERT` en `DetalleAsistencia`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Máximo un detalle por asistencia.
- **Estado Resultante en la BD:** Asistencia sincronizada.

---

### [SP-032] - `dbo.usp_sincronizar_docente_interno`
- **Módulo / Alcance:** Sincronización Interna - Docentes
- **Propósito de Negocio:** Crea o activa la tupla de rol `Docente` para un usuario institucional.
- **Entidades del MER Involucradas:** `Docente`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar si existe la tupla `(idUsuario, idInstitucion)` en `Docente`.
  2. Si no existe, insertarla en estado activo.
- **Reglas de Negocio y Validaciones Específicas:**
  * Idempotente.
- **Estado Resultante en la BD:** Fila activa en `dbo.Docente`.

---

### [SP-033] - `dbo.usp_sincronizar_estudiante_interno`
- **Módulo / Alcance:** Sincronización Interna - Estudiantes
- **Propósito de Negocio:** Crea o activa el rol `Estudiante` para un usuario.
- **Entidades del MER Involucradas:** `Estudiante`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Verificar tupla en `Estudiante`.
  2. Crear o activar según corresponda.
- **Reglas de Negocio y Validaciones Específicas:**
  * Idempotente.
- **Estado Resultante en la BD:** Fila activa en `dbo.Estudiante`.

---

### [SP-034] - `dbo.usp_sincronizar_usuario_interno`
- **Módulo / Alcance:** Sincronización Interna - Usuarios Base
- **Propósito de Negocio:** Sincroniza o crea la cuenta base en `dbo.Usuario` a partir de datos de identidad de Keycloak/SSO.
- **Entidades del MER Involucradas:** `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Buscar por número y tipo de documento o correo.
  2. Si existe, actualizar nombres y correo.
  3. Si no existe, insertar nuevo registro de usuario.
- **Reglas de Negocio y Validaciones Específicas:**
  * Evita cuentas duplicadas por documento o correo.
- **Estado Resultante en la BD:** Registro en `dbo.Usuario` creado o actualizado.

---

### [SP-035] - `dbo.usp_toggle_estado_asignatura`
- **Módulo / Alcance:** Gestión Académica - Asignaturas
- **Propósito de Negocio:** Alterna el estado activo/inactivo de una asignatura en el catálogo.
- **Entidades del MER Involucradas:** `Asignatura`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Cambiar la bandera de estado de la asignatura.
- **Reglas de Negocio y Validaciones Específicas:**
  * Requiere permisos de Coordinador o Administrador.
- **Estado Resultante en la BD:** Estado de la asignatura actualizado.

---

### [SP-036] a [SP-057] - Procedimientos Internos de Validación y Seguridad (RBAC)

* **`dbo.usp_validar_cruce_horario_docente_interno`**: Valida que un docente no tenga choques de horario en grupos activos simultáneos.
* **`dbo.usp_validar_cruce_horario_estudiante_interno`**: Verifica que las asignaturas/grupos del estudiante no colisionen en fecha y hora.
* **`dbo.usp_validar_cupo_disponible_grupo_interno`**: Verifica que las matrículas activas en `EstudianteGrupo` sean menores a `cupoMaximo`.
* **`dbo.usp_validar_docente_exista_por_id_interno`**: Verifica que el ID pertenezca a un docente válido y activo.
* **`dbo.usp_validar_estudiante_exista_por_id_interno`**: Verifica la validez y estado activo del estudiante.
* **`dbo.usp_validar_estudiante_grupo_exista_interno`**: Confirma la existencia del registro de matrícula `EstudianteGrupo`.
* **`dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno`**: Valida si el estudiante pertenece activamente al grupo de la sesión.
* **`dbo.usp_validar_fechas_periodo_academico_interno`**: Valida que la fecha de inicio sea menor a la fecha fin del período.
* **`dbo.usp_validar_grupo_exista_para_docente_interno`**: Verifica que el grupo esté asignado al docente especificado.
* **`dbo.usp_validar_grupo_exista_por_id_interno`**: Confirma la existencia del grupo.
* **`dbo.usp_validar_horarios_grupo_interno`**: Valida la congruencia horaria configurada para el grupo.
* **`dbo.usp_validar_id_correlacion_esta_presente_interno`**: Valida la presencia de `@idCorrelacion` (Retorna `GEN_002` si es NULL).
* **`dbo.usp_validar_id_interno`**: Valida que un UUID/GUID sea válido y no nulo.
* **`dbo.usp_validar_perfil_existe_por_codigo_interno`**: Confirma la existencia del código de perfil en el catálogo.
* **`dbo.usp_validar_permiso_rbac_usuario_interno`**: Valida los permisos de rol (RBAC) del usuario sobre el recurso. Retorna `SEC_001` si falla.
* **`dbo.usp_validar_prerrequisitos_asignatura_estudiante_interno`**: Verifica prerrequisitos de asignatura para el estudiante.
* **`dbo.usp_validar_registro_estudiante_en_grupo_interno`**: Valida condiciones para permitir el registro en grupo.
* **`dbo.usp_validar_sesion_exista_por_id_interno`**: Verifica la existencia de la sesión de clase.
* **`dbo.usp_validar_tipo_identificacion_exista_por_id_interno`**: Confirma la validez del tipo de documento.
* **`dbo.usp_validar_titularidad_jerarquica_interno`**: Valida si el usuario ejecutor es titular jerárquico del recurso. Retorna `SEC_002` si falla.
* **`dbo.usp_validar_unicidad_usuario_interno`**: Revisa que no existan documentos o correos duplicados.
* **`dbo.usp_validar_usuario_existe_por_id_interno`**: Valida la presencia activa del usuario en `dbo.Usuario`.

---

# 2. 👁️ VISTAS (VIEWS)

Las vistas de la base de datos se clasifican en vistas de catálogo/proyección general y **vistas autorizadas por RBAC (`uv_auth_*`)**, las cuales se filtran dinámicamente según el `SESSION_CONTEXT`.

### 2.1 Vistas Principales de Catálogo y Proyección

1. **`dbo.uv_administrador`**: Proyecta la lista de usuarios con perfil Administrador e información de institución.
2. **`dbo.uv_area`**: Expone las áreas académicas registradas.
3. **`dbo.uv_asignatura`**: Proyecta las asignaturas registradas, sus créditos, intensidad horaria y estado.
4. **`dbo.uv_asistencia`**: Proyecta las cabeceras de asistencia registradas para las sesiones (`id`, `idEstudianteGrupo`, `idSesion`).
5. **`dbo.uv_componente`**: Expone los componentes curriculares de los planes de estudio.
6. **`dbo.uv_coordinador`**: Lista de coordinadores de programa activos con sus datos de vinculación.
7. **`dbo.uv_coordinador_identidad`**: Proyección extendida del coordinador incluyendo nombres, documento y correo.
8. **`dbo.uv_decano`**: Lista de decanos de facultad.
9. **`dbo.uv_decano_identidad`**: Proyección de datos personales e identidad de decanos.
10. **`dbo.uv_detalle_asistencia`**: Proyección detallada del estado de asistencia por estudiante (`id`, `codigo`, `idAsistencia`, `asistio`, `codigoRazonCausa`, `fechaHoraInicio`, `fechaHoraFin`).
11. **`dbo.uv_dia`**: Catálogo de días de la semana (Lunes a Domingo).
12. **`dbo.uv_docente`**: Catálogo de docentes institucionales.
13. **`dbo.uv_docente_identidad`**: Proyección de datos de identidad de los docentes.
14. **`dbo.uv_estadistica_grupo`**: Métrica consolidada de asistencias, inasistencias y porcentajes de ausentismo por grupo.
15. **`dbo.uv_estado`**: Catálogo general de estados del sistema.
16. **`dbo.uv_estado_estudiante_grupo`**: Catálogo de estados de inscripción de estudiante en grupo (ej. Matriculado 'A').
17. **`dbo.uv_estudiante`**: Registro general de estudiantes.
18. **`dbo.uv_estudiante_grupo`**: Proyección de estudiantes matriculados en grupos académicos (`id`, `idEstudiante`, `idGrupo`, `nombreEstadoEstudiante`).
19. **`dbo.uv_estudiante_identidad`**: Proyección de identidad de estudiantes.
20. **`dbo.uv_estudiante_programa`**: Vinculación de estudiantes con sus programas académicos.
21. **`dbo.uv_facultad`**: Listado de facultades e información de decanos titulares.
22. **`dbo.uv_grupo`**: Oferta de grupos académicos por asignatura y período.
23. **`dbo.uv_horario`**: Franjas horarias asignadas a los grupos.
24. **`dbo.uv_horario_docente`**: Horario consolidado por docente (`idDocente`, `idGrupo`, `codigoMateria`, `horaInicio`, `horaFin`, `totalEstudiantes`).
25. **`dbo.uv_horario_estudiante`**: Horario consolidado de clases para cada estudiante.
26. **`dbo.uv_institucion`**: Catálogo de instituciones configuradas.
27. **`dbo.uv_mensaje_tecnico`**: Catálogo de mensajes técnicos contractuales (`DBCODE`).
28. **`dbo.uv_mensaje_usuario`**: Catálogo de mensajes entendibles por el usuario final.
29. **`dbo.uv_parametro`**: Parámetros de configuración del sistema (`grupo`, `clave`, `valor`, `estaActivo`).
30. **`dbo.uv_perfil`**: Catálogo de perfiles institucionales.
31. **`dbo.uv_periodo_academico`**: Períodos académicos y sus fechas de inicio y fin.
32. **`dbo.uv_plan_estudio`**: Planes de estudio institucionales.
33. **`dbo.uv_programa`**: Programas académicos (carreras).
34. **`dbo.uv_razon_causa`**: Catálogo de razones y causas de asistencia/inasistencia (`AN`, `SJC`, `EX`).
35. **`dbo.uv_semestre`**: Catálogo de semestres de la carrera.
36. **`dbo.uv_semestre_plan_estudio`**: Distribución de semestres en los planes de estudio.
37. **`dbo.uv_sesion`**: Sesiones de clase de los grupos (`id`, `nombre`, `numero`, `codigo`, `fechaHoraInicio`, `fechaHoraFin`).
38. **`dbo.uv_solicitud_revision_asistencia`**: Solicitudes de revisión de asistencia radicadas.
39. **`dbo.uv_tipo_identificacion`**: Catálogo de tipos de documento de identidad.
40. **`dbo.uv_tipo_programa`**: Catálogo de tipos de programa (Pregrado/Posgrado).
41. **`dbo.uv_usuario`**: Usuarios registrados en el sistema.
42. **`dbo.uv_usuario_autenticacion`**: Vista para consulta de credenciales y autenticación.
43. **`dbo.uv_usuario_perfil`**: Perfiles asignados a cada usuario.

### 2.2 Vistas Autorizadas por Seguridad RBAC (`uv_auth_*`)
Estas vistas aplican la política *fail-closed*: si no hay `SESSION_CONTEXT` activo, retornan 0 filas.

44. **`dbo.uv_auth_asistencia`**: Asistencias visibles únicamente según el rol y titularidad del usuario en sesión.
45. **`dbo.uv_auth_coordinador`**: Coordinadores accesibles según jurisdicción de facultad o institución.
46. **`dbo.uv_auth_decano`**: Decanos visibles según el ámbito del ejecutor.
47. **`dbo.uv_auth_docente`**: Docentes pertenecientes al ámbito permitido para el usuario en sesión.
48. **`dbo.uv_auth_estudiante`**: Estudiantes visibles (el docente solo ve sus grupos, el coordinador sus programas).
49. **`dbo.uv_auth_facultad`**: Facultades autorizadas.
50. **`dbo.uv_auth_grupo`**: Grupos autorizados según rol (Docentes ven solo sus grupos titulares).
51. **`dbo.uv_auth_institucion`**: Instituciones permitidas según perfil.
52. **`dbo.uv_auth_periodo_academico`**: Períodos académicos autorizados.
53. **`dbo.uv_auth_programa`**: Programas académicos visibles según perfil.
54. **`dbo.uv_auth_sesion`**: Sesiones de clase a las que el usuario tiene autorización de acceso/modificación.
55. **`dbo.uv_auth_solicitud_revision_asistencia`**: Solicitudes de revisión pertenecientes al docente titular o estudiante radicante.

---

# 3. 🧪 FUNCIONES (FUNCTIONS)

La base de datos cuenta con **15 funciones escalar/tabla** divididas en utilidades de validación, consulta de parámetros y lectura de contexto:

1. **`dbo.fn_diagramobjects`**: Función técnica interna de SQL Server para soporte de diagramas de base de datos.
2. **`dbo.ufn_obtener_detalle_error`**: Construye la cadena contractual del canal técnico de error en formato `DBCODE=<catalog-code>|<technical-detail>`.
3. **`dbo.ufn_obtener_estado_estudiante_grupo`**: Retorna el ID del estado de la matrícula en grupo a partir de su código funcional (ej. 'A' para Activo).
4. **`dbo.ufn_obtener_mensaje_desde_plantilla`**: Reemplaza marcadores de posición `{0}`, `{1}` en plantillas de mensajes del catálogo.
5. **`dbo.ufn_obtener_parametro`**: Obtiene el valor genérico en texto de un parámetro desde `CatalogoParametro` según su clave.
6. **`dbo.ufn_obtener_parametro_guid`**: Obtiene el valor de un parámetro del sistema convertido al tipo de dato `UNIQUEIDENTIFIER`.
7. **`dbo.ufn_obtener_parametro_int`**: Obtiene el valor de un parámetro convertido a entero (`INT`).
8. **`dbo.ufn_obtener_parametro_texto`**: Obtiene la cadena de texto de un parámetro configurado en `CatalogoParametro`.
9. **`dbo.ufn_obtener_perfil_usuario_contexto`**: Lee desde `SESSION_CONTEXT` el código de perfil activo del usuario ejecutor (`codigoPerfil`).
10. **`dbo.ufn_obtener_usuario_ejecutor_contexto`**: Lee desde `SESSION_CONTEXT` el GUID del usuario ejecutor (`idUsuarioEjecutor`).
11. **`dbo.ufn_reemplazar_plantilla_mensaje`**: Función auxiliar de formateo para sustituir variables en textos de respuesta.
12. **`dbo.ufn_validar_correo`**: Valida mediante expresiones regulares la sintaxis del correo electrónico institucional.
13. **`dbo.ufn_validar_numero`**: Verifica que una cadena contenga exclusivamente caracteres numéricos válidos.
14. **`dbo.ufn_validar_password`**: Valida las políticas de complejidad de contraseñas de usuario.
15. **`dbo.ufn_validar_texto`**: Valida que una cadena de texto cumpla con longitud mínima/máxima y no sea nula o vacía.

---
