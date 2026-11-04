USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- REC2 (auditoria BD 2026-10-28): usp_actualizar_asignatura y usp_toggle_estado_asignatura exigen ejecutor
-- (GEN_002), perfil COORDINADOR (SEC_001) y que coordine el programa de la asignatura (SEC_002).
-- Fixtures propias dentro de UNA transaccion con ROLLBACK final.
PRINT 'TEST START: test_rec2_rbac_asignatura';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idFacultad UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa);
DECLARE @idTipoProg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma);
DECLARE @idSemestre UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Semestre ORDER BY numero);
DECLARE @idArea UNIQUEIDENTIFIER, @idComponente UNIQUEIDENTIFIER;
SELECT TOP 1 @idArea = area, @idComponente = componente FROM dbo.Asignatura;
IF @tipoCC IS NULL OR @idFacultad IS NULL OR @idTipoProg IS NULL OR @idSemestre IS NULL OR @idArea IS NULL
    THROW 53400, 'TEST FAILED: REC2 faltan fixtures base.', 1;

CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
DECLARE @corr UNIQUEIDENTIFIER = NEWID();

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uC1 UNIQUEIDENTIFIER = NEWID(), @uC2 UNIQUEIDENTIFIER = NEWID(), @uD UNIQUEIDENTIFIER = NEWID();
    DECLARE @cC1 UNIQUEIDENTIFIER = NEWID(), @cC2 UNIQUEIDENTIFIER = NEWID(), @dD UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID(), @pl1 UNIQUEIDENTIFIER = NEWID();
    DECLARE @spe1 UNIQUEIDENTIFIER = NEWID(), @a1 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uC1, @tipoCC, 970010001, N'Coord', N'Uno', N'Rita', N'Qa', N'qa.c1.rec2@test.local', 1, 1, N'HashBackend_R2'),
           (@uC2, @tipoCC, 970010002, N'Coord', N'Dos', N'Raul', N'Qa', N'qa.c2.rec2@test.local', 1, 1, N'HashBackend_R2'),
           (@uD,  @tipoCC, 970010003, N'Docente', N'Uno', N'Rosa', N'Qa', N'qa.doc.rec2@test.local', 1, 1, N'HashBackend_R2');
    INSERT INTO dbo.Coordinador (id, usuario) VALUES (@cC1, @uC1), (@cC2, @uC2);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@dD, @uD);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    VALUES (@p1, @idFacultad, @idTipoProg, N'Programa QA REC2-1', @cC1, 1), (@p2, @idFacultad, @idTipoProg, N'Programa QA REC2-2', @cC2, 1);
    INSERT INTO dbo.PlanEstudio (id, programa, inp, estado) VALUES (@pl1, @p1, 9201, 1);
    INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) VALUES (@spe1, @pl1, @idSemestre);
    INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, semestrePlanEstudio, estado)
    VALUES (@a1, N'QAREC2A1', N'QA REC2 Materia', 3, @idArea, @idComponente, @spe1, 1);

    -- RA-01: sin ejecutor => GEN_002, sin cambios (actualizar y toggle)
    INSERT INTO #r EXEC dbo.usp_actualizar_asignatura @idAsignatura = @a1, @codigo = NULL, @nombre = N'QA Cambio', @creditos = 4,
        @idPlanEstudio = @pl1, @semestreNumero = NULL, @nombreArea = NULL, @nombreComponente = NULL, @idCorrelacion = @corr;
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @a1, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=GEN_002|%') <> 2
        THROW 53401, 'TEST FAILED: RA-01 sin ejecutor debio retornar GEN_002 en ambos SP.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @a1 AND nombre = N'QA REC2 Materia' AND credito = 3 AND estado = 1)
        THROW 53402, 'TEST FAILED: RA-01 la asignatura cambio sin ejecutor.', 1;
    PRINT 'TEST_PASS:REC2_RA01_SIN_EJECUTOR_GEN_002';

    -- RA-02: ejecutor con rol equivocado (DOCENTE) => SEC_001
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_asignatura @idAsignatura = @a1, @codigo = NULL, @nombre = N'QA Cambio', @creditos = 4,
        @idPlanEstudio = @pl1, @semestreNumero = NULL, @nombreArea = NULL, @nombreComponente = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @a1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=SEC_001|%') <> 2
        THROW 53403, 'TEST FAILED: RA-02 rol docente debio retornar SEC_001 en ambos SP.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @a1 AND nombre = N'QA REC2 Materia' AND estado = 1)
        THROW 53404, 'TEST FAILED: RA-02 la asignatura cambio con rol equivocado.', 1;
    PRINT 'TEST_PASS:REC2_RA02_ROL_EQUIVOCADO_SEC_001';

    -- RA-03: coordinador de OTRO programa => SEC_002
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_asignatura @idAsignatura = @a1, @codigo = NULL, @nombre = N'QA Cambio', @creditos = 4,
        @idPlanEstudio = @pl1, @semestreNumero = NULL, @nombreArea = NULL, @nombreComponente = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC2;
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @a1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC2;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=SEC_002|%') <> 2
        THROW 53405, 'TEST FAILED: RA-03 coordinador de otro programa debio retornar SEC_002 en ambos SP.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @a1 AND nombre = N'QA REC2 Materia' AND estado = 1)
        THROW 53406, 'TEST FAILED: RA-03 la asignatura cambio con un coordinador ajeno.', 1;
    PRINT 'TEST_PASS:REC2_RA03_OTRO_PROGRAMA_SEC_002';

    -- RA-05 (decision de John 2026-11-04): crear asignatura en el plan de OTRO programa => SEC_002, sin insertar
    DECLARE @a5 UNIQUEIDENTIFIER = NEWID();
    DECLARE @areaCodigo NVARCHAR(10) = (SELECT codigo FROM dbo.uv_area WHERE id = @idArea);
    DECLARE @numSemestre INT = (SELECT numero FROM dbo.Semestre WHERE id = @idSemestre);
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_asignatura @idAsignatura = @a5, @codigo = N'QAREC2C5', @nombre = N'QA REC2 Crear', @creditos = 3,
        @idPlanEstudio = @pl1, @semestreNumero = @numSemestre, @nombreArea = @areaCodigo, @nombreComponente = N'ESP',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uC2;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=SEC_002|%')
       OR EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @a5)
        THROW 53480, 'TEST FAILED: RA-05 crear en el plan de otro programa debio retornar SEC_002 sin insertar.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_asignatura @idAsignatura = @a5, @codigo = N'QAREC2C5', @nombre = N'QA REC2 Crear', @creditos = 3,
        @idPlanEstudio = @pl1, @semestreNumero = @numSemestre, @nombreArea = @areaCodigo, @nombreComponente = N'ESP',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @a5)
        THROW 53481, 'TEST FAILED: RA-05 el coordinador titular no pudo crear en su plan.', 1;
    PRINT 'TEST_PASS:REC2_RA05_CREAR_OTRO_PROGRAMA_SEC_002';

    -- RA-04: coordinador titular => exito en ambos SP
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_asignatura @idAsignatura = @a1, @codigo = NULL, @nombre = N'QA Cambio', @creditos = 4,
        @idPlanEstudio = @pl1, @semestreNumero = NULL, @nombreArea = NULL, @nombreComponente = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @a1 AND credito = 4)
        THROW 53407, 'TEST FAILED: RA-04 el coordinador titular no pudo actualizar.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @a1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @a1 AND estado = 0)
        THROW 53408, 'TEST FAILED: RA-04 el coordinador titular no pudo cambiar el estado.', 1;
    PRINT 'TEST_PASS:REC2_RA04_COORDINADOR_TITULAR_OK';

    IF @@TRANCOUNT <> 1 THROW 53498, 'TEST FAILED: REC2 alteraron el nivel de transaccion del llamador.', 1;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #r;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

DROP TABLE IF EXISTS #r;
IF @@TRANCOUNT <> 0 THROW 53499, 'TEST FAILED: test_rec2_rbac_asignatura dejo transacciones abiertas.', 1;
PRINT 'TEST END: test_rec2_rbac_asignatura';
GO
