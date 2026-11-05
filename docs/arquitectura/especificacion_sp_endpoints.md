# Especificación Técnica: Procedimientos Almacenados y Endpoints del Sistema de Gestión de Asistencias UCO

> [!IMPORTANT]
> Este documento define operaciones **atómicas orientadas a intención de dominio**, no CRUDs genéricos. Cada procedimiento encapsula una transacción de negocio completa con sus validaciones, bloqueos de concurrencia y auditoría.

---

## Convenciones

- **SP Orquestador (`usp_*`)**: Procedimiento expuesto al Backend vía `SimpleJdbcCall` o `JdbcTemplate.queryForMap`. Retorna siempre el bloque unificado `(idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)`.
- **SP Interno (`usp_*_interno`)**: Procedimiento invocado exclusivamente por orquestadores. Recibe/retorna parámetros `OUTPUT`. **Nunca** invocado directamente desde Spring Boot.
- **Operación Simple**: Mutación de 1 entidad/1 campo sin lógica multientidad → se ejecuta con `JdbcTemplate` parametrizado en el `*RepositorySqlServerAdapter` del Backend, **sin SP**.
- **Lectura/Consulta**: Se ejecuta contra vistas (`uv_*`) desde el Backend con `NamedParameterJdbcTemplate` y paginación nativa `OFFSET/FETCH`. **Sin SP**.

---

# PARTE 1: Especificación de Transacciones por Módulo

---

## Módulo 1: Control de Asistencia (Core Transaccional)

### Tablas implicadas
| Tabla | Columnas clave | FK principales |
|:---|:---|:---|
| `Asistencia` | `id`, `estudianteGrupo`, `sesion` | `FK → EstudianteGrupo`, `FK → Sesion` |
| `DetalleAsistencia` | `id`, `codigo`, `asistencia`, `asistio`, `razonCausa`, `fechaHoraInicio`, `fechaHoraFin` | `FK → Asistencia`, `FK → RazonCausa` |
| `EstudianteGrupo` | `id`, `estado`, `estudiante`, `grupo` | `FK → EstadoEstudianteGrupo`, `FK → Estudiante`, `FK → Grupo` |
| `Sesion` | `id`, `nombre`, `numero`, `codigo`, `numeroSemana`, `grupo`, `fechaHoraInicio`, `fechaHoraFin` | `FK → Grupo` |
| `RazonCausa` | `id`, `nombre`, `codigo` | — (paramétrica) |

### Transacción 1.1: Registrar Asistencia Masiva por Planilla

- **Intención de negocio**: El docente toma asistencia de toda la lista de estudiantes de una sesión en una sola operación.
- **Atomicidad requerida**: N estudiantes deben registrarse en una misma transacción. Si falla uno, se revierte todo.
- **Lógica de validación**:
  1. Validar que la sesión exista (`usp_validar_sesion_exista_por_id_interno`).
  2. Para cada estudiante del lote, validar que pertenezca activamente al grupo de la sesión (`usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno`).
  3. Resolver el `RazonCausa.id` **existente** a partir del código enviado. Estados públicos del batch: `'AN'`, `'SJC'`, `'EX'` (única lista aceptada; `A`, `F`, `T`, `J` y otros → `RC_001`). `RazonCausa` es catálogo cerrado: no se crean filas dinámicamente.
  4. Insertar o actualizar en `Asistencia` + `DetalleAsistencia`.
- **Seguridad**: `@idUsuarioEjecutor` = `Usuario.id` (requerido semánticamente; `NULL` → `GEN_002`), perfil `DOCENTE` y titularidad de la sesión (`Sesion → Grupo → Docente.id → uv_docente_identidad.idUsuario`).
- **Lectura**: el estado se lee vía `uv_detalle_asistencia.codigoRazonCausa`.
- **Concurrencia**: el lote se valida completo antes de escribir y es atómico (`BEGIN TRANSACTION ... COMMIT`, o `SAVE TRANSACTION` bajo transacción externa; cualquier fallo revierte todo el lote).
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_validar_permiso_rbac_usuario_interno`
  - `usp_validar_titularidad_jerarquica_interno`
  - `usp_validar_sesion_exista_por_id_interno`
  - `usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno` (por cada estudiante)
  - `usp_sincronizar_asistencia_estudiante_interno` (por cada estudiante)

### Transacción 1.2: Auto-Registro de Asistencia por Token/QR (Estudiante)

- **Intención de negocio**: El estudiante escanea un código QR o ingresa un PIN de 6 dígitos para marcar su propia asistencia en una sesión abierta.
- **Atomicidad requerida**: Validar token/PIN + validar matrícula activa + registrar asistencia en una transacción.
- **Lógica de validación**:
  1. Validar que el token/PIN coincida con el generado para la sesión y no haya expirado (TTL 60s).
  2. Validar que la sesión esté dentro de la ventana temporal (inicio – tolerancia ↔ fin).
  3. Validar que el estudiante esté matriculado y activo en el grupo de la sesión. Si no lo está, **rechazar con excepción** (no autovivificar).
  4. Validar que no exista ya un registro previo de asistencia para esa sesión (idempotencia).
  5. Insertar en `Asistencia` + `DetalleAsistencia` con `RazonCausa = 'AN'` (asistencia normal).
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_validar_sesion_abierta_con_ventana_temporal_interno`
  - `usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno`
  - `usp_sincronizar_asistencia_estudiante_interno`

---

## Módulo 2: Gestión de Sesiones y Calendario

### Tablas implicadas
| Tabla | Columnas clave | FK principales |
|:---|:---|:---|
| `Sesion` | `id`, `nombre`, `numero`, `codigo`, `numeroSemana`, `grupo`, `fechaHoraInicio`, `fechaHoraFin` | `FK → Grupo` |
| `Horario` | `id`, `grupo`, `dia`, `horaInicio`, `horaFin` | `FK → Grupo`, `FK → Dia` |
| `Grupo` | `id`, `asignatura`, `periodoAcademico`, `codigo`, `nombre`, `cantidadEstudiantes`, `docente` | `FK → Asignatura`, `FK → PeriodoAcademico`, `FK → Docente` |
| `PeriodoAcademico` | `id`, `institucion`, `nombre`, `codigo`, `fechaInicio`, `fechaFin`, `anio` | `FK → Institucion` |
| `Dia` | `id`, `nombre`, `codigo` | — (paramétrica) |

### Transacción 2.1: Crear Sesión Ordinaria/Extraordinaria (con Correlativo Atómico)

- **Intención de negocio**: El docente crea una nueva sesión de clase para un grupo, asignándole un número y código secuencial único.
- **Atomicidad requerida**: El cálculo de `MAX(numero) + 1` y la inserción deben ocurrir en la misma transacción con bloqueo pesimista para evitar correlativos duplicados bajo concurrencia.
- **Lógica de validación**:
  1. Validar correlación (`usp_validar_id_correlacion_esta_presente_interno`).
  2. Validar que el grupo exista (`usp_validar_grupo_exista_por_id_interno`) y la titularidad del ejecutor (`usp_validar_titularidad_jerarquica_interno`).
  3. Calcular `@numeroSiguiente = MAX(numero) + 1` con `WITH (UPDLOCK, HOLDLOCK)` sobre `dbo.Sesion`.
  4. Generar código `SES-XX`.
  5. Insertar en `dbo.Sesion`.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_validar_titularidad_jerarquica_interno`

### Transacción 2.2: Cierre de Sesión Legacy No Soportado

- **Intención de negocio**: Contrato histórico no soportado por el shape vigente. `dbo.Sesion` no posee estado/cierre persistible.
- **Atomicidad requerida**: Cero escrituras.
- **Lógica de validación**:
  1. Retornar `SES_003`.
  2. `estadoResultado = 0`.
  3. No crear ausencias para estudiantes omitidos.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_validar_sesion_exista_por_id_interno`
  - `usp_validar_titularidad_jerarquica_interno`
  - `usp_marcar_ausencias_pendientes_sesion_interno` *(nuevo)*

### Transacción 2.3: Cancelar Sesión con Motivo

- **Intención de negocio**: El docente cancela una sesión programada registrando el motivo de la cancelación.
- **Atomicidad requerida**: Cambiar estado de la sesión + registrar motivo en una transacción. Las asistencias parcialmente tomadas deben anularse.
- **Lógica de validación**:
  1. Validar existencia de la sesión y titularidad del docente.
  2. No validar cierre persistido porque `dbo.Sesion` no contiene esa columna.
  3. Anular registros existentes de `DetalleAsistencia` para esa sesión.
  4. Marcar la sesión como cancelada con el motivo proporcionado.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_validar_sesion_exista_por_id_interno`
  - `usp_validar_titularidad_jerarquica_interno`

### Transacción 2.4: Generar Sesiones Masivas del Semestre

- **Intención de negocio**: Dado un grupo con horarios semanales configurados, generar automáticamente todas las sesiones para las semanas del periodo académico.
- **Atomicidad requerida**: Todas las sesiones del semestre se generan en una transacción. Si falla la generación de una sesión, se revierte todo.
- **Lógica de validación**:
  1. Validar existencia del grupo.
  2. Validar existencia de franjas horarias en `dbo.Horario`.
  3. Validar coherencia de fechas del periodo académico.
  4. Iterar cada día calendario del periodo, cruzando con los horarios configurados.
  5. Insertar en `dbo.Sesion` evitando duplicación por fecha+hora.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_validar_grupo_exista_por_id_interno`
  - `usp_validar_horarios_grupo_interno`
  - `usp_validar_fechas_periodo_academico_interno`

---

## Módulo 3: Matrículas e Inscripciones Académicas

### Tablas implicadas
| Tabla | Columnas clave | FK principales |
|:---|:---|:---|
| `EstudianteGrupo` | `id`, `estado`, `estudiante`, `grupo` | `FK → EstadoEstudianteGrupo`, `FK → Estudiante`, `FK → Grupo` |
| `EstudiantePrograma` | `id`, `estudiante`, `programa` | `FK → Estudiante`, `FK → Programa` |
| `Grupo` | `id`, `cantidadEstudiantes`, `docente`, ... | `FK → Asignatura`, `FK → PeriodoAcademico`, `FK → Docente` |
| `EstadoEstudianteGrupo` | `id`, `nombre`, `codigo` | — (paramétrica: `A`, `F`, `CVP`, `CI`) |

