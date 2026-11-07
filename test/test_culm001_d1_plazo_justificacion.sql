USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- CULM-001 D.1 (CONTRACT §2.2, HU026B): plazo de excusas D1-01 .. D1-10 y D1-12 (D1-11, up/down/up de la migracion 20,
-- esta en test_culm001_d1_migraciones.sql). Cada caso corre dentro de UNA transaccion con ROLLBACK final: no deja datos.
-- Las sesiones se construyen relativas a la fecha LOCAL de hoy (TIEMPO/ZONA_HORARIA_SQLSERVER) para que la prueba no
-- dependa del dia en que corre. N = ASISTENCIA/DIAS_LIMITE_JUSTIFICACION (5 en la semilla).
--   limite (exclusivo) = medianoche local del dia  fecha-local-de-fin + N + 1
-- ============================================================================
IF OBJECT_ID('tempdb..#d1_expect') IS NOT NULL DROP PROCEDURE #d1_expect;
GO
CREATE PROCEDURE #d1_expect @label VARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT('TEST FAILED: CULM001_D1_', @label);
        THROW 52300, @mensaje, 1;
    END
END;
GO

DECLARE @tz NVARCHAR(128) = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));
DECLARE @n INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION');
DECLARE @hoyLocal DATE = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE @tz AS DATE);
DECLARE @codInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

DECLARE @group UNIQUEIDENTIFIER, @group2 UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER;
DECLARE @studentA UNIQUEIDENTIFIER, @studentC UNIQUEIDENTIFIER, @userA UNIQUEIDENTIFIER, @userC UNIQUEIDENTIFIER, @userT UNIQUEIDENTIFIER;
DECLARE @asignatura UNIQUEIDENTIFIER;

-- Estudiante A: inscrito en @group y con TODAS sus matriculas de esa asignatura inscritas (para la paridad D1-10).
SELECT TOP 1 @group = g.id, @teacher = g.docente, @asignatura = ug.idAsignatura, @studentA = eg.idEstudiante
FROM dbo.Grupo g
INNER JOIN dbo.uv_grupo ug ON ug.id = g.id
INNER JOIN dbo.uv_estudiante_grupo eg ON eg.idGrupo = g.id AND eg.codigoEstadoEstudiante = @codInscrita
WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo x INNER JOIN dbo.uv_grupo gx ON gx.id = x.idGrupo
                  WHERE x.idEstudiante = eg.idEstudiante AND gx.idAsignatura = ug.idAsignatura AND x.codigoEstadoEstudiante <> @codInscrita)
ORDER BY g.id, eg.idEstudiante;
SELECT TOP 1 @group2 = eg.idGrupo, @studentC = eg.idEstudiante
FROM dbo.uv_estudiante_grupo eg
WHERE eg.idGrupo <> @group AND eg.codigoEstadoEstudiante = @codInscrita
  AND NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo y WHERE y.idGrupo = @group AND y.idEstudiante = eg.idEstudiante)
ORDER BY eg.idGrupo, eg.idEstudiante;
SELECT @userA = usuario FROM dbo.Estudiante WHERE id = @studentA;
SELECT @userC = usuario FROM dbo.Estudiante WHERE id = @studentC;
SELECT @userT = usuario FROM dbo.Docente WHERE id = @teacher;

IF @group IS NULL OR @group2 IS NULL OR @studentA IS NULL OR @studentC IS NULL OR @userA IS NULL OR @userC IS NULL OR @userT IS NULL
   OR @tz IS NULL OR @tz = N'' OR @n IS NULL OR @n < 0
    THROW 52301, 'TEST FAILED: CULM001_D1 fixture o parametros faltantes (semilla local).', 1;

