-- CULM-001 D.1 (CONTRACT §14.2, D-RB-01): el down de la migracion 20 se niega a retroceder si D.2 ya esta aplicada
-- (existe usp_internal_radicar_solicitud_revision o usp_radicar_solicitud_revision_asistencia_v3). Se simula D.2 con un
-- procedimiento vacio dentro de una transaccion; el down debe abortar con THROW 50020 y no cambiar nada. Lo ejecuta
-- test/test_culm001_d1.ps1 con sqlcmd -b y MIGDIR; la transaccion nunca se confirma (la conexion termina en el error).
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO
BEGIN TRANSACTION;
GO
IF OBJECT_ID(N'dbo.usp_internal_radicar_solicitud_revision', N'P') IS NOT NULL
    THROW 57810, 'TEST FAILED: CULM001_D1_RB_01 el interno de D.2 ya existe; la prueba no puede simularlo.', 1;
EXEC (N'CREATE PROCEDURE dbo.usp_internal_radicar_solicitud_revision AS RETURN 0;');
GO
PRINT 'DOWN_GUARD_STUB_OK';
GO
:r $(MIGDIR)/20_culm001_d1_plazo_justificacion_down.sql
GO
PRINT 'DOWN_GUARD_NOT_ENFORCED';
GO
ROLLBACK TRANSACTION;
GO
