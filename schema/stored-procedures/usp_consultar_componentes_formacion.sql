USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_componentes_formacion (HU147 consultar componentes de formacion)
--
-- Catalogo institucional de componentes (BAS basicas, INS institucionales, ESP especificas) con el numero de
-- asignaturas de cada uno. Regla de John (2026-11-04): el componente decide la oferta (HU008): ESP es propia del programa
-- y solo una ESP inscribe al estudiante en el programa; BAS e INS son transversales. Lo usan el administrador y el
-- formulario de asignaturas del coordinador (P5: se elige un componente que exista en la tabla).
--
-- Resultset: READ_QUERY_RESULTSET (filas), NO el resultset canonico de 4 columnas de los comandos.
-- Las fallas se propagan con THROW (VAL_001 / SEC_001).
-- Ambito: perfiles ADMINISTRADOR, DECANO o COORDINADOR; el catalogo es comun a la institucion.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_componentes_formacion]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGuidVacio             UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.
    BEGIN TRY
        -- PASO 1: Correlacion presente
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (VAL_001)
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @idGuidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));
            SET @estadoResultado = 0;
        END

        -- PASO 3: Perfil ADMINISTRADOR, DECANO o COORDINADOR (SEC_001)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR,DECANO,COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END;

        -- PASO 4: Consulta y retorno de resultados
        SELECT
            idComponente     = c.id,
            codigo           = c.codigo,
            nombre           = c.nombre,
            totalAsignaturas = (SELECT COUNT(*) FROM dbo.uv_asignatura a WHERE a.idComponente = c.id)
        FROM dbo.uv_componente c
        ORDER BY c.nombre ASC, c.id ASC;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
