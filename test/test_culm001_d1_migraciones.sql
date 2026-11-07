-- CULM-001 D.1 (CONTRACT §2.2 D1-11, §14.2 D-RB-01): migracion 20 (plazo de excusas) up -> down -> up.
-- Lo ejecuta test/test_culm001_d1.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/). Todo ocurre dentro de UNA
-- transaccion que se revierte al final: la BD queda como estaba.
--   MIG_D1_DOWN_OK        el down quita la funcion, el interno, la vista, el SP de consulta y los mensajes REV_020/REV_025 y
--                         deja v1/v2 sin el validador de plazo
--   MIG_D1_UP1_OK         el up crea todo y v1/v2 llaman al validador
--   MIG_D1_UP2_OK         el up dos veces no cambia nada (mismos textos)
--   MIG_D1_DOWN_UP_OK     down -> up deja los mismos textos que el primer up
--   MIG_D1_ROLLBACK_OK    la transaccion se revirtio
-- La proteccion D-RB-01 del down (aborta con 50020 si existe el interno de D.2) esta en test_culm001_d1_down_guard.sql.
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF OBJECT_ID(N'tempdb..#d1mig') IS NOT NULL DROP TABLE #d1mig;
CREATE TABLE #d1mig (k NVARCHAR(60) PRIMARY KEY, v VARBINARY(32));
GO
:r $(MIGDIR)/20_culm001_d1_plazo_justificacion_down.sql
GO
IF OBJECT_ID(N'dbo.ufn_calcular_fecha_limite_justificacion', N'FN') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_internal_validar_plazo_justificacion', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_sesion_estudiante_reclamo', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_sesiones_materia_estudiante', N'P') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('REV_020', 'REV_025'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('REV_020', 'REV_025'))
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id IN (OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v2'), OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia'))
              AND definition LIKE N'%usp_internal_validar_plazo_justificacion%')
    THROW 57800, 'TEST FAILED: CULM001_D1_11 el down no restauro el estado anterior a D.1.', 1;
IF OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v2', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia', N'P') IS NULL
    THROW 57801, 'TEST FAILED: CULM001_D1_11 el down borro v1/v2.', 1;
INSERT #d1mig VALUES (N'v2_down', HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v2'))));
INSERT #d1mig VALUES (N'v1_down', HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia'))));
PRINT 'MIG_D1_DOWN_OK';
GO
:r $(MIGDIR)/20_culm001_d1_plazo_justificacion_up.sql
GO
IF OBJECT_ID(N'dbo.ufn_calcular_fecha_limite_justificacion', N'FN') IS NULL
   OR OBJECT_ID(N'dbo.usp_internal_validar_plazo_justificacion', N'P') IS NULL
   OR OBJECT_ID(N'dbo.uv_sesion_estudiante_reclamo', N'V') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_sesiones_materia_estudiante', N'P') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('REV_020', 'REV_025')) <> 2
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('REV_020', 'REV_025')) <> 2
   OR (SELECT COUNT(*) FROM sys.sql_modules WHERE object_id IN (OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v2'), OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia'))
              AND definition LIKE N'%usp_internal_validar_plazo_justificacion%') <> 2
    THROW 57802, 'TEST FAILED: CULM001_D1_11 el up no dejo los objetos de D.1.', 1;
INSERT #d1mig VALUES (N'v2_up', HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v2'))));
INSERT #d1mig VALUES (N'v1_up', HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia'))));
INSERT #d1mig VALUES (N'vista_up', HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.uv_sesion_estudiante_reclamo'))));
PRINT 'MIG_D1_UP1_OK';
GO
:r $(MIGDIR)/20_culm001_d1_plazo_justificacion_up.sql
GO
IF (SELECT v FROM #d1mig WHERE k = N'v2_up') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v2')))
   OR (SELECT v FROM #d1mig WHERE k = N'v1_up') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia')))
   OR (SELECT v FROM #d1mig WHERE k = N'vista_up') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.uv_sesion_estudiante_reclamo')))
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('REV_020', 'REV_025')) <> 2
    THROW 57803, 'TEST FAILED: CULM001_D1_11 el up repetido cambio objetos.', 1;
PRINT 'MIG_D1_UP2_OK';
GO
:r $(MIGDIR)/20_culm001_d1_plazo_justificacion_down.sql
GO
:r $(MIGDIR)/20_culm001_d1_plazo_justificacion_up.sql
GO
IF (SELECT v FROM #d1mig WHERE k = N'v2_up') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v2')))
   OR (SELECT v FROM #d1mig WHERE k = N'v1_up') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia')))
   OR (SELECT v FROM #d1mig WHERE k = N'vista_up') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.uv_sesion_estudiante_reclamo')))
    THROW 57804, 'TEST FAILED: CULM001_D1_11 down -> up no reprodujo el primer up.', 1;
PRINT 'MIG_D1_DOWN_UP_OK';
GO
ROLLBACK TRANSACTION;
GO
PRINT 'MIG_D1_ROLLBACK_OK';
GO
