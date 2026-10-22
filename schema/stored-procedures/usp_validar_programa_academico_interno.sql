USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_validar_programa_academico_interno]
-- Historias de Usuario: HU076 (alta) y HU077 (edicion)
-- Ambito: validaciones de negocio del programa academico. DEBE ejecutarse dentro de la transaccion del
-- llamador: bloquea (UPDLOCK, HOLDLOCK) la fila del coordinador para serializar dos altas/reasignaciones
-- concurrentes con el mismo coordinador (regla 1 a 1).
-- @idPrograma = NULL en el alta; en la edicion se excluye al propio programa de las reglas de unicidad.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_programa_academico_interno]
(
    @idPrograma              UNIQUEIDENTIFIER = NULL,
    @idFacultad              UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(100),
    @idTipoPrograma          UNIQUEIDENTIFIER,
    @idCoordinador           UNIQUEIDENTIFIER,
    @idModalidad             UNIQUEIDENTIFIER = NULL,
    @idJornada               UNIQUEIDENTIFIER = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDef            NVARCHAR(100)    = TRIM(@nombre);
    DECLARE @coordinadorBloqueado UNIQUEIDENTIFIER = NULL;
    DECLARE @msgP1 NVARCHAR(500), @msgP2 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    IF @estadoResultado = 1 AND (@nombreDef IS NULL OR @nombreDef = '' OR LEN(@nombreDef) > 50)
    BEGIN
        SET @msgP1 = CAST('nombre' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.uv_programa p WHERE p.idFacultad = @idFacultad AND LOWER(p.nombrePrograma) = LOWER(@nombreDef) AND (@idPrograma IS NULL OR p.id <> @idPrograma))
    BEGIN
        SET @msgP1 = CAST(@nombreDef AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'PROG_003',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1 AND (@idTipoPrograma IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_programa t WHERE t.id = @idTipoPrograma AND t.estaActivoTipoPrograma = 1))
    BEGIN
        SET @msgP1 = CAST(CONVERT(NVARCHAR(36), @idTipoPrograma) AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'PROG_004',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1 AND (@idModalidad IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.uv_modalidad m WHERE m.id = @idModalidad AND m.estaActivoModalidad = 1))
    BEGIN
        SET @msgP1 = CAST(CONVERT(NVARCHAR(36), @idModalidad) AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'PROG_006',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1 AND (@idJornada IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.uv_jornada j WHERE j.id = @idJornada AND j.estaActivoJornada = 1))
    BEGIN
        SET @msgP1 = CAST(CONVERT(NVARCHAR(36), @idJornada) AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'PROG_006',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- Coordinador: serializa por fila del coordinador y valida existencia, actividad y disponibilidad
    IF @estadoResultado = 1 AND @idCoordinador IS NOT NULL
    BEGIN
        SELECT @coordinadorBloqueado = c.id
        FROM dbo.Coordinador c WITH (UPDLOCK, HOLDLOCK)
        WHERE c.id = @idCoordinador;
    END

    IF @estadoResultado = 1 AND (@idCoordinador IS NULL OR @coordinadorBloqueado IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador_identidad ci WHERE ci.id = @idCoordinador AND ci.estaActivoUsuario = 1) OR EXISTS (SELECT 1 FROM dbo.Programa pr WITH (UPDLOCK, HOLDLOCK) WHERE pr.coordinador = @idCoordinador AND (@idPrograma IS NULL OR pr.id <> @idPrograma)))
    BEGIN
        SET @msgP1 = CAST(CONVERT(NVARCHAR(36), @idCoordinador) AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'PROG_005',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

END;
GO
