USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- CULM-001 B.1 (CONTRACT §2.7.1, §2.16.1 B1-VEN-01..05): ventana de registro SES-01 con @toleranciaMinutos y
-- @margenMinutos opcionales (NULL o negativos = 0, regla estricta [inicio, fin)) y rechazo SES_010 de sesiones
-- canceladas para todos los llamadores. Las llamadas de 5 parametros (lote congelado, autonomo) no cambian.
-- Todo corre en una transaccion que se revierte; las sesiones de prueba llevan el prefijo CULM1-.
PRINT 'TEST START: test_culm001_b1_ventana_tolerancia (CULM-001 B.1)';

IF OBJECT_ID(N'dbo.SesionCancelacion', N'U') IS NULL OR OBJECT_ID(N'dbo.TipoCancelacionSesion', N'U') IS NULL
    THROW 57000, 'TEST FAILED CULM001_B1_VEN_00: faltan dbo.SesionCancelacion o dbo.TipoCancelacionSesion.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_validar_sesion_ventana_registro_interno') AND name = N'@toleranciaMinutos')
   OR NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_validar_sesion_ventana_registro_interno') AND name = N'@margenMinutos')
    THROW 57001, 'TEST FAILED CULM001_B1_VEN_00: usp_validar_sesion_ventana_registro_interno no admite @toleranciaMinutos/@margenMinutos.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.sql_modules m WHERE m.object_id = OBJECT_ID(N'dbo.usp_validar_sesion_ventana_registro_interno')
               AND m.definition LIKE N'%@toleranciaMinutos%INT%=%NULL%' AND m.definition LIKE N'%@margenMinutos%INT%=%NULL%')
    THROW 57002, 'TEST FAILED CULM001_B1_VEN_00: los parametros nuevos deben ser opcionales (= NULL).', 1;
PRINT 'TEST_PASS:CULM001_B1_VEN_00_FIRMA';
GO

DECLARE @group UNIQUEIDENTIFIER, @student UNIQUEIDENTIFIER, @owner UNIQUEIDENTIFIER;
SELECT TOP 1 @group = eg.idGrupo, @student = eg.idEstudiante, @owner = di.idUsuario
FROM dbo.uv_estudiante_grupo eg
JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
WHERE eg.codigoEstadoEstudiante = 'A' AND g.grupoEstaHablitado = 1 AND di.estaActivoUsuario = 1
ORDER BY eg.id;
DECLARE @tipoDocente UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoCancelacionSesion WHERE esAutomatica = 0);
DECLARE @tol INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'TOLERANCIA_MINUTOS');
DECLARE @margen INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
IF @group IS NULL OR @student IS NULL OR @owner IS NULL OR @tipoDocente IS NULL OR @tol <> 15 OR @margen <> 30
    THROW 57010, 'TEST FAILED CULM001_B1_VEN: fixture faltante (grupo con docente y estudiante activos, TipoCancelacionSesion DOCENTE, TOLERANCIA=15, MARGEN=30).', 1;

