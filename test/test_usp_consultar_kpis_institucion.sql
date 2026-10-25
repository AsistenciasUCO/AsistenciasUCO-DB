USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_consultar_kpis_institucion (HU133/HU138/HU135/HU136)';
PRINT '==================================================';

DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1);
DECLARE @tipoId        UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion);
DECLARE @tipoProg      UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma ORDER BY nombre);
DECLARE @semestre      UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Semestre);
DECLARE @area          UNIQUEIDENTIFIER = (SELECT TOP 1 area FROM dbo.Asignatura);
DECLARE @componente    UNIQUEIDENTIFIER = (SELECT TOP 1 componente FROM dbo.Asignatura);
DECLARE @estA          UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'A');
DECLARE @estCI         UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'CI');
IF @idInstitucion IS NULL OR @tipoId IS NULL OR @tipoProg IS NULL OR @semestre IS NULL OR @area IS NULL OR @componente IS NULL OR @estA IS NULL OR @estCI IS NULL
    THROW 53000, 'TEST FAILED: fixtures base no disponibles.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #u (n INT IDENTITY(1,1), id UNIQUEIDENTIFIER);
    DECLARE @i INT = 1;
    WHILE @i <= 17
    BEGIN
        DECLARE @uid UNIQUEIDENTIFIER = NEWID();
        INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
        VALUES (@uid, @tipoId, 300000000 + ABS(CHECKSUM(NEWID()) % 99999999), CONCAT(N'Apellido', CHAR(64 + @i)), N'QA', CONCAT(N'Nombre', CHAR(64 + @i)), N'X',
                CONCAT(CONVERT(NVARCHAR(36), @uid), N'@qa.test'), 1, 1, N'x');
        INSERT INTO #u (id) VALUES (@uid);
        SET @i += 1;
    END
    -- n: 1 decano, 2 coordinador P1, 3 coordinador P2, 4 docente, 5..9 = E1..E5, 10 = E6, 11 = E7, 12 = usuario sin perfil
    DECLARE @uDec UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 1), @uC1 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 2),
            @uC2 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 3), @uDoc UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 4),
            @uPlano UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 12);

    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);

    DECLARE @sufijo NVARCHAR(8) = SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8);
    DECLARE @dec UNIQUEIDENTIFIER = NEWID(), @f UNIQUEIDENTIFIER = NEWID(), @c1 UNIQUEIDENTIFIER = NEWID(), @c2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID(), @doc UNIQUEIDENTIFIER = NEWID(), @per UNIQUEIDENTIFIER = NEWID();
    -- Instituciones propias del fixture: I1 (administrador A1) e I2 (administrador A2); aisla las cifras de los datos reales
    DECLARE @i1 UNIQUEIDENTIFIER = NEWID(), @i2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Institucion (id, nombre, estado) VALUES (@i1, CONCAT(N'QA I1 ', SUBSTRING(CONVERT(NVARCHAR(36), @i1), 1, 8)), 1), (@i2, CONCAT(N'QA I2 ', SUBSTRING(CONVERT(NVARCHAR(36), @i2), 1, 8)), 1);
    SET @idInstitucion = @i1;
    INSERT INTO dbo.Decano (id, usuario) VALUES (@dec, @uDec);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@f, CONCAT(N'QA KPI ', @sufijo), @idInstitucion, @dec, 1);
    INSERT INTO dbo.Coordinador (id, usuario, facultad) VALUES (@c1, @uC1, @f), (@c2, @uC2, @f);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES (@p1, @f, @tipoProg, CONCAT(N'KPI P1 ', @sufijo), @c1, 1), (@p2, @f, @tipoProg, CONCAT(N'KPI P2 ', @sufijo), @c2, 1);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@doc, @uDoc);
    DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AS DATE);
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio) VALUES (@per, @idInstitucion, CONCAT(N'QA KPI ', @sufijo), 930000 + ABS(CHECKSUM(NEWID()) % 9999), DATEADD(DAY, -60, @hoy), DATEADD(DAY, 60, @hoy), YEAR(@hoy));

    DECLARE @pl1 UNIQUEIDENTIFIER = NEWID(), @pl2 UNIQUEIDENTIFIER = NEWID(), @spe1 UNIQUEIDENTIFIER = NEWID(), @spe2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @a1 UNIQUEIDENTIFIER = NEWID(), @a2 UNIQUEIDENTIFIER = NEWID(), @a3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PlanEstudio (id, programa, inp, estado) VALUES (@pl1, @p1, 930000 + ABS(CHECKSUM(NEWID()) % 9999), 1), (@pl2, @p2, 940000 + ABS(CHECKSUM(NEWID()) % 9999), 1);
    INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) VALUES (@spe1, @pl1, @semestre), (@spe2, @pl2, @semestre);
    INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, semestrePlanEstudio, estado) VALUES
        (@a1, CONCAT(N'K1', @sufijo), N'Asignatura Uno', 3, @area, @componente, @spe1, 1),
        (@a2, CONCAT(N'K2', @sufijo), N'Asignatura Dos', 3, @area, @componente, @spe1, 1),
        (@a3, CONCAT(N'K3', @sufijo), N'Asignatura Tres', 3, @area, @componente, @spe2, 1);
    CREATE TABLE #g (k NVARCHAR(2), id UNIQUEIDENTIFIER);
    INSERT INTO #g VALUES (N'G1', NEWID()), (N'G2', NEWID()), (N'G3', NEWID());
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    SELECT g.id, CASE g.k WHEN N'G1' THEN @a1 WHEN N'G2' THEN @a2 ELSE @a3 END, @per, 930000 + ABS(CHECKSUM(NEWID()) % 99999), CONCAT(N'Grupo ', g.k), CASE g.k WHEN N'G1' THEN 10 WHEN N'G2' THEN 5 ELSE 40 END, 0, 0, 0, @doc FROM #g g;

    DECLARE @ahora DATETIME2 = SYSUTCDATETIME();
    CREATE TABLE #s (id UNIQUEIDENTIFIER, k NVARCHAR(2), n INT, h INT, prc NVARCHAR(24));
    INSERT INTO #s (id, k, n, h, prc)
    SELECT NEWID(), v.k, v.n, v.h, v.prc FROM (VALUES
        (N'G1', 1, -168, N'UTC_V2'),
        (N'G1', 2, -144, N'UTC_V2'),
        (N'G1', 3, -120, N'UTC_V2'),
        (N'G1', 4, -96, N'UTC_V2'),
        (N'G1', 5, -72, N'UTC_V2'),
        (N'G1', 6, -48, N'UTC_V2'),
        (N'G1', 7, -24, N'UTC_V2'),
        (N'G1', 8, -25, NULL),
        (N'G1', 9, 24, N'UTC_V2'),
        (N'G1', 10, 48, N'UTC_V2'),
        (N'G1', 11, 72, N'UTC_V2'),
        (N'G1', 12, 96, N'UTC_V2'),
        (N'G2', 1, -147, N'UTC_V2'),
        (N'G2', 2, -123, N'UTC_V2'),
        (N'G2', 3, -99, N'UTC_V2'),
        (N'G3', 1, -48, N'UTC_V2'),
        (N'G3', 2, -24, N'UTC_V2')
    ) v(k, n, h, prc);
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    SELECT s.id, CONCAT(N'Sesion ', s.k, N'-', s.n), s.n, CONCAT(N'S', RIGHT(CONVERT(NVARCHAR(36), s.id), 12)), 1 + (s.n / 3), g.id,
           DATEADD(HOUR, s.h, @ahora), DATEADD(HOUR, s.h + 2, @ahora), s.prc
    FROM #s s INNER JOIN #g g ON g.k = s.k;

    CREATE TABLE #e (k NVARCHAR(2), idEstudiante UNIQUEIDENTIFIER);
    INSERT INTO #e VALUES (N'E1', NEWID()), (N'E2', NEWID()), (N'E3', NEWID()), (N'E4', NEWID()), (N'E5', NEWID()), (N'E6', NEWID()), (N'E7', NEWID());
    INSERT INTO dbo.Estudiante (id, usuario) SELECT e.idEstudiante, u.id FROM #e e INNER JOIN #u u ON u.n = 4 + CAST(RIGHT(e.k, 1) AS INT) + IIF(e.k = N'E7', 0, 0);
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) SELECT NEWID(), e.idEstudiante, IIF(e.k = N'E7', @p2, @p1) FROM #e e;
    CREATE TABLE #eg (id UNIQUEIDENTIFIER, k NVARCHAR(2), g NVARCHAR(2));
    INSERT INTO #eg (id, k, g)
    SELECT NEWID(), v.k, v.g FROM (VALUES
        (N'E1', N'G1'), (N'E2', N'G1'), (N'E3', N'G1'), (N'E4', N'G1'), (N'E5', N'G1'), (N'E5', N'G2'), (N'E6', N'G1'), (N'E7', N'G3')
    ) v(k, g);
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    SELECT x.id, IIF(x.k = N'E6', @estCI, @estA), e.idEstudiante, g.id FROM #eg x INNER JOIN #e e ON e.k = x.k INNER JOIN #g g ON g.k = x.g;

    CREATE TABLE #reg (k NVARCHAR(2), g NVARCHAR(2), n INT, codigo NVARCHAR(5));
    INSERT INTO #reg VALUES
        ('E1', 'G1', 1, N'SJC'),
        ('E2', 'G1', 1, N'SJC'),
        ('E3', 'G1', 1, N'EX'),
        ('E4', 'G1', 1, N'AN'),
        ('E5', 'G1', 1, N'AN'),
        ('E6', 'G1', 1, N'AN'),
        ('E1', 'G1', 2, N'SJC'),
        ('E2', 'G1', 2, N'AN'),
        ('E3', 'G1', 2, N'EX'),
        ('E4', 'G1', 2, N'AN'),
        ('E5', 'G1', 2, N'AN'),
        ('E6', 'G1', 2, N'AN'),
        ('E1', 'G1', 3, N'AN'),
        ('E2', 'G1', 3, N'AN'),
        ('E3', 'G1', 3, N'AN'),
        ('E4', 'G1', 3, N'AN'),
        ('E5', 'G1', 3, N'AN'),
        ('E6', 'G1', 3, N'AN'),
        ('E1', 'G1', 4, N'AN'),
        ('E2', 'G1', 4, N'AN'),
        ('E3', 'G1', 4, N'AN'),
        ('E4', 'G1', 4, N'AN'),
        ('E5', 'G1', 4, N'AN'),
        ('E6', 'G1', 4, N'AN'),
        ('E1', 'G1', 5, N'AN'),
        ('E2', 'G1', 5, N'AN'),
        ('E3', 'G1', 5, N'AN'),
        ('E4', 'G1', 5, N'AN'),
        ('E5', 'G1', 5, N'AN'),
        ('E6', 'G1', 5, N'AN'),
        ('E1', 'G1', 6, N'AN'),
        ('E2', 'G1', 6, N'AN'),
        ('E3', 'G1', 6, N'AN'),
        ('E4', 'G1', 6, N'AN'),
        ('E5', 'G1', 6, N'AN'),
        ('E6', 'G1', 6, N'AN'),
        ('E5', 'G2', 1, N'SJC'),
        ('E5', 'G2', 2, N'SJC'),
        ('E5', 'G2', 3, N'AN'),
        ('E7', 'G3', 1, N'SJC'),
        ('E7', 'G3', 2, N'AN');
    CREATE TABLE #asi (id UNIQUEIDENTIFIER, egId UNIQUEIDENTIFIER, sesId UNIQUEIDENTIFIER, codigo NVARCHAR(5));
    INSERT INTO #asi (id, egId, sesId, codigo)
    SELECT NEWID(), x.id, s.id, r.codigo FROM #reg r INNER JOIN #eg x ON x.k = r.k AND x.g = r.g INNER JOIN #s s ON s.k = r.g AND s.n = r.n;
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion) SELECT id, egId, sesId FROM #asi;
    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
    SELECT NEWID(), 1, a.id, IIF(a.codigo = N'SJC', 0, 1), rc.id, @ahora, @ahora FROM #asi a INNER JOIN dbo.RazonCausa rc ON rc.codigo = a.codigo;


    -- Fixture de administrador: F2 y F3 (inactiva) en I1, F4 en I2, programas PX/P4/P5, periodo pasado, grupo G4 de un 2do docente
    DECLARE @uDec2 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 13), @uC3 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 14),
            @uE1 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 5), @uA1 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 15),
            @uA2 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 16), @uDoc2 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 17);
    DECLARE @dec2 UNIQUEIDENTIFIER = NEWID(), @f2 UNIQUEIDENTIFIER = NEWID(), @f3 UNIQUEIDENTIFIER = NEWID(), @f4 UNIQUEIDENTIFIER = NEWID(),
            @c3 UNIQUEIDENTIFIER = NEWID(), @px UNIQUEIDENTIFIER = NEWID(), @p4 UNIQUEIDENTIFIER = NEWID(), @p5 UNIQUEIDENTIFIER = NEWID(),
            @perPast UNIQUEIDENTIFIER = NEWID(), @g4 UNIQUEIDENTIFIER = NEWID(), @doc2 UNIQUEIDENTIFIER = NEWID(),
            @adm1 UNIQUEIDENTIFIER = NEWID(), @adm2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Decano (id, usuario) VALUES (@dec2, @uDec2);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES
        (@f2, CONCAT(N'QA KPI F2 ', @sufijo), @i1, @dec2, 1),
        (@f3, CONCAT(N'QA KPI F3 ', @sufijo), @i1, @dec2, 0),
        (@f4, CONCAT(N'QA KPI F4 ', @sufijo), @i2, @dec2, 1);
    INSERT INTO dbo.Coordinador (id, usuario, facultad) VALUES (@c3, @uC3, @f2);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES
        (@px, @f2, @tipoProg, CONCAT(N'KPI PX ', @sufijo), @c3, 1),
        (@p4, @f, @tipoProg, CONCAT(N'KPI P4 ', @sufijo), @c2, 0),
        (@p5, @f4, @tipoProg, CONCAT(N'KPI P5 ', @sufijo), @c3, 1);
    INSERT INTO dbo.Administrador (id, usuario, institucion) VALUES (@adm1, @uA1, @i1), (@adm2, @uA2, @i2);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@doc2, @uDoc2);
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@perPast, @i1, CONCAT(N'QA KPI PAST ', @sufijo), 950000 + ABS(CHECKSUM(NEWID()) % 9999), DATEADD(DAY, -400, @hoy), DATEADD(DAY, -300, @hoy), YEAR(@hoy) - 1);
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g4, @a1, @perPast, 960000 + ABS(CHECKSUM(NEWID()) % 9999), N'Grupo G4', 20, 0, 0, 0, @doc2);
    DECLARE @c UNIQUEIDENTIFIER = NEWID(), @inexistente UNIQUEIDENTIFIER = NEWID(), @err NVARCHAR(4000);
    CREATE TABLE #k (idInstitucion UNIQUEIDENTIFIER, nombreInstitucion NVARCHAR(50), idPeriodoAcademico UNIQUEIDENTIFIER, nombrePeriodoAcademico NVARCHAR(50),
        totalFacultades INT, totalProgramas INT, totalEstudiantes INT, estudiantesRegulares INT, estudiantesRiesgo INT, estudiantesPerdida INT, tasaRetencion DECIMAL(5,2),
        sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2), porcentajeAsistencia DECIMAL(5,2),
        sesionesVencidas INT, sesionesConRegistro INT, porcentajeCumplimiento DECIMAL(5,2),
        estudiantesConMatriculaActiva INT, estudiantesRegistrados INT, docentesConGrupoActivo INT, docentesRegistrados INT,
        umbralAdvertencia DECIMAL(5,2), umbralPerdida DECIMAL(5,2));
    -- T-DB-05: cifras exactas de I1 (periodo por defecto)
    INSERT INTO #k EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = @uA1, @idCorrelacion = @c, @idPeriodoAcademico = NULL;
    IF NOT ((SELECT COUNT(*) FROM #k) = 1) THROW 54301, 'TEST FAILED: se esperaba exactamente 1 fila', 1;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE idInstitucion = @i1 AND idPeriodoAcademico = @per AND totalFacultades = 3 AND totalProgramas = 4)
        THROW 54302, 'TEST FAILED: T-DB-05 institucion/periodo/facultades/programas (I1 / periodo vigente / 3 facultades / 4 programas)', 1;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE totalEstudiantes = 6 AND estudiantesRegulares = 2 AND estudiantesRiesgo = 1 AND estudiantesPerdida = 3 AND tasaRetencion = 50.00)
        THROW 54303, 'TEST FAILED: T-DB-05 conteos distintos de los calculados a mano (6 / 2 / 1 / 3 / 50.00)', 1;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE sesionesEjecutadas = 35 AND faltasSinJustaCausa = 6 AND porcentajeAusentismo = 17.14 AND porcentajeAsistencia = 82.86)
        THROW 54304, 'TEST FAILED: T-DB-05 ausentismo ponderado distinto del calculado a mano (35 / 6 / 17.14 / 82.86)', 1;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE sesionesVencidas = 12 AND sesionesConRegistro = 11 AND porcentajeCumplimiento = 91.67)
        THROW 54305, 'TEST FAILED: T-DB-05 cumplimiento distinto del calculado a mano (12 / 11 / 91.67)', 1;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE estudiantesConMatriculaActiva = 6 AND estudiantesRegistrados = 7 AND docentesConGrupoActivo = 1 AND docentesRegistrados = 2 AND umbralAdvertencia = 15 AND umbralPerdida = 20)
        THROW 54306, 'TEST FAILED: T-DB-09 censo distinto del calculado a mano (6 con matricula / 7 registrados / 1 docente con grupo / 2 registrados / 15 / 20)', 1;
    -- T-DB-06: invariantes
    IF EXISTS (SELECT 1 FROM #k WHERE estudiantesRegulares + estudiantesRiesgo + estudiantesPerdida <> totalEstudiantes OR totalEstudiantes <> estudiantesConMatriculaActiva OR sesionesConRegistro > sesionesVencidas)
        THROW 54307, 'TEST FAILED: T-DB-06 invariantes (regulares+riesgo+perdida = total = con matricula; con registro <= vencidas)', 1;
    -- T-DB-10: conciliacion contra tablas
    DECLARE @faltasDirectas INT = (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia
        INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa INNER JOIN dbo.EstudianteGrupo eg ON eg.id = a.estudianteGrupo
        INNER JOIN dbo.Grupo g ON g.id = eg.grupo INNER JOIN dbo.Asignatura asg ON asg.id = g.asignatura INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = asg.semestrePlanEstudio
        INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio INNER JOIN dbo.Programa pr ON pr.id = pe.programa INNER JOIN dbo.Facultad fa ON fa.id = pr.facultad
        WHERE fa.institucion = @i1 AND da.asistio = 0 AND rc.codigo = N'SJC');
    IF @faltasDirectas <> 6 THROW 54308, 'TEST FAILED T-DB-10: consulta de control = 6 faltas SJC en la institucion', 1;
    DECLARE @facultadesDirectas INT = (SELECT COUNT(*) FROM dbo.Facultad WHERE institucion = @i1);
    DECLARE @programasDirectos INT = (SELECT COUNT(*) FROM dbo.Programa pr INNER JOIN dbo.Facultad fa ON fa.id = pr.facultad WHERE fa.institucion = @i1);
    IF @facultadesDirectas <> 3 OR @programasDirectos <> 4 THROW 54309, 'TEST FAILED T-DB-10: consulta de control = 3 facultades y 4 programas', 1;
    PRINT 'TEST_PASS:HU133_HU138_HU135_HU136_KPIS_EXACTOS';
    TRUNCATE TABLE #k;

    -- T-DB-07/08: aislamiento. A2 solo ve I2 (1 facultad, 1 programa, sin datos): NULL en porcentajes, no ceros inventados
    INSERT INTO #k EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = @uA2, @idCorrelacion = @c, @idPeriodoAcademico = NULL;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE idInstitucion = @i2 AND idPeriodoAcademico IS NULL AND totalFacultades = 1 AND totalProgramas = 1 AND totalEstudiantes = 0
            AND tasaRetencion IS NULL AND sesionesEjecutadas = 0 AND faltasSinJustaCausa = 0 AND porcentajeAusentismo IS NULL AND porcentajeAsistencia IS NULL
            AND sesionesVencidas = 0 AND sesionesConRegistro = 0 AND porcentajeCumplimiento IS NULL AND estudiantesConMatriculaActiva = 0 AND estudiantesRegistrados = 0
            AND docentesConGrupoActivo = 0 AND docentesRegistrados = 0)
        THROW 54310, 'TEST FAILED: T-DB-07/08 I2 sin datos: ceros en conteos y NULL en porcentajes', 1;
    TRUNCATE TABLE #k;

    -- Periodo pasado explicito: G4 no habilitado, sin matriculas ni sesiones; los registrados no dependen del periodo
    INSERT INTO #k EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = @uA1, @idCorrelacion = @c, @idPeriodoAcademico = @perPast;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE idPeriodoAcademico = @perPast AND totalEstudiantes = 0 AND tasaRetencion IS NULL AND porcentajeAusentismo IS NULL AND porcentajeCumplimiento IS NULL
            AND docentesConGrupoActivo = 0 AND estudiantesRegistrados = 7 AND docentesRegistrados = 2)
        THROW 54311, 'TEST FAILED: periodo pasado explicito', 1;
    TRUNCATE TABLE #k;

    -- Errores
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k (idInstitucion, nombreInstitucion, idPeriodoAcademico, nombrePeriodoAcademico, totalFacultades, totalProgramas, totalEstudiantes, estudiantesRegulares, estudiantesRiesgo, estudiantesPerdida, tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo, porcentajeAsistencia, sesionesVencidas, sesionesConRegistro, porcentajeCumplimiento, estudiantesConMatriculaActiva, estudiantesRegistrados, docentesConGrupoActivo, docentesRegistrados, umbralAdvertencia, umbralPerdida) EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = @uDec, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_004|%'
        THROW 54321, 'TEST FAILED: T-DB-02 decano (esperaba KPI_004).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k (idInstitucion, nombreInstitucion, idPeriodoAcademico, nombrePeriodoAcademico, totalFacultades, totalProgramas, totalEstudiantes, estudiantesRegulares, estudiantesRiesgo, estudiantesPerdida, tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo, porcentajeAsistencia, sesionesVencidas, sesionesConRegistro, porcentajeCumplimiento, estudiantesConMatriculaActiva, estudiantesRegistrados, docentesConGrupoActivo, docentesRegistrados, umbralAdvertencia, umbralPerdida) EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = @uC1, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_004|%'
        THROW 54322, 'TEST FAILED: T-DB-02 coordinador (esperaba KPI_004).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k (idInstitucion, nombreInstitucion, idPeriodoAcademico, nombrePeriodoAcademico, totalFacultades, totalProgramas, totalEstudiantes, estudiantesRegulares, estudiantesRiesgo, estudiantesPerdida, tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo, porcentajeAsistencia, sesionesVencidas, sesionesConRegistro, porcentajeCumplimiento, estudiantesConMatriculaActiva, estudiantesRegistrados, docentesConGrupoActivo, docentesRegistrados, umbralAdvertencia, umbralPerdida) EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = @uPlano, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_004|%'
        THROW 54323, 'TEST FAILED: T-DB-02 usuario sin perfil (esperaba KPI_004).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k (idInstitucion, nombreInstitucion, idPeriodoAcademico, nombrePeriodoAcademico, totalFacultades, totalProgramas, totalEstudiantes, estudiantesRegulares, estudiantesRiesgo, estudiantesPerdida, tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo, porcentajeAsistencia, sesionesVencidas, sesionesConRegistro, porcentajeCumplimiento, estudiantesConMatriculaActiva, estudiantesRegistrados, docentesConGrupoActivo, docentesRegistrados, umbralAdvertencia, umbralPerdida) EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = @uE1, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_004|%'
        THROW 54324, 'TEST FAILED: T-DB-02 estudiante (esperaba KPI_004).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k (idInstitucion, nombreInstitucion, idPeriodoAcademico, nombrePeriodoAcademico, totalFacultades, totalProgramas, totalEstudiantes, estudiantesRegulares, estudiantesRiesgo, estudiantesPerdida, tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo, porcentajeAsistencia, sesionesVencidas, sesionesConRegistro, porcentajeCumplimiento, estudiantesConMatriculaActiva, estudiantesRegistrados, docentesConGrupoActivo, docentesRegistrados, umbralAdvertencia, umbralPerdida) EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = @uA1, @idCorrelacion = @c, @idPeriodoAcademico = @inexistente;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=PER_001|%'
        THROW 54325, 'TEST FAILED: periodo inexistente (esperaba PER_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k (idInstitucion, nombreInstitucion, idPeriodoAcademico, nombrePeriodoAcademico, totalFacultades, totalProgramas, totalEstudiantes, estudiantesRegulares, estudiantesRiesgo, estudiantesPerdida, tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo, porcentajeAsistencia, sesionesVencidas, sesionesConRegistro, porcentajeCumplimiento, estudiantesConMatriculaActiva, estudiantesRegistrados, docentesConGrupoActivo, docentesRegistrados, umbralAdvertencia, umbralPerdida) EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = @uA1, @idCorrelacion = NULL;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=CORR_001|%'
        THROW 54326, 'TEST FAILED: correlacion nula (esperaba CORR_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k (idInstitucion, nombreInstitucion, idPeriodoAcademico, nombrePeriodoAcademico, totalFacultades, totalProgramas, totalEstudiantes, estudiantesRegulares, estudiantesRiesgo, estudiantesPerdida, tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo, porcentajeAsistencia, sesionesVencidas, sesionesConRegistro, porcentajeCumplimiento, estudiantesConMatriculaActiva, estudiantesRegistrados, docentesConGrupoActivo, docentesRegistrados, umbralAdvertencia, umbralPerdida) EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = NULL, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=VAL_001|%'
        THROW 54327, 'TEST FAILED: ejecutor nulo (esperaba VAL_001).', 1;
    UPDATE dbo.CatalogoParametro SET estaActivo = 0 WHERE grupo = N'ASISTENCIA' AND clave = N'UMBRAL_ALERTA_PERDIDA';
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k (idInstitucion, nombreInstitucion, idPeriodoAcademico, nombrePeriodoAcademico, totalFacultades, totalProgramas, totalEstudiantes, estudiantesRegulares, estudiantesRiesgo, estudiantesPerdida, tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo, porcentajeAsistencia, sesionesVencidas, sesionesConRegistro, porcentajeCumplimiento, estudiantesConMatriculaActiva, estudiantesRegistrados, docentesConGrupoActivo, docentesRegistrados, umbralAdvertencia, umbralPerdida) EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = @uA1, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_002|%'
        THROW 54328, 'TEST FAILED: umbral ausente (esperaba KPI_002).', 1;
    UPDATE dbo.CatalogoParametro SET estaActivo = 1 WHERE grupo = N'ASISTENCIA' AND clave = N'UMBRAL_ALERTA_PERDIDA';
    PRINT 'TEST_PASS:HU133_KPIS_AMBITO_Y_ERRORES';

    -- Sin periodo vigente: una fila con ceros y NULL; el periodo anterior sigue consultable de forma explicita
    UPDATE dbo.PeriodoAcademico SET fechaFin = DATEADD(DAY, -1, @hoy), fechaInicio = DATEADD(DAY, -90, @hoy) WHERE id = @per;
    INSERT INTO #k EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = @uA1, @idCorrelacion = @c, @idPeriodoAcademico = NULL;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE idPeriodoAcademico IS NULL AND totalFacultades = 3 AND totalProgramas = 4 AND totalEstudiantes = 0 AND tasaRetencion IS NULL AND porcentajeAusentismo IS NULL AND porcentajeCumplimiento IS NULL)
        THROW 54340, 'TEST FAILED: sin periodo vigente', 1;
    TRUNCATE TABLE #k;
    INSERT INTO #k EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = @uA1, @idCorrelacion = @c, @idPeriodoAcademico = @per;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE totalEstudiantes = 6 AND sesionesEjecutadas = 35)
        THROW 54341, 'TEST FAILED: periodo explicito pasado', 1;
    DROP TABLE #k;

    IF @@TRANCOUNT <> 1 THROW 54098, 'TEST FAILED: el objeto altero el nivel de transaccion del llamador.', 1;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 54099, 'TEST FAILED: test_usp_consultar_kpis_institucion dejo transacciones abiertas.', 1;
