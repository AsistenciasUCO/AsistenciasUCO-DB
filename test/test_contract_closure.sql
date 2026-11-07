USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_contract_closure';

IF EXISTS (
    SELECT 1
    FROM sys.sql_modules
    WHERE [definition] LIKE '%@idUsuarioEjecutor IS NOT NULL%'
)
    THROW 52000, 'TEST FAILED: PUBLIC_SECURITY_EXECUTOR_REQUIRED found executor bypass pattern.', 1;
PRINT 'TEST_PASS:PUBLIC_SECURITY_EXECUTOR_REQUIRED';

IF EXISTS (
    SELECT 1
    FROM sys.parameters p
    JOIN sys.procedures sp ON sp.object_id = p.object_id
    WHERE SCHEMA_NAME(sp.schema_id) = 'dbo'
      AND sp.name IN ('usp_crear_sesion', 'usp_actualizar_sesion')
      AND p.name = '@idDocente'
)
    THROW 52001, 'TEST FAILED: SESSION_PUBLIC_SIGNATURE still exposes @idDocente.', 1;
PRINT 'TEST_PASS:SESSION_IDDOCENTE_REMOVED';

IF OBJECT_ID('dbo.CatalogoParametro', 'U') IS NULL
   OR OBJECT_ID('dbo.CatalogoMensajeUsuario', 'U') IS NULL
   OR OBJECT_ID('dbo.CatalogoMensajeTecnico', 'U') IS NULL
    THROW 52002, 'TEST FAILED: DEPLOY_CATALOGS_NON_DESTRUCTIVE catalog table missing.', 1;
PRINT 'TEST_PASS:DEPLOY_CATALOGS_NON_DESTRUCTIVE';

IF (SELECT COUNT(1) FROM dbo.CatalogoParametro WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER') <> 1
   OR (SELECT COUNT(1) FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'GEN_002') <> 1
   OR (SELECT COUNT(1) FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'GEN_002') <> 1
    THROW 52003, 'TEST FAILED: DEPLOY_CATALOGS_NON_DESTRUCTIVE seed duplicate check failed.', 1;
PRINT 'TEST_PASS:CATALOG_SEEDS_NO_DUPLICATES';

IF (SELECT COUNT(1) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.AuditoriaEvento')) <> 17
   OR NOT EXISTS (SELECT 1 FROM sys.columns c JOIN sys.types t ON t.user_type_id = c.user_type_id WHERE c.object_id = OBJECT_ID('dbo.AuditoriaEvento') AND c.name = 'occurredAt' AND t.name = 'datetimeoffset' AND c.scale = 7 AND c.is_nullable = 0)
    THROW 52004, 'TEST FAILED: AUDIT_SCHEMA_IMMUTABLE shape check failed.', 1;
PRINT 'TEST_PASS:AUDIT_SCHEMA_IMMUTABLE';

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @catNow DATETIME = SYSUTCDATETIME();
    MERGE dbo.CatalogoParametro AS Target
    USING (VALUES ('QA_UTC', 'UTC_CATALOG_TIMESTAMPS', 'ok', 'STRING', 'ok')) AS Source(grupo, clave, valor, tipoDato, valorDefecto)
    ON Target.grupo = Source.grupo AND Target.clave = Source.clave
    WHEN MATCHED THEN
        UPDATE SET valor = Source.valor, fechaModificacion = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
        VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.CatalogoParametro
        WHERE grupo = 'QA_UTC'
          AND clave = 'UTC_CATALOG_TIMESTAMPS'
          AND ABS(DATEDIFF(SECOND, @catNow, fechaModificacion)) <= 5
    )
        THROW 52005, 'TEST FAILED: UTC_CATALOG_TIMESTAMPS did not use UTC timestamp.', 1;

    DECLARE @auditId UNIQUEIDENTIFIER = NEWID();
    DECLARE @occurredAt DATETIMEOFFSET(7) = TODATETIMEOFFSET(SYSUTCDATETIME(), '+00:00');
    INSERT dbo.AuditoriaEvento (
        id, occurredAt, actorId, actorType, [action], resourceType, resourceId, result,
        correlationId, traceId, spanId, httpMethod, [path], httpStatus, clientIp, errorCode, metadata
    )
    VALUES (
        @auditId, @occurredAt, NULL, 'SYSTEM', 'UTC_AUDIT_TIMESTAMP', 'DB', NULL, 'SUCCESS',
        NEWID(), NULL, NULL, 'SQL', N'/db/fixture', 200, NULL, NULL, N'{"source":"test"}'
    );

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.AuditoriaEvento
        WHERE id = @auditId
          AND DATEPART(TZOFFSET, occurredAt) = 0
    )
        THROW 52006, 'TEST FAILED: UTC_AUDIT_TIMESTAMP did not persist +00:00 offset.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