DECLARE @n INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
DECLARE @s UNIQUEIDENTIFIER, @corr UNIQUEIDENTIFIER;
DECLARE @u NVARCHAR(4000), @t NVARCHAR(4000), @e BIT, @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
DECLARE @tranBefore INT;
DECLARE @existingSession UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Sesion ORDER BY id);
IF @existingSession IS NULL THROW 57015, 'TEST FAILED CULM001_B1_VEN: no hay una sesion existente para la prueba de bloqueo.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    SET @tranBefore = @@TRANCOUNT;

    -- ------------------------------------------------------------------------------------------------------------
    -- B1-VEN-01: llamada de 5 parametros = regla estricta [inicio, fin)
    -- ------------------------------------------------------------------------------------------------------------
    -- Antes del inicio por 3 s: SES_007
    SET @s = NEWID(); SET @n += 1;
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@s, N'CULM1-VEN01 antes', @n, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
            DATEADD(SECOND, 3, SYSUTCDATETIME()), DATEADD(HOUR, 2, SYSUTCDATETIME()), N'UTC_V2');
    SET @corr = NEWID();
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @s, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT;
    IF @e <> 0 OR @t NOT LIKE N'DBCODE=SES[_]007|%'
        THROW 57011, 'TEST FAILED CULM001_B1_VEN_01: sin tolerancia, un instante antes del inicio debe ser SES_007.', 1;
    -- Mismo SES_007 aunque el mensaje tecnico no cambie respecto a SES-01 (sin tolerancia no se agrega texto)
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_007', @p_param1 = @s, @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    IF @t <> CONCAT(@techMsg, ' Correlacion: ', @corr)
        THROW 57012, 'TEST FAILED CULM001_B1_VEN_01: la llamada de 5 parametros cambio el mensaje tecnico de SES-01.', 1;

    -- Fin exacto: SES_008 (fin = reloj antes de la llamada)
    SET @s = NEWID(); SET @n += 1;
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@s, N'CULM1-VEN01 fin', @n, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
            DATEADD(HOUR, -2, SYSUTCDATETIME()), SYSUTCDATETIME(), N'UTC_V2');
    SET @corr = NEWID();
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @s, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT;
    IF @e <> 0 OR @t NOT LIKE N'DBCODE=SES[_]008|%'
        THROW 57013, 'TEST FAILED CULM001_B1_VEN_01: sin tolerancia, el fin exacto debe ser SES_008.', 1;

    -- Durante: admite
    SET @s = NEWID(); SET @n += 1;
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@s, N'CULM1-VEN01 durante', @n, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
            DATEADD(HOUR, -1, SYSUTCDATETIME()), DATEADD(HOUR, 1, SYSUTCDATETIME()), N'UTC_V2');
    SET @corr = NEWID();
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @s, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT;
    IF @e <> 1
        THROW 57014, 'TEST FAILED CULM001_B1_VEN_01: sin tolerancia, una sesion en curso debe admitir el registro.', 1;
    PRINT 'TEST_PASS:CULM001_B1_VEN_01_SIN_TOLERANCIA';

    -- ------------------------------------------------------------------------------------------------------------
    -- B1-VEN-02: tolerancia 15 / margen 30
    -- ------------------------------------------------------------------------------------------------------------
    -- inicio - 15 min: admite (apertura = instante de la insercion, anterior a la llamada)
    SET @s = NEWID(); SET @n += 1;
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@s, N'CULM1-VEN02 apertura', @n, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
            DATEADD(MINUTE, 15, SYSUTCDATETIME()), DATEADD(HOUR, 2, SYSUTCDATETIME()), N'UTC_V2');
    SET @corr = NEWID();
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @s, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT,
        @toleranciaMinutos = @tol, @margenMinutos = @margen;
    IF @e <> 1
        THROW 57020, 'TEST FAILED CULM001_B1_VEN_02: inicio - 15 min debe admitir con tolerancia 15.', 1;
    -- La misma sesion sin tolerancia sigue cerrada (SES_007)
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @s, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT;
    IF @e <> 0 OR @t NOT LIKE N'DBCODE=SES[_]007|%'
        THROW 57021, 'TEST FAILED CULM001_B1_VEN_02: sin tolerancia la misma sesion debe seguir en SES_007.', 1;

    -- inicio - 15 min - 3 s: SES_007 con la tolerancia y margen aplicados en el mensaje tecnico
    SET @s = NEWID(); SET @n += 1;
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@s, N'CULM1-VEN02 antes apertura', @n, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
            DATEADD(SECOND, 15 * 60 + 3, SYSUTCDATETIME()), DATEADD(HOUR, 2, SYSUTCDATETIME()), N'UTC_V2');
    SET @corr = NEWID();
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @s, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT,
        @toleranciaMinutos = @tol, @margenMinutos = @margen;
    IF @e <> 0 OR @t NOT LIKE N'DBCODE=SES[_]007|%' OR @t NOT LIKE N'%Tolerancia: 15 min; margen: 30 min.%'
        THROW 57022, 'TEST FAILED CULM001_B1_VEN_02: antes de inicio - 15 min debe ser SES_007 con tolerancia y margen en el mensaje tecnico.', 1;

    -- fin + 30 min - 3 s: admite
    SET @s = NEWID(); SET @n += 1;
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@s, N'CULM1-VEN02 margen', @n, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
            DATEADD(HOUR, -3, SYSUTCDATETIME()), DATEADD(SECOND, -(30 * 60) + 3, SYSUTCDATETIME()), N'UTC_V2');
    SET @corr = NEWID();
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @s, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT,
        @toleranciaMinutos = @tol, @margenMinutos = @margen;
    IF @e <> 1
        THROW 57023, 'TEST FAILED CULM001_B1_VEN_02: fin + 30 min - 3 s debe admitir con margen 30.', 1;
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @s, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT;
    IF @e <> 0 OR @t NOT LIKE N'DBCODE=SES[_]008|%'
        THROW 57024, 'TEST FAILED CULM001_B1_VEN_02: sin margen la misma sesion debe estar cerrada (SES_008).', 1;

    -- fin + 30 min exacto: SES_008
    SET @s = NEWID(); SET @n += 1;
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@s, N'CULM1-VEN02 cierre', @n, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
            DATEADD(HOUR, -3, SYSUTCDATETIME()), DATEADD(MINUTE, -30, SYSUTCDATETIME()), N'UTC_V2');
    SET @corr = NEWID();
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @s, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT,
        @toleranciaMinutos = @tol, @margenMinutos = @margen;
    IF @e <> 0 OR @t NOT LIKE N'DBCODE=SES[_]008|%' OR @t NOT LIKE N'%Tolerancia: 15 min; margen: 30 min.%'
        THROW 57025, 'TEST FAILED CULM001_B1_VEN_02: fin + 30 min exacto debe ser SES_008 con tolerancia y margen en el mensaje tecnico.', 1;
    PRINT 'TEST_PASS:CULM001_B1_VEN_02_CON_TOLERANCIA';

    -- ------------------------------------------------------------------------------------------------------------
    -- B1-VEN-03: tolerancia/margen NULL o negativos = 0
    -- ------------------------------------------------------------------------------------------------------------
    SET @s = NEWID(); SET @n += 1;
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@s, N'CULM1-VEN03 antes', @n, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
            DATEADD(SECOND, 3, SYSUTCDATETIME()), DATEADD(HOUR, 2, SYSUTCDATETIME()), N'UTC_V2');
    SET @corr = NEWID();
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @s, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT,
        @toleranciaMinutos = -10, @margenMinutos = -10;
    IF @e <> 0 OR @t NOT LIKE N'DBCODE=SES[_]007|%'
        THROW 57030, 'TEST FAILED CULM001_B1_VEN_03: una tolerancia negativa debe tratarse como 0 (SES_007).', 1;
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @s, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT,
        @toleranciaMinutos = NULL, @margenMinutos = NULL;
    IF @e <> 0 OR @t NOT LIKE N'DBCODE=SES[_]007|%'
        THROW 57031, 'TEST FAILED CULM001_B1_VEN_03: una tolerancia NULL debe tratarse como 0 (SES_007).', 1;

    SET @s = NEWID(); SET @n += 1;
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@s, N'CULM1-VEN03 fin', @n, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
            DATEADD(HOUR, -2, SYSUTCDATETIME()), SYSUTCDATETIME(), N'UTC_V2');
    SET @corr = NEWID();
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @s, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT,
        @toleranciaMinutos = -1, @margenMinutos = -1;
    IF @e <> 0 OR @t NOT LIKE N'DBCODE=SES[_]008|%'
        THROW 57032, 'TEST FAILED CULM001_B1_VEN_03: un margen negativo debe tratarse como 0 (SES_008).', 1;
    PRINT 'TEST_PASS:CULM001_B1_VEN_03_NULL_NEGATIVO_ES_CERO';

    -- ------------------------------------------------------------------------------------------------------------
    -- B1-VEN-04: sesion cancelada => SES_010 con y sin tolerancia (validacion previa a la ventana)
    -- ------------------------------------------------------------------------------------------------------------
    DECLARE @sCancel UNIQUEIDENTIFIER = NEWID();
    SET @n += 1;
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sCancel, N'CULM1-VEN04 cancelada', @n, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
            DATEADD(HOUR, -1, SYSUTCDATETIME()), DATEADD(HOUR, 1, SYSUTCDATETIME()), N'UTC_V2');
    INSERT dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, idCorrelacion)
    VALUES (@sCancel, @tipoDocente, N'CULM1 motivo de prueba de cancelacion', NULL, @owner, NEWID());
    SET @corr = NEWID();
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @sCancel, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_010', @p_param1 = @sCancel, @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    IF @e <> 0 OR @t NOT LIKE N'DBCODE=SES[_]010|%' OR @u <> @userMsg OR @userMsg LIKE N'Mensaje de usuario no configurado%'
        THROW 57040, 'TEST FAILED CULM001_B1_VEN_04: una sesion cancelada en curso debe rechazarse con SES_010 (sin tolerancia).', 1;
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @sCancel, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT,
        @toleranciaMinutos = @tol, @margenMinutos = @margen;
    IF @e <> 0 OR @t NOT LIKE N'DBCODE=SES[_]010|%'
        THROW 57041, 'TEST FAILED CULM001_B1_VEN_04: una sesion cancelada debe rechazarse con SES_010 (con tolerancia).', 1;
    PRINT 'TEST_PASS:CULM001_B1_VEN_04_CANCELADA_SES010';

    -- El lote congelado sobre la sesion cancelada: SES_010 y sin escrituras. El SP revierte su savepoint (prohibido
    -- dentro de INSERT ... EXEC): la fila canonica la verifica test_summary.ps1 (TEST_RESULT_BEGIN/END).
    DECLARE @json NVARCHAR(MAX) = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":"AN"}]');
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_010', @p_param1 = @sCancel, @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:CULM001_B1_VEN_04_LOTE_CONGELADO|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:CULM001_B1_VEN_04_LOTE_CONGELADO|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:CULM001_B1_VEN_04_LOTE_CONGELADO';
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sCancel, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    PRINT 'TEST_RESULT_END:CULM001_B1_VEN_04_LOTE_CONGELADO';
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sCancel) OR @@TRANCOUNT <> @tranBefore
        THROW 57042, 'TEST FAILED CULM001_B1_VEN_04: el lote congelado escribio asistencia en una sesion cancelada.', 1;
    PRINT 'TEST_STATE_PASS:CULM001_B1_VEN_04_LOTE_CONGELADO';

    -- ------------------------------------------------------------------------------------------------------------
    -- B1-VEN-05: procedencia NULL => SES_009 antes que la tolerancia
    -- ------------------------------------------------------------------------------------------------------------
    SET @s = NEWID(); SET @n += 1;
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@s, N'CULM1-VEN05 indeterminada', @n, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
            DATEADD(MINUTE, 5, SYSUTCDATETIME()), DATEADD(HOUR, 2, SYSUTCDATETIME()), NULL);
    SET @corr = NEWID();
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @s, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT,
        @toleranciaMinutos = @tol, @margenMinutos = @margen;
    IF @e <> 0 OR @t NOT LIKE N'DBCODE=SES[_]009|%'
        THROW 57050, 'TEST FAILED CULM001_B1_VEN_05: procedencia NULL debe responder SES_009 aunque la tolerancia la admitiera.', 1;
    PRINT 'TEST_PASS:CULM001_B1_VEN_05_PROCEDENCIA_ANTES_QUE_TOLERANCIA';

    -- La lectura de la ventana con tolerancia sigue reteniendo el bloqueo de actualizacion sobre dbo.Sesion
    -- (sobre una sesion existente: las creadas en esta transaccion ya tienen bloqueo exclusivo)
    SET @corr = NEWID();
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @existingSession, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT,
        @toleranciaMinutos = @tol, @margenMinutos = @margen;
    IF NOT EXISTS (
        SELECT 1 FROM sys.dm_tran_locks l
        JOIN sys.partitions p ON p.hobt_id = l.resource_associated_entity_id
        WHERE l.request_session_id = @@SPID AND l.resource_type = 'KEY'
          AND p.object_id = OBJECT_ID('dbo.Sesion') AND l.request_mode IN ('U', 'RangeS-U'))
        THROW 57051, 'TEST FAILED CULM001_B1_VEN_LOCK: la validacion con tolerancia no retuvo el bloqueo sobre dbo.Sesion.', 1;
    PRINT 'TEST_PASS:CULM001_B1_VEN_LOCK_HELD';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 57099, 'TEST FAILED CULM001_B1_VEN: quedaron transacciones abiertas.', 1;
PRINT 'TEST_PASS:CULM001_B1_VEN_TRANCOUNT_ZERO';
PRINT 'TEST END: test_culm001_b1_ventana_tolerancia';
GO
