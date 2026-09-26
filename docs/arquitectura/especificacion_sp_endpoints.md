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
  1. Validar que la sesión exista y no esté cerrada (`usp_validar_sesion_exista_por_id_interno`).
  2. Para cada estudiante del lote, validar que pertenezca activamente al grupo de la sesión (`usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno`).
  3. Resolver dinámicamente el `RazonCausa.id` a partir del código enviado (ej. `'AN'`, `'SJC'`).
  4. Insertar o actualizar (`MERGE`) en `Asistencia` + `DetalleAsistencia`.
- **Concurrencia**: `SET XACT_ABORT ON; BEGIN TRANSACTION ... COMMIT`.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
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
  2. Validar que el grupo exista y pertenezca al docente titular (`usp_validar_grupo_exista_para_docente_interno`).
  3. Calcular `@numeroSiguiente = MAX(numero) + 1` con `WITH (UPDLOCK, HOLDLOCK)` sobre `dbo.Sesion`.
  4. Generar código `SES-XX`.
  5. Insertar en `dbo.Sesion`.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_validar_grupo_exista_para_docente_interno`

### Transacción 2.2: Cerrar Sesión y Congelar Planilla

- **Intención de negocio**: El docente cierra oficialmente una sesión. Los estudiantes matriculados sin registro son marcados automáticamente como ausentes.
- **Atomicidad requerida**: Cambiar el flag de cierre + marcar ausencias pendientes en una transacción.
- **Lógica de validación**:
  1. Validar que la sesión exista y no esté ya cerrada.
  2. Validar que el docente sea titular del grupo de la sesión.
  3. Insertar registros de ausencia (`asistio = 0`, `RazonCausa = 'SJC'`) para los estudiantes activos del grupo que no tengan registro en `Asistencia` para esa sesión.
  4. Marcar la sesión como cerrada.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_validar_sesion_exista_por_id_interno`
  - `usp_validar_grupo_exista_para_docente_interno`
  - `usp_marcar_ausencias_pendientes_sesion_interno` *(nuevo)*

### Transacción 2.3: Cancelar Sesión con Motivo

- **Intención de negocio**: El docente cancela una sesión programada registrando el motivo de la cancelación.
- **Atomicidad requerida**: Cambiar estado de la sesión + registrar motivo en una transacción. Las asistencias parcialmente tomadas deben anularse.
- **Lógica de validación**:
  1. Validar existencia de la sesión y titularidad del docente.
  2. Validar que la sesión no haya sido ya cerrada con asistencia completa.
  3. Anular registros existentes de `DetalleAsistencia` para esa sesión.
  4. Marcar la sesión como cancelada con el motivo proporcionado.
- **Procedimientos internos invocados**:
  - `usp_validar_id_correlacion_esta_presente_interno`
  - `usp_validar_sesion_exista_por_id_interno`
  - `usp_validar_grupo_exista_para_docente_interno`

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
  - `usp_validar_estudiante_grupo_exista_interno`

