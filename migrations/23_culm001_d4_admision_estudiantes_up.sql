-- ============================================================================
-- MIGRACION UP 23: CULM-001 D.4 - admision de estudiantes por el administrador, HU156 (CONTRACT D §5.2)
-- Siembra mensajes ADS_001..ADS_006 y los parametros IDENTIDAD/PERFILES_CORRECCION_ESTUDIANTE y _DECANO (MERGE), altera
-- usp_corregir_identidad_usuario (perfiles desde parametros; el administrador corrige estudiantes de su institucion), crea
-- usp_admitir_estudiante y usp_consultar_programas_institucion_paginado y concede EXECUTE al rol runtime. Idempotente.
-- Sin cambios de tablas. Down: 23_..._down.sql.
-- ============================================================================
PRINT 'MIGRACION 23 UP: admision de estudiantes (D.4)';
GO
-- ---- schema/seed/54_culm001_d4_mensajes.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.4 (CONTRACT §5.2, HU156): mensajes de la admision de estudiantes por el administrador. Idempotente (MERGE por codigo).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('ADS_001', 'SUCCESS',          'BAJO',  N'Estudiante admitido.'),
    ('ADS_002', 'BUSINESS_ERROR',   'BAJO',  N'El estudiante ya está admitido en este programa.'),
    ('ADS_003', 'BUSINESS_ERROR',   'MEDIO', N'El programa no existe o no pertenece a tu institución.'),
    ('ADS_004', 'BUSINESS_ERROR',   'MEDIO', N'El documento y el correo corresponden a personas distintas.'),
    ('ADS_005', 'VALIDATION_ERROR', 'BAJO',  N'El correo debe ser institucional ({}).'),
    ('ADS_006', 'VALIDATION_ERROR', 'BAJO',  N'Indica una contraseña inicial para el estudiante nuevo.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('ADS_001', 'SUCCESS',          'BAJO',  N'HU156: estudiante admitido en el programa; Usuario, Estudiante y EstudiantePrograma confirmados.'),
    ('ADS_002', 'BUSINESS_ERROR',   'BAJO',  N'HU156: EstudiantePrograma ya existe para el estudiante y el programa; sin escrituras.'),
    ('ADS_003', 'BUSINESS_ERROR',   'MEDIO', N'Ambito: el programa no existe, esta inactivo o no es de la institucion del administrador; sin escrituras.'),
    ('ADS_004', 'BUSINESS_ERROR',   'MEDIO', N'Regla: el documento y el correo no pertenecen al mismo Usuario (SUPUESTO-D-11); sin escrituras.'),
    ('ADS_005', 'VALIDATION_ERROR', 'BAJO',  N'Regla: el correo de un alta nueva no cumple REGISTRO/DOMINIO_CORREO_ESTUDIANTE ({}); sin escrituras.'),
    ('ADS_006', 'VALIDATION_ERROR', 'BAJO',  N'Regla: un alta nueva exige el hash de la contrasena inicial; sin escrituras.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
-- ---- schema/seed/54_culm001_d4_parametros.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.4 (CONTRACT §5.2, OBS-6): perfiles que pueden corregir la identidad de un estudiante y de un decano
-- (usp_corregir_identidad_usuario los lee en lugar de literales). Listas separadas por comas. Idempotente: si ya existen, no se
-- sobrescribe el valor vigente.
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('IDENTIDAD', 'PERFILES_CORRECCION_ESTUDIANTE', N'COORDINADOR,ADMINISTRADOR', 'STRING', N'COORDINADOR,ADMINISTRADOR'),
    ('IDENTIDAD', 'PERFILES_CORRECCION_DECANO',     N'ADMINISTRADOR',             'STRING', N'ADMINISTRADOR')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
-- ---- schema/stored-procedures/usp_corregir_identidad_usuario.sql
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
-- ---- schema/stored-procedures/usp_admitir_estudiante.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_admitir_estudiante (CULM-001 D.4, HU156; CONTRACT §5.2, SUPUESTO-D-07, SUPUESTO-D-11)
--
-- El ADMINISTRADOR crea (o reutiliza) un estudiante y lo vincula a un programa de SU institucion, sin matricularlo en grupos.
-- Orden: correlacion -> ejecutor (GEN_002) -> RBAC ADMINISTRADOR -> programa activo de su institucion (ADS_003) -> lectura bloqueada
-- (UPDLOCK, HOLDLOCK) de Usuario por documento y por correo -> documento y correo de personas distintas (ADS_004) -> en alta nueva:
-- correo institucional (ADS_005) y contrasena inicial (ADS_006) -> ya admitido en el programa (ADS_002) -> escrituras: Usuario
-- (usp_sincronizar_usuario_interno, solo si no existe), Estudiante (usp_sincronizar_estudiante_interno, solo si no existe) y
-- EstudiantePrograma. Todos los rechazos de negocio ocurren ANTES de escribir; un error del motor revierte lo escrito (transaccion
-- propia o savepoint). Persona existente (mismo documento y correo): no se revalida el dominio ni se pide contrasena (D5).
-- El vinculo se inserta aqui y no con usp_registrar_estudiante_en_programa_interno: ese nucleo resuelve la institucion del
-- estudiante desde uv_estudiante, que exige un programa, asi que fallaria para un estudiante sin programa.
-- @password es el HASH que arma el backend (nunca texto plano); no se escribe en ningun mensaje.
-- Resultset: MUTATION_COMMAND_RESULTSET (4 columnas canonicas) + idUsuario, idEstudiante, esUsuarioNuevo, esEstudianteNuevo
-- (nulos si falla, salvo ADS_002 que devuelve la persona ya admitida para que el backend repare su cuenta de identidad).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_admitir_estudiante]
(
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50) = NULL,
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50) = NULL,
    @correo                  NVARCHAR(255),
    @password                NVARCHAR(500) = NULL,
    @idPrograma              UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @correoNormalizado        NVARCHAR(255) = LOWER(TRIM(@correo));
    DECLARE @passwordNormalizado      NVARCHAR(500) = NULLIF(TRIM(@password), N'');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @idInstitucion           UNIQUEIDENTIFIER;
    DECLARE @idUsuarioPorDocumento   UNIQUEIDENTIFIER;
    DECLARE @idUsuarioPorCorreo      UNIQUEIDENTIFIER;
    DECLARE @idUsuarioResultado      UNIQUEIDENTIFIER;
    DECLARE @idEstudianteResultado   UNIQUEIDENTIFIER;
    DECLARE @esUsuarioNuevo          BIT = 0;
    DECLARE @esEstudianteNuevo       BIT = 0;
    DECLARE @dominioInstitucional    NVARCHAR(255);
    DECLARE @devolverPersona         BIT = 0;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @escrituraRealizada         BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: RBAC ADMINISTRADOR
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

        -- PASO 4: programa activo de la institucion del administrador (ADS_003; indistinguible de uno inexistente)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idInstitucion = a.institucion
            FROM dbo.Administrador a
            WHERE a.usuario = @idUsuarioEjecutorDefecto
            ORDER BY a.id;

            IF @idInstitucion IS NULL
               OR NOT EXISTS (SELECT 1 FROM dbo.uv_programa p
                              WHERE p.id = @idProgramaDefecto AND p.idInstitucion = @idInstitucion AND p.estaActivoPrograma = 1)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ADS_003',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: transaccion (propia o savepoint) y lectura bloqueada de la persona por documento y por correo
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_admitir_estudiante;
                SET @savepointCreado = 1;
            END

            SELECT TOP 1 @idUsuarioPorDocumento = u.id
            FROM dbo.Usuario u WITH (UPDLOCK, HOLDLOCK)
            WHERE u.tipoIdIdentificacion = @idTipoIdIdentificacion AND u.numeroIdentificacion = @numeroIdentificacion;

            SELECT TOP 1 @idUsuarioPorCorreo = u.id
            FROM dbo.Usuario u WITH (UPDLOCK, HOLDLOCK)
            WHERE u.correo = @correoNormalizado;

            -- ADS_004: documento y correo deben ser de la misma persona (ambos inexistentes o ambos del mismo usuario)
            IF (@idUsuarioPorDocumento IS NULL AND @idUsuarioPorCorreo IS NOT NULL)
               OR (@idUsuarioPorDocumento IS NOT NULL AND @idUsuarioPorCorreo IS NULL)
               OR (@idUsuarioPorDocumento IS NOT NULL AND @idUsuarioPorDocumento <> @idUsuarioPorCorreo)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ADS_004',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @idUsuarioResultado = @idUsuarioPorDocumento;
            END

            -- Alta nueva: correo institucional (ADS_005) y contrasena inicial (ADS_006)
            IF @estadoResultado = 1 AND @idUsuarioResultado IS NULL
            BEGIN
                SET @dominioInstitucional = dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE');
                IF dbo.ufn_correo_cumple_dominio_institucional(@correoNormalizado, @dominioInstitucional) = 0
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ADS_005', @p_param1 = @dominioInstitucional,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
                ELSE IF @passwordNormalizado IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ADS_006',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END

            -- Persona existente: estudiante y vinculo previos (ADS_002 si ya esta admitida en el programa)
            IF @estadoResultado = 1 AND @idUsuarioResultado IS NOT NULL
            BEGIN
                SELECT TOP 1 @idEstudianteResultado = e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioResultado;
                IF @idEstudianteResultado IS NOT NULL
                   AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep
                               WHERE ep.estudiante = @idEstudianteResultado AND ep.programa = @idProgramaDefecto)
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ADS_002',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                    SET @devolverPersona = 1;
                END
            END

            -- PASO 6: escrituras
            IF @estadoResultado = 1 AND @idUsuarioResultado IS NULL
            BEGIN
                SET @escrituraRealizada = 1;
                EXEC dbo.usp_sincronizar_usuario_interno
                    @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @primerApellido = @primerApellido,
                    @segundoApellido = @segundoApellido,
                    @primerNombre = @primerNombre,
                    @segundoNombre = @segundoNombre,
                    @correo = @correoNormalizado,
                    @password = @passwordNormalizado,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
                IF @estadoResultado = 1
                BEGIN
                    SELECT TOP 1 @idUsuarioResultado = u.id FROM dbo.Usuario u WHERE u.correo = @correoNormalizado;
                    SET @esUsuarioNuevo = 1;
                END
            END

            IF @estadoResultado = 1 AND @idEstudianteResultado IS NULL
            BEGIN
                SET @escrituraRealizada = 1;
                EXEC dbo.usp_sincronizar_estudiante_interno
                    @idUsuario = @idUsuarioResultado,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
                IF @estadoResultado = 1
                BEGIN
                    SELECT TOP 1 @idEstudianteResultado = e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioResultado;
                    SET @esEstudianteNuevo = 1;
                END
            END

            IF @estadoResultado = 1
            BEGIN
                SET @escrituraRealizada = 1;
                INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
                VALUES (NEWID(), @idEstudianteResultado, @idProgramaDefecto);

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ADS_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            -- PASO 7: cierre respetando el ownership (rollback solo si hubo escrituras y el resultado es fallido)
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    IF @estadoResultado = 1 OR @escrituraRealizada = 0
                        COMMIT TRANSACTION;
                    ELSE
                        ROLLBACK TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
            END
            ELSE IF @savepointCreado = 1
            BEGIN
                IF XACT_STATE() = 1 AND @estadoResultado = 0 AND @escrituraRealizada = 1
                    ROLLBACK TRANSACTION sp_admitir_estudiante;
            END
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
            ROLLBACK TRANSACTION sp_admitir_estudiante;
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
        SET @devolverPersona = 0;
        SET @esUsuarioNuevo = 0;
        SET @esEstudianteNuevo = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idUsuario               = IIF(@estadoResultado = 1 OR @devolverPersona = 1, @idUsuarioResultado, NULL),
        idEstudiante            = IIF(@estadoResultado = 1 OR @devolverPersona = 1, @idEstudianteResultado, NULL),
        esUsuarioNuevo          = IIF(@estadoResultado = 1 OR @devolverPersona = 1, @esUsuarioNuevo, NULL),
        esEstudianteNuevo       = IIF(@estadoResultado = 1 OR @devolverPersona = 1, @esEstudianteNuevo, NULL);
