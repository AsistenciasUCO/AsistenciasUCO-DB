USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- 14_culm001_a_correcciones_fase1_down.sql: rollback de 14_culm001_a_correcciones_fase1_up.sql (CONTRACT §8.2).
-- Orden (bloqueante 2 de REVIEW-3): (1) DROP de los SP nuevos; (2) internos de sesion y resolver del decano de develop
-- (65a4998); (3) uv_usuario_perfil y uv_decano de develop, SIN la referencia a Decano.estado; (4) guardia: ningun modulo
-- referencia Decano.estado (THROW 53320); (5) solo entonces DROP de DF_Decano_estado y de la columna; (6) DELETE de los
-- parametros y mensajes de A.2. No borra datos de negocio: un reclamo retirado (X) vuelve a pendiente (P).
-- Los parametros MATRICULA/* son de A.1 y los quita el down de la migracion 13. Idempotente.
-- ============================================================================

-- D14-1: SP nuevos (sus GRANT y el DENY caen con el DROP).
IF OBJECT_ID(N'dbo.usp_validar_solape_sesion_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_validar_solape_sesion_interno];
GO
IF OBJECT_ID(N'dbo.usp_consultar_directorio_estudiantes_paginado', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_directorio_estudiantes_paginado];
GO
IF OBJECT_ID(N'dbo.usp_consultar_estudiantes_grupo_ambito_paginado', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_estudiantes_grupo_ambito_paginado];
GO
IF OBJECT_ID(N'dbo.usp_consultar_asistencias_grupo_ambito_paginado', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_asistencias_grupo_ambito_paginado];
GO
IF OBJECT_ID(N'dbo.usp_consultar_materias_estudiante', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_materias_estudiante];
GO
IF OBJECT_ID(N'dbo.usp_consultar_horario_estudiante', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_horario_estudiante];
GO
IF OBJECT_ID(N'dbo.usp_retirar_solicitud_revision_asistencia', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_retirar_solicitud_revision_asistencia];
GO
IF OBJECT_ID(N'dbo.usp_cambiar_estado_decano', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_cambiar_estado_decano];
GO
IF OBJECT_ID(N'dbo.usp_buscar_estudiante_por_documento_grupo', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_buscar_estudiante_por_documento_grupo];
GO

-- D14-2: internos de develop.
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- UTC-D06-POST-FREEZE: nucleo unico de creacion de sesion compartido por
--   * usp_crear_sesion    (v1, firma congelada DB-GP-001C) -> @procedenciaTemporal = NULL
--   * usp_crear_sesion_v2 (v2, instantes UTC confirmados)   -> @procedenciaTemporal = 'UTC_V2'
-- Las horas y la marca se escriben en el MISMO INSERT. Este SP no es publico: el rol runtime
-- tiene DENY EXECUTE directo y solo se alcanza por encadenamiento de propiedad desde los wrappers.
-- UTC_GENERADOR y UTC_OWNER NO se aceptan por esta via (generador y clasificacion propios).
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_sesion_interno]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(50),
    @fechaHoraInicio         DATETIME2,
    @fechaHoraFin            DATETIME2,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @procedenciaTemporal     NVARCHAR(24),
    @idCorrelacionResultado  UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto            NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idNuevoSesion   UNIQUEIDENTIFIER = NEWID();
    DECLARE @numeroSiguiente INT = 1;
    DECLARE @codigoSesion    NVARCHAR(50);

    -- Ownership transaccional (propia o savepoint bajo transacción externa)
    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET @idCorrelacionResultado = @idCorrelacionDefecto;

    BEGIN TRY
        -- PASOS 0-1.6: procedencia, correlacion y seguridad antes de consultar el grupo.
        EXEC dbo.usp_validar_sesion_operacion_interno
            @idCorrelacion = @idCorrelacion,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @procedenciaTemporal = @procedenciaTemporal,
            @fechaHoraInicio = @fechaHoraInicio,
            @fechaHoraFin = @fechaHoraFin,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @faseValidacion = 0;

        -- PASO 2: Validación de existencia del grupo académico
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.1: Titularidad del docente ejecutor sobre el grupo.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idGrupoDefecto,
                @tipoEntidadPadre = 'GRUPO',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.5: conservar la prioridad contractual de entidad antes de fechas.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_operacion_interno
                @idCorrelacion = @idCorrelacion,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @procedenciaTemporal = @procedenciaTemporal,
                @fechaHoraInicio = @fechaHoraInicio,
                @fechaHoraFin = @fechaHoraFin,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @faseValidacion = 2;
        END

        -- PASO 3: Cálculo transaccional del correlativo de sesión e inserción
        -- (ownership transaccional: propia o savepoint bajo transacción externa)
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION usp_crear_sesion;
                SET @savepointCreado = 1;
            END

            SELECT @numeroSiguiente = COALESCE(MAX(numero), 0) + 1
            FROM [dbo].[Sesion] WITH (UPDLOCK, HOLDLOCK)
            WHERE grupo = @idGrupoDefecto;

            SET @codigoSesion = CASE
                WHEN @numeroSiguiente < 100 THEN CONCAT('SES-', RIGHT('0' + CAST(@numeroSiguiente AS VARCHAR(10)), 2))
                ELSE CONCAT('SES-', CAST(@numeroSiguiente AS VARCHAR(10)))
            END;

            -- Horas y procedencia en la MISMA sentencia (UTC-D06).
            INSERT INTO dbo.Sesion (
                id, nombre, numero, codigo, numeroSemana, grupo,
                fechaHoraInicio, fechaHoraFin, procedenciaTemporal
            )
            VALUES (
                @idNuevoSesion,
                CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE CONCAT('Sesión #', @numeroSiguiente) END,
                @numeroSiguiente,
                @codigoSesion,
                @numeroSiguiente,
                @idGrupoDefecto,
                @fechaHoraInicio,
                @fechaHoraFin,
                @procedenciaTemporal
            );

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() <> 0
                    ROLLBACK TRANSACTION;
            END

            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Sesion', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- BLOQUE CATCH: Captura centralizada de excepciones y reversión respetando ownership transaccional
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();

        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION usp_crear_sesion;
        END

        -- Transacción externa condenada (XACT_STATE = -1) que no nos pertenece: propagar al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- UTC-D06-POST-FREEZE: nucleo unico de actualizacion de sesion compartido por
--   * usp_actualizar_sesion    (v1, firma congelada DB-GP-001C) -> @procedenciaTemporal = NULL
--   * usp_actualizar_sesion_v2 (v2, instantes UTC confirmados)   -> @procedenciaTemporal = 'UTC_V2'
-- PUT completo de horas: horas y marca se escriben en el MISMO UPDATE. Una actualizacion v1 de una
-- sesion confirmada la vuelve INDETERMINADA aunque el valor temporal sea identico, porque v1 no
-- declara zona. Solo NULL o UTC_V2 se aceptan por esta via.
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_sesion_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(50),
    @fechaHoraInicio         DATETIME2,
    @fechaHoraFin            DATETIME2,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @procedenciaTemporal     NVARCHAR(24),
    @idCorrelacionResultado  UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto            NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idGrupoSesion UNIQUEIDENTIFIER;

BEGIN
    SET NOCOUNT ON;
    SET @idCorrelacionResultado = @idCorrelacionDefecto;

    BEGIN TRY
        -- PASOS 0-1.6: procedencia, correlacion y seguridad antes de consultar la sesión.
        EXEC dbo.usp_validar_sesion_operacion_interno
            @idCorrelacion = @idCorrelacion,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @procedenciaTemporal = @procedenciaTemporal,
            @fechaHoraInicio = @fechaHoraInicio,
            @fechaHoraFin = @fechaHoraFin,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @faseValidacion = 0;

        -- PASO 2: Validar existencia de la sesión con código semántico SES_001
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @idGrupoSesion = grupo
            FROM [dbo].[Sesion]
            WHERE id = @idSesionDefecto;

            IF @idGrupoSesion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_001',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Titularidad del docente ejecutor sobre la sesión.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idSesionDefecto,
                @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: conservar la prioridad contractual de entidad antes de fechas.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_operacion_interno
                @idCorrelacion = @idCorrelacion,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @procedenciaTemporal = @procedenciaTemporal,
                @fechaHoraInicio = @fechaHoraInicio,
                @fechaHoraFin = @fechaHoraFin,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @faseValidacion = 2;
        END

        IF @estadoResultado = 1
        BEGIN
            -- Horas y procedencia en la MISMA sentencia (UTC-D06).
            UPDATE dbo.Sesion
            SET nombre = CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE nombre END,
                fechaHoraInicio = @fechaHoraInicio,
                fechaHoraFin = @fechaHoraFin,
                procedenciaTemporal = @procedenciaTemporal
            WHERE id = @idSesionDefecto;

            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Sesion', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_resolver_facultad_decano_interno]
-- HU102/HU103/HU106/HU144: valida correlacion y ejecutor y resuelve la facultad que dirige el decano (ambito).
-- Falla con THROW (DBCODE=...): CORR_001, VAL_001 (ejecutor nulo), KPI_003 (no es decano de una facultad), KPI_002 (umbral ausente).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_facultad_decano_interno]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @validarUmbrales   BIT = 1,
    @idFacultad        UNIQUEIDENTIFIER OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @msgP1 NVARCHAR(500);
    SET @idFacultad = NULL;
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0 THROW 51000, @mensajeTecnicoResultado, 1;
    IF @idUsuarioEjecutor IS NULL OR @idUsuarioEjecutor = @guidVacio
    BEGIN
        SET @msgP1 = CAST(N'UsuarioEjecutor' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT TOP 1 @idFacultad = f.id
    FROM dbo.uv_facultad f
    INNER JOIN dbo.uv_decano_identidad di ON di.id = f.idDecano
    WHERE di.idUsuario = @idUsuarioEjecutor
    ORDER BY f.estaActivaFacultad DESC, f.nombreFacultad ASC, f.id ASC;

    IF @idFacultad IS NULL
    BEGIN
        SET @msgP1 = CAST(CONVERT(NVARCHAR(36), @idUsuarioEjecutor) AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'KPI_003',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    IF @validarUmbrales = 1 AND dbo.ufn_clasificar_permanencia(0, N'A') IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'KPI_002',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END
END;
GO

-- D14-3: vistas de develop (sin Decano.estado), ANTES de borrar la columna.
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    VIEW [dbo].[uv_decano]
AS
SELECT		di.id,
			di.idUsuario,
			di.numeroIdentificacion,
			di.nombreCompleto,
			di.estaActivoUsuario,			
			idInstitucion = f.idInstitucion,
			nombreInstitucion = f.nombreInstitucion,
			idFacultad = f.id,
			nombreFacultad = f.nombreFacultad,
			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,
			estaActivoDecano = IIF(di.estaActivoUsuario = 1 AND (f.id IS NULL OR f.estaActivaFacultad = 1), 1, 0),
			estaActivoTextoDecano = IIF(di.estaActivoUsuario = 1 AND (f.id IS NULL OR f.estaActivaFacultad = 1), 'SI', 'NO')

FROM		uv_decano_identidad di
LEFT JOIN   uv_facultad f 
ON			di.id = f.idDecano
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM uv_perfil WHERE codigo = 'DE') p
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_usuario_perfil]
AS
SELECT		idUsuario = a.usuario,
			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,
			estado = IIF(u.estado = 1, 1, 0)
FROM		Administrador a
INNER JOIN	Usuario u
ON			a.usuario = u.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM Perfil WHERE codigo = 'AD') p

UNION

SELECT		idUsuario = d.usuario,
			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,
			estado = IIF(u.estado = 1, 1, 0)
FROM		Decano d
INNER JOIN	Usuario u
ON			d.usuario = u.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM Perfil WHERE codigo = 'DE') p

UNION

SELECT		idUsuario = c.usuario,
			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,
			estado = IIF(u.estado = 1, 1, 0)
FROM		Coordinador c
INNER JOIN	Usuario u
ON			c.usuario = u.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM Perfil WHERE codigo = 'CD') p
-- HU121/HU122 (D1): un rol de coordinador inactivo deja de figurar como perfil (RBAC y roles activos)
WHERE		c.estado = 1

UNION

SELECT		idUsuario = d.usuario,
			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,
			estado = IIF(u.estado = 1, 1, 0)
FROM		Docente d
INNER JOIN	Usuario u
ON			d.usuario = u.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM Perfil WHERE codigo = 'DO') p

UNION

SELECT		idUsuario = e.usuario,
			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,
			estado = IIF(u.estado = 1, 1, 0)
FROM		Estudiante e
INNER JOIN	Usuario u
ON			e.usuario = u.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM Perfil WHERE codigo = 'ES') p
GO

-- D14-4 y D14-5: guardia y borrado de la columna.
USE [gestionasistenciadb];
GO
IF COL_LENGTH('dbo.Decano', 'estado') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM sys.sql_expression_dependencies d
               WHERE d.referenced_id = OBJECT_ID(N'dbo.Decano')
                 AND (d.referenced_minor_id = COLUMNPROPERTY(OBJECT_ID(N'dbo.Decano'), 'estado', 'ColumnId')
                      OR OBJECT_DEFINITION(d.referencing_id) LIKE N'%d.estado%'))
        THROW 53320, 'CULM001_A: hay modulos que referencian Decano.estado; restaurarlos antes de borrar la columna.', 1;
    IF OBJECT_ID(N'dbo.DF_Decano_estado', N'D') IS NOT NULL
        ALTER TABLE dbo.Decano DROP CONSTRAINT DF_Decano_estado;
    ALTER TABLE dbo.Decano DROP COLUMN estado;
END
GO

-- D14-6: datos de A.2 (reclamos X vuelven a P; parametros y mensajes de A.2).
DECLARE @retirados INT;
UPDATE r SET estado = p.id
FROM dbo.SolicitudRevisionAsistencia r
INNER JOIN dbo.Estado x ON x.id = r.estado AND x.codigo = 'X'
CROSS JOIN (SELECT id FROM dbo.Estado WHERE codigo = 'P') p;
SET @retirados = @@ROWCOUNT;
PRINT CONCAT('CULM001_A_DOWN14 reclamos retirados devueltos a pendiente=', @retirados);
DELETE FROM dbo.CatalogoParametro
WHERE (grupo = 'ARCHIVOS' AND clave = 'LIMITE_SUBIDAS_POR_MINUTO')
   OR (grupo = 'ASISTENCIA_QR' AND clave IN ('LIMITE_IP_POR_MINUTO', 'LIMITE_ESTUDIANTE_POR_MINUTO'))
   OR (grupo = 'RECLAMO' AND clave IN ('ESTADO_PENDIENTE', 'ESTADO_RETIRADO'));
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('SES_017', 'REV_006', 'REV_007', 'REV_008', 'DEC_002', 'DEC_003');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('SES_017', 'REV_006', 'REV_007', 'REV_008', 'DEC_002', 'DEC_003');
PRINT CONCAT('CULM001_A_DOWN14 Decano.estado=', IIF(COL_LENGTH('dbo.Decano', 'estado') IS NULL, 'retirada', 'PRESENTE'));
GO
