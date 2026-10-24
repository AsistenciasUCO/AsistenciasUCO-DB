USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_consultar_kpis_coordinador (HU065)';
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
    WHILE @i <= 12
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
    SELECT g.id, CASE g.k WHEN N'G1' THEN @a1 WHEN N'G2' THEN @a2 ELSE @a3 END, @per, 930000 + ABS(CHECKSUM(NEWID()) % 99999), CONCAT(N'Grupo ', g.k), 40, 0, 0, 0, @doc FROM #g g;

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

    -- Usuarios ejecutores y de estudiantes por clave
    DECLARE @uE1 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 5), @uE5 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 9);
    DECLARE @idE1 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #e WHERE k = N'E1'), @idE2 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #e WHERE k = N'E2'),
            @idE3 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #e WHERE k = N'E3'), @idE4 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #e WHERE k = N'E4'),
            @idE5 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #e WHERE k = N'E5'), @idE7 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #e WHERE k = N'E7');
    DECLARE @g1 UNIQUEIDENTIFIER = (SELECT id FROM #g WHERE k = N'G1'), @g2 UNIQUEIDENTIFIER = (SELECT id FROM #g WHERE k = N'G2');
    DECLARE @c UNIQUEIDENTIFIER, @inexistente UNIQUEIDENTIFIER = NEWID();

    CREATE TABLE #k (idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(50), idPeriodoAcademico UNIQUEIDENTIFIER, nombrePeriodoAcademico NVARCHAR(50),
        totalEstudiantes INT, estudiantesRegulares INT, estudiantesRiesgo INT, estudiantesPerdida INT, tasaPermanencia DECIMAL(5,2),
        sesionesProgramadas INT, sesionesVencidas INT, sesionesEjecutadas INT, sesionesVencidasSinRegistro INT, sesionesSinProcedenciaTemporal INT,
        porcentajeCumplimiento DECIMAL(5,2), porcentajeProgresoCalendario DECIMAL(5,2), umbralAdvertencia DECIMAL(5,2), umbralPerdida DECIMAL(5,2));
    DECLARE @err NVARCHAR(4000);
    SET @c = NEWID();

    -- T-KPI-01/03/06: cifras exactas del programa P1 (periodo vigente por defecto)
    INSERT INTO #k EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idPeriodoAcademico = NULL;
    IF NOT ((SELECT COUNT(*) FROM #k) = 1)
        THROW 53201, 'TEST FAILED: se esperaba exactamente 1 fila', 1;
    IF NOT (EXISTS (SELECT 1 FROM #k WHERE idPrograma = @p1 AND idPeriodoAcademico = @per AND totalEstudiantes = 5 AND estudiantesRegulares = 2 AND estudiantesRiesgo = 1 AND estudiantesPerdida = 2 AND tasaPermanencia = 60.00))
        THROW 53202, 'TEST FAILED: T-KPI-01/02 conteos de permanencia distintos de los calculados a mano (5 / 2 / 1 / 2 / 60.00)', 1;
    IF NOT (EXISTS (SELECT 1 FROM #k WHERE sesionesProgramadas = 15 AND sesionesVencidas = 10 AND sesionesEjecutadas = 9 AND sesionesVencidasSinRegistro = 1 AND sesionesSinProcedenciaTemporal = 1 AND porcentajeCumplimiento = 90.00 AND porcentajeProgresoCalendario = 66.67))
        THROW 53203, 'TEST FAILED: T-KPI-03 cumplimiento distinto del calculado a mano (15 / 10 / 9 / 1 / 1 / 90.00 / 66.67)', 1;
    IF NOT (EXISTS (SELECT 1 FROM #k WHERE umbralAdvertencia = 15 AND umbralPerdida = 20))
        THROW 53204, 'TEST FAILED: T-KPI-06 eco de umbrales', 1;
    PRINT 'TEST_PASS:HU065_HU070_KPIS_EXACTOS';
    TRUNCATE TABLE #k;

    -- T-KPI-07: conciliacion contra una consulta directa sobre las tablas (sin usar las vistas nuevas)
    DECLARE @faltasDirectas INT = (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia
        INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa INNER JOIN dbo.EstudianteGrupo eg ON eg.id = a.estudianteGrupo
        INNER JOIN dbo.Grupo g ON g.id = eg.grupo INNER JOIN dbo.Asignatura asg ON asg.id = g.asignatura INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = asg.semestrePlanEstudio
        INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio WHERE pe.programa = @p1 AND da.asistio = 0 AND rc.codigo = N'SJC');
    IF @faltasDirectas <> 5 THROW 53205, 'TEST FAILED T-KPI-07: el fixture debia tener 5 faltas SJC en P1 (2+1+0+0+2).', 1;

    -- T-SEC-01: el coordinador de P2 solo ve P2
    INSERT INTO #k EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uC2, @idCorrelacion = @c, @idPeriodoAcademico = NULL;
    IF NOT (EXISTS (SELECT 1 FROM #k WHERE idPrograma = @p2 AND totalEstudiantes = 1 AND estudiantesPerdida = 1 AND sesionesProgramadas = 2 AND sesionesEjecutadas = 2))
        THROW 53206, 'TEST FAILED: T-SEC-01 el coordinador de P2 debe ver solo su programa (1 estudiante, 2 sesiones)', 1;
    TRUNCATE TABLE #k;

    -- T-KPI-04: periodo explicito inexistente
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idPeriodoAcademico = @inexistente;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=PER_001|%'
        THROW 53207, 'TEST FAILED: periodo inexistente (esperaba PER_001).', 1;
    -- T-KPI-04: periodo explicito = el vigente
    INSERT INTO #k EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idPeriodoAcademico = @per;
    IF NOT (EXISTS (SELECT 1 FROM #k WHERE totalEstudiantes = 5))
        THROW 53208, 'TEST FAILED: T-KPI-04 periodo explicito', 1;
    TRUNCATE TABLE #k;

    -- T-SEC-02: ejecutores que no son coordinador de un programa
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uDec, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_001|%'
        THROW 53209, 'TEST FAILED: decano (esperaba KPI_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uPlano, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_001|%'
        THROW 53210, 'TEST FAILED: usuario sin perfil (esperaba KPI_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uE1, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_001|%'
        THROW 53211, 'TEST FAILED: estudiante (esperaba KPI_001).', 1;

    -- T-SEC-03: correlacion y ejecutor nulos
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uC1, @idCorrelacion = NULL;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=CORR_001|%'
        THROW 53212, 'TEST FAILED: correlacion nula (esperaba CORR_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = NULL, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=VAL_001|%'
        THROW 53213, 'TEST FAILED: ejecutor nulo (esperaba VAL_001).', 1;

    -- T-DB-10: falta un umbral => KPI_002 (no se asume un valor)
    UPDATE dbo.CatalogoParametro SET estaActivo = 0 WHERE grupo = N'ASISTENCIA' AND clave = N'UMBRAL_ALERTA_PERDIDA';
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #k EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uC1, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_002|%'
        THROW 53214, 'TEST FAILED: umbral ausente (esperaba KPI_002).', 1;
    UPDATE dbo.CatalogoParametro SET estaActivo = 1 WHERE grupo = N'ASISTENCIA' AND clave = N'UMBRAL_ALERTA_PERDIDA';

    -- T-KPI-05: sin periodo vigente => una fila con ceros y porcentajes NULL (no es error)
    UPDATE dbo.PeriodoAcademico SET fechaFin = DATEADD(DAY, -1, @hoy), fechaInicio = DATEADD(DAY, -90, @hoy) WHERE id = @per;
    INSERT INTO #k EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idPeriodoAcademico = NULL;
    IF NOT (EXISTS (SELECT 1 FROM #k WHERE idPeriodoAcademico IS NULL AND totalEstudiantes = 0 AND sesionesProgramadas = 0 AND porcentajeCumplimiento IS NULL AND porcentajeProgresoCalendario IS NULL AND tasaPermanencia IS NULL))
        THROW 53215, 'TEST FAILED: T-KPI-05 sin periodo vigente', 1;
    PRINT 'TEST_PASS:HU065_KPIS_AMBITO_Y_ERRORES';

    -- T-KPI-05 (cont.): el periodo anterior sigue consultable de forma explicita (D8)
    TRUNCATE TABLE #k;
    INSERT INTO #k EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idPeriodoAcademico = @per;
    IF NOT (EXISTS (SELECT 1 FROM #k WHERE totalEstudiantes = 5 AND sesionesEjecutadas = 9))
        THROW 53216, 'TEST FAILED: D8 periodo explicito pasado', 1;
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
    THROW 53099, 'TEST FAILED: test_usp_consultar_kpis_coordinador dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_consultar_kpis_coordinador (HU065 OK)';
PRINT '==================================================';
GO