END;
GO
-- ---- schema/stored-procedures/usp_consultar_programas_institucion_paginado.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_programas_institucion_paginado (CULM-001 D.4, HU156; CONTRACT §5.2)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 si la validacion falla: GEN_002, SEC_001,
-- PAG_001). Programas ACTIVOS de la institucion del ADMINISTRADOR (el ambito esta aqui: Administrador.institucion), para el
-- selector de programa de la admision. Filtros opcionales: @texto (contiene, en el nombre del programa) y @idFacultad.
-- Columnas: id, nombre, idFacultad, nombreFacultad, totalRegistros (COUNT(1) OVER()). Orden nombreFacultad, nombre.
-- Programa no tiene columna de codigo en el modelo vigente, por eso no se devuelve. @tamanoPagina entre 1 y
-- PAGINACION/TAMANO_MAXIMO. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_programas_institucion_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 50,
    @texto             NVARCHAR(100) = NULL,
    @idFacultad        UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @textoFiltro          NVARCHAR(100) = NULLIF(TRIM(@texto), N'');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @idInstitucion UNIQUEIDENTIFIER;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'ADMINISTRADOR', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
       AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
            OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT TOP 1 @idInstitucion = a.institucion FROM dbo.Administrador a WHERE a.usuario = @idUsuarioDefecto ORDER BY a.id;

    SET @offset = (@numeroPagina - 1) * @tamanoPagina;
    SELECT
        id             = p.id,
        nombre         = p.nombrePrograma,
        idFacultad     = p.idFacultad,
        nombreFacultad = p.nombreFacultad,
        totalRegistros = COUNT(1) OVER()
    FROM dbo.uv_programa p
    WHERE p.idInstitucion = @idInstitucion
      AND p.estaActivoPrograma = 1
      AND (@idFacultad IS NULL OR p.idFacultad = @idFacultad)
      AND (@textoFiltro IS NULL OR p.nombrePrograma LIKE CONCAT(N'%', @textoFiltro, N'%'))
    ORDER BY p.nombreFacultad ASC, p.nombrePrograma ASC, p.id ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
-- ---- schema/security/rol_asistencias_runtime_culm001_d4.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.4 (CONTRACT §5.2): permisos de la admision de estudiantes (HU156). Solo EXECUTE sobre los SP publicos; los nucleos
-- usp_*_interno que usan NO se conceden. Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_admitir_estudiante', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_admitir_estudiante] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_programas_institucion_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_programas_institucion_paginado] TO [rol_asistencias_runtime];
GO