### Transacción 3.3: Asignar o Reasignar Docente a Grupo

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
| `Asistencia`, `DetalleAsistencia` | Registrar asistencia masiva por planilla | `usp_registrar_asistencias_sesion` | `POST /api/v1/asistencias/lote` | `DOCENTE` (titular del grupo) | Recibe JSON con lista de estudiantes y estado. Valida sesión abierta y pertenencia de cada estudiante al grupo. Itera y sincroniza cada asistencia en una transacción atómica. Invoca internamente: `usp_validar_sesion_exista_por_id_interno`, `usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno`, `usp_sincronizar_asistencia_estudiante_interno`. |
| `Asistencia`, `DetalleAsistencia` | Registrar asistencia individual | `usp_registrar_asistencia_estudiante` | `POST /api/v1/asistencias` | `DOCENTE` (titular del grupo) | Registra la asistencia de un único estudiante para una sesión. Valida matrícula activa (`usp_validar_estudiante_grupo_exista_interno`) y existencia de sesión (`usp_validar_sesion_exista_por_id_interno`). Resuelve `RazonCausa` por código y delega a `usp_sincronizar_asistencia_estudiante_interno`. |
| `Asistencia`, `DetalleAsistencia` | Auto-registro de asistencia por QR/PIN | `usp_registrar_asistencia_estudiante_autonomo` | `POST /api/v1/estudiante/asistencia-qr` | `ESTUDIANTE` (matriculado en grupo) | Valida token/PIN efímero (TTL 60s) generado por el docente. Verifica que la sesión esté dentro de la ventana temporal. Valida matrícula activa del estudiante (sin autovivificación). Registra asistencia como `'AN'` (Asistencia Normal). Invoca internamente: `usp_validar_sesion_abierta_con_ventana_temporal_interno`, `usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno`, `usp_sincronizar_asistencia_estudiante_interno`. |
| `Sesion` | Generar token/PIN efímero para asistencia | — *(Backend Java)* | `GET /api/v1/sesiones/{id}/qr-token` | `DOCENTE` (titular del grupo) | Genera un token UUID + PIN de 6 dígitos con expiración de 60 segundos en memoria (sin SP, lógica en Spring Boot `AsistenciaQrController`). |

## Módulo: Gestión de Sesiones

| Tabla | Transacción / Acción de Negocio | Procedimiento Almacenado (BD) | Método del Controlador (Backend) | Rol / Permiso Requerido | Descripción del procedimiento |
|:---|:---|:---|:---|:---|:---|
| `Sesion` | Crear sesión ordinaria o extraordinaria | `usp_crear_sesion` | `POST /api/v1/sesiones` | `DOCENTE` (titular del grupo) | Valida que el grupo pertenezca al docente titular (`usp_validar_grupo_exista_para_docente_interno`). Calcula correlativo secuencial `MAX(numero) + 1` con bloqueo `UPDLOCK, HOLDLOCK`. Genera código `SES-XX`. Inserta en `dbo.Sesion`. |
| `Sesion`, `Asistencia`, `DetalleAsistencia` | Cerrar sesión y congelar planilla | `usp_cerrar_sesion` | `POST /api/v1/sesiones/cierres` | `DOCENTE` (titular del grupo) | Valida existencia de la sesión, que no esté ya cerrada, y titularidad del docente. Marca como ausentes (`asistio = 0`) a los estudiantes activos del grupo sin registro de asistencia para esa sesión (`usp_marcar_ausencias_pendientes_sesion_interno`). Marca sesión como cerrada. |
| `Sesion` | Cancelar sesión con motivo | `usp_cancelar_sesion_con_motivo` | `PATCH /api/v1/docente/sesiones/{id}/cancelar` | `DOCENTE` (titular del grupo) | Valida existencia de la sesión y titularidad del docente. Marca sesión como cancelada con motivo de cancelación. Anula registros existentes de `DetalleAsistencia` para esa sesión si los hay. |
| `Sesion` | Generar sesiones masivas del semestre | `usp_generar_sesiones_grupo` | `POST /api/v1/grupos` *(después de crear grupo)* | `DOCENTE`, `COORDINADOR` | Recibe el ID del grupo. Valida existencia de horarios y coherencia de fechas del periodo. Itera cada día del calendario académico, cruza con las franjas horarias del grupo (tabla `Horario`) y genera las sesiones evitando duplicación. Transacción completa. Invoca: `usp_validar_grupo_exista_por_id_interno`, `usp_validar_horarios_grupo_interno`, `usp_validar_fechas_periodo_academico_interno`. |
| `Sesion` | Actualizar datos operativos de sesión | `usp_actualizar_sesion` | `PUT /api/v1/sesiones/{id}` | `DOCENTE` (titular del grupo) | Actualiza nombre, descripción, fechas de una sesión no cerrada. Valida existencia y titularidad. |

## Módulo: Matrículas e Inscripciones

