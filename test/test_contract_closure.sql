USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_contract_closure';

IF EXISTS (
    SELECT 1
    FROM sys.sql_modules
    WHERE [definition] LIKE '%@idUsuarioEjecutor IS NOT NULL%'
)
    THROW 52000, 'TEST FAILED: PUBLIC_SECURITY_EXECUTOR_REQUIRED found executor bypass pattern.', 1;
PRINT 'TEST_PASS:PUBLIC_SECURITY_EXECUTOR_REQUIRED';

IF EXISTS (
    SELECT 1
    FROM sys.parameters p
    JOIN sys.procedures sp ON sp.object_id = p.object_id
    WHERE SCHEMA_NAME(sp.schema_id) = 'dbo'
      AND sp.name IN ('usp_crear_sesion', 'usp_actualizar_sesion')
      AND p.name = '@idDocente'
)
    THROW 52001, 'TEST FAILED: SESSION_PUBLIC_SIGNATURE still exposes @idDocente.', 1;
PRINT 'TEST_PASS:SESSION_IDDOCENTE_REMOVED';

IF OBJECT_ID('dbo.CatalogoParametro', 'U') IS NULL
   OR OBJECT_ID('dbo.CatalogoMensajeUsuario', 'U') IS NULL
   OR OBJECT_ID('dbo.CatalogoMensajeTecnico', 'U') IS NULL
    THROW 52002, 'TEST FAILED: DEPLOY_CATALOGS_NON_DESTRUCTIVE catalog table missing.', 1;
PRINT 'TEST_PASS:DEPLOY_CATALOGS_NON_DESTRUCTIVE';

IF (SELECT COUNT(1) FROM dbo.CatalogoParametro WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER') <> 1
   OR (SELECT COUNT(1) FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'GEN_002') <> 1
   OR (SELECT COUNT(1) FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'GEN_002') <> 1
    THROW 52003, 'TEST FAILED: DEPLOY_CATALOGS_NON_DESTRUCTIVE seed duplicate check failed.', 1;
PRINT 'TEST_PASS:CATALOG_SEEDS_NO_DUPLICATES';

IF (SELECT COUNT(1) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.AuditoriaEvento')) <> 17
   OR NOT EXISTS (SELECT 1 FROM sys.columns c JOIN sys.types t ON t.user_type_id = c.user_type_id WHERE c.object_id = OBJECT_ID('dbo.AuditoriaEvento') AND c.name = 'occurredAt' AND t.name = 'datetimeoffset' AND c.scale = 7 AND c.is_nullable = 0)
    THROW 52004, 'TEST FAILED: AUDIT_SCHEMA_IMMUTABLE shape check failed.', 1;
PRINT 'TEST_PASS:AUDIT_SCHEMA_IMMUTABLE';

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @catNow DATETIME = SYSUTCDATETIME();
    MERGE dbo.CatalogoParametro AS Target
    USING (VALUES ('QA_UTC', 'UTC_CATALOG_TIMESTAMPS', 'ok', 'STRING', 'ok')) AS Source(grupo, clave, valor, tipoDato, valorDefecto)
    ON Target.grupo = Source.grupo AND Target.clave = Source.clave
    WHEN MATCHED THEN
        UPDATE SET valor = Source.valor, fechaModificacion = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
        VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.CatalogoParametro
        WHERE grupo = 'QA_UTC'
          AND clave = 'UTC_CATALOG_TIMESTAMPS'
          AND ABS(DATEDIFF(SECOND, @catNow, fechaModificacion)) <= 5
    )
        THROW 52005, 'TEST FAILED: UTC_CATALOG_TIMESTAMPS did not use UTC timestamp.', 1;

    DECLARE @auditId UNIQUEIDENTIFIER = NEWID();
    DECLARE @occurredAt DATETIMEOFFSET(7) = TODATETIMEOFFSET(SYSUTCDATETIME(), '+00:00');
    INSERT dbo.AuditoriaEvento (
        id, occurredAt, actorId, actorType, [action], resourceType, resourceId, result,
        correlationId, traceId, spanId, httpMethod, [path], httpStatus, clientIp, errorCode, metadata
    )
    VALUES (
        @auditId, @occurredAt, NULL, 'SYSTEM', 'UTC_AUDIT_TIMESTAMP', 'DB', NULL, 'SUCCESS',
        NEWID(), NULL, NULL, 'SQL', N'/db/fixture', 200, NULL, NULL, N'{"source":"test"}'
    );

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.AuditoriaEvento
        WHERE id = @auditId
          AND DATEPART(TZOFFSET, occurredAt) = 0
    )
        THROW 52006, 'TEST FAILED: UTC_AUDIT_TIMESTAMP did not persist +00:00 offset.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
