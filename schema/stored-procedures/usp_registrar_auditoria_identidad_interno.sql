USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU159 (correccion de identidad de usuarios, 2026-11-05): registra en dbo.AuditoriaEvento una correccion de datos de
-- identidad con el motivo y los valores anteriores (instantanea tomada por la fachada antes de escribir) y nuevos
-- (ufn_obtener_identidad_usuario_json despues de escribir). Visible en la auditoria del administrador (HU172).
-- Sin transaccion propia (corre dentro de la fachada publica); un error se propaga al CATCH de la fachada.
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_auditoria_identidad_interno]
(
    @idUsuario          UNIQUEIDENTIFIER,
    @identidadAnterior  NVARCHAR(MAX),
    @motivo             NVARCHAR(500),
    @accion             VARCHAR(120),
    @tipoRecurso        VARCHAR(120),
    @idRecurso          UNIQUEIDENTIFIER,
    @ruta               NVARCHAR(240),
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.AuditoriaEvento (
        id, occurredAt, actorId, actorType, action,
        resourceType, resourceId, result, correlationId,
        httpMethod, path, httpStatus, metadata
    ) VALUES (
        NEWID(),
        SYSDATETIMEOFFSET(),
        CAST(@idUsuarioEjecutor AS NVARCHAR(120)),
        'USER',
        @accion,
        @tipoRecurso,
        CAST(@idRecurso AS NVARCHAR(120)),
        'SUCCESS',
        @idCorrelacion,
        'PUT',
        @ruta,
        200,
        (SELECT idUsuario = CAST(@idUsuario AS NVARCHAR(36)),
                motivo = NULLIF(TRIM(@motivo), N''),
                anterior = JSON_QUERY(@identidadAnterior),
                nuevo = JSON_QUERY(dbo.ufn_obtener_identidad_usuario_json(@idUsuario))
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    );
END;
GO
