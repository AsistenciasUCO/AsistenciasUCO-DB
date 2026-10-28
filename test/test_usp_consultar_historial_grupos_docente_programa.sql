USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_consultar_historial_grupos_docente_programa (HU094)';
PRINT '==================================================';

DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1);
DECLARE @tipoId        UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion);
DECLARE @tipoProg      UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma ORDER BY nombre);
DECLARE @semestre      UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Semestre);
DECLARE @area          UNIQUEIDENTIFIER = (SELECT TOP 1 area FROM dbo.Asignatura);
DECLARE @componente    UNIQUEIDENTIFIER = (SELECT TOP 1 componente FROM dbo.Asignatura);
DECLARE @tvCat         UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'CAT');
DECLARE @estA          UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'A');
IF @idInstitucion IS NULL OR @tipoId IS NULL OR @tipoProg IS NULL OR @semestre IS NULL OR @area IS NULL OR @componente IS NULL OR @tvCat IS NULL OR @estA IS NULL
    THROW 53700, 'TEST FAILED: fixtures base no disponibles.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #u (n INT IDENTITY(1,1), id UNIQUEIDENTIFIER);
    DECLARE @i INT = 1;
    WHILE @i <= 8
    BEGIN
        DECLARE @uid UNIQUEIDENTIFIER = NEWID();
        INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
        VALUES (@uid, @tipoId, 310000000 + ABS(CHECKSUM(NEWID()) % 99999999), CONCAT(N'Apellido', CHAR(64 + @i)), N'QA', CONCAT(N'Nombre', CHAR(64 + @i)), N'X',
                CONCAT(CONVERT(NVARCHAR(36), @uid), N'@qa.test'), 1, 1, N'x');
        INSERT INTO #u (id) VALUES (@uid);
        SET @i += 1;
    END
    -- n: 1 decano, 2 coordinador P1, 3 coordinador P2, 4 docente D1 (P1 y P2), 5 docente D2 (P1, otro titular),
    --    6 docente D3 (sin vinculo con P1), 7 estudiante E1, 8 estudiante E2
    DECLARE @uDec UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 1), @uC1 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 2),
            @uC2 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 3);

    DECLARE @sufijo NVARCHAR(8) = SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8);
    DECLARE @dec UNIQUEIDENTIFIER = NEWID(), @f UNIQUEIDENTIFIER = NEWID(), @c1 UNIQUEIDENTIFIER = NEWID(), @c2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @d1 UNIQUEIDENTIFIER = NEWID(), @d2 UNIQUEIDENTIFIER = NEWID(), @d3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Decano (id, usuario) VALUES (@dec, @uDec);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@f, CONCAT(N'QA HU094 ', @sufijo), @idInstitucion, @dec, 1);
    INSERT INTO dbo.Coordinador (id, usuario, facultad) VALUES (@c1, @uC1, @f), (@c2, @uC2, @f);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES
        (@p1, @f, @tipoProg, CONCAT(N'HU094 P1 ', @sufijo), @c1, 1), (@p2, @f, @tipoProg, CONCAT(N'HU094 P2 ', @sufijo), @c2, 1);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d1, (SELECT id FROM #u WHERE n = 4)), (@d2, (SELECT id FROM #u WHERE n = 5)), (@d3, (SELECT id FROM #u WHERE n = 6));
    -- D1 vinculado a P1 INACTIVO (el historial se consulta igual) y a P2; D2 vinculado a P1; D3 sin vinculo con P1.
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc) VALUES
        (NEWID(), @d1, @p1, @tvCat, 0, SYSUTCDATETIME()), (NEWID(), @d1, @p2, @tvCat, 1, SYSUTCDATETIME()),
        (NEWID(), @d2, @p1, @tvCat, 1, SYSUTCDATETIME()), (NEWID(), @d3, @p2, @tvCat, 1, SYSUTCDATETIME());

    -- Periodos: vigente, finalizado y proximo (fechas relativas a hoy; holgura para la zona horaria local).
    DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @perV UNIQUEIDENTIFIER = NEWID(), @perF UNIQUEIDENTIFIER = NEWID(), @perP UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio) VALUES
        (@perV, @idInstitucion, CONCAT(N'QA V ', @sufijo), 950000 + ABS(CHECKSUM(NEWID()) % 9999), DATEADD(DAY, -60, @hoy), DATEADD(DAY, 60, @hoy), YEAR(@hoy)),
        (@perF, @idInstitucion, CONCAT(N'QA F ', @sufijo), 960000 + ABS(CHECKSUM(NEWID()) % 9999), DATEADD(DAY, -400, @hoy), DATEADD(DAY, -200, @hoy), YEAR(@hoy) - 1),
        (@perP, @idInstitucion, CONCAT(N'QA P ', @sufijo), 970000 + ABS(CHECKSUM(NEWID()) % 9999), DATEADD(DAY, 100, @hoy), DATEADD(DAY, 200, @hoy), YEAR(@hoy));

    DECLARE @pl1 UNIQUEIDENTIFIER = NEWID(), @pl2 UNIQUEIDENTIFIER = NEWID(), @spe1 UNIQUEIDENTIFIER = NEWID(), @spe2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @a1 UNIQUEIDENTIFIER = NEWID(), @a2 UNIQUEIDENTIFIER = NEWID(), @a3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PlanEstudio (id, programa, inp, estado) VALUES (@pl1, @p1, 950000 + ABS(CHECKSUM(NEWID()) % 9999), 1), (@pl2, @p2, 960000 + ABS(CHECKSUM(NEWID()) % 9999), 1);
    INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) VALUES (@spe1, @pl1, @semestre), (@spe2, @pl2, @semestre);
    INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, semestrePlanEstudio, estado) VALUES
        (@a1, CONCAT(N'H1', @sufijo), N'Algebra QA', 3, @area, @componente, @spe1, 1),
        (@a2, CONCAT(N'H2', @sufijo), N'Calculo QA', 3, @area, @componente, @spe1, 1),
        (@a3, CONCAT(N'H3', @sufijo), N'Fisica QA', 3, @area, @componente, @spe2, 1);

    -- G1 vigente (D1, P1), G2 finalizado (D1, P1), G3 proximo (D1, P1), G4 vigente de P2 (D1, excluido),
    -- G5 vigente de P1 con otro titular (D2, excluido), G6 vigente (D1, P1, segunda asignatura).
    CREATE TABLE #g (k NVARCHAR(2), id UNIQUEIDENTIFIER, a UNIQUEIDENTIFIER, per UNIQUEIDENTIFIER, doc UNIQUEIDENTIFIER, cap INT);
    INSERT INTO #g VALUES
        (N'G1', NEWID(), @a1, @perV, @d1, 30), (N'G2', NEWID(), @a2, @perF, @d1, 25), (N'G3', NEWID(), @a1, @perP, @d1, 20),
        (N'G4', NEWID(), @a3, @perV, @d1, 30), (N'G5', NEWID(), @a2, @perV, @d2, 30), (N'G6', NEWID(), @a2, @perV, @d1, 15);
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    SELECT g.id, g.a, g.per, 950000 + ABS(CHECKSUM(NEWID()) % 99999), CONCAT(N'Grupo ', g.k), g.cap, 0, 0, 0, g.doc FROM #g g;

    -- Dos matriculas activas en G1 y una en G6 => 3 estudiantes activos en periodos vigentes.
    DECLARE @e1 UNIQUEIDENTIFIER = NEWID(), @e2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e1, (SELECT id FROM #u WHERE n = 7)), (@e2, (SELECT id FROM #u WHERE n = 8));
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES
        (NEWID(), @estA, @e1, (SELECT id FROM #g WHERE k = N'G1')), (NEWID(), @estA, @e2, (SELECT id FROM #g WHERE k = N'G1')),
        (NEWID(), @estA, @e1, (SELECT id FROM #g WHERE k = N'G6'));

    DECLARE @g1 UNIQUEIDENTIFIER = (SELECT id FROM #g WHERE k = N'G1'), @g2 UNIQUEIDENTIFIER = (SELECT id FROM #g WHERE k = N'G2'),
            @g3 UNIQUEIDENTIFIER = (SELECT id FROM #g WHERE k = N'G3'), @g6 UNIQUEIDENTIFIER = (SELECT id FROM #g WHERE k = N'G6');
    DECLARE @c UNIQUEIDENTIFIER = NEWID(), @err NVARCHAR(4000);

    CREATE TABLE #h (n INT IDENTITY(1,1), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(50), idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100),
        idPeriodoAcademico UNIQUEIDENTIFIER, codigoPeriodoAcademico INT, nombrePeriodoAcademico NVARCHAR(50), fechaInicioPeriodo DATE, fechaFinPeriodo DATE,
        estadoPeriodo NVARCHAR(10), capacidadMaxima INT, estudiantesActivos INT, estudiantesFinalizados INT, estudiantesCanceladosVoluntad INT,
        estudiantesCanceladosInasistencia INT, resumenTotalGrupos INT, resumenTotalPeriodos INT, resumenGruposVigentes INT,
        resumenEstudiantesActivosVigentes INT, totalRegistros INT);

    -- H-01: historial completo de D1 en P1 (G1, G6, G2, G3), del periodo mas reciente al mas antiguo; excluye P2 y otros titulares.
    INSERT INTO #h (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, nombreAsignatura, idPeriodoAcademico, codigoPeriodoAcademico, nombrePeriodoAcademico,
        fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, capacidadMaxima, estudiantesActivos, estudiantesFinalizados, estudiantesCanceladosVoluntad,
        estudiantesCanceladosInasistencia, resumenTotalGrupos, resumenTotalPeriodos, resumenGruposVigentes, resumenEstudiantesActivosVigentes, totalRegistros)
    EXEC dbo.usp_consultar_historial_grupos_docente_programa @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idDocente = @d1;
    IF (SELECT COUNT(*) FROM #h) <> 4 OR EXISTS (SELECT 1 FROM #h WHERE totalRegistros <> 4)
        THROW 53701, 'TEST FAILED: H-01 se esperaban 4 grupos de D1 en P1.', 1;
    IF (SELECT idGrupo FROM #h WHERE n = 1) <> @g3 OR (SELECT idGrupo FROM #h WHERE n = 4) <> @g2
        THROW 53702, 'TEST FAILED: H-01 orden por fecha de inicio del periodo descendente.', 1;
    IF (SELECT idGrupo FROM #h WHERE n = 2) <> @g1 OR (SELECT idGrupo FROM #h WHERE n = 3) <> @g6
        THROW 53703, 'TEST FAILED: H-01 desempate por nombre de asignatura.', 1;
    PRINT 'TEST_PASS:HU094_HISTORIAL_AMBITO_ORDEN';

    -- H-02: estado del periodo, estadistica y resumen sobre todo el historial.
    IF (SELECT estadoPeriodo FROM #h WHERE idGrupo = @g1) <> N'VIGENTE' OR (SELECT estadoPeriodo FROM #h WHERE idGrupo = @g2) <> N'FINALIZADO'
       OR (SELECT estadoPeriodo FROM #h WHERE idGrupo = @g3) <> N'PROXIMO'
        THROW 53704, 'TEST FAILED: H-02 estadoPeriodo.', 1;
    IF (SELECT estudiantesActivos FROM #h WHERE idGrupo = @g1) <> 2 OR (SELECT capacidadMaxima FROM #h WHERE idGrupo = @g1) <> 30
        THROW 53705, 'TEST FAILED: H-02 estadistica del grupo.', 1;
    IF EXISTS (SELECT 1 FROM #h WHERE resumenTotalGrupos <> 4 OR resumenTotalPeriodos <> 3 OR resumenGruposVigentes <> 2 OR resumenEstudiantesActivosVigentes <> 3)
        THROW 53706, 'TEST FAILED: H-02 resumen de carga.', 1;
    PRINT 'TEST_PASS:HU094_HISTORIAL_RESUMEN';

    -- H-03: filtro por periodo y paginacion; el resumen no depende del filtro ni de la pagina.
    TRUNCATE TABLE #h;
    INSERT INTO #h (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, nombreAsignatura, idPeriodoAcademico, codigoPeriodoAcademico, nombrePeriodoAcademico,
        fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, capacidadMaxima, estudiantesActivos, estudiantesFinalizados, estudiantesCanceladosVoluntad,
        estudiantesCanceladosInasistencia, resumenTotalGrupos, resumenTotalPeriodos, resumenGruposVigentes, resumenEstudiantesActivosVigentes, totalRegistros)
    EXEC dbo.usp_consultar_historial_grupos_docente_programa @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idDocente = @d1,
        @idPeriodoAcademico = @perV, @numeroPagina = 2, @tamanoPagina = 1;
    IF (SELECT COUNT(*) FROM #h) <> 1 OR (SELECT idGrupo FROM #h) <> @g6 OR (SELECT totalRegistros FROM #h) <> 2 OR (SELECT resumenTotalGrupos FROM #h) <> 4
        THROW 53707, 'TEST FAILED: H-03 filtro de periodo y paginacion.', 1;
    TRUNCATE TABLE #h;
    INSERT INTO #h (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, nombreAsignatura, idPeriodoAcademico, codigoPeriodoAcademico, nombrePeriodoAcademico,
        fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, capacidadMaxima, estudiantesActivos, estudiantesFinalizados, estudiantesCanceladosVoluntad,
        estudiantesCanceladosInasistencia, resumenTotalGrupos, resumenTotalPeriodos, resumenGruposVigentes, resumenEstudiantesActivosVigentes, totalRegistros)
    EXEC dbo.usp_consultar_historial_grupos_docente_programa @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idDocente = @d1, @numeroPagina = 0, @tamanoPagina = 500;
    IF (SELECT COUNT(*) FROM #h) <> 4
        THROW 53708, 'TEST FAILED: H-03 paginacion normalizada.', 1;
    PRINT 'TEST_PASS:HU094_HISTORIAL_FILTRO_PAGINACION';

    -- H-04: docente vinculado sin grupos => 0 filas (no es error).
    TRUNCATE TABLE #h;
    UPDATE dbo.Grupo SET docente = @d1 WHERE id = (SELECT id FROM #g WHERE k = N'G5');
    INSERT INTO #h (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, nombreAsignatura, idPeriodoAcademico, codigoPeriodoAcademico, nombrePeriodoAcademico,
        fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, capacidadMaxima, estudiantesActivos, estudiantesFinalizados, estudiantesCanceladosVoluntad,
        estudiantesCanceladosInasistencia, resumenTotalGrupos, resumenTotalPeriodos, resumenGruposVigentes, resumenEstudiantesActivosVigentes, totalRegistros)
    EXEC dbo.usp_consultar_historial_grupos_docente_programa @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idDocente = @d2;
    IF (SELECT COUNT(*) FROM #h) <> 0
        THROW 53709, 'TEST FAILED: H-04 docente sin grupos debe devolver 0 filas.', 1;
    PRINT 'TEST_PASS:HU094_HISTORIAL_SIN_GRUPOS';

    -- H-05: docente sin vinculo con el programa, docente inexistente y docente de otro programa => GEN_001 (indistinguibles).
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #h (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, nombreAsignatura, idPeriodoAcademico, codigoPeriodoAcademico, nombrePeriodoAcademico,
            fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, capacidadMaxima, estudiantesActivos, estudiantesFinalizados, estudiantesCanceladosVoluntad,
            estudiantesCanceladosInasistencia, resumenTotalGrupos, resumenTotalPeriodos, resumenGruposVigentes, resumenEstudiantesActivosVigentes, totalRegistros)
        EXEC dbo.usp_consultar_historial_grupos_docente_programa @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idDocente = @d3;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=GEN_001|%'
        THROW 53710, 'TEST FAILED: H-05 docente sin vinculo (esperaba GEN_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #h (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, nombreAsignatura, idPeriodoAcademico, codigoPeriodoAcademico, nombrePeriodoAcademico,
            fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, capacidadMaxima, estudiantesActivos, estudiantesFinalizados, estudiantesCanceladosVoluntad,
            estudiantesCanceladosInasistencia, resumenTotalGrupos, resumenTotalPeriodos, resumenGruposVigentes, resumenEstudiantesActivosVigentes, totalRegistros)
        EXEC dbo.usp_consultar_historial_grupos_docente_programa @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idDocente = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=GEN_001|%'
        THROW 53711, 'TEST FAILED: H-05 docente inexistente (esperaba GEN_001).', 1;
    -- El coordinador de P2 solo ve el grupo de P2 de D1 (G4).
    TRUNCATE TABLE #h;
    INSERT INTO #h (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, nombreAsignatura, idPeriodoAcademico, codigoPeriodoAcademico, nombrePeriodoAcademico,
        fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, capacidadMaxima, estudiantesActivos, estudiantesFinalizados, estudiantesCanceladosVoluntad,
        estudiantesCanceladosInasistencia, resumenTotalGrupos, resumenTotalPeriodos, resumenGruposVigentes, resumenEstudiantesActivosVigentes, totalRegistros)
    EXEC dbo.usp_consultar_historial_grupos_docente_programa @idUsuarioEjecutor = @uC2, @idCorrelacion = @c, @idDocente = @d1;
    IF (SELECT COUNT(*) FROM #h) <> 1 OR (SELECT idGrupo FROM #h) <> (SELECT id FROM #g WHERE k = N'G4')
        THROW 53712, 'TEST FAILED: H-05 el coordinador de P2 solo ve los grupos de P2.', 1;
    PRINT 'TEST_PASS:HU094_HISTORIAL_AMBITO_DOCENTE';

    -- H-06: ejecutor que no coordina (decano) => KPI_001; docente nulo => VAL_001; ejecutor nulo => VAL_001.
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_historial_grupos_docente_programa @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @idDocente = @d1;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_001|%'
        THROW 53713, 'TEST FAILED: H-06 decano (esperaba KPI_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_historial_grupos_docente_programa @idUsuarioEjecutor = @uC1, @idCorrelacion = @c, @idDocente = NULL;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=VAL_001|%'
        THROW 53714, 'TEST FAILED: H-06 docente nulo (esperaba VAL_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_historial_grupos_docente_programa @idUsuarioEjecutor = NULL, @idCorrelacion = @c, @idDocente = @d1;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=VAL_001|%'
        THROW 53715, 'TEST FAILED: H-06 ejecutor nulo (esperaba VAL_001).', 1;
    PRINT 'TEST_PASS:HU094_HISTORIAL_VALIDACIONES';

    IF @@TRANCOUNT <> 1 THROW 53798, 'TEST FAILED: el objeto altero el nivel de transaccion del llamador.', 1;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 53799, 'TEST FAILED: test_usp_consultar_historial_grupos_docente_programa dejo transacciones abiertas.', 1;
PRINT '==================================================';
PRINT 'TEST END: test_usp_consultar_historial_grupos_docente_programa (HU094)';
PRINT '==================================================';
GO
