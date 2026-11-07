USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.4, DEC-012): horas que vale cada toma de una sesion = horas de la sesion / numero de tomas de la
-- sesion. 0 si la sesion no existe, no tiene tomas o esta cancelada (dbo.SesionCancelacion). Solo para SP: las vistas usan
-- la ventana COUNT(*) OVER (PARTITION BY sesion).
CREATE OR ALTER FUNCTION [dbo].[ufn_horas_toma]
(
    @idSesion UNIQUEIDENTIFIER
)
RETURNS DECIMAL(12,6)
AS
BEGIN
    DECLARE @horas DECIMAL(12,6) = 0;
    DECLARE @tomas INT = (SELECT COUNT(1) FROM dbo.TomaAsistencia t WHERE t.sesion = @idSesion);

    IF @tomas > 0 AND NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesion)
        SELECT @horas = CAST(dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin) / @tomas AS DECIMAL(12,6))
        FROM dbo.Sesion s
        WHERE s.id = @idSesion;

    RETURN @horas;
END;
GO
