USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU159 (correccion de identidad de usuarios, 2026-11-05): instantanea JSON de los datos de identidad de un usuario
-- (tipo y numero de documento, nombres y apellidos) para dejar en dbo.AuditoriaEvento los valores anteriores y nuevos.
-- No incluye correo, contrasena ni estado. NULL si el usuario no existe.
CREATE OR ALTER FUNCTION [dbo].[ufn_obtener_identidad_usuario_json]
(
    @idUsuario UNIQUEIDENTIFIER
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    RETURN (
        SELECT idTipoIdentificacion = CAST(u.tipoIdIdentificacion AS NVARCHAR(36)),
               u.numeroIdentificacion,
               u.primerNombre,
               u.segundoNombre,
               u.primerApellido,
               u.segundoApellido
        FROM dbo.Usuario u
        WHERE u.id = @idUsuario
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );
END;
GO
