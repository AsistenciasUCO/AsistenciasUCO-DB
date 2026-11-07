-- CULM-001 B.2 (CONTRACT §2.3, §2.14, §2.16.2 B2-MIG-01..06): migracion 16 (tomas y QR de asistencia).
-- Lo ejecuta test/test_culm001_b2.ps1 con sqlcmd y las variables MIGDIR (copia de migrations/) y SCHEMADIR (copia de
-- schema/). Todo ocurre dentro de UNA transaccion que se revierte al final: la BD queda como estaba.
--   B2-MIG-01  up sobre la BD con datos: una toma 1 por sesion con detalles, toma NOT NULL, indices nuevos, mismos detalles
--   B2-MIG-02  up dos veces: la segunda no cambia nada
--   B2-MIG-03  down con una sola toma: esquema y datos iguales al original (checksum de DetalleAsistencia sin las columnas
--              nuevas); down dos veces es idempotente. (Los casos con 2 tomas, sin y con confirmacion, van en el runner.)
--   B2-MIG-04  up -> down -> up de 15 y 16
--   B2-MIG-05  (simulado) los scripts de tablas, FKs y semillas de B.2 dos veces seguidas sobre la BD con datos y sobre una
--              DetalleAsistencia vacia: sin 4922 ni 50002; NOT NULL, dependientes creados, UX antiguo borrado; la segunda
--              pasada no cambia nada.
--   B2-MIG-06  la secuencia queda por delante de MAX(codigo) tras el despliegue y tras 16_up
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF OBJECT_ID(N'tempdb..#b2mig') IS NOT NULL DROP TABLE #b2mig;
CREATE TABLE #b2mig (k NVARCHAR(60) PRIMARY KEY, v BIGINT);
INSERT INTO #b2mig (k, v)
SELECT N'detalle_checksum', CHECKSUM_AGG(CHECKSUM(id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)) FROM dbo.DetalleAsistencia
UNION ALL SELECT N'detalle_count', COUNT_BIG(*) FROM dbo.DetalleAsistencia
UNION ALL SELECT N'vista_checksum', CHECKSUM_AGG(CHECKSUM(id, codigo, idAsistencia, asistio, idRazonCausa, codigoRazonCausa, fechaHoraInicio, fechaHoraFin)) FROM dbo.uv_detalle_asistencia
UNION ALL SELECT N'sesiones_con_detalle', COUNT_BIG(DISTINCT a.sesion) FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia
UNION ALL SELECT N'multitoma', COUNT_BIG(*) FROM (SELECT asistencia FROM dbo.DetalleAsistencia GROUP BY asistencia HAVING COUNT(*) > 1) x;
IF (SELECT v FROM #b2mig WHERE k = N'multitoma') <> 0
    THROW 57700, 'MIG_PRECONDICION: la BD tiene asistencias con varias tomas; esta prueba parte de una sola toma por asistencia.', 1;
PRINT 'MIG_SNAPSHOT_OK';
GO

-- ---------------------------------------------------------------------------------------------------------------
-- B2-MIG-03 (una sola toma): down restaura el esquema y los datos originales; down dos veces es idempotente
-- ---------------------------------------------------------------------------------------------------------------
:setvar CONFIRMAR_COLAPSO 0
:r $(MIGDIR)/16_culm001_b2_tomas_asistencia_qr_down.sql
GO
IF OBJECT_ID(N'dbo.TomaAsistencia', N'U') IS NOT NULL OR OBJECT_ID(N'dbo.TokenAsistenciaToma', N'U') IS NOT NULL
   OR OBJECT_ID(N'dbo.ModoTomaAsistencia', N'U') IS NOT NULL OR OBJECT_ID(N'dbo.EstadoTomaAsistencia', N'U') IS NOT NULL
   OR COL_LENGTH(N'dbo.DetalleAsistencia', N'toma') IS NOT NULL OR COL_LENGTH(N'dbo.DetalleAsistencia', N'registradoPorEstudiante') IS NOT NULL
   OR COL_LENGTH(N'dbo.DetalleAsistencia', N'fechaRegistroUtc') IS NOT NULL
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND name = N'UX_DetalleAsistencia_Asistencia' AND is_unique = 1)
   OR OBJECT_ID(N'dbo.seq_detalle_asistencia_codigo', N'SO') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_toma_asistencia', N'V') IS NOT NULL OR OBJECT_ID(N'dbo.uv_asistencia_sesion_horas', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_detalle_asistencia_v2', N'V') IS NOT NULL OR OBJECT_ID(N'dbo.uv_faltantes_toma', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_token_asistencia_toma', N'V') IS NOT NULL OR OBJECT_ID(N'dbo.uv_modo_toma_asistencia', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_abrir_toma_asistencia', N'P') IS NOT NULL OR OBJECT_ID(N'dbo.usp_registrar_asistencia_por_token', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_resumen_asistencia_estudiante', N'P') IS NOT NULL OR OBJECT_ID(N'dbo.ufn_horas_sesion', N'FN') IS NOT NULL
   OR (SELECT COUNT(*) FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_sincronizar_asistencia_estudiante_interno')) <> 7
   OR COL_LENGTH(N'dbo.uv_resumen_asistencia_estudiante_grupo', N'horasDictadas') IS NOT NULL
   OR COL_LENGTH(N'dbo.uv_cumplimiento_sesion_grupo', N'totalTomas') IS NOT NULL
   OR COL_LENGTH(N'dbo.uv_sesion_estado', N'totalTomas') IS NOT NULL
   OR NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_ejecutar_cierre_masivo_periodo') AND definition LIKE N'%COUNT(da.id)%')
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_cancelar_sesion') AND definition LIKE N'%TomaAsistencia%')
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_internal_aplicar_festivos_grupo') AND definition LIKE N'%TomaAsistencia%')
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_precargar_sesiones_grupo_interno') AND definition LIKE N'%TomaAsistencia%')
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_kpis_decano') AND definition LIKE N'%horas%')
   OR OBJECT_ID(N'dbo.usp_cancelar_sesion', N'P') IS NULL OR OBJECT_ID(N'dbo.uv_sesion_estado', N'V') IS NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE N'TOM[_]%' OR codigo LIKE N'AQR[_]%')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo IN (N'TOMA_ASISTENCIA', N'ASISTENCIA_QR') OR (grupo = N'ASISTENCIA' AND clave LIKE N'CODIGO_RAZON[_]%'))
    THROW 57710, 'MIG_CHECK_DOWN_FAILED: 16_down no restauro el esquema anterior a B.2.', 1;
