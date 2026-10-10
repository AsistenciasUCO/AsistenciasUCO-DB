USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- UTC-D06-POST-FREEZE: defensa en profundidad de la procedencia temporal.
--
-- Regla: toda sentencia UPDATE que incluya fechaHoraInicio o fechaHoraFin en su lista SET debe
-- incluir tambien procedenciaTemporal en la MISMA sentencia. UPDATE(col) es verdadero cuando la
-- columna aparece en el SET aunque el valor no cambie, por lo que la regla no depende de
-- comparar valores. Los SP autorizados (v1, v2, generador y clasificacion) siempre reafirman la
-- marca; un UPDATE directo 08:00 -> 18:00 que omite la marca se rechaza y se revierte completo.
--
-- Limites documentados (no se prometen):
--   * Un principal con ALTER sobre la tabla (dbo/sysadmin/db_owner) puede deshabilitar el trigger
--     o reafirmar explicitamente una marca falsa: queda bajo el regimen de auditoria del DBA.
--   * El principal runtime NO llega a este trigger por DML directo: DENY INSERT/UPDATE/DELETE en
--     dbo.Sesion (schema/security/rol_asistencias_runtime.sql); solo escribe via EXEC de SP.
CREATE OR ALTER TRIGGER [dbo].[tr_Sesion_procedencia_temporal]
ON [dbo].[Sesion]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM inserted)
        RETURN;

    IF (UPDATE(fechaHoraInicio) OR UPDATE(fechaHoraFin)) AND NOT UPDATE(procedenciaTemporal)
    BEGIN
        THROW 52110, 'UTC_D06_PROCEDENCIA_REQUERIDA: un UPDATE de fechaHoraInicio/fechaHoraFin en dbo.Sesion debe reafirmar procedenciaTemporal en la misma sentencia.', 1;
    END
END;
GO
