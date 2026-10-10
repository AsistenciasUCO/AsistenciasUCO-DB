USE [gestionasistenciadb];
GO
-- UTC-D06-POST-FREEZE: procedencia temporal de dbo.Sesion.
-- Oraculos: docs/work-items/UTC-D06-POST-FREEZE/TEST_PLAN.md (D06-01..D06-11).
-- Bloque 1 (transaccion revertida): esquema, SP v1/v2, permisos efectivos, clasificacion, generador, snapshot.
-- Bloque 2 (autocommit aislado): UPDATE directo rechazado por trigger y fila intacta; limpieza garantizada.
SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_utc_d06_procedencia_temporal';

-- D06-01: columna nullable NVARCHAR(24), sin DEFAULT, CHECK habilitado y confiable.
IF NOT EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('dbo.Sesion') AND c.name = 'procedenciaTemporal'
      AND TYPE_NAME(c.user_type_id) = 'nvarchar' AND c.max_length = 48 AND c.is_nullable = 1
      AND c.default_object_id = 0
)
    THROW 53001, 'TEST FAILED: UTC_D06_SCHEMA_COLUMN procedenciaTemporal NVARCHAR(24) NULL sin default.', 1;
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID('dbo.Sesion') AND name = 'CK_Sesion_ProcedenciaTemporal'
      AND is_disabled = 0 AND is_not_trusted = 0
)
    THROW 53002, 'TEST FAILED: UTC_D06_SCHEMA_COLUMN CHECK de procedencia ausente o no confiable.', 1;
IF (SELECT TOP 1 column_id FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Sesion') AND name = 'procedenciaTemporal')
   <> (SELECT MAX(column_id) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Sesion'))
    THROW 53003, 'TEST FAILED: UTC_D06_SCHEMA_COLUMN procedenciaTemporal debe ser la ultima columna (DB nueva = DB migrada).', 1;
PRINT 'TEST_PASS:UTC_D06_SCHEMA_COLUMN';

-- D06-01: filas sembradas (historicas) quedan INDETERMINADAS con sus DATETIME2 exactos.
IF EXISTS (
    SELECT 1 FROM dbo.Sesion
    WHERE id IN ('B2C3D4E5-F6A7-8B9C-0D1E-2F3A4B5C6D7E', 'C3D4E5F6-A7B8-9C0D-1E2F-3A4B5C6D7E8F')
      AND procedenciaTemporal IS NOT NULL
)
    THROW 53004, 'TEST FAILED: UTC_D06_LEGACY_ROWS_NULL una sesion sembrada recibio procedencia.', 1;
IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = 'B2C3D4E5-F6A7-8B9C-0D1E-2F3A4B5C6D7E')
   AND NOT EXISTS (
    SELECT 1 FROM dbo.Sesion
    WHERE id = 'B2C3D4E5-F6A7-8B9C-0D1E-2F3A4B5C6D7E'
      AND fechaHoraInicio = CAST('2026-08-17T08:00:00.0000000' AS DATETIME2(7))
      AND fechaHoraFin = CAST('2026-08-17T10:00:00.0000000' AS DATETIME2(7))
)
    THROW 53005, 'TEST FAILED: UTC_D06_LEGACY_ROWS_NULL la migracion altero las horas sembradas.', 1;
PRINT 'TEST_PASS:UTC_D06_LEGACY_ROWS_NULL';

-- D06-08/D06-09: v2 conserva las 10 columnas legacy (nombre/orden/tipo/nulabilidad) + procedencia.
DECLARE @v1Shape NVARCHAR(MAX) = (
    SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT(c.column_id, ':', c.name, ':', t.name, ':', c.scale, ':', c.is_nullable)), ',')
           WITHIN GROUP (ORDER BY c.column_id)
    FROM sys.columns c JOIN sys.types t ON t.user_type_id = c.user_type_id
    WHERE c.object_id = OBJECT_ID('dbo.uv_sesion')
);
DECLARE @v2Shape NVARCHAR(MAX) = (
    SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT(c.column_id, ':', c.name, ':', t.name, ':', c.scale, ':', c.is_nullable)), ',')
           WITHIN GROUP (ORDER BY c.column_id)
    FROM sys.columns c JOIN sys.types t ON t.user_type_id = c.user_type_id
    WHERE c.object_id = OBJECT_ID('dbo.uv_sesion_v2') AND c.column_id <= 10
);
IF @v1Shape IS NULL OR @v2Shape IS NULL OR @v1Shape <> @v2Shape
    THROW 53006, 'TEST FAILED: UTC_D06_V2_VIEW_SHAPE columnas 1..10 de uv_sesion_v2 difieren de uv_sesion.', 1;
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.uv_sesion_v2') AND column_id = 11 AND name = 'procedenciaTemporal'
      AND TYPE_NAME(user_type_id) = 'nvarchar' AND max_length = 48 AND is_nullable = 1
) OR (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.uv_sesion_v2')) <> 11
    THROW 53007, 'TEST FAILED: UTC_D06_V2_VIEW_SHAPE columna 11 procedenciaTemporal ausente o sobrante.', 1;
IF (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.uv_sesion')) <> 10
   OR EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.uv_auth_sesion') AND name = 'procedenciaTemporal')
    THROW 53008, 'TEST FAILED: UTC_D06_V2_VIEW_SHAPE una vista v1 gano columnas.', 1;
PRINT 'TEST_PASS:UTC_D06_V2_VIEW_SHAPE';

-- Firmas v2 = firmas v1 (mismos parametros nombrados) y resultset canonico de 4 columnas.
DECLARE @sigCrearV1 NVARCHAR(MAX) = (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT(p.name, ':', TYPE_NAME(p.user_type_id))), ',') WITHIN GROUP (ORDER BY p.parameter_id) FROM sys.parameters p WHERE p.object_id = OBJECT_ID('dbo.usp_crear_sesion'));
DECLARE @sigCrearV2 NVARCHAR(MAX) = (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT(p.name, ':', TYPE_NAME(p.user_type_id))), ',') WITHIN GROUP (ORDER BY p.parameter_id) FROM sys.parameters p WHERE p.object_id = OBJECT_ID('dbo.usp_crear_sesion_v2'));
DECLARE @sigActV1 NVARCHAR(MAX) = (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT(p.name, ':', TYPE_NAME(p.user_type_id))), ',') WITHIN GROUP (ORDER BY p.parameter_id) FROM sys.parameters p WHERE p.object_id = OBJECT_ID('dbo.usp_actualizar_sesion'));
DECLARE @sigActV2 NVARCHAR(MAX) = (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT(p.name, ':', TYPE_NAME(p.user_type_id))), ',') WITHIN GROUP (ORDER BY p.parameter_id) FROM sys.parameters p WHERE p.object_id = OBJECT_ID('dbo.usp_actualizar_sesion_v2'));
IF @sigCrearV2 IS NULL OR @sigCrearV1 <> @sigCrearV2 OR @sigActV2 IS NULL OR @sigActV1 <> @sigActV2
    THROW 53009, 'TEST FAILED: UTC_D06_V2_SIGNATURES las firmas v2 no replican las v1.', 1;
