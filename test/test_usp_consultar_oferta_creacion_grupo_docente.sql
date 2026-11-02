USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- F3 (2026-11-02): usp_consultar_oferta_creacion_grupo_docente. El docente ve solo las asignaturas activas de los
-- programas con los que tiene vinculo activo, junto con su propio idDocente. Otros perfiles reciben SEC_001 (THROW).
PRINT 'TEST START: test_usp_consultar_oferta_creacion_grupo_docente';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER, @idProg UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER;
SELECT TOP 1 @idAsig = a.id, @idProg = pe.idPrograma
FROM dbo.uv_asignatura a
INNER JOIN dbo.uv_semestre_plan_estudio spe ON a.idSemestrePlanEstudio = spe.id
INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id AND pe.estaActivoPlanEstudio = 1
INNER JOIN dbo.uv_programa pr ON pe.idPrograma = pr.id AND pr.idCoordinador IS NOT NULL
WHERE a.estaActivaAsignatura = 1;
SELECT @uCoord = ci.idUsuario FROM dbo.uv_programa pr INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = pr.idCoordinador WHERE pr.id = @idProg;
DECLARE @tvCat UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'CAT');
IF @tipoCC IS NULL OR @idAsig IS NULL OR @uCoord IS NULL OR @tvCat IS NULL
    THROW 53300, 'TEST FAILED: faltan fixtures del seed (asignatura activa, coordinador o vinculacion).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uD1 UNIQUEIDENTIFIER = NEWID(), @uD2 UNIQUEIDENTIFIER = NEWID(), @d1 UNIQUEIDENTIFIER = NEWID(), @d2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD1, @tipoCC, 972100001, N'Oferta', N'Uno', N'Olga', N'Qa', N'qa.oferta.d1@test.local', 1, 1, N'HashBackend_O1'),
           (@uD2, @tipoCC, 972100002, N'Oferta', N'Dos', N'Omar', N'Qa', N'qa.oferta.d2@test.local', 1, 1, N'HashBackend_O2');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d1, @uD1), (@d2, @uD2);
    -- d1 tiene vinculo activo con el programa; d2 no tiene vinculo
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @d1, @idProg, @tvCat, 1, SYSUTCDATETIME());

    CREATE TABLE #o (idDocente UNIQUEIDENTIFIER, idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(50), nombreAsignatura NVARCHAR(200),
                     idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(200));

    -- 1. El docente vinculado ve las asignaturas activas del programa y su propio idDocente
    INSERT INTO #o EXEC dbo.usp_consultar_oferta_creacion_grupo_docente @idUsuarioEjecutor = @uD1, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #o WHERE idAsignatura = @idAsig AND idDocente = @d1 AND idPrograma = @idProg)
        THROW 53301, 'TEACHER_OFFER_LINKED FAILED: debio incluir la asignatura activa de su programa con su idDocente.', 1;
    IF EXISTS (SELECT 1 FROM #o WHERE idPrograma <> @idProg OR idDocente <> @d1)
        THROW 53302, 'TEACHER_OFFER_LINKED FAILED: solo debe devolver asignaturas de sus programas y su idDocente.', 1;
    IF EXISTS (SELECT 1 FROM #o o INNER JOIN dbo.uv_asignatura a ON a.id = o.idAsignatura WHERE a.estaActivaAsignatura = 0)
        THROW 53303, 'TEACHER_OFFER_LINKED FAILED: no debe devolver asignaturas inactivas.', 1;
    PRINT 'TEST_PASS:TEACHER_OFFER_LINKED';

    -- 2. El docente sin vinculo no ve nada
    TRUNCATE TABLE #o;
    INSERT INTO #o EXEC dbo.usp_consultar_oferta_creacion_grupo_docente @idUsuarioEjecutor = @uD2, @idCorrelacion = @corr;
    IF EXISTS (SELECT 1 FROM #o) THROW 53304, 'TEACHER_OFFER_NO_LINK FAILED: sin vinculo activo no debe devolver filas.', 1;
    PRINT 'TEST_PASS:TEACHER_OFFER_NO_LINK';

    -- 3. Un coordinador o un ejecutor ausente no consulta la oferta del docente (THROW con el codigo de catalogo)
    DECLARE @rechazado BIT = 0, @mensaje NVARCHAR(4000);
    BEGIN TRY
        INSERT INTO #o EXEC dbo.usp_consultar_oferta_creacion_grupo_docente @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @rechazado = 1;
        SET @mensaje = ERROR_MESSAGE();
    END CATCH
    IF @rechazado = 0 OR @mensaje NOT LIKE '%SEC_001%'
        THROW 53305, 'TEACHER_OFFER_REJECTS_OTHER_PROFILES FAILED: un coordinador debio recibir SEC_001.', 1;
    PRINT 'TEST_PASS:TEACHER_OFFER_REJECTS_OTHER_PROFILES';

    DROP TABLE #o;
    ROLLBACK TRANSACTION;
    IF @@TRANCOUNT <> 0 THROW 53306, 'TEST FAILED: transaccion abierta.', 1;
    PRINT 'TEST END: test_usp_consultar_oferta_creacion_grupo_docente';
END TRY
BEGIN CATCH
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID('tempdb..#o') IS NOT NULL DROP TABLE #o;
    THROW 53399, @err, 1;
END CATCH
GO