### Transacción 3.1: Matricular Estudiante en Grupo (con Control de Cupo y Cruce Horario)

- **Intención de negocio**: Inscribir a un estudiante en un grupo académico garantizando que hay cupo disponible y no existe cruce de horarios.
- **Atomicidad requerida**: La lectura de cupo y la inserción del registro deben ser atómicas con bloqueo `WITH (UPDLOCK)` sobre el grupo.
- **Lógica de validación**:
  1. Validar existencia y estado activo del estudiante.
  2. Validar existencia y habilitación del grupo.
  3. Validar que el estudiante no esté ya matriculado en ese grupo (unicidad).
  4. Validar cruce de horarios con otros grupos del estudiante.
  5. Validar cupo disponible (`cuposDisponibles > 0` en `uv_grupo`).
  6. Insertar en `EstudianteGrupo` con estado `'A'` (Activo).
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_validar_estudiante_exista_por_id_interno`
  - `usp_validar_grupo_exista_por_id_interno`
  - `usp_validar_registro_estudiante_en_grupo_interno`
  - `usp_validar_cruce_horario_estudiante_interno`

### Transacción 3.2: Retirar Estudiante de Grupo (Cancelación Voluntaria)

- **Intención de negocio**: Retirar a un estudiante de un grupo, liberando el cupo y cambiando su estado a `'CVP'` (Cancelado por Voluntad Propia).
- **Atomicidad requerida**: Cambiar el estado de la matrícula + actualizar el contador del grupo.
- **Lógica de validación**:
  1. Validar que exista la relación activa en `EstudianteGrupo`.
  2. Cambiar estado a `'CVP'` (no eliminar físicamente para preservar historial).
  3. Actualizar `cantidadEstudiantesCancelaronVoluntadPropia` en `dbo.Grupo`.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`

### Transacción 3.3: Asignar o Reasignar Docente a Grupo

> **Estado (2026-10-29):** el docente del grupo se asigna hoy en `usp_crear_grupo` y `usp_actualizar_grupo`. El SP `usp_registrar_docente_en_grupo` y su interno se eliminaron por no tener uso. `usp_validar_cruce_horario_docente_interno` aplica la regla "un docente no puede tener dos grupos a la misma hora": `usp_actualizar_grupo` la invoca al cambiar el titular (HOR_002, HTTP 409). `usp_crear_grupo` no la necesita porque el grupo nace sin horario.

- **Intención de negocio**: Asignar un nuevo docente titular a un grupo o transferir la titularidad.
- **Atomicidad requerida**: Validar disponibilidad horaria del nuevo docente en todos los bloques del grupo antes de la reasignación.
- **Lógica de validación**:
  1. Validar existencia y estado activo del docente.
  2. Validar que el grupo existe.
  3. Validar cruce de horarios del docente con otros grupos que ya tenga asignados.
  4. Actualizar `Grupo.docente`.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_validar_docente_exista_por_id_interno`
  - `usp_validar_grupo_exista_por_id_interno`
  - `usp_validar_cruce_horario_docente_interno`

### Transacción 3.4: Resolver Solicitud de Matrícula (Coordinador)

> **ELIMINADO (2026-10-29):** `usp_resolver_solicitud_matricula` era un stub sin tabla `SolicitudMatricula` y se borró por no tener uso. El flujo vigente es el de solicitudes de ingreso (HU053-HU055, `usp_resolver_solicitud_ingreso_grupo`). El texto siguiente es histórico.

- **Intención de negocio**: El coordinador aprueba o rechaza una solicitud de inscripción de un estudiante a un grupo. Si aprueba, ejecuta automáticamente la matrícula con las mismas validaciones de cupo y cruce horario.
- **Atomicidad requerida**: Actualizar estado de la solicitud + ejecutar la matrícula (si aplica) en una transacción.
- **Lógica de validación**:
  1. Validar existencia de la solicitud en estado pendiente.
  2. Validar que el coordinador tenga ámbito sobre el programa del grupo.
  3. Si acción = `'APROBADA'`: ejecutar `usp_registrar_estudiante_en_grupo_interno`.
  4. Si acción = `'RECHAZADA'`: solo actualizar estado de la solicitud con respuesta.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_registrar_estudiante_en_grupo_interno` (condicionalmente)

---

## Módulo 4: Solicitudes de Revisión de Asistencia (Reclamos)

### Tablas implicadas
| Tabla | Columnas clave | FK principales |
|:---|:---|:---|
| `SolicitudRevisionAsistencia` | `id`, `nombre`, `asistencia`, `fecha`, `estado`, `justificacionSolicitud`, `justificacionRespuesta` | `FK → Asistencia`, `FK → Estado` |
| `Asistencia` | `id`, `estudianteGrupo`, `sesion` | `FK → EstudianteGrupo`, `FK → Sesion` |
| `DetalleAsistencia` | `id`, `asistencia`, `asistio`, `razonCausa` | `FK → Asistencia`, `FK → RazonCausa` |
| `Estado` | `id`, `nombre`, `codigo` | — (paramétrica: `A` = Aceptada, `R` = Rechazada) |

### Transacción 4.1: Radicar Solicitud de Revisión (Estudiante)

- **Intención de negocio**: Un estudiante solicita la revisión de su asistencia para una sesión donde fue registrado como ausente, adjuntando justificación y soporte documental.
- **Atomicidad requerida**: Crear la solicitud + crear el registro de `Asistencia` si no existe (para vincular la solicitud) en una transacción.
- **Lógica de validación**:
  1. Validar existencia del estudiante.
  2. Validar existencia de la sesión.
  3. Validar que el estudiante pertenezca al grupo de la sesión.
  4. Validar plazo reglamentario de reclamación (configurable en `CatalogoParametro`: `ASISTENCIA.DIAS_LIMITE_JUSTIFICACION = 5`).
  5. Crear `Asistencia` si no existe. Insertar `SolicitudRevisionAsistencia` con estado `'PEND'` (Pendiente).
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_validar_estudiante_exista_por_id_interno`
  - `usp_validar_sesion_exista_por_id_interno`
  - `usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno`

### Transacción 4.2: Resolver Solicitud de Revisión (Docente/Coordinador)

- **Intención de negocio**: El docente titular (o coordinador) aprueba o rechaza una justificación de inasistencia. Si se aprueba, la asistencia se muta atómicamente a `asistio = 1` con `RazonCausa = 'EX'` (Excusa).
- **Atomicidad requerida**: Actualizar estado de la solicitud + mutar `DetalleAsistencia` (si se aprueba) en una transacción.
- **Lógica de validación**:
  1. Validar que la solicitud exista y esté en estado pendiente.
  2. Validar que el docente sea titular del grupo asociado a la sesión de la solicitud (ámbito RBAC).
  3. Si acción = `'APROBADA'`: `UPDATE DetalleAsistencia SET asistio = 1, razonCausa = <ID de 'EX'>`.
  4. Si acción = `'RECHAZADA'`: Solo actualizar estado + respuesta.
  5. Registrar trazabilidad.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`

---

## Módulo 5: Gestión de Identidad Institucional y Roles

### Tablas implicadas
| Tabla | Columnas clave | FK principales |
|:---|:---|:---|
| `Usuario` | `id`, `tipoIdIdentificacion`, `numeroIdentificacion`, `primerNombre`, `segundoNombre`, `primerApellido`, `segundoApellido`, `correo`, `correoConfirmado`, `estado`, `password` | `FK → TipoIdentificacion` |
| `Decano` | `id`, `usuario` | `FK → Usuario` |
| `Coordinador` | `id`, `usuario` | `FK → Usuario` |
| `Docente` | `id`, `usuario` | `FK → Usuario` |
| `Estudiante` | `id`, `usuario` | `FK → Usuario` |
| `Facultad` | `id`, `nombre`, `institucion`, `decano`, `estado` | `FK → Institucion`, `FK → Decano` |
| `Programa` | `id`, `facultad`, `tipoDePrograma`, `nombre`, `coordinador`, `estado` | `FK → Facultad`, `FK → TipoPrograma`, `FK → Coordinador` |

### Transacción 5.1: Designar Decano y Adscribirlo a Facultad

- **Intención de negocio**: El administrador crea un nuevo decano (o reutiliza un usuario existente) y lo asigna como decano titular de una facultad específica.
- **Atomicidad requerida**: Crear/reutilizar usuario + crear rol Decano + actualizar `Facultad.decano` en una transacción.
- **Lógica de validación**:
  1. Validar correlación.
  2. Resolver la facultad destino por ID o por nombre.
  3. Buscar si ya existe un `Usuario` con el correo o número de identificación. Si no existe, crearlo via `usp_sincronizar_usuario_interno`.
  4. Verificar si ya existe un `Decano` vinculado a ese usuario. Si no, crear el registro.
  5. Asignar el decano a la facultad: `UPDATE Facultad SET decano = @idDecano`.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_sincronizar_usuario_interno` (condicionalmente)
  - `usp_validar_unicidad_usuario_interno`

### Transacción 5.2: Designar Coordinador y Adscribirlo a Programa

- **Intención de negocio**: El decano crea un nuevo coordinador y lo asigna como coordinador titular de un programa académico de su facultad.
- **Atomicidad requerida**: Crear/reutilizar usuario + crear rol Coordinador + actualizar `Programa.coordinador` en una transacción.
- **Lógica de validación**:
  1. Validar correlación.
  2. Validar que el programa exista.
  3. Validar que el programa pertenezca a la facultad del decano (ámbito RBAC).
  4. Crear/reutilizar usuario y rol coordinador.
  5. Asignar: `UPDATE Programa SET coordinador = @idCoordinador`.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_sincronizar_usuario_interno` (condicionalmente)
  - `usp_validar_unicidad_usuario_interno`

### Transacción 5.3: Sincronizar Usuario Institucional

- **Intención de negocio**: Garantizar que un usuario autenticado existe en la tabla `Usuario` con todos sus datos biográficos, creándolo o actualizándolo según corresponda.
- **Atomicidad requerida**: Validaciones de unicidad + inserción/actualización en una transacción.
- **Lógica de validación**:
  1. Validar tipo de identificación.
  2. Validar unicidad de correo y número de documento.
  3. Insertar o actualizar `Usuario`.
