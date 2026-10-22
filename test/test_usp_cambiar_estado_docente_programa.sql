USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- HU093 (T-093-01..05): usp_cambiar_estado_docente_programa y regla D12 en grupos (DOC_009).
-- Inactivar cambia SOLO DocentePrograma.estado: no toca Usuario ni los grupos ya asignados.
PRINT 'TEST START: test_usp_cambiar_estado_docente_programa';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idFacultad UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa);
DECLARE @idTipoProg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma);
IF @tipoCC IS NULL OR @idFacultad IS NULL OR @idTipoProg IS NULL
    THROW 52600, 'TEST FAILED: faltan fixtures base.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uC1 UNIQUEIDENTIFIER = NEWID(), @uC2 UNIQUEIDENTIFIER = NEWID(), @uD UNIQUEIDENTIFIER = NEWID(), @uD2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @cC1 UNIQUEIDENTIFIER = NEWID(), @cC2 UNIQUEIDENTIFIER = NEWID(), @dD UNIQUEIDENTIFIER = NEWID(), @dD2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uC1, @tipoCC, 970000001, N'Coord', N'Uno', N'Carlos', N'Qa', N'qa.c1.hu093@test.local', 1, 1, N'HashBackend_F1'),
           (@uC2, @tipoCC, 970000002, N'Coord', N'Dos', N'Diana',  N'Qa', N'qa.c2.hu093@test.local', 1, 1, N'HashBackend_F2'),
           (@uD,  @tipoCC, 970000011, N'Docente', N'Uno', N'Dario', N'Qa', N'qa.doc.hu093@test.local', 1, 1, N'HashBackend_F3'),
           (@uD2, @tipoCC, 970000012, N'Docente', N'Dos', N'Dora', N'Qa', N'qa.doc2.hu093@test.local', 1, 1, N'HashBackend_F4');
    INSERT INTO dbo.Coordinador (id, usuario) VALUES (@cC1, @uC1), (@cC2, @uC2);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@dD, @uD), (@dD2, @uD2);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    VALUES (@p1, @idFacultad, @idTipoProg, N'Programa QA 093-1', @cC1, 1), (@p2, @idFacultad, @idTipoProg, N'Programa QA 093-2', @cC2, 1);
    DECLARE @tvCat UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'CAT');
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @dD, @p1, @tvCat, 1, SYSUTCDATETIME()), (NEWID(), @dD, @p2, @tvCat, 1, SYSUTCDATETIME());

    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    DECLARE @msg NVARCHAR(4000);

    -- T-093-01: inactivar solo cambia el vinculo del programa del coordinador
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_docente_programa
        @idDocente = @dD, @idPrograma = @p1, @estaActivo = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52610, 'T-093-01 FAILED: inactivar no retorno exito.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @dD AND programa = @p1 AND estado = 0) THROW 52611, 'T-093-01 FAILED: el vinculo de P1 sigue activo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @dD AND programa = @p2 AND estado = 1) THROW 52612, 'T-093-01 FAILED: el vinculo de P2 no debio cambiar.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uD AND estado = 1) THROW 52613, 'T-093-01 FAILED: no debe inactivar a la persona.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Docente WHERE id = @dD) THROW 52614, 'T-093-01 FAILED: el rol Docente debe conservarse.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_docente_programa WHERE idDocente = @dD AND idPrograma = @p1 AND estaActivoVinculacion = 0 AND estaActivoDocentePrograma = 0)
        THROW 52615, 'T-093-01 FAILED: el directorio no refleja el estado inactivo.', 1;
    PRINT 'TEST_PASS:T-093-01';

    -- T-093-02: idempotencia y reactivacion
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_docente_programa
        @idDocente = @dD, @idPrograma = @p1, @estaActivo = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52620, 'T-093-02 FAILED: inactivar dos veces debio ser exitoso (idempotente).', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_docente_programa
        @idDocente = @dD, @idPrograma = @p1, @estaActivo = 1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52621, 'T-093-02 FAILED: reactivar no retorno exito.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @dD AND programa = @p1 AND estado = 1) THROW 52622, 'T-093-02 FAILED: el vinculo no quedo activo.', 1;
    PRINT 'TEST_PASS:T-093-02';

    -- T-093-04: ambito, RBAC y vinculo inexistente
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'DOC_008';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_docente_programa    -- docente sin vinculo con P1
        @idDocente = @dD2, @idPrograma = @p1, @estaActivo = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52640, 'T-093-04 FAILED: sin vinculo debio retornar DOC_008.', 1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_002';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_docente_programa    -- C1 sobre P2
        @idDocente = @dD, @idPrograma = @p2, @estaActivo = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52641, 'T-093-04 FAILED: programa ajeno debio retornar SEC_002.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @dD AND programa = @p2 AND estado = 1) THROW 52642, 'T-093-04 FAILED: el vinculo ajeno cambio.', 1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_001';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_docente_programa    -- ejecutor docente
        @idDocente = @dD, @idPrograma = @p1, @estaActivo = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52643, 'T-093-04 FAILED: ejecutor docente debio retornar SEC_001.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_docente_programa    -- estado obligatorio
        @idDocente = @dD, @idPrograma = @p1, @estaActivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0) THROW 52644, 'T-093-04 FAILED: @estaActivo NULL debio rechazarse.', 1;
    PRINT 'TEST_PASS:T-093-04';

    -- T-093-03 (D12): un docente con vinculo INACTIVO no puede ser titular nuevo de un grupo del programa;
    -- los grupos ya asignados se conservan y editarlos sin cambiar el titular sigue funcionando.
    DECLARE @idAsig UNIQUEIDENTIFIER, @idProgAsig UNIQUEIDENTIFIER, @uCoordAsig UNIQUEIDENTIFIER;
    SELECT TOP 1 @idAsig = a.id, @idProgAsig = pe.idPrograma
    FROM dbo.uv_asignatura a
    INNER JOIN dbo.uv_semestre_plan_estudio spe ON a.idSemestrePlanEstudio = spe.id
    INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
    INNER JOIN dbo.uv_programa pr ON pe.idPrograma = pr.id AND pr.idCoordinador IS NOT NULL;
    SELECT @uCoordAsig = ci.idUsuario FROM dbo.uv_programa pr INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = pr.idCoordinador WHERE pr.id = @idProgAsig;
    DECLARE @idPeriodo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_periodo_academico ORDER BY anio DESC);
    IF @idAsig IS NULL OR @uCoordAsig IS NULL OR @idPeriodo IS NULL THROW 52630, 'TEST FAILED: faltan fixtures del seed (asignatura/coordinador/periodo).', 1;

    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc) VALUES (NEWID(), @dD2, @idProgAsig, @tvCat, 1, SYSUTCDATETIME());
    DECLARE @g1 UNIQUEIDENTIFIER = NEWID(), @g2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @cod1 INT = 80000 + ABS(CHECKSUM(NEWID()) % 9000), @cod2 INT = 89000 + ABS(CHECKSUM(NEWID()) % 900);

    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_grupo
        @idGrupo = @g1, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = @cod1, @nombre = N'Grupo QA 093',
        @idDocente = @dD2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoordAsig;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52631, 'T-093-03 FAILED: con vinculo activo el grupo debio crearse.', 1;

    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_docente_programa
        @idDocente = @dD2, @idPrograma = @idProgAsig, @estaActivo = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoordAsig;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52632, 'T-093-03 FAILED: no pudo inactivar el vinculo del programa del seed.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @g1 AND docente = @dD2) THROW 52633, 'T-093-03 FAILED: el grupo ya asignado debio conservarse.', 1;

    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'DOC_009';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_grupo
        @idGrupo = @g2, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = @cod2, @nombre = N'Grupo QA 093 b',
        @idDocente = @dD2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoordAsig;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52634, 'T-093-03 FAILED: crear grupo con titular inactivo debio retornar DOC_009.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @g2) THROW 52635, 'T-093-03 FAILED: se creo el grupo con titular inactivo.', 1;

    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_grupo    -- mismo titular (inactivo) y solo cupo: permitido
        @idGrupo = @g1, @codigo = NULL, @nombre = NULL, @idDocente = @dD2, @cupoMaximo = 55, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoordAsig;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52636, 'T-093-03 FAILED: editar cupo con el mismo titular inactivo debio permitirse.', 1;

    -- Reactivar permite volver a asignarlo como titular
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_docente_programa
        @idDocente = @dD2, @idPrograma = @idProgAsig, @estaActivo = 1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoordAsig;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_grupo
        @idGrupo = @g2, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = @cod2, @nombre = N'Grupo QA 093 b',
        @idDocente = @dD2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoordAsig;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52638, 'T-093-03 FAILED: reactivado, el docente debio poder ser titular.', 1;
    PRINT 'TEST_PASS:T-093-03';

    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    PRINT 'TEST_PASS:TEST_USP_CAMBIAR_ESTADO_DOCENTE_PROGRAMA';
END TRY
BEGIN CATCH
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
    THROW 52999, @err, 1;
END CATCH
GO
