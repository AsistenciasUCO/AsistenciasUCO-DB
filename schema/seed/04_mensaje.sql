USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente Completo: Catálogo de Mensajes de Usuario (CatalogoMensajeUsuario)
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    -- Correlación y Transacción
    ('CORR_001', 'BUSINESS_ERROR', 'ALTO', 'El identificador de correlación no está presente o está vacío.'),
    ('ERR_CORRELACION_REQUERIDA', 'BUSINESS_ERROR', 'ALTO', 'El codigo de correlacion es requerido.'),

    -- Plantillas Generales Dinámicas ({})
    ('GEN_001', 'BUSINESS_ERROR', 'MEDIO', 'El {} especificado no existe en el sistema.'),
    ('GEN_002', 'BUSINESS_ERROR', 'MEDIO', 'El {} no puede estar vacío o no está presente.'),
    ('GEN_003', 'BUSINESS_ERROR', 'ALTO', 'Ya existe un {} registrado con este {}.'),
    ('GEN_004', 'SUCCESS', 'BAJO', '{} registrado(a) exitosamente.'),
    ('GEN_005', 'SUCCESS', 'BAJO', '{} actualizado(a) exitosamente.'),

    -- Validaciones Biográficas y Formato
    ('VAL_001', 'BUSINESS_ERROR', 'MEDIO', 'El número de identificación es obligatorio.'),
    ('VAL_002', 'BUSINESS_ERROR', 'MEDIO', 'El número de identificación debe tener entre {} y {} dígitos.'),
    ('VAL_003', 'BUSINESS_ERROR', 'MEDIO', 'Los nombres y apellidos son obligatorios.'),
    ('VAL_004', 'BUSINESS_ERROR', 'MEDIO', 'El campo {} contiene caracteres no permitidos.'),
    ('VAL_005', 'BUSINESS_ERROR', 'MEDIO', 'El correo electrónico es obligatorio y debe tener un formato válido.'),
    ('VAL_006', 'BUSINESS_ERROR', 'ALTO', 'La dirección de correo electrónico ya se encuentra registrada.'),
    ('VAL_007', 'BUSINESS_ERROR', 'ALTO', 'La contraseña no cumple con los requisitos mínimos de seguridad.'),

    -- Entidades del Sistema
    ('USU_001', 'BUSINESS_ERROR', 'MEDIO', 'El usuario especificado no existe en el sistema.'),
    ('ERR_USUARIO_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', 'El usuario especificado no existe.'),
    ('USU_002', 'BUSINESS_ERROR', 'ALTO', 'El usuario especificado se encuentra inactivo en la plataforma.'),
    ('ERR_UNICIDAD_CORREO', 'BUSINESS_ERROR', 'ALTO', 'El correo electronico ya se encuentra registrado.'),
    ('ERR_UNICIDAD_DOCUMENTO', 'BUSINESS_ERROR', 'ALTO', 'El numero de documento ya esta registrado para este tipo de identificacion.'),

    ('EST_001', 'BUSINESS_ERROR', 'MEDIO', 'El estudiante especificado no existe en el sistema.'),
    ('ERR_ESTUDIANTE_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', 'El estudiante especificado no existe.'),
    ('EST_002', 'BUSINESS_ERROR', 'ALTO', 'El estudiante ya se encuentra matriculado o registrado en este grupo.'),
    ('ERR_MATRICULA_DUPLICADA', 'BUSINESS_ERROR', 'ALTO', 'Usted ya se encuentra registrado o matriculado en este grupo.'),
    ('EST_003', 'BUSINESS_ERROR', 'ALTO', 'El estudiante ya pertenece a este programa académico.'),
    ('EST_004', 'BUSINESS_ERROR', 'ALTO', 'El estudiante no pertenece al grupo de la sesion seleccionada.'),
    ('ERR_ESTUDIANTE_NO_PERTENECE_SESION', 'BUSINESS_ERROR', 'ALTO', 'El estudiante no pertenece al grupo de la sesion seleccionada.'),

    ('DOC_001', 'BUSINESS_ERROR', 'MEDIO', 'El docente especificado no existe o se encuentra inactivo.'),
    ('ERR_DOCENTE_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', 'El docente especificado no existe o esta inactivo.'),
    ('ERR_DOCENTE_NO_TITULAR_GRUPO', 'BUSINESS_ERROR', 'ALTO', 'El docente indicado no es el titular del grupo seleccionado.'),

    ('PROG_001', 'BUSINESS_ERROR', 'ALTO', 'El programa académico especificado no existe en el sistema.'),
    ('ERR_PROGRAMA_GRUPO_NO_ENCONTRADO', 'BUSINESS_ERROR', 'ALTO', 'No se encontro un programa academico asociado a este grupo.'),

    ('GRUP_001', 'BUSINESS_ERROR', 'MEDIO', 'El grupo seleccionado no existe o no se encuentra habilitado.'),
    ('ERR_GRUPO_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', 'El grupo seleccionado no existe o no esta habilitado.'),
    ('ERR_GRUPO_NO_HABILITADO', 'BUSINESS_ERROR', 'MEDIO', 'El grupo seleccionado no se encuentra habilitado para matricula.'),
    ('GRUP_002', 'BUSINESS_ERROR', 'ALTO', 'El grupo ha alcanzado o superado la capacidad máxima de estudiantes permitida.'),
    ('ERR_CUPO_SUPERADO', 'BUSINESS_ERROR', 'ALTO', 'El grupo ha superado la capacidad maxima de estudiantes permitida.'),
    ('ERR_CAPACIDAD_GRUPO_INVALIDA', 'SYSTEM_ERROR', 'CRITICO', 'No fue posible determinar una capacidad máxima válida para el grupo.'),
    ('ERR_CUPO_INFERIOR_OCUPACION', 'BUSINESS_ERROR', 'ALTO', 'La capacidad del grupo no puede ser menor al número actual de estudiantes activos.'),
    ('GRUP_003', 'BUSINESS_ERROR', 'ALTO', 'No se encontró un programa académico asociado a este grupo.'),

    ('HOR_001', 'BUSINESS_ERROR', 'ALTO', 'No es posible realizar el registro. Existe un cruce de horario con otra asignatura.'),
    ('ERR_CRUCE_HORARIO_ESTUDIANTE', 'BUSINESS_ERROR', 'ALTO', 'No es posible realizar el registro. Existe un cruce de horario con otra asignatura.'),
    ('HOR_002', 'BUSINESS_ERROR', 'ALTO', 'Existe un cruce de horario para el docente en la misma franja horaria.'),
    ('ERR_CRUCE_HORARIO_DOCENTE', 'BUSINESS_ERROR', 'ALTO', 'Existe un cruce de horario para el docente en la misma franja horaria.'),

    ('SES_001', 'BUSINESS_ERROR', 'MEDIO', 'La sesión de clase especificada no existe o no se encuentra activa.'),
    ('ERR_SESION_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', 'La sesion de clase no existe o no esta abierta.'),
    ('SES_002', 'BUSINESS_ERROR', 'MEDIO', 'El código de verificación de asistencia es incorrecto o ha expirado.'),
    ('SES_003', 'BUSINESS_ERROR', 'MEDIO', 'El cierre de sesión no está soportado por el contrato vigente de base de datos.'),
    ('SES_004', 'BUSINESS_ERROR', 'MEDIO', 'La fecha y hora de fin de sesión debe ser posterior a la fecha y hora de inicio.'),
    ('ERR_TOKEN_VERIFICACION_INVALIDO', 'BUSINESS_ERROR', 'MEDIO', 'El codigo de verificacion de asistencia es incorrecto o ha expirado.'),

    ('INST_001', 'BUSINESS_ERROR', 'CRITICO', 'El estudiante, programa y facultad deben pertenecer a la misma institución.'),
    ('ERR_PROGRAMA_FACULTAD_INCONSISTENTE', 'BUSINESS_ERROR', 'CRITICO', 'El programa académico indicado no pertenece a la facultad especificada.'),

    -- Razón de causa / estado de asistencia (contrato AN, SJC, EX)
    ('RC_001', 'BUSINESS_ERROR', 'MEDIO', 'El estado de asistencia {} no corresponde a una razón de causa válida.'),
    ('ATT_001', 'BUSINESS_ERROR', 'MEDIO', 'El payload JSON de asistencia no cumple el contrato requerido.'),
    ('ATT_002', 'BUSINESS_ERROR', 'MEDIO', 'El lote de asistencia no puede estar vacío.'),
    ('ATT_003', 'BUSINESS_ERROR', 'MEDIO', 'El estudiante {} aparece más de una vez en el lote de asistencia.'),
    ('SEC_001', 'BUSINESS_ERROR', 'ALTO', 'No tiene permisos suficientes para realizar esta operación.'),
    ('SEC_002', 'BUSINESS_ERROR', 'ALTO', 'No tiene autorización sobre el recurso solicitado.'),

    -- Capacidades no implementadas
    ('ERR_SOLICITUD_MATRICULA_NO_IMPLEMENTADA', 'BUSINESS_ERROR', 'MEDIO', 'La gestión de solicitudes de matrícula aún no se encuentra disponible.'),

    -- Errores de Sistema
    ('SYS_001', 'SYSTEM_ERROR', 'CRITICO', 'Ocurrió un error inesperado al procesar la solicitud.'),
    ('ERR_INESPERADO_REGISTRO_ESTUDIANTE', 'SYSTEM_ERROR', 'CRITICO', 'Hubo un error inesperado al procesar el registro completo del estudiante.'),
    ('ERR_INESPERADO_REGISTRO_DOCENTE', 'SYSTEM_ERROR', 'CRITICO', 'Hubo un error inesperado al procesar el registro completo del docente.'),
    ('ERR_INESPERADO_REGISTRO_ASISTENCIA', 'SYSTEM_ERROR', 'CRITICO', 'Hubo un error inesperado al registrar la asistencia del estudiante.'),

    -- Éxitos
    ('SUC_REGISTRO_ESTUDIANTE_GRUPO', 'SUCCESS', 'BAJO', 'Se ha registrado el estudiante en el grupo de forma satisfactoria.'),
    ('SUC_REGISTRO_DOCENTE_GRUPO', 'SUCCESS', 'BAJO', 'Se ha registrado el docente en el grupo de forma satisfactoria.'),
    ('SUC_REGISTRO_ASISTENCIA', 'SUCCESS', 'BAJO', 'Asistencia registrada de forma satisfactoria.')

) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET 
        Target.tipoMensaje = Source.tipoMensaje,
        Target.severidad = Source.severidad,
        Target.contenido = Source.contenido,
        Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- Sembrado Idempotente Completo: Catálogo de Mensajes Técnicos (CatalogoMensajeTecnico)
MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    -- Correlación y Transacción
    ('CORR_001', 'BUSINESS_ERROR', 'CRITICO', 'Validación fallida: idCorrelacion no está presente o no es un UUID válido. Transacción no procesable.'),
    ('ERR_CORRELACION_REQUERIDA', 'BUSINESS_ERROR', 'CRITICO', 'Error: idCorrelacion no esta presente o es invalido.'),

    -- Plantillas Generales Dinámicas ({})
    ('GEN_001', 'BUSINESS_ERROR', 'MEDIO', 'Error de existencia: No se encontró el registro para la entidad [{}] con el identificador proporcionado.'),
    ('GEN_002', 'BUSINESS_ERROR', 'MEDIO', 'Error de validación: El parámetro o campo [{}] es requerido y no contiene un valor válido.'),
    ('GEN_003', 'BUSINESS_ERROR', 'ALTO', 'Error de unicidad: Se detectó un registro duplicado para la entidad [{}] con la propiedad [{}].'),
    ('GEN_004', 'SUCCESS', 'BAJO', 'Operación exitosa: Se completó la creación/registro de la entidad [{}] de manera correcta.'),
    ('GEN_005', 'SUCCESS', 'BAJO', 'Operación exitosa: Se completó la actualización de la entidad [{}] de manera correcta.'),

    -- Validaciones Biográficas y Formato
    ('VAL_001', 'BUSINESS_ERROR', 'MEDIO', 'Validación de campo: numeroIdentificacion no está presente o es nulo.'),
    ('VAL_002', 'BUSINESS_ERROR', 'MEDIO', 'Validación de rango: numeroIdentificacion debe tener una longitud de entre {} y {} dígitos.'),
    ('VAL_003', 'BUSINESS_ERROR', 'MEDIO', 'Validación de campo: nombres o apellidos vacíos o no proporcionados.'),
    ('VAL_004', 'BUSINESS_ERROR', 'MEDIO', 'Validación de formato: El valor enviado para [{}] contiene caracteres especiales no válidos.'),
    ('VAL_005', 'BUSINESS_ERROR', 'MEDIO', 'Validación de formato: La dirección de correo electrónico no cumple con la estructura estándar.'),
    ('VAL_006', 'BUSINESS_ERROR', 'ALTO', 'Fallo de unicidad: El correo electrónico ya existe en la vista uv_usuario.'),
    ('VAL_007', 'BUSINESS_ERROR', 'ALTO', 'Validación de seguridad: La contraseña no satisface las políticas de complejidad establecidas.'),

    -- Entidades del Sistema
    ('USU_001', 'BUSINESS_ERROR', 'MEDIO', 'Error de búsqueda: No se encontró el usuario con el ID especificado: {}.'),
    ('ERR_USUARIO_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', 'Error: No se encontro el ID de Usuario especificado: {}.'),
    ('USU_002', 'BUSINESS_ERROR', 'ALTO', 'Restricción de acceso: El usuario [{}] tiene estaActivo = 0.'),
    ('ERR_UNICIDAD_CORREO', 'BUSINESS_ERROR', 'ALTO', 'Fallo unicidad: El correo [{}] ya existe en uv_usuario.'),
    ('ERR_UNICIDAD_DOCUMENTO', 'BUSINESS_ERROR', 'ALTO', 'Fallo unicidad: Duplicado en idTipoIdentificacion y numeroIdentificacion [{}].'),

    ('EST_001', 'BUSINESS_ERROR', 'MEDIO', 'Error de búsqueda: No se encontró el estudiante especificado en uv_estudiante: {}.'),
    ('ERR_ESTUDIANTE_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', 'Error: No se encontro el ID de Estudiante especificado: {}.'),
    ('EST_002', 'BUSINESS_ERROR', 'ALTO', 'Registro duplicado: El estudiante {} ya se encuentra asociado al grupo {} en uv_estudiante_grupo.'),
    ('ERR_MATRICULA_DUPLICADA', 'BUSINESS_ERROR', 'ALTO', 'Registro duplicado detectado en uv_estudiante_grupo para Estudiante en Grupo: {}.'),
    ('EST_003', 'BUSINESS_ERROR', 'ALTO', 'Registro duplicado: El estudiante {} ya está asociado al programa en uv_estudiante_programa.'),
    ('EST_004', 'BUSINESS_ERROR', 'ALTO', 'Validación de pertenencia fallida: El estudiante {} no está inscrito en el grupo de la sesión {}.'),
    ('ERR_ESTUDIANTE_NO_PERTENECE_SESION', 'BUSINESS_ERROR', 'ALTO', 'Validacion fallida: Estudiante no pertenece al grupo de la sesion: {}.'),

    ('DOC_001', 'BUSINESS_ERROR', 'MEDIO', 'Error de búsqueda: Docente no encontrado o deshabilitado en uv_docente: {}.'),
    ('ERR_DOCENTE_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', 'Error: No se encontro el ID de Docente especificado: {}.'),
    ('ERR_DOCENTE_NO_TITULAR_GRUPO', 'BUSINESS_ERROR', 'ALTO', 'Docente {} no es titular del Grupo {} (uv_grupo.idDocente).'),

    ('PROG_001', 'BUSINESS_ERROR', 'ALTO', 'Error de búsqueda: No se encontró el programa en uv_programa: {}.'),
    ('ERR_PROGRAMA_GRUPO_NO_ENCONTRADO', 'BUSINESS_ERROR', 'ALTO', 'Error: Trazabilidad rota para Grupo ID {}.'),

    ('GRUP_001', 'BUSINESS_ERROR', 'MEDIO', 'Error de búsqueda: Grupo inexistente o deshabilitado en uv_grupo: {}.'),
    ('ERR_GRUPO_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', 'Error: No existe un grupo habilitado con el identificador: {}.'),
    ('ERR_GRUPO_NO_HABILITADO', 'BUSINESS_ERROR', 'MEDIO', 'Grupo existente, pero fuera de ventana habilitada para matricula: {}.'),
    ('GRUP_002', 'BUSINESS_ERROR', 'ALTO', 'Límite alcanzado: Capacidad máxima superada para el grupo seleccionado: {}.'),
    ('ERR_CUPO_SUPERADO', 'BUSINESS_ERROR', 'ALTO', 'Cupo lleno. Maximo de estudiantes alcanzado para Grupo: {}.'),
    ('ERR_CAPACIDAD_GRUPO_INVALIDA', 'SYSTEM_ERROR', 'CRITICO', 'El parametro GRUPO/CAPACIDAD_MAXIMA_DEFECTO es nulo, cero o negativo: {}.'),
    ('ERR_CUPO_INFERIOR_OCUPACION', 'BUSINESS_ERROR', 'ALTO', 'Grupo {}: capacidad solicitada {} es menor a los estudiantes activos {}.'),
    ('GRUP_003', 'BUSINESS_ERROR', 'ALTO', 'Inconsistencia de trazabilidad: Grupo {} sin programa académico vinculado.'),

    ('HOR_001', 'BUSINESS_ERROR', 'ALTO', 'Colisión horaria: Se detectó una superposición de horario para el estudiante en la misma franja: {}.'),
    ('ERR_CRUCE_HORARIO_ESTUDIANTE', 'BUSINESS_ERROR', 'ALTO', 'Cruce detectado en uv_horario para Estudiante con GrupoID: {}.'),
    ('HOR_002', 'BUSINESS_ERROR', 'ALTO', 'Colisión horaria: Se detectó una superposición de horario para el docente en la misma franja: {}.'),
    ('ERR_CRUCE_HORARIO_DOCENTE', 'BUSINESS_ERROR', 'ALTO', 'Cruce detectado en uv_horario para Docente con GrupoID: {}.'),

    ('SES_001', 'BUSINESS_ERROR', 'MEDIO', 'Error de búsqueda: Sesión no encontrada o cerrada en uv_sesion: {}.'),
    ('ERR_SESION_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', 'Error: No se encontro una sesion activa para el ID especificado: {}.'),
    ('SES_002', 'BUSINESS_ERROR', 'MEDIO', 'Validación fallida: Token QR o código de verificación no coincide o venció para Sesión: {}.'),
    ('SES_003', 'BUSINESS_ERROR', 'MEDIO', 'LEGACY_NOT_SUPPORTED: dbo.Sesion no posee columna de cierre/estado; usp_cerrar_sesion no persiste cierre real.'),
    ('SES_004', 'BUSINESS_ERROR', 'MEDIO', 'Validación temporal fallida: fechaHoraFin [{}] debe ser posterior a fechaHoraInicio [{}].'),
    ('ERR_TOKEN_VERIFICACION_INVALIDO', 'BUSINESS_ERROR', 'MEDIO', 'Fallo: Codigo de verificacion incorrecto o expirado para Sesion: {}.'),

    ('INST_001', 'BUSINESS_ERROR', 'CRITICO', 'Inconsistencia institucional: Los identificadores de institución no coinciden entre la facultad, programa y estudiante: {}.'),
    ('ERR_PROGRAMA_FACULTAD_INCONSISTENTE', 'BUSINESS_ERROR', 'CRITICO', 'Programa {} no pertenece a la Facultad {} indicada en uv_programa.idFacultad.'),

    -- Razón de causa / estado de asistencia (contrato AN, SJC, EX)
    ('RC_001', 'BUSINESS_ERROR', 'MEDIO', 'RazonCausa.codigo = [{}] no existe o no es válido para el contrato de asistencia.'),
    ('ATT_001', 'BUSINESS_ERROR', 'MEDIO', 'Payload JSON inválido: se requiere un arreglo no nulo de objetos con exactamente idEstudiante y estado.'),
    ('ATT_002', 'BUSINESS_ERROR', 'MEDIO', 'Payload JSON válido pero vacío: no hay operación de negocio que ejecutar.'),
    ('ATT_003', 'BUSINESS_ERROR', 'MEDIO', 'Duplicidad en payload JSON: idEstudiante [{}] aparece más de una vez.'),
    ('SEC_001', 'BUSINESS_ERROR', 'ALTO', 'RBAC denegado: el usuario no posee perfil activo requerido o no existe/está inactivo.'),
    ('SEC_002', 'BUSINESS_ERROR', 'ALTO', 'Titularidad denegada: el usuario no está autorizado sobre el recurso solicitado.'),

    -- Capacidades no implementadas
    ('ERR_SOLICITUD_MATRICULA_NO_IMPLEMENTADA', 'BUSINESS_ERROR', 'MEDIO', 'Capability SolicitudMatricula is not implemented in the current schema.'),

    -- Errores de Sistema
    ('SYS_001', 'SYSTEM_ERROR', 'CRITICO', 'Excepción de sistema no controlada capturada en bloque CATCH: {}.'),
    ('ERR_INESPERADO_REGISTRO_ESTUDIANTE', 'SYSTEM_ERROR', 'CRITICO', 'Error critico en orquestador [usp_registrar_estudiante_en_grupo_usuario_no_existente]: {}.'),
    ('ERR_INESPERADO_REGISTRO_DOCENTE', 'SYSTEM_ERROR', 'CRITICO', 'Error critico en orquestador [usp_registrar_docente_en_grupo_usuario_no_existente]: {}.'),
    ('ERR_INESPERADO_REGISTRO_ASISTENCIA', 'SYSTEM_ERROR', 'CRITICO', 'Error critico en orquestador [usp_registrar_asistencia_estudiante]: {}.'),

    -- Éxitos
    ('SUC_REGISTRO_ESTUDIANTE_GRUPO', 'SUCCESS', 'BAJO', 'Operacion exitosa completa. Orquestador finalizado para Estudiante en Grupo: {}.'),
    ('SUC_REGISTRO_DOCENTE_GRUPO', 'SUCCESS', 'BAJO', 'Operacion exitosa completa. Orquestador finalizado para Docente en Grupo: {}.'),
    ('SUC_REGISTRO_ASISTENCIA', 'SUCCESS', 'BAJO', 'Sincronizacion de asistencia completa. Registrada para: {}.')

) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET 
        Target.tipoMensaje = Source.tipoMensaje,
        Target.severidad = Source.severidad,
        Target.contenido = Source.contenido,
        Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
