USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- F2 (2026-11-02): usp_precargar_sesiones_grupo. Crea las sesiones futuras que faltan a partir del horario del grupo, sin
-- duplicar, retira las futuras generadas que ya no encajan (sin tocar las creadas a mano) y respeta el ambito:
-- coordinador del programa o docente titular (SEC_002 si no). Usa un periodo futuro fijo (2098) para ser determinista.
PRINT 'TEST START: test_usp_precargar_sesiones_grupo';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @zonaHorariaSqlServer SYSNAME = (SELECT TOP 1 valor FROM dbo.uv_parametro WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1);
DECLARE @fechaHoraLocalAhora DATETIME2(0) = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zonaHorariaSqlServer AS DATETIME2(0));
DECLARE @fechaHoyLocal DATE = CAST(@fechaHoraLocalAhora AS DATE);
DECLARE @inicioSlotVencidoLocal DATETIME2(0) = DATEADD(MINUTE, DATEDIFF(MINUTE, 0, @fechaHoraLocalAhora) + 5, 0);
DECLARE @finSlotVencidoLocal DATETIME2(0) = DATEADD(MINUTE, 5, @inicioSlotVencidoLocal);
DECLARE @codigoDiaHoy NVARCHAR(2) = CASE DATEDIFF(DAY, '19000101', @fechaHoyLocal) % 7
    WHEN 0 THEN N'LU' WHEN 1 THEN N'MA' WHEN 2 THEN N'MI' WHEN 3 THEN N'JU'
    WHEN 4 THEN N'VI' WHEN 5 THEN N'SA' ELSE N'DO' END;
