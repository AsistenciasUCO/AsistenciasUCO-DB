USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_ejecutar_cierre_masivo_periodo]
(
    @codigoPeriodo          NVARCHAR(50),
    @idActor                NVARCHAR(100),
    @idCorrelacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoPeriodoDefecto     NVARCHAR(50)     = TRIM(@codigoPeriodo);
    DECLARE @idActorDefecto           NVARCHAR(100)    = TRIM(@idActor);

    DECLARE @idPeriodoTarget               UNIQUEIDENTIFIER;
    DECLARE @idEstadoFinalizado            UNIQUEIDENTIFIER;
    DECLARE @idEstadoCanceladoInasistencia UNIQUEIDENTIFIER;
    DECLARE @totalEstudiantes              INT = 0;
    DECLARE @totalReprobados               INT = 0;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor si es suministrado
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

        -- PASO 2: Buscar período académico objetivo consultando uv_periodo_academico
        IF @estadoResultado = 1
        BEGIN
            IF @codigoPeriodoDefecto IS NOT NULL AND @codigoPeriodoDefecto <> ''
            BEGIN
                SELECT TOP 1 @idPeriodoTarget = id
                FROM [dbo].[uv_periodo_academico]
                WHERE nombre = @codigoPeriodoDefecto 
                   OR CAST(codigo AS NVARCHAR(50)) = @codigoPeriodoDefecto
                ORDER BY anio DESC;
            END

            IF @idPeriodoTarget IS NULL
            BEGIN
                SELECT TOP 1 @idPeriodoTarget = id
                FROM [dbo].[uv_periodo_academico]
                ORDER BY anio DESC, codigo DESC;
            END

            IF @idPeriodoTarget IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'PeriodoAcademico',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Ejecución transaccional de Cierre Masivo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstadoFinalizado = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'F' ORDER BY id ASC;
            SELECT TOP 1 @idEstadoCanceladoInasistencia = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'CI' ORDER BY id ASC;

            BEGIN TRANSACTION;

            -- 1. Conteo de estudiantes procesados
            SELECT @totalEstudiantes = COUNT(eg.id)
            FROM dbo.EstudianteGrupo eg
            INNER JOIN dbo.Grupo g ON eg.grupo = g.id
            WHERE g.periodoAcademico = @idPeriodoTarget;

            -- 3. Actualizar estudiantes con fallas críticas (>= 3 inasistencias en DetalleAsistencia) a Cancelado por Inasistencia
            ;WITH InasistenciasPorEstudiante AS (
                SELECT 
                    eg.estudiante,
                    eg.grupo,
                    COUNT(da.id) AS totalFallas
                FROM dbo.DetalleAsistencia da
                INNER JOIN dbo.Asistencia a ON da.asistencia = a.id
                INNER JOIN dbo.EstudianteGrupo eg ON a.estudianteGrupo = eg.id
                INNER JOIN dbo.Sesion s ON a.sesion = s.id
                INNER JOIN dbo.Grupo g ON s.grupo = g.id
                WHERE g.periodoAcademico = @idPeriodoTarget
                  AND da.asistio = 0
                GROUP BY eg.estudiante, eg.grupo
                HAVING COUNT(da.id) >= 3
            )
            UPDATE eg
            SET eg.estado = @idEstadoCanceladoInasistencia
            FROM dbo.EstudianteGrupo eg
            INNER JOIN InasistenciasPorEstudiante ipe 
                ON eg.estudiante = ipe.estudiante AND eg.grupo = ipe.grupo
            WHERE eg.estado = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');

            SET @totalReprobados = @@ROWCOUNT;

            -- 4. Actualizar resto de estudiantes activos a Finalizado
            UPDATE eg
            SET eg.estado = @idEstadoFinalizado
            FROM dbo.EstudianteGrupo eg
            INNER JOIN dbo.Grupo g ON eg.grupo = g.id
            WHERE g.periodoAcademico = @idPeriodoTarget
              AND eg.estado = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');

            -- 5. Actualizar contadores en tabla Grupo
            UPDATE g
            SET 
                cantidadEstudiantesFinalizaron = (
                    SELECT COUNT(1) FROM dbo.EstudianteGrupo eg 
                    WHERE eg.grupo = g.id AND eg.estado = @idEstadoFinalizado
                ),
                cantidadEstudiantesCancelaronAutomaticamente = (
                    SELECT COUNT(1) FROM dbo.EstudianteGrupo eg 
                    WHERE eg.grupo = g.id AND eg.estado = @idEstadoCanceladoInasistencia
                )
            FROM dbo.Grupo g
            WHERE g.periodoAcademico = @idPeriodoTarget;

            -- 6. Auditoría de evento
            INSERT INTO dbo.AuditoriaEvento (
                id, occurredAt, actorId, actorType, action,
                resourceType, resourceId, result, correlationId,
                httpMethod, path, httpStatus, metadata
            ) VALUES (
                NEWID(),
                SYSDATETIMEOFFSET(),
                CASE WHEN @idActorDefecto IS NOT NULL AND @idActorDefecto <> '' THEN @idActorDefecto ELSE 'ADMIN_SISTEMA' END,
                CASE WHEN @idActorDefecto IS NOT NULL AND @idActorDefecto <> '' THEN 'USER' ELSE 'SYSTEM' END,
                'CIERRE_MASIVO_PERIODO',
                'PeriodoAcademico',
                CAST(@idPeriodoTarget AS NVARCHAR(50)),
                'SUCCESS',
                @idCorrelacionDefecto,
                'POST',
                '/api/v1/admin/cierre-masivo',
                200,
                CONCAT('{"procesados":', @totalEstudiantes, ',"reprobadosPorFallas":', @totalReprobados, '}')
            );

            COMMIT TRANSACTION;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'CierreMasivoPeriodo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
