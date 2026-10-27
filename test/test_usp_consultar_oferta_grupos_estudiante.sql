USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_consultar_oferta_grupos_estudiante (HU008)';
PRINT '==================================================';

DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1);
DECLARE @tipoId        UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion);
DECLARE @tipoProg      UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma ORDER BY nombre);
DECLARE @semestre      UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Semestre);
DECLARE @area          UNIQUEIDENTIFIER = (SELECT TOP 1 area FROM dbo.Asignatura);
DECLARE @compESP UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'ESP');
DECLARE @compINS UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'INS');
DECLARE @compBAS UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'BAS');
DECLARE @estA          UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'A');
DECLARE @estI          UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'I');
DECLARE @solP          UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'P' AND id = 'B4B4D37E-6A8F-4E1D-AF32-0B2C60E2E977');
DECLARE @diaLu UNIQUEIDENTIFIER = (SELECT id FROM dbo.Dia WHERE codigo = N'LU');
DECLARE @diaMa UNIQUEIDENTIFIER = (SELECT id FROM dbo.Dia WHERE codigo = N'MA');
IF @idInstitucion IS NULL OR @tipoId IS NULL OR @tipoProg IS NULL OR @semestre IS NULL OR @area IS NULL OR @compESP IS NULL OR @compINS IS NULL OR @compBAS IS NULL
   OR @estA IS NULL OR @estI IS NULL OR @solP IS NULL OR @diaLu IS NULL OR @diaMa IS NULL
    THROW 53900, 'TEST FAILED: fixtures base no disponibles.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #u (n INT IDENTITY(1,1), id UNIQUEIDENTIFIER);
    DECLARE @i INT = 1;
    WHILE @i <= 6
    BEGIN
        DECLARE @uid UNIQUEIDENTIFIER = NEWID();
        INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
        VALUES (@uid, @tipoId, 330000000 + ABS(CHECKSUM(NEWID()) % 99999999), CONCAT(N'Apellido', CHAR(64 + @i)), N'QA', CONCAT(N'Nombre', CHAR(64 + @i)), N'X',
                CONCAT(CONVERT(NVARCHAR(36), @uid), N'@qa.test'), 1, 1, N'x');
        INSERT INTO #u (id) VALUES (@uid);
        SET @i += 1;
    END
    -- n: 1 decano, 2 coordinador P1, 3 coordinador P2, 4 docente, 5 estudiante E1 (P1), 6 estudiante E2 (P1)
    DECLARE @uDoc UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 4), @uE1 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 5);

    DECLARE @sufijo NVARCHAR(8) = SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8);
    DECLARE @dec UNIQUEIDENTIFIER = NEWID(), @f UNIQUEIDENTIFIER = NEWID(), @c1 UNIQUEIDENTIFIER = NEWID(), @c2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID(), @doc UNIQUEIDENTIFIER = NEWID();
    DECLARE @e1 UNIQUEIDENTIFIER = NEWID(), @e2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Decano (id, usuario) VALUES (@dec, (SELECT id FROM #u WHERE n = 1));
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@f, CONCAT(N'QA HU008 ', @sufijo), @idInstitucion, @dec, 1);
    INSERT INTO dbo.Coordinador (id, usuario, facultad) VALUES (@c1, (SELECT id FROM #u WHERE n = 2), @f), (@c2, (SELECT id FROM #u WHERE n = 3), @f);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES
        (@p1, @f, @tipoProg, CONCAT(N'HU008 P1 ', @sufijo), @c1, 1), (@p2, @f, @tipoProg, CONCAT(N'HU008 P2 ', @sufijo), @c2, 1);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@doc, @uDoc);
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e1, @uE1), (@e2, (SELECT id FROM #u WHERE n = 6));
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) VALUES (NEWID(), @e1, @p1), (NEWID(), @e2, @p1);

    DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @perV UNIQUEIDENTIFIER = NEWID(), @perF UNIQUEIDENTIFIER = NEWID(), @perP UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio) VALUES
        (@perV, @idInstitucion, CONCAT(N'QA V ', @sufijo), 980000 + ABS(CHECKSUM(NEWID()) % 9999), DATEADD(DAY, -60, @hoy), DATEADD(DAY, 60, @hoy), YEAR(@hoy)),
        (@perF, @idInstitucion, CONCAT(N'QA F ', @sufijo), 985000 + ABS(CHECKSUM(NEWID()) % 4999), DATEADD(DAY, -400, @hoy), DATEADD(DAY, -200, @hoy), YEAR(@hoy) - 1),
        (@perP, @idInstitucion, CONCAT(N'QA P ', @sufijo), 990000 + ABS(CHECKSUM(NEWID()) % 9999), DATEADD(DAY, 100, @hoy), DATEADD(DAY, 200, @hoy), YEAR(@hoy));

    DECLARE @pl1 UNIQUEIDENTIFIER = NEWID(), @pl2 UNIQUEIDENTIFIER = NEWID(), @spe1 UNIQUEIDENTIFIER = NEWID(), @spe2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @a1 UNIQUEIDENTIFIER = NEWID(), @a2 UNIQUEIDENTIFIER = NEWID(), @a3 UNIQUEIDENTIFIER = NEWID(), @a4 UNIQUEIDENTIFIER = NEWID(), @a5 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PlanEstudio (id, programa, inp, estado) VALUES (@pl1, @p1, 970000 + ABS(CHECKSUM(NEWID()) % 9999), 1), (@pl2, @p2, 975000 + ABS(CHECKSUM(NEWID()) % 4999), 1);
    INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) VALUES (@spe1, @pl1, @semestre), (@spe2, @pl2, @semestre);
    INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, semestrePlanEstudio, estado) VALUES
        (@a1, CONCAT(N'O1', @sufijo), N'Algebra QA008', 3, @area, @compESP, @spe1, 1),
        (@a2, CONCAT(N'O2', @sufijo), N'Calculo QA008', 3, @area, @compESP, @spe1, 1),
        (@a3, CONCAT(N'O3', @sufijo), N'Fisica QA008', 3, @area, @compINS, @spe2, 1),
        (@a4, CONCAT(N'O4', @sufijo), N'Electronica QA008', 3, @area, @compESP, @spe2, 1),
        (@a5, CONCAT(N'O5', @sufijo), N'Biologia QA008', 3, @area, @compBAS, @spe1, 1);

    -- G1 vigente (P1 ESP, cupo 2, 1 activo de E2 y 1 inactivo), G2 proximo (P1 ESP), G3 finalizado (P1, excluido),
    -- G4 vigente de P2 INSTITUCIONAL (transversal: incluido), G5 vigente (P1 ESP, cupo 1, E1 matriculado => 0 cupos),
    -- G6 vigente de P2 ESPECIFICA (excluido: no es su programa), G7 vigente (P1 BASICA, transversal).
    DECLARE @base INT = 900000 + ABS(CHECKSUM(NEWID()) % 9000) * 10;
    CREATE TABLE #g (k NVARCHAR(2), id UNIQUEIDENTIFIER, a UNIQUEIDENTIFIER, per UNIQUEIDENTIFIER, cap INT, cod INT);
    INSERT INTO #g VALUES
        (N'G1', NEWID(), @a1, @perV, 2, @base + 1), (N'G2', NEWID(), @a2, @perP, 30, @base + 2), (N'G3', NEWID(), @a1, @perF, 30, @base + 3),
        (N'G4', NEWID(), @a3, @perV, 30, @base + 4), (N'G5', NEWID(), @a1, @perV, 1, @base + 5), (N'G6', NEWID(), @a4, @perV, 30, @base + 6),
        (N'G7', NEWID(), @a5, @perV, 30, @base + 7);
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    SELECT g.id, g.a, g.per, g.cod, CONCAT(N'Grupo ', g.k), g.cap, 0, 0, 0, @doc FROM #g g;
    DECLARE @g1 UNIQUEIDENTIFIER = (SELECT id FROM #g WHERE k = N'G1'), @g2 UNIQUEIDENTIFIER = (SELECT id FROM #g WHERE k = N'G2'),
            @g5 UNIQUEIDENTIFIER = (SELECT id FROM #g WHERE k = N'G5'), @g4 UNIQUEIDENTIFIER = (SELECT id FROM #g WHERE k = N'G4'),
            @g7 UNIQUEIDENTIFIER = (SELECT id FROM #g WHERE k = N'G7');
    -- Valor por defecto del parametro (incluir transversales), independiente del ambiente.
    UPDATE dbo.CatalogoParametro SET valor = N'1' WHERE grupo = 'OFERTA' AND clave = 'INCLUIR_TRANSVERSALES';
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin) VALUES
        (NEWID(), @g1, @diaMa, '10:00', '12:00'), (NEWID(), @g1, @diaLu, '08:00', '10:00');
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES
        (NEWID(), @estA, @e2, @g1), (NEWID(), @estI, @e1, @g1), (NEWID(), @estA, @e1, @g5);
    DECLARE @sol UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.SolicitudIngresoGrupo (id, estudiante, grupo, estado, fechaSolicitudUtc) VALUES (@sol, @e1, @g2, @solP, SYSUTCDATETIME());

    DECLARE @c UNIQUEIDENTIFIER = NEWID(), @err NVARCHAR(4000);
    CREATE TABLE #o (n INT IDENTITY(1,1), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(50), idAsignatura UNIQUEIDENTIFIER,
        codigoAsignatura NVARCHAR(20), nombreAsignatura NVARCHAR(100), nombreDocente NVARCHAR(400), idPeriodoAcademico UNIQUEIDENTIFIER,
        nombrePeriodoAcademico NVARCHAR(50), fechaInicioPeriodo DATE, fechaFinPeriodo DATE, estadoPeriodo NVARCHAR(10), horario NVARCHAR(400),
        capacidadMaxima INT, estudiantesActivos INT, cuposDisponibles INT, matriculado BIT, idSolicitudAbierta UNIQUEIDENTIFIER,
        codigoEstadoSolicitud CHAR(1), codigoComponente NVARCHAR(3), totalRegistros INT);

    -- O-01: especificas de su programa + transversales (BAS/INS) de la institucion, en periodos vigentes y proximos;
    --       excluye el periodo finalizado y las especificas de otro programa.
    INSERT INTO #o (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, codigoAsignatura, nombreAsignatura, nombreDocente, idPeriodoAcademico,
        nombrePeriodoAcademico, fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, horario, capacidadMaxima, estudiantesActivos, cuposDisponibles,
        matriculado, idSolicitudAbierta, codigoEstadoSolicitud, codigoComponente, totalRegistros)
    EXEC dbo.usp_consultar_oferta_grupos_estudiante @idCorrelacion = @c, @idUsuarioEjecutor = @uE1;
    IF (SELECT COUNT(*) FROM #o) <> 5 OR EXISTS (SELECT 1 FROM #o WHERE totalRegistros <> 5)
        THROW 53901, 'TEST FAILED: O-01 se esperaban 5 grupos (G1, G5, G7, G2, G4).', 1;
    IF (SELECT idGrupo FROM #o WHERE n = 1) <> @g1 OR (SELECT idGrupo FROM #o WHERE n = 2) <> @g5 OR (SELECT idGrupo FROM #o WHERE n = 3) <> @g7
       OR (SELECT idGrupo FROM #o WHERE n = 4) <> @g2 OR (SELECT idGrupo FROM #o WHERE n = 5) <> @g4
        THROW 53902, 'TEST FAILED: O-01 orden por asignatura, inicio del periodo y codigo.', 1;
    IF (SELECT codigoComponente FROM #o WHERE idGrupo = @g4) <> N'INS' OR (SELECT codigoComponente FROM #o WHERE idGrupo = @g7) <> N'BAS'
       OR (SELECT codigoComponente FROM #o WHERE idGrupo = @g1) <> N'ESP'
        THROW 53911, 'TEST FAILED: O-01 componente de la asignatura.', 1;
    PRINT 'TEST_PASS:HU008_OFERTA_AMBITO_ORDEN';

    -- O-02: cupos, horario, estado del periodo y relacion del estudiante con cada grupo.
    IF NOT EXISTS (SELECT 1 FROM #o WHERE idGrupo = @g1 AND capacidadMaxima = 2 AND estudiantesActivos = 1 AND cuposDisponibles = 1
                   AND matriculado = 0 AND idSolicitudAbierta IS NULL AND estadoPeriodo = N'VIGENTE'
                   AND horario = N'Lunes 08:00-10:00; Martes 10:00-12:00' AND nombreDocente LIKE N'NombreD%')
        THROW 53903, 'TEST FAILED: O-02 G1 (cupo, horario, docente, matricula inactiva no cuenta).', 1;
    IF NOT EXISTS (SELECT 1 FROM #o WHERE idGrupo = @g5 AND cuposDisponibles = 0 AND matriculado = 1 AND horario IS NULL)
        THROW 53904, 'TEST FAILED: O-02 G5 (matriculado, sin cupo, sin horario).', 1;
    IF NOT EXISTS (SELECT 1 FROM #o WHERE idGrupo = @g2 AND estadoPeriodo = N'PROXIMO' AND idSolicitudAbierta = @sol AND codigoEstadoSolicitud = 'P' AND cuposDisponibles = 30)
        THROW 53905, 'TEST FAILED: O-02 G2 (proximo con solicitud abierta P).', 1;
    PRINT 'TEST_PASS:HU008_OFERTA_CUPOS_RELACION';

    -- O-03: busqueda por asignatura y paginacion.
    TRUNCATE TABLE #o;
    INSERT INTO #o (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, codigoAsignatura, nombreAsignatura, nombreDocente, idPeriodoAcademico,
        nombrePeriodoAcademico, fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, horario, capacidadMaxima, estudiantesActivos, cuposDisponibles,
        matriculado, idSolicitudAbierta, codigoEstadoSolicitud, codigoComponente, totalRegistros)
    EXEC dbo.usp_consultar_oferta_grupos_estudiante @busqueda = N'  calculo qa008 ', @idCorrelacion = @c, @idUsuarioEjecutor = @uE1;
    IF (SELECT COUNT(*) FROM #o) <> 1 OR (SELECT idGrupo FROM #o) <> @g2
        THROW 53906, 'TEST FAILED: O-03 busqueda por asignatura.', 1;
    TRUNCATE TABLE #o;
    INSERT INTO #o (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, codigoAsignatura, nombreAsignatura, nombreDocente, idPeriodoAcademico,
        nombrePeriodoAcademico, fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, horario, capacidadMaxima, estudiantesActivos, cuposDisponibles,
        matriculado, idSolicitudAbierta, codigoEstadoSolicitud, codigoComponente, totalRegistros)
    EXEC dbo.usp_consultar_oferta_grupos_estudiante @numeroPagina = 2, @tamanoPagina = 1, @idCorrelacion = @c, @idUsuarioEjecutor = @uE1;
    IF (SELECT COUNT(*) FROM #o) <> 1 OR (SELECT idGrupo FROM #o) <> @g5 OR (SELECT totalRegistros FROM #o) <> 5
        THROW 53907, 'TEST FAILED: O-03 paginacion.', 1;
    TRUNCATE TABLE #o;
    INSERT INTO #o (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, codigoAsignatura, nombreAsignatura, nombreDocente, idPeriodoAcademico,
        nombrePeriodoAcademico, fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, horario, capacidadMaxima, estudiantesActivos, cuposDisponibles,
        matriculado, idSolicitudAbierta, codigoEstadoSolicitud, codigoComponente, totalRegistros)
    EXEC dbo.usp_consultar_oferta_grupos_estudiante @busqueda = N'100%_', @idCorrelacion = @c, @idUsuarioEjecutor = @uE1;
    IF (SELECT COUNT(*) FROM #o) <> 0
        THROW 53908, 'TEST FAILED: O-03 comodines escapados.', 1;
    PRINT 'TEST_PASS:HU008_OFERTA_BUSQUEDA_PAGINACION';

    -- O-05: con OFERTA.INCLUIR_TRANSVERSALES = 0 solo se ofrecen las especificas de su programa (las transversales
    --       se ingresan con el enlace del docente).
    UPDATE dbo.CatalogoParametro SET valor = N'0' WHERE grupo = 'OFERTA' AND clave = 'INCLUIR_TRANSVERSALES';
    TRUNCATE TABLE #o;
    INSERT INTO #o (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, codigoAsignatura, nombreAsignatura, nombreDocente, idPeriodoAcademico,
        nombrePeriodoAcademico, fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, horario, capacidadMaxima, estudiantesActivos, cuposDisponibles,
        matriculado, idSolicitudAbierta, codigoEstadoSolicitud, codigoComponente, totalRegistros)
    EXEC dbo.usp_consultar_oferta_grupos_estudiante @idCorrelacion = @c, @idUsuarioEjecutor = @uE1;
    IF (SELECT COUNT(*) FROM #o) <> 3 OR EXISTS (SELECT 1 FROM #o WHERE codigoComponente <> N'ESP')
        THROW 53912, 'TEST FAILED: O-05 sin transversales solo quedan las especificas (G1, G5, G2).', 1;
    UPDATE dbo.CatalogoParametro SET valor = N'1' WHERE grupo = 'OFERTA' AND clave = 'INCLUIR_TRANSVERSALES';
    PRINT 'TEST_PASS:HU008_OFERTA_PARAMETRO_TRANSVERSALES';

    -- O-04: un ejecutor que no es estudiante obtiene 0 filas; ejecutor nulo => VAL_001.
    TRUNCATE TABLE #o;
    INSERT INTO #o (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, codigoAsignatura, nombreAsignatura, nombreDocente, idPeriodoAcademico,
        nombrePeriodoAcademico, fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, horario, capacidadMaxima, estudiantesActivos, cuposDisponibles,
        matriculado, idSolicitudAbierta, codigoEstadoSolicitud, codigoComponente, totalRegistros)
    EXEC dbo.usp_consultar_oferta_grupos_estudiante @idCorrelacion = @c, @idUsuarioEjecutor = @uDoc;
    IF (SELECT COUNT(*) FROM #o) <> 0
        THROW 53909, 'TEST FAILED: O-04 un docente no ve oferta de estudiante.', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_oferta_grupos_estudiante @idCorrelacion = @c, @idUsuarioEjecutor = NULL;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=VAL_001|%'
        THROW 53910, 'TEST FAILED: O-04 ejecutor nulo (esperaba VAL_001).', 1;
    PRINT 'TEST_PASS:HU008_OFERTA_VALIDACIONES';

    IF @@TRANCOUNT <> 1 THROW 53998, 'TEST FAILED: el objeto altero el nivel de transaccion del llamador.', 1;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 53999, 'TEST FAILED: test_usp_consultar_oferta_grupos_estudiante dejo transacciones abiertas.', 1;
PRINT '==================================================';
PRINT 'TEST END: test_usp_consultar_oferta_grupos_estudiante (HU008)';
PRINT '==================================================';
GO