DECLARE @idAsig UNIQUEIDENTIFIER, @idProg UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER, @idInstitucion UNIQUEIDENTIFIER;
SELECT TOP 1 @idAsig = a.id, @idProg = pe.idPrograma, @uCoord = ci.idUsuario, @idInstitucion = pr.idInstitucion
FROM dbo.uv_asignatura a
INNER JOIN dbo.uv_semestre_plan_estudio spe ON a.idSemestrePlanEstudio = spe.id
INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
INNER JOIN dbo.uv_programa pr ON pe.idPrograma = pr.id
INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = pr.idCoordinador
WHERE pr.estaActivoPrograma = 1 AND ci.estaActivoUsuario = 1 AND ci.estaActivoRolCoordinador = 1 AND a.estaActivaAsignatura = 1
ORDER BY a.id;
DECLARE @idPeriodoBase UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_periodo_academico WHERE idInstitucion = @idInstitucion ORDER BY anio DESC);
DECLARE @tvCat UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_tipo_vinculacion WHERE codigo = 'CAT');
IF @tipoCC IS NULL OR @idAsig IS NULL OR @uCoord IS NULL OR @idInstitucion IS NULL OR @idPeriodoBase IS NULL OR @tvCat IS NULL OR @zonaHorariaSqlServer IS NULL
    THROW 53400, 'TEST FAILED: faltan fixtures del seed (asignatura, coordinador, periodo o vinculacion).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uD1 UNIQUEIDENTIFIER = NEWID(), @uD2 UNIQUEIDENTIFIER = NEWID(), @uE UNIQUEIDENTIFIER = NEWID();
    DECLARE @d1 UNIQUEIDENTIFIER = NEWID(), @d2 UNIQUEIDENTIFIER = NEWID(), @e UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD1, @tipoCC, 973000001, N'Precarga', N'Uno', N'Pablo', N'Qa', N'qa.precarga.d1@test.local', 1, 1, N'HashBackend_P1'),
           (@uD2, @tipoCC, 973000002, N'Precarga', N'Dos', N'Marina', N'Qa', N'qa.precarga.d2@test.local', 1, 1, N'HashBackend_P2'),
           (@uE, @tipoCC, 974000000 + ABS(CHECKSUM(NEWID()) % 99999999), N'Precarga', N'Estudiante', N'Sara', N'Qa',
            CONCAT(N'qa.precarga.estudiante.', REPLACE(CONVERT(NVARCHAR(36), @uE), N'-', N''), N'@test.local'), 1, 1, N'HashBackend_PE');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d1, @uD1), (@d2, @uD2);
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e, @uE);
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @d1, @idProg, @tvCat, 1, SYSUTCDATETIME()), (NEWID(), @d2, @idProg, @tvCat, 1, SYSUTCDATETIME());

    -- Periodos deterministas de 4, 8, 12, 16 y 18 semanas. El vencido termina ayer en hora civil institucional.
    DECLARE @idFuturo UNIQUEIDENTIFIER = NEWID(), @idPasado UNIQUEIDENTIFIER = NEWID();
    DECLARE @idPeriodo8 UNIQUEIDENTIFIER = NEWID(), @idPeriodo12 UNIQUEIDENTIFIER = NEWID();
    DECLARE @idPeriodo16 UNIQUEIDENTIFIER = NEWID(), @idPeriodo18 UNIQUEIDENTIFIER = NEWID();
    DECLARE @codigoPeriodoBase INT = 2000000 + ABS(CHECKSUM(NEWID()) % 900000);
    DECLARE @fechaFinPasado DATE = DATEADD(DAY, -1, @fechaHoyLocal);
    DECLARE @fechaInicioPasado DATE = DATEADD(DAY, -28, @fechaHoyLocal);
    DECLARE @fechaBaseVariable DATE = '2098-01-06';
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@idFuturo, @idInstitucion, N'Periodo QA precarga futuro', @codigoPeriodoBase + 1, '2098-01-06', '2098-01-31', 2098),
           (@idPasado, @idInstitucion, N'Periodo QA precarga vencido', @codigoPeriodoBase + 2, @fechaInicioPasado, @fechaFinPasado, YEAR(@fechaFinPasado)),
           (@idPeriodo8, @idInstitucion, N'Periodo QA precarga 8 semanas', @codigoPeriodoBase + 3, @fechaBaseVariable, DATEADD(DAY, 55, @fechaBaseVariable), 2098),
           (@idPeriodo12, @idInstitucion, N'Periodo QA precarga 12 semanas', @codigoPeriodoBase + 4, @fechaBaseVariable, DATEADD(DAY, 83, @fechaBaseVariable), 2098),
           (@idPeriodo16, @idInstitucion, N'Periodo QA precarga 16 semanas', @codigoPeriodoBase + 5, @fechaBaseVariable, DATEADD(DAY, 111, @fechaBaseVariable), 2098),
           (@idPeriodo18, @idInstitucion, N'Periodo QA precarga 18 semanas', @codigoPeriodoBase + 6, @fechaBaseVariable, DATEADD(DAY, 125, @fechaBaseVariable), 2098);

    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @userMsg NVARCHAR(4000);
    DECLARE @base INT = 61000 + ABS(CHECKSUM(NEWID()) % 9000);
    DECLARE @gA UNIQUEIDENTIFIER = NEWID(), @gB UNIQUEIDENTIFIER = NEWID(), @gC UNIQUEIDENTIFIER = NEWID();
    DECLARE @gV8 UNIQUEIDENTIFIER = NEWID(), @gV12 UNIQUEIDENTIFIER = NEWID(), @gV16 UNIQUEIDENTIFIER = NEWID(), @gV18 UNIQUEIDENTIFIER = NEWID();
    DECLARE @codA INT = @base, @codB INT = @base + 1, @codC INT = @base + 2;
    DECLARE @codV8 INT = @base + 3, @codV12 INT = @base + 4, @codV16 INT = @base + 5, @codV18 INT = @base + 6;

    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gA, @idAsignatura = @idAsig, @idPeriodoAcademico = @idFuturo, @codigo = @codA,
        @nombre = N'Grupo QA Precarga A', @idDocente = @d1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gB, @idAsignatura = @idAsig, @idPeriodoAcademico = @idFuturo, @codigo = @codB,
        @nombre = N'Grupo QA Precarga B', @idDocente = @d1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gC, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPasado, @codigo = @codC,
        @nombre = N'Grupo QA Precarga C', @idDocente = @d1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gV8, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo8, @codigo = @codV8,
        @nombre = N'Grupo QA Precarga 8 semanas', @idDocente = @d1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gV12, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo12, @codigo = @codV12,
        @nombre = N'Grupo QA Precarga 12 semanas', @idDocente = @d1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gV16, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo16, @codigo = @codV16,
        @nombre = N'Grupo QA Precarga 16 semanas', @idDocente = @d1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gV18, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo18, @codigo = @codV18,
        @nombre = N'Grupo QA Precarga 18 semanas', @idDocente = @d1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) <> 7 OR @@TRANCOUNT <> 1
        THROW 53401, 'TEST FAILED: los grupos de prueba debieron crearse dentro de la transaccion externa.', 1;

    DECLARE @idAsigOtro UNIQUEIDENTIFIER;
    SELECT TOP 1 @idAsigOtro = a.id
    FROM dbo.uv_asignatura a
    INNER JOIN dbo.uv_semestre_plan_estudio spe ON a.idSemestrePlanEstudio = spe.id
    INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
    INNER JOIN dbo.uv_programa pr ON pr.id = pe.idPrograma
    WHERE pe.idPrograma <> @idProg;
    IF @idAsigOtro IS NULL THROW 53404, 'TEST FAILED: se requiere una asignatura de otro programa para probar el ambito.', 1;
    DECLARE @gOtro UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@gOtro, @idAsigOtro, @idFuturo, @base + 7, N'Grupo QA Precarga Otro Programa', 20, 0, 0, 0, @d1);

    DECLARE @idEstadoActivo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
    DECLARE @idRazonAN UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_razon_causa WHERE codigo = 'AN');
    IF @idEstadoActivo IS NULL OR @idRazonAN IS NULL THROW 53403, 'TEST FAILED: faltan catálogos de estudiante activo o asistencia AN.', 1;
    DECLARE @idEstudianteGrupo UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@idEstudianteGrupo, @idEstadoActivo, @e, @gA);

    -- Horario de A: lunes y miercoles 08-10. C (periodo vencido) programa hoy en una franja futura.
    IF CAST(@inicioSlotVencidoLocal AS DATE) <> @fechaHoyLocal OR CAST(@finSlotVencidoLocal AS DATE) <> @fechaHoyLocal
    BEGIN
        SET @inicioSlotVencidoLocal = DATEADD(HOUR, 22, CAST(@fechaHoyLocal AS DATETIME2(0)));
        SET @finSlotVencidoLocal = DATEADD(MINUTE, 1439, CAST(@fechaHoyLocal AS DATETIME2(0)));
    END
    DECLARE @horarioVencido NVARCHAR(MAX) = CONCAT(N'[{"codigoDia":"', @codigoDiaHoy, N'","horaInicio":"',
        CONVERT(CHAR(5), CAST(@inicioSlotVencidoLocal AS TIME(0)), 108), N'","horaFin":"',
        CONVERT(CHAR(5), CAST(@finSlotVencidoLocal AS TIME(0)), 108), N'"}]');
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gA,
        @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"},{"codigoDia":"MI","horaInicio":"08:00","horaFin":"10:00"}]',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gC,
        @horariosJSON = @horarioVencido, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gV8,
        @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"13:00","horaFin":"14:00"}]', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gV12,
        @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"14:00","horaFin":"15:00"},{"codigoDia":"MI","horaInicio":"14:00","horaFin":"15:00"}]',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gV16,
        @horariosJSON = N'[{"codigoDia":"MA","horaInicio":"15:00","horaFin":"16:00"}]', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gV18,
        @horariosJSON = N'[{"codigoDia":"VI","horaInicio":"16:00","horaFin":"17:00"},{"codigoDia":"DO","horaInicio":"16:00","horaFin":"17:00"}]',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) <> 6 OR @@TRANCOUNT <> 1
        THROW 53402, 'TEST FAILED: los horarios de prueba debieron guardarse dentro de la transaccion externa.', 1;

    -- Sesiones esperadas: lunes (dia 0) y miercoles (dia 2) del periodo futuro
    DECLARE @esperadasLuMi INT = (SELECT COUNT(*) FROM (SELECT TOP (26) n = ROW_NUMBER() OVER (ORDER BY (SELECT 1)) - 1 FROM sys.all_objects) d
                                  WHERE DATEDIFF(DAY, '19000101', DATEADD(DAY, d.n, CAST('2098-01-06' AS DATE))) % 7 IN (0, 2));
    DECLARE @esperadasLu INT = (SELECT COUNT(*) FROM (SELECT TOP (26) n = ROW_NUMBER() OVER (ORDER BY (SELECT 1)) - 1 FROM sys.all_objects) d
                                WHERE DATEDIFF(DAY, '19000101', DATEADD(DAY, d.n, CAST('2098-01-06' AS DATE))) % 7 = 0);

    -- 1. Precarga: crea las sesiones futuras del horario, marcadas UTC_GENERADOR y con correlativo consecutivo
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gA, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR @@TRANCOUNT <> 1
        THROW 53410, 'PRELOAD_CREATES FAILED: el coordinador debio poder precargar las sesiones.', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_sesion_v2 WHERE idGrupo = @gA) <> @esperadasLuMi
        THROW 53411, 'PRELOAD_CREATES FAILED: cantidad de sesiones distinta de las lunes y miercoles del periodo.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_sesion_v2 WHERE idGrupo = @gA AND procedenciaTemporal <> N'UTC_GENERADOR')
        THROW 53412, 'PRELOAD_CREATES FAILED: todas debian quedar marcadas UTC_GENERADOR.', 1;
    IF (SELECT MIN(numero) FROM dbo.uv_sesion_v2 WHERE idGrupo = @gA) <> 1 OR (SELECT MAX(numero) FROM dbo.uv_sesion_v2 WHERE idGrupo = @gA) <> @esperadasLuMi
        THROW 53413, 'PRELOAD_CREATES FAILED: el correlativo debia ser consecutivo desde 1.', 1;
    -- Zona institucional SA Pacific (UTC-5): lunes 2098-01-06 08:00 local = 13:00 UTC
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_v2 WHERE idGrupo = @gA AND fechaHoraInicio = '2098-01-06T13:00:00' AND fechaHoraFin = '2098-01-06T15:00:00')
        THROW 53414, 'PRELOAD_CREATES FAILED: la primera sesion debia estar convertida a UTC.', 1;
    PRINT 'TEST_PASS:PRELOAD_CREATES';

    -- 2. Idempotente: repetir no duplica
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gA, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR @@TRANCOUNT <> 1
       OR (SELECT COUNT(*) FROM dbo.uv_sesion_v2 WHERE idGrupo = @gA) <> @esperadasLuMi
        THROW 53420, 'PRELOAD_IDEMPOTENT FAILED: repetir la precarga no debia duplicar sesiones.', 1;
    PRINT 'TEST_PASS:PRELOAD_IDEMPOTENT';

    -- Evidencia de proteccion: una sesion futura con asistencia, una sesion UTC_OWNER clasificada,
    -- una sesion historica y una sesion manual deben sobrevivir al cambio de horario.
    DECLARE @idSesionConAsistencia UNIQUEIDENTIFIER;
    SELECT TOP 1 @idSesionConAsistencia = id
    FROM dbo.uv_sesion_v2
    WHERE idGrupo = @gA AND procedenciaTemporal = N'UTC_GENERADOR' AND fechaHoraInicio > '2098-01-06T13:00:00'
    ORDER BY fechaHoraInicio;
    IF @idSesionConAsistencia IS NULL THROW 53421, 'TEST FAILED: no se encontro la sesion futura para adjuntar asistencia.', 1;
    DECLARE @idAsistencia UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@idAsistencia, @idEstudianteGrupo, @idSesionConAsistencia);
    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
    SELECT NEWID(), 680000 + ABS(CHECKSUM(NEWID()) % 9999), @idAsistencia, 1, @idRazonAN, s.fechaHoraInicio, s.fechaHoraFin
    FROM dbo.uv_sesion_v2 s WHERE s.id = @idSesionConAsistencia;

    DECLARE @idSesionClasificada UNIQUEIDENTIFIER = NEWID();
    DECLARE @idSesionHistorica UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@idSesionClasificada, N'Sesion clasificada QA', 899, N'F2CLASS1', 1, @gA, '2098-01-07T23:00:00', '2098-01-08T00:00:00', N'UTC_OWNER'),
           (@idSesionHistorica, N'Sesion historica QA', 902, N'F2HIST1', 1, @gA, '2020-01-06T13:00:00', '2020-01-06T15:00:00', N'UTC_GENERADOR');
    INSERT INTO dbo.SesionProcedenciaClasificacion (
        id, sesion, ambiente, idManifiesto, hashEvidencia, procedenciaAnterior, procedenciaNueva,
        fechaHoraInicioAnterior, fechaHoraFinAnterior, fechaHoraInicioUtc, fechaHoraFinUtc,
        usuarioEjecutor, usuarioAprobador, idCorrelacion, fechaRegistro
    )
    VALUES (
        NEWID(), @idSesionClasificada, N'QA-F2', N'F2-QA-MANIFIESTO', REPLICATE('a', 64), NULL, N'UTC_OWNER',
        '2098-01-07T23:00:00', '2098-01-08T00:00:00', '2098-01-07T23:00:00', '2098-01-08T00:00:00',
        @uD1, @uCoord, @corr, SYSUTCDATETIME()
    );

    -- 3. Cambio de horario: lunes 09-11; se sustituyen los slots futuros elegibles y sobreviven las evidencias.
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (NEWID(), N'Sesion manual QA', 900, N'MANQA1', 1, @gA, '2098-01-07T19:00:00', '2098-01-07T21:00:00', N'UTC_V2');
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gA,
        @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"09:00","horaFin":"11:00"}]', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gA, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR @@TRANCOUNT <> 1
        THROW 53430, 'PRELOAD_REGENERATE FAILED: la regeneracion debio ser exitosa.', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_sesion_v2 WHERE idGrupo = @gA AND procedenciaTemporal = N'UTC_GENERADOR' AND fechaHoraInicio > SYSUTCDATETIME()) <> @esperadasLu + 1
        THROW 53431, 'PRELOAD_REGENERATE FAILED: debian quedar los lunes actualizados y la sesion con asistencia.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_v2 WHERE id = @idSesionConAsistencia AND procedenciaTemporal = N'UTC_GENERADOR')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a INNER JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id WHERE a.idSesion = @idSesionConAsistencia AND a.idEstudianteGrupo = @idEstudianteGrupo)
        THROW 53432, 'PRELOAD_PRESERVES_ATTENDANCE FAILED: la sesion o su evidencia de asistencia desaparecio.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_v2 WHERE id = @idSesionClasificada AND procedenciaTemporal = N'UTC_OWNER')
        THROW 53433, 'PRELOAD_PRESERVES_CLASSIFICATION FAILED: la sesion con clasificacion academica desaparecio.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_v2 WHERE id = @idSesionHistorica AND fechaHoraInicio = '2020-01-06T13:00:00' AND procedenciaTemporal = N'UTC_GENERADOR')
        THROW 53434, 'PRELOAD_PRESERVES_HISTORY FAILED: la sesion historica cambio o desaparecio.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_v2 WHERE idGrupo = @gA AND codigo = N'MANQA1' AND procedenciaTemporal = N'UTC_V2')
        THROW 53438, 'PRELOAD_REGENERATE FAILED: la sesion creada a mano debia conservarse.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_v2 WHERE idGrupo = @gA AND procedenciaTemporal = N'UTC_GENERADOR' AND fechaHoraInicio = '2098-01-06T14:00:00' AND fechaHoraFin = '2098-01-06T16:00:00')
        THROW 53435, 'PRELOAD_REGENERATE FAILED: el nuevo horario del lunes no se sincronizo a UTC.', 1;
    IF EXISTS (SELECT fechaHoraInicio, fechaHoraFin FROM dbo.uv_sesion_v2 WHERE idGrupo = @gA GROUP BY fechaHoraInicio, fechaHoraFin HAVING COUNT(*) > 1)
        THROW 53436, 'PRELOAD_REGENERATE FAILED: aparecieron sesiones duplicadas por horario.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_sesion_v2 WHERE idGrupo = @gA AND id <> @idSesionConAsistencia AND procedenciaTemporal = N'UTC_GENERADOR' AND fechaHoraInicio IN ('2098-01-06T13:00:00','2098-01-13T13:00:00','2098-01-20T13:00:00','2098-01-27T13:00:00'))
        THROW 53437, 'PRELOAD_REGENERATE FAILED: quedaron slots antiguos generados que eran elegibles para sustituirse.', 1;
    PRINT 'TEST_PASS:PRELOAD_PRESERVES_ATTENDANCE';
    PRINT 'TEST_PASS:PRELOAD_PRESERVES_CLASSIFICATION';
    PRINT 'TEST_PASS:PRELOAD_PRESERVES_HISTORY';
    PRINT 'TEST_PASS:PRELOAD_REGENERATE';

    -- 4. Defensa por dominio y rol: coordinador de otro programa y estudiante no escriben sesiones.
    DECLARE @cantidadAntesNoAutorizado INT = (SELECT COUNT(*) FROM dbo.uv_sesion_v2 WHERE idGrupo = @gA);
    SELECT @userMsg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_002';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gOtro, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg AND mensajeTecnicoResultado LIKE 'DBCODE=SEC_002|%')
       OR EXISTS (SELECT 1 FROM dbo.uv_sesion_v2 WHERE idGrupo = @gOtro)
       OR @@TRANCOUNT <> 1
        THROW 53443, 'PRELOAD_CROSS_PROGRAM_DENIED FAILED: el coordinador de otro programa no recibio SEC_002 o hubo escrituras.', 1;
    PRINT 'TEST_PASS:PRELOAD_CROSS_PROGRAM_DENIED';

    SELECT @userMsg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_001';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gA, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg AND mensajeTecnicoResultado LIKE 'DBCODE=SEC_001|%')
       OR (SELECT COUNT(*) FROM dbo.uv_sesion_v2 WHERE idGrupo = @gA) <> @cantidadAntesNoAutorizado
       OR @@TRANCOUNT <> 1
        THROW 53444, 'PRELOAD_NO_PRIVILEGE_DENIED FAILED: un estudiante sin permiso no recibio SEC_001 o hubo escrituras.', 1;
    PRINT 'TEST_PASS:PRELOAD_NO_PRIVILEGE_DENIED';

    -- 5. Ambito docente: el titular puede; otro docente recibe SEC_002 y no hay cambios
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gA, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR @@TRANCOUNT <> 1
        THROW 53440, 'PRELOAD_SCOPE FAILED: el docente titular debio poder precargar.', 1;
    DECLARE @antes INT = (SELECT COUNT(*) FROM dbo.uv_sesion_v2 WHERE idGrupo = @gA);
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gA, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD2;
    SELECT @userMsg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_002';
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg) OR @@TRANCOUNT <> 1
        THROW 53441, 'PRELOAD_SCOPE FAILED: un docente que no es titular debio recibir SEC_002.', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_sesion_v2 WHERE idGrupo = @gA) <> @antes
        THROW 53442, 'PRELOAD_SCOPE FAILED: el rechazo no debia cambiar sesiones.', 1;
    PRINT 'TEST_PASS:PRELOAD_SCOPE';

    -- 6. Sin horario no hay precarga
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gB, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR EXISTS (SELECT 1 FROM dbo.uv_sesion_v2 WHERE idGrupo = @gB) OR @@TRANCOUNT <> 1
        THROW 53450, 'PRELOAD_REQUIRES_SCHEDULE FAILED: sin horario no debia crear sesiones.', 1;
    PRINT 'TEST_PASS:PRELOAD_REQUIRES_SCHEDULE';

    -- 7. Un periodo que termino ayer no puede crear una sesion para hoy, aunque coincida con el dia configurado.
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @gC, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF EXISTS (SELECT 1 FROM dbo.uv_sesion_v2 WHERE idGrupo = @gC) OR @@TRANCOUNT <> 1
        THROW 53460, 'PRELOAD_NO_PAST FAILED: un periodo vencido genero una sesion para hoy.', 1;
    PRINT 'TEST_PASS:PRELOAD_NO_PAST';

    -- 8. Cantidad variable por duracion y numero de dias semanales; las fechas civiles permanecen dentro del periodo.
    DECLARE @dayOffsets TABLE (n INT NOT NULL PRIMARY KEY);
    INSERT INTO @dayOffsets (n)
    SELECT TOP (126) CONVERT(INT, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1)
    FROM sys.all_objects;
    DECLARE @expected8 INT = (SELECT COUNT(*) FROM @dayOffsets WHERE n < 56 AND DATEDIFF(DAY, '19000101', DATEADD(DAY, n, @fechaBaseVariable)) % 7 = 0);
    DECLARE @expected12 INT = (SELECT COUNT(*) FROM @dayOffsets WHERE n < 84 AND DATEDIFF(DAY, '19000101', DATEADD(DAY, n, @fechaBaseVariable)) % 7 IN (0, 2));
    DECLARE @expected16 INT = (SELECT COUNT(*) FROM @dayOffsets WHERE n < 112 AND DATEDIFF(DAY, '19000101', DATEADD(DAY, n, @fechaBaseVariable)) % 7 = 1);
    DECLARE @expected18 INT = (SELECT COUNT(*) FROM @dayOffsets WHERE n < 126 AND DATEDIFF(DAY, '19000101', DATEADD(DAY, n, @fechaBaseVariable)) % 7 IN (4, 6));
    DECLARE @variableCases TABLE (orden INT PRIMARY KEY, idGrupo UNIQUEIDENTIFIER, esperado INT, token VARCHAR(64), dias INT, fechaFin DATE);
    INSERT INTO @variableCases (orden, idGrupo, esperado, token, dias, fechaFin)
    VALUES (1, @gV8, @expected8, 'PRELOAD_VARIABLE_8WEEK_SINGLE', 56, DATEADD(DAY, 55, @fechaBaseVariable)),
           (2, @gV12, @expected12, 'PRELOAD_VARIABLE_12WEEK_TWO', 84, DATEADD(DAY, 83, @fechaBaseVariable)),
           (3, @gV16, @expected16, 'PRELOAD_VARIABLE_16WEEK_SINGLE', 112, DATEADD(DAY, 111, @fechaBaseVariable)),
           (4, @gV18, @expected18, 'PRELOAD_VARIABLE_18WEEK_TWO', 126, DATEADD(DAY, 125, @fechaBaseVariable));
    DECLARE @caseOrden INT = 1, @caseGrupo UNIQUEIDENTIFIER, @caseEsperado INT, @caseToken VARCHAR(64), @caseDias INT, @caseFechaFin DATE;
    WHILE @caseOrden <= 4
    BEGIN
        SELECT @caseGrupo = idGrupo, @caseEsperado = esperado, @caseToken = token, @caseDias = dias, @caseFechaFin = fechaFin
        FROM @variableCases WHERE orden = @caseOrden;
        TRUNCATE TABLE #r;
        INSERT INTO #r EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @caseGrupo, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
        IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR @@TRANCOUNT <> 1
           OR (SELECT COUNT(*) FROM dbo.uv_sesion_v2 WHERE idGrupo = @caseGrupo) <> @caseEsperado
           OR (SELECT COUNT(DISTINCT numero) FROM dbo.uv_sesion_v2 WHERE idGrupo = @caseGrupo) <> @caseEsperado
           OR (SELECT COUNT(DISTINCT codigo) FROM dbo.uv_sesion_v2 WHERE idGrupo = @caseGrupo) <> @caseEsperado
            THROW 53470, 'PRELOAD_VARIABLE_PERIODS FAILED: la cantidad, el correlativo o los codigos no coinciden con el calendario semanal.', 1;
        IF EXISTS (
            SELECT 1 FROM dbo.uv_sesion_v2
            WHERE idGrupo = @caseGrupo
              AND CAST(fechaHoraInicio AT TIME ZONE 'UTC' AT TIME ZONE @zonaHorariaSqlServer AS DATE) NOT BETWEEN @fechaBaseVariable AND @caseFechaFin
        )
            THROW 53471, 'PRELOAD_VARIABLE_PERIODS FAILED: aparecio una fecha civil fuera del periodo.', 1;
        IF EXISTS (SELECT fechaHoraInicio, fechaHoraFin FROM dbo.uv_sesion_v2 WHERE idGrupo = @caseGrupo GROUP BY fechaHoraInicio, fechaHoraFin HAVING COUNT(*) > 1)
            THROW 53472, 'PRELOAD_VARIABLE_PERIODS FAILED: aparecieron sesiones duplicadas.', 1;
        PRINT CONCAT(N'TEST_PASS:', @caseToken);
        SET @caseOrden += 1;
    END

    DECLARE @idRuntimeRole INT = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime');
    IF @idRuntimeRole IS NULL
       OR NOT EXISTS (SELECT 1 FROM sys.database_permissions WHERE grantee_principal_id = @idRuntimeRole AND class = 1 AND major_id = OBJECT_ID(N'dbo.usp_precargar_sesiones_grupo') AND permission_name = 'EXECUTE' AND state = 'G')
       OR NOT EXISTS (SELECT 1 FROM sys.database_permissions WHERE grantee_principal_id = @idRuntimeRole AND class = 1 AND major_id = OBJECT_ID(N'dbo.usp_precargar_sesiones_grupo_interno') AND permission_name = 'EXECUTE' AND state = 'D')
       OR (SELECT COUNT(*) FROM sys.database_permissions WHERE grantee_principal_id = @idRuntimeRole AND class = 1 AND major_id = OBJECT_ID(N'dbo.Sesion') AND permission_name IN ('INSERT', 'UPDATE', 'DELETE') AND state = 'D') <> 3
        THROW 53473, 'PRELOAD_RUNTIME_LEAST_PRIVILEGE FAILED: runtime permissions on the preloader or session table are incorrect.', 1;
    PRINT 'TEST_PASS:PRELOAD_RUNTIME_LEAST_PRIVILEGE';

    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    IF EXISTS (SELECT 1 FROM dbo.uv_grupo WHERE id IN (@gA, @gB, @gC, @gV8, @gV12, @gV16, @gV18, @gOtro)) THROW 53490, 'TEST FAILED: quedaron grupos de prueba.', 1;
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
