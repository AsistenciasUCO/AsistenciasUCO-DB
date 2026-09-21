USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_establecer_contexto_usuario_ejecutor]
    @p_idUsuario UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    EXEC sys.sp_set_session_context 
        @key = N'idUsuarioEjecutor', 
        @value = @p_idUsuario, 
        @read_only = 0;
END;
GO
