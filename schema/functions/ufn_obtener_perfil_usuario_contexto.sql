USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER FUNCTION [dbo].[ufn_obtener_perfil_usuario_contexto] (
    @p_idUsuario UNIQUEIDENTIFIER
)
RETURNS VARCHAR(10)
AS
BEGIN
    IF @p_idUsuario IS NULL
        RETURN NULL;

    DECLARE @v_codigoPerfil VARCHAR(10);

    SELECT TOP 1 @v_codigoPerfil = codigoPerfil
    FROM dbo.uv_usuario_perfil
    WHERE idUsuario = @p_idUsuario;

    RETURN @v_codigoPerfil;
END;
GO