-- Finales de sesion (UTC) construidos desde la fecha local de hoy.
DECLARE @finDentro DATETIME2(7)  = CAST(CAST(DATEADD(HOUR, 12, CAST(DATEADD(DAY, -@n, @hoyLocal) AS DATETIME2(7))) AS DATETIME2(7)) AT TIME ZONE @tz AT TIME ZONE 'UTC' AS DATETIME2(7));
DECLARE @finNoche  DATETIME2(7)  = CAST(CAST(DATEADD(MINUTE, 23 * 60 + 30, CAST(DATEADD(DAY, -@n, @hoyLocal) AS DATETIME2(7))) AS DATETIME2(7)) AT TIME ZONE @tz AT TIME ZONE 'UTC' AS DATETIME2(7));
DECLARE @finVencida DATETIME2(7) = CAST(CAST(DATEADD(HOUR, 12, CAST(DATEADD(DAY, -(@n + 1), @hoyLocal) AS DATETIME2(7))) AS DATETIME2(7)) AT TIME ZONE @tz AT TIME ZONE 'UTC' AS DATETIME2(7));
DECLARE @finReciente DATETIME2(7) = DATEADD(DAY, -2, SYSUTCDATETIME());

DECLARE @sDentro UNIQUEIDENTIFIER = NEWID(), @sNoche UNIQUEIDENTIFIER = NEWID(), @sVencida UNIQUEIDENTIFIER = NEWID(),
        @sReciente UNIQUEIDENTIFIER = NEWID(), @sAjena UNIQUEIDENTIFIER = NEWID(), @sCancelada UNIQUEIDENTIFIER = NEWID(),
        @sVencida2 UNIQUEIDENTIFIER = NEWID(), @sIdem UNIQUEIDENTIFIER = NEWID();
DECLARE @num INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
DECLARE @num2 INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group2);

DECLARE @corr UNIQUEIDENTIFIER, @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000), @ok BIT, @filasAntes INT, @filasDespues INT;
DECLARE @file1 UNIQUEIDENTIFIER = NEWID(), @fileIdem UNIQUEIDENTIFIER = NEWID();
DECLARE @sha1 CHAR(64) = LOWER(CONVERT(CHAR(64), HASHBYTES('SHA2_256', 'culm001-d1-1'), 2));
DECLARE @shaI CHAR(64) = LOWER(CONVERT(CHAR(64), HASHBYTES('SHA2_256', 'culm001-d1-i'), 2));
DECLARE @tcCancel UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoCancelacionSesion WHERE esAutomatica = 0 ORDER BY id);
DECLARE @errNum INT, @errMsg NVARCHAR(4000), @idInscrita UNIQUEIDENTIFIER;
DECLARE @limite DATETIME2(7), @esperado DATETIME2(7);

CREATE TABLE #w (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX),
    mensajeTecnicoResultado NVARCHAR(MAX), estadoResultado INT NOT NULL);
CREATE TABLE #sm (id UNIQUEIDENTIFIER, nombre NVARCHAR(250), numero INT, codigo NVARCHAR(50), numeroSemana INT,
    idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(100), fechaHoraInicio DATETIME2(7), fechaHoraFin DATETIME2(7),
    fechaLimiteJustificacionUtc DATETIME2(7), plazoJustificacionVigente BIT, totalRegistros INT);
CREATE TABLE #esp (id UNIQUEIDENTIFIER, nombre NVARCHAR(250), numero INT, codigo NVARCHAR(50), numeroSemana INT,
    idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(100), fechaHoraInicio DATETIME2(7), fechaHoraFin DATETIME2(7));

BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin) VALUES
        (@sDentro,    N'QA D1 dentro',      @num,     LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finDentro),   @finDentro),
        (@sNoche,     N'QA D1 noche',       @num + 1, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finNoche),    @finNoche),
        (@sVencida,   N'QA D1 vencida',     @num + 2, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finVencida),  @finVencida),
        (@sReciente,  N'QA D1 reciente',    @num + 3, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finReciente), @finReciente),
        (@sCancelada, N'QA D1 cancelada',   @num + 4, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finReciente), @finReciente),
        (@sVencida2,  N'QA D1 vencida 2',   @num + 5, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finVencida),  @finVencida),
        (@sIdem,      N'QA D1 idempotente', @num + 6, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finDentro),   @finDentro);
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin) VALUES
        (@sAjena, N'QA D1 ajena', @num2, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group2, DATEADD(HOUR, -1, @finVencida), @finVencida);

    -- ---------------------------------------------------------------- D1-07 funcion (ejemplo de §0 [SUPUESTO-D-01])
    -- Fin 2026-11-04 08:00 Bogota (13:00 UTC), N = 5 => limite 2026-11-10 00:00 Bogota (05:00 UTC). A las 23:30 locales
    -- (2026-11-05 04:30 UTC) y a las 21:00 locales (2026-11-05 02:00 UTC) el dia local es el mismo => mismo limite.
    EXEC sys.sp_executesql N'SELECT @r = dbo.ufn_calcular_fecha_limite_justificacion(@fin)', N'@fin DATETIME2(7), @r DATETIME2(7) OUTPUT',
        @fin = '2026-11-04T13:00:00', @r = @limite OUTPUT;
    SET @esperado = CAST(CAST(DATEADD(DAY, @n + 1, CAST('2026-11-04' AS DATETIME2(7))) AS DATETIME2(7)) AT TIME ZONE @tz AT TIME ZONE 'UTC' AS DATETIME2(7));
    SET @ok = IIF(@limite = @esperado AND (@n <> 5 OR @limite = '2026-11-10T05:00:00'), 1, 0);
    EXEC #d1_expect 'D1_07_FUNCION_EJEMPLO', @ok;
    EXEC sys.sp_executesql N'SELECT @r = dbo.ufn_calcular_fecha_limite_justificacion(@fin)', N'@fin DATETIME2(7), @r DATETIME2(7) OUTPUT',
        @fin = '2026-11-05T04:30:00', @r = @limite OUTPUT;
    SET @ok = IIF(@limite = @esperado, 1, 0);
    EXEC #d1_expect 'D1_07_FIN_23_30_LOCALES', @ok;
    EXEC sys.sp_executesql N'SELECT @r = dbo.ufn_calcular_fecha_limite_justificacion(@fin)', N'@fin DATETIME2(7), @r DATETIME2(7) OUTPUT',
        @fin = '2026-11-05T02:00:00', @r = @limite OUTPUT;
    SET @ok = IIF(@limite = @esperado, 1, 0);
    EXEC #d1_expect 'D1_07_FIN_21_00_LOCALES', @ok;
    SET @limite = '2000-01-01';
    EXEC sys.sp_executesql N'SELECT @r = dbo.ufn_calcular_fecha_limite_justificacion(@fin)', N'@fin DATETIME2(7), @r DATETIME2(7) OUTPUT',
        @fin = NULL, @r = @limite OUTPUT;
    SET @ok = IIF(@limite IS NULL, 1, 0);
    EXEC #d1_expect 'D1_07_FIN_NULO_DA_NULO', @ok;
    PRINT 'TEST_PASS:CULM001_D1_07_FUNCION';

    -- ---------------------------------------------------------------- D1-01 falta reciente: se admite
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @sReciente,
        @categoria = N'ASISTENCIA', @justificacion = N'QA D1-01', @idArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE idCorrelacion = @corr AND estadoResultado = 1)
                  AND EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia r INNER JOIN dbo.Asistencia a ON a.id = r.asistencia
                              WHERE a.sesion = @sReciente AND r.justificacionSolicitud = N'QA D1-01'), 1, 0);
    EXEC #d1_expect 'D1_01_RECIENTE_ADMITIDA', @ok;
    PRINT 'TEST_PASS:CULM001_D1_01_RECIENTE';

    -- ---------------------------------------------------------------- D1-02 / D1-07: ultimo dia del plazo (12:00 y 23:30 locales)
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @sDentro,
        @categoria = N'ASISTENCIA', @justificacion = N'QA D1-02', @idArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE idCorrelacion = @corr AND estadoResultado = 1), 1, 0);
    EXEC #d1_expect 'D1_02_ULTIMO_DIA_SE_ADMITE', @ok;
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @sNoche,
        @categoria = N'ASISTENCIA', @justificacion = N'QA D1-07', @idArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE idCorrelacion = @corr AND estadoResultado = 1), 1, 0);
    EXEC #d1_expect 'D1_07_FIN_23_30_SE_ADMITE_EL_ULTIMO_DIA', @ok;
    PRINT 'TEST_PASS:CULM001_D1_02_ULTIMO_DIA';

    -- ---------------------------------------------------------------- D1-03 vencida: REV_020, sin escrituras, soporte sigue DRAFT
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte = @file1, @nombreOriginal = N'evidencia.pdf',
        @tipoContenido = 'application/pdf', @tamanioBytes = 1234, @checksumSha256 = @sha1, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SELECT @filasAntes = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @sVencida,
        @categoria = N'ASISTENCIA', @justificacion = N'QA D1-03', @idArchivoSoporte = @file1, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SELECT @filasDespues = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE idCorrelacion = @corr AND estadoResultado = 0
                          AND mensajeUsuarioResultado LIKE N'El plazo para justificar esta inasistencia venci%')
                  AND @filasAntes = @filasDespues
                  AND NOT EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @file1 AND estado = 'ATTACHED')
                  AND EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @file1 AND estado = 'DRAFT' AND solicitudRevisionAsistencia IS NULL)
                  AND @@TRANCOUNT = 1, 1, 0);
    EXEC #d1_expect 'D1_03_VENCIDA_REV_020_SIN_ESCRITURAS', @ok;
    PRINT 'TEST_PASS:CULM001_D1_03_VENCIDA';

    -- ---------------------------------------------------------------- D1-04 el parametro manda: N = 1 vence la sesion de hace N dias
    UPDATE dbo.CatalogoParametro SET valor = N'1' WHERE grupo = 'ASISTENCIA' AND clave = 'DIAS_LIMITE_JUSTIFICACION';
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @sIdem,
        @categoria = N'ASISTENCIA', @justificacion = N'QA D1-04', @idArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SET @ok = IIF(@n <= 1 OR EXISTS (SELECT 1 FROM #w WHERE idCorrelacion = @corr AND estadoResultado = 0
                          AND mensajeUsuarioResultado LIKE N'El plazo para justificar esta inasistencia venci%'), 1, 0);
    EXEC #d1_expect 'D1_04_PARAMETRO_EN_1_VENCE', @ok;
    UPDATE dbo.CatalogoParametro SET valor = CAST(@n AS NVARCHAR(20)) WHERE grupo = 'ASISTENCIA' AND clave = 'DIAS_LIMITE_JUSTIFICACION';
    PRINT 'TEST_PASS:CULM001_D1_04_PARAMETRO';

    -- ---------------------------------------------------------------- D1-05 la v1 aplica el mismo plazo
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia @idEstudiante = @studentA, @idSesion = @sVencida2,
        @categoria = N'ASISTENCIA', @justificacion = N'QA D1-05', @soporteNombre = NULL, @soporteUrl = NULL,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE idCorrelacion = @corr AND estadoResultado = 0
                          AND mensajeUsuarioResultado LIKE N'El plazo para justificar esta inasistencia venci%')
                  AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia r INNER JOIN dbo.Asistencia a ON a.id = r.asistencia
                                  WHERE a.sesion = @sVencida2), 1, 0);
    EXEC #d1_expect 'D1_05_V1_VENCIDA_REV_020', @ok;
    PRINT 'TEST_PASS:CULM001_D1_05_V1';

    -- ---------------------------------------------------------------- D1-06 sesion ajena y vencida: error de propiedad, no REV_020
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @sAjena,
        @categoria = N'ASISTENCIA', @justificacion = N'QA D1-06', @idArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE idCorrelacion = @corr AND estadoResultado = 0
                          AND mensajeUsuarioResultado NOT LIKE N'El plazo para justificar esta inasistencia venci%'), 1, 0);
    EXEC #d1_expect 'D1_06_AJENA_NO_ES_REV_020', @ok;
    PRINT 'TEST_PASS:CULM001_D1_06_PROPIEDAD_ANTES_QUE_PLAZO';

    -- ---------------------------------------------------------------- D1-08 parametro ausente: REV_025, sin escritura
    UPDATE dbo.CatalogoParametro SET valor = N'', valorDefecto = N'' WHERE grupo = 'ASISTENCIA' AND clave = 'DIAS_LIMITE_JUSTIFICACION';
    SELECT @filasAntes = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @sIdem,
        @categoria = N'ASISTENCIA', @justificacion = N'QA D1-08', @idArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SELECT @filasDespues = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE idCorrelacion = @corr AND estadoResultado = 0
                          AND mensajeUsuarioResultado LIKE N'No es posible validar el plazo de justificaci%')
                  AND @filasAntes = @filasDespues, 1, 0);
    EXEC #d1_expect 'D1_08_PARAMETRO_AUSENTE_REV_025', @ok;
    UPDATE dbo.CatalogoParametro SET valor = CAST(@n AS NVARCHAR(20)), valorDefecto = CAST(@n AS NVARCHAR(20))
    WHERE grupo = 'ASISTENCIA' AND clave = 'DIAS_LIMITE_JUSTIFICACION';
    PRINT 'TEST_PASS:CULM001_D1_08_PARAMETRO_AUSENTE';

    -- ---------------------------------------------------------------- D1-09 fecha de radicacion en hora local, no UTC
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM sys.sql_modules
                              WHERE object_id IN (OBJECT_ID('dbo.usp_radicar_solicitud_revision_asistencia_v2'), OBJECT_ID('dbo.usp_radicar_solicitud_revision_asistencia'))
                                AND definition LIKE N'%CAST(CURRENT_TIMESTAMP AS DATE)%')
                  AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia r INNER JOIN dbo.Asistencia a ON a.id = r.asistencia
                                  WHERE a.sesion = @sReciente AND r.justificacionSolicitud = N'QA D1-01' AND r.fecha <> @hoyLocal), 1, 0);
    EXEC #d1_expect 'D1_09_FECHA_RADICACION_LOCAL', @ok;
    PRINT 'TEST_PASS:CULM001_D1_09_FECHA_LOCAL';

    -- ---------------------------------------------------------------- D1-12 reintento tras el vencimiento: exito idempotente
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte = @fileIdem, @nombreOriginal = N'evidencia.pdf',
        @tipoContenido = 'application/pdf', @tamanioBytes = 1234, @checksumSha256 = @shaI, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @sIdem,
        @categoria = N'ASISTENCIA', @justificacion = N'QA D1-12', @idArchivoSoporte = @fileIdem, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE idCorrelacion = @corr AND estadoResultado = 1), 1, 0);
    EXEC #d1_expect 'D1_12_PRIMER_ENVIO_EXITOSO', @ok;
    SELECT @filasAntes = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    -- Se vence el plazo moviendo la sesion al pasado (el limite pasa a ser anterior a ahora).
    UPDATE dbo.Sesion SET fechaHoraInicio = DATEADD(DAY, -60, fechaHoraInicio), fechaHoraFin = DATEADD(DAY, -60, fechaHoraFin) WHERE id = @sIdem;
    TRUNCATE TABLE #w;
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @sIdem,
        @categoria = N'ASISTENCIA', @justificacion = N'QA D1-12', @idArchivoSoporte = @fileIdem, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SELECT @filasDespues = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE idCorrelacion = @corr AND estadoResultado = 1) AND @filasAntes = @filasDespues, 1, 0);
    EXEC #d1_expect 'D1_12_REINTENTO_VENCIDO_ES_IDEMPOTENTE', @ok;
    PRINT 'TEST_PASS:CULM001_D1_12_REINTENTO_IDEMPOTENTE';

    -- ---------------------------------------------------------------- D1-10 usp_consultar_sesiones_materia_estudiante
    -- (a) paridad con la HQL actual (uv_sesion x uv_estudiante_grupo x uv_grupo) con matriculas inscritas
    INSERT INTO #esp (id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin)
    SELECT s.id, s.nombre, s.numero, s.codigo, s.numeroSemana, s.idGrupo, s.codigoGrupo, s.nombreGrupo, s.fechaHoraInicio, s.fechaHoraFin
    FROM dbo.uv_sesion s
    INNER JOIN dbo.uv_estudiante_grupo eg ON eg.idGrupo = s.idGrupo
    INNER JOIN dbo.uv_grupo g ON g.id = s.idGrupo
    WHERE eg.idEstudiante = @studentA AND g.idAsignatura = @asignatura;
    SET @corr = NEWID();
    INSERT INTO #sm EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @userA, @idCorrelacion = @corr,
        @idMateria = @asignatura, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF((SELECT COUNT(*) FROM #esp) >= 7
                  AND (SELECT COUNT(*) FROM #sm) = (SELECT COUNT(*) FROM #esp)
                  AND NOT EXISTS (SELECT id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin FROM #esp
                                  EXCEPT SELECT id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin FROM #sm)
                  AND NOT EXISTS (SELECT id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin FROM #sm
                                  EXCEPT SELECT id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin FROM #esp)
                  AND NOT EXISTS (SELECT 1 FROM #sm WHERE totalRegistros <> (SELECT COUNT(*) FROM #esp)), 1, 0);
    EXEC #d1_expect 'D1_10_PARIDAD_CON_LA_HQL', @ok;
    -- columnas nuevas: limite = funcion; vigente solo dentro del plazo
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #sm m INNER JOIN dbo.Sesion s ON s.id = m.id
                              WHERE m.fechaLimiteJustificacionUtc IS NULL OR m.fechaLimiteJustificacionUtc <> dbo.ufn_calcular_fecha_limite_justificacion(s.fechaHoraFin))
                  AND (SELECT plazoJustificacionVigente FROM #sm WHERE id = @sReciente) = 1
                  AND (SELECT plazoJustificacionVigente FROM #sm WHERE id = @sDentro) = 1
                  AND (SELECT plazoJustificacionVigente FROM #sm WHERE id = @sVencida) = 0
                  AND (SELECT plazoJustificacionVigente FROM #sm WHERE id = @sIdem) = 0, 1, 0);
    EXEC #d1_expect 'D1_10_COLUMNAS_DE_PLAZO', @ok;
    -- (b) sesion cancelada: nunca tiene plazo vigente
    INSERT dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, usuarioEjecutor, idCorrelacion)
    VALUES (@sCancelada, @tcCancel, N'QA D1 cancelada', @userT, NEWID());
    TRUNCATE TABLE #sm;
    SET @corr = NEWID();
    INSERT INTO #sm EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @userA, @idCorrelacion = @corr,
        @idMateria = @asignatura, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF((SELECT plazoJustificacionVigente FROM #sm WHERE id = @sCancelada) = 0
                  AND (SELECT plazoJustificacionVigente FROM #sm WHERE id = @sReciente) = 1, 1, 0);
    EXEC #d1_expect 'D1_10_CANCELADA_SIN_PLAZO_VIGENTE', @ok;
    -- (c) materia ajena: 0 filas
    TRUNCATE TABLE #sm;
    SET @corr = NEWID();
    INSERT INTO #sm EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @userA, @idCorrelacion = @corr,
        @idMateria = @sAjena, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #sm), 1, 0);
    EXEC #d1_expect 'D1_10_MATERIA_AJENA_CERO_FILAS', @ok;
    -- (d) paginacion: la segunda pagina de 3 trae las filas 4..6 y el total completo
    TRUNCATE TABLE #sm;
    SET @corr = NEWID();
    INSERT INTO #sm EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @userA, @idCorrelacion = @corr,
        @idMateria = @asignatura, @numeroPagina = 2, @tamanoPagina = 3;
    SET @ok = IIF((SELECT COUNT(*) FROM #sm) = 3 AND NOT EXISTS (SELECT 1 FROM #sm WHERE totalRegistros <> (SELECT COUNT(*) FROM #esp)), 1, 0);
    EXEC #d1_expect 'D1_10_PAGINACION_Y_TOTAL', @ok;
    -- (e) paginacion invalida: PAG_001 (THROW 51000)
    SET @errNum = NULL;
    BEGIN TRY
        SET @corr = NEWID();
        INSERT INTO #sm EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @userA, @idCorrelacion = @corr,
            @idMateria = @asignatura, @numeroPagina = 1, @tamanoPagina = 0;
    END TRY
    BEGIN CATCH
        SET @errNum = ERROR_NUMBER();
        SET @errMsg = ERROR_MESSAGE();
    END CATCH
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = N'1', @p_param2 = N'0',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    SET @ok = IIF(@errNum = 51000 AND @errMsg = @techMsg, 1, 0);
    EXEC #d1_expect 'D1_10_PAGINACION_INVALIDA_PAG_001', @ok;
    -- (f) un docente no es estudiante: THROW 51000
    SET @errNum = NULL;
    BEGIN TRY
        SET @corr = NEWID();
        INSERT INTO #sm EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
            @idMateria = @asignatura, @numeroPagina = 1, @tamanoPagina = 100;
    END TRY
    BEGIN CATCH
        SET @errNum = ERROR_NUMBER();
    END CATCH
    SET @ok = IIF(@errNum = 51000, 1, 0);
    EXEC #d1_expect 'D1_10_NO_ESTUDIANTE_RECHAZADO', @ok;
    -- (g) matricula inactiva (I) o cancelada por inasistencia (CI): 0 filas (cambio intencional, DEC-022 §3)
    TRUNCATE TABLE #sm;
    SELECT @idInscrita = eg.id FROM dbo.EstudianteGrupo eg WHERE eg.estudiante = @studentA AND eg.grupo = @group;
    UPDATE dbo.EstudianteGrupo SET estado = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'I') WHERE id = @idInscrita;
    SET @corr = NEWID();
    INSERT INTO #sm EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @userA, @idCorrelacion = @corr,
        @idMateria = @asignatura, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #sm), 1, 0);
    EXEC #d1_expect 'D1_10_MATRICULA_I_CERO_FILAS', @ok;
    UPDATE dbo.EstudianteGrupo SET estado = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'CI') WHERE id = @idInscrita;
    SET @corr = NEWID();
    INSERT INTO #sm EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @userA, @idCorrelacion = @corr,
        @idMateria = @asignatura, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #sm), 1, 0);
    EXEC #d1_expect 'D1_10_MATRICULA_CI_CERO_FILAS', @ok;
    PRINT 'TEST_PASS:CULM001_D1_10_SESIONES_MATERIA_ESTUDIANTE';

    -- ---------------------------------------------------------------- permisos de minimo privilegio (D1-SEG)
    SET @ok = IIF(EXISTS (SELECT 1 FROM sys.database_permissions dp
                          WHERE dp.major_id = OBJECT_ID(N'dbo.usp_consultar_sesiones_materia_estudiante') AND dp.permission_name = N'EXECUTE'
                            AND dp.state IN ('G', 'W') AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime'))
                  AND NOT EXISTS (SELECT 1 FROM sys.database_permissions dp
                          WHERE dp.major_id = OBJECT_ID(N'dbo.usp_internal_validar_plazo_justificacion')
                            AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime'))
                  AND OBJECT_ID(N'dbo.usp_internal_validar_plazo_justificacion', N'P') IS NOT NULL, 1, 0);
    EXEC #d1_expect 'D1_SEG_PERMISOS', @ok;
    PRINT 'TEST_PASS:CULM001_D1_SEG_PERMISOS';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    DECLARE @fallo NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' (linea ', ERROR_LINE(), N')');
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #w; DROP TABLE IF EXISTS #sm; DROP TABLE IF EXISTS #esp;
    THROW 52302, @fallo, 1;
END CATCH
IF OBJECT_ID('tempdb..#w') IS NOT NULL DROP TABLE #w;
IF OBJECT_ID('tempdb..#sm') IS NOT NULL DROP TABLE #sm;
IF OBJECT_ID('tempdb..#esp') IS NOT NULL DROP TABLE #esp;
GO

-- ---------------------------------------------------------------- D1-03 (autocommit): el rechazo no deja transacciones abiertas
-- Con una sesion historica de la semilla (fuera de plazo) y fuera de toda transaccion de la prueba: REV_020 y @@TRANCOUNT = 0.
DECLARE @codIns NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
DECLARE @sx UNIQUEIDENTIFIER, @ex UNIQUEIDENTIFIER, @ux UNIQUEIDENTIFIER, @cx UNIQUEIDENTIFIER = NEWID();
SELECT TOP 1 @sx = s.id, @ex = eg.idEstudiante, @ux = e.usuario
FROM dbo.Sesion s
INNER JOIN dbo.uv_estudiante_grupo eg ON eg.idGrupo = s.grupo AND eg.codigoEstadoEstudiante = @codIns
INNER JOIN dbo.Estudiante e ON e.id = eg.idEstudiante
WHERE s.fechaHoraFin < DATEADD(DAY, -60, SYSUTCDATETIME())
ORDER BY s.id, eg.idEstudiante;
IF @sx IS NULL
    THROW 52305, 'TEST FAILED: CULM001_D1_03_AUTOCOMMIT fixture ausente: la semilla local no tiene una sesion historica con estudiante inscrito.', 1;
BEGIN
    -- Sin el validador de plazo, la llamada de abajo radicaria (y confirmaria) una solicitud real: se corta antes.
    IF OBJECT_ID(N'dbo.usp_internal_validar_plazo_justificacion', N'P') IS NULL
        THROW 52304, 'TEST FAILED: CULM001_D1_03_AUTOCOMMIT usp_internal_validar_plazo_justificacion ausente.', 1;
    CREATE TABLE #w2 (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX),
        mensajeTecnicoResultado NVARCHAR(MAX), estadoResultado INT NOT NULL);
    INSERT INTO #w2 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @ex, @idSesion = @sx,
        @categoria = N'ASISTENCIA', @justificacion = N'QA D1-03 autocommit', @idArchivoSoporte = NULL, @idCorrelacion = @cx, @idUsuarioEjecutor = @ux;
    IF NOT (@@TRANCOUNT = 0 AND EXISTS (SELECT 1 FROM #w2 WHERE idCorrelacion = @cx AND estadoResultado = 0
                                        AND mensajeUsuarioResultado LIKE N'El plazo para justificar esta inasistencia venci%')
            AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud = N'QA D1-03 autocommit'))
    BEGIN
        DROP TABLE #w2;
        THROW 52303, 'TEST FAILED: CULM001_D1_03_AUTOCOMMIT_TRANCOUNT_CERO', 1;
    END
    DROP TABLE #w2;
    PRINT 'TEST_PASS:CULM001_D1_03_AUTOCOMMIT';
END
GO
DROP PROCEDURE #d1_expect;
GO
