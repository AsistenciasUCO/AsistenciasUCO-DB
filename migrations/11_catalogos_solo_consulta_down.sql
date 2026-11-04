-- Rollback de 11_catalogos_solo_consulta_up.sql: restaura los SP de escritura tal como estaban en develop (25f79b2)
-- y sus GRANT EXECUTE.
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_guardar_tipo_identificacion_interno (HU153, 2026-11-04)
--
-- Nucleo de escritura del catalogo de tipos de documento: con @idTipoIdentificacion NULL inserta (codigo y nombre ya
-- validados por la fachada); con id solo actualiza el NOMBRE (el codigo es inmutable: decision de John, sin estado).
-- Transaccion propia si no hay una abierta; si la hay, savepoint (REC4 #4: sin XACT_ABORT para no condenar la
-- transaccion del llamador). Expone el triplete OUTPUT.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_guardar_tipo_identificacion_interno]
(
    @idTipoIdentificacion    UNIQUEIDENTIFIER,
    @codigo                  NVARCHAR(5),
    @nombre                  NVARCHAR(50),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @savepointCreado      BIT = 0;

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Transaccion propia o savepoint
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sv_guardar_tipo_identificacion;
            SET @savepointCreado = 1;
        END

        -- PASO 2: Alta o cambio de nombre
        IF @idTipoIdentificacion IS NULL
        BEGIN
            INSERT INTO dbo.TipoIdentificacion (id, tipoIdentificacion, nombre)
            VALUES (NEWID(), @codigo, @nombre);

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = N'Tipo de documento',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        END
        ELSE
        BEGIN
            UPDATE dbo.TipoIdentificacion SET nombre = @nombre WHERE id = @idTipoIdentificacion;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_005',
                @p_param1 = N'Tipo de documento',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        END
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));

        IF @transaccionPropia = 1
        BEGIN
            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sv_guardar_tipo_identificacion;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_guardar_tipo_identificacion (HU153 administracion del catalogo de tipos de documento)
--
-- Solo ADMINISTRADOR (SEC_001). Decision de John (2026-11-04): crear y editar el nombre; sin estado (no se inactiva) y
-- sin DDL.
--   * Alta (@idTipoIdentificacion NULL): codigo obligatorio de 1 a 5 letras A-Z (se guarda en mayusculas: CC, TI, PEP)
--     y unico (GEN_003); nombre de 3 a 50 caracteres y unico sin distinguir mayusculas (GEN_003).
--   * Edicion (con id): el tipo debe existir (GEN_001); solo cambia el nombre (mismas reglas). El codigo es inmutable
--     porque forma parte de la identificacion de los usuarios; si llega, se ignora.
-- Salida canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado).
-- La escritura y su transaccion viven en usp_guardar_tipo_identificacion_interno.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_guardar_tipo_identificacion]
(
    @idTipoIdentificacion  UNIQUEIDENTIFIER = NULL,
    @codigo                NVARCHAR(20)     = NULL,
    @nombre                NVARCHAR(100)    = NULL,
    @idCorrelacion         UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor     UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGuidVacio              UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idTipoDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idTipoIdentificacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @esAlta                   BIT;
    DECLARE @idTipoEscritura          UNIQUEIDENTIFIER;
    DECLARE @codigoDef                NVARCHAR(20)     = UPPER(TRIM(@codigo));
    DECLARE @nombreDef                NVARCHAR(100)    = TRIM(@nombre);
    DECLARE @parametroInvalido        NVARCHAR(100);
    DECLARE @mensajeUsuarioResultado  NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado  NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado          BIT = 1;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SET @esAlta = IIF(@idTipoDefecto IS NULL OR @idTipoDefecto = @idGuidVacio, 1, 0);
        SET @idTipoEscritura = IIF(@esAlta = 1, NULL, @idTipoDefecto);

        -- PASO 1: Correlacion, ejecutor (GEN_002) y perfil ADMINISTRADOR (SEC_001)
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@idUsuarioEjecutorDefecto IS NULL OR @idUsuarioEjecutorDefecto = @idGuidVacio)
        BEGIN
            SET @parametroInvalido = N'idUsuarioEjecutor';
        END

        IF @estadoResultado = 1 AND @parametroInvalido IS NULL
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Formato del codigo (solo en el alta) y del nombre (GEN_002)
        IF @estadoResultado = 1 AND @parametroInvalido IS NULL AND @esAlta = 1
           AND (@codigoDef IS NULL OR LEN(@codigoDef) < 1 OR LEN(@codigoDef) > 5 OR @codigoDef LIKE '%[^A-Z]%')
        BEGIN
            SET @parametroInvalido = N'código del tipo de documento (1 a 5 letras)';
        END

        IF @estadoResultado = 1 AND @parametroInvalido IS NULL AND (@nombreDef IS NULL OR LEN(@nombreDef) < 3 OR LEN(@nombreDef) > 50)
        BEGIN
            SET @parametroInvalido = N'nombre del tipo de documento (3 a 50 caracteres)';
        END

        IF @estadoResultado = 1 AND @parametroInvalido IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = @parametroInvalido,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: El tipo existe en la edicion (GEN_001)
        IF @estadoResultado = 1 AND @esAlta = 0
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_identificacion t WHERE t.id = @idTipoDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = N'tipo de documento',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: Unicidad del codigo (alta) y del nombre (excluyendo el propio) (GEN_003)
        IF @estadoResultado = 1
           AND ((@esAlta = 1 AND EXISTS (SELECT 1 FROM dbo.uv_tipo_identificacion t WHERE UPPER(t.TipoIdentificacion) = @codigoDef))
                OR EXISTS (SELECT 1 FROM dbo.uv_tipo_identificacion t
                           WHERE LOWER(t.nombre) = LOWER(@nombreDef) AND (@esAlta = 1 OR t.id <> @idTipoDefecto)))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_003',
                @p_param1 = N'tipo de documento',
                @p_param2 = N'código o nombre',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: Escritura (usp_guardar_tipo_identificacion_interno)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_guardar_tipo_identificacion_interno
                @idTipoIdentificacion = @idTipoEscritura,
                @codigo = @codigoDef,
                @nombre = @nombreDef,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_crear_area_interno]