PRINT 'TEST_PASS:UTC_CATALOG_TIMESTAMPS';
PRINT 'TEST_PASS:UTC_AUDIT_TIMESTAMP';

IF (SELECT COUNT(1) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.uv_parametro') AND name IN ('grupo', 'clave', 'valor', 'estaActivo', 'fechaModificacion')) <> 5
    THROW 52007, 'TEST FAILED: CATALOG_PARAMETER_CACHE_CONTRACT missing uv_parametro columns.', 1;
PRINT 'TEST_PASS:CATALOG_PARAMETER_CACHE_CONTRACT';

IF (SELECT COUNT(1) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.uv_mensaje_usuario') AND name IN ('codigo', 'contenido', 'estaActivo', 'fechaModificacion')) <> 4
   OR (SELECT COUNT(1) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.uv_mensaje_tecnico') AND name IN ('codigo', 'contenido', 'estaActivo', 'fechaModificacion')) <> 4
    THROW 52008, 'TEST FAILED: CATALOG_MESSAGE_CACHE_CONTRACT missing message view columns.', 1;
PRINT 'TEST_PASS:CATALOG_MESSAGE_CACHE_CONTRACT';

DECLARE @technicalCodeCases TABLE (
    codigo VARCHAR(100) NOT NULL PRIMARY KEY,
    param1 NVARCHAR(500) NULL,
    param2 NVARCHAR(500) NULL
);

INSERT @technicalCodeCases (codigo, param1, param2)
VALUES
    ('SEC_001', CONVERT(NVARCHAR(36), NEWID()), NULL),
    ('SEC_002', CONVERT(NVARCHAR(36), NEWID()), NULL),
    ('ATT_001', NULL, NULL),
    ('ATT_002', NULL, NULL),
    ('ATT_003', CONVERT(NVARCHAR(36), NEWID()), NULL),
    ('SES_001', CONVERT(NVARCHAR(36), NEWID()), NULL),
    ('SES_003', CONVERT(NVARCHAR(36), NEWID()), NULL),
    ('SES_004', CONVERT(NVARCHAR(30), SYSUTCDATETIME(), 126), CONVERT(NVARCHAR(30), DATEADD(HOUR, -1, SYSUTCDATETIME()), 126)),
    ('RC_001', N'ZZZ', NULL),
    ('GEN_002', N'idUsuarioEjecutor', NULL),
    ('EST_004', CONVERT(NVARCHAR(36), NEWID()), CONVERT(NVARCHAR(36), NEWID()));

DECLARE @prefixFailures TABLE (
    codigo VARCHAR(100) NOT NULL,
    actual NVARCHAR(4000) NULL
);
DECLARE @caseCodigo VARCHAR(100), @caseParam1 NVARCHAR(500), @caseParam2 NVARCHAR(500);
DECLARE code_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT codigo, param1, param2 FROM @technicalCodeCases ORDER BY codigo;
OPEN code_cursor;
FETCH NEXT FROM code_cursor INTO @caseCodigo, @caseParam1, @caseParam2;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @caseUser NVARCHAR(4000), @caseTech NVARCHAR(4000);
    EXEC dbo.usp_obtener_mensaje_catalogo
        @p_codigo = @caseCodigo,
        @p_param1 = @caseParam1,
        @p_param2 = @caseParam2,
        @mensajeUsuarioResultado = @caseUser OUTPUT,
        @mensajeTecnicoResultado = @caseTech OUTPUT;

    IF @caseTech NOT LIKE CONCAT('DBCODE=', @caseCodigo, '|%')
        INSERT @prefixFailures (codigo, actual) VALUES (@caseCodigo, @caseTech);

    FETCH NEXT FROM code_cursor INTO @caseCodigo, @caseParam1, @caseParam2;
END
CLOSE code_cursor;
DEALLOCATE code_cursor;

IF EXISTS (SELECT 1 FROM @prefixFailures)
BEGIN
    DECLARE @prefixFailure NVARCHAR(4000) = (
        SELECT TOP 1 CONCAT('TEST FAILED: TECHNICAL_CODE_CHANNEL ', codigo, ' actual=', COALESCE(actual, N'NULL'))
        FROM @prefixFailures
        ORDER BY codigo
    );
    THROW 52011, @prefixFailure, 1;
END
PRINT 'TEST_PASS:TECHNICAL_CODE_CHANNEL';
PRINT 'TEST_PASS:SEC_001_PREFIX';
PRINT 'TEST_PASS:SEC_002_PREFIX';
PRINT 'TEST_PASS:ATT_PREFIX';
PRINT 'TEST_PASS:SES_PREFIX';
PRINT 'TEST_PASS:RC_001_PREFIX';
PRINT 'TEST_PASS:GEN_002_PREFIX';
PRINT 'TEST_PASS:EST_004_PREFIX';

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @fallbackCode VARCHAR(100) = 'QA_TECH_FALLBACK';
    DECLARE @fallbackUser NVARCHAR(4000), @fallbackTech NVARCHAR(4000);
    INSERT dbo.CatalogoMensajeUsuario (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (@fallbackCode, 'BUSINESS_ERROR', 'MEDIO', N'QA fallback usuario.', 1, SYSUTCDATETIME(), SYSUTCDATETIME());

    EXEC dbo.usp_obtener_mensaje_catalogo
        @p_codigo = @fallbackCode,
        @mensajeUsuarioResultado = @fallbackUser OUTPUT,
        @mensajeTecnicoResultado = @fallbackTech OUTPUT;

    IF @fallbackTech NOT LIKE CONCAT('DBCODE=', @fallbackCode, '|Mensaje técnico no configurado%')
        THROW 52012, 'TEST FAILED: TECHNICAL_CODE_CHANNEL_FALLBACK lost catalog code.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
PRINT 'TEST_PASS:TECHNICAL_CODE_CHANNEL_FALLBACK';

DECLARE @badResultSets TABLE (
    procedureName SYSNAME NOT NULL,
    reason NVARCHAR(4000) NOT NULL
);

-- Exclusiones normativas de la regla MUTATION_COMMAND_RESULTSET (4 columnas canonicas):
--   usp_obtener_mensaje_catalogo             helper tecnico de catalogo (contrato publico lo excluye).
--   usp_consultar_grupos_paginado            READ_QUERY_RESULTSET: devuelve filas de datos + totalRegistros;
--                                            NON_GOLDEN_PATH_EXTENSION, no es un SP de comando/mutacion.
--   usp_consultar_archivo_soporte_autorizado / usp_consultar_solicitudes_revision_docente (LB-004D)
--                                            READ_QUERY_RESULTSET: devuelven filas de datos; NON_GOLDEN_PATH_EXTENSION.
--   usp_consultar_docentes_programa / usp_consultar_candidatos_docente_programa (HU062/HU091)
--                                            READ_QUERY_RESULTSET: devuelven filas de datos; NON_GOLDEN_PATH_EXTENSION.
--   usp_corregir_identidad_usuario (HU159): comando canonico + idUsuario, correo y numeroIdentificacion para la
--                                            sincronizacion de la cuenta de identidad (igual que usp_actualizar_coordinador).
--   usp_consultar_perfil_usuario (HU006)
--                                            READ_QUERY_RESULTSET: perfil propio con una fila por vinculo; NON_GOLDEN_PATH_EXTENSION.
--   usp_consultar_historial_grupos_docente_programa (HU094) / usp_consultar_resumen_docentes_programa (HU095)
--                                            READ_QUERY_RESULTSET: historial del docente + resumen / consolidado por tipo de vinculacion; NON_GOLDEN_PATH_EXTENSION.
--   usp_consultar_oferta_grupos_estudiante (HU008)
--                                            READ_QUERY_RESULTSET: oferta de grupos del estudiante + totalRegistros; NON_GOLDEN_PATH_EXTENSION.
--   usp_consultar_destinatarios_retiro_estudiante_grupo (HU051)
--                                            READ_QUERY_RESULTSET: destinatarios del aviso de retiro; NON_GOLDEN_PATH_EXTENSION.
--   usp_consultar_solicitudes_revision_estudiante (HU010/HU011)
--                                            READ_QUERY_RESULTSET: filas propias del estudiante + totalRegistros; NON_GOLDEN_PATH_EXTENSION.
--   usp_consultar_detalle_solicitud_revision_docente (HU035/HU036)
--                                            READ_QUERY_RESULTSET: 0..1 fila de detalle; NON_GOLDEN_PATH_EXTENSION.
--   usp_consultar_programas_academicos (HU108)
--   usp_consultar_kpis_coordinador / alerta_temprana / bitacora / ficha / resumen_asistencia (HU065-HU070): lecturas de solo consulta
--                                            READ_QUERY_RESULTSET: filas de programa + totalRegistros; NON_GOLDEN_PATH_EXTENSION.
--   usp_consultar_estudiantes_facultad_paginado / usp_consultar_estudiante_facultad_detalle /
--   usp_consultar_estructura_facultad / usp_consultar_sesiones_facultad_paginado (HU104/HU105/HU109/HU119/HU145)
--                                            READ_QUERY_RESULTSET: filas de datos del decano; NON_GOLDEN_PATH_EXTENSION.
--   usp_consultar_programas_creditos_facultad_paginado / usp_consultar_docentes_facultad_paginado /
--   usp_buscar_asignaturas_paginado / usp_buscar_estudiantes_institucion_paginado /
--   usp_consultar_historial_estudiante (HU112/HU128/HU143/HU157)
--                                            READ_QUERY_RESULTSET: filas de datos del decano o del administrador; NON_GOLDEN_PATH_EXTENSION.
--   usp_consultar_consolidado_asistencia_grupos_paginado / usp_consultar_auditoria_eventos_paginado /
--   usp_consultar_componentes_formacion (HU061/HU172/HU147)
--                                            READ_QUERY_RESULTSET: consolidado, auditoria y catalogo de componentes; NON_GOLDEN_PATH_EXTENSION.
--   usp_consultar_token_verificacion_correo / usp_consultar_reenvio_verificacion_correo (IDENT-001): READ_QUERY_RESULTSET: 0..1 fila con idUsuario; NON_GOLDEN_PATH_EXTENSION.
--   usp_abrir_ventana_matricula_grupo / usp_rotar_token_matricula_grupo / usp_rotar_token_matricula_automatico /
--   usp_matricular_estudiante_por_token / usp_registrar_estudiante_por_token_publico (HU176B, CONTRACT §2.3, §2.3b, §2.5 y A2):
--                                            comando canonico + columnas extra documentadas (idVentana, fechas, idEstudiante/idUsuario/idGrupo),
--                                            igual que usp_actualizar_coordinador.
--   usp_consultar_ventanas_matricula_por_rotar / usp_validar_token_matricula_publico (HU176B)
--                                            READ_QUERY_RESULTSET: ventanas por rotar / datos minimos del curso; NON_GOLDEN_PATH_EXTENSION.
--   usp_consultar_directorio_estudiantes_paginado / usp_consultar_estudiantes_grupo_ambito_paginado /
--   usp_consultar_asistencias_grupo_ambito_paginado / usp_consultar_materias_estudiante / usp_consultar_horario_estudiante /
--   usp_buscar_estudiante_por_documento_grupo (CULM-001 A.2-1, A.2-2, A.2-11, A.2-15)
--                                            READ_QUERY_RESULTSET con ambito en el SP; NON_GOLDEN_PATH_EXTENSION.
--   usp_cambiar_estado_decano (CULM-001 A.2-8): comando canonico + idUsuario, personaSinRolesActivos y estaActivoDecano,
--                                            igual que usp_cambiar_estado_coordinador.
--   usp_establecer_contexto_usuario_ejecutor helper de SESSION_CONTEXT: no devuelve resultset.
--   CULM-001 B.1 (CONTRACT §2.0, §2.7): usp_cancelar_sesion / usp_cargar_dias_festivos[_automatico] /
--   usp_aplicar_festivos_grupo / usp_aplicar_festivos_periodo / usp_aplicar_festivos_automatico / usp_generar_sesiones_grupo_v2
--                                            comando canonico + columnas de datos documentadas (NULL si estadoResultado = 0).
--   usp_consultar_destinatarios_sesion_cancelada / usp_consultar_sesiones_festivo_con_asistencia_paginado /
--   usp_consultar_dias_festivos / usp_consultar_carga_festivos_anio
--                                            READ_QUERY_RESULTSET: destinatarios, sesiones reportadas, festivos y carga del anio.
--   CULM-001 B.2 (CONTRACT §2.0, §2.8): usp_abrir_toma_asistencia / usp_cerrar_toma_asistencia / usp_registrar_asistencias_toma /
--   usp_abrir_qr_toma / usp_rotar_token_asistencia_toma / usp_rotar_token_asistencia_automatico / usp_cerrar_qr_toma /
--   usp_registrar_asistencia_por_token      comando canonico + columnas de datos documentadas (NULL si estadoResultado = 0).
--   usp_cerrar_tomas_vencidas (job)         una fila por toma cerrada (idToma, idSesion, idGrupo, totalAusentesMarcados).
--   usp_consultar_tomas_qr_por_rotar / usp_consultar_tomas_sesion / usp_consultar_faltantes_toma_paginado /
--   usp_consultar_asistencias_toma_paginado / usp_consultar_resumen_asistencia_grupo_docente_paginado /
--   usp_consultar_resumen_asistencia_estudiante
--                                            READ_QUERY_RESULTSET: tomas, faltantes, asistencias por toma y resumenes por horas.
--   CULM-001 D.1 (CONTRACT §2.2): usp_consultar_sesiones_materia_estudiante
--                                            READ_QUERY_RESULTSET: sesiones de la materia con la fecha limite de justificacion.
-- El resultset canonico de 4 columnas es exclusivo de los SP de comando/mutacion del Golden Path.
INSERT @badResultSets (procedureName, reason)
SELECT sp.name, CONCAT('describe_error=', COALESCE(CONVERT(NVARCHAR(20), d.error_number), N'NULL'), ': ', COALESCE(d.error_message, N''))
FROM sys.procedures sp
CROSS APPLY sys.dm_exec_describe_first_result_set_for_object(sp.object_id, NULL) d
WHERE SCHEMA_NAME(sp.schema_id) = 'dbo'
  AND sp.name LIKE 'usp[_]%'
  AND sp.name NOT LIKE '%[_]interno'
  AND sp.name <> 'usp_obtener_mensaje_catalogo'
  AND sp.name NOT IN ('usp_reservar_notificaciones_salientes', 'usp_depurar_notificaciones_salientes')
  AND sp.name <> 'usp_consultar_grupos_paginado'
  AND sp.name NOT IN ('usp_consultar_archivo_soporte_autorizado', 'usp_consultar_solicitudes_revision_docente', 'usp_consultar_solicitudes_revision_estudiante', 'usp_consultar_destinatarios_retiro_estudiante_grupo', 'usp_consultar_destinatarios_reclamo_asistencia', 'usp_consultar_perfil_usuario', 'usp_consultar_oferta_grupos_estudiante', 'usp_consultar_detalle_solicitud_revision_docente', 'usp_consultar_programas_academicos', 'usp_consultar_docentes_programa', 'usp_consultar_historial_grupos_docente_programa', 'usp_consultar_resumen_docentes_programa', 'usp_consultar_candidatos_docente_programa', 'usp_actualizar_coordinador', 'usp_corregir_identidad_usuario', 'usp_cambiar_estado_coordinador', 'usp_consultar_kpis_coordinador', 'usp_consultar_alerta_temprana_programa', 'usp_consultar_bitacora_estudiante_programa', 'usp_consultar_ficha_estudiante_programa', 'usp_consultar_resumen_asistencia_estudiante_programa', 'usp_consultar_kpis_decano', 'usp_consultar_comparativa_programas_facultad', 'usp_consultar_aforo_grupos_facultad', 'usp_consultar_kpis_institucion', 'usp_consultar_comparativa_facultades', 'usp_consultar_tendencia_ausentismo', 'usp_consultar_oferta_creacion_grupo_docente')
  AND sp.name <> 'usp_consultar_sesiones_grupo_paginado'
  AND sp.name <> 'usp_consultar_asistencias_sesion_paginado'
  AND sp.name NOT IN ('usp_consultar_estudiantes_facultad_paginado', 'usp_consultar_estudiante_facultad_detalle', 'usp_consultar_estructura_facultad', 'usp_consultar_sesiones_facultad_paginado')
  AND sp.name NOT IN ('usp_consultar_programas_creditos_facultad_paginado', 'usp_consultar_docentes_facultad_paginado', 'usp_buscar_asignaturas_paginado', 'usp_buscar_estudiantes_institucion_paginado', 'usp_consultar_historial_estudiante')
  AND sp.name NOT IN ('usp_consultar_consolidado_asistencia_grupos_paginado', 'usp_consultar_auditoria_eventos_paginado', 'usp_consultar_componentes_formacion')
  AND sp.name NOT IN ('usp_consultar_directorio_estudiantes_paginado', 'usp_consultar_estudiantes_grupo_ambito_paginado', 'usp_consultar_asistencias_grupo_ambito_paginado', 'usp_consultar_materias_estudiante', 'usp_consultar_horario_estudiante', 'usp_buscar_estudiante_por_documento_grupo', 'usp_cambiar_estado_decano')
  AND sp.name NOT IN ('usp_establecer_contexto_usuario_ejecutor', 'usp_consultar_token_verificacion_correo', 'usp_consultar_reenvio_verificacion_correo', 'usp_abrir_ventana_matricula_grupo', 'usp_rotar_token_matricula_grupo', 'usp_rotar_token_matricula_automatico', 'usp_matricular_estudiante_por_token', 'usp_registrar_estudiante_por_token_publico', 'usp_consultar_ventanas_matricula_por_rotar', 'usp_validar_token_matricula_publico')
  AND sp.name NOT IN ('usp_abrir_toma_asistencia', 'usp_cerrar_toma_asistencia', 'usp_cerrar_tomas_vencidas', 'usp_registrar_asistencias_toma', 'usp_abrir_qr_toma', 'usp_rotar_token_asistencia_toma', 'usp_rotar_token_asistencia_automatico', 'usp_consultar_tomas_qr_por_rotar', 'usp_cerrar_qr_toma', 'usp_registrar_asistencia_por_token', 'usp_consultar_tomas_sesion', 'usp_consultar_faltantes_toma_paginado', 'usp_consultar_asistencias_toma_paginado', 'usp_consultar_resumen_asistencia_grupo_docente_paginado', 'usp_consultar_resumen_asistencia_estudiante')
  AND sp.name <> 'usp_consultar_sesiones_materia_estudiante'
  AND d.error_number IS NOT NULL;

INSERT @badResultSets (procedureName, reason)
SELECT sp.name, CONCAT('canonical_columns=', COUNT(d.column_ordinal))
FROM sys.procedures sp
CROSS APPLY sys.dm_exec_describe_first_result_set_for_object(sp.object_id, NULL) d
WHERE SCHEMA_NAME(sp.schema_id) = 'dbo'
  AND sp.name LIKE 'usp[_]%'
  AND sp.name NOT LIKE '%[_]interno'
  AND sp.name <> 'usp_obtener_mensaje_catalogo'
  AND sp.name NOT IN ('usp_reservar_notificaciones_salientes', 'usp_depurar_notificaciones_salientes')
  AND sp.name <> 'usp_consultar_grupos_paginado'
  AND sp.name NOT IN ('usp_consultar_archivo_soporte_autorizado', 'usp_consultar_solicitudes_revision_docente', 'usp_consultar_solicitudes_revision_estudiante', 'usp_consultar_destinatarios_retiro_estudiante_grupo', 'usp_consultar_destinatarios_reclamo_asistencia', 'usp_consultar_perfil_usuario', 'usp_consultar_oferta_grupos_estudiante', 'usp_consultar_detalle_solicitud_revision_docente', 'usp_consultar_programas_academicos', 'usp_consultar_docentes_programa', 'usp_consultar_historial_grupos_docente_programa', 'usp_consultar_resumen_docentes_programa', 'usp_consultar_candidatos_docente_programa', 'usp_actualizar_coordinador', 'usp_corregir_identidad_usuario', 'usp_cambiar_estado_coordinador', 'usp_consultar_kpis_coordinador', 'usp_consultar_alerta_temprana_programa', 'usp_consultar_bitacora_estudiante_programa', 'usp_consultar_ficha_estudiante_programa', 'usp_consultar_resumen_asistencia_estudiante_programa', 'usp_consultar_kpis_decano', 'usp_consultar_comparativa_programas_facultad', 'usp_consultar_aforo_grupos_facultad', 'usp_consultar_kpis_institucion', 'usp_consultar_comparativa_facultades', 'usp_consultar_tendencia_ausentismo', 'usp_consultar_oferta_creacion_grupo_docente')
  AND sp.name <> 'usp_consultar_sesiones_grupo_paginado'
  AND sp.name <> 'usp_consultar_asistencias_sesion_paginado'
  AND sp.name NOT IN ('usp_consultar_estudiantes_facultad_paginado', 'usp_consultar_estudiante_facultad_detalle', 'usp_consultar_estructura_facultad', 'usp_consultar_sesiones_facultad_paginado')
  AND sp.name NOT IN ('usp_consultar_programas_creditos_facultad_paginado', 'usp_consultar_docentes_facultad_paginado', 'usp_buscar_asignaturas_paginado', 'usp_buscar_estudiantes_institucion_paginado', 'usp_consultar_historial_estudiante')
  AND sp.name NOT IN ('usp_consultar_consolidado_asistencia_grupos_paginado', 'usp_consultar_auditoria_eventos_paginado', 'usp_consultar_componentes_formacion')
  AND sp.name NOT IN ('usp_consultar_directorio_estudiantes_paginado', 'usp_consultar_estudiantes_grupo_ambito_paginado', 'usp_consultar_asistencias_grupo_ambito_paginado', 'usp_consultar_materias_estudiante', 'usp_consultar_horario_estudiante', 'usp_buscar_estudiante_por_documento_grupo', 'usp_cambiar_estado_decano')
  AND sp.name NOT IN ('usp_establecer_contexto_usuario_ejecutor', 'usp_consultar_token_verificacion_correo', 'usp_consultar_reenvio_verificacion_correo', 'usp_abrir_ventana_matricula_grupo', 'usp_rotar_token_matricula_grupo', 'usp_rotar_token_matricula_automatico', 'usp_matricular_estudiante_por_token', 'usp_registrar_estudiante_por_token_publico', 'usp_consultar_ventanas_matricula_por_rotar', 'usp_validar_token_matricula_publico')
  AND sp.name NOT IN ('usp_cancelar_sesion', 'usp_cargar_dias_festivos', 'usp_cargar_dias_festivos_automatico', 'usp_aplicar_festivos_grupo', 'usp_aplicar_festivos_periodo', 'usp_aplicar_festivos_automatico', 'usp_generar_sesiones_grupo_v2', 'usp_consultar_destinatarios_sesion_cancelada', 'usp_consultar_sesiones_festivo_con_asistencia_paginado', 'usp_consultar_dias_festivos', 'usp_consultar_carga_festivos_anio')
  AND sp.name NOT IN ('usp_abrir_toma_asistencia', 'usp_cerrar_toma_asistencia', 'usp_cerrar_tomas_vencidas', 'usp_registrar_asistencias_toma', 'usp_abrir_qr_toma', 'usp_rotar_token_asistencia_toma', 'usp_rotar_token_asistencia_automatico', 'usp_consultar_tomas_qr_por_rotar', 'usp_cerrar_qr_toma', 'usp_registrar_asistencia_por_token', 'usp_consultar_tomas_sesion', 'usp_consultar_faltantes_toma_paginado', 'usp_consultar_asistencias_toma_paginado', 'usp_consultar_resumen_asistencia_grupo_docente_paginado', 'usp_consultar_resumen_asistencia_estudiante')
  AND sp.name <> 'usp_consultar_sesiones_materia_estudiante'
  AND d.error_number IS NULL
GROUP BY sp.name
HAVING COUNT(d.column_ordinal) <> 4;

INSERT @badResultSets (procedureName, reason)
SELECT sp.name, CONCAT('bad column ', d.column_ordinal, ': ', d.name, '/', d.system_type_name)
FROM sys.procedures sp
CROSS APPLY sys.dm_exec_describe_first_result_set_for_object(sp.object_id, NULL) d
WHERE SCHEMA_NAME(sp.schema_id) = 'dbo'
  AND sp.name LIKE 'usp[_]%'
  AND sp.name NOT LIKE '%[_]interno'
  AND sp.name <> 'usp_obtener_mensaje_catalogo'
  AND sp.name NOT IN ('usp_reservar_notificaciones_salientes', 'usp_depurar_notificaciones_salientes')
  AND sp.name <> 'usp_consultar_grupos_paginado'
  AND sp.name NOT IN ('usp_consultar_archivo_soporte_autorizado', 'usp_consultar_solicitudes_revision_docente', 'usp_consultar_solicitudes_revision_estudiante', 'usp_consultar_destinatarios_retiro_estudiante_grupo', 'usp_consultar_destinatarios_reclamo_asistencia', 'usp_consultar_perfil_usuario', 'usp_consultar_oferta_grupos_estudiante', 'usp_consultar_detalle_solicitud_revision_docente', 'usp_consultar_programas_academicos', 'usp_consultar_docentes_programa', 'usp_consultar_historial_grupos_docente_programa', 'usp_consultar_resumen_docentes_programa', 'usp_consultar_candidatos_docente_programa', 'usp_actualizar_coordinador', 'usp_corregir_identidad_usuario', 'usp_cambiar_estado_coordinador', 'usp_consultar_kpis_coordinador', 'usp_consultar_alerta_temprana_programa', 'usp_consultar_bitacora_estudiante_programa', 'usp_consultar_ficha_estudiante_programa', 'usp_consultar_resumen_asistencia_estudiante_programa', 'usp_consultar_kpis_decano', 'usp_consultar_comparativa_programas_facultad', 'usp_consultar_aforo_grupos_facultad', 'usp_consultar_kpis_institucion', 'usp_consultar_comparativa_facultades', 'usp_consultar_tendencia_ausentismo', 'usp_consultar_oferta_creacion_grupo_docente')
  AND sp.name <> 'usp_consultar_sesiones_grupo_paginado'
  AND sp.name <> 'usp_consultar_asistencias_sesion_paginado'
  AND sp.name NOT IN ('usp_consultar_estudiantes_facultad_paginado', 'usp_consultar_estudiante_facultad_detalle', 'usp_consultar_estructura_facultad', 'usp_consultar_sesiones_facultad_paginado')
  AND sp.name NOT IN ('usp_consultar_programas_creditos_facultad_paginado', 'usp_consultar_docentes_facultad_paginado', 'usp_buscar_asignaturas_paginado', 'usp_buscar_estudiantes_institucion_paginado', 'usp_consultar_historial_estudiante')
  AND sp.name NOT IN ('usp_consultar_consolidado_asistencia_grupos_paginado', 'usp_consultar_auditoria_eventos_paginado', 'usp_consultar_componentes_formacion')
  AND sp.name NOT IN ('usp_consultar_directorio_estudiantes_paginado', 'usp_consultar_estudiantes_grupo_ambito_paginado', 'usp_consultar_asistencias_grupo_ambito_paginado', 'usp_consultar_materias_estudiante', 'usp_consultar_horario_estudiante', 'usp_buscar_estudiante_por_documento_grupo', 'usp_cambiar_estado_decano')
  AND sp.name NOT IN ('usp_establecer_contexto_usuario_ejecutor', 'usp_consultar_token_verificacion_correo', 'usp_consultar_reenvio_verificacion_correo', 'usp_abrir_ventana_matricula_grupo', 'usp_rotar_token_matricula_grupo', 'usp_rotar_token_matricula_automatico', 'usp_matricular_estudiante_por_token', 'usp_registrar_estudiante_por_token_publico', 'usp_consultar_ventanas_matricula_por_rotar', 'usp_validar_token_matricula_publico')
  AND sp.name NOT IN ('usp_cancelar_sesion', 'usp_cargar_dias_festivos', 'usp_cargar_dias_festivos_automatico', 'usp_aplicar_festivos_grupo', 'usp_aplicar_festivos_periodo', 'usp_aplicar_festivos_automatico', 'usp_generar_sesiones_grupo_v2', 'usp_consultar_destinatarios_sesion_cancelada', 'usp_consultar_sesiones_festivo_con_asistencia_paginado', 'usp_consultar_dias_festivos', 'usp_consultar_carga_festivos_anio')
  AND sp.name NOT IN ('usp_abrir_toma_asistencia', 'usp_cerrar_toma_asistencia', 'usp_cerrar_tomas_vencidas', 'usp_registrar_asistencias_toma', 'usp_abrir_qr_toma', 'usp_rotar_token_asistencia_toma', 'usp_rotar_token_asistencia_automatico', 'usp_consultar_tomas_qr_por_rotar', 'usp_cerrar_qr_toma', 'usp_registrar_asistencia_por_token', 'usp_consultar_tomas_sesion', 'usp_consultar_faltantes_toma_paginado', 'usp_consultar_asistencias_toma_paginado', 'usp_consultar_resumen_asistencia_grupo_docente_paginado', 'usp_consultar_resumen_asistencia_estudiante')
  AND sp.name <> 'usp_consultar_sesiones_materia_estudiante'
  AND d.error_number IS NULL
  AND (
       (d.column_ordinal = 1 AND (d.name <> 'idCorrelacion' OR d.system_type_name <> 'uniqueidentifier'))
    OR (d.column_ordinal = 2 AND (d.name <> 'mensajeUsuarioResultado' OR d.system_type_name NOT LIKE 'nvarchar%'))
    OR (d.column_ordinal = 3 AND (d.name <> 'mensajeTecnicoResultado' OR d.system_type_name NOT LIKE 'nvarchar%'))
    OR (d.column_ordinal = 4 AND (d.name <> 'estadoResultado' OR d.system_type_name <> 'bit'))
  );

IF EXISTS (SELECT 1 FROM @badResultSets)
BEGIN
    DECLARE @publicResultFailure NVARCHAR(4000) = (
        SELECT TOP 1 CONCAT('TEST FAILED: PUBLIC_CANONICAL_RESULTSET ', procedureName, ' ', reason)
        FROM @badResultSets
        ORDER BY procedureName
    );
    THROW 52009, @publicResultFailure, 1;
END
PRINT 'TEST_PASS:PUBLIC_CANONICAL_RESULTSET';

IF @@TRANCOUNT <> 0 THROW 52010, 'TEST FAILED: test_contract_closure left transaction open.', 1;
PRINT 'TEST END: test_contract_closure';
GO