IF (SELECT CHECKSUM_AGG(CHECKSUM(id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)) FROM dbo.DetalleAsistencia) <> (SELECT v FROM #b2mig WHERE k = N'detalle_checksum')
   OR (SELECT COUNT_BIG(*) FROM dbo.DetalleAsistencia) <> (SELECT v FROM #b2mig WHERE k = N'detalle_count')
   OR (SELECT CHECKSUM_AGG(CHECKSUM(id, codigo, idAsistencia, asistio, idRazonCausa, codigoRazonCausa, fechaHoraInicio, fechaHoraFin)) FROM dbo.uv_detalle_asistencia) <> (SELECT v FROM #b2mig WHERE k = N'vista_checksum')
    THROW 57711, 'MIG_CHECK_DOWN_DATA: con una sola toma 16_down debe dejar DetalleAsistencia identico al original.', 1;
-- el lote congelado sigue funcionando sobre el esquema restaurado (sincronizar de 7 parametros)
DECLARE @u NVARCHAR(4000), @t NVARCHAR(4000), @e BIT, @c UNIQUEIDENTIFIER = NEWID(), @eg UNIQUEIDENTIFIER, @est UNIQUEIDENTIFIER, @ses UNIQUEIDENTIFIER;
SELECT TOP 1 @est = eg.estudiante, @ses = s.id FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo e ON e.id = eg.estado AND e.codigo = 'A'
INNER JOIN dbo.Sesion s ON s.grupo = eg.grupo ORDER BY s.id;
IF @ses IS NOT NULL
BEGIN
    EXEC dbo.usp_sincronizar_asistencia_estudiante_interno @idEstudiante = @est, @idSesion = @ses, @codigoEstado = N'AN', @idCorrelacion = @c,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT;
    IF @e <> 1 THROW 57712, 'MIG_CHECK_DOWN_SINCRONIZAR: la version restaurada de usp_sincronizar_asistencia_estudiante_interno no funciona.', 1;
END
PRINT 'MIG_DOWN1_OK';
GO
:r $(MIGDIR)/16_culm001_b2_tomas_asistencia_qr_down.sql
GO
PRINT 'MIG_DOWN2_OK';
GO

-- ---------------------------------------------------------------------------------------------------------------
-- B2-MIG-01 / B2-MIG-06: up sobre la BD con datos
-- ---------------------------------------------------------------------------------------------------------------
-- (deshace la escritura de prueba del sincronizar restaurado antes de medir: la fila extra no afecta el conteo de
--  sesiones con detalle, pero si el checksum; se toma un nuevo checksum de referencia)
UPDATE #b2mig SET v = (SELECT CHECKSUM_AGG(CHECKSUM(id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)) FROM dbo.DetalleAsistencia) WHERE k = N'detalle_checksum';
UPDATE #b2mig SET v = (SELECT COUNT_BIG(*) FROM dbo.DetalleAsistencia) WHERE k = N'detalle_count';
UPDATE #b2mig SET v = (SELECT COUNT_BIG(DISTINCT a.sesion) FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia) WHERE k = N'sesiones_con_detalle';
UPDATE #b2mig SET v = (SELECT CHECKSUM_AGG(CHECKSUM(id, codigo, idAsistencia, asistio, idRazonCausa, codigoRazonCausa, fechaHoraInicio, fechaHoraFin)) FROM dbo.uv_detalle_asistencia) WHERE k = N'vista_checksum';
GO
:r $(MIGDIR)/16_culm001_b2_tomas_asistencia_qr_up.sql
GO
IF COLUMNPROPERTY(OBJECT_ID(N'dbo.DetalleAsistencia'), N'toma', N'AllowsNull') <> 0
   OR EXISTS (SELECT 1 FROM dbo.DetalleAsistencia WHERE toma IS NULL)
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND name = N'UX_DetalleAsistencia_Asistencia_Toma' AND is_unique = 1)
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND name = N'IX_DetalleAsistencia_Toma')
   OR NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DetalleAsistencia_TomaAsistencia')
   OR EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND name = N'UX_DetalleAsistencia_Asistencia')
   OR (SELECT COUNT_BIG(*) FROM dbo.TomaAsistencia) <> (SELECT v FROM #b2mig WHERE k = N'sesiones_con_detalle')
   OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia t INNER JOIN dbo.ModoTomaAsistencia m ON m.id = t.modo INNER JOIN dbo.EstadoTomaAsistencia e ON e.id = t.estado
              WHERE t.numero <> 1 OR t.esImplicita <> 1 OR m.usaCodigoQr <> 0 OR e.estaAbierta <> 0 OR t.fechaCierreUtc IS NULL)
   OR EXISTS (SELECT 1 FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia INNER JOIN dbo.TomaAsistencia t ON t.id = da.toma
              WHERE t.sesion <> a.sesion)
   OR (SELECT CHECKSUM_AGG(CHECKSUM(id, codigo, idAsistencia, asistio, idRazonCausa, codigoRazonCausa, fechaHoraInicio, fechaHoraFin)) FROM dbo.uv_detalle_asistencia) <> (SELECT v FROM #b2mig WHERE k = N'vista_checksum')
   OR (SELECT CHECKSUM_AGG(CHECKSUM(id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)) FROM dbo.DetalleAsistencia) <> (SELECT v FROM #b2mig WHERE k = N'detalle_checksum')
   OR OBJECT_ID(N'dbo.uv_toma_asistencia', N'V') IS NULL OR OBJECT_ID(N'dbo.uv_asistencia_sesion_horas', N'V') IS NULL
   OR COL_LENGTH(N'dbo.uv_resumen_asistencia_estudiante_grupo', N'horasDictadas') IS NULL
    THROW 57720, 'MIG_CHECK_UP_FAILED: 16_up no dejo una toma 1 por sesion con detalles, toma NOT NULL e indices nuevos con los mismos detalles.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.sequences sq WHERE sq.object_id = OBJECT_ID(N'dbo.seq_detalle_asistencia_codigo')
               AND CAST(sq.current_value AS BIGINT) >= (SELECT ISNULL(MAX(CAST(codigo AS BIGINT)), 0) FROM dbo.DetalleAsistencia))
    THROW 57721, 'MIG_CHECK_UP_SECUENCIA: tras 16_up la secuencia debe estar por delante de MAX(codigo) (B2-MIG-06).', 1;
UPDATE #b2mig SET v = (SELECT COUNT_BIG(*) FROM dbo.TomaAsistencia) WHERE k = N'multitoma';
PRINT 'MIG_UP1_OK';
GO
:r $(MIGDIR)/16_culm001_b2_tomas_asistencia_qr_up.sql
GO
IF (SELECT COUNT_BIG(*) FROM dbo.TomaAsistencia) <> (SELECT v FROM #b2mig WHERE k = N'multitoma')
   OR COLUMNPROPERTY(OBJECT_ID(N'dbo.DetalleAsistencia'), N'toma', N'AllowsNull') <> 0
    THROW 57722, 'MIG_CHECK_UP2_FAILED: una segunda ejecucion de 16_up no debe cambiar nada (B2-MIG-02).', 1;
PRINT 'MIG_UP2_OK';
GO

-- ---------------------------------------------------------------------------------------------------------------
-- B2-MIG-05 (simulado): tablas, FKs y semillas 35/36 de B.2 dos veces sobre la BD con datos (estado anterior a B.2)
-- ---------------------------------------------------------------------------------------------------------------
:r $(MIGDIR)/16_culm001_b2_tomas_asistencia_qr_down.sql
GO
:r $(SCHEMADIR)/tables/DetalleAsistencia.sql
:r $(SCHEMADIR)/tables/EstadoTomaAsistencia.sql
:r $(SCHEMADIR)/tables/ModoTomaAsistencia.sql
:r $(SCHEMADIR)/tables/TokenAsistenciaToma.sql
:r $(SCHEMADIR)/tables/TomaAsistencia.sql
:r $(SCHEMADIR)/tables/zz_foreign_keys.sql
:r $(SCHEMADIR)/seed/35_catalogos_toma_asistencia.sql
:r $(SCHEMADIR)/seed/36_backfill_toma_asistencia.sql
GO
IF COLUMNPROPERTY(OBJECT_ID(N'dbo.DetalleAsistencia'), N'toma', N'AllowsNull') <> 0
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND name = N'UX_DetalleAsistencia_Asistencia_Toma')
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND name = N'IX_DetalleAsistencia_Toma')
   OR NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DetalleAsistencia_TomaAsistencia')
   OR EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND name = N'UX_DetalleAsistencia_Asistencia')
   OR (SELECT COUNT_BIG(*) FROM dbo.TomaAsistencia) <> (SELECT v FROM #b2mig WHERE k = N'sesiones_con_detalle')
   OR OBJECT_ID(N'dbo.seq_detalle_asistencia_codigo', N'SO') IS NULL
    THROW 57730, 'MIG_CHECK_DEPLOY1_FAILED: la primera pasada de tablas + semilla 36 debe dejar toma NOT NULL con sus dependientes (B2-MIG-05).', 1;
IF OBJECT_ID(N'tempdb..#b2migObj') IS NOT NULL DROP TABLE #b2migObj;
SELECT o.name, o.type, o.modify_date INTO #b2migObj FROM sys.objects o
WHERE o.parent_object_id = OBJECT_ID(N'dbo.DetalleAsistencia') OR o.object_id IN (OBJECT_ID(N'dbo.DetalleAsistencia'), OBJECT_ID(N'dbo.TomaAsistencia'), OBJECT_ID(N'dbo.seq_detalle_asistencia_codigo'));
INSERT INTO #b2migObj (name, type, modify_date) SELECT i.name, 'IX', NULL FROM sys.indexes i WHERE i.object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND i.name IS NOT NULL;
UPDATE #b2mig SET v = (SELECT COUNT_BIG(*) FROM dbo.TomaAsistencia) WHERE k = N'multitoma';
PRINT 'MIG_DEPLOY1_OK';
GO
:r $(SCHEMADIR)/tables/DetalleAsistencia.sql
:r $(SCHEMADIR)/tables/EstadoTomaAsistencia.sql
:r $(SCHEMADIR)/tables/ModoTomaAsistencia.sql
:r $(SCHEMADIR)/tables/TokenAsistenciaToma.sql
:r $(SCHEMADIR)/tables/TomaAsistencia.sql
:r $(SCHEMADIR)/tables/zz_foreign_keys.sql
:r $(SCHEMADIR)/seed/35_catalogos_toma_asistencia.sql
:r $(SCHEMADIR)/seed/36_backfill_toma_asistencia.sql
GO
IF EXISTS (SELECT name, type FROM #b2migObj EXCEPT (SELECT o.name, o.type FROM sys.objects o
               WHERE o.parent_object_id = OBJECT_ID(N'dbo.DetalleAsistencia') OR o.object_id IN (OBJECT_ID(N'dbo.DetalleAsistencia'), OBJECT_ID(N'dbo.TomaAsistencia'), OBJECT_ID(N'dbo.seq_detalle_asistencia_codigo'))
               UNION ALL SELECT i.name, 'IX' FROM sys.indexes i WHERE i.object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND i.name IS NOT NULL))
   OR EXISTS ((SELECT o.name, o.type FROM sys.objects o
               WHERE o.parent_object_id = OBJECT_ID(N'dbo.DetalleAsistencia') OR o.object_id IN (OBJECT_ID(N'dbo.DetalleAsistencia'), OBJECT_ID(N'dbo.TomaAsistencia'), OBJECT_ID(N'dbo.seq_detalle_asistencia_codigo'))
               UNION ALL SELECT i.name, 'IX' FROM sys.indexes i WHERE i.object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND i.name IS NOT NULL) EXCEPT SELECT name, type FROM #b2migObj)
   OR (SELECT COUNT_BIG(*) FROM dbo.TomaAsistencia) <> (SELECT v FROM #b2mig WHERE k = N'multitoma')
   OR EXISTS (SELECT 1 FROM #b2migObj b INNER JOIN sys.objects o ON o.name = b.name AND o.type = b.type WHERE b.modify_date IS NOT NULL AND o.modify_date <> b.modify_date)
    THROW 57731, 'MIG_CHECK_DEPLOY2_FAILED: la segunda pasada de tablas + semilla 36 no debe cambiar nada (B2-MIG-05).', 1;
PRINT 'MIG_DEPLOY2_OK';
GO
-- Variante sin detalles (DetalleAsistencia vacia, como en una BD nueva): estado anterior a B.2 y dos pasadas
:r $(MIGDIR)/16_culm001_b2_tomas_asistencia_qr_down.sql
GO
DELETE FROM dbo.DetalleAsistencia;
GO
:r $(SCHEMADIR)/tables/DetalleAsistencia.sql
:r $(SCHEMADIR)/tables/EstadoTomaAsistencia.sql
:r $(SCHEMADIR)/tables/ModoTomaAsistencia.sql
:r $(SCHEMADIR)/tables/TokenAsistenciaToma.sql
:r $(SCHEMADIR)/tables/TomaAsistencia.sql
:r $(SCHEMADIR)/tables/zz_foreign_keys.sql
:r $(SCHEMADIR)/seed/35_catalogos_toma_asistencia.sql
:r $(SCHEMADIR)/seed/36_backfill_toma_asistencia.sql
:r $(SCHEMADIR)/tables/DetalleAsistencia.sql
:r $(SCHEMADIR)/tables/zz_foreign_keys.sql
:r $(SCHEMADIR)/seed/36_backfill_toma_asistencia.sql
GO
IF COLUMNPROPERTY(OBJECT_ID(N'dbo.DetalleAsistencia'), N'toma', N'AllowsNull') <> 0
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND name = N'UX_DetalleAsistencia_Asistencia_Toma')
   OR NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DetalleAsistencia_TomaAsistencia')
   OR EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND name = N'UX_DetalleAsistencia_Asistencia')
   OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia)
    THROW 57732, 'MIG_CHECK_DEPLOY_VACIA_FAILED: sin detalles las dos pasadas deben dejar toma NOT NULL con dependientes y sin tomas (B2-MIG-05).', 1;
