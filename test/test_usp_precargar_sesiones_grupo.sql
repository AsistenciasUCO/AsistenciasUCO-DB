USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- F2 (2026-11-02): usp_precargar_sesiones_grupo. Crea las sesiones futuras que faltan a partir del horario del grupo, sin
-- duplicar, retira las futuras generadas que ya no encajan (sin tocar las creadas a mano) y respeta el ambito:
-- coordinador del programa o docente titular (SEC_002 si no). Usa un periodo futuro fijo (2098) para ser determinista.
PRINT 'TEST START: test_usp_precargar_sesiones_grupo';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER, @idProg UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER;
SELECT TOP 1 @idAsig = a.id, @idProg = pe.idPrograma
FROM dbo.uv_asignatura a
INNER JOIN dbo.uv_semestre_plan_estudio spe ON a.idSemestrePlanEstudio = spe.id
INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
INNER JOIN dbo.uv_programa pr ON pe.idPrograma = pr.id AND pr.idCoordinador IS NOT NULL;
SELECT @uCoord = ci.idUsuario FROM dbo.uv_programa pr INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = pr.idCoordinador WHERE pr.id = @idProg;
DECLARE @idPeriodoBase UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_periodo_academico ORDER BY anio DESC);
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT institucion FROM dbo.PeriodoAcademico WHERE id = @idPeriodoBase);
DECLARE @tvCat UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'CAT');
IF @tipoCC IS NULL OR @idAsig IS NULL OR @uCoord IS NULL OR @idInstitucion IS NULL OR @tvCat IS NULL
    THROW 53400, 'TEST FAILED: faltan fixtures del seed (asignatura, coordinador, periodo o vinculacion).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uD1 UNIQUEIDENTIFIER = NEWID(), @uD2 UNIQUEIDENTIFIER = NEWID(), @d1 UNIQUEIDENTIFIER = NEWID(), @d2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD1, @tipoCC, 973000001, N'Precarga', N'Uno', N'Pablo', N'Qa', N'qa.precarga.d1@test.local', 1, 1, N'HashBackend_P1'),
           (@uD2, @tipoCC, 973000002, N'Precarga', N'Dos', N'Paula', N'Qa', N'qa.precarga.d2@test.local', 1, 1, N'HashBackend_P2');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d1, @uD1), (@d2, @uD2);
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @d1, @idProg, @tvCat, 1, SYSUTCDATETIME()), (NEWID(), @d2, @idProg, @tvCat, 1, SYSUTCDATETIME());

    -- Periodo futuro fijo (4 semanas) y periodo pasado: las sesiones del pasado no se generan
    DECLARE @idFuturo UNIQUEIDENTIFIER = NEWID(), @idPasado UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@idFuturo, @idInstitucion, N'Periodo QA precarga futuro', 96, '2098-01-06', '2098-01-31', 2098),
           (@idPasado, @idInstitucion, N'Periodo QA precarga pasado', 95, '2020-01-06', '2020-02-28', 2020);

    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @userMsg NVARCHAR(4000);
    DECLARE @base INT = 61000 + ABS(CHECKSUM(NEWID()) % 9000);
    DECLARE @gA UNIQUEIDENTIFIER = NEWID(), @gB UNIQUEIDENTIFIER = NEWID(), @gC UNIQUEIDENTIFIER = NEWID();
    DECLARE @codA INT = @base, @codB INT = @base + 1, @codC INT = @base + 2;

    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gA, @idAsignatura = @idAsig, @idPeriodoAcademico = @idFuturo, @codigo = @codA,
        @nombre = N'Grupo QA Precarga A', @idDocente = @d1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gB, @idAsignatura = @idAsig, @idPeriodoAcademico = @idFuturo, @codigo = @codB,
        @nombre = N'Grupo QA Precarga B', @idDocente = @d1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gC, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPasado, @codigo = @codC,
        @nombre = N'Grupo QA Precarga C', @idDocente = @d1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) <> 3 THROW 53401, 'TEST FAILED: los grupos de prueba debieron crearse.', 1;

    -- Horario de A: lunes y miercoles 08-10. C (periodo pasado) tambien lleva horario.
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gA,
        @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"},{"codigoDia":"MI","horaInicio":"08:00","horaFin":"10:00"}]',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gC,
        @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"}]', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) <> 2 THROW 53402, 'TEST FAILED: los horarios de prueba debieron guardarse.', 1;

    -- Sesiones esperadas: lunes (dia 0) y miercoles (dia 2) del periodo futuro
    DECLARE @esperadasLuMi INT = (SELECT COUNT(*) FROM (SELECT TOP (26) n = ROW_NUMBER() OVER (ORDER BY (SELECT 1)) - 1 FROM sys.all_objects) d
                                  WHERE DATEDIFF(DAY, '19000101', DATEADD(DAY, d.n, CAST('2098-01-06' AS DATE))) % 7 IN (0, 2));
    DECLARE @esperadasLu INT = (SELECT COUNT(*) FROM (SELECT TOP (26) n = ROW_NUMBER() OVER (ORDER BY (SELECT 1)) - 1 FROM sys.all_objects) d
                                WHERE DATEDIFF(DAY, '19000101', DATEADD(DAY, d.n, CAST('2098-01-06' AS DATE))) % 7 = 0);

    -- 1. Precarga: crea las sesiones futuras del horario, marcadas UTC_GENERADOR y con correlativo consecutivo
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gA, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
        THROW 53410, 'PRELOAD_CREATES FAILED: el coordinador debio poder precargar las sesiones.', 1;
    IF (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @gA) <> @esperadasLuMi
        THROW 53411, 'PRELOAD_CREATES FAILED: cantidad de sesiones distinta de las lunes y miercoles del periodo.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @gA AND procedenciaTemporal <> N'UTC_GENERADOR')
        THROW 53412, 'PRELOAD_CREATES FAILED: todas debian quedar marcadas UTC_GENERADOR.', 1;
    IF (SELECT MIN(numero) FROM dbo.Sesion WHERE grupo = @gA) <> 1 OR (SELECT MAX(numero) FROM dbo.Sesion WHERE grupo = @gA) <> @esperadasLuMi
        THROW 53413, 'PRELOAD_CREATES FAILED: el correlativo debia ser consecutivo desde 1.', 1;
    -- Zona institucional SA Pacific (UTC-5): lunes 2098-01-06 08:00 local = 13:00 UTC
    IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @gA AND fechaHoraInicio = '2098-01-06T13:00:00' AND fechaHoraFin = '2098-01-06T15:00:00')
        THROW 53414, 'PRELOAD_CREATES FAILED: la primera sesion debia estar convertida a UTC.', 1;
    PRINT 'TEST_PASS:PRELOAD_CREATES';

    -- 2. Idempotente: repetir no duplica
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gA, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @gA) <> @esperadasLuMi
        THROW 53420, 'PRELOAD_IDEMPOTENT FAILED: repetir la precarga no debia duplicar sesiones.', 1;
    PRINT 'TEST_PASS:PRELOAD_IDEMPOTENT';

    -- 3. Cambio de horario: queda solo el lunes; se retiran los miercoles generados y se conserva la sesion creada a mano
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (NEWID(), N'Sesion manual QA', 900, N'MANQA1', 1, @gA, '2098-01-07T19:00:00', '2098-01-07T21:00:00', N'UTC_V2');
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gA,
        @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"}]', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gA, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
        THROW 53430, 'PRELOAD_REGENERATE FAILED: la regeneracion debio ser exitosa.', 1;
    IF (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @gA AND procedenciaTemporal = N'UTC_GENERADOR') <> @esperadasLu
        THROW 53431, 'PRELOAD_REGENERATE FAILED: debian quedar solo las sesiones generadas de los lunes.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @gA AND codigo = N'MANQA1')
        THROW 53432, 'PRELOAD_REGENERATE FAILED: la sesion creada a mano debia conservarse.', 1;
    PRINT 'TEST_PASS:PRELOAD_REGENERATE';

    -- 4. Ambito: el docente titular puede; otro docente recibe SEC_002 y no hay cambios
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gA, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
        THROW 53440, 'PRELOAD_SCOPE FAILED: el docente titular debio poder precargar.', 1;
    DECLARE @antes INT = (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @gA);
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gA, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD2;
    SELECT @userMsg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_002';
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg)
        THROW 53441, 'PRELOAD_SCOPE FAILED: un docente que no es titular debio recibir SEC_002.', 1;
    IF (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @gA) <> @antes
        THROW 53442, 'PRELOAD_SCOPE FAILED: el rechazo no debia cambiar sesiones.', 1;
    PRINT 'TEST_PASS:PRELOAD_SCOPE';

    -- 5. Sin horario no hay precarga
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gB, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @gB)
        THROW 53450, 'PRELOAD_REQUIRES_SCHEDULE FAILED: sin horario no debia crear sesiones.', 1;
    PRINT 'TEST_PASS:PRELOAD_REQUIRES_SCHEDULE';

    -- 6. Un periodo ya vencido no genera sesiones del pasado
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gC, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @gC)
        THROW 53460, 'PRELOAD_NO_PAST FAILED: no debia generar sesiones del pasado.', 1;
    PRINT 'TEST_PASS:PRELOAD_NO_PAST';

    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    IF EXISTS (SELECT 1 FROM dbo.Grupo WHERE id IN (@gA, @gB, @gC)) THROW 53490, 'TEST FAILED: quedaron grupos de prueba.', 1;
    IF @@TRANCOUNT <> 0 THROW 53491, 'TEST FAILED: transaccion abierta.', 1;
    PRINT 'TEST END: test_usp_precargar_sesiones_grupo';
END TRY
BEGIN CATCH
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
    THROW 53499, @err, 1;
END CATCH
GO