- **Procedimientos internos invocados**:
  - `usp_validar_tipo_identificacion_exista_por_id_interno`
  - `usp_validar_unicidad_usuario_interno`

---

## Módulo 6: Cierre Masivo de Periodo Académico

### Tablas implicadas
| Tabla | FK | Descripción |
|:---|:---|:---|
| `EstudianteGrupo` | `FK → Estudiante, Grupo, EstadoEstudianteGrupo` | Registros de matrícula activa a procesar |
| `Grupo` | `FK → Asignatura, PeriodoAcademico, Docente` | Contadores de finalizados/cancelados |
| `DetalleAsistencia` | `FK → Asistencia, RazonCausa` | Cálculo de inasistencias acumuladas |
| `PeriodoAcademico` | `FK → Institucion` | Período objetivo del cierre |
| `AuditoriaEvento` | — | Registro de auditoría del cierre |

### Transacción 6.1: Ejecutar Cierre Masivo de Periodo

- **Intención de negocio**: Al finalizar el semestre, procesar todos los grupos del periodo: marcar como `'CI'` (Cancelado por Inasistencia) a los estudiantes que superan el umbral de faltas, marcar como `'F'` (Finalizado) al resto, y actualizar los contadores en `Grupo`.
- **Atomicidad requerida**: Todo el cierre del periodo se ejecuta en una sola transacción. Si falla cualquier paso, se revierte todo.
- **Lógica de validación**:
  1. Validar correlación.
  2. Resolver el periodo académico por código o nombre.
  3. Calcular inasistencias acumuladas por estudiante/grupo usando `DetalleAsistencia` (umbral: ≥ 20% configurable en `CatalogoParametro`).
  4. Actualizar estados masivamente en `EstudianteGrupo`.
  5. Actualizar contadores en `Grupo`.
  6. Insertar evento en `AuditoriaEvento`.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`

---

## Módulo 7: Gestión de Grupo del Docente

### Transacción 7.1: Crear Grupo Académico (con Validación de Unicidad de Código)

- **Intención de negocio**: El docente o coordinador crea un nuevo grupo para una asignatura en un periodo académico.
- **Lógica de validación**:
  1. Validar existencia de la asignatura.
  2. Resolver periodo académico (si viene nulo, usar el más reciente).
  3. Validar existencia y estado activo del docente.
  4. Validar unicidad de código de grupo dentro de la asignatura/periodo.
  5. Insertar en `dbo.Grupo` con contadores en 0.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_validar_docente_exista_por_id_interno`

---

# PARTE 2: Matriz Técnica de Mapeo

---

## Módulo: Control de Asistencia

| Tabla | Transacción / Acción de Negocio | Procedimiento Almacenado (BD) | Método del Controlador (Backend) | Rol / Permiso Requerido | Descripción del procedimiento |
|:---|:---|:---|:---|:---|:---|
| `Asistencia`, `DetalleAsistencia` | Registrar asistencia masiva por planilla | `usp_registrar_asistencias_sesion` | `POST /api/v1/asistencias/lote` | `DOCENTE` (titular del grupo) | Recibe JSON array con elementos exactos `idEstudiante` y estado (`AN`/`SJC`/`EX`) y `@idUsuarioEjecutor` (`Usuario.id`, requerido). Valida RBAC docente, titularidad de la sesión, existencia de sesión, JSON completo, duplicados y pertenencia activa de cada estudiante antes de escribir. Lote parcial permitido; estudiante omitido = sin registro. Sincroniza asistencia en transacción atómica e idempotente. |
| `Asistencia`, `DetalleAsistencia` | Auto-registro de asistencia por QR/PIN | `usp_registrar_asistencia_estudiante_autonomo` | `POST /api/v1/estudiante/asistencia-qr` | `ESTUDIANTE` (matriculado en grupo) | Valida token/PIN efímero (TTL 60s) generado por el docente. Verifica que la sesión esté dentro de la ventana temporal. Valida matrícula activa del estudiante (sin autovivificación). Registra asistencia como `'AN'` (Asistencia Normal). Invoca internamente: `usp_validar_sesion_abierta_con_ventana_temporal_interno`, `usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno`, `usp_sincronizar_asistencia_estudiante_interno`. |
| `Sesion` | Generar token/PIN efímero para asistencia | — *(Backend Java)* | `GET /api/v1/sesiones/{id}/qr-token` | `DOCENTE` (titular del grupo) | Genera un token UUID + PIN de 6 dígitos con expiración de 60 segundos en memoria (sin SP, lógica en Spring Boot `AsistenciaQrController`). |

## Módulo: Gestión de Sesiones

| Tabla | Transacción / Acción de Negocio | Procedimiento Almacenado (BD) | Método del Controlador (Backend) | Rol / Permiso Requerido | Descripción del procedimiento |
|:---|:---|:---|:---|:---|:---|
| `Sesion` | Crear sesión ordinaria o extraordinaria | `usp_crear_sesion` | `POST /api/v1/sesiones` | `DOCENTE` (titular del grupo) | Firma pública sin `@idDocente`: recibe `@idGrupo`, `@nombre`, `@fechaHoraInicio`, `@fechaHoraFin`, `@idCorrelacion`, `@idUsuarioEjecutor`. Valida RBAC docente y titularidad del grupo resolviendo `Usuario.id -> Docente.id`. Fechas inicio/fin son obligatorias y `fechaHoraFin > fechaHoraInicio`. Calcula `numero = COALESCE(MAX(numero), 0) + 1` por grupo (no `COUNT(*)`) y `codigo` (`SES-01`...`SES-99`, `SES-100+` sin truncar) dentro de la misma transacción (ownership propia o savepoint), protegida con `UPDLOCK, HOLDLOCK` y respaldada por los índices `UNIQUE` `UX_Sesion_Grupo_Numero`/`UX_Sesion_Grupo_Codigo`. |
| `Sesion` | Cierre legacy no soportado | `usp_cerrar_sesion` | No incluir en contrato backend target | N/A | Retorna `SES_003`, `estadoResultado = 0`, sin escrituras. `dbo.Sesion` no posee columna de cierre/estado. |
| `Sesion` | Cancelar sesión con motivo | `usp_cancelar_sesion_con_motivo` | `PATCH /api/v1/docente/sesiones/{id}/cancelar` | `DOCENTE` (titular del grupo) | Valida existencia de la sesión y titularidad del docente. Marca sesión como cancelada con motivo de cancelación. Anula registros existentes de `DetalleAsistencia` para esa sesión si los hay. |
| `Sesion` | Generar sesiones masivas del semestre | `usp_generar_sesiones_grupo` | `POST /api/v1/grupos` *(después de crear grupo)* | `DOCENTE` (titular del grupo) | Recibe el ID del grupo y `@idUsuarioEjecutor` obligatorio. Valida existencia de horarios, coherencia de fechas del periodo, RBAC docente y titularidad del grupo. Convierte fecha local + horario local desde `TIEMPO/ZONA_HORARIA_SQLSERVER` con `AT TIME ZONE` y persiste instantes UTC. El correlativo `MAX(numero)` se calcula dentro de la transacción protegida con `UPDLOCK, HOLDLOCK` para evitar duplicados frente a `usp_crear_sesion` concurrente. |
| `Sesion` | Actualizar datos operativos de sesión | `usp_actualizar_sesion` | `PUT /api/v1/sesiones/{id}` | `DOCENTE` (titular del grupo) | Firma pública sin `@idDocente`: recibe `@idSesion`, `@nombre`, `@fechaHoraInicio`, `@fechaHoraFin`, `@idCorrelacion`, `@idUsuarioEjecutor`. PUT completo: inicio y fin son obligatorios, `fechaHoraFin > fechaHoraInicio`, sesión inexistente retorna `SES_001`, y la titularidad se resuelve con `Usuario.id`. No existen atributos de aula, descripción, tipo ni cierre en `dbo.Sesion`. |

## Módulo: Matrículas e Inscripciones

| Tabla | Transacción / Acción de Negocio | Procedimiento Almacenado (BD) | Método del Controlador (Backend) | Rol / Permiso Requerido | Descripción del procedimiento |
|:---|:---|:---|:---|:---|:---|
| `EstudianteGrupo`, `Grupo` | Matricular estudiante en grupo | `usp_registrar_estudiante_en_grupo_interno` | `POST /api/v1/coordinador/grupos/{id}/estudiantes`, `POST /api/v1/grupos/{id}/estudiantes` | `COORDINADOR` (del programa), `DOCENTE` (titular del grupo) | Valida existencia del estudiante, existencia y habilitación del grupo, unicidad de la matrícula, cruce horario con otros grupos del estudiante, y cupo disponible. Inserta en `EstudianteGrupo` con estado `'A'`. Invoca: `usp_validar_estudiante_exista_por_id_interno`, `usp_validar_grupo_exista_por_id_interno`, `usp_validar_registro_estudiante_en_grupo_interno`, `usp_validar_cruce_horario_estudiante_interno`. |
| `EstudianteGrupo`, `Grupo` | Retirar estudiante de grupo (voluntario) | `usp_retirar_estudiante_de_grupo` | `DELETE /api/v1/coordinador/grupos/{id}/estudiantes/{estId}` | `COORDINADOR` (del programa), `DOCENTE` (titular del grupo) | Valida que exista la relación activa en `EstudianteGrupo`. Cambia estado a `'CVP'` (Cancelado por Voluntad Propia). Actualiza `Grupo.cantidadEstudiantesCancelaronVoluntadPropia`. |

## Módulo: Solicitudes de Revisión (Reclamos)