-- Historias de Usuario: HU151 / HU152
-- Ambito: operacion atomica de persistencia. Inserta Area de Conocimiento activo.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_area_interno]
(
    @codigo                  NVARCHAR(3),
    @nombre                  NVARCHAR(50),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sv_crear_area;
                SET @savepointCreado = 1;
            END

            INSERT INTO dbo.Area (id, nombre, codigo, estado)
            VALUES (NEWID(), @nombre, @codigo, 1);

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Area de Conocimiento',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);

            IF @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
            END
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sv_crear_area;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_crear_area]
-- Historias de Usuario: HU151 / HU152
-- Ambito: Administrador Institucional. Alta de Area de Conocimiento.
-- Salida Canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_area]
(
    @codigo            NVARCHAR(20) = NULL,
    @nombre            NVARCHAR(150) = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoDef                NVARCHAR(20)     = UPPER(TRIM(@codigo));
    DECLARE @nombreDef                NVARCHAR(150)    = TRIM(@nombre);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 AND (@codigoDef IS NULL OR LEN(@codigoDef) <> 3 OR @codigoDef LIKE '%[^A-Z0-9]%')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Codigo de Area de Conocimiento',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Formato invalido (3 caracteres A-Z/0-9). Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@nombreDef IS NULL OR LEN(@nombreDef) < 3 OR LEN(@nombreDef) > 50)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Nombre de Area de Conocimiento',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Longitud invalida (3-50). Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.uv_area WHERE codigo = @codigoDef)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ARE_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Conflicto de unicidad para codigo. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.uv_area WHERE LOWER(nombre) = LOWER(@nombreDef))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ARE_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Conflicto de unicidad para nombre. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_crear_area_interno
                @codigo = @codigoDef,
                @nombre = @nombreDef,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_actualizar_area_interno]
