USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_obtener_mensaje_catalogo]
    @p_codigo                  VARCHAR(100),
    @p_param1                  NVARCHAR(500) = NULL,
    @p_param2                  NVARCHAR(500) = NULL,
    @p_param3                  NVARCHAR(500) = NULL,
    @mensajeUsuarioResultado   NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado   NVARCHAR(4000) OUTPUT,
    @tipoMensajeResultado      VARCHAR(50) = NULL OUTPUT,
    @severidadResultado        VARCHAR(20) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @codigoLimpio VARCHAR(100) = TRIM(ISNULL(@p_codigo, ''));
    DECLARE @rawUsuario NVARCHAR(4000) = NULL;
    DECLARE @rawTecnico NVARCHAR(4000) = NULL;
    DECLARE @tipoUsr VARCHAR(50) = NULL;
    DECLARE @sevUsr VARCHAR(20) = NULL;
    DECLARE @tipoTec VARCHAR(50) = NULL;
    DECLARE @sevTec VARCHAR(20) = NULL;
    DECLARE @codigoResultado VARCHAR(100) = CASE WHEN @codigoLimpio = '' THEN 'DESCONOCIDO' ELSE @codigoLimpio END;
    DECLARE @detalleTecnico NVARCHAR(3900) = NULL;

    -- Consulta EXCLUSIVA mediante VISTA uv_mensaje_usuario
    SELECT 
        @rawUsuario = contenido,
        @tipoUsr    = tipoMensaje,
        @sevUsr     = severidad
    FROM dbo.uv_mensaje_usuario
    WHERE codigo = @codigoLimpio;

    -- Consulta EXCLUSIVA mediante VISTA uv_mensaje_tecnico
    SELECT 
        @rawTecnico = contenido,
        @tipoTec    = tipoMensaje,
        @sevTec     = severidad
    FROM dbo.uv_mensaje_tecnico
    WHERE codigo = @codigoLimpio;

    -- Gestión interna de NULOS y Fallbacks para Mensaje de Usuario
    IF @rawUsuario IS NULL
    BEGIN
        SET @mensajeUsuarioResultado = CONCAT('Mensaje de usuario no configurado para el código: ', ISNULL(@codigoLimpio, 'DESCONOCIDO'));
        SET @tipoUsr = 'SYSTEM_ERROR';
        SET @sevUsr  = 'ALTO';
    END
    ELSE
    BEGIN
        SET @mensajeUsuarioResultado = dbo.ufn_reemplazar_plantilla_mensaje(@rawUsuario, @p_param1, @p_param2, @p_param3);
    END

    -- Gestión interna de NULOS y Fallbacks para Mensaje Técnico
    IF @rawTecnico IS NULL
    BEGIN
        SET @detalleTecnico = CONCAT('Mensaje técnico no configurado para el código: ', @codigoResultado);
        SET @tipoTec = 'SYSTEM_ERROR';
        SET @sevTec  = 'CRITICO';
    END
    ELSE
    BEGIN
        SET @detalleTecnico = dbo.ufn_reemplazar_plantilla_mensaje(@rawTecnico, @p_param1, @p_param2, @p_param3);
    END

    SET @mensajeTecnicoResultado = CONCAT('DBCODE=', @codigoResultado, '|', @detalleTecnico);

    -- Asignación de tipoMensaje y severidad garantizando NO NULOS
    SET @tipoMensajeResultado = ISNULL(@tipoUsr, ISNULL(@tipoTec, 'BUSINESS_ERROR'));
    SET @severidadResultado   = ISNULL(@sevUsr, ISNULL(@sevTec, 'MEDIO'));
END;
GO
