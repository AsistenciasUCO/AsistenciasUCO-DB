USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- F1 (2026-10-30): el COORDINADOR del programa define el horario semanal del grupo (reemplaza todas sus franjas).
-- @horariosJSON: arreglo no vacio de {"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"} (codigos de dbo.Dia).
-- Reglas: formato, dia existente y horaFin > horaInicio (HOR_004); las franjas del grupo no se traslapan entre si,
-- las contiguas si se permiten (HOR_003); el docente titular no tiene otro grupo a la misma hora en el periodo (HOR_002,
-- usp_validar_cruce_horario_docente_interno). Grupo de otro programa: SEC_002. Ninguna regla deja escrituras parciales.
CREATE OR ALTER PROCEDURE [dbo].[usp_guardar_horarios_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @horariosJSON            NVARCHAR(MAX),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignatura             UNIQUEIDENTIFIER;
    DECLARE @idDocente                UNIQUEIDENTIFIER;
    DECLARE @idPrograma               UNIQUEIDENTIFIER;
    DECLARE @idDocenteEjecutor        UNIQUEIDENTIFIER;
    DECLARE @ejecutorEsCoordinador    BIT = 0;
    DECLARE @motivoInvalido           NVARCHAR(200);
    DECLARE @franjaA                  NVARCHAR(100);
    DECLARE @franjaB                  NVARCHAR(100);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;

    DECLARE @franjas TABLE (
        secuencia  INT IDENTITY(1, 1) PRIMARY KEY,
        idDia      UNIQUEIDENTIFIER NULL,
        codigoDia  NVARCHAR(10)     NULL,
        nombreDia  NVARCHAR(50)     NULL,
        horaInicio TIME(0)          NULL,
        horaFin    TIME(0)          NULL
    );

BEGIN
    -- Sin XACT_ABORT ON: con savepoint condenaria la transaccion del llamador (Msg 3930); ver skill procedimientos-externos-condiciones.
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (GEN_002) y perfil COORDINADOR
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'COORDINADOR,DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: El grupo existe (VAL_002) y pertenece al programa que coordina el ejecutor (SEC_002)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idAsignatura = g.idAsignatura, @idDocente = g.idDocente
            FROM dbo.uv_grupo g
            WHERE g.id = @idGrupoDefecto;

            IF @idAsignatura IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002', @p_param1 = 'Grupo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.uv_coordinador_identidad ci WHERE ci.idUsuario = @idUsuarioEjecutorDefecto)
            BEGIN
                SET @ejecutorEsCoordinador = 1;
            END

            SELECT @idDocenteEjecutor = di.id
            FROM dbo.uv_docente_identidad di
            WHERE di.idUsuario = @idUsuarioEjecutorDefecto;
        END

        -- COORDINADOR: titular del programa de la asignatura del grupo
        IF @estadoResultado = 1 AND @ejecutorEsCoordinador = 1
        BEGIN
            SELECT TOP 1 @idPrograma = pe.idPrograma
            FROM dbo.uv_asignatura a
            INNER JOIN dbo.uv_semestre_plan_estudio spe ON a.idSemestrePlanEstudio = spe.id
            INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
            WHERE a.id = @idAsignatura;

            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idPrograma,
                @tipoEntidadPadre = 'PROGRAMA',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- F3 DOCENTE: solo el titular del grupo, y solo para definir el horario inicial (HOR_005); los cambios van por el coordinador
        IF @estadoResultado = 1 AND @ejecutorEsCoordinador = 0
        BEGIN
            IF @idDocenteEjecutor IS NULL OR @idDocenteEjecutor <> @idDocente
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SEC_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF EXISTS (SELECT 1 FROM dbo.uv_horario h WHERE h.idGrupo = @idGrupoDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'HOR_005',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: Formato del horario (HOR_004): arreglo no vacio, solo las 3 claves, dia existente y horaFin > horaInicio
        IF @estadoResultado = 1
        BEGIN
            IF @horariosJSON IS NULL OR ISJSON(@horariosJSON, ARRAY) <> 1 OR NOT EXISTS (SELECT 1 FROM OPENJSON(@horariosJSON))
            BEGIN
                SET @motivoInvalido = N'debe enviar al menos una franja';
            END
            ELSE IF EXISTS (
                SELECT 1
                FROM OPENJSON(@horariosJSON) item
                WHERE item.[type] <> 5
                   OR EXISTS (SELECT 1 FROM OPENJSON(item.value) campo WHERE campo.[key] NOT IN ('codigoDia', 'horaInicio', 'horaFin'))
            )
            BEGIN
                SET @motivoInvalido = N'cada franja lleva solo codigoDia, horaInicio y horaFin';
            END
            ELSE
            BEGIN
                INSERT INTO @franjas (idDia, codigoDia, nombreDia, horaInicio, horaFin)
                SELECT d.id, f.codigoDia, d.nombre, TRY_CAST(f.horaInicio AS TIME(0)), TRY_CAST(f.horaFin AS TIME(0))
                FROM OPENJSON(@horariosJSON)
                    WITH (codigoDia NVARCHAR(10) '$.codigoDia', horaInicio NVARCHAR(20) '$.horaInicio', horaFin NVARCHAR(20) '$.horaFin') f
                LEFT JOIN dbo.uv_dia d ON d.codigo = UPPER(TRIM(f.codigoDia));

                SELECT TOP 1 @motivoInvalido =
                    CASE
                        WHEN idDia IS NULL THEN CONCAT(N'el dia "', codigoDia, N'" no existe')
                        WHEN horaInicio IS NULL OR horaFin IS NULL THEN N'las horas deben tener formato HH:mm'
                        ELSE CONCAT(N'en ', nombreDia, N' la hora de fin debe ser mayor que la de inicio')
                    END
                FROM @franjas
                WHERE idDia IS NULL OR horaInicio IS NULL OR horaFin IS NULL OR horaFin <= horaInicio
                ORDER BY secuencia;
            END

            IF @motivoInvalido IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'HOR_004', @p_param1 = @motivoInvalido,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: Las franjas del grupo no se traslapan entre si (HOR_003); las contiguas se permiten
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @franjaA = CONCAT(a.nombreDia, ' ', CONVERT(CHAR(5), a.horaInicio, 108), '-', CONVERT(CHAR(5), a.horaFin, 108)),
                @franjaB = CONCAT(b.nombreDia, ' ', CONVERT(CHAR(5), b.horaInicio, 108), '-', CONVERT(CHAR(5), b.horaFin, 108))
            FROM @franjas a
            INNER JOIN @franjas b ON b.idDia = a.idDia AND b.secuencia > a.secuencia
            WHERE a.horaInicio < b.horaFin AND a.horaFin > b.horaInicio
            ORDER BY a.secuencia, b.secuencia;

            IF @franjaA IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'HOR_003', @p_param1 = @franjaA, @p_param2 = @franjaB,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 6: Reemplazo atomico de las franjas y cruce del docente titular (HOR_002) sobre el horario nuevo
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
                SAVE TRANSACTION sp_guardar_horarios_grupo;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_guardar_horarios_grupo_interno
                @idGrupo = @idGrupoDefecto,
                @horariosJSON = @horariosJSON,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_validar_cruce_horario_docente_interno
                    @idDocente = @idDocente,
                    @idGrupo = @idGrupoDefecto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_005', @p_param1 = 'Horario del grupo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            -- Rechazo de negocio despues de escribir: se deshace todo lo escrito en este SP
            IF @estadoResultado = 0
            BEGIN
                IF @transaccionPropia = 1
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @transaccionPropia = 0;
                END
                ELSE
                BEGIN
                    ROLLBACK TRANSACTION sp_guardar_horarios_grupo;
                    SET @savepointCreado = 0;
                END
            END
            ELSE IF @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_guardar_horarios_grupo;
        END
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
        estadoResultado         = @estadoResultado;
END;
GO
