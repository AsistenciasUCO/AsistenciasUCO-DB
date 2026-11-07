USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- culm1_segundo_ambito_down.sql (CULM-001 A.2-13, A2-DB-7): retira el fixture culm1_segundo_ambito.sql.
-- Borra SOLO las filas con ids fijos C1B0... que creo el script, en orden de FK. Nunca borra una CULM1-Facultad B (ni
-- su decano) que ya existia y se encontro por nombre: esa no tiene id C1B0... Idempotente.
-- ============================================================================
SET XACT_ABORT ON;
BEGIN TRANSACTION;

DECLARE @p CHAR(34) = 'C1B00000-0000-4000-8000-0000000000';
DELETE FROM dbo.SolicitudRevisionAsistencia WHERE id = CAST(@p + '81' AS UNIQUEIDENTIFIER);
DELETE FROM dbo.DetalleAsistencia WHERE id IN (CAST(@p + '71' AS UNIQUEIDENTIFIER), CAST(@p + '72' AS UNIQUEIDENTIFIER), CAST(@p + '73' AS UNIQUEIDENTIFIER));
DELETE FROM dbo.Asistencia WHERE id IN (CAST(@p + '61' AS UNIQUEIDENTIFIER), CAST(@p + '62' AS UNIQUEIDENTIFIER), CAST(@p + '63' AS UNIQUEIDENTIFIER));
DELETE FROM dbo.Sesion WHERE id = CAST(@p + '51' AS UNIQUEIDENTIFIER);
DELETE FROM dbo.EstudiantePrograma WHERE id IN (CAST(@p + '41' AS UNIQUEIDENTIFIER), CAST(@p + '42' AS UNIQUEIDENTIFIER), CAST(@p + '43' AS UNIQUEIDENTIFIER));
DELETE FROM dbo.EstudianteGrupo WHERE id IN (CAST(@p + '31' AS UNIQUEIDENTIFIER), CAST(@p + '32' AS UNIQUEIDENTIFIER), CAST(@p + '33' AS UNIQUEIDENTIFIER));
DELETE FROM dbo.Horario WHERE id = CAST(@p + '0D' AS UNIQUEIDENTIFIER);
DELETE FROM dbo.Grupo WHERE id = CAST(@p + '0C' AS UNIQUEIDENTIFIER);
DELETE FROM dbo.Asignatura WHERE id = CAST(@p + '09' AS UNIQUEIDENTIFIER);
DELETE FROM dbo.SemestrePlanEstudio WHERE id = CAST(@p + '08' AS UNIQUEIDENTIFIER);
DELETE FROM dbo.PlanEstudio WHERE id = CAST(@p + '07' AS UNIQUEIDENTIFIER);
DELETE FROM dbo.DocentePrograma WHERE id = CAST(@p + '0E' AS UNIQUEIDENTIFIER);
DELETE FROM dbo.Programa WHERE id = CAST(@p + '06' AS UNIQUEIDENTIFIER);
DELETE FROM dbo.Coordinador WHERE id = CAST(@p + '05' AS UNIQUEIDENTIFIER);
DELETE FROM dbo.Docente WHERE id = CAST(@p + '0B' AS UNIQUEIDENTIFIER);
DELETE FROM dbo.Estudiante WHERE id IN (CAST(@p + '21' AS UNIQUEIDENTIFIER), CAST(@p + '22' AS UNIQUEIDENTIFIER), CAST(@p + '23' AS UNIQUEIDENTIFIER));
DELETE FROM dbo.Facultad WHERE id = CAST(@p + '01' AS UNIQUEIDENTIFIER);
DELETE FROM dbo.Decano WHERE id = CAST(@p + '03' AS UNIQUEIDENTIFIER)
    AND NOT EXISTS (SELECT 1 FROM dbo.Facultad f WHERE f.decano = CAST(@p + '03' AS UNIQUEIDENTIFIER));
DELETE FROM dbo.Usuario
WHERE id IN (CAST(@p + '02' AS UNIQUEIDENTIFIER), CAST(@p + '04' AS UNIQUEIDENTIFIER), CAST(@p + '0A' AS UNIQUEIDENTIFIER),
             CAST(@p + '11' AS UNIQUEIDENTIFIER), CAST(@p + '12' AS UNIQUEIDENTIFIER), CAST(@p + '13' AS UNIQUEIDENTIFIER))
  AND NOT EXISTS (SELECT 1 FROM dbo.Decano d WHERE d.usuario = Usuario.id);

COMMIT TRANSACTION;
PRINT 'CULM1_SEGUNDO_AMBITO retirado (solo filas C1B0...).';
GO
SET XACT_ABORT OFF;
GO
