USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- SES-04: un reclamo de inasistencia aprobado por el docente titular deja la asistencia JUSTIFICADA (EX, asistio = 0);
-- el rechazo conserva la asistencia original. Acciones exactas, una sola rectificacion, auditoria oficial con estado
-- previo y nuevo, y rechazos controlados. Las sesiones ya terminaron: la rectificacion es valida tras el cierre (SES-01
-- no aplica a este flujo). Todos los rechazos de negocio confirman una transaccion sin escrituras, por eso se verifican
-- con INSERT ... EXEC.
DECLARE @group UNIQUEIDENTIFIER, @enrollment UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER;
SELECT TOP 1 @group = eg.idGrupo, @enrollment = eg.id, @teacher = g.idDocente
FROM dbo.uv_estudiante_grupo eg JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
WHERE eg.codigoEstadoEstudiante = 'A' AND g.grupoEstaHablitado = 1
ORDER BY eg.id;
DECLARE @teacherUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_docente_identidad WHERE id = @teacher);
DECLARE @sjc UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = 'SJC');
DECLARE @an UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = 'AN');
DECLARE @pending UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'P');
IF @group IS NULL OR @teacherUser IS NULL OR @sjc IS NULL OR @an IS NULL OR @pending IS NULL
    OR NOT EXISTS (SELECT 1 FROM dbo.RazonCausa WHERE codigo = 'EX')
    THROW 54400, 'TEST FAILED: SES04 fixture missing (grupo con docente, RazonCausa AN/SJC/EX, Estado P).', 1;

DECLARE @n INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
DECLARE @dc INT = 1 + (SELECT ISNULL(MAX(codigo), 0) FROM dbo.DetalleAsistencia);
DECLARE @sApprove UNIQUEIDENTIFIER = NEWID(), @sReject UNIQUEIDENTIFIER = NEWID(), @sNoDetail UNIQUEIDENTIFIER = NEWID(),
        @sPresent UNIQUEIDENTIFIER = NEWID(), @sInvalid UNIQUEIDENTIFIER = NEWID();
DECLARE @aApprove UNIQUEIDENTIFIER = NEWID(), @aReject UNIQUEIDENTIFIER = NEWID(), @aNoDetail UNIQUEIDENTIFIER = NEWID(),
        @aPresent UNIQUEIDENTIFIER = NEWID(), @aInvalid UNIQUEIDENTIFIER = NEWID();
DECLARE @dApprove UNIQUEIDENTIFIER = NEWID(), @dReject UNIQUEIDENTIFIER = NEWID(), @dPresent UNIQUEIDENTIFIER = NEWID(),
        @dInvalid UNIQUEIDENTIFIER = NEWID();
DECLARE @rApprove UNIQUEIDENTIFIER = NEWID(), @rReject UNIQUEIDENTIFIER = NEWID(), @rNoDetail UNIQUEIDENTIFIER = NEWID(),
        @rPresent UNIQUEIDENTIFIER = NEWID(), @rInvalid UNIQUEIDENTIFIER = NEWID();
DECLARE @inicio DATETIME2 = DATEADD(HOUR, -4, SYSUTCDATETIME()), @fin DATETIME2 = DATEADD(HOUR, -2, SYSUTCDATETIME());
DECLARE @corr UNIQUEIDENTIFIER, @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000), @auditBefore INT;
CREATE TABLE #ses04Result (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX),
    mensajeTecnicoResultado NVARCHAR(MAX), estadoResultado INT NOT NULL);

BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    SELECT v.id, v.nombre, @n + v.k, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, @inicio, @fin, N'UTC_V2'
    FROM (VALUES (@sApprove, N'SES04 Aprobar', 0), (@sReject, N'SES04 Rechazar', 1), (@sNoDetail, N'SES04 Sin detalle', 2),
                 (@sPresent, N'SES04 Presente', 3), (@sInvalid, N'SES04 Accion', 4)) v(id, nombre, k);
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion)
    VALUES (@aApprove, @enrollment, @sApprove), (@aReject, @enrollment, @sReject), (@aNoDetail, @enrollment, @sNoDetail),
           (@aPresent, @enrollment, @sPresent), (@aInvalid, @enrollment, @sInvalid);
    INSERT dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
    VALUES (@dApprove, @dc, @aApprove, 0, @sjc, @inicio, @fin), (@dReject, @dc + 1, @aReject, 0, @sjc, @inicio, @fin),
           (@dPresent, @dc + 2, @aPresent, 1, @an, @inicio, @fin), (@dInvalid, @dc + 3, @aInvalid, 0, @sjc, @inicio, @fin);
    INSERT dbo.SolicitudRevisionAsistencia (id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta)
    VALUES (@rApprove, N'REC-SES04-A', @aApprove, CAST(SYSUTCDATETIME() AS DATE), @pending, N'Cita medica', N''),
           (@rReject, N'REC-SES04-R', @aReject, CAST(SYSUTCDATETIME() AS DATE), @pending, N'Sin soporte', N''),
           (@rNoDetail, N'REC-SES04-N', @aNoDetail, CAST(SYSUTCDATETIME() AS DATE), @pending, N'Sin detalle', N''),
           (@rPresent, N'REC-SES04-P', @aPresent, CAST(SYSUTCDATETIME() AS DATE), @pending, N'Presente', N''),
           (@rInvalid, N'REC-SES04-I', @aInvalid, CAST(SYSUTCDATETIME() AS DATE), @pending, N'Accion', N'');

    -- A. Accion fuera del contrato: no se interpreta como rechazo (REV_001), la solicitud sigue pendiente.
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'REV_001', @p_param1 = N'ACEPTAR',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #ses04Result
    EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @rInvalid, @idDocente = @teacher,
        @accion = N'ACEPTAR', @respuestaDocente = N'x', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF (SELECT COUNT(*) FROM #ses04Result WHERE idCorrelacion = @corr AND estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE id = @rInvalid AND estado = @pending)
       OR NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia WHERE id = @dInvalid AND razonCausa = @sjc AND asistio = 0)
        THROW 54401, 'TEST FAILED: SES04_INVALID_ACTION aceptó una acción fuera del contrato.', 1;
    PRINT 'TEST_PASS:SES04_INVALID_ACTION';

    -- B. Solicitud inexistente: REV_005.
    TRUNCATE TABLE #ses04Result;
    SET @corr = NEWID();
    DECLARE @missing UNIQUEIDENTIFIER = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'REV_005', @p_param1 = @missing,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #ses04Result
    EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @missing, @idDocente = @teacher,
        @accion = N'APROBADA', @respuestaDocente = N'x', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF (SELECT COUNT(*) FROM #ses04Result WHERE idCorrelacion = @corr AND estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 54402, 'TEST FAILED: SES04_NOT_FOUND no devolvió REV_005.', 1;
    PRINT 'TEST_PASS:SES04_NOT_FOUND';

    -- C. Docente no titular: VAL_007, sin cambios.
    TRUNCATE TABLE #ses04Result;
    SET @corr = NEWID();
    INSERT INTO #ses04Result
    EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @rApprove, @idDocente = @missing,
        @accion = N'APROBADA', @respuestaDocente = N'Ajeno', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF (SELECT COUNT(*) FROM #ses04Result WHERE idCorrelacion = @corr AND estadoResultado = 0) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE id = @rApprove AND estado = @pending)
       OR NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia WHERE id = @dApprove AND razonCausa = @sjc)
        THROW 54403, 'TEST FAILED: SES04_NON_OWNER un docente ajeno resolvió la solicitud.', 1;
    PRINT 'TEST_PASS:SES04_NON_OWNER';

    -- D. Aprobacion de una ausencia SJC: solicitud A, asistencia EX con asistio = 0, una auditoria con estado previo/nuevo.
    TRUNCATE TABLE #ses04Result;
    SET @corr = NEWID();
    SET @auditBefore = (SELECT COUNT(*) FROM dbo.AuditoriaEvento WHERE resourceId = CAST(@rApprove AS NVARCHAR(120)));
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'SolicitudRevisionAsistencia',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #ses04Result
    EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @rApprove, @idDocente = @teacher,
        @accion = N' aprobada ', @respuestaDocente = N'Soporte verificado', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF (SELECT COUNT(*) FROM #ses04Result WHERE idCorrelacion = @corr AND estadoResultado = 1 AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 54404, 'TEST FAILED: SES04_APPROVE_SJC_TO_EX resultado canónico incorrecto.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_solicitud_revision_asistencia r JOIN dbo.Estado e ON e.id = r.idEstado
                   WHERE r.id = @rApprove AND e.codigo = 'A' AND r.justificacionRespuesta = N'Soporte verificado')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia WHERE id = @dApprove AND codigoRazonCausa = 'EX' AND asistio = 0)
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia WHERE asistencia = @aApprove) <> 1
        THROW 54405, 'TEST FAILED: SES04_APPROVE_SJC_TO_EX la asistencia no quedó JUSTIFICADA (EX, asistio = 0).', 1;
    IF (SELECT COUNT(*) FROM dbo.AuditoriaEvento
        WHERE resourceId = CAST(@rApprove AS NVARCHAR(120)) AND action = 'RESOLVER_SOLICITUD_REVISION_ASISTENCIA'
          AND correlationId = @corr AND actorId = CAST(@teacherUser AS NVARCHAR(120)) AND result = 'SUCCESS'
          AND JSON_VALUE(metadata, '$.razonCausaAnterior') = 'SJC' AND JSON_VALUE(metadata, '$.razonCausaNueva') = 'EX'
          AND JSON_VALUE(metadata, '$.estadoSolicitudAnterior') = 'P' AND JSON_VALUE(metadata, '$.estadoSolicitudNuevo') = 'A'
          AND JSON_VALUE(metadata, '$.asistioNuevo') = 'false') <> 1
       OR (SELECT COUNT(*) FROM dbo.AuditoriaEvento WHERE resourceId = CAST(@rApprove AS NVARCHAR(120))) <> @auditBefore + 1
        THROW 54406, 'TEST FAILED: SES04_APPROVE_AUDITED no registró la auditoría con estado previo y nuevo.', 1;
    PRINT 'TEST_PASS:SES04_APPROVE_SJC_TO_EX';
    PRINT 'TEST_PASS:SES04_APPROVE_AUDITED';

    -- E. Reintento / doble clic con la misma decision: exito idempotente, sin segunda rectificacion ni auditoria.
    TRUNCATE TABLE #ses04Result;
    SET @corr = NEWID();
    INSERT INTO #ses04Result
    EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @rApprove, @idDocente = @teacher,
        @accion = N'APROBADA', @respuestaDocente = N'Reintento', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF (SELECT COUNT(*) FROM #ses04Result WHERE idCorrelacion = @corr AND estadoResultado = 1) <> 1
       OR (SELECT COUNT(*) FROM dbo.AuditoriaEvento WHERE resourceId = CAST(@rApprove AS NVARCHAR(120))) <> @auditBefore + 1
       OR NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE id = @rApprove AND justificacionRespuesta = N'Soporte verificado')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia WHERE id = @dApprove AND codigoRazonCausa = 'EX' AND asistio = 0)
        THROW 54407, 'TEST FAILED: SES04_APPROVE_IDEMPOTENT el reintento produjo una segunda rectificación o cambió la respuesta.', 1;
    PRINT 'TEST_PASS:SES04_APPROVE_IDEMPOTENT';

    -- F. Decision contradictoria sobre una solicitud ya aprobada: REV_002, nada cambia.
    TRUNCATE TABLE #ses04Result;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'REV_002', @p_param1 = @rApprove,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #ses04Result
    EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @rApprove, @idDocente = @teacher,
        @accion = N'RECHAZADA', @respuestaDocente = N'Contradictoria', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF (SELECT COUNT(*) FROM #ses04Result WHERE idCorrelacion = @corr AND estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_solicitud_revision_asistencia r JOIN dbo.Estado e ON e.id = r.idEstado
                      WHERE r.id = @rApprove AND e.codigo = 'A')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia WHERE id = @dApprove AND codigoRazonCausa = 'EX' AND asistio = 0)
        THROW 54408, 'TEST FAILED: SES04_CONTRADICTORY_REJECTED una segunda decisión contradictoria alteró la resolución.', 1;
    PRINT 'TEST_PASS:SES04_CONTRADICTORY_REJECTED';

    -- G. Rechazo: solicitud R y la asistencia original (SJC, asistio = 0) intacta; auditado sin cambio de detalle.
    TRUNCATE TABLE #ses04Result;
    SET @corr = NEWID();
    INSERT INTO #ses04Result
    EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @rReject, @idDocente = @teacher,
        @accion = N'RECHAZADA', @respuestaDocente = N'Sin soporte válido', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF (SELECT COUNT(*) FROM #ses04Result WHERE idCorrelacion = @corr AND estadoResultado = 1) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_solicitud_revision_asistencia r JOIN dbo.Estado e ON e.id = r.idEstado
                      WHERE r.id = @rReject AND e.codigo = 'R')
       OR NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia WHERE id = @dReject AND razonCausa = @sjc AND asistio = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE resourceId = CAST(@rReject AS NVARCHAR(120)) AND correlationId = @corr
                      AND JSON_VALUE(metadata, '$.razonCausaNueva') = 'SJC' AND JSON_VALUE(metadata, '$.estadoSolicitudNuevo') = 'R')
        THROW 54409, 'TEST FAILED: SES04_REJECT_KEEPS_ATTENDANCE el rechazo alteró la asistencia o no quedó auditado.', 1;
    PRINT 'TEST_PASS:SES04_REJECT_KEEPS_ATTENDANCE';

    -- H. Asistencia sin detalle: REV_004, sin crear filas ni simular justificacion.
    TRUNCATE TABLE #ses04Result;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'REV_004', @p_param1 = @rNoDetail,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #ses04Result
    EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @rNoDetail, @idDocente = @teacher,
        @accion = N'APROBADA', @respuestaDocente = N'x', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF (SELECT COUNT(*) FROM #ses04Result WHERE idCorrelacion = @corr AND estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
       OR EXISTS (SELECT 1 FROM dbo.DetalleAsistencia WHERE asistencia = @aNoDetail)
       OR NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE id = @rNoDetail AND estado = @pending)
        THROW 54410, 'TEST FAILED: SES04_NO_DETAIL simuló una justificación sin detalle.', 1;
    PRINT 'TEST_PASS:SES04_NO_DETAIL';

    -- I. Una presencia (AN, asistio = 1) no es justificable: REV_003, sin cambios.
    TRUNCATE TABLE #ses04Result;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'REV_003', @p_param1 = @rPresent,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #ses04Result
    EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @rPresent, @idDocente = @teacher,
        @accion = N'APROBADA', @respuestaDocente = N'x', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF (SELECT COUNT(*) FROM #ses04Result WHERE idCorrelacion = @corr AND estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia WHERE id = @dPresent AND razonCausa = @an AND asistio = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE id = @rPresent AND estado = @pending)
        THROW 54411, 'TEST FAILED: SES04_PRESENT_NOT_JUSTIFIABLE convirtió una presencia.', 1;
    PRINT 'TEST_PASS:SES04_PRESENT_NOT_JUSTIFIABLE';

    -- J. La rectificacion ocurrio sobre sesiones ya cerradas: el registro ordinario no se reabre (SES-01).
    IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE id IN (@sApprove, @sReject) AND fechaHoraFin > SYSUTCDATETIME())
        THROW 54412, 'TEST FAILED: SES04_AFTER_SESSION_CLOSE la fixture no usa sesiones cerradas.', 1;
    PRINT 'TEST_PASS:SES04_AFTER_SESSION_CLOSE';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
DROP TABLE #ses04Result;
IF EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE id IN (@rApprove, @rReject, @rNoDetail, @rPresent, @rInvalid))
   OR EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE resourceId IN (CAST(@rApprove AS NVARCHAR(120)), CAST(@rReject AS NVARCHAR(120))))
    THROW 54413, 'TEST FAILED: SES04 dejó residuos de la fixture.', 1;
PRINT 'TEST END: test_ses04_reclamo_justificada';
GO