IF EXISTS (
    SELECT 1
    FROM (VALUES ('usp_crear_sesion_v2'), ('usp_actualizar_sesion_v2'), ('usp_clasificar_procedencia_sesion')) e(procedureName)
    CROSS APPLY sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(CONCAT('dbo.', e.procedureName)), NULL) d
    GROUP BY e.procedureName
    HAVING COUNT(d.column_ordinal) <> 4 OR MAX(d.error_number) IS NOT NULL
       OR MAX(CASE WHEN d.column_ordinal = 1 THEN d.name END) <> 'idCorrelacion'
       OR MAX(CASE WHEN d.column_ordinal = 4 THEN d.name END) <> 'estadoResultado'
)
    THROW 53010, 'TEST FAILED: UTC_D06_V2_SIGNATURES resultset canonico alterado.', 1;
PRINT 'TEST_PASS:UTC_D06_V2_SIGNATURES';
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @grupo UNIQUEIDENTIFIER, @periodo UNIQUEIDENTIFIER, @docente UNIQUEIDENTIFIER, @usuarioDocente UNIQUEIDENTIFIER;
SELECT TOP 1 @grupo = id, @periodo = idPeriodoAcademico, @docente = idDocente
FROM dbo.uv_grupo WHERE grupoEstaHablitado = 1 ORDER BY cuposDisponibles DESC;
SELECT TOP 1 @usuarioDocente = idUsuario FROM dbo.uv_docente_identidad WHERE id = @docente;
DECLARE @institucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
DECLARE @usuarioAdmin UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_usuario_perfil WHERE codigoPerfil = 'AD' AND estado = 1);
DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
IF @grupo IS NULL OR @usuarioDocente IS NULL OR @usuarioAdmin IS NULL OR @institucion IS NULL OR @tipoId IS NULL
    THROW 53020, 'TEST FAILED: UTC_D06 fixture incompleta (grupo/docente/admin/institucion/CC).', 1;

CREATE TABLE #r (
    idCorrelacion UNIQUEIDENTIFIER,
    mensajeUsuarioResultado NVARCHAR(4000),
    mensajeTecnicoResultado NVARCHAR(4000),
    estadoResultado BIT
);

