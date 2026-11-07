USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_corregir_identidad_usuario (HU159, decision de John 2026-11-05)
--
-- Correccion de los datos de identidad (tipo y numero de documento, nombres y apellidos) por jerarquia. No toca el
-- correo, la contrasena ni el estado. @tipoUsuario elige el registro y quien puede corregirlo:
--   * ESTUDIANTE (@idRegistro = Estudiante.id): los perfiles de IDENTIDAD/PERFILES_CORRECCION_ESTUDIANTE (CULM-001 D.4). El
--     coordinador de un programa al que pertenece el estudiante (EstudiantePrograma -> Programa.coordinador) o el administrador de
--     la institucion de uno de sus programas. Uno fuera de ese ambito (aunque este en un grupo del coordinador) es
--     indistinguible de uno inexistente: GEN_001.
--   * DECANO (@idRegistro = Decano.id): los perfiles de IDENTIDAD/PERFILES_CORRECCION_DECANO; el administrador de la institucion
--     de sus facultades.
--   (Coordinador y docente se corrigen en sus SP de edicion: usp_actualizar_coordinador y
--   usp_actualizar_docente_programa. El administrador no se corrige por la app.)
--   * El motivo es obligatorio (1..500 caracteres, sin espacios extremos): IDE_001.
--   * La correccion la hace el nucleo comun usp_corregir_identidad_usuario_interno: nombres (VAL_003, VAL_004),
--     documento (usp_corregir_documento_usuario_interno: IDE_003 si esta apagado, VAL_001, ERR_UNICIDAD_DOCUMENTO) y
--     auditoria CORREGIR_IDENTIDAD_<TIPO> con el motivo y los valores anteriores y nuevos (visible en HU172).
--     El documento es el username del proveedor de identidad: el backend lo sincroniza despues de confirmar en DB.
-- Resultset: MUTATION_COMMAND_RESULTSET (4 columnas canonicas) + idUsuario, correo y numeroIdentificacion
-- (nulos si falla) para la sincronizacion de la cuenta de identidad.
-- Codigos: GEN_002 ejecutor nulo, IDE_001 motivo, GEN_001 registro fuera del ambito, IDE_002 exito.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_corregir_identidad_usuario]
(
    @tipoUsuario             VARCHAR(20),
    @idRegistro              UNIQUEIDENTIFIER,
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50) = NULL,
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50) = NULL,
    @motivo                  NVARCHAR(MAX),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idRegistroDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idRegistro, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @esDecano                 BIT = IIF(@tipoUsuario = 'DECANO', 1, 0);
    -- Perfiles que pueden corregir cada tipo de registro, desde parametros (CULM-001 D.4, OBS-6): lista separada por comas;
    -- NULL => tipo no soportado, lo rechaza el paso 3. El ambito de cada perfil se evalua por datos, sin nombrar perfiles.
    DECLARE @perfilRequerido          VARCHAR(200) = NULLIF(TRIM(CASE @tipoUsuario
                                          WHEN 'ESTUDIANTE' THEN dbo.ufn_obtener_parametro('IDENTIDAD', 'PERFILES_CORRECCION_ESTUDIANTE')
                                          WHEN 'DECANO' THEN dbo.ufn_obtener_parametro('IDENTIDAD', 'PERFILES_CORRECCION_DECANO') END), '');
    DECLARE @tipoRecurso              VARCHAR(120) = IIF(@esDecano = 1, 'Decano', 'Estudiante');
    DECLARE @accionAuditoria          VARCHAR(120) = IIF(@esDecano = 1, 'CORREGIR_IDENTIDAD_DECANO', 'CORREGIR_IDENTIDAD_ESTUDIANTE');
    DECLARE @rutaAuditoria            NVARCHAR(240) = IIF(@esDecano = 1, N'/api/v1/admin/decanos/{id}/identidad',
                                                         N'/api/v1/coordinador/estudiantes/{idEstudiante}/identidad');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @motivoNormalizado        NVARCHAR(MAX) = NULLIF(TRIM(@motivo), N'');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @codigoRechazo           VARCHAR(100);

    DECLARE @idUsuarioRegistro       UNIQUEIDENTIFIER;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    -- Solo se hace ROLLBACK si hubo escritura: un rechazo de negocio antes de escribir no lo necesita, y SQL Server
    -- prohibe ROLLBACK dentro de INSERT ... EXEC (3915), que es como se consume este SP en las pruebas.
    DECLARE @mutacionRealizada          BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
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
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: tipo soportado (un perfil vacio pasaria el RBAC) y RBAC (COORDINADOR para un estudiante,
        -- ADMINISTRADOR para un decano)
        IF @estadoResultado = 1 AND @perfilRequerido IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001', @p_param1 = 'tipoUsuario',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = @perfilRequerido,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Motivo obligatorio (IDE_001)
        IF @estadoResultado = 1 AND (@motivoNormalizado IS NULL OR LEN(@motivoNormalizado) > 500)
        BEGIN
            SET @codigoRechazo = 'IDE_001';
        END

        -- PASO 5: Ambito y escritura dentro de una transaccion (propia o savepoint si el llamador ya tiene una)
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_corregir_identidad_usuario;
                SET @savepointCreado = 1;
            END

            -- Ambito por jerarquia, en tablas base.
            SELECT @idUsuarioRegistro = u.id
            FROM dbo.Usuario u WITH (UPDLOCK, HOLDLOCK)
            WHERE (@esDecano = 0 AND (EXISTS (
                      -- Ambito del coordinador: estudiante de un programa que el ejecutor coordina
                      SELECT 1
                      FROM dbo.Estudiante e
                      INNER JOIN dbo.EstudiantePrograma ep ON ep.estudiante = e.id
                      INNER JOIN dbo.Programa p ON p.id = ep.programa
                      INNER JOIN dbo.Coordinador c ON c.id = p.coordinador
                      WHERE e.id = @idRegistroDefecto AND e.usuario = u.id AND c.usuario = @idUsuarioEjecutorDefecto)
                  OR EXISTS (
                      -- Ambito del administrador: estudiante de un programa de la institucion del ejecutor
                      SELECT 1
                      FROM dbo.Estudiante e
                      INNER JOIN dbo.EstudiantePrograma ep ON ep.estudiante = e.id
                      INNER JOIN dbo.Programa p ON p.id = ep.programa
                      INNER JOIN dbo.Facultad f ON f.id = p.facultad
                      INNER JOIN dbo.Administrador a ON a.institucion = f.institucion
                      WHERE e.id = @idRegistroDefecto AND e.usuario = u.id AND a.usuario = @idUsuarioEjecutorDefecto)))
               OR (@esDecano = 1 AND EXISTS (
                      SELECT 1
                      FROM dbo.Decano d
                      INNER JOIN dbo.Administrador a ON a.usuario = @idUsuarioEjecutorDefecto
                      WHERE d.id = @idRegistroDefecto AND d.usuario = u.id
                        AND NOT EXISTS (SELECT 1 FROM dbo.Facultad f WHERE f.decano = d.id AND f.institucion <> a.institucion)));

            IF @idUsuarioRegistro IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = @tipoRecurso,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 1
            BEGIN
                -- Los rechazos del nucleo ocurren antes de escribir; un error del motor condena la transaccion (XACT_ABORT).
                EXEC dbo.usp_corregir_identidad_usuario_interno
                    @idUsuario = @idUsuarioRegistro,
                    @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @primerNombre = @primerNombre,
                    @segundoNombre = @segundoNombre,
                    @primerApellido = @primerApellido,
                    @segundoApellido = @segundoApellido,
                    @motivo = @motivoNormalizado,
                    @accionAuditoria = @accionAuditoria,
                    @tipoRecurso = @tipoRecurso,
                    @idRecurso = @idRegistroDefecto,
                    @rutaAuditoria = @rutaAuditoria,
                    @idUsuarioEjecutor = @idUsuarioEjecutorDefecto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
                SET @mutacionRealizada = @estadoResultado;
            END

            -- Cierre de la transaccion respetando el ownership
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    IF @estadoResultado = 1 OR @mutacionRealizada = 0
                        COMMIT TRANSACTION;
                    ELSE
                        ROLLBACK TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                BEGIN
                    ROLLBACK TRANSACTION;
                END
            END
            ELSE IF @savepointCreado = 1
            BEGIN
                IF XACT_STATE() = 1 AND @estadoResultado = 0 AND @mutacionRealizada = 1
                    ROLLBACK TRANSACTION sp_corregir_identidad_usuario;
            END
        END

        -- PASO 6: Traducir el codigo de rechazo a su mensaje de catalogo
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_corregir_identidad_usuario;
        END
        -- Transaccion externa condenada que no nos pertenece: se propaga la excepcion al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END
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
        estadoResultado         = @estadoResultado,
        idUsuario               = IIF(@estadoResultado = 1, @idUsuarioRegistro, NULL),
        correo                  = (SELECT u.correo FROM dbo.Usuario u WHERE @estadoResultado = 1 AND u.id = @idUsuarioRegistro),
        numeroIdentificacion    = (SELECT u.numeroIdentificacion FROM dbo.Usuario u
                                   WHERE @estadoResultado = 1 AND u.id = @idUsuarioRegistro);
END;
GO