PRINT 'TEST_PASS:UTC_CATALOG_TIMESTAMPS';
PRINT 'TEST_PASS:UTC_AUDIT_TIMESTAMP';

IF (SELECT COUNT(1) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.uv_parametro') AND name IN ('grupo', 'clave', 'valor', 'estaActivo', 'fechaModificacion')) <> 5
    THROW 52007, 'TEST FAILED: CATALOG_PARAMETER_CACHE_CONTRACT missing uv_parametro columns.', 1;
PRINT 'TEST_PASS:CATALOG_PARAMETER_CACHE_CONTRACT';

IF (SELECT COUNT(1) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.uv_mensaje_usuario') AND name IN ('codigo', 'contenido', 'estaActivo', 'fechaModificacion')) <> 4
   OR (SELECT COUNT(1) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.uv_mensaje_tecnico') AND name IN ('codigo', 'contenido', 'estaActivo', 'fechaModificacion')) <> 4
    THROW 52008, 'TEST FAILED: CATALOG_MESSAGE_CACHE_CONTRACT missing message view columns.', 1;
PRINT 'TEST_PASS:CATALOG_MESSAGE_CACHE_CONTRACT';

DECLARE @badResultSets TABLE (
    procedureName SYSNAME NOT NULL,
    reason NVARCHAR(4000) NOT NULL
);

INSERT @badResultSets (procedureName, reason)
SELECT sp.name, CONCAT('describe_error=', COALESCE(CONVERT(NVARCHAR(20), d.error_number), N'NULL'), ': ', COALESCE(d.error_message, N''))
FROM sys.procedures sp
CROSS APPLY sys.dm_exec_describe_first_result_set_for_object(sp.object_id, NULL) d
WHERE SCHEMA_NAME(sp.schema_id) = 'dbo'
  AND sp.name LIKE 'usp[_]%'
  AND sp.name NOT LIKE '%[_]interno'
  AND sp.name <> 'usp_obtener_mensaje_catalogo'
  AND d.error_number IS NOT NULL;

INSERT @badResultSets (procedureName, reason)
SELECT sp.name, CONCAT('canonical_columns=', COUNT(d.column_ordinal))
FROM sys.procedures sp
CROSS APPLY sys.dm_exec_describe_first_result_set_for_object(sp.object_id, NULL) d
WHERE SCHEMA_NAME(sp.schema_id) = 'dbo'
  AND sp.name LIKE 'usp[_]%'
  AND sp.name NOT LIKE '%[_]interno'
  AND sp.name <> 'usp_obtener_mensaje_catalogo'
  AND d.error_number IS NULL
GROUP BY sp.name
HAVING COUNT(d.column_ordinal) <> 4;

INSERT @badResultSets (procedureName, reason)
SELECT sp.name, CONCAT('bad column ', d.column_ordinal, ': ', d.name, '/', d.system_type_name)
FROM sys.procedures sp
CROSS APPLY sys.dm_exec_describe_first_result_set_for_object(sp.object_id, NULL) d
WHERE SCHEMA_NAME(sp.schema_id) = 'dbo'
  AND sp.name LIKE 'usp[_]%'
  AND sp.name NOT LIKE '%[_]interno'
  AND sp.name <> 'usp_obtener_mensaje_catalogo'
  AND d.error_number IS NULL
  AND (
       (d.column_ordinal = 1 AND (d.name <> 'idCorrelacion' OR d.system_type_name <> 'uniqueidentifier'))
    OR (d.column_ordinal = 2 AND (d.name <> 'mensajeUsuarioResultado' OR d.system_type_name NOT LIKE 'nvarchar%'))
    OR (d.column_ordinal = 3 AND (d.name <> 'mensajeTecnicoResultado' OR d.system_type_name NOT LIKE 'nvarchar%'))
    OR (d.column_ordinal = 4 AND (d.name <> 'estadoResultado' OR d.system_type_name <> 'bit'))
  );

IF EXISTS (SELECT 1 FROM @badResultSets)
BEGIN
    DECLARE @publicResultFailure NVARCHAR(4000) = (
        SELECT TOP 1 CONCAT('TEST FAILED: PUBLIC_CANONICAL_RESULTSET ', procedureName, ' ', reason)
        FROM @badResultSets
        ORDER BY procedureName
    );
    THROW 52009, @publicResultFailure, 1;
END
PRINT 'TEST_PASS:PUBLIC_CANONICAL_RESULTSET';

IF @@TRANCOUNT <> 0 THROW 52010, 'TEST FAILED: test_contract_closure left transaction open.', 1;
PRINT 'TEST END: test_contract_closure';
GO
