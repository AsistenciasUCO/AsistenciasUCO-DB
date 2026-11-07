USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- HU008 (regla de John 2026-10-27) — regresion de la matricula (usp_registrar_estudiante_en_grupo_interno): matricular
-- en un grupo de asignatura ESPECIFICA (ESP) inscribe al estudiante en el programa (EstudiantePrograma); en una
-- TRANSVERSAL (BAS o INS) lo matricula en el grupo SIN inscribirlo en el programa.
-- CULM-001 A (E-13, DEC-009): HU053-HU055 se descartan; la via es la matricula manual del DOCENTE titular
-- (usp_registrar_estudiante_en_grupo, HU050) con usuarios existentes (el SP los encuentra por correo).
-- RI-04 (T-07): la reactivacion de una matricula retirada (I -> A) aplica la misma regla, y la aplica UNA sola vez,
-- en el bloque del interno (el SP nuevo de reactivacion no contiene la regla).
-- Fixtures dentro de UNA transaccion con ROLLBACK final.
-- ============================================================================
PRINT 'TEST START: test_hu008_regla_inscripcion_programa';

DECLARE @group UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER, @periodo UNIQUEIDENTIFIER, @userT UNIQUEIDENTIFIER;
DECLARE @asignatura UNIQUEIDENTIFIER, @programa UNIQUEIDENTIFIER, @tipoCC UNIQUEIDENTIFIER;
DECLARE @compESP UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'ESP');
DECLARE @compINS UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'INS');
DECLARE @compBAS UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'BAS');
DECLARE @estI UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = N'I');

SELECT TOP 1 @group = g.id, @teacher = g.docente, @periodo = g.periodoAcademico, @asignatura = g.asignatura, @programa = pe.programa
FROM dbo.Grupo g
INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
ORDER BY g.id;
SELECT @userT = usuario FROM dbo.Docente WHERE id = @teacher;
SELECT TOP 1 @tipoCC = id FROM dbo.TipoIdentificacion ORDER BY id;

IF @group IS NULL OR @userT IS NULL OR @programa IS NULL OR @tipoCC IS NULL OR @compESP IS NULL OR @compINS IS NULL OR @compBAS IS NULL OR @estI IS NULL
    THROW 53950, 'TEST FAILED: HU008_REGLA fixture missing (seed data).', 1;

DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @zona NVARCHAR(100) = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoyLocal DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
DECLARE @u1 UNIQUEIDENTIFIER = NEWID(), @u2 UNIQUEIDENTIFIER = NEWID(), @u3 UNIQUEIDENTIFIER = NEWID();
DECLARE @u4 UNIQUEIDENTIFIER = NEWID(), @u5 UNIQUEIDENTIFIER = NEWID(), @u6 UNIQUEIDENTIFIER = NEWID();
DECLARE @e1 UNIQUEIDENTIFIER = NEWID(), @e2 UNIQUEIDENTIFIER = NEWID(), @e3 UNIQUEIDENTIFIER = NEWID();
DECLARE @e4 UNIQUEIDENTIFIER = NEWID(), @e5 UNIQUEIDENTIFIER = NEWID(), @e6 UNIQUEIDENTIFIER = NEWID();
DECLARE @eg4 UNIQUEIDENTIFIER = NEWID(), @eg5 UNIQUEIDENTIFIER = NEWID(), @eg6 UNIQUEIDENTIFIER = NEWID();

CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);

