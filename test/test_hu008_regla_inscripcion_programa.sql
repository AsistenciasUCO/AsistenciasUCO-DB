USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
-- El indice unico filtrado de SolicitudIngresoGrupo exige QUOTED_IDENTIFIER ON para el DML (sqlcmd lo deja OFF).
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- HU008 (regla de John 2026-10-27) — regresion de la matricula (usp_registrar_estudiante_en_grupo_interno) usada por
-- HU053-HU055: aceptar una solicitud en un grupo de asignatura ESPECIFICA (ESP) inscribe al estudiante en el programa
-- (EstudiantePrograma); en una TRANSVERSAL (BAS o INS) lo matricula en el grupo SIN inscribirlo en el programa.
-- Fixtures dentro de UNA transaccion con ROLLBACK final.
-- ============================================================================
PRINT 'TEST START: test_hu008_regla_inscripcion_programa';

DECLARE @group UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER, @periodo UNIQUEIDENTIFIER, @userT UNIQUEIDENTIFIER;
DECLARE @asignatura UNIQUEIDENTIFIER, @programa UNIQUEIDENTIFIER, @tipoCC UNIQUEIDENTIFIER;
DECLARE @compESP UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'ESP');
DECLARE @compINS UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'INS');
DECLARE @compBAS UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'BAS');

SELECT TOP 1 @group = g.id, @teacher = g.docente, @periodo = g.periodoAcademico, @asignatura = g.asignatura, @programa = pe.programa
FROM dbo.Grupo g
INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
ORDER BY g.id;
SELECT @userT = usuario FROM dbo.Docente WHERE id = @teacher;
SELECT TOP 1 @tipoCC = id FROM dbo.TipoIdentificacion ORDER BY id;

IF @group IS NULL OR @userT IS NULL OR @programa IS NULL OR @tipoCC IS NULL OR @compESP IS NULL OR @compINS IS NULL OR @compBAS IS NULL
    THROW 53950, 'TEST FAILED: HU008_REGLA fixture missing (seed data).', 1;

DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @zona NVARCHAR(100) = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoyLocal DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
DECLARE @u1 UNIQUEIDENTIFIER = NEWID(), @u2 UNIQUEIDENTIFIER = NEWID(), @u3 UNIQUEIDENTIFIER = NEWID();
DECLARE @e1 UNIQUEIDENTIFIER = NEWID(), @e2 UNIQUEIDENTIFIER = NEWID(), @e3 UNIQUEIDENTIFIER = NEWID();
DECLARE @s1 UNIQUEIDENTIFIER = NEWID(), @s2 UNIQUEIDENTIFIER = NEWID(), @s3 UNIQUEIDENTIFIER = NEWID();

CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
CREATE TABLE #rx (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
    estadoResultado BIT, codigoEstadoResultante CHAR(1));

BEGIN TRANSACTION;
BEGIN TRY
    -- Periodo vigente y cupo holgado.
    UPDATE dbo.PeriodoAcademico SET fechaFin = DATEADD(DAY, 30, @hoyLocal) WHERE id = @periodo;
    UPDATE dbo.Grupo SET cantidadEstudiantes = (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo
        WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') + 5 WHERE id = @group;

    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@u1, @tipoCC, 970008001, N'Uno', N'Qa', N'Est', N'Hu008', N'qa.hu008.1@test.local', 1, 1, N'HashBackend_R1'),
           (@u2, @tipoCC, 970008002, N'Dos', N'Qa', N'Est', N'Hu008', N'qa.hu008.2@test.local', 1, 1, N'HashBackend_R1'),
           (@u3, @tipoCC, 970008003, N'Tres', N'Qa', N'Est', N'Hu008', N'qa.hu008.3@test.local', 1, 1, N'HashBackend_R1');
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e1, @u1), (@e2, @u2), (@e3, @u3);

    -- RI-01: asignatura ESPECIFICA => matricula activa e inscripcion en el programa.
    UPDATE dbo.Asignatura SET componente = @compESP WHERE id = @asignatura;
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @s1, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @u1;
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @s1, @accion = N'ACEPTAR', @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    IF NOT EXISTS (SELECT 1 FROM #rx WHERE estadoResultado = 1 AND codigoEstadoResultante = 'A')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND idEstudiante = @e1 AND codigoEstadoEstudiante = 'A')
       OR NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @e1 AND programa = @programa)
        THROW 53951, 'TEST FAILED: RI-01 ESP debe matricular e inscribir en el programa.', 1;
    PRINT 'TEST_PASS:HU008_RI01_ESP_INSCRIBE_PROGRAMA';

    -- RI-02: asignatura INSTITUCIONAL => matricula activa SIN inscripcion en el programa.
    UPDATE dbo.Asignatura SET componente = @compINS WHERE id = @asignatura;
    TRUNCATE TABLE #r; TRUNCATE TABLE #rx;
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @s2, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @u2;
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @s2, @accion = N'ACEPTAR', @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    IF NOT EXISTS (SELECT 1 FROM #rx WHERE estadoResultado = 1 AND codigoEstadoResultante = 'A')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND idEstudiante = @e2 AND codigoEstadoEstudiante = 'A')
       OR EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @e2)
        THROW 53952, 'TEST FAILED: RI-02 INS debe matricular sin inscribir en el programa.', 1;
    PRINT 'TEST_PASS:HU008_RI02_INS_NO_INSCRIBE_PROGRAMA';

    -- RI-03: asignatura BASICA => matricula activa SIN inscripcion en el programa.
    UPDATE dbo.Asignatura SET componente = @compBAS WHERE id = @asignatura;
    TRUNCATE TABLE #r; TRUNCATE TABLE #rx;
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @s3, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @u3;
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @s3, @accion = N'ACEPTAR', @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    IF NOT EXISTS (SELECT 1 FROM #rx WHERE estadoResultado = 1 AND codigoEstadoResultante = 'A')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND idEstudiante = @e3 AND codigoEstadoEstudiante = 'A')
       OR EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @e3)
        THROW 53953, 'TEST FAILED: RI-03 BAS debe matricular sin inscribir en el programa.', 1;
    PRINT 'TEST_PASS:HU008_RI03_BAS_NO_INSCRIBE_PROGRAMA';

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
DROP TABLE IF EXISTS #rx;
PRINT 'TEST END: test_hu008_regla_inscripcion_programa';
GO
