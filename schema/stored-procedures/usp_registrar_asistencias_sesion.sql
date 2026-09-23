USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CONTRATO PUBLICO (backend AsistenciasUCO):
--   * Estados aceptados en @asistenciaJSON: AN (asistencia normal), SJC (sin justa causa), EX (excusa).
--     Se normaliza con TRIM + UPPER antes de validar. A / F / T / J / cualquier otro valor => RC_001.
--   * @idUsuarioEjecutor = Usuario.id del docente titular. OPTIONAL EN FIRMA != OPTIONAL EN CONTRATO:
--     el default = NULL se conserva solo por compatibilidad de firma; NULL se rechaza funcionalmente (GEN_002).
--   * RazonCausa es un catalogo cerrado: este SP jamas crea filas en dbo.RazonCausa.
--   * El lote es atomico: todo se valida antes de escribir y cualquier fallo revierte el lote completo.
--   * Result set canonico (una unica fila): idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_asistencias_sesion]
(
    @idSesion       UNIQUEIDENTIFIER,
    @asistenciaJSON NVARCHAR(MAX),
    @idCorrelacion  UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    -- 1. Estandarización e inicialización de variables locales utilizando catálogo de parámetros (Sin ISNULL)
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @totalEstudiantes     INT = 0;
    DECLARE @iterador             INT = 1;
    DECLARE @idEstudianteActual   UNIQUEIDENTIFIER;
    DECLARE @idEstudianteInvalido UNIQUEIDENTIFIER;
    DECLARE @idGrupoSesion        UNIQUEIDENTIFIER;
    DECLARE @estadoActual         NVARCHAR(50);
    DECLARE @secuenciaInvalida    INT;
    DECLARE @estadoInvalido       NVARCHAR(200);

    -- Tabla temporal en memoria para iterar el JSON de asistencias (estado ya normalizado TRIM + UPPER)
    DECLARE @EstudiantesATrabajar TABLE (
        secuencia    INT IDENTITY(1,1),
        idEstudiante UNIQUEIDENTIFIER NULL,
        estado       NVARCHAR(200) NULL
    );

    -- Inicialización interna de variables de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    -- Control de ownership transaccional (ver docs/procedimiento-transacciones)
    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.1: El ejecutor (Usuario.id) es obligatorio: NULL nunca se salta RBAC ni titularidad
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

        -- PASO 1.2: Validación de usuario existente y perfil RBAC DOCENTE
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Validación de existencia de la sesión de clase
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.1: Titularidad del docente sobre la sesión (Usuario.id -> Docente.id del grupo)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idGrupoSesion = grupo
            FROM dbo.Sesion
            WHERE id = @idSesionDefecto;

            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idSesionDefecto,
                @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Desglose del JSON y validación de TODOS los registros antes de cualquier escritura
        IF @estadoResultado = 1
        BEGIN
            IF @asistenciaJSON IS NULL OR ISJSON(@asistenciaJSON, ARRAY) <> 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ATT_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM OPENJSON(@asistenciaJSON) item
                WHERE item.[type] <> 5
                   OR (SELECT COUNT(1) FROM OPENJSON(item.value)) <> 2
                   OR NOT EXISTS (SELECT 1 FROM OPENJSON(item.value) field WHERE field.[key] = 'idEstudiante')
                   OR NOT EXISTS (SELECT 1 FROM OPENJSON(item.value) field WHERE field.[key] = 'estado')
                   OR EXISTS (SELECT 1 FROM OPENJSON(item.value) field WHERE field.[key] NOT IN ('idEstudiante', 'estado'))
            )
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ATT_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            INSERT INTO @EstudiantesATrabajar (idEstudiante, estado)
            SELECT TRY_CAST(idEstudiante AS UNIQUEIDENTIFIER), UPPER(TRIM(estado))
            FROM OPENJSON(@asistenciaJSON)
            WITH (
                idEstudiante NVARCHAR(100) '$.idEstudiante',
                estado       NVARCHAR(200) '$.estado'
            );

            SELECT @totalEstudiantes = COUNT(1) FROM @EstudiantesATrabajar;

            -- 3.1: lote no vacío
            IF @totalEstudiantes = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ATT_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- 3.2: idEstudiante no nulo (ni un valor que no sea UUID)
            SELECT TOP 1 @secuenciaInvalida = secuencia
            FROM @EstudiantesATrabajar
            WHERE idEstudiante IS NULL
            ORDER BY secuencia;

            IF @secuenciaInvalida IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_002',
                    @p_param1 = 'idEstudiante',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- 3.3: estado no nulo/no vacío y perteneciente al contrato público AN / SJC / EX
            IF @estadoResultado = 1
            BEGIN
                SELECT TOP 1
                    @secuenciaInvalida = secuencia,
                    @estadoInvalido = CASE WHEN estado IS NULL OR estado = '' THEN N'(vacio)' ELSE estado END
                FROM @EstudiantesATrabajar
                WHERE estado IS NULL OR estado = '' OR estado NOT IN ('AN', 'SJC', 'EX')
                ORDER BY secuencia;

                IF @secuenciaInvalida IS NOT NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'RC_001',
                        @p_param1 = @estadoInvalido,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END

            -- 3.4: estudiantes no duplicados dentro del mismo lote
            IF @estadoResultado = 1
            BEGIN
                SELECT TOP 1 @idEstudianteInvalido = idEstudiante
                FROM @EstudiantesATrabajar
                GROUP BY idEstudiante
                HAVING COUNT(1) > 1
                ORDER BY idEstudiante;

                IF @idEstudianteInvalido IS NOT NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ATT_003',
                        @p_param1 = @idEstudianteInvalido,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END

            -- 3.5: pertenencia activa de TODOS los estudiantes antes de cualquier escritura
            IF @estadoResultado = 1
            BEGIN
                SELECT TOP 1 @idEstudianteInvalido = et.idEstudiante
                FROM @EstudiantesATrabajar et
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM dbo.Estudiante e
                    INNER JOIN dbo.EstudianteGrupo eg ON eg.estudiante = e.id
                    INNER JOIN dbo.EstadoEstudianteGrupo eeg ON eeg.id = eg.estado
                    WHERE e.id = et.idEstudiante
                      AND eg.grupo = @idGrupoSesion
                      AND eeg.codigo = 'A'
                )
                ORDER BY et.secuencia;

                IF @idEstudianteInvalido IS NOT NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'EST_004',
                        @p_param1 = @idEstudianteInvalido,
                        @p_param2 = @idSesionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
        END

        -- PASO 4: Sincronización atómica del lote (ownership transaccional: propia o savepoint bajo transacción externa)
        IF @estadoResultado = 1
        BEGIN
            SET @iterador = 1;

            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_asistencias_sesion;
                SET @savepointCreado = 1;
            END

            WHILE @iterador <= @totalEstudiantes AND @estadoResultado = 1
            BEGIN
                SELECT
                    @idEstudianteActual = idEstudiante,
                    @estadoActual       = estado
                FROM @EstudiantesATrabajar
                WHERE secuencia = @iterador;

                -- Sincronización de asistencia individual por estudiante (estado ya validado: AN / SJC / EX)
                IF @estadoResultado = 1
                BEGIN
                    EXEC dbo.usp_sincronizar_asistencia_estudiante_interno
                        @idEstudiante = @idEstudianteActual,
                        @idSesion = @idSesionDefecto,
                        @codigoEstado = @estadoActual,
                        @idCorrelacion = @idCorrelacionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                        @estadoResultado = @estadoResultado OUTPUT;
                END

                SET @iterador = @iterador + 1;
            END

            -- Control transaccional de cierre del bloque de asistencias respetando ownership
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1 AND @estadoResultado = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() <> 0
                    ROLLBACK TRANSACTION;
            END
            ELSE IF @savepointCreado = 1
            BEGIN
                IF XACT_STATE() = 1 AND @estadoResultado = 0
                    ROLLBACK TRANSACTION sp_asistencias_sesion;
            END
        END

        -- PASO 5: Evaluación de resultado final y generación de mensaje de éxito desde el Catálogo de Mensajes
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'BloqueAsistenciasSesion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

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
            ROLLBACK TRANSACTION sp_asistencias_sesion;
        END

        -- Transacción externa condenada (XACT_STATE = -1) que no nos pertenece: propagar al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = [dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados garantizando el nombre de columna idCorrelacion
    SELECT
        idCorrelacion = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado;
END;
GO
