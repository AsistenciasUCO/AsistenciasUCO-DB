USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_consultar_bitacora_estudiante_programa (HU067)';
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

    CREATE TABLE #b (idSesion UNIQUEIDENTIFIER, numeroSesion INT, nombreSesion NVARCHAR(50), fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2, idGrupo UNIQUEIDENTIFIER,
        codigoGrupo INT, idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(50), asistio BIT, codigoRazonCausa NVARCHAR(5), nombreRazonCausa NVARCHAR(50), totalRegistros INT, ord INT IDENTITY(1,1));
    DECLARE @err NVARCHAR(4000);
    SET @c = NEWID();

    -- T-BIT-01: E5 esta en G1 (7 vencidas) y G2 (3 vencidas) = 10 filas, la mas reciente primero
    INSERT INTO #b (idSesion, numeroSesion, nombreSesion, fechaHoraInicio, fechaHoraFin, idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, asistio, codigoRazonCausa, nombreRazonCausa, totalRegistros) EXEC dbo.usp_consultar_bitacora_estudiante_programa @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idEstudiante = @idE5, @idPeriodoAcademico = NULL, @numeroPagina = 1, @tamanoPagina = 50;
    IF NOT ((SELECT COUNT(*) FROM #b) = 10 AND EXISTS (SELECT 1 FROM #b WHERE totalRegistros = 10))
        THROW 53401, 'TEST FAILED: T-BIT-01 E5 debe tener 10 filas de bitacora', 1;
    IF NOT ((SELECT TOP 1 numeroSesion FROM #b ORDER BY ord) = 7 AND (SELECT TOP 1 idGrupo FROM #b ORDER BY ord) = @g1)
        THROW 53402, 'TEST FAILED: T-BIT-01 la primera fila debe ser la sesion 7 de G1 (la mas reciente)', 1;
    IF EXISTS (SELECT 1 FROM #b a INNER JOIN #b n ON n.ord = a.ord + 1 WHERE n.fechaHoraInicio > a.fechaHoraInicio)
        THROW 53403, 'TEST FAILED T-BIT-01: el orden no es cronologico descendente.', 1;
    -- T-BIT-02: sesion vencida sin registro del estudiante => asistio NULL (no 0)
    IF (SELECT COUNT(*) FROM #b WHERE asistio IS NULL) <> 1 THROW 53404, 'TEST FAILED T-BIT-02: la sesion 7 sin registro debe tener asistio NULL.', 1;
    IF (SELECT COUNT(*) FROM #b WHERE asistio = 0 AND codigoRazonCausa = N'SJC') <> 2 THROW 53405, 'TEST FAILED: E5 debe tener 2 faltas SJC (G2).', 1;
    IF EXISTS (SELECT 1 FROM #b WHERE idGrupo NOT IN (@g1, @g2)) THROW 53406, 'TEST FAILED: aparecieron sesiones de otros grupos.', 1;
    TRUNCATE TABLE #b;
    PRINT 'TEST_PASS:HU067_BITACORA_EXACTA';

    -- T-BIT-03: paginacion
    INSERT INTO #b (idSesion, numeroSesion, nombreSesion, fechaHoraInicio, fechaHoraFin, idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, asistio, codigoRazonCausa, nombreRazonCausa, totalRegistros) EXEC dbo.usp_consultar_bitacora_estudiante_programa @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idEstudiante = @idE5, @idPeriodoAcademico = NULL, @numeroPagina = 2, @tamanoPagina = 4;
    IF NOT ((SELECT COUNT(*) FROM #b) = 4 AND EXISTS (SELECT 1 FROM #b WHERE totalRegistros = 10))
        THROW 53407, 'TEST FAILED: T-BIT-03 pagina 2 de tamano 4', 1;
    TRUNCATE TABLE #b;

    -- T-FIC-03 / CA-06: estudiante de otro programa o inexistente => GEN_001 identico
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #b (idSesion, numeroSesion, nombreSesion, fechaHoraInicio, fechaHoraFin, idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, asistio, codigoRazonCausa, nombreRazonCausa, totalRegistros) EXEC dbo.usp_consultar_bitacora_estudiante_programa @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idEstudiante = @idE7, @idPeriodoAcademico = NULL, @numeroPagina = 1, @tamanoPagina = 50;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=GEN_001|%'
        THROW 53408, 'TEST FAILED: estudiante de otro programa (esperaba GEN_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #b (idSesion, numeroSesion, nombreSesion, fechaHoraInicio, fechaHoraFin, idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, asistio, codigoRazonCausa, nombreRazonCausa, totalRegistros) EXEC dbo.usp_consultar_bitacora_estudiante_programa @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idEstudiante = @inexistente, @idPeriodoAcademico = NULL, @numeroPagina = 1, @tamanoPagina = 50;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=GEN_001|%'
        THROW 53409, 'TEST FAILED: estudiante inexistente (esperaba GEN_001).', 1;

    -- T-SEC: ejecutores sin perfil de coordinador
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #b (idSesion, numeroSesion, nombreSesion, fechaHoraInicio, fechaHoraFin, idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, asistio, codigoRazonCausa, nombreRazonCausa, totalRegistros) EXEC dbo.usp_consultar_bitacora_estudiante_programa @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @idEstudiante = @idE5, @idPeriodoAcademico = NULL, @numeroPagina = 1, @tamanoPagina = 50;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_001|%'
        THROW 53410, 'TEST FAILED: decano (esperaba KPI_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #b (idSesion, numeroSesion, nombreSesion, fechaHoraInicio, fechaHoraFin, idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, asistio, codigoRazonCausa, nombreRazonCausa, totalRegistros) EXEC dbo.usp_consultar_bitacora_estudiante_programa @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idEstudiante = NULL, @idPeriodoAcademico = NULL, @numeroPagina = 1, @tamanoPagina = 50;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=VAL_001|%'
        THROW 53411, 'TEST FAILED: estudiante nulo (esperaba VAL_001).', 1;

    -- T-SEC-01: el coordinador de P2 no ve a E5
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #b (idSesion, numeroSesion, nombreSesion, fechaHoraInicio, fechaHoraFin, idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, asistio, codigoRazonCausa, nombreRazonCausa, totalRegistros) EXEC dbo.usp_consultar_bitacora_estudiante_programa @idUsuarioEjecutor = @uC2, @idCorrelacion = @c, @idEstudiante = @idE5, @idPeriodoAcademico = NULL, @numeroPagina = 1, @tamanoPagina = 50;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=GEN_001|%'
        THROW 53412, 'TEST FAILED: coordinador de otro programa (esperaba GEN_001).', 1;
    DROP TABLE #b;
    PRINT 'TEST_PASS:HU067_BITACORA_AMBITO';

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
    THROW 53099, 'TEST FAILED: test_usp_consultar_bitacora_estudiante_programa dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_consultar_bitacora_estudiante_programa (HU067 OK)';
PRINT '==================================================';
GO