BEGIN TRANSACTION;
BEGIN TRY
    -- Periodo vigente y cupo holgado.
    UPDATE dbo.PeriodoAcademico SET fechaFin = DATEADD(DAY, 30, @hoyLocal) WHERE id = @periodo;
    UPDATE dbo.Grupo SET cantidadEstudiantes = (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo
        WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') + 10 WHERE id = @group;

    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@u1, @tipoCC, 970008001, N'Uno', N'Qa', N'Est', N'Hu008', N'qa.hu008.1@test.local', 1, 1, N'HashBackend_R1'),
           (@u2, @tipoCC, 970008002, N'Dos', N'Qa', N'Est', N'Hu008', N'qa.hu008.2@test.local', 1, 1, N'HashBackend_R1'),
           (@u3, @tipoCC, 970008003, N'Tres', N'Qa', N'Est', N'Hu008', N'qa.hu008.3@test.local', 1, 1, N'HashBackend_R1'),
           (@u4, @tipoCC, 970008004, N'Cuatro', N'Qa', N'Est', N'Hu008', N'qa.hu008.4@test.local', 1, 1, N'HashBackend_R1'),
           (@u5, @tipoCC, 970008005, N'Cinco', N'Qa', N'Est', N'Hu008', N'qa.hu008.5@test.local', 1, 1, N'HashBackend_R1'),
           (@u6, @tipoCC, 970008006, N'Seis', N'Qa', N'Est', N'Hu008', N'qa.hu008.6@test.local', 1, 1, N'HashBackend_R1');
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e1, @u1), (@e2, @u2), (@e3, @u3), (@e4, @u4), (@e5, @u5), (@e6, @u6);

    -- RI-01: asignatura ESPECIFICA => matricula activa e inscripcion en el programa.
    UPDATE dbo.Asignatura SET componente = @compESP WHERE id = @asignatura;
    INSERT INTO #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @group, @numeroIdentificacion = 970008001,
        @primerNombre = N'Est', @segundoNombre = N'Hu008', @primerApellido = N'Uno', @segundoApellido = N'Qa',
        @correo = N'qa.hu008.1@test.local', @password = N'HashBackend_R1', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND idEstudiante = @e1 AND codigoEstadoEstudiante = 'A')
       OR NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @e1 AND programa = @programa)
        THROW 53951, 'TEST FAILED: RI-01 ESP debe matricular e inscribir en el programa.', 1;
    PRINT 'TEST_PASS:HU008_RI01_ESP_INSCRIBE_PROGRAMA';

    -- RI-02: asignatura INSTITUCIONAL => matricula activa SIN inscripcion en el programa.
    UPDATE dbo.Asignatura SET componente = @compINS WHERE id = @asignatura;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @group, @numeroIdentificacion = 970008002,
        @primerNombre = N'Est', @segundoNombre = N'Hu008', @primerApellido = N'Dos', @segundoApellido = N'Qa',
        @correo = N'qa.hu008.2@test.local', @password = N'HashBackend_R1', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND idEstudiante = @e2 AND codigoEstadoEstudiante = 'A')
       OR EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @e2)
        THROW 53952, 'TEST FAILED: RI-02 INS debe matricular sin inscribir en el programa.', 1;
    PRINT 'TEST_PASS:HU008_RI02_INS_NO_INSCRIBE_PROGRAMA';

    -- RI-03: asignatura BASICA => matricula activa SIN inscripcion en el programa.
    UPDATE dbo.Asignatura SET componente = @compBAS WHERE id = @asignatura;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @group, @numeroIdentificacion = 970008003,
        @primerNombre = N'Est', @segundoNombre = N'Hu008', @primerApellido = N'Tres', @segundoApellido = N'Qa',
        @correo = N'qa.hu008.3@test.local', @password = N'HashBackend_R1', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND idEstudiante = @e3 AND codigoEstadoEstudiante = 'A')
       OR EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @e3)
        THROW 53953, 'TEST FAILED: RI-03 BAS debe matricular sin inscribir en el programa.', 1;
    PRINT 'TEST_PASS:HU008_RI03_BAS_NO_INSCRIBE_PROGRAMA';

    -- RI-04 (T-07): reactivacion manual de una matricula retirada (I), sin EstudiantePrograma. ESP inscribe; INS y BAS no.
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@eg4, @estI, @e4, @group), (@eg5, @estI, @e5, @group), (@eg6, @estI, @e6, @group);
    UPDATE dbo.Asignatura SET componente = @compESP WHERE id = @asignatura;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @group, @numeroIdentificacion = 970008004,
        @primerNombre = N'Est', @segundoNombre = N'Hu008', @primerApellido = N'Cuatro', @segundoApellido = N'Qa',
        @correo = N'qa.hu008.4@test.local', @password = N'HashBackend_R1', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE id = @eg4 AND codigoEstadoEstudiante = 'A')
       OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @group AND estudiante = @e4) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @e4 AND programa = @programa)
        THROW 53954, 'TEST FAILED: RI-04 ESP reactivar la misma matricula debe inscribir en el programa.', 1;
    UPDATE dbo.Asignatura SET componente = @compINS WHERE id = @asignatura;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @group, @numeroIdentificacion = 970008005,
        @primerNombre = N'Est', @segundoNombre = N'Hu008', @primerApellido = N'Cinco', @segundoApellido = N'Qa',
        @correo = N'qa.hu008.5@test.local', @password = N'HashBackend_R1', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE id = @eg5 AND codigoEstadoEstudiante = 'A')
       OR EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @e5)
        THROW 53955, 'TEST FAILED: RI-04 INS reactivar no debe inscribir en el programa.', 1;
    UPDATE dbo.Asignatura SET componente = @compBAS WHERE id = @asignatura;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @group, @numeroIdentificacion = 970008006,
        @primerNombre = N'Est', @segundoNombre = N'Hu008', @primerApellido = N'Seis', @segundoApellido = N'Qa',
        @correo = N'qa.hu008.6@test.local', @password = N'HashBackend_R1', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE id = @eg6 AND codigoEstadoEstudiante = 'A')
       OR EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @e6)
        THROW 53956, 'TEST FAILED: RI-04 BAS reactivar no debe inscribir en el programa.', 1;
    -- La regla vive en un solo sitio: el SP de reactivacion no inscribe en el programa ni conoce el componente ESP.
    IF OBJECT_ID('dbo.usp_internal_reactivar_matricula_retirada', 'P') IS NULL
       OR OBJECT_DEFINITION(OBJECT_ID('dbo.usp_internal_reactivar_matricula_retirada')) LIKE '%EstudiantePrograma%'
       OR OBJECT_DEFINITION(OBJECT_ID('dbo.usp_internal_reactivar_matricula_retirada')) LIKE '%''ESP''%'
        THROW 53957, 'TEST FAILED: RI-04 usp_internal_reactivar_matricula_retirada no debe contener la regla ESP.', 1;
    PRINT 'TEST_PASS:HU008_RI04_REACTIVACION_REGLA_ESP';

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
    THROW 53999, 'TEST FAILED: test_hu008_regla_inscripcion_programa dejo transacciones abiertas.', 1;
DROP TABLE IF EXISTS #r;
PRINT 'TEST END: test_hu008_regla_inscripcion_programa';
GO