| Tabla | Transacción / Acción de Negocio | Procedimiento Almacenado (BD) | Método del Controlador (Backend) | Rol / Permiso Requerido | Descripción del procedimiento |
|:---|:---|:---|:---|:---|:---|
| `SolicitudRevisionAsistencia`, `Asistencia` | Radicar solicitud de revisión de asistencia | `usp_radicar_solicitud_revision_asistencia` | `POST /api/v1/estudiante/reclamos` | `ESTUDIANTE` (matriculado y con falta registrada) | Valida existencia del estudiante, de la sesión, y pertenencia al grupo. Valida plazo reglamentario (5 días hábiles). Crea `Asistencia` de respaldo si no existe. Inserta `SolicitudRevisionAsistencia` con estado `'PEND'`. Invoca: `usp_validar_estudiante_exista_por_id_interno`, `usp_validar_sesion_exista_por_id_interno`, `usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno`. |
| `SolicitudRevisionAsistencia`, `DetalleAsistencia` | Resolver solicitud de revisión (aprobar/rechazar) | `usp_resolver_solicitud_revision_asistencia` | `PATCH /api/v1/docente/reclamos/{id}` | `DOCENTE` (titular del grupo de la sesión del reclamo) | Valida existencia de la solicitud y que el docente sea titular del grupo (ámbito RBAC). Si `'APROBADA'`: cambia estado de solicitud + muta `DetalleAsistencia.asistio = 1`. Si `'RECHAZADA'`: solo actualiza estado y respuesta. Transacción atómica. |

## Módulo: Gestión de Identidad y Roles RBAC

| Tabla | Transacción / Acción de Negocio | Procedimiento Almacenado (BD) | Método del Controlador (Backend) | Rol / Permiso Requerido | Descripción del procedimiento |
|:---|:---|:---|:---|:---|:---|
| `Usuario`, `Decano`, `Facultad` | Designar decano y adscribirlo a facultad | `usp_crear_decano` | `POST /api/v1/admin/decanos` | `ADMINISTRADOR` | Busca o crea el `Usuario` vía `usp_sincronizar_usuario_interno`. Crea el registro `Decano` si no existe. Actualiza `Facultad.decano`. Transacción atómica. |
| `Usuario`, `Coordinador`, `Programa` | Designar coordinador y adscribirlo a programa | `usp_crear_coordinador` | `POST /api/v1/decano/coordinadores` | `DECANO` (de la facultad del programa) | Busca o crea el `Usuario` vía `usp_sincronizar_usuario_interno`. Crea el registro `Coordinador` si no existe. Valida que el programa exista. Actualiza `Programa.coordinador`. Transacción atómica. |
| `Usuario` | Sincronizar usuario institucional | `usp_sincronizar_usuario_interno` | — *(interno, invocado por otros SPs)* | — (interno) | Valida tipo de identificación. Valida unicidad de correo y número de documento. Inserta o actualiza `Usuario`. Invoca: `usp_validar_tipo_identificacion_exista_por_id_interno`, `usp_validar_unicidad_usuario_interno`. |
| `Usuario` | Activar/Desactivar usuario | — *(Operación simple: Backend)* | `PATCH /api/v1/admin/decanos/{id}/toggle`, `PATCH /api/v1/decano/coordinadores/{id}/estado`, `PATCH /api/v1/coordinador/docentes/{id}/estado` | `ADMINISTRADOR`, `DECANO`, `COORDINADOR` (según ámbito) | `UPDATE dbo.Usuario SET estado = IIF(estado = 1, 0, 1) WHERE id = ?`. Operación simple ejecutada directamente en el `*RepositorySqlServerAdapter` del Backend. Sin SP. |

## Módulo: Gestión Académica (Grupos, Asignaturas, Planes de Estudio)

| Tabla | Transacción / Acción de Negocio | Procedimiento Almacenado (BD) | Método del Controlador (Backend) | Rol / Permiso Requerido | Descripción del procedimiento |
|:---|:---|:---|:---|:---|:---|
| `Grupo` | Crear grupo académico | `usp_crear_grupo` | `POST /api/v1/grupos` | `DOCENTE`, `COORDINADOR` | El COORDINADOR crea y asigna cualquier docente; el DOCENTE solo crea grupos a su propio nombre (`SEC_002` si asigna a otro; F3). Valida existencia de asignatura. Resuelve periodo académico. Valida docente activo. Valida unicidad de código de grupo en asignatura/periodo. Inserta `Grupo` con contadores en 0. Invoca: `usp_validar_docente_exista_por_id_interno`. |
| `Grupo` | Actualizar datos operativos del grupo | `usp_actualizar_grupo` | `PUT /api/v1/grupos/{id}` | `DOCENTE` (titular), `COORDINADOR` | Valida existencia del grupo. Valida docente si se modifica y, si cambia el titular, que no tenga otro grupo a la misma hora (HOR_002, HTTP 409). Valida unicidad de código (excluyendo el propio grupo). Actualiza nombre, código y docente de forma granular (solo campos proporcionados). |
| `Asignatura` | Crear nueva asignatura en plan | `usp_crear_asignatura` | `POST /api/v1/coordinador/planes-estudio/{id}/asignaturas` | `COORDINADOR` (del programa) | Crea una asignatura en un `SemestrePlanEstudio` existente del plan. Exige perfil `COORDINADOR` (SEC_001), plan existente (PLA_002) de su programa (SEC_002), créditos > 0 (ASI_001), área y componente reales por código o nombre exactos (GEN_001) y semestre del plan (PLA_004; ya no se crea). |
| `Asignatura` | Actualizar datos de asignatura | `usp_actualizar_asignatura` | `PUT /api/v1/coordinador/planes-estudio/{planId}/asignaturas/{asigId}` | `COORDINADOR` (del programa) | Exige `@idUsuarioEjecutor` (GEN_002), perfil `COORDINADOR` (SEC_001) y que coordine el programa de la asignatura (SEC_002). Actualiza código, nombre, créditos (> 0, ASI_001; nulo conserva), área y componente reales (GEN_001) de una asignatura existente. |
| `Asignatura` | Alternar estado activo/inactivo | `usp_toggle_estado_asignatura` | `PATCH /api/v1/coordinador/asignaturas/{id}/estado` | `COORDINADOR` (del programa) | Exige `@idUsuarioEjecutor` (GEN_002), perfil `COORDINADOR` (SEC_001) y que coordine el programa de la asignatura (SEC_002). Valida existencia de la asignatura. Alterna el campo `estado` entre 1 y 0 atómicamente. |
| `Asignatura` | Eliminar asignatura del plan | `usp_eliminar_asignatura` | `DELETE /api/v1/coordinador/planes-estudio/{planId}/asignaturas/{asigId}` | `COORDINADOR` (del programa) | Valida que no existan grupos activos vinculados a la asignatura antes de eliminarla. |

## Módulo: Cierre Masivo de Periodo

| Tabla | Transacción / Acción de Negocio | Procedimiento Almacenado (BD) | Método del Controlador (Backend) | Rol / Permiso Requerido | Descripción del procedimiento |
|:---|:---|:---|:---|:---|:---|
| `EstudianteGrupo`, `Grupo`, `DetalleAsistencia`, `AuditoriaEvento` | Ejecutar cierre masivo de periodo académico | `usp_ejecutar_cierre_masivo_periodo` | `POST /api/v1/admin/cierre-masivo` | `ADMINISTRADOR` | Resuelve el periodo objetivo. Calcula inasistencias acumuladas por estudiante/grupo. Marca con `'CI'` a quienes superen el umbral (≥ 3 faltas ó ≥ 20%). Marca con `'F'` al resto de activos. Actualiza contadores en `Grupo`. Registra evento de auditoría. Transacción completa. |

## Módulo: Operaciones Simples sin SP (Backend Directo)

> [!TIP]
> Estas operaciones se ejecutan con `JdbcTemplate` parametrizado en los `*RepositorySqlServerAdapter` del Backend, **sin procedimiento almacenado**, porque son mutaciones de 1 tabla / 1-2 campos sin lógica multientidad.

| Tabla | Transacción / Acción de Negocio | Procedimiento Almacenado (BD) | Método del Controlador (Backend) | Rol / Permiso Requerido | Descripción del procedimiento |
|:---|:---|:---|:---|:---|:---|
| `Facultad` | Crear facultad | — *(Backend directo)* | `POST /api/v1/admin/facultades` | `ADMINISTRADOR` | `INSERT INTO dbo.Facultad ...` con validación de unicidad de nombre en el repositorio. |
| `Facultad` | Editar nombre/atributos de facultad | — *(Backend directo)* | `PUT /api/v1/admin/facultades/{id}` | `ADMINISTRADOR` | `UPDATE dbo.Facultad SET nombre = ? WHERE id = ?` |
| `Facultad` | Activar/Desactivar facultad | — *(Backend directo)* | `PATCH /api/v1/admin/facultades/{id}/estado` | `ADMINISTRADOR` | `UPDATE dbo.Facultad SET estado = IIF(estado = 1, 0, 1) WHERE id = ?` |
| `Institucion` | Crear institución | — *(Backend directo)* | `POST /api/v1/admin/instituciones` | `ADMINISTRADOR` | Inserción directa parametrizada. |
| `Institucion` | Editar institución | — *(Backend directo)* | `PUT /api/v1/admin/instituciones/{id}` | `ADMINISTRADOR` | Actualización directa parametrizada. |
| `Institucion` | Activar/Desactivar institución | — *(Backend directo)* | `PATCH /api/v1/admin/instituciones/{id}/toggle-estado` | `ADMINISTRADOR` | Toggle de estado. |
| `PlanEstudio` | Crear plan de estudio | — *(Backend directo)* | `POST /api/v1/coordinador/planes-estudio` | `COORDINADOR` | Inserción directa con validación de programa del coordinador. |
| `PlanEstudio` | Editar plan de estudio | — *(Backend directo)* | `PUT /api/v1/coordinador/planes-estudio/{id}` | `COORDINADOR` | Actualización de INP y estado. |
| `PlanEstudio` | Toggle estado plan | — *(Backend directo)* | `PATCH /api/v1/coordinador/planes-estudio/{id}/toggle-estado` | `COORDINADOR` | Toggle del campo `estado`. |
| `SemestrePlanEstudio` | Agregar semestre a plan | — *(Backend directo)* | `POST /api/v1/coordinador/planes-estudio/{id}/semestres` | `COORDINADOR` | Inserción directa vinculando con tabla `Semestre`. |
| `SemestrePlanEstudio` | Quitar semestre de plan | — *(Backend directo)* | `DELETE /api/v1/coordinador/planes-estudio/{id}/semestres/{num}` | `COORDINADOR` | Eliminación directa con validación de que no tenga asignaturas vinculadas. |
| `PeriodoAcademico` | Crear periodo académico | — *(Backend directo)* | `POST /api/v1/coordinador/periodos-academicos` | `COORDINADOR`, `ADMINISTRADOR` | Inserción directa con validación de no solapamiento de fechas. |
| `PeriodoAcademico` | Editar periodo académico | — *(Backend directo)* | `PUT /api/v1/coordinador/periodos-academicos/{id}` | `COORDINADOR`, `ADMINISTRADOR` | Actualización de nombre, fechas. |
| `Area` | Crear/Editar/Toggle área de conocimiento | — *(Backend directo)* | `POST /PUT /PATCH /api/v1/admin/areas{/{id}{/estado}}` | `ADMINISTRADOR` | Operaciones CRUD simples sobre tabla paramétrica. |
| `Horario` | Configurar franja horaria del grupo | — *(Backend directo)* | `POST /api/v1/grupos` *(dentro de la lógica de creación)* | `DOCENTE`, `COORDINADOR` | Inserción directa en `dbo.Horario` vinculando grupo y día. |