BEGIN TRANSACTION;
BEGIN TRY
    -- D06-02: v2 crea con el instante UTC exacto (Bogota 20:00-22:00 -05:00 = 01:00-03:00Z dia siguiente)
    -- y 7 decimales sin redondeo; marca UTC_V2 en el mismo INSERT.
    DECLARE @inicioV2 DATETIME2(7) = '2026-07-16T01:00:00.1234567';
    DECLARE @finV2 DATETIME2(7) = '2026-07-16T03:00:00.0000001';
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #r EXEC dbo.usp_crear_sesion_v2
        @idGrupo = @grupo, @nombre = N'D06 V2 Bogota', @fechaHoraInicio = @inicioV2, @fechaHoraFin = @finV2,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioDocente;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @corr)
        THROW 53021, 'TEST FAILED: UTC_D06_V2_CREATE_MARK usp_crear_sesion_v2 no retorno SUCCESS.', 1;
    DECLARE @sesionV2 UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Sesion WHERE grupo = @grupo AND nombre = N'D06 V2 Bogota');
    IF NOT EXISTS (
        SELECT 1 FROM dbo.uv_sesion_v2
        WHERE id = @sesionV2 AND procedenciaTemporal = N'UTC_V2'
          AND fechaHoraInicio = @inicioV2 AND fechaHoraFin = @finV2
    )
        THROW 53022, 'TEST FAILED: UTC_D06_V2_CREATE_MARK hora/marca UTC_V2 no persistidas exactamente.', 1;
    PRINT 'TEST_PASS:UTC_D06_V2_CREATE_MARK';

    -- D06-04: v1 crea INDETERMINADA (NULL) sin cambiar su firma ni resultset.
    TRUNCATE TABLE #r;
    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_crear_sesion
        @idGrupo = @grupo, @nombre = N'D06 V1 Legacy',
        @fechaHoraInicio = '2026-07-20T13:00:00', @fechaHoraFin = '2026-07-20T15:00:00',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioDocente;
    DECLARE @sesionV1 UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Sesion WHERE grupo = @grupo AND nombre = N'D06 V1 Legacy');
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @sesionV1 AND procedenciaTemporal IS NULL)
        THROW 53023, 'TEST FAILED: UTC_D06_V1_CREATE_NULL v1 debe crear con procedenciaTemporal NULL.', 1;
    PRINT 'TEST_PASS:UTC_D06_V1_CREATE_NULL';

    -- D06-03: v2 PATCH sobre sesion INDETERMINADA la confirma (horas + marca, misma sentencia).
    TRUNCATE TABLE #r;
    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_sesion_v2
        @idSesion = @sesionV1, @nombre = N'D06 V1 Confirmada',
        @fechaHoraInicio = '2026-07-21T00:30:00', @fechaHoraFin = '2026-07-21T02:00:00',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioDocente;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (
            SELECT 1 FROM dbo.Sesion
            WHERE id = @sesionV1 AND procedenciaTemporal = N'UTC_V2' AND nombre = N'D06 V1 Confirmada'
              AND fechaHoraInicio = '2026-07-21T00:30:00' AND fechaHoraFin = '2026-07-21T02:00:00')
        THROW 53024, 'TEST FAILED: UTC_D06_V2_UPDATE_MARK PATCH v2 no confirmo horas+marca.', 1;
    PRINT 'TEST_PASS:UTC_D06_V2_UPDATE_MARK';

    -- HTTP-02/D06-10: fin <= inicio (UTC) conserva SES_004 y no escribe nada.
    TRUNCATE TABLE #r;
    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_sesion_v2
        @idSesion = @sesionV2, @nombre = N'D06 Invertida',
        @fechaHoraInicio = '2026-07-16T03:00:00', @fechaHoraFin = '2026-07-16T03:00:00',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioDocente;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE '%SES_004%')
       OR NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @sesionV2 AND nombre = N'D06 V2 Bogota'
                      AND fechaHoraInicio = @inicioV2 AND fechaHoraFin = @finV2 AND procedenciaTemporal = N'UTC_V2')
        THROW 53025, 'TEST FAILED: UTC_D06_V2_SES_004_NO_WRITE rango invertido modifico la sesion.', 1;
    PRINT 'TEST_PASS:UTC_D06_V2_SES_004_NO_WRITE';

    -- HTTP-03: docente no titular rechazado (SEC_002) sin mutacion.
    DECLARE @usuarioIntruso UNIQUEIDENTIFIER = 'D06D06D0-0000-0000-0000-000000000001';
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido,
        primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@usuarioIntruso, @tipoId, 906000001, N'Docente', N'Ajeno', N'Utc', N'Qa', N'd06.intruso@test.local', 1, 1, N'HashBackend_QaD06_1234567890');
    INSERT INTO dbo.Docente (id, usuario) VALUES ('D06D06D0-0000-0000-0000-000000000002', @usuarioIntruso);
    TRUNCATE TABLE #r;
    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_sesion_v2
        @idSesion = @sesionV2, @nombre = N'D06 Intrusa',
        @fechaHoraInicio = '2026-07-16T05:00:00', @fechaHoraFin = '2026-07-16T06:00:00',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioIntruso;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @sesionV2 AND fechaHoraInicio = @inicioV2 AND procedenciaTemporal = N'UTC_V2')
        THROW 53026, 'TEST FAILED: UTC_D06_V2_NON_OWNER docente ajeno modifico la sesion.', 1;
    PRINT 'TEST_PASS:UTC_D06_V2_NON_OWNER';

    -- D06-04/READ-04: v1 PATCH sobre sesion CONFIRMADA la invalida aunque las horas sean identicas.
    TRUNCATE TABLE #r;
    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_sesion
        @idSesion = @sesionV1, @nombre = N'D06 V1 Confirmada',
        @fechaHoraInicio = '2026-07-21T00:30:00', @fechaHoraFin = '2026-07-21T02:00:00',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioDocente;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_v2 WHERE id = @sesionV1 AND procedenciaTemporal IS NULL
                      AND fechaHoraInicio = '2026-07-21T00:30:00')
        THROW 53027, 'TEST FAILED: UTC_D06_V1_UPDATE_INVALIDATES v1 no invalido la marca confirmada.', 1;
    PRINT 'TEST_PASS:UTC_D06_V1_UPDATE_INVALIDATES';

    -- Nucleo interno: no acepta procedencias reservadas al generador o al owner.
    TRUNCATE TABLE #r;
    DECLARE @iCorr UNIQUEIDENTIFIER, @iUsr NVARCHAR(4000), @iTec NVARCHAR(4000), @iEst BIT;
    DECLARE @conteoGrupo INT = (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @grupo);
    EXEC dbo.usp_crear_sesion_interno
        @idGrupo = @grupo, @nombre = N'D06 Owner Falso', @fechaHoraInicio = '2026-07-22T13:00:00',
        @fechaHoraFin = '2026-07-22T14:00:00', @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioDocente,
        @procedenciaTemporal = N'UTC_OWNER', @idCorrelacionResultado = @iCorr OUTPUT,
        @mensajeUsuarioResultado = @iUsr OUTPUT, @mensajeTecnicoResultado = @iTec OUTPUT, @estadoResultado = @iEst OUTPUT;
    IF @iEst <> 0 OR @conteoGrupo <> (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @grupo)
        THROW 53028, 'TEST FAILED: UTC_D06_INTERNAL_REJECTS_RESERVED_MARK el nucleo acepto UTC_OWNER.', 1;
    PRINT 'TEST_PASS:UTC_D06_INTERNAL_REJECTS_RESERVED_MARK';

    -- CHECK: valores fuera del catalogo de procedencia se rechazan (error 547) sin insertar.
    DECLARE @checkRechazo BIT = 0;
    BEGIN TRY
        INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
        VALUES (NEWID(), N'D06 Check', 9901, N'D06-CHK', 1, @grupo, '2026-07-23T13:00:00', '2026-07-23T14:00:00', N'UTC_LOCAL');
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 547 SET @checkRechazo = 1;
    END CATCH
    IF @checkRechazo = 0 OR XACT_STATE() <> 1 OR EXISTS (SELECT 1 FROM dbo.Sesion WHERE codigo = N'D06-CHK')
        THROW 53029, 'TEST FAILED: UTC_D06_CHECK_REJECTS_UNKNOWN CHECK no rechazo UTC_LOCAL.', 1;
    PRINT 'TEST_PASS:UTC_D06_CHECK_REJECTS_UNKNOWN';

    -- D06-09: uv_sesion_v2 = uv_sesion (10 columnas) para TODAS las filas, sin ocultar historicos.
    IF EXISTS (
        SELECT id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin FROM dbo.uv_sesion
        EXCEPT
        SELECT id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin FROM dbo.uv_sesion_v2
    ) OR EXISTS (
        SELECT id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin FROM dbo.uv_sesion_v2
        EXCEPT
        SELECT id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin FROM dbo.uv_sesion
    ) OR EXISTS (
        SELECT 1 FROM dbo.uv_sesion_v2 v JOIN dbo.Sesion s ON s.id = v.id
        WHERE NOT (v.procedenciaTemporal = s.procedenciaTemporal OR (v.procedenciaTemporal IS NULL AND s.procedenciaTemporal IS NULL))
    ) OR (SELECT COUNT(*) FROM dbo.uv_sesion_v2) <> (SELECT COUNT(*) FROM dbo.uv_sesion)
        THROW 53030, 'TEST FAILED: UTC_D06_V2_VIEW_PARITY uv_sesion_v2 no refleja uv_sesion + marca de la misma fila.', 1;
    PRINT 'TEST_PASS:UTC_D06_V2_VIEW_PARITY';

    -- D06-06 (permisos EFECTIVOS): principal del rol runtime, sin login, via EXECUTE AS USER.
    CREATE USER [utc_d06_runtime_probe] WITHOUT LOGIN;
    ALTER ROLE [rol_asistencias_runtime] ADD MEMBER [utc_d06_runtime_probe];
    DECLARE @dmlDenegado BIT = 0, @selectTablaDenegado BIT = 0, @internoDenegado BIT = 0, @clasificarDenegado BIT = 0;
    DECLARE @lecturaV2 INT = NULL;
    DECLARE @rProbe TABLE (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    EXECUTE AS USER = 'utc_d06_runtime_probe';
        BEGIN TRY
            UPDATE dbo.Sesion SET fechaHoraInicio = DATEADD(HOUR, 10, fechaHoraInicio), procedenciaTemporal = procedenciaTemporal WHERE id = @sesionV2;
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() = 229 SET @dmlDenegado = 1;
        END CATCH
        BEGIN TRY
            DECLARE @x INT = (SELECT COUNT(*) FROM dbo.Sesion);
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() = 229 SET @selectTablaDenegado = 1;
        END CATCH
        BEGIN TRY
            EXEC dbo.usp_crear_sesion_interno
                @idGrupo = @grupo, @nombre = N'D06 Probe', @fechaHoraInicio = '2026-07-22T13:00:00',
                @fechaHoraFin = '2026-07-22T14:00:00', @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioDocente,
                @procedenciaTemporal = N'UTC_V2', @idCorrelacionResultado = @iCorr OUTPUT,
                @mensajeUsuarioResultado = @iUsr OUTPUT, @mensajeTecnicoResultado = @iTec OUTPUT, @estadoResultado = @iEst OUTPUT;
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() = 229 SET @internoDenegado = 1;
        END CATCH
        BEGIN TRY
            EXEC dbo.usp_clasificar_procedencia_sesion
                @idSesion = @sesionV1, @ambiente = N'QA', @idManifiesto = N'X', @hashEvidencia = '0000000000000000000000000000000000000000000000000000000000000000',
                @fechaHoraInicioVerificada = '2026-07-21T00:30:00', @fechaHoraFinVerificada = '2026-07-21T02:00:00',
                @fechaHoraInicioUtc = '2026-07-21T00:30:00', @fechaHoraFinUtc = '2026-07-21T02:00:00',
                @idUsuarioAprobador = @usuarioDocente, @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioAdmin;
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() = 229 SET @clasificarDenegado = 1;
        END CATCH
        SET @lecturaV2 = (SELECT COUNT(*) FROM dbo.uv_sesion_v2 WHERE id = @sesionV2);
        DELETE FROM @rProbe;
        SET @corr = NEWID();
        INSERT INTO @rProbe EXEC dbo.usp_actualizar_sesion_v2
            @idSesion = @sesionV2, @nombre = N'D06 Via Runtime',
            @fechaHoraInicio = @inicioV2, @fechaHoraFin = @finV2,
            @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioDocente;
    REVERT;
    IF @dmlDenegado = 0 OR @selectTablaDenegado = 0 OR @internoDenegado = 0 OR @clasificarDenegado = 0 OR @lecturaV2 <> 1
        THROW 53031, 'TEST FAILED: UTC_D06_RUNTIME_PERMISSIONS el rol runtime tiene DML/SELECT de tabla o EXEC reservado.', 1;
    IF NOT EXISTS (SELECT 1 FROM @rProbe WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @sesionV2 AND nombre = N'D06 Via Runtime' AND procedenciaTemporal = N'UTC_V2'
                      AND fechaHoraInicio = @inicioV2)
        THROW 53032, 'TEST FAILED: UTC_D06_RUNTIME_PERMISSIONS el rol runtime no puede escribir via SP v2.', 1;
    PRINT 'TEST_PASS:UTC_D06_RUNTIME_PERMISSIONS';

    -- D06-07: clasificacion administrativa por ID y ambiente, con manifiesto y aprobador distinto.
    DECLARE @usuarioAprobador UNIQUEIDENTIFIER = 'D06D06D0-0000-0000-0000-000000000003';
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido,
        primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@usuarioAprobador, @tipoId, 906000003, N'Aprobador', N'Owner', N'Utc', N'Qa', N'd06.aprobador@test.local', 1, 1, N'HashBackend_QaD06_1234567890');
    INSERT INTO dbo.Administrador (id, usuario, institucion) VALUES ('D06D06D0-0000-0000-0000-000000000004', @usuarioAprobador, @institucion);
    IF EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'OPERACION' AND clave = 'AMBIENTE')
        UPDATE dbo.CatalogoParametro SET valor = N'QA-D06', estaActivo = 1 WHERE grupo = 'OPERACION' AND clave = 'AMBIENTE';
    ELSE
        INSERT INTO dbo.CatalogoParametro (grupo, clave, valor, tipoDato, valorDefecto) VALUES ('OPERACION', 'AMBIENTE', N'QA-D06', 'STRING', N'');

    DECLARE @hash CHAR(64) = '3f79bb7b435b05321651daefd374cdc681dc06faa65e374e38337b88ca046dea';
    DECLARE @histA UNIQUEIDENTIFIER, @histB UNIQUEIDENTIFIER;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_sesion @idGrupo = @grupo, @nombre = N'D06 Hist A',
        @fechaHoraInicio = '2026-03-02T13:00:00', @fechaHoraFin = '2026-03-02T15:00:00', @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioDocente;
    INSERT INTO #r EXEC dbo.usp_crear_sesion @idGrupo = @grupo, @nombre = N'D06 Hist B',
        @fechaHoraInicio = '2026-03-03T13:00:00', @fechaHoraFin = '2026-03-03T15:00:00', @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioDocente;
    SET @histA = (SELECT id FROM dbo.Sesion WHERE grupo = @grupo AND nombre = N'D06 Hist A');
    SET @histB = (SELECT id FROM dbo.Sesion WHERE grupo = @grupo AND nombre = N'D06 Hist B');

    -- rechazos: ambiente ajeno, ejecutor = aprobador, ejecutor docente, horas distintas al manifiesto
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_clasificar_procedencia_sesion @idSesion = @histA, @ambiente = N'PRODUCCION', @idManifiesto = N'MAN-D06-001',
        @hashEvidencia = @hash, @fechaHoraInicioVerificada = '2026-03-02T13:00:00', @fechaHoraFinVerificada = '2026-03-02T15:00:00',
        @fechaHoraInicioUtc = '2026-03-02T13:00:00', @fechaHoraFinUtc = '2026-03-02T15:00:00',
        @idUsuarioAprobador = @usuarioAprobador, @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioAdmin;
    INSERT INTO #r EXEC dbo.usp_clasificar_procedencia_sesion @idSesion = @histA, @ambiente = N'QA-D06', @idManifiesto = N'MAN-D06-001',
        @hashEvidencia = @hash, @fechaHoraInicioVerificada = '2026-03-02T13:00:00', @fechaHoraFinVerificada = '2026-03-02T15:00:00',
        @fechaHoraInicioUtc = '2026-03-02T13:00:00', @fechaHoraFinUtc = '2026-03-02T15:00:00',
        @idUsuarioAprobador = @usuarioAdmin, @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioAdmin;
    INSERT INTO #r EXEC dbo.usp_clasificar_procedencia_sesion @idSesion = @histA, @ambiente = N'QA-D06', @idManifiesto = N'MAN-D06-001',
        @hashEvidencia = @hash, @fechaHoraInicioVerificada = '2026-03-02T13:00:00', @fechaHoraFinVerificada = '2026-03-02T15:00:00',
        @fechaHoraInicioUtc = '2026-03-02T13:00:00', @fechaHoraFinUtc = '2026-03-02T15:00:00',
        @idUsuarioAprobador = @usuarioAprobador, @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioDocente;
    INSERT INTO #r EXEC dbo.usp_clasificar_procedencia_sesion @idSesion = @histA, @ambiente = N'QA-D06', @idManifiesto = N'MAN-D06-001',
        @hashEvidencia = @hash, @fechaHoraInicioVerificada = '2026-03-02T08:00:00', @fechaHoraFinVerificada = '2026-03-02T15:00:00',
        @fechaHoraInicioUtc = '2026-03-02T13:00:00', @fechaHoraFinUtc = '2026-03-02T15:00:00',
        @idUsuarioAprobador = @usuarioAprobador, @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioAdmin;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0) <> 4
       OR EXISTS (SELECT 1 FROM dbo.Sesion WHERE id IN (@histA, @histB) AND procedenciaTemporal IS NOT NULL)
       OR EXISTS (SELECT 1 FROM dbo.SesionProcedenciaClasificacion WHERE sesion IN (@histA, @histB))
        THROW 53033, 'TEST FAILED: UTC_D06_CLASSIFICATION_REJECTS una clasificacion invalida fue aceptada.', 1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE mensajeTecnicoResultado LIKE '%SES_006%')
        THROW 53034, 'TEST FAILED: UTC_D06_CLASSIFICATION_REJECTS horas fuera de manifiesto no reportaron SES_006.', 1;
    PRINT 'TEST_PASS:UTC_D06_CLASSIFICATION_REJECTS';

    -- aceptada: solo A cambia (verificacion + conversion individual 08:00 -05 -> 13:00Z ya almacenado); B sigue NULL.
    TRUNCATE TABLE #r;
    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_clasificar_procedencia_sesion @idSesion = @histA, @ambiente = N'QA-D06', @idManifiesto = N'MAN-D06-001',
        @hashEvidencia = @hash, @fechaHoraInicioVerificada = '2026-03-02T13:00:00', @fechaHoraFinVerificada = '2026-03-02T15:00:00',
        @fechaHoraInicioUtc = '2026-03-02T13:00:00', @fechaHoraFinUtc = '2026-03-02T15:00:00',
        @idUsuarioAprobador = @usuarioAprobador, @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_v2 WHERE id = @histA AND procedenciaTemporal = N'UTC_OWNER' AND fechaHoraInicio = '2026-03-02T13:00:00')
       OR NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @histB AND procedenciaTemporal IS NULL)
       OR (SELECT COUNT(*) FROM dbo.SesionProcedenciaClasificacion WHERE sesion = @histA AND ambiente = N'QA-D06'
             AND idManifiesto = N'MAN-D06-001' AND hashEvidencia = @hash AND usuarioAprobador = @usuarioAprobador
             AND usuarioEjecutor = @usuarioAdmin AND idCorrelacion = @corr AND procedenciaAnterior IS NULL) <> 1
        THROW 53035, 'TEST FAILED: UTC_D06_CLASSIFICATION_BY_ID clasificacion individual o bitacora incorrecta.', 1;
    -- reintento sobre fila ya clasificada: rechazado, sin segunda bitacora
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_clasificar_procedencia_sesion @idSesion = @histA, @ambiente = N'QA-D06', @idManifiesto = N'MAN-D06-002',
        @hashEvidencia = @hash, @fechaHoraInicioVerificada = '2026-03-02T13:00:00', @fechaHoraFinVerificada = '2026-03-02T15:00:00',
        @fechaHoraInicioUtc = '2026-03-02T13:00:00', @fechaHoraFinUtc = '2026-03-02T15:00:00',
        @idUsuarioAprobador = @usuarioAprobador, @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0)
       OR (SELECT COUNT(*) FROM dbo.SesionProcedenciaClasificacion WHERE sesion = @histA) <> 1
        THROW 53036, 'TEST FAILED: UTC_D06_CLASSIFICATION_BY_ID reclasificacion no fue rechazada.', 1;
    PRINT 'TEST_PASS:UTC_D06_CLASSIFICATION_BY_ID';

    -- D06-11: DetalleAsistencia es SNAPSHOT de las horas al registrar asistencia; editar la sesion no lo altera.
    DECLARE @eg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstudianteGrupo WHERE grupo = @grupo);
    DECLARE @razon UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.RazonCausa);
    IF @eg IS NULL OR @razon IS NULL
        THROW 53037, 'TEST FAILED: UTC_D06_DETALLE_SNAPSHOT fixture EstudianteGrupo/RazonCausa ausente.', 1;
    DECLARE @asis UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@asis, @eg, @sesionV2);
    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
    VALUES (NEWID(), 990000 + ABS(CHECKSUM(NEWID()) % 9999), @asis, 1, @razon, @inicioV2, @finV2);
    TRUNCATE TABLE #r;
    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_sesion_v2
        @idSesion = @sesionV2, @nombre = N'D06 Movida',
        @fechaHoraInicio = '2026-07-17T01:00:00', @fechaHoraFin = '2026-07-17T03:00:00',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioDocente;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia WHERE asistencia = @asis AND fechaHoraInicio = @inicioV2 AND fechaHoraFin = @finV2)
        THROW 53038, 'TEST FAILED: UTC_D06_DETALLE_SNAPSHOT editar la sesion altero el snapshot de asistencia.', 1;
    PRINT 'TEST_PASS:UTC_D06_DETALLE_SNAPSHOT';

    -- D06-05: el generador marca UTC_GENERADOR solo con conversion real por fecha en la zona institucional
    -- (Berlin CEST +02 / CET +01) y aborta sin escrituras ante una hora local inexistente (salto DST).
    -- Primitiva de conversion del motor (fechas fijas, independiente del dia de ejecucion):
    IF CAST(CAST('2026-10-18T02:30:00' AS DATETIME2) AT TIME ZONE 'W. Europe Standard Time' AT TIME ZONE 'UTC' AS DATETIME2) <> '2026-10-18T00:30:00'
       OR CAST(CAST('2026-11-01T02:30:00' AS DATETIME2) AT TIME ZONE 'W. Europe Standard Time' AT TIME ZONE 'UTC' AS DATETIME2) <> '2026-11-01T01:30:00'
       OR CAST(CAST('2026-03-29T02:30:00' AS DATETIME2) AT TIME ZONE 'W. Europe Standard Time' AS DATETIME2) = '2026-03-29T02:30:00'
        THROW 53044, 'TEST FAILED: UTC_D06_GENERATOR_MARK tzdata del motor no resuelve CEST/CET/gap como se espera.', 1;

    UPDATE dbo.CatalogoParametro SET valor = N'W. Europe Standard Time'
    WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER';
    DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'W. Europe Standard Time' AS DATE);
    DECLARE @asig UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_asignatura);
    DECLARE @domingo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Dia WHERE codigo = 'DO');
    DECLARE @perGen UNIQUEIDENTIFIER = NEWID(), @grpGen UNIQUEIDENTIFIER = NEWID();
    DECLARE @perGap UNIQUEIDENTIFIER = NEWID(), @grpGap UNIQUEIDENTIFIER = NEWID();
    -- Gap: un periodo de 400 dias con clase dominical 02:30 contiene siempre el ultimo domingo de marzo.
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@perGen, @institucion, N'Periodo D06 Berlin', 600000 + ABS(CHECKSUM(NEWID()) % 99999), @hoy, DATEADD(DAY, 6, @hoy), YEAR(@hoy)),
           (@perGap, @institucion, N'Periodo D06 Gap', 700000 + ABS(CHECKSUM(NEWID()) % 99999), @hoy, DATEADD(DAY, 400, @hoy), YEAR(@hoy));
    INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes,
        cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@grpGen, @asig, @perGen, 600000 + ABS(CHECKSUM(NEWID()) % 99999), N'Grupo D06 Berlin', 20, 0, 0, 0, @docente),
           (@grpGap, @asig, @perGap, 700000 + ABS(CHECKSUM(NEWID()) % 99999), N'Grupo D06 Gap', 20, 0, 0, 0, @docente);
    INSERT dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    SELECT NEWID(), @grpGen, id, '02:30', '03:15' FROM dbo.Dia;
    INSERT dbo.Horario (id, grupo, dia, horaInicio, horaFin) VALUES (NEWID(), @grpGap, @domingo, '02:30', '03:15');

    TRUNCATE TABLE #r;
    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_generar_sesiones_grupo @idGrupo = @grpGap, @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioDocente;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE '%SES_005%')
       OR EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @grpGap)
        THROW 53039, 'TEST FAILED: UTC_D06_GENERATOR_DST_GAP hora local inexistente (Berlin, ultimo domingo de marzo 02:30) no aborto sin escrituras.', 1;
    PRINT 'TEST_PASS:UTC_D06_GENERATOR_DST_GAP';

    -- Semana actual en Berlin, clase diaria 02:30: oraculo calculado fila a fila con la zona; si la semana
    -- contuviera el salto DST, el oraculo es SES_005 sin escrituras.
    DECLARE @semanaConGap BIT = CASE WHEN EXISTS (
        SELECT 1 FROM (VALUES (0),(1),(2),(3),(4),(5),(6)) n(d)
        CROSS APPLY (SELECT local = CAST(CONCAT(CONVERT(CHAR(10), DATEADD(DAY, n.d, @hoy), 23), 'T02:30:00') AS DATETIME2)) x
        WHERE CAST(x.local AT TIME ZONE 'W. Europe Standard Time' AS DATETIME2) <> x.local
    ) THEN 1 ELSE 0 END;
    TRUNCATE TABLE #r;
    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_generar_sesiones_grupo @idGrupo = @grpGen, @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioDocente;
    IF @semanaConGap = 1
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE '%SES_005%')
           OR EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @grpGen)
            THROW 53040, 'TEST FAILED: UTC_D06_GENERATOR_MARK semana con salto DST no aborto.', 1;
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @grpGen) <> 7
       OR EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @grpGen AND (procedenciaTemporal IS NULL OR procedenciaTemporal <> N'UTC_GENERADOR'))
       OR EXISTS (
            SELECT 1 FROM dbo.Sesion s
            CROSS APPLY (SELECT localEsperada = CAST(s.fechaHoraInicio AT TIME ZONE 'UTC' AT TIME ZONE 'W. Europe Standard Time' AS DATETIME2)) l
            WHERE s.grupo = @grpGen
              AND (CAST(l.localEsperada AS TIME) <> '02:30' OR DATEDIFF(MINUTE, s.fechaHoraInicio, l.localEsperada) NOT IN (60, 120)))
        THROW 53040, 'TEST FAILED: UTC_D06_GENERATOR_MARK generador sin UTC_GENERADOR u offset Berlin incorrecto.', 1;
    PRINT CONCAT('TEST_INFO:UTC_D06_GENERATOR_WEEK_HAS_DST_GAP=', @semanaConGap);
    PRINT 'TEST_PASS:UTC_D06_GENERATOR_MARK';