| Tabla | Transacción / Acción de Negocio | Procedimiento Almacenado (BD) | Método del Controlador (Backend) | Rol / Permiso Requerido | Descripción del procedimiento |
|:---|:---|:---|:---|:---|:---|
| `EstudianteGrupo`, `Grupo` | Matricular estudiante en grupo | `usp_registrar_estudiante_en_grupo_interno` | `POST /api/v1/coordinador/grupos/{id}/estudiantes`, `POST /api/v1/grupos/{id}/estudiantes` | `COORDINADOR` (del programa), `DOCENTE` (titular del grupo) | Valida existencia del estudiante, existencia y habilitación del grupo, unicidad de la matrícula, cruce horario con otros grupos del estudiante, y cupo disponible. Inserta en `EstudianteGrupo` con estado `'A'`. Invoca: `usp_validar_estudiante_exista_por_id_interno`, `usp_validar_grupo_exista_por_id_interno`, `usp_validar_registro_estudiante_en_grupo_interno`, `usp_validar_cruce_horario_estudiante_interno`. |
| `EstudianteGrupo`, `Grupo` | Retirar estudiante de grupo (voluntario) | `usp_retirar_estudiante_de_grupo` | `DELETE /api/v1/coordinador/grupos/{id}/estudiantes/{estId}` | `COORDINADOR` (del programa), `DOCENTE` (titular del grupo) | Valida que exista la relación activa en `EstudianteGrupo`. Cambia estado a `'CVP'` (Cancelado por Voluntad Propia). Actualiza `Grupo.cantidadEstudiantesCancelaronVoluntadPropia`. |
| `Grupo` | Asignar/reasignar docente a grupo | `usp_registrar_docente_en_grupo_interno` | `POST /api/v1/docentes/asignaciones/grupo` | `COORDINADOR` (del programa) | Valida existencia y estado activo del docente. Valida existencia del grupo. Valida cruce de horarios del docente con otros grupos. Actualiza `Grupo.docente`. Invoca: `usp_validar_docente_exista_por_id_interno`, `usp_validar_cruce_horario_docente_interno`. |
| `SolicitudMatricula`, `EstudianteGrupo` | Resolver solicitud de matrícula | `usp_resolver_solicitud_matricula` | `PATCH /api/v1/coordinador/solicitudes-matricula/{id}` | `COORDINADOR` (del programa) | Valida existencia de la solicitud. Si acción = `'APROBADA'`, ejecuta `usp_registrar_estudiante_en_grupo_interno` con todas las validaciones de cupo y cruce. Si `'RECHAZADA'`, solo actualiza estado. |

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
| `Grupo` | Crear grupo académico | `usp_crear_grupo` | `POST /api/v1/grupos` | `DOCENTE`, `COORDINADOR` | Valida existencia de asignatura. Resuelve periodo académico. Valida docente activo. Valida unicidad de código de grupo en asignatura/periodo. Inserta `Grupo` con contadores en 0. Invoca: `usp_validar_docente_exista_por_id_interno`. |
| `Grupo` | Actualizar datos operativos del grupo | `usp_actualizar_grupo` | `PUT /api/v1/grupos/{id}` | `DOCENTE` (titular), `COORDINADOR` | Valida existencia del grupo. Valida docente si se modifica. Valida unicidad de código (excluyendo el propio grupo). Actualiza nombre, código y docente de forma granular (solo campos proporcionados). |
| `Asignatura` | Crear nueva asignatura en plan | `usp_crear_asignatura` | `POST /api/v1/coordinador/planes-estudio/{id}/asignaturas` | `COORDINADOR` (del programa) | Crea una asignatura vinculada a un `SemestrePlanEstudio`, resolviendo `Area` y `Componente` por nombre o ID. |
| `Asignatura` | Actualizar datos de asignatura | `usp_actualizar_asignatura` | `PUT /api/v1/coordinador/planes-estudio/{planId}/asignaturas/{asigId}` | `COORDINADOR` (del programa) | Actualiza código, nombre, créditos, área y componente de una asignatura existente. |
| `Asignatura` | Alternar estado activo/inactivo | `usp_toggle_estado_asignatura` | `PATCH /api/v1/coordinador/asignaturas/{id}/estado` | `COORDINADOR` (del programa) | Valida existencia de la asignatura. Alterna el campo `estado` entre 1 y 0 atómicamente. |
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
> Todas las lecturas se ejecutan directamente sobre las **43 vistas relacionales (`uv_*`)** desde los adaptadores secundarios de Spring Boot con `NamedParameterJdbcTemplate` y paginación nativa `OFFSET / FETCH`. No requieren procedimientos almacenados.

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
| `uv_solicitud_revision_asistencia` | Listar reclamos del estudiante / docente | `GET /api/v1/estudiante/reclamos`, `GET /api/v1/docente/reclamos` | `ESTUDIANTE`, `DOCENTE` |
| `uv_tipo_identificacion` | Listar tipos de identificación | `GET /api/v1/tipos-identificacion` | `TODOS` |
| `uv_usuario_perfil` | Consultar perfil del usuario autenticado | `GET /api/v1/usuarios/perfil` | `TODOS` (autenticado) |

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
| `usp_validar_grupo_exista_para_docente_interno` | Validación RBAC | Valida que el grupo pertenezca al docente titular | `usp_crear_sesion`, `usp_cerrar_sesion`, `usp_registrar_docente*` |
| `usp_validar_estudiante_grupo_exista_interno` | Validación | Valida existencia de matrícula activa `EstudianteGrupo` | `usp_registrar_asistencia_estudiante` |
| `usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno` | Validación | Valida que el estudiante esté inscrito en el grupo de la sesión | `usp_registrar_asistencias_sesion`, `usp_radicar_solicitud*` |
| `usp_validar_registro_estudiante_en_grupo_interno` | Unicidad | Valida que el estudiante no esté ya matriculado en el grupo | `usp_registrar_estudiante_en_grupo_interno` |
| `usp_validar_cruce_horario_estudiante_interno` | Concurrencia | Detecta solapamientos entre franjas horarias del estudiante | `usp_registrar_estudiante_en_grupo_interno` |
| `usp_validar_cruce_horario_docente_interno` | Concurrencia | Detecta solapamientos entre franjas horarias del docente | `usp_registrar_docente_en_grupo_interno` |
| `usp_validar_horarios_grupo_interno` | Validación | Verifica que el grupo tenga franjas horarias configuradas | `usp_generar_sesiones_grupo` |
| `usp_validar_fechas_periodo_academico_interno` | Validación | Valida coherencia y vigencia de fechas del periodo | `usp_generar_sesiones_grupo` |
| `usp_validar_unicidad_usuario_interno` | Unicidad | Valida unicidad de correo y documento en `uv_usuario` | `usp_sincronizar_usuario_interno` |
| `usp_validar_tipo_identificacion_exista_por_id_interno` | Validación | Valida existencia del tipo de identificación | `usp_sincronizar_usuario_interno` |
| `usp_validar_perfil_existe_por_codigo_interno` | Validación | Valida existencia de un perfil institucional por código | `usp_sincronizar_*_interno` |
| `usp_validar_usuario_existe_por_id_interno` | Validación | Valida existencia del usuario por ID | Reutilizable |
| `usp_sincronizar_usuario_interno` | Persistencia | Crea o actualiza registro en `Usuario` | `usp_crear_decano`, `usp_crear_coordinador` |
| `usp_sincronizar_asistencia_estudiante_interno` | Persistencia | MERGE idempotente en `Asistencia` + `DetalleAsistencia` | `usp_registrar_asistencia*`, `usp_registrar_asistencias_sesion` |
| `usp_sincronizar_docente_interno` | Persistencia | Crea registro `Docente` desde `Usuario` existente | `DocenteRepositorySqlServerAdapter` |
| `usp_sincronizar_estudiante_interno` | Persistencia | Crea registro `Estudiante` desde `Usuario` existente | Orquestadores de registro estudiantil |
| `usp_obtener_mensaje_catalogo` | Mensajería | Traduce códigos de catálogo a mensajes para usuario/técnico | Todos los SPs |