## Módulo: Consultas y Lecturas (Sin SP — Vistas `uv_*`)

> [!NOTE]
> Todas las lecturas se ejecutan directamente sobre las vistas relacionales `uv_*` (**67** en `schema/views` al 2026-11-05) desde los adaptadores secundarios de Spring Boot con `NamedParameterJdbcTemplate` y paginación nativa `OFFSET / FETCH`. No requieren procedimientos almacenados.

| Vista | Consulta / Acción | Método del Controlador (Backend) | Rol / Permiso Requerido |
|:---|:---|:---|:---|
| `uv_grupo`, `uv_estadistica_grupo` | Listar grupos (con filtro de ámbito por rol) | `GET /api/v1/grupos` | `DOCENTE`, `COORDINADOR`, `DECANO`, `ADMIN` |
| `uv_sesion` | Listar sesiones de un grupo | `GET /api/v1/sesiones/grupo/{grupoId}` | `DOCENTE` (titular) |
| `uv_estudiante_grupo` | Listar estudiantes de un grupo | `GET /api/v1/grupos/{id}/estudiantes` | `DOCENTE`, `COORDINADOR` |
| `uv_asistencia`, `uv_detalle_asistencia` | Consultar asistencias por grupo/sesión | `GET /api/v1/grupos/{id}/asistencias` | `DOCENTE`, `COORDINADOR` |
| `uv_estudiante`, `uv_estudiante_identidad` | Listar/buscar estudiantes del programa | `GET /api/v1/estudiante/materias`, `GET /api/v1/coordinador/estudiantes` | `ESTUDIANTE`, `COORDINADOR` |
| `uv_docente`, `uv_docente_identidad` | Listar/buscar docentes | `GET /api/v1/coordinador/docentes`, `GET /api/v1/docentes` | `COORDINADOR`, `DECANO`, `ADMIN` |
| `uv_coordinador`, `uv_coordinador_identidad` | Listar coordinadores de la facultad | `GET /api/v1/decano/coordinadores` | `DECANO` |
| `uv_decano`, `uv_decano_identidad` | Listar decanos institucionales | `GET /api/v1/admin/decanos` | `ADMINISTRADOR` |
| `uv_facultad` | Listar facultades | `GET /api/v1/admin/facultades`, `GET /api/v1/decano/facultad` | `ADMINISTRADOR`, `DECANO` |
| `uv_programa` | Listar programas | `GET /api/v1/decano/facultad` *(programas de la facultad)* | `DECANO`, `COORDINADOR` |
| `uv_plan_estudio` | Listar planes de estudio | `GET /api/v1/coordinador/planes-estudio` | `COORDINADOR` |
| `uv_asignatura` | Listar asignaturas | `GET /api/v1/coordinador/asignaturas` | `COORDINADOR` |
| `uv_periodo_academico` | Listar periodos académicos | `GET /api/v1/coordinador/periodos-academicos` | `COORDINADOR`, `ADMIN` |
| `uv_horario_docente` | Consultar horario del docente | `GET /api/v1/docente/horarios` | `DOCENTE` |
| `uv_horario_estudiante` | Consultar horario del estudiante | `GET /api/v1/estudiante/horarios` | `ESTUDIANTE` |
| `uv_solicitud_revision_asistencia` | Listar reclamos (histórico; hoy el estudiante usa `usp_consultar_solicitudes_revision_estudiante` y el docente `usp_consultar_solicitudes_revision_docente`) | `GET /api/v1/estudiante/reclamos`, `GET /api/v1/docente/reclamos` | `ESTUDIANTE`, `DOCENTE` |
| `uv_tipo_identificacion` | Listar tipos de identificación | `GET /api/v1/tipos-identificacion` | `TODOS` |
| `uv_categoria_justificacion` | Listar los motivos para justificar una inasistencia (HU005/HU016) | `GET /api/v1/categorias-justificacion` | `TODOS` (autenticado) |
| `usp_consultar_perfil_usuario` (HU006; antes previsto como `uv_usuario_perfil`) | Consultar perfil del usuario autenticado con sus vínculos | `GET /api/v1/usuarios/perfil` | `TODOS` (autenticado) |

---

## Catálogo de Procedimientos Internos Reutilizables (`_interno`)

| Procedimiento Interno | Tipo | Propósito | Invocado por |
|:---|:---|:---|:---|
| `usp_validar_id_correlacion_esta_presente_interno` | Validación | Exige UUID de correlación válido para trazabilidad | Todos los SPs orquestadores |
| `usp_validar_id_interno` | Validación | Valida que un UUID no sea nulo ni el GUID vacío | Reutilizable por todos |
| `usp_validar_sesion_exista_por_id_interno` | Validación | Comprueba existencia de sesión en `uv_sesion` | `usp_registrar_asistencia*`, `usp_cerrar_sesion`, `usp_radicar_solicitud*` |
| `usp_validar_estudiante_exista_por_id_interno` | Validación | Comprueba existencia y estado activo del estudiante | `usp_registrar_estudiante_en_grupo_interno`, `usp_radicar_solicitud*` |
| `usp_validar_docente_exista_por_id_interno` | Validación | Comprueba existencia y estado activo del docente | `usp_crear_grupo`, `usp_actualizar_grupo`, `usp_registrar_docente*` |
| `usp_validar_grupo_exista_por_id_interno` | Validación | Comprueba existencia y habilitación del grupo | `usp_registrar_estudiante*`, `usp_generar_sesiones*` |
| `usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno` | Validación | Valida que el estudiante esté inscrito en el grupo de la sesión | `usp_registrar_asistencias_sesion`, `usp_radicar_solicitud*` |
| `usp_validar_registro_estudiante_en_grupo_interno` | Unicidad | Valida que el estudiante no esté ya matriculado en el grupo | `usp_registrar_estudiante_en_grupo_interno` |
| `usp_validar_cruce_horario_estudiante_interno` | Concurrencia | Detecta solapamientos entre franjas horarias del estudiante | `usp_registrar_estudiante_en_grupo_interno` |
| `usp_validar_cruce_horario_docente_interno` | Concurrencia | Detecta solapamientos entre franjas horarias del docente | `usp_actualizar_grupo` (al cambiar el titular, desde 2026-10-29) |
| `usp_validar_horarios_grupo_interno` | Validación | Verifica que el grupo tenga franjas horarias configuradas | `usp_generar_sesiones_grupo` |
| `usp_validar_fechas_periodo_academico_interno` | Validación | Valida coherencia y vigencia de fechas del periodo | `usp_generar_sesiones_grupo` |
| `usp_validar_unicidad_usuario_interno` | Unicidad | Valida unicidad de correo y documento en `uv_usuario` | `usp_sincronizar_usuario_interno` |
| `usp_validar_tipo_identificacion_exista_por_id_interno` | Validación | Valida existencia del tipo de identificación | `usp_sincronizar_usuario_interno` |
| `usp_validar_perfil_existe_por_codigo_interno` | Validación | Valida existencia de un perfil institucional por código | `usp_sincronizar_*_interno` |
| `usp_validar_usuario_existe_por_id_interno` | Validación | Valida existencia del usuario por ID | Reutilizable |
| `usp_sincronizar_usuario_interno` | Persistencia | Crea o actualiza registro en `Usuario` | `usp_crear_decano`, `usp_crear_coordinador` |
| `usp_sincronizar_asistencia_estudiante_interno` | Persistencia | Inserta/actualiza `Asistencia` + `DetalleAsistencia` resolviendo una `RazonCausa` existente (catálogo cerrado, `RC_001` si no existe; alias legacy `A→AN`, `F→SJC` solo internos) | `usp_registrar_asistencia*`, `usp_registrar_asistencias_sesion` |
| `usp_sincronizar_docente_interno` | Persistencia | Crea registro `Docente` desde `Usuario` existente | `DocenteRepositorySqlServerAdapter` |
| `usp_sincronizar_estudiante_interno` | Persistencia | Crea registro `Estudiante` desde `Usuario` existente | Orquestadores de registro estudiantil |
| `usp_obtener_mensaje_catalogo` | Mensajería | Traduce códigos de catálogo a mensajes para usuario/técnico | Todos los SPs |

---

## Addendum 2026-10-25 — Plan de estudio, períodos y consultas de coordinador y decano