END TRY
BEGIN CATCH
    IF USER_NAME() = N'utc_d06_runtime_probe' REVERT;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;

IF DATABASE_PRINCIPAL_ID(N'utc_d06_runtime_probe') IS NOT NULL
    THROW 53041, 'TEST FAILED: UTC_D06 dejo el usuario probe creado.', 1;
IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE nombre LIKE N'D06 %')
    THROW 53042, 'TEST FAILED: UTC_D06 dejo sesiones de prueba.', 1;
IF (SELECT valor FROM dbo.CatalogoParametro WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER') <> N'SA Pacific Standard Time'
    THROW 53043, 'TEST FAILED: UTC_D06 no restauro la zona institucional.', 1;
DROP TABLE #r;
GO

-- Bloque 2 (autocommit aislado). D06-06/D06-10: un UPDATE directo 08:00 -> 18:00 que conserva la marca
-- confirmada (sin reafirmarla) se rechaza en el trigger y no deja horas ni marca parciales.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @grupo UNIQUEIDENTIFIER, @usuarioDocente UNIQUEIDENTIFIER;
SELECT TOP 1 @grupo = g.id, @usuarioDocente = di.idUsuario
FROM dbo.uv_grupo g JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
WHERE g.grupoEstaHablitado = 1 ORDER BY g.cuposDisponibles DESC;

CREATE TABLE #r2 (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
INSERT INTO #r2 EXEC dbo.usp_crear_sesion_v2 @idGrupo = @grupo, @nombre = N'D06 Directo',
    @fechaHoraInicio = '2026-09-01T08:00:00', @fechaHoraFin = '2026-09-01T09:00:00',
    @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioDocente;
DECLARE @sesion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Sesion WHERE grupo = @grupo AND nombre = N'D06 Directo');
DECLARE @falla NVARCHAR(400) = NULL;
BEGIN TRY
    IF @sesion IS NULL SET @falla = N'fixture v2 no creada';
    IF @falla IS NULL
    BEGIN
        DECLARE @rechazado BIT = 0;
        BEGIN TRY
            UPDATE dbo.Sesion
            SET fechaHoraInicio = '2026-09-01T18:00:00', fechaHoraFin = '2026-09-01T19:00:00'
            WHERE id = @sesion;
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() = 52110 SET @rechazado = 1;
        END CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF @rechazado = 0
            SET @falla = N'UPDATE directo de horas sin reafirmar marca no fue rechazado';
        ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @sesion AND procedenciaTemporal = N'UTC_V2'
                            AND fechaHoraInicio = '2026-09-01T08:00:00' AND fechaHoraFin = '2026-09-01T09:00:00')
            SET @falla = N'UPDATE rechazado dejo horas o marca parciales';
    END
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @falla = CONCAT(N'error inesperado ', ERROR_NUMBER(), N': ', ERROR_MESSAGE());
END CATCH;
DELETE FROM dbo.Sesion WHERE id = @sesion;
DROP TABLE #r2;
IF @falla IS NOT NULL
BEGIN
    DECLARE @msg NVARCHAR(2048) = CONCAT(N'TEST FAILED: UTC_D06_DIRECT_UPDATE_REJECTED ', @falla);
    THROW 53050, @msg, 1;
END
PRINT 'TEST_PASS:UTC_D06_DIRECT_UPDATE_REJECTED';

IF @@TRANCOUNT <> 0 THROW 53051, 'TEST FAILED: test_utc_d06_procedencia_temporal dejo transacciones abiertas.', 1;
PRINT 'TEST END: test_utc_d06_procedencia_temporal';
GO
