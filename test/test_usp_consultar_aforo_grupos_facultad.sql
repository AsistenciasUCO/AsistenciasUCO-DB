USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_consultar_aforo_grupos_facultad (HU144)';
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
    CREATE TABLE #a (n INT IDENTITY(1,1), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(50),
        cupoMaximo INT, matriculadosActivos INT, cuposDisponibles INT, tasaAforo DECIMAL(7,2), grupoEstaHabilitado BIT, totalRegistros INT);
    -- T-DB-13/16: filas exactas ordenadas por aforo desc
    INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10;
    IF (SELECT COUNT(*) FROM #a) <> 3 OR EXISTS (SELECT 1 FROM #a WHERE totalRegistros <> 3) THROW 53601, 'TEST FAILED: T-DB-13 se esperaban 3 grupos habilitados (G1, G2, G3) con totalRegistros = 3', 1;
    IF NOT ((SELECT idGrupo FROM #a WHERE n = 1) = @g1 AND (SELECT idGrupo FROM #a WHERE n = 2) = @g2 AND (SELECT idGrupo FROM #a WHERE n = 3) = @g3)
        THROW 53608, 'TEST FAILED: T-DB-13 orden esperado G1 (50.00), G2 (20.00), G3 (2.50)', 1;
    IF NOT EXISTS (SELECT 1 FROM #a WHERE idGrupo = @g1 AND idPrograma = @p1 AND cupoMaximo = 10 AND matriculadosActivos = 5 AND cuposDisponibles = 5 AND tasaAforo = 50.00 AND grupoEstaHabilitado = 1)
        THROW 53602, 'TEST FAILED: T-DB-13 fila G1 distinta de la calculada a mano (10 / 5 / 5 / 50.00)', 1;
    IF NOT EXISTS (SELECT 1 FROM #a WHERE idGrupo = @g2 AND idPrograma = @p1 AND cupoMaximo = 5 AND matriculadosActivos = 1 AND cuposDisponibles = 4 AND tasaAforo = 20.00)
        THROW 53603, 'TEST FAILED: T-DB-13 fila G2 distinta de la calculada a mano (5 / 1 / 4 / 20.00)', 1;
    IF NOT EXISTS (SELECT 1 FROM #a WHERE idGrupo = @g3 AND idPrograma = @p2 AND cupoMaximo = 40 AND matriculadosActivos = 1 AND cuposDisponibles = 39 AND tasaAforo = 2.50)
        THROW 53604, 'TEST FAILED: T-DB-13 fila G3 distinta de la calculada a mano (40 / 1 / 39 / 2.50)', 1;
    PRINT 'TEST_PASS:HU144_AFORO_EXACTO';
    TRUNCATE TABLE #a;

    -- Paginacion: tamano 2 => [G1, G2] y [G3], total estable
    INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 2;
    IF NOT ((SELECT COUNT(*) FROM #a) = 2 AND (SELECT idGrupo FROM #a WHERE n = 1) = @g1 AND (SELECT idGrupo FROM #a WHERE n = 2) = @g2 AND NOT EXISTS (SELECT 1 FROM #a WHERE totalRegistros <> 3))
        THROW 53605, 'TEST FAILED: T-DB-13 pagina 1 (G1, G2, total 3)', 1;
    TRUNCATE TABLE #a;
    INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 2, @tamanoPagina = 2;
    IF NOT ((SELECT COUNT(*) FROM #a) = 1 AND EXISTS (SELECT 1 FROM #a WHERE idGrupo = @g3 AND totalRegistros = 3))
        THROW 53606, 'TEST FAILED: T-DB-13 pagina 2 (G3, total 3)', 1;
    TRUNCATE TABLE #a;

    -- T-DB-14: filtro por programa
    INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10, @idPrograma = @p2;
    IF NOT ((SELECT COUNT(*) FROM #a) = 1 AND EXISTS (SELECT 1 FROM #a WHERE idGrupo = @g3 AND totalRegistros = 1))
        THROW 53607, 'TEST FAILED: T-DB-14 filtro por P2 => solo G3', 1;
    TRUNCATE TABLE #a;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10, @idPrograma = @px;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=GEN_001|%'
        THROW 53620, 'TEST FAILED: T-DB-14 programa de otra facultad (esperaba GEN_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10, @idPrograma = @inexistente;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=GEN_001|%'
        THROW 53621, 'TEST FAILED: T-DB-14 programa inexistente (esperaba GEN_001).', 1;

    -- T-DB-15: soloHabilitados en el periodo pasado (G4 no habilitado; 0/20 = 0.00 es un dato real)
    INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10, @idPeriodoAcademico = @perPast, @soloHabilitados = 1;
    IF EXISTS (SELECT 1 FROM #a) THROW 53613, 'TEST FAILED: T-DB-15 soloHabilitados = 1 no debe listar grupos de un periodo vencido', 1;
    INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10, @idPeriodoAcademico = @perPast, @soloHabilitados = 0;
    IF NOT ((SELECT COUNT(*) FROM #a) = 1 AND EXISTS (SELECT 1 FROM #a WHERE idGrupo = @g4 AND cupoMaximo = 20 AND matriculadosActivos = 0 AND cuposDisponibles = 20 AND tasaAforo = 0.00 AND grupoEstaHabilitado = 0 AND totalRegistros = 1))
        THROW 53614, 'TEST FAILED: T-DB-15 soloHabilitados = 0 debe listar G4 (20 / 0 / 20 / 0.00 / no habilitado)', 1;
    TRUNCATE TABLE #a;

    -- T-DB-16: cupo 0 => tasa NULL (sin division por cero)
    UPDATE dbo.Grupo SET cantidadEstudiantes = 0 WHERE id = @g3;
    INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10, @idPrograma = @p2;
    IF NOT EXISTS (SELECT 1 FROM #a WHERE idGrupo = @g3 AND cupoMaximo = 0 AND tasaAforo IS NULL)
        THROW 53615, 'TEST FAILED: T-DB-16 cupo 0 => tasaAforo NULL', 1;
    UPDATE dbo.Grupo SET cantidadEstudiantes = 40 WHERE id = @g3;
    TRUNCATE TABLE #a;
    PRINT 'TEST_PASS:HU144_AFORO_FILTROS';

    -- Aislamiento y errores
    INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uDec2, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10;
    IF EXISTS (SELECT 1 FROM #a) THROW 53616, 'TEST FAILED: el decano2 no debe ver grupos de F', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_003|%'
        THROW 53622, 'TEST FAILED: T-DB-02 coordinador (esperaba KPI_003).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uE1, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_003|%'
        THROW 53623, 'TEST FAILED: T-DB-02 estudiante (esperaba KPI_003).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uPlano, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_003|%'
        THROW 53624, 'TEST FAILED: T-DB-02 usuario sin perfil (esperaba KPI_003).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 0, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=PAG_001|%'
        THROW 53625, 'TEST FAILED: T-DB-17 pagina 0 (esperaba PAG_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 101;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=PAG_001|%'
        THROW 53626, 'TEST FAILED: T-DB-17 tamano sobre el maximo (esperaba PAG_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10, @idPeriodoAcademico = @inexistente;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=PER_001|%'
        THROW 53627, 'TEST FAILED: periodo inexistente (esperaba PER_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #a (idGrupo, codigoGrupo, idAsignatura, nombreAsignatura, idPrograma, nombrePrograma, cupoMaximo, matriculadosActivos, cuposDisponibles, tasaAforo, grupoEstaHabilitado, totalRegistros) EXEC dbo.usp_consultar_aforo_grupos_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = NULL, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=CORR_001|%'
        THROW 53628, 'TEST FAILED: correlacion nula (esperaba CORR_001).', 1;
    PRINT 'TEST_PASS:HU144_AFORO_AMBITO_Y_ERRORES';
    DROP TABLE #a;

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
    THROW 53099, 'TEST FAILED: test_usp_consultar_aforo_grupos_facultad dejo transacciones abiertas.', 1;
