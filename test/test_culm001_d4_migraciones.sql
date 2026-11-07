-- CULM-001 D.4 (CONTRACT §5.2 D4-12): migracion 23 (admision de estudiantes) up -> down -> up.
-- Lo ejecuta test/test_culm001_d4.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/). Todo ocurre dentro de UNA
-- transaccion que se revierte al final: la BD queda como estaba.
--   MIG_D4_DOWN_OK     el down quita usp_admitir_estudiante, usp_consultar_programas_institucion_paginado, los mensajes ADS_* y
--                      los parametros IDENTIDAD/PERFILES_CORRECCION_*, y restaura usp_corregir_identidad_usuario anterior a D.4
--   MIG_D4_UP1_OK      el up crea todo y usp_corregir_identidad_usuario lee los perfiles de los parametros
--   MIG_D4_UP2_OK      el up dos veces no cambia nada (mismos textos)
--   MIG_D4_DOWN_UP_OK  down -> up deja los mismos textos que el primer up
--   MIG_D4_ROLLBACK_OK la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF OBJECT_ID(N'tempdb..#d4mig') IS NOT NULL DROP TABLE #d4mig;
CREATE TABLE #d4mig (k NVARCHAR(60) PRIMARY KEY, v VARBINARY(32));
GO
:r $(MIGDIR)/23_culm001_d4_admision_estudiantes_down.sql
GO
IF OBJECT_ID(N'dbo.usp_admitir_estudiante', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_programas_institucion_paginado', N'P') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'ADS[_]%')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo LIKE 'ADS[_]%')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'IDENTIDAD' AND clave IN ('PERFILES_CORRECCION_ESTUDIANTE', 'PERFILES_CORRECCION_DECANO'))
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_corregir_identidad_usuario') AND definition LIKE N'%PERFILES_CORRECCION%')
    THROW 57900, 'TEST FAILED: CULM001_D4_12 el down no restauro el estado anterior a D.4.', 1;
IF OBJECT_ID(N'dbo.usp_corregir_identidad_usuario', N'P') IS NULL
    THROW 57901, 'TEST FAILED: CULM001_D4_12 el down borro usp_corregir_identidad_usuario.', 1;
PRINT 'MIG_D4_DOWN_OK';
GO
:r $(MIGDIR)/23_culm001_d4_admision_estudiantes_up.sql
GO
IF OBJECT_ID(N'dbo.usp_admitir_estudiante', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_programas_institucion_paginado', N'P') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'ADS[_]%') <> 6
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo LIKE 'ADS[_]%') <> 6
   OR (SELECT COUNT(*) FROM dbo.CatalogoParametro WHERE grupo = 'IDENTIDAD' AND clave IN ('PERFILES_CORRECCION_ESTUDIANTE', 'PERFILES_CORRECCION_DECANO')) <> 2
   OR NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_corregir_identidad_usuario') AND definition LIKE N'%PERFILES_CORRECCION_ESTUDIANTE%')
    THROW 57902, 'TEST FAILED: CULM001_D4_12 el up no dejo los objetos de D.4.', 1;
INSERT #d4mig VALUES (N'admitir', HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_admitir_estudiante'))));
INSERT #d4mig VALUES (N'corregir', HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_corregir_identidad_usuario'))));
INSERT #d4mig VALUES (N'programas', HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_programas_institucion_paginado'))));
PRINT 'MIG_D4_UP1_OK';
GO
:r $(MIGDIR)/23_culm001_d4_admision_estudiantes_up.sql
GO
IF (SELECT v FROM #d4mig WHERE k = N'admitir') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_admitir_estudiante')))
   OR (SELECT v FROM #d4mig WHERE k = N'corregir') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_corregir_identidad_usuario')))
   OR (SELECT v FROM #d4mig WHERE k = N'programas') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_programas_institucion_paginado')))
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'ADS[_]%') <> 6
    THROW 57903, 'TEST FAILED: CULM001_D4_12 el up repetido cambio objetos.', 1;
PRINT 'MIG_D4_UP2_OK';
GO
:r $(MIGDIR)/23_culm001_d4_admision_estudiantes_down.sql
GO
:r $(MIGDIR)/23_culm001_d4_admision_estudiantes_up.sql
GO
IF (SELECT v FROM #d4mig WHERE k = N'admitir') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_admitir_estudiante')))
   OR (SELECT v FROM #d4mig WHERE k = N'corregir') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_corregir_identidad_usuario')))
   OR (SELECT v FROM #d4mig WHERE k = N'programas') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_programas_institucion_paginado')))
    THROW 57904, 'TEST FAILED: CULM001_D4_12 down -> up no reprodujo el primer up.', 1;
PRINT 'MIG_D4_DOWN_UP_OK';
GO
ROLLBACK TRANSACTION;
GO
PRINT 'MIG_D4_ROLLBACK_OK';
GO