PRINT 'MIG_DEPLOY_VACIA_OK';
GO

-- ---------------------------------------------------------------------------------------------------------------
-- B2-MIG-04: up -> down -> up de 15 y 16 (con la 16 desplegada: 16_down, 15_down, 15_up, 16_up)
-- ---------------------------------------------------------------------------------------------------------------
:r $(MIGDIR)/16_culm001_b2_tomas_asistencia_qr_up.sql
GO
:r $(MIGDIR)/16_culm001_b2_tomas_asistencia_qr_down.sql
GO
:r $(MIGDIR)/15_culm001_b1_sesion_cancelada_festivos_down.sql
GO
IF OBJECT_ID(N'dbo.SesionCancelacion', N'U') IS NOT NULL OR OBJECT_ID(N'dbo.TomaAsistencia', N'U') IS NOT NULL
    THROW 57740, 'MIG_CHECK_15_16_DOWN_FAILED', 1;
PRINT 'MIG_15_16_DOWN_OK';
GO
:r $(MIGDIR)/15_culm001_b1_sesion_cancelada_festivos_up.sql
GO
:r $(MIGDIR)/16_culm001_b2_tomas_asistencia_qr_up.sql
GO
IF OBJECT_ID(N'dbo.SesionCancelacion', N'U') IS NULL OR OBJECT_ID(N'dbo.TomaAsistencia', N'U') IS NULL
   OR COLUMNPROPERTY(OBJECT_ID(N'dbo.DetalleAsistencia'), N'toma', N'AllowsNull') <> 0
   OR COL_LENGTH(N'dbo.uv_sesion_estado', N'totalTomas') IS NULL OR COL_LENGTH(N'dbo.uv_cumplimiento_sesion_grupo', N'totalTomas') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.uv_cumplimiento_sesion_grupo') AND definition LIKE N'%SesionCancelacion%')
    THROW 57741, 'MIG_CHECK_15_16_UP_FAILED: up de 15 y 16 tras el down debe dejar las tablas y vistas de B.1 y B.2.', 1;
PRINT 'MIG_15_16_UP_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0 THROW 57750, 'MIG_TRANCOUNT', 1;
IF OBJECT_ID(N'dbo.usp_abrir_toma_asistencia', N'P') IS NULL OR OBJECT_ID(N'dbo.TomaAsistencia', N'U') IS NULL
   OR COLUMNPROPERTY(OBJECT_ID(N'dbo.DetalleAsistencia'), N'toma', N'AllowsNull') <> 0
   OR (SELECT COUNT(*) FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_sincronizar_asistencia_estudiante_interno')) <> 12
    THROW 57751, 'MIG_ROLLBACK_DID_NOT_RESTORE', 1;
PRINT 'MIG_RESTORED_OK';
GO
