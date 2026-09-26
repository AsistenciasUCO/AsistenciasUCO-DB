# Especificación Técnica de Transacciones y Procedimientos Reactivos Compuestos
## Sistema de Gestión de Asistencia Académica (`gestionasistenciadb`)

---

## 🏛️ Introducción Arquitectónica

El presente documento define la arquitectura detallada de **180 Transacciones y Procedimientos Reactivos Compuestos** para el ecosistema `gestionasistenciadb`.

A diferencia de las operaciones CRUD tradicionales que ejecutan mutaciones simples aisladas, una **Transacción Reactiva Compuesta (PR)** es un procedimiento atómico orquestado a nivel de negocio que:
1. **Consolida múltiples Historias de Usuario (HUs)** en una sola llamada desde la aplicación cliente.
2. **Previene datos huérfanos e inconsistencias en el MER** (ej. crear usuarios sin asignación institucional o registrar asistencias sin verificar la validez de la sesión/matrícula).
3. **Garantiza la integridad referencial y atómica** ejecutando validaciones de entrada, transformaciones de estado y propagaciones en cascada en un solo bloque de transacción.

---

### [PR-002] - Registrar Docente Institucional en Grupo (Creación/Actualización Reactiva de Usuario + Rol Docente + Asignación a Grupo)
- **Historias de Usuario que satisface:** HU052 (Registro de docentes en grupos con validación de existencia), HU050 (Sincronización de usuarios).
- **Propósito de Negocio:** Permite asignar un docente a un grupo académico en un solo paso. Si la persona no está registrada como usuario o no tiene perfil de docente instituido, la transacción lo crea y categoriza reactivamente antes de vincularlo al grupo, evitando fallos por clave foránea o datos incompletos.
- **Entidades del MER Involucradas:** `Usuario`, `Docente`, `Grupo`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idGrupo` exista y esté en un estado activo.
  2. Ejecutar la sincronización interna de usuario (`PR-001` / `usp_sincronizar_usuario_interno`): crear o actualizar datos personales en `Usuario`.
  3. Verificar si el usuario ya tiene un registro en la tabla `Docente` para la `Institucion` del grupo:
     * **Si NO existe:** Insertar en `Docente` relacionando `idUsuario`, `idInstitucion` y `estado = 1`.
     * **Si existe:** Asegurar que su estado sea activo.
  4. Validar que el docente no tenga cruces de horario incompatibles en otros grupos activos para el mismo periodo académico.
  5. Asignar el `idDocente` como titular en la tabla `Grupo` (o tabla de vinculación docente-grupo).
- **Reglas de Negocio y Validaciones Específicas:**
  * Un docente no puede ser asignado a un grupo cuyo periodo académico ya esté cerrado.
  * Se verifica la unicidad de la relación docente-grupo para evitar duplicaciones.
- **Estado Resultante en la BD:** Usuario registrado/actualizado, perfil de `Docente` asegurado y tabla `Grupo` vinculada al docente en estado activo.

---

### [PR-003] - Registrar Estudiante Institucional en Grupo (Sincronización + Perfil Estudiante + Programa + Matrícula en Grupo)
- **Historias de Usuario que satisface:** HU053 (Registro e inscripción de estudiantes en grupos académicos), HU051 (Registro en programas académicos), HU050.
- **Propósito de Negocio:** Orquesta el enrolamiento completo de un estudiante en un grupo. Registra/actualiza al usuario, le otorga el rol de `Estudiante`, lo inscribe en el `Programa` correspondiente a la asignatura del grupo si no lo está, y finalmente lo matricula en `EstudianteGrupo` con estado activo.
- **Entidades del MER Involucradas:** `Usuario`, `Estudiante`, `EstudiantePrograma`, `Programa`, `Grupo`, `Asignatura`, `EstudianteGrupo`, `EstadoEstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la existencia del `idGrupo` y que el cupo máximo (`cupoMaximo`) no haya sido superado por las matrículas activas existentes.
  2. Ejecutar la sincronización reactiva de usuario (`Usuario`): crear o actualizar los datos personales.
  3. Validar/Insertar el registro del rol en la tabla `Estudiante` (`idUsuario`, `idInstitucion`).
  4. Identificar el `Programa` académico a través de la `Asignatura` del `Grupo`:
     * Verificar si existe la relación en `EstudiantePrograma`. Si no existe, crear la vinculación reactivamente.
  5. Obtener el `idEstadoEstudianteGrupo` correspondiente a "MATRICULADO / ACTIVO".
  6. Insertar el registro de matrícula en `EstudianteGrupo` (`idEstudiante`, `idGrupo`, `estadoEstudianteGrupo`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Rechaza la matrícula si el número de inscritos en `EstudianteGrupo` es igual o mayor a `cupoMaximo` del `Grupo`.
  * Evita la doble matrícula activa de un mismo estudiante en el mismo grupo.
- **Estado Resultante en la BD:** Estudiante dado de alta en `Usuario`, `Estudiante`, `EstudiantePrograma` y matriculado formalmente en `EstudianteGrupo`.

---

### [PR-004] - Asignar Decano a Facultad con Validación/Creación de Usuario e Inactivación de Decano Previo
- **Historias de Usuario que satisface:** HU102 (Gestión macro de facultades y decanaturas), HU050.
- **Propósito de Negocio:** Garantizar que una facultad tenga exactamente un Decano activo titular. Si ya existía un decano previo en la facultad, lo inactiva o desvincula en la misma transacción antes de promover al nuevo usuario y asignarlo a la `Facultad`.
- **Entidades del MER Involucradas:** `Usuario`, `Decano`, `Facultad`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la existencia y estado activo de la `Facultad` y de la `Institucion`.
  2. Sincronizar/Crear los datos personales del nuevo candidato a Decano en `Usuario`.
  3. Verificar/Crear el rol de `Decano` para el usuario en la `Institucion`.
  4. Consultar el decano actual en `Facultad`:
     * Si la `Facultad` tiene un `decano` (FK) asignado diferente al nuevo, cambiar el estado del decano saliente en la tabla `Decano` a inactivo o remover la titularidad.
  5. Actualizar la clave foránea `decano` en la tabla `Facultad` apuntando al nuevo ID de `Decano`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Una `Facultad` no puede quedarse con una referencia nula a `Decano` a menos que esté en estado inactivo.
  * El usuario asignado como decano debe estar en estado activo en `Usuario`.
- **Estado Resultante en la BD:** Nuevo decano promovido en `Decano` y actualizado como titular de la `Facultad`; decano anterior archivado/inactivado de forma limpia.

---

### [PR-005] - Asignar Coordinador a Programa Académico con Actualización Reactiva y Transferencia de Dirección
- **Historias de Usuario que satisface:** HU066 (Gestión de coordinación de programas), HU050.
- **Propósito de Negocio:** Permite asignar la dirección de un programa académico a un profesional. Crea/actualiza la cuenta de usuario, le asigna el rol de `Coordinador` institucional y actualiza la FK `coordinador` en la entidad `Programa`.
- **Entidades del MER Involucradas:** `Usuario`, `Coordinador`, `Programa`, `Institucion`, `Facultad`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idPrograma` exista y pertenezca a una `Facultad` activa.
  2. Sincronizar los datos del usuario en la tabla `Usuario`.
  3. Verificar la presencia del rol en la tabla `Coordinador` para la `Institucion` dada; si no existe, insertarlo en estado activo.
  4. Actualizar el campo `coordinador` en `Programa` asignando la FK del nuevo `Coordinador`.
  5. Registrar el evento en la bitácora de cambios de administración académica.
- **Reglas de Negocio y Validaciones Específicas:**
  * Un coordinador debe estar asociado a la misma institución a la que pertenece la facultad del programa.
- **Estado Resultante en la BD:** El campo `coordinador` en `Programa` queda actualizado atómicamente con el rol `Coordinador` vigente.

---

### [PR-006] - Actualización Perfilada de Datos Personales de Usuario con Re-validación de Credenciales
- **Historias de Usuario que satisface:** HU050 (Gestión de cuentas de usuarios).
- **Propósito de Negocio:** Actualizar de forma segura nombres, apellidos, correo y contraseña de un usuario existente, verificando la no duplicidad del correo con otros usuarios activos antes de confirmar los cambios.
- **Entidades del MER Involucradas:** `Usuario`, `TipoIdentificacion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idUsuario` exista en la BD.
  2. Si el correo electrónico va a ser modificado, validar que no pertenezca a ningún otro usuario diferente en `Usuario`.
  3. Validar que el `idTipoIdentificacion` sea válido.
  4. Actualizar los campos `primerNombre`, `segundoNombre`, `primerApellido`, `segundoApellido`, `correo` y opcionalmente `password` en la tabla `Usuario`.
- **Reglas de Negocio y Validaciones Específicas:**
  * No se permite cambiar el número de identificación ni el tipo de documento a menos que se invoque una transacción especial de rectificación de identidad (`PR-015`).
- **Estado Resultante en la BD:** `Usuario` actualizado con datos personales consistentes y correo único.

---

### [PR-007] - Desactivación Reactiva de Usuario con Inactivación en Cascada de Roles
- **Historias de Usuario que satisface:** HU050 (Gestión del estado de usuarios y seguridad).
- **Propósito de Negocio:** Cuando un usuario es inhabilitado (ej. por retiro de la universidad), la transacción marca `estado = 0` en `Usuario` y desactiva en cascada todos sus roles activos (`Docente`, `Estudiante`, `Coordinador`, `Decano`), evitando que conserve permisos en el sistema.
- **Entidades del MER Involucradas:** `Usuario`, `Docente`, `Estudiante`, `Coordinador`, `Decano`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `idUsuario`.
  2. Actualizar el campo `estado = 0` en la tabla `Usuario`.
  3. Desactivar (`estado = 0`) en la tabla `Docente` si el usuario tenía registro.
  4. Desactivar (`estado = 0`) en la tabla `Estudiante` si el usuario tenía registro.
  5. Desactivar (`estado = 0`) en la tabla `Coordinador` si el usuario tenía registro.
  6. Desactivar (`estado = 0`) en la tabla `Decano` si el usuario tenía registro.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si el usuario es el único `Decano` activo de una facultad o `Coordinador` de un programa, la transacción retorna una advertencia o exige la reasignación previa para evitar FKs inconsistentes.
- **Estado Resultante en la BD:** Usuario y todos sus registros de rol asociados quedan en `estado = 0` (inactivo).

---

### [PR-008] - Reactivación Integral de Usuario y Reincorporación a Estructuras Académicas
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Reactivar un usuario previamente inhabilitado, cambiando su estado a activo y restaurando sus roles institucionales principales tras verificación administrativa.
- **Entidades del MER Involucradas:** `Usuario`, `Docente`, `Estudiante`, `Coordinador`, `Decano`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `idUsuario` inactivo (`estado = 0`).
  2. Actualizar `estado = 1` en la tabla `Usuario`.
  3. Reactivar reactivamente los roles de `Estudiante` o `Docente` asociados al usuario según la solicitud de reincorporación.
- **Reglas de Negocio y Validaciones Específicas:**
  * No reactiva automáticamente asignaciones a grupos cerrados o periodos académicos vencidos.
- **Estado Resultante en la BD:** Usuario con `estado = 1` y roles institucionales vigentes reactivados.

---

### [PR-010] - Conversión Reactiva de Rol (Promoción de Estudiante/Docente a Coordinador o Decano)
- **Historias de Usuario que satisface:** HU050, HU066, HU102.
- **Propósito de Negocio:** Permitir que un usuario que ya posee el rol de `Estudiante` o `Docente` adquiera un nuevo rol de gestión (`Coordinador` o `Decano`) sin necesidad de duplicar su cuenta de usuario ni alterar su histórico académico previo.
- **Entidades del MER Involucradas:** `Usuario`, `Docente`, `Estudiante`, `Coordinador`, `Decano`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idUsuario` exista y esté en estado activo (`estado = 1`).
  2. Identificar el nuevo rol a asignar (`Coordinador` o `Decano`).
  3. Verificar si el registro en la tabla de rol de destino ya existe:
     * Si no existe, insertar un nuevo registro relacionando `idUsuario`, `idInstitucion` y `estado = 1`.
     * Si existe pero estaba inactivo, reactivarlo (`estado = 1`).
  4. Mantener intactos los registros existentes en `Docente` o `Estudiante`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Un mismo `idUsuario` puede poseer múltiples roles activos en la misma `Institucion` manteniendo la integridad de sus claves primarias.
- **Estado Resultante en la BD:** El usuario mantiene su identidad única en `Usuario` y adquiere una nueva tupla en la tabla del rol otorgado.

---

### [PR-012] - Cambio de Contraseña y Expiración de Credenciales con Auditoría de Seguridad
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Permite la actualización segura de la clave de acceso de un usuario previa validación de la contraseña anterior o token de recuperación, registrando la traza del cambio.
- **Entidades del MER Involucradas:** `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `idUsuario`.
  2. Verificar que la contraseña anterior o el token de restablecimiento sea correcto.
  3. Hash/Encriptar la nueva contraseña e implemetarla en el campo `password` de `Usuario`.
- **Reglas de Negocio y Validaciones Específicas:**
  * La nueva contraseña no debe ser igual a la anterior.
- **Estado Resultante en la BD:** Campo `password` en `Usuario` actualizado atómicamente.

---

### [PR-017] - Asignación Reactiva de Administrador Institucional con Configuración de Alcance
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Otorga privilegios de administración global o de sede a un usuario existente o nuevo, vinculándolo a la entidad `Institucion`.
- **Entidades del MER Involucradas:** `Usuario`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la existencia de la `Institucion`.
  2. Sincronizar/Crear los datos del usuario en la tabla `Usuario`.
  3. Registrar o actualizar la tupla del perfil administrador asociándolo a la `Institucion`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Requiere confirmación del Administrador raíz para otorgar alcance global.
- **Estado Resultante en la BD:** Usuario configurado con rol y permisos administrativos sobre la institución.

---

### [PR-018] - Sincronización de Correo Electrónico Institucional y Actualización de Dominios Habilitados
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Actualizar el dominio del correo institucional de un grupo de usuarios cuando la universidad cambia su dominio de correo (ej. de `@uco.edu.co` a `@uco.edu`), manteniendo la integridad de las cuentas.
- **Entidades del MER Involucradas:** `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir el dominio anterior y el nuevo dominio institucional.
  2. Identificar los registros en `Usuario` cuyo correo coincida con el dominio anterior.
  3. Reemplazar la extensión de correo conservando el identificador local previa validación de no duplicidad.
  4. Actualizar masivamente la tabla `Usuario`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Aborta cualquier registro individual que genere conflicto de unicidad con un correo preexistente.
- **Estado Resultante en la BD:** Correos actualizados en `Usuario` bajo el nuevo dominio institucional.

---

### [PR-020] - Inactivación Temporal de Docente con Suspensión de Asignaciones a Grupos Activos
- **Historias de Usuario que satisface:** HU052, HU050.
- **Propósito de Negocio:** Suspender temporalmente el rol de un docente (ej. por comisión de estudios o licencia médica) sin borrar su usuario, desvinculándolo reactivamente de los grupos activos donde figura como titular.
- **Entidades del MER Involucradas:** `Usuario`, `Docente`, `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `idDocente`.
  2. Cambiar `estado = 0` en la tabla `Docente`.
  3. Identificar los `Grupo` activos del periodo donde el docente es titular.
  4. Dejar el campo `docente` en estado nulo o reasignar temporalmente según requerimiento.
- **Reglas de Negocio y Validaciones Específicas:**
  * Genera una lista de advertencia con los grupos que quedaron sin docente asignado para requerir su pronta reasignación (`PR-026`).
- **Estado Resultante en la BD:** `Docente` inactivo y grupos involucrados notificados para asignación de reemplazo.

---

### [PR-021] - Inactivación Temporal de Estudiante con Suspensión de Matrículas en Periodo Académico
- **Historias de Usuario que satisface:** HU053, HU050.
- **Propósito de Negocio:** Registrar la reserva de cupo o suspensión temporal de estudios de un alumno, inactivando su perfil de `Estudiante` y marcando sus matrículas activas en `EstudianteGrupo` como "SUSPENDIDA / CANCELADA VOLUNTARIA".
- **Entidades del MER Involucradas:** `Usuario`, `Estudiante`, `EstudianteGrupo`, `EstadoEstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idEstudiante` tenga matrículas activas en el periodo vigente.
  2. Actualizar `estado = 0` en la entidad `Estudiante`.
  3. Actualizar todas las filas en `EstudianteGrupo` para el periodo vigente al estado "CANCELADO_VOLUNTARIO".
  4. Liberar el cupo reservado en los respectivos `Grupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * No elimina las asistencias históricas previamente tomadas en las sesiones transcurridas.
- **Estado Resultante en la BD:** Estudiante suspendido y cupos liberados en los grupos matriculados.

---

### [PR-024] - Validación de Unicidad de Correo e Identificación con Generación de Reporte de Inconsistencias
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Procedimiento reactivo de diagnóstico e higiene de datos para detectar registros homónimos o colisiones de correo/documento antes de migraciones de periodo.
- **Entidades del MER Involucradas:** `Usuario`, `TipoIdentificacion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Escanear la tabla `Usuario` buscando duplicidades en `(tipoIdentificacion, numeroIdentificacion)` y en `correo`.
  2. Marcar temporalmente los registros con bandera de inconsistencia.
  3. Retornar el reporte detallado para acción administrativa.
- **Reglas de Negocio y Validaciones Específicas:**
  * Operación atómica de solo lectura de inconsistencias sin alterar datos sin autorización.
- **Estado Resultante en la BD:** Reporte de calidad de datos generado.

---

### [PR-032] - Crear Facultad con Vinculación Inmediata de Decano y Áreas Iniciales
- **Historias de Usuario que satisface:** HU102 (Gestión de Facultades).
- **Propósito de Negocio:** Dar de alta una `Facultad` académica asociándola a una `Institucion`, nombrando atómicamente a su `Decano` titular e inicializando sus áreas del conocimiento.
- **Entidades del MER Involucradas:** `Facultad`, `Institucion`, `Decano`, `Area`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Institucion` exista y esté activa.
  2. Validar o registrar al usuario decano y asegurar su perfil en `Decano` (`PR-004`).
  3. Insertar la nueva `Facultad` relacionando `nombre`, `institucion` y `decano`.
  4. Crear el `Area` general por defecto para la facultad.
- **Reglas de Negocio y Validaciones Específicas:**
  * No se permite crear una facultad sin un decano válido asignado.
- **Estado Resultante en la BD:** `Facultad` creada y vinculada a su institución, decano y área base.

---

### [PR-033] - Crear Programa Académico con Coordinador Asignado, Tipo de Programa y Facultad
- **Historias de Usuario que satisface:** HU051, HU066.
- **Propósito de Negocio:** Registrar una carrera profesional o posgrado (ej. Ingeniería de Sistemas). Asigna el `TipoPrograma`, lo vincula a la `Facultad` y nombra atómicamente al `Coordinador` responsable.
- **Entidades del MER Involucradas:** `Programa`, `Facultad`, `TipoPrograma`, `Coordinador`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia y estado activo de la `Facultad` y `TipoPrograma`.
  2. Sincronizar/Asignar al `Coordinador` institucional (`PR-005`).
  3. Insertar en `Programa` relacionando `nombre`, `facultad`, `tipoPrograma`, `coordinador` y `estado = 1`.
- **Reglas de Negocio y Validaciones Específicas:**
  * El nombre del programa debe ser único dentro de la misma facultad.
- **Estado Resultante en la BD:** `Programa` registrado y listo para estructurar planes de estudio.

---

### [PR-034] - Estructurar Plan de Estudio con Asignación Automática de Semestres Académicos
- **Historias de Usuario que satisface:** HU018, HU019.
- **Propósito de Negocio:** Crear la malla curricular (`PlanEstudio`) para un programa académico y generar automáticamente los registros de `SemestrePlanEstudio` para la cantidad de semestres definida (ej. 1 a 10 semestres).
- **Entidades del MER Involucradas:** `PlanEstudio`, `Programa`, `Semestre`, `SemestrePlanEstudio`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idPrograma` esté activo.
  2. Insertar el nuevo `PlanEstudio` (`nombre`, `programa`, `estado = 1`).
  3. Consultar los registros de la tabla `Semestre` (del 1 al N).
  4. Por cada semestre, crear la tupla en `SemestrePlanEstudio` asociando `planEstudio` y `semestre`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Un programa puede tener múltiples planes de estudio (ej. Plan 2018, Plan 2024), pero solo uno vigente para nuevos ingresos.
- **Estado Resultante en la BD:** `PlanEstudio` creado con toda la estructura de semestres lista para asociar materias.

---

---

### [PR-036] - Asociar Asignaturas a Semestres en el Plan de Estudios con Validación de Coherencia Curricular
- **Historias de Usuario que satisface:** HU025 (Consultar asignaturas por semestre en el plan de estudios).
- **Propósito de Negocio:** Asociar una asignatura a un semestre de un plan de estudios. La transacción valida atómicamente que no existan ciclos infinitos de prerrequisitos (ej. A depende de B y B depende de A).
- **Entidades del MER Involucradas:** `Asignatura`, `SemestrePlanEstudio`, `PlanEstudio`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la asignatura origen y la asignatura requerida pertenezcan al mismo `PlanEstudio`.
  2. Verificar que la asignatura prerrequisito esté en un `Semestre` anterior a la asignatura objetivo.
  3. Ejecutar algoritmo recursivo de grafos para verificar la ausencia de dependencias circulares.
  4. Registrar la relación de prerrequisito.
- **Reglas de Negocio y Validaciones Específicas:**
  * No se permite que una asignatura sea prerrequisito de sí misma ni de asignaturas de su mismo semestre.
- **Estado Resultante en la BD:** Prerrequisito registrado y validado en la estructura curricular.

---

### [PR-037] - Inactivar Programa Académico con Verificación de Planes de Estudio y Estudiantes Inscritos
- **Historias de Usuario que satisface:** HU051, HU066.
- **Propósito de Negocio:** Inactivar un programa académico que entra en liquidación o sustitución, deshabilitando sus nuevos ingresos mientras se protegen las matrículas de estudiantes activos hasta su graduación.
- **Entidades del MER Involucradas:** `Programa`, `PlanEstudio`, `EstudiantePrograma`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `idPrograma`.
  2. Verificar la cantidad de estudiantes activos en `EstudiantePrograma`.
  3. Cambiar `estado = 0` en `Programa` impidiendo nuevas inscripciones.
  4. Inactivar los `PlanEstudio` asociados para nuevas aperturas.
- **Reglas de Negocio y Validaciones Específicas:**
  * Mantiene habilitados los grupos vigentes para estudiantes antiguos en proceso de culminación.
- **Estado Resultante en la BD:** `Programa` marcado con `estado = 0` para admisiones de nuevos estudiantes.

---

### [PR-038] - Crear Periodo Académico con Apertura de Calendario y Rangos de Fechas Validados
- **Historias de Usuario que satisface:** HU028, HU034, HU027.
- **Propósito de Negocio:** Registrar un nuevo ciclo lectivo (ej. "2026-1"), definiendo atómicamente la fecha de inicio (`fechaInicio`) y fin (`fechaFin`) que regirán los rangos válidos para abrir sesiones y registrar asistencias.
- **Entidades del MER Involucradas:** `PeriodoAcademico`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el código del periodo (ej. "2026-1") no exista previamente en `PeriodoAcademico`.
  2. Validar que `fechaFin` sea posterior a `fechaInicio`.
  3. Insertar la tupla en `PeriodoAcademico` (`id`, `codigo`, `fechaInicio`, `fechaFin`, `estado = 1`).
- **Reglas de Negocio y Validaciones Específicas:**
  * No se pueden solapar dos periodos académicos regulares en el mismo rango de fechas salvo periodos especiales vacacionales.
- **Estado Resultante en la BD:** `PeriodoAcademico` activo habilitado para aperturar oferta de grupos.

---

### [PR-039] - Actualizar Periodo Académico con Reprogramación de Rangos de Fechas en Sesiones y Grupos
- **Historias de Usuario que satisface:** HU028.
- **Propósito de Negocio:** Reajustar las fechas de inicio o fin de un periodo lectivo en curso (ej. por extensiones del calendario académico), actualizando reactivamente los límites de vigencia de todos sus grupos y sesiones programadas.
- **Entidades del MER Involucradas:** `PeriodoAcademico`, `Grupo`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idPeriodoAcademico` exista.
  2. Actualizar `fechaInicio` y/o `fechaFin` en `PeriodoAcademico`.
  3. Ajustar los rangos de vigencia de las entidades `Grupo` asociadas a este periodo.
  4. Reprogramar o validar las fechas en la tabla `Sesion` que queden fuera del nuevo rango.
- **Reglas de Negocio y Validaciones Específicas:**
  * No permite acortar un periodo a una fecha pasada que invalide sesiones que ya tengan asistencias registradas.
- **Estado Resultante en la BD:** Rangos del periodo y sesiones del calendario sincronizados.

---

### [PR-040] - Cierre Oficial de Periodo Académico con Consolidación de Estadísticas de Ausentismo
- **Historias de Usuario que satisface:** HU001, HU002, HU066, HU102.
- **Propósito de Negocio:** Concluir formalmente un periodo académico. Cierra reactivamente todas las sesiones pendientes, congela las asistencias, calcula los porcentajes finales de inasistencia por estudiante/grupo y cambia `estado = 0` en `PeriodoAcademico`.
- **Entidades del MER Involucradas:** `PeriodoAcademico`, `Grupo`, `Sesion`, `Asistencia`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el periodo académico se encuentre en la fecha de cierre o posterior.
  2. Cerrar atómicamente todas las `Sesion` del periodo que permanezcan en estado abierto (`PR-124`).
  3. Calcular y congelar el porcentaje final de ausentismo acumulado para cada `EstudianteGrupo`.
  4. Cambiar `estado = 0` en `PeriodoAcademico`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Al cerrar el periodo, se bloquean todas las modificaciones posteriores a registros de asistencia a través del flujo regular docente.
- **Estado Resultante en la BD:** `PeriodoAcademico` cerrado y consolidado estadísticamente.

---

### [PR-051] - Inactivar Facultad con Reubicación o Inactivación de Programas Académicos
- **Historias de Usuario que satisface:** HU102.
- **Propósito de Negocio:** Inactivar una facultad universitaria reubicando o cerrando en cascada sus programas académicos adscritos.
- **Entidades del MER Involucradas:** `Facultad`, `Programa`, `Decano`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Facultad` no tenga grupos activos en curso.
  2. Inactivar los `Programa` asociados que no hayan sido transferidos.
  3. Inactivar la titularidad del `Decano`.
  4. Actualizar `estado = 0` en `Facultad`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Bloquea la inactivación si existen materias con clases dictándose en el periodo actual.
- **Estado Resultante en la BD:** `Facultad` y sus dependencias inactivadas ordenadamente.

---

### [PR-053] - Actualizar Créditos y Horas Semanales de Asignatura con Recálculo de Intensidad
- **Historias de Usuario que satisface:** HU007.
- **Propósito de Negocio:** Modificar la intensidad horaria o créditos académicos de una materia, recalculando el número estimado de sesiones teóricas del periodo.
- **Entidades del MER Involucradas:** `Asignatura`, `Grupo`, `Horario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la `Asignatura`.
  2. Actualizar los datos de intensidad horaria en `Asignatura`.
- **Reglas de Negocio y Validaciones Específicas:**
  * No altera de forma retroactiva las sesiones que ya han sido ejecutadas en periodos cerrados.
- **Estado Resultante en la BD:** Intensidad horaria de la asignatura actualizada.

---

### [PR-059] - Auditoría Cambios Malla Curricular y Planes de Estudio
- **Historias de Usuario que satisface:** HU019.
- **Propósito de Negocio:** Registrar en la bitácora de auditoría cualquier adición, modificación o retiro de asignaturas en los planes de estudio.
- **Entidades del MER Involucradas:** `PlanEstudio`, `Asignatura`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir los datos de la modificación realizada sobre la malla.
  2. Insertar la traza con `idCorrelacion`, usuario responsable y valores anteriores/nuevos.
- **Reglas de Negocio y Validaciones Específicas:**
  * Inmutable y atómica con la mutación realizada sobre la estructura académica.
- **Estado Resultante en la BD:** Registro de auditoría de malla curricular guardado.

---

---

### [PR-062] - Programación de Horario para Grupo con Validación de Cruces Horarios de Docente y Día
- **Historias de Usuario que satisface:** HU048 (Crear horarios para clases), HU034 (Validar cruce horario docente).
- **Propósito de Negocio:** Asignar la franja horaria (`horaInicio` a `horaFin`) y el día (`Dia`) a un grupo. La transacción valida reactivamente que el docente asignado al grupo no tenga otra clase programada a esa misma hora en otro grupo.
- **Entidades del MER Involucradas:** `Horario`, `Grupo`, `Dia`, `Docente`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `Grupo` y que `horaFin` sea posterior a `horaInicio`.
  2. Validar que el `idDia` exista en la tabla `Dia`.
  3. Consultar los horarios del docente titular del grupo para el mismo `Dia` en el periodo académico:
     * **Si existe superposición de horas:** Abortar la transacción emitiendo un mensaje descriptivo de cruce de horario.
  4. Insertar en `Horario` (`grupo`, `dia`, `horaInicio`, `horaFin`, `estado = 1`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Un grupo puede tener múltiples registros en `Horario` (ej. Lunes 08:00-10:00 y Miércoles 08:00-10:00).
- **Estado Resultante en la BD:** Franja horaria registrada en `Horario` sin colisión de agenda docente.

---

### [PR-064] - Cancelación de Grupo Académico con Desinscripción en Cascada y Liberación de Horarios
- **Historias de Usuario que satisface:** HU047 (Cancelar sesión/grupo), HU051 (Retirar estudiantes).
- **Propósito de Negocio:** Cancelar un grupo por baja matrícula u orden administrativa. Inactiva el grupo (`estado = 0`), cambia todas sus matrículas en `EstudianteGrupo` a "GRUPO_CANCELADO" e inactiva sus franjas horarias en una sola transacción atómica.
- **Entidades del MER Involucradas:** `Grupo`, `EstudianteGrupo`, `Horario`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `Grupo`.
  2. Cambiar `estado = 0` en `Grupo`.
  3. Inactivar (`estado = 0`) todas las tuplas en `Horario` asociadas al grupo.
  4. Actualizar las matrículas en `EstudianteGrupo` al estado "CANCELADO_POR_INSTITUCION".
  5. Inactivar o cancelar las `Sesion` futuras programadas que no tengan asistencias registradas.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si el grupo ya tiene asistencias tomadas en sesiones dictadas, se preserva el historial atómicamente.
- **Estado Resultante en la BD:** Grupo e inscripciones canceladas ordenadamente.

---

### [PR-065] - Modificación de Cupo Máximo de Grupo con Verificación de Matriculados Activos
- **Historias de Usuario que satisface:** HU044.
- **Propósito de Negocio:** Ampliar o reducir la capacidad de estudiantes de un grupo, asegurando que el nuevo cupo no sea inferior al número de estudiantes ya matriculados activos.
- **Entidades del MER Involucradas:** `Grupo`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Contar la cantidad de estudiantes con matrícula activa en `EstudianteGrupo` para el `Grupo`.
  2. Validar que `nuevoCupoMaximo` sea mayor o igual al conteo de matriculados activos.
  3. Actualizar `cupoMaximo` en `Grupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si el nuevo cupo es menor a los alumnos inscritos, la transacción retorna error de restricción de capacidad.
- **Estado Resultante en la BD:** Campo `cupoMaximo` en `Grupo` actualizado.

---

### [PR-066] - Reprogramación de Horario de Grupo con Actualización Masiva de Fechas de Sesiones
- **Historias de Usuario que satisface:** HU049 (Modificar horarios), HU046 (Cambiar datos de sesión).
- **Propósito de Negocio:** Modificar el día u hora de una clase ya iniciada en el periodo y recalcular atómicamente las fechas de las futuras sesiones programadas en la tabla `Sesion`.
- **Entidades del MER Involucradas:** `Horario`, `Grupo`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar el `idHorario` y los nuevos datos de `dia`, `horaInicio` y `horaFin`.
  2. Verificar disponibilidad del docente en el nuevo horario (`PR-073`).
  3. Actualizar la tupla en `Horario`.
  4. Actualizar la fecha y horas en la tabla `Sesion` para las sesiones futuras sin asistencia tomada.
- **Reglas de Negocio y Validaciones Específicas:**
  * Las sesiones pasadas que ya cuentan con registros en `Asistencia` se mantienen inmutables.
- **Estado Resultante en la BD:** Horarios y sesiones futuras re-sincronizadas.

---

### [PR-071] - Apertura Masiva de Grupos para Periodo Académico Basado en Oferta del Periodo Anterior
- **Historias de Usuario que satisface:** HU043.
- **Propósito de Negocio:** Clonar la estructura de grupos de un periodo anterior para el nuevo periodo lectivo, agilizando la preparación del calendario académico.
- **Entidades del MER Involucradas:** `Grupo`, `Horario`, `PeriodoAcademico`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar el `idPeriodoAnterior` y el `idPeriodoNuevo`.
  2. Obtener la lista de grupos activos del periodo anterior.
  3. Por cada grupo, crear la nueva tupla en `Grupo` para el nuevo periodo y clonar sus franjas en `Horario`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Se crean sin docente asignado ni estudiantes matriculados para posterior ajuste.
- **Estado Resultante en la BD:** Oferta de grupos del nuevo periodo creada en lote.

---

### [PR-073] - Validar Cruces Horarios de Docente en Múltiples Grupos e Instituciones
- **Historias de Usuario que satisface:** HU034 (Validar consistencia horaria).
- **Propósito de Negocio:** Procedimiento de diagnóstico atómico que escanea todas las asignaciones horarias de un profesor en la universidad para certificar que no tenga traslapes de horas.
- **Entidades del MER Involucradas:** `Docente`, `Grupo`, `Horario`, `Dia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar todas las tuplas de `Horario` donde el docente sea titular en grupos activos.
  2. Evaluar colisiones en la fórmula `(horaInicioA < horaFinB) AND (horaFinA > horaInicioB)` para el mismo `Dia`.
  3. Retornar `estado = 1` si está libre o `estado = 0` con el detalle de los grupos en conflicto.
- **Reglas de Negocio y Validaciones Específicas:**
  * Función reactiva de validación previa consumida por `PR-062` y `PR-063`.
- **Estado Resultante en la BD:** Resultado de validación sin efectos secundarios de modificación.

---

### [PR-086] - Cierre Definitivo de Grupo Académico al Concluir el Periodo
- **Historias de Usuario que satisface:** HU044.
- **Propósito de Negocio:** Concluir las actividades de un grupo, deshabilitando cualquier modificación a su plantilla y asistencias.
- **Entidades del MER Involucradas:** `Grupo`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que todas las `Sesion` del grupo estén en estado cerrado.
  2. Actualizar `estado = 0` o "FINALIZADO" en `Grupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Congela las planillas de asistencia para consulta histórica.
- **Estado Resultante en la BD:** Grupo finalizado.

---

### [PR-092] - Matrícula Reactiva de Estudiante en Grupo con Validación de Asignaturas y Plan de Estudios, Cupos y Cruces Horarios
- **Historias de Usuario que satisface:** HU053 (Inscripción de estudiantes en grupo), HU026, HU034.
- **Propósito de Negocio:** Inscribir a un estudiante en una asignatura/grupo específica. Valida atómicamente el cupo disponible, la vigencia del grupo, los prerrequisitos de la asignatura y que el alumno no tenga colisión de horario con otras materias matriculadas.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Grupo`, `Estudiante`, `EstadoEstudianteGrupo`, `Horario`, `Asignatura`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `Grupo` esté activo y con `cupoMaximo` disponible.
  2. Validar que el estudiante no esté ya matriculado en el mismo grupo o en otro grupo de la misma asignatura en el mismo periodo.
  3. Verificar el pertenencia de la `Asignatura` al `PlanEstudio` del estudiante.
  4. Verificar ausencia de cruce horario con sus otros grupos matriculados en el periodo.
  5. Obtener el `idEstadoEstudianteGrupo` correspondiente a "MATRICULADO / ACTIVO".
  6. Insertar en `EstudianteGrupo` (`estudiante`, `grupo`, `estadoEstudianteGrupo`, `estado = 1`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Si el cupo está agotado o existe cruce horario, rechaza la transacción informando el motivo técnico.
- **Estado Resultante en la BD:** Tupla creada en `EstudianteGrupo` con estado activo.

---

### [PR-093] - Matrícula Masiva por Lote de Estudiantes en Lista de Clases
- **Historias de Usuario que satisface:** HU053.
- **Propósito de Negocio:** Procesar masivamente el listado de alumnos para una sección antes del inicio de clases (ej. carga de archivo plano de admisiones).
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Grupo`, `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir lista de estudiantes y el `idGrupo`.
  2. Por cada estudiante en el lote:
     * Ejecutar la lógica atómica de `PR-092`.
  3. Retornar el número de alumnos inscritos exitosamente y la lista de rechazados con causa.
- **Reglas de Negocio y Validaciones Específicas:**
  * La transacción evalúa el cupo máximo restante por cada iteración.
- **Estado Resultante en la BD:** Grupo poblado con su plantilla de estudiantes.

---

### [PR-094] - Cambio de Estado de Estudiante en Grupo (Activo, Retirado, Cancelado por Ausentismo)
- **Historias de Usuario que satisface:** HU004 (Ver estado de estudiante en grupo).
- **Propósito de Negocio:** Actualizar la condición administrativa de un estudiante dentro de un grupo (ej. cambiar de "MATRICULADO" a "RETIRADO_DISCIPLINARIO" o "CANCELADO_AUSENTISMO").
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `EstadoEstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idEstadoEstudianteGrupo` exista en el catálogo de referencia.
  2. Actualizar el campo `estadoEstudianteGrupo` en la entidad `EstudianteGrupo`.
  3. Registrar la fecha y usuario responsable de la mutación de estado.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si el estado cambia a cancelado o retirado, se libera el cupo reservado para el grupo.
- **Estado Resultante en la BD:** Campo `estadoEstudianteGrupo` actualizado atómicamente.

---

### [PR-095] - Cancelación de Matrícula de Estudiante en Grupo por Solicitud Voluntaria
- **Historias de Usuario que satisface:** HU026, HU051.
- **Propósito de Negocio:** Procesar el retiro voluntario de una materia por parte del alumno dentro de las fechas límites permitidas por el reglamento académico.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `EstadoEstudianteGrupo`, `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la solicitud esté dentro de la fecha límite de retiros de asignaturas.
  2. Actualizar el estado en `EstudianteGrupo` a "CANCELADO_VOLUNTARIO".
  3. Liberar la vacante en la capacidad del `Grupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Conserva las asistencias previamente registradas para fines de historial académico.
- **Estado Resultante en la BD:** Estudiante retirado del grupo y cupo disponible.

---

### [PR-096] - Cancelación Automática de Matrícula en Grupo por Exceso de Inasistencias
- **Historias de Usuario que satisface:** HU013, HU096.
- **Propósito de Negocio:** Aplicar la norma reglamentaria de pérdida de materia por faltas. Cuando el porcentaje de inasistencias supera el límite (ej. 20%), el procedimiento cancela automáticamente la matrícula.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Asistencia`, `EstadoEstudianteGrupo`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Calcular el % de faltas sobre el total de sesiones programadas o dictadas.
  2. Verificar si supera el umbral parametrizado en la institución (`PR-050`).
  3. Si lo supera, actualizar el estado en `EstudianteGrupo` a "CANCELADO_POR_INASISTENCIA".
  4. Generar la notificación oficial para el estudiante y la coordinación.
- **Reglas de Negocio y Validaciones Específicas:**
  * Procedimiento atómico invocado al cerrar sesiones (`PR-124`) o por ejecutor programado.
- **Estado Resultante en la BD:** Matrícula cancelada automáticamente con causal de ausentismo.

---

### [PR-099] - Rechazo de Solicitud de Inscripción de Estudiante con Notificación y Liberación de Cupo
- **Historias de Usuario que satisface:** HU054 (Rechazar solicitud para unirse a grupo).
- **Propósito de Negocio:** Rechazar formalmente una petición de ingreso a un grupo con sobre-demanda.
- **Entidades del MER Involucradas:** `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Actualizar la solicitud a estado "RECHAZADA".
  2. Notificar al estudiante la causa de no aceptación.
- **Reglas de Negocio y Validaciones Específicas:**
  * No genera ningún registro de asistencia ni reserva en el grupo.
- **Estado Resultante en la BD:** Solicitud rechazada.

---

### [PR-100] - Inactivación de Estudiante en Programa Académico por Retiro Definitivo o Graduación
- **Historias de Usuario que satisface:** HU051, HU100.
- **Propósito de Negocio:** Dar de baja la vinculación de un alumno con su programa académico por graduación o deserción formal.
- **Entidades del MER Involucradas:** `EstudiantePrograma`, `Programa`, `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Actualizar `estado = 0` en `EstudiantePrograma`.
  2. Inactivar o cerrar las matrículas activas en `EstudianteGrupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Registra el motivo oficial de la desvinculación.
- **Estado Resultante en la BD:** Estudiante desvinculado del programa.

---

### [PR-101] - Reincorporación/Reingreso de Estudiante a Programa Académico
- **Historias de Usuario que satisface:** HU051.
- **Propósito de Negocio:** Reactivar la ficha académica de un estudiante que vuelve a la universidad tras un periodo de retiro.
- **Entidades del MER Involucradas:** `EstudiantePrograma`, `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el estudiante tenga historial previo en `EstudiantePrograma`.
  2. Reactivar `estado = 1` en `EstudiantePrograma`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Habilita al estudiante para matricular nuevos grupos en el periodo vigente.
- **Estado Resultante en la BD:** Ficha académica reincorporada.

---

### [PR-103] - Registro de Estudiante en Plan de Estudio Específico
- **Historias de Usuario que satisface:** HU019, HU051.
- **Propósito de Negocio:** Asignar la versión exacta de la malla curricular (`PlanEstudio`) a un estudiante dentro de su programa.
- **Entidades del MER Involucradas:** `EstudiantePrograma`, `PlanEstudio`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `PlanEstudio` pertenezca al `Programa`.
  2. Asignar la referencia del plan en la ficha del estudiante.
- **Reglas de Negocio y Validaciones Específicas:**
  * Determina cuáles asignaturas son obligatorias para la graduación del alumno.
- **Estado Resultante en la BD:** Plan de estudio asignado al alumno.

---

### [PR-106] - Enrolamiento Directo por Archivo Masivo CSV/Excel de Estudiantes en Grupos
- **Historias de Usuario que satisface:** HU053, HU050.
- **Propósito de Negocio:** Importar la lista definitiva de matriculados enviada por la oficina de registro académico.
- **Entidades del MER Involucradas:** `Usuario`, `Estudiante`, `EstudianteGrupo`, `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Procesar el archivo masivo creando usuarios nuevos si no existen.
  2. Registrar matrículas en `EstudianteGrupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Operación batch que omite duplicados y genera reporte de consistencia.
- **Estado Resultante en la BD:** Enrolamiento masivo completado.

---

### [PR-113] - Bloqueo Administrativo de Matrícula de Estudiante en Grupos
- **Historias de Usuario que satisface:** HU051.
- **Propósito de Negocio:** Bloquear la facultad de un estudiante para inscribir nuevas materias por sanción disciplinaria o mora.
- **Entidades del MER Involucradas:** `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Activar la bandera de bloqueo administrativo en la entidad `Estudiante`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Rechaza cualquier invocación de `PR-092` por parte del estudiante.
- **Estado Resultante en la BD:** Estudiante bloqueado administrativamente.

---

### [PR-114] - Desbloqueo Administrativo de Matrícula de Estudiante
- **Historias de Usuario que satisface:** HU051.
- **Propósito de Negocio:** Retirar la sanción administrativa permitiendo al alumno matricularse nuevamente.
- **Entidades del MER Involucradas:** `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Desactivar la bandera de bloqueo en `Estudiante`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Restablece inmediatamente sus permisos en el portal.
- **Estado Resultante en la BD:** Estudiante habilitado.

---

### [PR-122] - Toma de Asistencia Masiva por Lote en Sesión por el Docente
- **Historias de Usuario que satisface:** HU027 (Registrar asistencia), HU029, HU033.
- **Propósito de Negocio:** Guardar en un solo envío atómico desde la app toda la lista de clase con los estados de asistencia asignados a cada estudiante (Asistió, Faltó, Tarde).
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `EstudianteGrupo`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Sesion` esté activa y pertenezca al docente en sesión.
  2. Recibir la colección de pares `(idEstudianteGrupo, idEstadoAsistencia)`.
  3. Por cada elemento del lote:
     * Validar que el `EstudianteGrupo` pertenezca al grupo de la sesión.
     * Evaluar si ya existe registro en `Asistencia`:
       * **Si NO existe:** Insertar nueva tupla en `Asistencia` (`estudianteGrupo`, `sesion`, `fechaHora`, `estado`).
       * **Si YA existe:** Actualizar el `estado` en `Asistencia`.
  4. Retornar el resumen de procesados.
- **Reglas de Negocio y Validaciones Específicas:**
  * Transacción atómica integral: si un `idEstudianteGrupo` es inválido, aborta la operación completa para garantizar consistencia.
- **Estado Resultante en la BD:** Registros creados o actualizados en `Asistencia` para toda la plantilla.

---

### [PR-123] - Registro de Asistencia Autónoma por Estudiante mediante QR/Token Dinámico
- **Historias de Usuario que satisface:** HU027 (Auto-registro de asistencia estudiante), HU053.
- **Propósito de Negocio:** Permitir que el estudiante escanee el QR dinámico o ingrese el token de clase en su celular para registrar de forma autónoma su asistencia a la sesión activa.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `EstudianteGrupo`, `Estudiante`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el token dinámico de la `Sesion` sea válido y no haya expirado.
  2. Identificar la matrícula activa del alumno en `EstudianteGrupo` para el grupo de la sesión.
  3. Verificar que no exista ya un marcaje de asistencia para este estudiante en esta sesión.
  4. Comparar `fechaHora` actual con la hora de inicio de la sesión:
     * Si está dentro de la tolerancia de tiempo (ej. 10 min), registrar con `Estado = ASISTIO`.
     * Si supera la tolerancia pero está dentro del margen de retardo, registrar con `Estado = TARDE`.
  5. Insertar la tupla en `Asistencia`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Valida la geolocalización o IP si el parámetro institucional de presencia está activo.
- **Estado Resultante en la BD:** Registro individual en `Asistencia` creado autónomamente.

---

### [PR-125] - Modificación Atómica de Registro de Asistencia de un Estudiante en Sesión Específica
- **Historias de Usuario que satisface:** HU033 (Modificar asistencia tomada), HU027.
- **Propósito de Negocio:** Permitir al docente corregir de forma individual la asistencia de un alumno (ej. cambiar de "FALTA" a "ASISTIO" o "JUSTIFICADA") tras verificar su presencia.
- **Entidades del MER Involucradas:** `Asistencia`, `Estado`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia de la tupla en `Asistencia`.
  2. Verificar que la fecha de la sesión no supere el límite reglamentario de edición (ej. máximo 8 días).
  3. Actualizar el campo `estado` en la entidad `Asistencia`.
  4. Recalcular el % de ausentismo acumulado del estudiante.
- **Reglas de Negocio y Validaciones Específicas:**
  * Registra en la auditoría el usuario y la justificación del cambio de estado.
- **Estado Resultante en la BD:** Registro en `Asistencia` corregido y ausentismo recalculado.

---

### [PR-126] - Cancelación de Sesión de Clase Programada con Notificación a Estudiantes
- **Historias de Usuario que satisface:** HU047 (Cancelar sesión).
- **Propósito de Negocio:** Marcar una sesión como cancelada (ej. por calamidad del docente o suspensión institucional), evitando que compute como falta para los estudiantes.
- **Entidades del MER Involucradas:** `Sesion`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Sesion` no haya concluido.
  2. Actualizar el estado en `Sesion` a "CANCELADA".
  3. Si existían registros de asistencia parciales, actualizarlos o inactivarlos.
  4. Emite evento de notificación para la App de los estudiantes.
- **Reglas de Negocio y Validaciones Específicas:**
  * Una sesión cancelada no afecta negativamente el porcentaje de asistencias requeridas del curso.
- **Estado Resultante en la BD:** `Sesion` marcada como cancelada.

---

### [PR-127] - Reprogramación de Sesión Cancelada en Nueva Fecha/Hora sin Cruces Horarios
- **Historias de Usuario que satisface:** HU045, HU046.
- **Propósito de Negocio:** Agendar la reposición de una clase cancelada en una nueva fecha/hora, verificando previamente la disponibilidad del docente y del aula.
- **Entidades del MER Involucradas:** `Sesion`, `Grupo`, `Docente`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la nueva fecha y horas no generen colisión para el docente (`PR-073`).
  2. Actualizar `fechaHoraInicio` y `fechaHoraFin` en la tupla de `Sesion`.
  3. Reabrir la sesión en estado "REPROGRAMADA / ABIERTA".
- **Reglas de Negocio y Validaciones Específicas:**
  * Requiere confirmación de disponibilidad enviada a los alumnos del grupo.
- **Estado Resultante en la BD:** Clase de reposición reprogramada en el calendario.

---

### [PR-129] - Toma de Asistencia por Escaneo Masivo de Código de Estudiante (Barcode/NFC)
- **Historias de Usuario que satisface:** HU027.
- **Propósito de Negocio:** Permitir que el docente escanee rápidamente con el carné de los estudiantes (código de barras o NFC) para registrar la asistencia en tiempo real.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `Usuario`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir el número de documento escaneado y el `idSesion`.
  2. Localizar la matrícula activa en `EstudianteGrupo`.
  3. Insertar/Actualizar la asistencia con `Estado = ASISTIO`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Emite respuesta sonora/visual en la app cliente por cada carné escaneado exitosamente.
- **Estado Resultante en la BD:** Registro de asistencia individual creado por escaneo.

---

### [PR-130] - Corrección Lote de Asistencia en Sesión por Error del Docente en el Llamado
- **Historias de Usuario que satisface:** HU033.
- **Propósito de Negocio:** Permitir re-enviar la plantilla completa de asistencia de una sesión previa para sobrescribir errores de marcaje cometidos por el docente.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Sesion` no haya sido cerrada formalmente por la coordinación.
  2. Recibir la plantilla corregida.
  3. Sobrescribir los estados de `Asistencia` en una sola transacción atómica.
- **Reglas de Negocio y Validaciones Específicas:**
  * Guarda la traza en auditoría con la versión anterior y la nueva versión de la plantilla.
- **Estado Resultante en la BD:** Plantilla de asistencia en la sesión corregida.

---

### [PR-132] - Consolidar Cierre Automático Nocturno de Sesiones Olvidadas Abiertas por Docentes
- **Historias de Usuario que satisface:** HU028, Configuración Ecosistema.
- **Propósito de Negocio:** Proceso batch automático ejecutado a medianoche. Detecta sesiones que quedaron en estado "ABIERTA" por olvido del docente, marcando las inasistencias omitidas y cerrándolas de forma segura.
- **Entidades del MER Involucradas:** `Sesion`, `Asistencia`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar todas las `Sesion` con `fechaHoraFin < NOW()` que permanezcan en estado abierto.
  2. Ejecutar la lógica de cierre automático (`PR-124`) para cada una.
  3. Registrar la traza en la bitácora del sistema.
- **Reglas de Negocio y Validaciones Específicas:**
  * Envía un correo recordatorio al docente notificando el cierre automático de la sesión.
- **Estado Resultante en la BD:** Sesiones olvidadas cerradas de forma atómica.

---

### [PR-134] - Consulta de Plantilla de Asistencia en Tiempo Real para Sesión Activa
- **Historias de Usuario que satisface:** HU029 (Consultar listado de asistencia de sesión).
- **Propósito de Negocio:** Retornar al dispositivo del docente el estado actual de la toma de lista de la sesión en curso (cuántos asistieron, cuántos faltan y cuántos han marcado por QR).
- **Entidades del MER Involucradas:** `Sesion`, `Asistencia`, `EstudianteGrupo`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar los estudiantes matriculados en el grupo.
  2. Hacer `LEFT JOIN` con la tabla `Asistencia` para la `Sesion` indicada.
  3. Retornar el listado completo consolidado.
- **Reglas de Negocio y Validaciones Específicas:**
  * Lectura optimizada para alta concurrencia durante la toma de lista.
- **Estado Resultante en la BD:** Plantilla consolidada retornada al cliente.

---

### [PR-136] - Bloqueo de Edición de Asistencia en Sesiones con Fecha Mayor a Límite Reglamentario
- **Historias de Usuario que satisface:** HU033.
- **Propósito de Negocio:** Impedir que un docente modifique planillas de asistencia de clases dictadas hace más de 8 o 15 días, exigiendo solicitud de desbloqueo al coordinador (`PR-137`).
- **Entidades del MER Involucradas:** `Sesion`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Evaluar la diferencia en días entre la fecha de la sesión y la fecha actual.
  2. Si `diferencia_dias > parametro_dias_limite`, bloquear la actualización y retornar mensaje de restricción.
- **Reglas de Negocio y Validaciones Específicas:**
  * Garantiza la estabilidad de las planillas de asistencia para evitar manipulaciones extemporáneas.
- **Estado Resultante en la BD:** Intento de edición bloqueado por vencimiento reglamentario.

---

### [PR-139] - Generación de Token Dinámico / Código QR Temporal para Sesión por el Docente
- **Historias de Usuario que satisface:** HU028.
- **Propósito de Negocio:** Generar la clave encriptada/QR que cambia cada 30 segundos y que se proyecta en el aula para que los estudiantes registren su presencia.
- **Entidades del MER Involucradas:** `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Sesion` esté activa.
  2. Generar el token temporal con algoritmo hash y timestamp.
  3. Actualizar la semilla del token en la entidad `Sesion`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Impide la captura remota del QR por estudiantes que no están físicamente en el aula.
- **Estado Resultante en la BD:** Token dinámico de sesión activo.

---

### [PR-140] - Validación de Token Dinámico de Asistencia y Expulsión por Token Vencido
- **Historias de Usuario que satisface:** HU027.
- **Propósito de Negocio:** Verificar la autenticidad del token enviado por el celular del estudiante al hacer marcaje autónomo (`PR-123`).
- **Entidades del MER Involucradas:** `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar el token recibido contra la semilla activa de la `Sesion`.
  2. Si el token expiró, retornar error de token inválido y denegar el registro.
- **Reglas de Negocio y Validaciones Específicas:**
  * Función de seguridad previa a la inserción en `Asistencia`.
- **Estado Resultante en la BD:** Diagnóstico de seguridad de token.

---

### [PR-141] - Registro de Asistencia en Modalidad Virtual / Remota con Enlace de Conexión
- **Historias de Usuario que satisface:** HU027.
- **Propósito de Negocio:** Registrar el ingreso y tiempo de permanencia de estudiantes en clases dictadas a través de plataformas virtuales (Teams, Zoom).
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir los logs de conexión virtual de la sesión.
  2. Mapear usuarios con `EstudianteGrupo` e insertar asistencias.
- **Reglas de Negocio y Validaciones Específicas:**
  * Exige un porcentaje mínimo de permanencia en la llamada (ej. 70% de la clase) para marcar `ASISTIO`.
- **Estado Resultante en la BD:** Asistencias virtuales registradas.

---

### [PR-143] - Marcaje de Asistencia Grupal Total por Evento Institucional / Salida de Campo
- **Historias de Usuario que satisface:** HU027, HU028.
- **Propósito de Negocio:** Marcar atómicamente a TODO el grupo como "ASISTIO_EVENTO_INSTITUCIONAL" por actividades académicas autorizadas fuera del campus.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la autorización del evento para el `Grupo`.
  2. Registrar para la totalidad de la plantilla de `EstudianteGrupo` la asistencia institucional.
  3. Cerrar la `Sesion`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Exime individualmente el marcaje sin requerir llamada de lista uno a uno.
- **Estado Resultante en la BD:** Asistencia masiva de evento registrada.

---

### [PR-145] - Verificación de Integridad entre `Sesion`, `EstudianteGrupo` y `Asistencia`
- **Historias de Usuario que satisface:** Configuración Ecosistema.
- **Propósito de Negocio:** Procedimiento reactivo de mantenimiento que detecta asistencias registradas para estudiantes desvinculados o sesiones inconsistentes.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Escanear incoherencias en las llaves foráneas y fechas de `Asistencia`.
  2. Marcar registros anómalos para revisión técnica.
- **Reglas de Negocio y Validaciones Específicas:**
  * Diagnóstico sin pérdida de datos.
- **Estado Resultante en la BD:** Reporte de consistencia de asistencias.

---

### [PR-146] - Re-apertura de Sesión Cerrada para Inclusión de Estudiante Extemporáneo
- **Historias de Usuario que satisface:** HU028, HU053.
- **Propósito de Negocio:** Reabrir temporalmente una sesión concluida para agregar la asistencia de un alumno matriculado tardíamente.
- **Entidades del MER Involucradas:** `Sesion`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Cambiar el estado de la `Sesion` a "REABIERTA_TEMPORAL".
  2. Insertar el marcaje del estudiante tardío.
  3. Re-cerrar la `Sesion` (`PR-124`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Registra la causa justificada en la bitácora de auditoría.
- **Estado Resultante en la BD:** Asistencia de alumno extemporáneo incluida.

---

### [PR-148] - Reporte Reactivo de Faltas Consecutivas en el Transcurso de las Sesiones
- **Historias de Usuario que satisface:** HU013, HU066.
- **Propósito de Negocio:** Detectar cuando un estudiante acumula 3 o más faltas consecutivas en las últimas sesiones del grupo para alerta temprana de deserción.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Analizar la secuencia temporal de registros en `Asistencia` para el estudiante.
  2. Si se detectan N inasistencias seguidas sin justificar, emitir la alerta a bienestar universitario.
- **Reglas de Negocio y Validaciones Específicas:**
  * Diagnóstico automático en tiempo real.
- **Estado Resultante en la BD:** Alerta de faltas consecutivas generada.

---

### [PR-149] - Notificación Push / Correo Inmediata al Estudiante por Inasistencia Registrada
- **Historias de Usuario que satisface:** HU001, HU013.
- **Propósito de Negocio:** Notificar al instante al estudiante en su celular cada vez que un profesor le marca una falta o llegada tarde en clase.
- **Entidades del MER Involucradas:** `Asistencia`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Al insertar en `Asistencia` una tupla con estado "FALTA" o "TARDE", disparar el evento de mensajería.
  2. Construir y enviar la notificación con fecha, materia y profesor.
- **Reglas de Negocio y Validaciones Específicas:**
  * Permite al alumno reaccionar a tiempo y solicitar revisión si hubo un error (`PR-151`).
- **Estado Resultante en la BD:** Evento de notificación emitido.

---

---

### [PR-152] - Resolver Solicitud de Justificación por el Docente (Aprobación/Rechazo + Cambio Atómico en `Asistencia`)
- **Historias de Usuario que satisface:** HU035 (Ver solicitudes de revisión pendientes), HU037 (Aprobar/Rechazar justificaciones).
- **Propósito de Negocio:** Permite al profesor evaluar la solicitud del alumno. Si se aprueba, la transacción actualiza atómicamente la solicitud a "APROBADA" y modifica el campo `estado` en `Asistencia` a "JUSTIFICADA", recalculando el porcentaje de faltas acumuladas en un solo paso.
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`, `Asistencia`, `Estado`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `SolicitudRevisionAsistencia` esté en estado "PENDIENTE_REVISION".
  2. Validar que el docente que resuelve sea el titular o suplente del `Grupo`.
  3. Recibir la decisión ("APROBADA" o "RECHAZADA") y comentario del docente.
  4. Actualizar el estado en `SolicitudRevisionAsistencia`.
  5. **Si la decisión es APROBADA:**
     * Actualizar la tupla en `Asistencia` asignando el estado "JUSTIFICADA".
     * Recalcular el porcentaje de ausentismo acumulado en `EstudianteGrupo`.
  6. Notificar la decisión al estudiante.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si la justificación es aprobada, la falta justificada deja de sumar negativamente hacia el límite reglamentario de cancelación de materia.
- **Estado Resultante en la BD:** Solicitud resuelta y estado en `Asistencia` actualizado atómicamente.

---

### [PR-154] - Cancelación de Solicitud de Revisión por el Estudiante antes de ser Evaluada
- **Historias de Usuario que satisface:** HU010.
- **Propósito de Negocio:** Permitir que el estudiante retire voluntariamente su solicitud de revisión si la radicó por error o con datos incorrectos.
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `SolicitudRevisionAsistencia` esté en estado "PENDIENTE_REVISION" y pertenezca al estudiante.
  2. Actualizar el estado a "CANCELADA_POR_ESTUDIANTE".
- **Reglas de Negocio y Validaciones Específicas:**
  * No se puede cancelar una solicitud que ya ha sido APROBADA o RECHAZADA por el docente.
- **Estado Resultante en la BD:** Solicitud marcada como cancelada.

---

### [PR-155] - Generación de Alerta Temprana de Ausentismo Crítico al Superar Umbral
- **Historias de Usuario que satisface:** HU013 (Recibir alertas de ausentismo), HU066.
- **Propósito de Negocio:** Disparar de forma reactiva una alerta visual y por correo cuando el % de inasistencias de un alumno alcanza el 15% (Advertencia) o el 20% (Pérdida por inasistencias).
- **Entidades del MER Involucradas:** `Asistencia`, `EstudianteGrupo`, `Grupo`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Calcular la suma de faltas no justificadas del estudiante en la materia sobre el total de clases del periodo.
  2. Si `%_faltas >= 15%` y no existía alerta activa, generar el registro de alerta temprana.
  3. Enviar notificación push al estudiante y correo al docente/coordinador.
- **Reglas de Negocio y Validaciones Específicas:**
  * Función de evaluación automática ejecutada tras cada marcaje o resolución de justificación.
- **Estado Resultante en la BD:** Alerta temprana registrada y emitida.

---

### [PR-156] - Envío de Notificación Consolidada a Coordinación por Estudiantes en Riesgo
- **Historias de Usuario que satisface:** HU066, HU013.
- **Propósito de Negocio:** Generar un reporte periódico automático para la coordinación con la lista de alumnos que superaron el umbral crítico de faltas en cualquier asignatura de la facultad.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Grupo`, `Programa`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar todos los `EstudianteGrupo` con alerta activa de ausentismo.
  2. Agrupar por programa académico.
  3. Enviar el paquete consolidado de alertas al correo del `Coordinador`.
- **Reglas de Negocio and Validaciones Específicas:**
  * Facilita la intervención temprana de bienestar universitario.
- **Estado Resultante en la BD:** Traza de reporte de alerta enviado.

---

### [PR-157] - Emisión de Certificado Oficial de Porcentaje de Asistencia por Asignatura
- **Historias de Usuario que satisface:** HU001, HU002.
- **Propósito de Negocio:** Generar el reporte oficial en PDF/XML de asistencias acumuladas de un estudiante para trámites de becas o patrocinios institucionales.
- **Entidades del MER Involucradas:** `Estudiante`, `EstudianteGrupo`, `Asistencia`, `Grupo`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar todas las `Sesion` ejecutadas del grupo y los registros correspondientes en `Asistencia`.
  2. Calcular: Total Clases Dictadas, Asistencias, Faltas Justificadas, Faltas No Justificadas, Retardos y % Definitivo.
  3. Retornar el certificado firmado digitalmente.
- **Reglas de Negocio y Validaciones Específicas:**
  * Certificado atómico inmutable para trámites externos.
- **Estado Resultante en la BD:** Documento de certificación generado.

---

### [PR-158] - Registro de Razón / Causa de Inasistencia Institucional (Mantenimiento de Catálogo)
- **Historias de Usuario que satisface:** HU005, HU016, HU042.
- **Propósito de Negocio:** Dar de alta o actualizar las opciones del catálogo `RazonCausa` (ej. "Incapacidad Médica EPS", "Calamidad Doméstica Comprobada", "Cita Judicial", "Representación Deportiva").
- **Entidades del MER Involucradas:** `RazonCausa`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `codigo` o `nombre` en `RazonCausa` no esté duplicado.
  2. Insertar/Actualizar la tupla (`id`, `codigo`, `nombre`, `estado = 1`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Catálogo global utilizado en las pantallas de justificación de estudiantes y docentes.
- **Estado Resultante en la BD:** Opción registrada en `RazonCausa`.

---

### [PR-159] - Consulta Consolidada de Histórico de Asistencias del Estudiante (`uv_asistencia`)
- **Historias de Usuario que satisface:** HU001 (Ver detalles de inasistencias), HU002 (Consultar histórico).
- **Propósito de Negocio:** Retornar en una vista/procedimiento de lectura ultra-rápida todo el expediente de asistencias del estudiante a lo largo de su carrera.
- **Entidades del MER Involucradas:** `Asistencia`, `EstudianteGrupo`, `Sesion`, `Grupo`, `Asignatura`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Ejecutar consulta sobre la vista optimizada `uv_asistencia` filtrando por `idEstudiante`.
  2. Formatear desglose por materia, periodo, fecha de clase y estado.
  3. Retornar la respuesta al cliente app.
- **Reglas de Negocio y Validaciones Específicas:**
  * Lectura optimizada mediante índices covering en `Asistencia`.
- **Estado Resultante en la BD:** Histórico retornado al cliente.

---

### [PR-160] - Consulta Consolidada de Estadísticas de Asistencia por Grupo (`uv_estadistica_grupo`)
- **Historias de Usuario que satisface:** HU060, HU066.
- **Propósito de Negocio:** Retornar a la coordinación el resumen estadístico de un grupo (% de asistencia promedio, número de estudiantes en riesgo, total de clases dictadas).
- **Entidades del MER Involucradas:** `Grupo`, `Sesion`, `Asistencia`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar la vista `uv_estadistica_grupo` filtrando por `idGrupo`.
  2. Retornar indicadores clave KPI del grupo.
- **Reglas de Negocio y Validaciones Específicas:**
  * Utilizado por docentes y coordinadores en su panel de mando.
- **Estado Resultante en la BD:** Indicadores KPI del grupo retornados.

---

### [PR-161] - Generación de Reporte Macro de Deserción y Ausentismo para Decanatura por Facultad
- **Historias de Usuario que satisface:** HU102 (Reportes macro decanatura).
- **Propósito de Negocio:** Consolidar métricas a nivel gerencial para el Decano, mostrando los programas académicos y materias con mayor índice de inasistencias en la Facultad.
- **Entidades del MER Involucradas:** `Facultad`, `Programa`, `Grupo`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Agrupar la totalidad de asistencias y faltas del periodo lectivo por `Programa` y `Facultad`.
  2. Generar ranking de ausentismo y proyección de pérdida de asignaturas.
- **Reglas de Negocio y Validaciones Específicas:**
  * Consulta atómica agregada de alto nivel.
- **Estado Resultante en la BD:** Reporte macro de decanatura generado.

---

### [PR-163] - Reabrir Solicitud de Revisión Rechazada por Presentación de Nuevo Soporte Oficial
- **Historias de Usuario que satisface:** HU010, HU037.
- **Propósito de Negocio:** Permitir que una solicitud que fue rechazada se reabra si el estudiante presenta una excusa oficial expedida posteriormente por bienestar o secretaría académica.
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la solicitud anterior estuviera en estado "RECHAZADA".
  2. Actualizar el estado a "REABIERTA_PENDIENTE_EVALUACION".
  3. Anexar el nuevo soporte a la observación.
- **Reglas de Negocio y Validaciones Específicas:**
  * Requiere aval del coordinador o decano.
- **Estado Resultante en la BD:** Solicitud reabierta para reconsideración.

---

### [PR-169] - Generación de Indicador KPI de Cumplimiento de Toma de Lista por Docente
- **Historias de Usuario que satisface:** HU060 (Monitorear docentes que no siguen el proceso).
- **Propósito de Negocio:** Calcular el porcentaje de clases en las que cada profesor tomó asistencia a tiempo vs sesiones olvidadas o cerradas por el sistema.
- **Entidades del MER Involucradas:** `Docente`, `Grupo`, `Sesion`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Contar el total de sesiones dictadas por el docente.
  2. Contar cuántas sesiones fueron cerradas con tomadas de lista manual/autónoma a tiempo.
  3. Calcular el KPI de cumplimiento docente y retornar a coordinación.
- **Reglas de Negocio y Validaciones Específicas:**
  * Utilizado para evaluación de desempeño docente.
- **Estado Resultante en la BD:** Indicador KPI de cumplimiento docente calculado.

---

### [PR-170] - Exportación Registros de Asistencia a Formato Oficial de Acta de Notas y Faltas
- **Historias de Usuario que satisface:** HU027, HU029, HU040.
- **Propósito de Negocio:** Consolidar en un solo archivo plano u objeto de salida la lista de estudiantes de un grupo con sus calificaciones y faltas totales al cerrar el semestre.
- **Entidades del MER Involucradas:** `Grupo`, `EstudianteGrupo`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Extraer los matriculados finales del grupo.
  2. Consolidar el total de faltas justificadas, inasistencias y estado final (Aprobó / Reprobó por inasistencias).
  3. Firmar digitalmente la planilla de entrega.
- **Reglas de Negocio y Validaciones Específicas:**
  * Requisito previo para el cierre definitivo de actas.
- **Estado Resultante en la BD:** Acta oficial de asistencia generada.

---

### [PR-171] - Consulta de Solicitudes de Justificación Vencidas Sin Respuesta del Docente
- **Historias de Usuario que satisface:** HU035, HU171.
- **Propósito de Negocio:** Listar aquellas solicitudes de revisión de asistencia que llevan más de 5 días hábiles en estado "PENDIENTE" sin que el docente las haya aprobado o rechazado.
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`, `Grupo`, `Docente`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar la entidad `SolicitudRevisionAsistencia` filtrando por estado "PENDIENTE" y `fechaSolicitud < NOW() - 5_DIAS`.
  2. Retornar el listado a la coordinación de programa.
- **Reglas de Negocio y Validaciones Específicas:**
  * Dispara alerta al docente recordándole responder la solicitud.
- **Estado Resultante en la BD:** Reporte de solicitudes vencidas retornado.

---

### [PR-172] - Aprobación Automática de Justificación por Silencio Administrativo del Docente
- **Historias de Usuario que satisface:** HU010, HU037.
- **Propósito de Negocio:** Aplicar el principio de silencio administrativo positivo. Si un docente no responde una justificación médica en más de 10 días, el sistema aprueba automáticamente la excusa y marca la asistencia como "JUSTIFICADA".
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`, `Asistencia`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Buscar solicitudes pendientes con más de 10 días de antigüedad.
  2. Ejecutar la aprobación automática (`PR-152`) registrando la causal "APROBADO_POR_SILENCIO_ADMINISTRATIVO".
  3. Actualizar la tupla en `Asistencia` a "JUSTIFICADA".
- **Reglas de Negocio y Validaciones Específicas:**
  * Protege al estudiante ante la inacción o negligencia del profesor.
- **Estado Resultante en la BD:** Justificación aprobada por silencio administrativo.

---

### [PR-175] - Consolidación de Histórico Académico de Asistencias para Proceso de Graduación
- **Historias de Usuario que satisface:** HU002.
- **Propósito de Negocio:** Certificar que un estudiante candidato a grado cumplió con el requisito institucional de porcentaje mínimo de asistencia en todas las asignaturas de su plan de estudio.
- **Entidades del MER Involucradas:** `Estudiante`, `EstudiantePrograma`, `EstudianteGrupo`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Verificar todas las asignaturas del plan de estudio cursadas por el alumno.
  2. Certificar que ninguna asignatura tenga estado de reprobación por inasistencia.
  3. Emitir el aval de asistencia para el expediente de graduación.
- **Reglas de Negocio y Validaciones Específicas:**
  * Requisito indispensable para el paz y salvo de graduación.
- **Estado Resultante en la BD:** Aval de asistencia para grado emitido.

---

### [PR-179] - Respaldar y Archivar Registros de Asistencia de Periodos Académicos Históricos
- **Historias de Usuario que satisface:** Mantenimiento y Rendimiento BD.
- **Propósito de Negocio:** Mover registros de `Asistencia` y `Sesion` de hace más de 5 años a tablas de archivo histórico para optimizar la velocidad y el tamaño de las tablas operativas principales.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `PeriodoAcademico`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Identificar periodos académicos concluidos hace más de 5 años.
  2. Transferir atómicamente sus tuplas a las tablas de archivo histórico (`Asistencia_Historico`).
  3. Purgar los registros de la tabla operativa principal sin perder la capacidad de consulta agregada.
- **Reglas de Negocio y Validaciones Específicas:**
  * Operación de mantenimiento nocturna que preserva el 100% de la integridad referencial.
- **Estado Resultante en la BD:** Tablas de producción optimizadas y registros antiguos archivados.

---
