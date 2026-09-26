USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_grupos_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL,
    @idAsignatura       UNIQUEIDENTIFIER = NULL,
    @filtroTexto        NVARCHAR(100)    = NULL,
    @numeroPagina       INT              = 1,
    @tamanoPagina       INT              = 10
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 1. NormalizaciÃ³n de parÃ¡metros con funciones de catÃ¡logo (sin valores quemados ni ISNULL)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- NormalizaciÃ³n de paginaciÃ³n protegida (mÃ­nimo 1, mÃ¡ximo 100)
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- NormalizaciÃ³n de filtro de texto
    DECLARE @filtroNormalizado NVARCHAR(102) = IIF(TRIM(@filtroTexto) IS NULL OR TRIM(@filtroTexto) = '', NULL, CONCAT('%', TRIM(@filtroTexto), '%'));

    -- 2. Variables de diagnÃ³stico y validaciÃ³n
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    BEGIN TRY
        -- 3. ValidaciÃ³n obligatoria de identificador de correlaciÃ³n
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 4. ValidaciÃ³n obligatoria de usuario ejecutor (no nulo y no GUID vacÃ­o)
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- 5. Establecer identidad en el contexto de sesiÃ³n para la vista securizada uv_auth_grupo
        EXEC dbo.usp_establecer_contexto_usuario_ejecutor 
            @p_idUsuario = @idUsuarioDefecto;

        -- 6. Consulta optimizada y determinÃ­stica a la vista securizada
        SELECT 
            g.id,
            g.codigo,
            g.nombre,
            g.idAsignatura,
            g.nombreAsignatura,
            g.idDocente,
            g.capacidadMaximaPermitida,
            g.estudiantesActivos,
            g.cuposDisponibles,
            g.grupoEstaHablitado,
            g.fechaInicioPeriodoAcademico,
            g.fechaFinPeriodoAcademico,
            COUNT(*) OVER() AS totalRegistros
        FROM dbo.uv_auth_grupo g
        WHERE 
            (@idPeriodoAcademico IS NULL OR g.idPeriodoAcademico = @idPeriodoAcademico)
            AND (@idAsignatura IS NULL OR g.idAsignatura = @idAsignatura)
            AND (
                @filtroNormalizado IS NULL 
                OR g.nombre LIKE @filtroNormalizado 
                OR g.codigo LIKE @filtroNormalizado 
                OR g.nombreAsignatura LIKE @filtroNormalizado
            )
        ORDER BY g.nombreAsignatura ASC, g.codigo ASC, g.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

        -- 7. Limpieza defensiva del contexto de sesiÃ³n
        EXEC dbo.usp_establecer_contexto_usuario_ejecutor 
            @p_idUsuario = NULL;

    END TRY
    BEGIN CATCH
        -- Limpieza obligatoria del contexto ante cualquier excepciÃ³n
        EXEC dbo.usp_establecer_contexto_usuario_ejecutor 
            @p_idUsuario = NULL;
        THROW;
    END CATCH;
END;
GO
