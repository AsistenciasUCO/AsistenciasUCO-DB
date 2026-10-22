USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Devuelve 1 si el usuario conserva al menos un rol activo (uv_usuario_perfil.estado = 1), 0 en caso contrario.
-- Un rol con estado propio inactivo (HU121/HU122: Coordinador.estado = 0) no figura en uv_usuario_perfil.
-- Determinista sobre vistas. La extension por estado de otros roles (p. ej. Docente) se hace en la vista.
CREATE OR ALTER FUNCTION [dbo].[ufn_usuario_tiene_roles_activos]
(
    @idUsuario UNIQUEIDENTIFIER
)
RETURNS BIT
AS
BEGIN
    RETURN IIF(
        @idUsuario IS NOT NULL
        AND EXISTS (SELECT 1 FROM dbo.uv_usuario_perfil WHERE idUsuario = @idUsuario AND estado = 1),
        1, 0);
END;
GO