-- Historias de Usuario: HU151 / HU152
-- Ambito: operacion atomica de persistencia. Actualiza el nombre de Area de Conocimiento.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_area_interno]
(
    @id                      UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(50),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sv_actualizar_area;
                SET @savepointCreado = 1;
            END

            UPDATE dbo.Area
            SET nombre = @nombre
            WHERE id = @id;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_005',
                @p_param1 = 'Area de Conocimiento',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);

            IF @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
            END
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sv_actualizar_area;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_actualizar_area]
-- Historias de Usuario: HU151 / HU152
-- Ambito: Administrador Institucional. Modifica el nombre de Area de Conocimiento; el codigo es inmutable.
-- Salida Canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_area]
(
    @id                UNIQUEIDENTIFIER = NULL,
    @nombre            NVARCHAR(150)    = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDef                NVARCHAR(150)    = TRIM(@nombre);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar perfil del ejecutor (RBAC ADMINISTRADOR)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Validacion de negocio (ARE_001)
        IF @estadoResultado = 1 AND (@id IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_area WHERE id = @id))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ARE_001',
                @p_param1 = @id,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: Validacion de negocio (GEN_002)
        IF @estadoResultado = 1 AND (@nombreDef IS NULL OR LEN(@nombreDef) < 3 OR LEN(@nombreDef) > 50)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Nombre de Area de Conocimiento',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Longitud invalida (3-50). Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: Validacion de negocio (ARE_002)
        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.uv_area WHERE LOWER(nombre) = LOWER(@nombreDef) AND id <> @id)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ARE_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Conflicto de unicidad para nombre. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 7: Ejecutar usp_actualizar_area_interno
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_actualizar_area_interno
                @id = @id,
                @nombre = @nombreDef,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_cambiar_estado_area_interno]
-- Historias de Usuario: HU151 / HU152
-- Ambito: operacion atomica de persistencia. Fija el estado de Area de Conocimiento.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cambiar_estado_area_interno]
(
    @id                      UNIQUEIDENTIFIER,
    @estaActiva              BIT,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sv_cambiar_estado_area;
                SET @savepointCreado = 1;
            END

            UPDATE dbo.Area
            SET estado = @estaActiva
            WHERE id = @id;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_005',
                @p_param1 = 'Area de Conocimiento',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);

            IF @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
            END
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sv_cambiar_estado_area;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_cambiar_estado_area]
-- Historias de Usuario: HU151 / HU152
-- Ambito: Administrador Institucional. Fija el estado deseado de Area de Conocimiento (idempotente, sin cascada).
-- Salida Canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cambiar_estado_area]
(
    @id                UNIQUEIDENTIFIER = NULL,
    @estaActiva        BIT              = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar perfil del ejecutor (RBAC ADMINISTRADOR)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Validacion de negocio (ARE_001)
        IF @estadoResultado = 1 AND (@id IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_area WHERE id = @id))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ARE_001',
                @p_param1 = @id,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: Validacion de negocio (GEN_002)
        IF @estadoResultado = 1 AND @estaActiva IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Estado deseado de Area de Conocimiento',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: Ejecutar usp_cambiar_estado_area_interno
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_cambiar_estado_area_interno
                @id = @id,
                @estaActiva = @estaActiva,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_crear_tipo_programa_interno]
-- Historias de Usuario: HU154
-- Ambito: operacion atomica de persistencia. Inserta Tipo de Programa activo.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_tipo_programa_interno]
(
    @codigo                  NVARCHAR(3),
    @nombre                  NVARCHAR(50),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sv_crear_tipo_programa;
                SET @savepointCreado = 1;
            END

            INSERT INTO dbo.TipoPrograma (id, nombre, codigo, estado)
            VALUES (NEWID(), @nombre, @codigo, 1);

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Tipo de Programa',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);

            IF @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
            END
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sv_crear_tipo_programa;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_crear_tipo_programa]
-- Historias de Usuario: HU154
-- Ambito: Administrador Institucional. Alta de Tipo de Programa.
-- Salida Canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_tipo_programa]
(
    @codigo            NVARCHAR(20) = NULL,
    @nombre            NVARCHAR(150) = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoDef                NVARCHAR(20)     = UPPER(TRIM(@codigo));
    DECLARE @nombreDef                NVARCHAR(150)    = TRIM(@nombre);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 AND (@codigoDef IS NULL OR LEN(@codigoDef) <> 3 OR @codigoDef LIKE '%[^A-Z0-9]%')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Codigo de Tipo de Programa',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Formato invalido (3 caracteres A-Z/0-9). Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@nombreDef IS NULL OR LEN(@nombreDef) < 3 OR LEN(@nombreDef) > 50)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Nombre de Tipo de Programa',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Longitud invalida (3-50). Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.uv_tipo_programa WHERE codigo = @codigoDef)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'TPR_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Conflicto de unicidad para codigo. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.uv_tipo_programa WHERE LOWER(nombre) = LOWER(@nombreDef))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'TPR_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Conflicto de unicidad para nombre. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_crear_tipo_programa_interno
                @codigo = @codigoDef,
                @nombre = @nombreDef,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_actualizar_tipo_programa_interno]