| Endpoint | SP | HU |
|:---|:---|:---|
| `PATCH /api/v1/coordinador/planes-estudio/{id}/toggle-estado` | `usp_cambiar_estado_plan_estudio` | HU081 |
| `POST /api/v1/coordinador/planes-estudio/{id}/semestres` | `usp_agregar_semestre_plan_estudio` | HU082 |
| `DELETE /api/v1/coordinador/planes-estudio/{id}/semestres/{numero}` | `usp_quitar_semestre_plan_estudio` | HU083 |
| `POST /api/v1/admin/periodos-academicos` | `usp_crear_periodo_academico` | HU096 |
| `PUT /api/v1/admin/periodos-academicos/{id}` | `usp_actualizar_periodo_academico` | HU097 |
| `DELETE /api/v1/admin/periodos-academicos/{id}` | `usp_eliminar_periodo_academico` | HU098 |
| `GET /api/v1/coordinador/grupos` | `usp_consultar_grupos_paginado` | HU064 |
| `GET /api/v1/coordinador/grupos/{id}/sesiones` | `usp_consultar_sesiones_grupo_paginado` | HU060 |
| `GET /api/v1/coordinador/sesiones/{id}/asistencias` | `usp_consultar_asistencias_sesion_paginado` | HU061 |
| `GET /api/v1/decano/estudiantes` | `usp_consultar_estudiantes_facultad_paginado` | HU104/HU105 |
| `GET /api/v1/decano/estudiantes/{id}` | `usp_consultar_estudiante_facultad_detalle` | HU105 |
| `GET /api/v1/decano/estructura` | `usp_consultar_estructura_facultad` | HU109/HU119 (y planes de HU108) |
| `GET /api/v1/decano/sesiones` | `usp_consultar_sesiones_facultad_paginado` | HU145 |
| `GET /api/v1/decano/programas-creditos` | `usp_consultar_programas_creditos_facultad_paginado` | HU112 |
| `GET /api/v1/decano/docentes` | `usp_consultar_docentes_facultad_paginado` | HU128 |
| `GET /api/v1/decano/asignaturas` y `GET /api/v1/admin/asignaturas` | `usp_buscar_asignaturas_paginado` | HU143 |
| `GET /api/v1/admin/estudiantes` | `usp_buscar_estudiantes_institucion_paginado` | HU157 |
| `GET /api/v1/admin/estudiantes/{id}/historial` y `GET /api/v1/decano/estudiantes/{id}/historial` | `usp_consultar_historial_estudiante` | HU157 |
| `GET /api/v1/coordinador/consolidado-asistencia` (COORDINADOR, ADMINISTRADOR) y `GET /api/v1/decano/consolidado-asistencia` (DECANO, ADMINISTRADOR) | `usp_consultar_consolidado_asistencia_grupos_paginado` | HU061 |
| `GET /api/v1/admin/auditoria` | `usp_consultar_auditoria_eventos_paginado` | HU172 |
| `GET /api/v1/coordinador/componentes-formacion` | `usp_consultar_componentes_formacion` | HU147 |
| ~~`POST /api/v1/admin/tipos-identificacion`, `PUT /api/v1/admin/tipos-identificacion/{id}`~~ | ~~`usp_guardar_tipo_identificacion`~~ eliminado el 2026-11-04 (catálogo de solo consulta; la consulta sigue en `GET /api/v1/tipos-identificacion`) | HU153 |
| `POST`/`PUT /api/v1/coordinador/planes-estudio/{id}/asignaturas…` (sin cambio de ruta) | `usp_crear_asignatura`, `usp_actualizar_asignatura` (P5: área y componente deben existir, `GEN_001`; semestre del plan, `PLA_004`; créditos > 0, `ASI_001`; plan del programa del coordinador, `SEC_002`) | P5 |
| `GET /api/v1/admin/estados` | Lectura directa de `uv_estado` y `uv_estado_estudiante_grupo` (catálogos de solo consulta, sin SP) | HU155/HU167 |
| `GET /api/v1/categorias-justificacion` (autenticado) | Lectura directa de `uv_categoria_justificacion` (catálogo de solo consulta, sin SP) | HU005/HU016 |
| `GET /api/v1/docente/asignaturas` (aditivo) | `uv_docente` + `uv_programa` (tipo de programa del grupo) | HU058 |
| `GET /api/v1/estudiante/reclamos` | `usp_consultar_solicitudes_revision_estudiante` | HU010/HU011 (consulta) |
| `POST /api/v1/docente/grupos/{grupoId}/estudiantes/{estudianteId}/retiro` | `usp_retirar_estudiante_grupo` + `usp_consultar_destinatarios_retiro_estudiante_grupo` | HU051 |
| `GET /api/v1/estudiante/oferta-academica` | `usp_consultar_oferta_grupos_estudiante` | HU008 |
| `POST /api/v1/estudiante/solicitudes-matricula` | `usp_registrar_solicitud_ingreso_grupo` | HU053 |
| `GET /api/v1/estudiante/solicitudes-matricula` | `usp_consultar_solicitudes_ingreso_estudiante` | HU053/HU055 |
| `POST /api/v1/estudiante/solicitudes-matricula/{id}/retiro` | `usp_retirar_solicitud_ingreso_grupo` | HU055 |
| `GET /api/v1/docente/grupos/{grupoId}/solicitudes-ingreso` | `usp_consultar_solicitudes_ingreso_grupo_docente` | HU053-HU055 |
| `PATCH /api/v1/docente/solicitudes-ingreso/{id}` | `usp_resolver_solicitud_ingreso_grupo` (+ destinatarios) | HU053/HU054/HU055 |
| `GET /api/v1/coordinador/docentes/{idDocente}/ficha` | `usp_consultar_docentes_programa` (cabecera, `@idDocente`) + `usp_consultar_historial_grupos_docente_programa` | HU094 |
| `GET /api/v1/coordinador/docentes/resumen` | `usp_consultar_resumen_docentes_programa` | HU095 |

Firma de entrada/salida y códigos: `DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md` (addendums 2026-10-25, HU010/HU011, HU051, HU053-HU055, HU008, HU094/HU095 y HU006) y el `CONTRACT.md` de cada work item del backend.

---

## Addendum REC5 (2026-10-29): SP públicos que faltaban en esta especificación

Auditoría BD 2026-10-28: 53 de 102 SP públicos no figuraban aquí (10 de ellos, los paginados y por id legacy, se eliminaron el 2026-10-29 por no tener uso; hoy hay 89 SP públicos). Cada endpoint se trazó sobre el backend `develop` (`*JpaRepository` → puerto → caso de uso → controller). La columna "Propósito" sale del comentario de cabecera del SP. Las firmas completas y los códigos están en el script del SP y en su work item.

