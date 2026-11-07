USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_validar_solape_sesion_interno (CULM-001 A.2-10; F-DOC-017; CONTRACT §8.2.3 A2-DB-2)
--
-- Interno (DENY EXECUTE al runtime). Rechaza con SES_017 una sesion [@fechaHoraInicio, @fechaHoraFin) que se cruce con
-- otra sesion (s.fechaHoraInicio < @fechaHoraFin AND s.fechaHoraFin > @fechaHoraInicio; los bordes iguales NO solapan)
-- del MISMO grupo o de OTRO grupo del mismo docente (Grupo.docente del grupo), excluida @idSesionExcluir (la propia
-- sesion al actualizar). Lee con UPDLOCK, HOLDLOCK las sesiones de los grupos del docente para serializar creaciones
-- concurrentes: lo llaman usp_crear_sesion_interno y usp_actualizar_sesion_interno DENTRO de su transaccion, antes de
-- escribir. No escribe. Cuando B introduzca SesionCancelacion (DEC-016), debera excluir las sesiones canceladas.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_solape_sesion_interno]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idSesionExcluir         UNIQUEIDENTIFIER = NULL,
    @fechaHoraInicio         DATETIME2,
    @fechaHoraFin            DATETIME2,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocente            UNIQUEIDENTIFIER;
    DECLARE @idSesionConflicto    UNIQUEIDENTIFIER;
BEGIN
    SET NOCOUNT ON;

    SELECT @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @estadoResultado = 1;

    BEGIN TRY
        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: sesion del mismo grupo o de otro grupo del mismo docente que se cruce (bordes iguales no solapan)
        IF @estadoResultado = 1 AND @fechaHoraInicio IS NOT NULL AND @fechaHoraFin IS NOT NULL
        BEGIN
            SELECT @idDocente = g.docente FROM dbo.Grupo g WHERE g.id = @idGrupo;

            SELECT TOP 1 @idSesionConflicto = s.id
            FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Grupo g ON g.id = s.grupo
            WHERE (s.grupo = @idGrupo OR (@idDocente IS NOT NULL AND g.docente = @idDocente))
              AND s.fechaHoraInicio < @fechaHoraFin
              AND s.fechaHoraFin > @fechaHoraInicio
              AND (@idSesionExcluir IS NULL OR s.id <> @idSesionExcluir)
            ORDER BY s.fechaHoraInicio, s.id;

            IF @idSesionConflicto IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_017',
                    @p_param1 = @idSesionConflicto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
    END TRY
    BEGIN CATCH
        IF XACT_STATE() = -1
            THROW;
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
