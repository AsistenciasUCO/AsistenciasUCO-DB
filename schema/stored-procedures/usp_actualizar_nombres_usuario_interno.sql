USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU092: actualiza solo los nombres/apellidos de un usuario (los parametros NULL no se tocan). No modifica correo,
-- documento, contrasena ni estado. Las fachadas publicas aportan RBAC, titularidad, validacion y transaccion.
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_nombres_usuario_interno]
(
    @idUsuario       UNIQUEIDENTIFIER,
    @primerNombre    NVARCHAR(50) = NULL,
    @segundoNombre   NVARCHAR(50) = NULL,
    @primerApellido  NVARCHAR(50) = NULL,
    @segundoApellido NVARCHAR(50) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Usuario
    SET primerNombre    = IIF(@primerNombre    IS NULL, primerNombre,    @primerNombre),
        segundoNombre   = IIF(@segundoNombre   IS NULL, segundoNombre,   @segundoNombre),
        primerApellido  = IIF(@primerApellido  IS NULL, primerApellido,  @primerApellido),
        segundoApellido = IIF(@segundoApellido IS NULL, segundoApellido, @segundoApellido)
    WHERE id = @idUsuario;
END;
GO
