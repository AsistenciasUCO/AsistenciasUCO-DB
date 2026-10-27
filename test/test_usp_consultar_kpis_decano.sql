USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_consultar_kpis_decano (HU102/HU106/HU144)';
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
    WHILE @i <= 14
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


    -- Fixture de decano: 2da facultad F2 (decano2, sin grupos), programa PX de F2, programa inactivo P4 de F, periodo pasado y grupo G4
    DECLARE @uDec2 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 13), @uC3 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 14),
            @uE1 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 5);
    DECLARE @dec2 UNIQUEIDENTIFIER = NEWID(), @f2 UNIQUEIDENTIFIER = NEWID(), @c3 UNIQUEIDENTIFIER = NEWID(), @px UNIQUEIDENTIFIER = NEWID(),
            @p4 UNIQUEIDENTIFIER = NEWID(), @perPast UNIQUEIDENTIFIER = NEWID(), @g4 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Decano (id, usuario) VALUES (@dec2, @uDec2);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@f2, CONCAT(N'QA KPI F2 ', @sufijo), @idInstitucion, @dec2, 1);
    INSERT INTO dbo.Coordinador (id, usuario, facultad) VALUES (@c3, @uC3, @f2);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES (@px, @f2, @tipoProg, CONCAT(N'KPI PX ', @sufijo), @c3, 1), (@p4, @f, @tipoProg, CONCAT(N'KPI P4 ', @sufijo), @c2, 0);
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@perPast, @idInstitucion, CONCAT(N'QA KPI PAST ', @sufijo), 950000 + ABS(CHECKSUM(NEWID()) % 9999), DATEADD(DAY, -400, @hoy), DATEADD(DAY, -300, @hoy), YEAR(@hoy) - 1);
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g4, @a1, @perPast, 960000 + ABS(CHECKSUM(NEWID()) % 9999), N'Grupo G4', 20, 0, 0, 0, @doc);
    DECLARE @c UNIQUEIDENTIFIER = NEWID(), @inexistente UNIQUEIDENTIFIER = NEWID(), @err NVARCHAR(4000);
    DECLARE @g1 UNIQUEIDENTIFIER = (SELECT id FROM #g WHERE k = N'G1'), @g2 UNIQUEIDENTIFIER = (SELECT id FROM #g WHERE k = N'G2'), @g3 UNIQUEIDENTIFIER = (SELECT id FROM #g WHERE k = N'G3');
    CREATE TABLE #k (idFacultad UNIQUEIDENTIFIER, nombreFacultad NVARCHAR(50), idPeriodoAcademico UNIQUEIDENTIFIER, nombrePeriodoAcademico NVARCHAR(50),
        totalProgramas INT, totalEstudiantes INT, estudiantesRegulares INT, estudiantesRiesgo INT, estudiantesPerdida INT, tasaRetencion DECIMAL(5,2),
        sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2), porcentajeAsistencia DECIMAL(5,2),
        gruposActivos INT, cupoTotal INT, matriculadosActivos INT, tasaAforo DECIMAL(7,2), umbralAdvertencia DECIMAL(5,2), umbralPerdida DECIMAL(5,2));
    -- T-DB-06: cifras exactas de F (periodo por defecto)
    INSERT INTO #k EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @idPeriodoAcademico = NULL;
    IF NOT ((SELECT COUNT(*) FROM #k) = 1) THROW 53401, 'TEST FAILED: se esperaba exactamente 1 fila', 1;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE idFacultad = @f AND idPeriodoAcademico = @per AND totalProgramas = 3 AND totalEstudiantes = 6 AND estudiantesRegulares = 2 AND estudiantesRiesgo = 1 AND estudiantesPerdida = 3 AND tasaRetencion = 50.00)
        THROW 53402, 'TEST FAILED: T-DB-06 conteos distintos de los calculados a mano (3 programas / 6 / 2 / 1 / 3 / 50.00)', 1;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE sesionesEjecutadas = 35 AND faltasSinJustaCausa = 6 AND porcentajeAusentismo = 17.14 AND porcentajeAsistencia = 82.86)
        THROW 53403, 'TEST FAILED: T-DB-06 ausentismo ponderado distinto del calculado a mano (35 / 6 / 17.14 / 82.86)', 1;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE gruposActivos = 3 AND cupoTotal = 55 AND matriculadosActivos = 7 AND tasaAforo = 12.73 AND umbralAdvertencia = 15 AND umbralPerdida = 20)
        THROW 53404, 'TEST FAILED: T-DB-06 aforo/umbrales distintos de los calculados a mano (3 / 55 / 7 / 12.73 / 15 / 20)', 1;
    -- T-DB-07: invariante y conciliacion contra tablas
    IF EXISTS (SELECT 1 FROM #k WHERE estudiantesRegulares + estudiantesRiesgo + estudiantesPerdida <> totalEstudiantes)
        THROW 53405, 'TEST FAILED: T-DB-07 regulares + riesgo + perdida debe ser el total', 1;
    DECLARE @faltasDirectas INT = (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia
        INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa INNER JOIN dbo.EstudianteGrupo eg ON eg.id = a.estudianteGrupo
        INNER JOIN dbo.Grupo g ON g.id = eg.grupo INNER JOIN dbo.Asignatura asg ON asg.id = g.asignatura INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = asg.semestrePlanEstudio
        INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio INNER JOIN dbo.Programa pr ON pr.id = pe.programa
        WHERE pr.facultad = @f AND da.asistio = 0 AND rc.codigo = N'SJC');
    IF @faltasDirectas <> 6 THROW 53406, 'TEST FAILED T-DB-07: consulta de control = 6 faltas SJC en la facultad', 1;
    PRINT 'TEST_PASS:HU102_HU106_HU144_KPIS_EXACTOS';
    TRUNCATE TABLE #k;

    -- T-DB-08/09: aislamiento. El decano2 solo ve F2 (1 programa, sin matriculas): NULL en porcentajes, no ceros inventados
    INSERT INTO #k EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uDec2, @idCorrelacion = @c, @idPeriodoAcademico = NULL;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE idFacultad = @f2 AND idPeriodoAcademico IS NULL AND totalProgramas = 1 AND totalEstudiantes = 0 AND estudiantesRegulares = 0 AND estudiantesRiesgo = 0 AND estudiantesPerdida = 0
            AND tasaRetencion IS NULL AND sesionesEjecutadas = 0 AND faltasSinJustaCausa = 0 AND porcentajeAusentismo IS NULL AND porcentajeAsistencia IS NULL AND gruposActivos = 0 AND cupoTotal = 0 AND matriculadosActivos = 0 AND tasaAforo IS NULL)
        THROW 53407, 'TEST FAILED: T-DB-08/09 F2 sin datos: ceros en conteos y NULL en porcentajes', 1;
    TRUNCATE TABLE #k;

    -- Periodo pasado explicito: G4 no habilitado, sin matriculas => aforo NULL
    INSERT INTO #k EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @idPeriodoAcademico = @perPast;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE idPeriodoAcademico = @perPast AND totalEstudiantes = 0 AND tasaRetencion IS NULL AND porcentajeAusentismo IS NULL AND gruposActivos = 0 AND cupoTotal = 0 AND tasaAforo IS NULL)
        THROW 53408, 'TEST FAILED: periodo pasado explicito', 1;
    TRUNCATE TABLE #k;

    -- Errores
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uC1, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_003|%'
        THROW 53410, 'TEST FAILED: T-DB-02 coordinador (esperaba KPI_003).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uPlano, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_003|%'
        THROW 53411, 'TEST FAILED: T-DB-02 usuario sin perfil (esperaba KPI_003).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uE1, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_003|%'
        THROW 53412, 'TEST FAILED: T-DB-02 estudiante (esperaba KPI_003).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @idPeriodoAcademico = @inexistente;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=PER_001|%'
        THROW 53413, 'TEST FAILED: periodo inexistente (esperaba PER_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uDec, @idCorrelacion = NULL;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=CORR_001|%'
        THROW 53414, 'TEST FAILED: correlacion nula (esperaba CORR_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = NULL, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=VAL_001|%'
        THROW 53415, 'TEST FAILED: ejecutor nulo (esperaba VAL_001).', 1;
    UPDATE dbo.CatalogoParametro SET estaActivo = 0 WHERE grupo = N'ASISTENCIA' AND clave = N'UMBRAL_ALERTA_PERDIDA';
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uDec, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_002|%'
        THROW 53416, 'TEST FAILED: umbral ausente (esperaba KPI_002).', 1;
    UPDATE dbo.CatalogoParametro SET estaActivo = 1 WHERE grupo = N'ASISTENCIA' AND clave = N'UMBRAL_ALERTA_PERDIDA';
    PRINT 'TEST_PASS:HU102_KPIS_AMBITO_Y_ERRORES';

    -- Sin periodo vigente (D7): una fila con ceros y NULL; el periodo anterior sigue consultable de forma explicita
    UPDATE dbo.PeriodoAcademico SET fechaFin = DATEADD(DAY, -3, @hoy), fechaInicio = DATEADD(DAY, -90, @hoy) WHERE id = @per;
    INSERT INTO #k EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @idPeriodoAcademico = NULL;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE idPeriodoAcademico IS NULL AND totalProgramas = 3 AND totalEstudiantes = 0 AND tasaRetencion IS NULL AND porcentajeAusentismo IS NULL AND gruposActivos = 0 AND tasaAforo IS NULL)
        THROW 53430, 'TEST FAILED: sin periodo vigente', 1;
    TRUNCATE TABLE #k;
    INSERT INTO #k EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @idPeriodoAcademico = @per;
    IF NOT EXISTS (SELECT 1 FROM #k WHERE totalEstudiantes = 6 AND sesionesEjecutadas = 35)
        THROW 53431, 'TEST FAILED: periodo explicito pasado', 1;
    DROP TABLE #k;

    IF @@TRANCOUNT <> 1 THROW 53098, 'TEST FAILED: el objeto altero el nivel de transaccion del llamador.', 1;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 53099, 'TEST FAILED: test_usp_consultar_kpis_decano dejo transacciones abiertas.', 1;
