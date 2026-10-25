USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_resolvers_institucion_admin (HU133)';
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
    DECLARE @idI UNIQUEIDENTIFIER, @idPer UNIQUEIDENTIFIER;
    -- T-DB-01: administrador => su institucion
    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @uA1, @idCorrelacion = @c, @validarUmbrales = 1, @idInstitucion = @idI OUTPUT;
    IF @idI IS NULL OR @idI <> @i1 THROW 54100, 'TEST FAILED: T-DB-01 el administrador A1 debia resolver I1', 1;
    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @uA2, @idCorrelacion = @c, @validarUmbrales = 1, @idInstitucion = @idI OUTPUT;
    IF @idI IS NULL OR @idI <> @i2 THROW 54100, 'TEST FAILED: T-DB-01 el administrador A2 debia resolver I2', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @validarUmbrales = 1, @idInstitucion = @idI OUTPUT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_004|%'
        THROW 54101, 'TEST FAILED: T-DB-02 decano (esperaba KPI_004).', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @validarUmbrales = 1, @idInstitucion = @idI OUTPUT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_004|%'
        THROW 54102, 'TEST FAILED: T-DB-02 coordinador (esperaba KPI_004).', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @uPlano, @idCorrelacion = @c, @validarUmbrales = 1, @idInstitucion = @idI OUTPUT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_004|%'
        THROW 54103, 'TEST FAILED: T-DB-02 usuario sin perfil (esperaba KPI_004).', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @uE1, @idCorrelacion = @c, @validarUmbrales = 1, @idInstitucion = @idI OUTPUT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_004|%'
        THROW 54104, 'TEST FAILED: T-DB-02 estudiante (esperaba KPI_004).', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @uDoc, @idCorrelacion = @c, @validarUmbrales = 1, @idInstitucion = @idI OUTPUT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_004|%'
        THROW 54105, 'TEST FAILED: T-DB-02 docente (esperaba KPI_004).', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = NULL, @idCorrelacion = @c, @validarUmbrales = 1, @idInstitucion = @idI OUTPUT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=VAL_001|%'
        THROW 54106, 'TEST FAILED: T-DB-03 ejecutor nulo (esperaba VAL_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @uA1, @idCorrelacion = NULL, @validarUmbrales = 1, @idInstitucion = @idI OUTPUT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=CORR_001|%'
        THROW 54107, 'TEST FAILED: T-DB-03 correlacion nula (esperaba CORR_001).', 1;
    UPDATE dbo.CatalogoParametro SET estaActivo = 0 WHERE grupo = N'ASISTENCIA' AND clave = N'UMBRAL_ALERTA_PERDIDA';
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @uA1, @idCorrelacion = @c, @validarUmbrales = 1, @idInstitucion = @idI OUTPUT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_002|%'
        THROW 54108, 'TEST FAILED: T-DB-03 umbral ausente (esperaba KPI_002).', 1;
    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @uA1, @idCorrelacion = @c, @validarUmbrales = 0, @idInstitucion = @idI OUTPUT;
    IF @idI <> @i1 THROW 54199, 'TEST FAILED: T-DB-03 con validarUmbrales = 0 no debe exigir el umbral', 1;
    UPDATE dbo.CatalogoParametro SET estaActivo = 1 WHERE grupo = N'ASISTENCIA' AND clave = N'UMBRAL_ALERTA_PERDIDA';
    PRINT 'TEST_PASS:HU133_RESOLVER_INSTITUCION';

    -- T-DB-04: periodo
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @i1, @idPeriodoSolicitado = NULL, @idPeriodo = @idPer OUTPUT;
    IF @idPer IS NULL OR @idPer <> @per THROW 54200, 'TEST FAILED: T-DB-04 por defecto debia ser el periodo con grupos habilitados', 1;
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @i1, @idPeriodoSolicitado = @perPast, @idPeriodo = @idPer OUTPUT;
    IF @idPer IS NULL OR @idPer <> @perPast THROW 54201, 'TEST FAILED: T-DB-04 periodo explicito', 1;
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @i2, @idPeriodoSolicitado = NULL, @idPeriodo = @idPer OUTPUT;
    IF @idPer IS NOT NULL THROW 54202, 'TEST FAILED: T-DB-04 institucion sin grupos => NULL', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @i1, @idPeriodoSolicitado = @inexistente, @idPeriodo = @idPer OUTPUT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=PER_001|%'
        THROW 54203, 'TEST FAILED: T-DB-04 periodo inexistente (esperaba PER_001).', 1;
    PRINT 'TEST_PASS:HU133_RESOLVER_PERIODO';

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
    THROW 54099, 'TEST FAILED: test_usp_resolvers_institucion_admin dejo transacciones abiertas.', 1;