-- Historias de Usuario: HU154
-- Ambito: operacion atomica de persistencia. Actualiza el nombre de Tipo de Programa.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_tipo_programa_interno]
(
    @id                      UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(50),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sv_actualizar_tipo_programa;
                SET @savepointCreado = 1;
            END

            UPDATE dbo.TipoPrograma
            SET nombre = @nombre
            WHERE id = @id;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_005',
                @p_param1 = 'Tipo de Programa',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);

            IF @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
            END
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sv_actualizar_tipo_programa;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_actualizar_tipo_programa]
-- Historias de Usuario: HU154
-- Ambito: Administrador Institucional. Modifica el nombre de Tipo de Programa; el codigo es inmutable.
-- Salida Canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_tipo_programa]
(
    @id                UNIQUEIDENTIFIER = NULL,
    @nombre            NVARCHAR(150)    = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDef                NVARCHAR(150)    = TRIM(@nombre);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar perfil del ejecutor (RBAC ADMINISTRADOR)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Validacion de negocio (TPR_001)
        IF @estadoResultado = 1 AND (@id IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_programa WHERE id = @id))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'TPR_001',
                @p_param1 = @id,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: Validacion de negocio (GEN_002)
        IF @estadoResultado = 1 AND (@nombreDef IS NULL OR LEN(@nombreDef) < 3 OR LEN(@nombreDef) > 50)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Nombre de Tipo de Programa',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Longitud invalida (3-50). Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: Validacion de negocio (TPR_002)
        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.uv_tipo_programa WHERE LOWER(nombre) = LOWER(@nombreDef) AND id <> @id)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'TPR_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Conflicto de unicidad para nombre. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 7: Ejecutar usp_actualizar_tipo_programa_interno
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_actualizar_tipo_programa_interno
                @id = @id,
                @nombre = @nombreDef,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_cambiar_estado_tipo_programa_interno]
-- Historias de Usuario: HU154
-- Ambito: operacion atomica de persistencia. Fija el estado de Tipo de Programa.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cambiar_estado_tipo_programa_interno]
(
    @id                      UNIQUEIDENTIFIER,
    @estaActivo              BIT,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sv_cambiar_estado_tipo_programa;
                SET @savepointCreado = 1;
            END

            UPDATE dbo.TipoPrograma
            SET estado = @estaActivo
            WHERE id = @id;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_005',
                @p_param1 = 'Tipo de Programa',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);

            IF @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
            END
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sv_cambiar_estado_tipo_programa;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_cambiar_estado_tipo_programa]
-- Historias de Usuario: HU154
-- Ambito: Administrador Institucional. Fija el estado deseado de Tipo de Programa (idempotente, sin cascada).
-- Salida Canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cambiar_estado_tipo_programa]
(
    @id                UNIQUEIDENTIFIER = NULL,
    @estaActivo        BIT              = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar perfil del ejecutor (RBAC ADMINISTRADOR)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Validacion de negocio (TPR_001)
        IF @estadoResultado = 1 AND (@id IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_programa WHERE id = @id))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'TPR_001',
                @p_param1 = @id,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: Validacion de negocio (GEN_002)
        IF @estadoResultado = 1 AND @estaActivo IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Estado deseado de Tipo de Programa',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: Ejecutar usp_cambiar_estado_tipo_programa_interno
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_cambiar_estado_tipo_programa_interno
                @id = @id,
                @estaActivo = @estaActivo,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

GRANT EXECUTE ON [dbo].[usp_guardar_tipo_identificacion] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_crear_area] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_actualizar_area] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_cambiar_estado_area] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_crear_tipo_programa] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_actualizar_tipo_programa] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_cambiar_estado_tipo_programa] TO [rol_asistencias_runtime];
GO
