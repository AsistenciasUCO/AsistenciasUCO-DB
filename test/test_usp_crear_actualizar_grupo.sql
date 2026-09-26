USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_usp_crear_actualizar_grupo';

DECLARE @idAsig UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_asignatura);
DECLARE @idPeriodo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_periodo_academico ORDER BY anio DESC);
DECLARE @idDocente UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_docente);
DECLARE @idUsuarioCoordinador UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_coordinador_identidad WHERE estaActivoUsuario = 1);
DECLARE @capacidadDefecto INT = dbo.ufn_obtener_parametro_int(NULL, 'GRUPO', 'CAPACIDAD_MAXIMA_DEFECTO');

IF @idAsig IS NULL THROW 51200, 'TEST FAILED: no existe fixture uv_asignatura.', 1;
IF @idPeriodo IS NULL THROW 51201, 'TEST FAILED: no existe fixture uv_periodo_academico.', 1;
IF @idDocente IS NULL THROW 51202, 'TEST FAILED: no existe fixture uv_docente.', 1;
IF @idUsuarioCoordinador IS NULL THROW 51217, 'TEST FAILED: no existe fixture usuario coordinador.', 1;
IF @capacidadDefecto IS NULL OR @capacidadDefecto <= 0 THROW 51203, 'TEST FAILED: capacidad defecto invalida.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @idGrupo1 UNIQUEIDENTIFIER = NEWID();
    DECLARE @c1 UNIQUEIDENTIFIER = NEWID();
    DECLARE @c2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @c3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @c4 UNIQUEIDENTIFIER = NEWID();
    DECLARE @codigoGrupo INT = 70000 + ABS(CHECKSUM(NEWID()) % 10000);

    CREATE TABLE #grupoResultado (
        idCorrelacion UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado BIT
    );

    INSERT INTO #grupoResultado
    EXEC dbo.usp_crear_grupo
        @idGrupo = @idGrupo1,
        @idAsignatura = @idAsig,
        @idPeriodoAcademico = @idPeriodo,
        @codigo = @codigoGrupo,
        @nombre = N'Grupo Capacidad Defecto',
        @idDocente = @idDocente,
        @idCorrelacion = @c1,
        @idUsuarioEjecutor = @idUsuarioCoordinador;

    IF NOT EXISTS (SELECT 1 FROM #grupoResultado WHERE estadoResultado = 1)
        THROW 51204, 'TEST FAILED: usp_crear_grupo no retorno SUCCESS.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @idGrupo1 AND cantidadEstudiantes = @capacidadDefecto AND cantidadEstudiantes > 0)
        THROW 51205, 'TEST FAILED: crear grupo no persistio capacidad por defecto valida.', 1;

    TRUNCATE TABLE #grupoResultado;
    INSERT INTO #grupoResultado
    EXEC dbo.usp_actualizar_grupo
        @idGrupo = @idGrupo1,
        @codigo = NULL,
        @nombre = NULL,
        @idDocente = NULL,
        @cupoMaximo = 60,
        @idCorrelacion = @c2,
        @idUsuarioEjecutor = @idUsuarioCoordinador;

    IF NOT EXISTS (SELECT 1 FROM #grupoResultado WHERE estadoResultado = 1)
        THROW 51208, 'TEST FAILED: usp_actualizar_grupo no retorno SUCCESS.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @idGrupo1 AND cantidadEstudiantes = 60)
        THROW 51209, 'TEST FAILED: actualizar grupo no persistio cupo.', 1;

    DECLARE @estadoActivo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');
    DECLARE @estudiante1 UNIQUEIDENTIFIER = (SELECT id FROM (SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM dbo.Estudiante) e WHERE rn = 1);
    DECLARE @estudiante2 UNIQUEIDENTIFIER = (SELECT id FROM (SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM dbo.Estudiante) e WHERE rn = 2);
    IF @estadoActivo IS NULL THROW 51210, 'TEST FAILED: no existe estado activo de EstudianteGrupo.', 1;
    IF @estudiante1 IS NULL OR @estudiante2 IS NULL THROW 51211, 'TEST FAILED: no existen dos estudiantes fixture para ocupacion de grupo.', 1;

    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    VALUES
        (NEWID(), @estadoActivo, @estudiante1, @idGrupo1),
        (NEWID(), @estadoActivo, @estudiante2, @idGrupo1);

    DECLARE @cantidadAntes INT = (SELECT cantidadEstudiantes FROM dbo.Grupo WHERE id = @idGrupo1);
    TRUNCATE TABLE #grupoResultado;

    INSERT INTO #grupoResultado
    EXEC dbo.usp_actualizar_grupo
        @idGrupo = @idGrupo1,
        @codigo = NULL,
        @nombre = NULL,
        @idDocente = NULL,
        @cupoMaximo = 1,
        @idCorrelacion = @c3,
        @idUsuarioEjecutor = @idUsuarioCoordinador;

    IF NOT EXISTS (SELECT 1 FROM #grupoResultado WHERE estadoResultado = 0 AND mensajeUsuarioResultado = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'ERR_CUPO_INFERIOR_OCUPACION'))
        THROW 51212, 'TEST FAILED: cupo inferior no retorno ERR_CUPO_INFERIOR_OCUPACION.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @idGrupo1 AND cantidadEstudiantes = @cantidadAntes)
        THROW 51213, 'TEST FAILED: cupo inferior modifico capacidad existente.', 1;

    TRUNCATE TABLE #grupoResultado;
    INSERT INTO #grupoResultado
    EXEC dbo.usp_actualizar_grupo
        @idGrupo = @idGrupo1,
        @codigo = NULL,
        @nombre = N'Grupo Renombrado',
        @idDocente = NULL,
        @cupoMaximo = NULL,
        @idCorrelacion = @c4,
        @idUsuarioEjecutor = @idUsuarioCoordinador;

    IF NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @idGrupo1 AND cantidadEstudiantes = 60 AND nombre = N'Grupo Renombrado')
        THROW 51214, 'TEST FAILED: actualizar grupo con NULL no conservo cupo.', 1;

    DROP TABLE #grupoResultado;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;

IF EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @idGrupo1)
    THROW 51215, 'TEST FAILED: grupo dejo datos permanentes.', 1;

IF @@TRANCOUNT <> 0 THROW 51216, 'TEST FAILED: grupo dejo transacciones abiertas.', 1;
PRINT 'TEST PASS: grupo create/update/cupo/uv_grupo.';
PRINT 'TEST_PASS:GROUP_CREATE';
PRINT 'TEST_PASS:GROUP_UPDATE';
PRINT 'TEST_PASS:GROUP_CAPACITY_REJECT';
PRINT 'TEST END: test_usp_crear_actualizar_grupo';
GO
