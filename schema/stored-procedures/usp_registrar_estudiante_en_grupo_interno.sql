USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_registrar_estudiante_en_grupo_interno (HU050 manual y HU176B QR/PIN)
--
-- Requiere transaccion del llamador; no la abre ni la confirma. Sus dos llamadores publicos la abren
-- (usp_registrar_estudiante_en_grupo y usp_internal_matricular_por_token) y revierten su savepoint de negocio ante un
-- rechazo posterior a la escritura (docs/arquitectura/transaccion-procedimiento.md, internos compuestos).
-- CULM-001 A.1 (DEC-009): PASO 3.8 reactiva la matricula RETIRADA del estudiante en el grupo (misma fila, I -> estado
-- destino) mediante usp_internal_reactivar_matricula_retirada; sin matricula retirada sigue el alta normal. La regla de
-- inscripcion en el programa (componente ESP) es comun a los dos caminos y vive solo aqui.
-- El estado por defecto ('' o el parametro) se resuelve con MATRICULA/ESTADO_INSCRITA (sin literal quemado).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_estudiante_en_grupo_interno]
(
    @idEstudiante            UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @codigoEstado            NVARCHAR(10) = 'A',
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstadoActivo       UNIQUEIDENTIFIER;
    DECLARE @reactivada           BIT = 0;

    -- Inicialización de respuesta desde parámetros del catálogo
    SELECT 
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Obtener identificador del Estado para EstudianteGrupo
        IF @estadoResultado = 1
        BEGIN
            DECLARE @codigoEstadoDefecto NVARCHAR(10) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@codigoEstado, 'GENERAL', 'CADENA_VACIA')));
            IF @codigoEstadoDefecto = '' SET @codigoEstadoDefecto = UPPER(TRIM(CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10))));

            SELECT @idEstadoActivo = id 
            FROM dbo.uv_estado_estudiante_grupo 
            WHERE codigo = @codigoEstadoDefecto;

            IF @idEstadoActivo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001',
                    @p_param1 = 'Estado Estudiante Grupo (A)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Validaciones de reglas de negocio en sub-procedimientos
        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id_interno 
                @idEstudiante = @idEstudianteDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_cupo_disponible_grupo_interno 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_cruce_horario_estudiante_interno 
                @idEstudiante = @idEstudianteDefecto, 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3.8 (CULM-001 A.1, DEC-009): reactivar la matricula retirada (misma fila) si existe.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_internal_reactivar_matricula_retirada
                @idEstudiante = @idEstudianteDefecto,
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @codigoEstadoDestino = @codigoEstadoDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @reactivada = @reactivada OUTPUT;
        END

        IF @estadoResultado = 1 AND @reactivada = 0
        BEGIN
            EXEC dbo.usp_validar_registro_estudiante_en_grupo_interno 
                @idEstudiante = @idEstudianteDefecto, 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Inscripcion en el programa (comun al alta y a la reactivacion) e insercion del alta en dbo.EstudianteGrupo
        IF @estadoResultado = 1 
        BEGIN
            DECLARE @idProgramaGrupo UNIQUEIDENTIFIER;
            SELECT TOP 1 @idProgramaGrupo = pe.programa 
            FROM dbo.Grupo g 
            INNER JOIN dbo.Asignatura a ON g.asignatura = a.id
            -- HU008 (regla de John 2026-10-27): solo una asignatura ESPECIFICA (componente ESP) inscribe al estudiante
            -- en el programa; las transversales (BAS/INS) no crean fila en EstudiantePrograma.
            INNER JOIN dbo.Componente comp ON comp.id = a.componente AND comp.codigo = 'ESP'
            INNER JOIN dbo.SemestrePlanEstudio sp ON a.semestrePlanEstudio = sp.id
            INNER JOIN dbo.PlanEstudio pe ON sp.planEstudio = pe.id
            WHERE g.id = @idGrupoDefecto;

            IF @idProgramaGrupo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @idEstudianteDefecto AND programa = @idProgramaGrupo)
            BEGIN
                INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
                VALUES (NEWID(), @idEstudianteDefecto, @idProgramaGrupo);
            END

            IF @reactivada = 0
            BEGIN
                INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
                VALUES (NEWID(), @idEstadoActivo, @idEstudianteDefecto, @idGrupoDefecto);
            END

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Estudiante en Grupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 1;
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
END;
GO