| Módulo | SP | Endpoint / consumidor | Rol | Parámetros | Propósito |
|---|---|---|---|---|---|
| `ArchivoSoporte` | `usp_consultar_archivo_soporte_autorizado` | `GET /api/v1/archivos/{fileId}` | Propietario o docente titular | `@idArchivoSoporte, @idCorrelacion, @idUsuarioEjecutor` | usp_consultar_archivo_soporte_autorizado  (LB-004D, R1) Clasificacion (DB-GP-001C): NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md Resultset: READ_QUERY_RESULTSET (0..1 fila de datos). NO es un MUTATION_COMMAND_RESULTSET: … |
| `ArchivoSoporte` | `usp_registrar_archivo_soporte` | `POST /api/v1/archivos/subir` | ESTUDIANTE | `@idArchivoSoporte, @nombreOriginal, @tipoContenido, @tamanioBytes, @checksumSha256, @idCorrelacion, @idUsuarioEjecutor` | usp_registrar_archivo_soporte  (LB-004D, W1) Registra en estado DRAFT la metadata de un soporte ya almacenado por el backend. El propietario es SIEMPRE @idUsuarioEjecutor (no existe parametro de propietario). El fileId lo genera el backend; la DB no lo genera … |
| `Coordinador` | `usp_actualizar_coordinador` | `PUT /api/v1/decano/coordinadores/{id}` | DECANO | `@idCoordinador, @primerNombre, @segundoNombre, @primerApellido, @segundoApellido, @correo, @idFacultad, @idCorrelacion, @idUsuarioEjecutor, @idTipoIdIdentificacion = NULL, @numeroIdentificacion = NULL, @motivo = NULL` | HU121: edita nombres, apellidos y correo de un coordinador de la facultad del decano ejecutor; HU159 (2026-11-05): también corrige el documento (opcional; si cambia, motivo y auditoría). Devuelve idUsuario para que el backend sincronice la cuenta y el username |
| `Estudiante` | `usp_corregir_identidad_usuario` (`@tipoUsuario = ESTUDIANTE`) | `PUT /api/v1/coordinador/estudiantes/{idEstudiante}/identidad` | COORDINADOR | `@tipoUsuario, @idRegistro, @idTipoIdIdentificacion, @numeroIdentificacion, @primerNombre, @segundoNombre, @primerApellido, @segundoApellido, @motivo, @idCorrelacion, @idUsuarioEjecutor` | HU159: corrige documento, nombres y apellidos de un estudiante del programa del coordinador (`EstudiantePrograma`), con motivo obligatorio y auditoría. No toca correo, contraseña ni estado |
| `Decano` | `usp_corregir_identidad_usuario` (`@tipoUsuario = DECANO`) | `PUT /api/v1/admin/decanos/{id}/identidad` | ADMINISTRADOR | Los mismos | HU159: el administrador corrige documento, nombres y apellidos del decano, con motivo obligatorio y auditoría |
| `Docente` | `usp_actualizar_docente_programa` (aditivo) | `PUT /api/v1/coordinador/docentes/{idDocente}` | COORDINADOR | `+ @idTipoIdIdentificacion = NULL, @numeroIdentificacion = NULL, @motivo = NULL` | HU092 + HU159: el coordinador corrige el documento del docente vinculado (opcional; si cambia, motivo y auditoría) |
| `Configuración` | Lectura de `CatalogoParametro` (`IDENTIDAD.PERMITIR_CORREGIR_DOCUMENTO`) | `GET /api/v1/configuracion/identidad` | Autenticado | — | HU159: el frontend oculta los campos de documento si la corrección está apagada |
| `Coordinador` | `usp_cambiar_estado_coordinador` | `PATCH /api/v1/decano/coordinadores/{id}/estado` | DECANO | `@idCoordinador, @estaActivo, @idFacultad, @idCorrelacion, @idUsuarioEjecutor` | HU122: activa o desactiva el rol de coordinador de la facultad del decano ejecutor. Regla D3: no se puede desactivar a quien coordina un programa activo (COO_001). Regla D1: Usuario.estado pasa a 0 solo si la persona no conserva otro rol activo; al reactivar v… |
| `DocentePrograma` | `usp_actualizar_docente_programa` | `PUT /api/v1/coordinador/docentes/{idDocente}` | COORDINADOR | `@idDocente, @idPrograma, @idTipoVinculacion, @primerNombre, @segundoNombre, @primerApellido, @segundoApellido, @idCorrelacion, @idUsuarioEjecutor` | HU092: edita (a) el tipo de vinculacion del vinculo docente-programa y (b) los nombres/apellidos de la persona. Solo se actualizan los parametros no nulos (''/vacio en un segundo nombre o apellido lo limpia). Correo y documento NO se editan aqui (el correo exi… |
| `DocentePrograma` | `usp_cambiar_estado_docente_programa` | `PATCH /api/v1/coordinador/docentes/{idDocente}/estado` | COORDINADOR | `@idDocente, @idPrograma, @estaActivo, @idCorrelacion, @idUsuarioEjecutor` | HU093 (D12): activa o inactiva el VINCULO del docente con el programa del coordinador (DocentePrograma.estado). No toca Usuario.estado, ni el rol Docente, ni los grupos ya asignados, ni la cuenta de identidad. Idempotente. RBAC COORDINADOR + titularidad PROGRA… |
| `DocentePrograma` | `usp_consultar_candidatos_docente_programa` | `GET /api/v1/coordinador/docentes/candidatos` | COORDINADOR | `@idUsuarioEjecutor, @idCorrelacion, @idPrograma, @busqueda` | usp_consultar_candidatos_docente_programa (HU091, picker de docentes existentes) Resultset: READ_QUERY_RESULTSET con datos MINIMOS (D4, sin correo): idDocente, idUsuario, codigoTipoIdentificacion, numeroIdentificacion, nombreCompleto. Candidato = docente activ… |
| `DocentePrograma` | `usp_vincular_docente_programa` | `POST /api/v1/coordinador/docentes` | COORDINADOR | `@idDocente, @idUsuario, @idTipoIdentificacion, @numeroIdentificacion, @primerNombre, @segundoNombre, @primerApellido, @segundoApellido, @correo, @password, @idTipoVinculacion, @idPrograma, @idCorrelacion, @idUsuarioEjecutor` | HU091: vincula un docente al programa del coordinador. Tres modos excluyentes: (a) @idDocente        docente existente (p. ej. de otro programa de la misma institucion) (b) @idUsuario        usuario existente que aun no es docente (c) datos de persona  alta nu… |
| `Facultad` | `usp_actualizar_facultad` | `PUT /api/v1/admin/facultades/{id}` | ADMINISTRADOR | `@id, @nombre, @idDecano, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_actualizar_facultad] Historias de Usuario: HU110 (modificar denominacion) y HU117 (reasignar decano) Ambito: Administrador Institucional (Nivel 1 de custodia jerarquica) Semantica: un parametro NULL no se modifica. Al menos uno es obl… |
| `Facultad` | `usp_cambiar_estado_facultad` | `PATCH /api/v1/admin/facultades/{id}/estado` | ADMINISTRADOR | `@id, @estaActiva, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_cambiar_estado_facultad] Historia de Usuario: HU111 (alternar estado operativo de la facultad) Ambito: Administrador Institucional. Recibe el estado deseado (idempotente), sin cascada. Salida Canonica: (idCorrelacion, mensajeUsuarioRe… |
| `Facultad` | `usp_crear_facultad` | `POST /api/v1/admin/facultades` | ADMINISTRADOR | `@id, @nombre, @idInstitucion, @idDecano, @idCorrelacion, @idUsuarioEjecutor, @idFacultad, @nombreFacultad` | Procedimiento: [dbo].[usp_crear_facultad] Historia de Usuario: HU116 (Alta institucional de nueva facultad) Ámbito: Administrador Institucional (Nivel 1 de custodia jerárquica) Estándar: Conforme a procedimientos-externos-condiciones, consulta-a-bd y AGENTS.md… |
| `Identidad` | `usp_revocar_identidad_externa` | `Flujo de identidad externa (POST /api/v1/identidad/cuentas/acceso/reconciliaciones)` | Sistema (Security Baseline) | `@emisor, @sujeto, @idCorrelacion` | SEC-BASELINE-017: revoca el vinculo (emisor, sujeto) -> Usuario.id. Idempotente: revocar un vinculo ya revocado responde exito sin cambios. La fila se conserva (estado = 0) para que la identidad revocada no pueda reutilizarse ni reasignarse a otra cuenta sin u… |
| `Identidad` | `usp_vincular_identidad_externa` | `Flujo de identidad externa (POST /api/v1/identidad/cuentas/acceso/reconciliaciones)` | Sistema (Security Baseline) | `@emisor, @sujeto, @idUsuario, @correoVinculacion, @idCorrelacion` | SEC-BASELINE-017: registra el vinculo estable (emisor, sujeto) -> Usuario.id. Reglas (todas atomicas bajo UPDLOCK/HOLDLOCK; los indices unicos son la ultima barrera ante carreras): * El usuario debe existir y estar activo. * Repetir el mismo vinculo vigente es… |
| `Indicadores` | `usp_consultar_aforo_grupos_facultad` | `GET /api/v1/decano/aforo-grupos` | DECANO | `@idUsuarioEjecutor, @idCorrelacion, @numeroPagina, @tamanoPagina, @idPeriodoAcademico, @idPrograma, @soloHabilitados` | usp_consultar_aforo_grupos_facultad (HU144). READ_QUERY_RESULTSET paginado. Solo lectura. Aforo = matriculados activos / cupo maximo (D4); NULL si el cupo es 0. No se recorta por encima de 100 %. @soloHabilitados = 1 (defecto) lista solo grupos habilitados en … |
| `Indicadores` | `usp_consultar_alerta_temprana_programa` | `GET /api/v1/coordinador/alertas-tempranas` | COORDINADOR | `@idUsuarioEjecutor, @idCorrelacion, @numeroPagina, @tamanoPagina, @idPeriodoAcademico, @semaforo, @filtroTexto` | usp_consultar_alerta_temprana_programa (HU066, HU070). READ_QUERY_RESULTSET paginado. Solo lectura. Una fila por persona: % = el mayor de sus matriculas activas, faltas = suma, clasificacion = la peor (D6). |
| `Indicadores` | `usp_consultar_bitacora_estudiante_programa` | `GET /api/v1/coordinador/estudiantes/{idEstudiante}/bitacora` | COORDINADOR | `@idUsuarioEjecutor, @idCorrelacion, @idEstudiante, @numeroPagina, @tamanoPagina, @idPeriodoAcademico` | usp_consultar_bitacora_estudiante_programa (HU067). READ_QUERY_RESULTSET paginado. Solo lectura. Sesiones vencidas de los grupos del programa en los que el estudiante esta (o estuvo) matriculado, la mas reciente primero. asistio = NULL cuando la sesion vencida… |
| `Indicadores` | `usp_consultar_comparativa_facultades` | `GET /api/v1/admin/comparativa-facultades` | ADMINISTRADOR | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico` | usp_consultar_comparativa_facultades (HU139). READ_QUERY_RESULTSET sin paginar. Solo lectura. Una fila por facultad de la institucion (activas e inactivas, D4). Mismas definiciones que usp_consultar_kpis_institucion. Orden: ausentismo descendente (NULL al fina… |
| `Indicadores` | `usp_consultar_comparativa_programas_facultad` | `GET /api/v1/decano/comparativa-programas` | DECANO | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico` | usp_consultar_comparativa_programas_facultad (HU103). READ_QUERY_RESULTSET sin paginar (D6). Solo lectura. Una fila por programa de la facultad (activos e inactivos, D5). Mismas definiciones que usp_consultar_kpis_decano. Orden: ausentismo descendente (NULL al… |
| `Indicadores` | `usp_consultar_ficha_estudiante_programa` | `GET /api/v1/coordinador/estudiantes/{idEstudiante}/ficha` | COORDINADOR | `@idUsuarioEjecutor, @idCorrelacion, @idEstudiante` | usp_consultar_ficha_estudiante_programa (HU069). READ_QUERY_RESULTSET (1 fila). Solo campos que existen en la DB (sin telefono, D5). |
| `Indicadores` | `usp_consultar_kpis_coordinador` | `GET /api/v1/coordinador/indicadores` | COORDINADOR | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico` | usp_consultar_kpis_coordinador (HU065, HU070). READ_QUERY_RESULTSET (1 fila). Solo lectura: sin XACT_ABORT. Ambito: el programa que coordina el ejecutor. Todas las cifras salen de las vistas de resumen (ver CONTRACT §1). |
| `Indicadores` | `usp_consultar_kpis_decano` | `GET /api/v1/decano/indicadores` | DECANO | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico` | usp_consultar_kpis_decano (HU102, HU106, HU144). READ_QUERY_RESULTSET de una fila. Solo lectura. Estudiante = persona con la peor clasificacion de sus matriculas activas de la facultad (D3). Retencion = (regular + riesgo) / total (D2). Ausentismo = faltas / se… |
| `Indicadores` | `usp_consultar_kpis_institucion` | `GET /api/v1/admin/indicadores` | ADMINISTRADOR | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico` | usp_consultar_kpis_institucion (HU133, HU135, HU136, HU138). READ_QUERY_RESULTSET de una fila. Solo lectura. Mismas definiciones que las olas 1 y 2: persona = peor clasificacion de sus matriculas activas; ausentismo ponderado por matricula activa (sesionesEjec… |
| `Indicadores` | `usp_consultar_resumen_asistencia_estudiante_programa` | `GET /api/v1/coordinador/estudiantes/{idEstudiante}/ficha (resumen de asistencia de la ficha)` | COORDINADOR | `@idUsuarioEjecutor, @idCorrelacion, @idEstudiante, @idPeriodoAcademico` | usp_consultar_resumen_asistencia_estudiante_programa (HU069). READ_QUERY_RESULTSET (una fila por matricula). Solo lectura. |
| `Indicadores` | `usp_consultar_tendencia_ausentismo` | `GET /api/v1/admin/tendencia-ausentismo` | ADMINISTRADOR | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico, @granularidad` | usp_consultar_tendencia_ausentismo (HU134). READ_QUERY_RESULTSET sin paginar. Solo lectura. Serie temporal del ausentismo del periodo por SEMANA (calendario, inicia el lunes) o MES, segun la hora local institucional (parametro TIEMPO/ZONA_HORARIA_SQLSERVER) de… |
| `PlanEstudio` | `usp_registrar_o_actualizar_plan_estudio` | `POST /api/v1/coordinador/planes-estudio y PUT /api/v1/coordinador/planes-estudio/{id}` | COORDINADOR | `@idPlanEstudio, @idPrograma, @inp, @idCorrelacion, @idUsuarioEjecutor` | CC-003G-01: proveedor publico exigido por el backend (PlanEstudioJpaRepository.SQL_REGISTRAR_O_ACTUALIZAR_PLAN). Contrato de entrada: el backend envia (@idPlanEstudio, @idPrograma, @inp, @idCorrelacion) y, desde este work item, @idUsuarioEjecutor (el usuario C… |
| `Programa` | `usp_actualizar_programa_academico` | `PUT /api/v1/decano/programas/{id}` | DECANO | `@idPrograma, @nombre, @idTipoPrograma, @idCoordinador, @idModalidad, @idJornada, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_actualizar_programa_academico] Historia de Usuario: HU077 Ambito: Decano de Facultad. Edicion de nombre, tipo, modalidad, jornada y coordinador de un programa de la facultad del decano. Salida Canonica: (idCorrelacion, mensajeUsuarioR… |
| `Programa` | `usp_cambiar_estado_programa_academico` | `PATCH /api/v1/decano/programas/{id}/estado` | DECANO | `@idPrograma, @estaActivo, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_cambiar_estado_programa_academico] Historia de Usuario: HU078 Ambito: Decano de Facultad. Activa o desactiva un programa de la facultad del decano. Recibe el estado destino (idempotente). Salida Canonica: (idCorrelacion, mensajeUsuari… |
| `Programa` | `usp_consultar_programas_academicos` | `GET /api/v1/decano/programas` | DECANO | `@idUsuarioEjecutor, @idCorrelacion, @numeroPagina, @tamanoPagina, @nombre, @estaActivo, @idTipoPrograma` | usp_consultar_programas_academicos (HU108, solo listado de programas) Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas de los comandos. Las fallas de paginacion se propagan con THROW (DBCODE=PAG_001). Ambito: las… |
| `Programa` | `usp_crear_programa_academico` | `POST /api/v1/decano/programas` | DECANO | `@idPrograma, @nombre, @idTipoPrograma, @idCoordinador, @idModalidad, @idJornada, @idFacultad, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_crear_programa_academico] Historia de Usuario: HU076 Ambito: Decano de Facultad. Alta de un programa academico en la facultad del decano (coordinador obligatorio, 1 a 1). Reemplaza el UPSERT anterior: solo inserta. Salida Canonica: (i… |
| `Revision` | `usp_consultar_detalle_solicitud_revision_docente` | `GET /api/v1/docente/reclamos/{id}` | DOCENTE | `@idSolicitud, @idUsuarioEjecutor, @idCorrelacion` | usp_consultar_detalle_solicitud_revision_docente  (HU035/HU036) Clasificacion (DB-GP-001C): NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md Resultset: READ_QUERY_RESULTSET (0..1 fila con el detalle y la causal de una solici… |
| `Revision` | `usp_radicar_solicitud_revision_asistencia_v2` | `POST /api/v1/asistencias/revisiones` | ESTUDIANTE | `@idEstudiante, @idSesion, @categoria, @justificacion, @idArchivoSoporte, @idCorrelacion, @idUsuarioEjecutor` | usp_radicar_solicitud_revision_asistencia_v2  (LB-004D, W2) Radica la solicitud de revision y, si se indica @idArchivoSoporte, vincula el soporte (DRAFT -> ATTACHED) en la MISMA transaccion. La v1 permanece intacta. * Sin @soporteNombre/@soporteUrl: la v2 no c… |
| `Seguridad` | `usp_establecer_contexto_usuario_ejecutor` | `Sin endpoint: fija SESSION_CONTEXT para las vistas uv_auth_*` | Helper tecnico | `@p_idUsuario` | Fija `SESSION_CONTEXT(idUsuarioEjecutor)` de la conexión para que las vistas `uv_auth_*` filtren por el usuario (fail-closed sin contexto). |
| `Sesion` | `usp_actualizar_sesion_v2` | `PATCH /api/v2/sesiones/{sesionId}` | DOCENTE | `@idSesion, @nombre, @fechaHoraInicio, @fechaHoraFin, @idCorrelacion, @idUsuarioEjecutor` | UTC-D06-POST-FREEZE: actualizacion v2 (PATCH de reemplazo completo de horas). El backend solo invoca este SP con instantes normalizados a UTC desde RFC3339 con offset explicito (UTC-D02): horas y marca UTC_V2 se escriben en el MISMO UPDATE. Mismos parametros n… |
| `Sesion` | `usp_clasificar_procedencia_sesion` | `Sin endpoint: mantenimiento UTC-D06, solo rol_asistencias_clasificador_temporal` | Rol temporal | `@idSesion, @ambiente, @idManifiesto, @hashEvidencia, @fechaHoraInicioVerificada, @fechaHoraFinVerificada, @fechaHoraInicioUtc, @fechaHoraFinUtc, @idUsuarioAprobador, @idCorrelacion, @idUsuarioEjecutor` | UTC-D06-POST-FREEZE: UNICO camino administrativo para marcar una sesion historica como UTC_OWNER. No es un endpoint del backend: lo ejecuta el owner funcional/DBA con un manifiesto aprobado, sesion por sesion y ambiente por ambiente. Fail-closed: * el ejecutor… |
| `Sesion` | `usp_crear_sesion_v2` | `POST /api/v2/sesiones` | DOCENTE | `@idGrupo, @nombre, @fechaHoraInicio, @fechaHoraFin, @idCorrelacion, @idUsuarioEjecutor` | UTC-D06-POST-FREEZE: creacion v2. El backend solo invoca este SP despues de normalizar un RFC3339 con offset explicito (perfil UTC-D02) al instante UTC, por lo que las horas recibidas son instantes UTC confirmados: se marcan UTC_V2 en el MISMO INSERT (usp_crea… |
| `SolicitudIngreso` | `usp_consultar_destinatarios_solicitud_ingreso_grupo` | `Sin endpoint propio: lo usa el backend para notificar tras registrar/resolver una solicitud (HU053-HU055)` | Interno backend | `@idSolicitud, @idCorrelacion, @idUsuarioEjecutor` | usp_consultar_destinatarios_solicitud_ingreso_grupo  (HU053/HU054/HU055) Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo). Destinatarios de los avisos de una solicitud de ingreso: el ESTUDIANTE solicitante y el DOCENTE … |

### SP públicos legacy sin consumidor en el backend

El backend de `develop` no lo invoca y no tiene `GRANT EXECUTE` al runtime. Se conserva porque la HU176B (matrícula autónoma por QR) lo nombra como base. Los otros 10 SP legacy de esta tabla (paginados y por id) se eliminaron el 2026-10-29 por no tener uso (`migrations/08_eliminar_codigo_sin_uso_up.sql`).

| SP | Parámetros | Propósito |
|---|---|---|
| `usp_registrar_estudiante_en_grupo_autonomo` | `@idGrupo, @numeroIdentificacion, @primerNombre, @segundoNombre, @primerApellido, @segundoApellido, @correo, @password, @idCorrelacion, @idUsuarioEjecutor, @idTipoIdIdentificacion` | Autoinscripción del estudiante a un grupo (registro + matrícula). Reemplazado en el flujo actual por las solicitudes de ingreso (HU053-HU055). |

## Addendum F2 (2026-11-02): precarga de sesiones del grupo

| Tabla | SP | Endpoint | Rol | Parámetros | Propósito |
|---|---|---|---|---|---|
| `Sesion` | `usp_precargar_sesiones_grupo` | `POST /api/v1/grupos` y `PUT /api/v1/grupos/{id}` (misma transacción que crear o actualizar el grupo y guardar su horario) | COORDINADOR (del programa) o DOCENTE titular | `@idGrupo, @idCorrelacion, @idUsuarioEjecutor` | Crea las sesiones futuras que faltan desde el horario y retira las futuras generadas que ya no encajan. Solo desde hoy; sin duplicar; no toca sesiones pasadas ni las creadas a mano. `SEC_002` si el ejecutor no es el titular o el coordinador del programa |

## Addendum F3 (2026-11-02): el docente crea sus propios grupos

| Tabla / vista | SP | Endpoint | Rol | Parámetros | Propósito |
|---|---|---|---|---|---|
| `uv_docente_programa`, `uv_plan_estudio`, `uv_semestre_plan_estudio`, `uv_asignatura` | `usp_consultar_oferta_creacion_grupo_docente` | `GET /api/v1/docente/oferta-creacion-grupos` | `DOCENTE` | `@idUsuarioEjecutor, @idCorrelacion` | Devuelve el `idDocente` del ejecutor y las asignaturas activas de los programas con vínculo activo, para el formulario "Nuevo grupo". `SEC_001` si el ejecutor no es DOCENTE. |

`usp_crear_grupo` acepta también al DOCENTE: solo a su propio nombre y solo para asignaturas de programas con vínculo activo (`SEC_002` en otro caso). `usp_guardar_horarios_grupo` acepta al docente titular solo para el horario inicial (`HOR_005` si ya existe).

## Addendum F1 (2026-10-30): horario semanal del grupo

| Tabla | SP | Endpoint | Rol | Parámetros | Propósito |
|---|---|---|---|---|---|
| `Horario` | `usp_guardar_horarios_grupo` | `POST /api/v1/grupos` y `PUT /api/v1/grupos/{id}` con `franjas` (misma transacción que crear o actualizar el grupo) | COORDINADOR (del programa); DOCENTE titular solo para el horario inicial (`HOR_005` si ya existe; F3) | `@idGrupo, @horariosJSON, @idCorrelacion, @idUsuarioEjecutor` | Reemplaza el horario semanal del grupo. HOR_004 (formato), HOR_003 (franjas que se cruzan) y HOR_002 (cruce del docente) responden 400, 400 y 409 |

`GET /api/v1/grupos` devuelve además las `franjas` de cada grupo, leídas de `uv_horario`, que ahora expone `codigoDia`; `uv_dia` también expone `codigo`.
