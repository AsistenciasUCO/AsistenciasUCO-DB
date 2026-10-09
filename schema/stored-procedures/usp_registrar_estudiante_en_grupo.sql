USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =====================================================================================
-- PUBLIC (consumido por el backend): POST /api/v1/grupos/{grupoId}/estudiantes.
-- Provider publico canonico de la unidad "registrar estudiante en grupo" (TD-043
-- STUDENT_ENROLLMENT_PROVIDER). Orquesta los SP internos; el backend NO invoca _interno.
--
-- Contrato explicito (sin defaults que sustituyan datos):
--   @idUsuarioEjecutor       OBLIGATORIO. NULL -> GEN_002, cero escrituras.
--   @idTipoIdIdentificacion  OBLIGATORIO. NULL -> GEN_002; inexistente -> GEN_001. Sin fallback a 'CC'.
--   Salida: 1 fila, 4 columnas canonicas. Sin parametros OUTPUT hacia el consumidor.
--
-- Autorizacion (modelo-jerarquico-rbac):
--   1. RBAC: el ejecutor debe tener perfil DOCENTE o COORDINADOR (SEC_001).
--      ADMINISTRADOR NO se acepta: no hay bypass administrativo.
--   2. Titularidad (SEC_002), en OR:
--        a. DOCENTE titular del grupo  -> usp_validar_titularidad_jerarquica_interno (GRUPO)
--        b. COORDINADOR del programa del grupo -> usp_validar_titularidad_jerarquica_interno (PROGRAMA)
--      Un usuario con ambos perfiles basta con cumplir una de las dos reglas.
--
-- Identidad (sin sobrescribir credenciales ni fusionar usuarios):
--   - Se busca por correo y por (idTipoIdIdentificacion, numeroIdentificacion) mediante uv_usuario.
--   - Ambas claves apuntan al mismo usuario  -> se reutiliza; NO se modifica su password.
--   - Ninguna existe                          -> se crea Usuario (usp_sincronizar_usuario_interno)
--                                               y Estudiante si falta (usp_sincronizar_estudiante_interno).
--   - Cualquier otro caso (una sola clave coincide, o claves en usuarios distintos)
--                                             -> IDN_001 (conflicto), cero escrituras.
--
-- Transaccion (ownership): si no hay transaccion externa, abre y cierra la propia; si la hay,
-- usa SAVEPOINT sp_matricula_grupo. Nunca hace COMMIT ni ROLLBACK total de una transaccion ajena.
-- =====================================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_estudiante_en_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @password                NVARCHAR(500),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER
)
AS
    -- 1. Estandarizacion e inicializacion de variables utilizando funciones de catalogo (Sin ISNULL / COALESCE)
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idTipoIdDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idTipoIdIdentificacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @correoDefecto            NVARCHAR(100)    = LOWER(TRIM(dbo.ufn_obtener_parametro_texto(@correo, 'GENERAL', 'CADENA_VACIA')));

    DECLARE @idProgramaGrupo          UNIQUEIDENTIFIER;
    DECLARE @idUsuarioPorCorreo       UNIQUEIDENTIFIER;
    DECLARE @idUsuarioPorIdentificacion UNIQUEIDENTIFIER;
    DECLARE @idUsuarioTarget          UNIQUEIDENTIFIER;
    DECLARE @idEstudianteResultado    UNIQUEIDENTIFIER;
    DECLARE @esTitularGrupo           BIT = 0;
    DECLARE @esCoordinadorPrograma    BIT = 0;
    DECLARE @transaccionPropia        BIT = 0;
    DECLARE @savepointCreado          BIT = 0;
    DECLARE @estadoTransaccionCatch   INT;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado  NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado  NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado          BIT = 1;

    -- Variables descartables para sondeos de titularidad (no son la respuesta del SP)
    DECLARE @mensajeUsuarioSondeo     NVARCHAR(4000);
    DECLARE @mensajeTecnicoSondeo     NVARCHAR(4000);

BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor obligatorio (sin fallback)
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

        -- PASO 3: tipo de identificacion explicito (sin fallback a 'CC' ni al primer tipo del catalogo)
        IF @estadoResultado = 1 AND @idTipoIdIdentificacion IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idTipoIdIdentificacion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_tipo_identificacion_exista_por_id_interno
                @idTipoId = @idTipoIdDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: RBAC. Solo DOCENTE o COORDINADOR; ADMINISTRADOR queda fuera (sin bypass).
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'DOCENTE,COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: el grupo debe existir
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 6: titularidad (OR). Antes de cualquier validacion de capacidad o escritura.
        IF @estadoResultado = 1
        BEGIN
            -- Programa del grupo resuelto por vistas: uv_grupo -> uv_asignatura -> uv_semestre_plan_estudio
            SELECT TOP 1 @idProgramaGrupo = spe.idPrograma
            FROM dbo.uv_grupo g
            INNER JOIN dbo.uv_asignatura a ON a.id = g.idAsignatura
            INNER JOIN dbo.uv_semestre_plan_estudio spe ON spe.id = a.idSemestrePlanEstudio
            WHERE g.id = @idGrupoDefecto;

            -- 6.a DOCENTE titular del grupo
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idGrupoDefecto,
                @tipoEntidadPadre = 'GRUPO',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioSondeo OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoSondeo OUTPUT,
                @estadoResultado = @esTitularGrupo OUTPUT;

            -- 6.b COORDINADOR del programa del grupo (solo si no es titular del grupo)
            IF @esTitularGrupo = 0 AND @idProgramaGrupo IS NOT NULL
            BEGIN
                EXEC dbo.usp_validar_titularidad_jerarquica_interno
                    @idUsuario = @idUsuarioEjecutorDefecto,
                    @idEntidadPadre = @idProgramaGrupo,
                    @tipoEntidadPadre = 'PROGRAMA',
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioSondeo OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoSondeo OUTPUT,
                    @estadoResultado = @esCoordinadorPrograma OUTPUT;
            END

            IF @esTitularGrupo = 0 AND @esCoordinadorPrograma = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SEC_002',
                    @p_param1 = 'Titularidad Grupo o Programa',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 7: cupo disponible antes de tocar identidad (evita Usuario/Estudiante parciales)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_cupo_disponible_grupo_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 8: resolucion de identidad (solo lectura, sin escrituras)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idUsuarioPorCorreo = u.id
            FROM dbo.uv_usuario u
            WHERE u.correo = @correoDefecto;

            SELECT TOP 1 @idUsuarioPorIdentificacion = u.id
            FROM dbo.uv_usuario u
            WHERE u.idTipoIdentificacion = @idTipoIdDefecto
              AND u.numeroIdentificacion = @numeroIdentificacion;

            -- Conflicto: una sola clave coincide, o ambas apuntan a usuarios distintos. No se fusiona ni modifica nada.
            IF (@idUsuarioPorCorreo IS NULL AND @idUsuarioPorIdentificacion IS NOT NULL)
               OR (@idUsuarioPorCorreo IS NOT NULL AND @idUsuarioPorIdentificacion IS NULL)
               OR (@idUsuarioPorCorreo IS NOT NULL AND @idUsuarioPorIdentificacion IS NOT NULL
                   AND @idUsuarioPorCorreo <> @idUsuarioPorIdentificacion)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'IDN_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 1 AND @idUsuarioPorCorreo IS NOT NULL
            BEGIN
                SET @idUsuarioTarget = @idUsuarioPorCorreo;
            END
        END

        -- PASO 9: escrituras Usuario -> Estudiante -> EstudianteGrupo con ownership transaccional
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_matricula_grupo;
                SET @savepointCreado = 1;
            END

            -- 9.1 Usuario: solo si no existe. Su credencial no se modifica para usuarios existentes.
            IF @idUsuarioTarget IS NULL
            BEGIN
                EXEC dbo.usp_sincronizar_usuario_interno
                    @idTipoIdIdentificacion = @idTipoIdDefecto,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @primerApellido = @primerApellido,
                    @segundoApellido = @segundoApellido,
                    @primerNombre = @primerNombre,
                    @segundoNombre = @segundoNombre,
                    @correo = @correo,
                    @password = @password,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                BEGIN
                    SELECT TOP 1 @idUsuarioTarget = u.id FROM dbo.uv_usuario u WHERE u.correo = @correoDefecto;
                END
            END

            -- 9.2 Estudiante: solo si el usuario aun no es estudiante
            IF @estadoResultado = 1 AND @idUsuarioTarget IS NOT NULL
            BEGIN
                SELECT TOP 1 @idEstudianteResultado = ei.id
                FROM dbo.uv_estudiante_identidad ei
                WHERE ei.idUsuario = @idUsuarioTarget;

                IF @idEstudianteResultado IS NULL
                BEGIN
                    EXEC dbo.usp_sincronizar_estudiante_interno
                        @idUsuario = @idUsuarioTarget,
                        @idCorrelacion = @idCorrelacionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                        @estadoResultado = @estadoResultado OUTPUT;

                    IF @estadoResultado = 1
                    BEGIN
                        SELECT TOP 1 @idEstudianteResultado = ei.id
                        FROM dbo.uv_estudiante_identidad ei
                        WHERE ei.idUsuario = @idUsuarioTarget;
                    END
                END
            END

            -- Guarda: un Usuario sin Estudiante resoluble no puede matricularse; falla controlado (y se revierte).
            IF @estadoResultado = 1 AND @idEstudianteResultado IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'EST_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- 9.3 Matricula en el grupo (EstudiantePrograma se garantiza dentro del interno)
            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_registrar_estudiante_en_grupo_interno
                    @idEstudiante = @idEstudianteResultado,
                    @idGrupo = @idGrupoDefecto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            -- Cierre: se confirma solo la transaccion propia; con savepoint no se confirma la externa.
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1 AND @estadoResultado = 1
                BEGIN
                    COMMIT TRANSACTION;
                END
                ELSE IF XACT_STATE() <> 0
                BEGIN
                    ROLLBACK TRANSACTION;
                END
            END
            ELSE IF @savepointCreado = 1 AND @estadoResultado = 0
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    ROLLBACK TRANSACTION sp_matricula_grupo;
                END
                -- Transaccion externa condenada (un error que no admite savepoint): no se puede revertir solo lo
                -- de este SP. Se propaga al propietario de la transaccion, que debe revertirla completa.
                ELSE IF XACT_STATE() = -1
                BEGIN
                    THROW 51000, 'Transaccion externa condenada durante la matricula; el llamador debe revertirla.', 1;
                END
            END
        END

    END TRY
    BEGIN CATCH
        -- Rollback solo de lo que este SP posee; la transaccion externa se propaga si esta condenada.
        SET @estadoTransaccionCatch = XACT_STATE();

        IF @transaccionPropia = 1 AND @estadoTransaccionCatch <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_matricula_grupo;
        END

        -- Transaccion externa condenada que no nos pertenece: propagar al propietario.
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

    -- BLOQUE FINAL: contrato canonico (1 fila, 4 columnas)
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
