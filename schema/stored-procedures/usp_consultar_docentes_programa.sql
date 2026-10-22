USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_docentes_programa (HU062 / HU089 / HU063)
--
-- Resultset: READ_QUERY_RESULTSET (filas de uv_auth_docente_programa + totalRegistros). NO es un
-- MUTATION_COMMAND_RESULTSET. Las fallas de RBAC/titularidad se propagan con THROW (mensaje tecnico
-- de catalogo, que lleva el codigo para el clasificador del backend).
-- Solo lectura: sin XACT_ABORT (las fallas se propagan con THROW sin condenar la transaccion del llamador).
-- Paginacion normalizada (pagina >= 1, tamano 1..100) igual que usp_consultar_grupos_paginado.
-- Busqueda: solo digitos => prefijo de numeroIdentificacion; en otro caso => contiene en nombreCompleto.
-- SESSION_CONTEXT se aplica solo durante la consulta y SIEMPRE se restaura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_docentes_programa]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPrograma         UNIQUEIDENTIFIER,
    @numeroPagina       INT              = 1,
    @tamanoPagina       INT              = 10,
    @busqueda           NVARCHAR(50)     = NULL,
    @estaActivo         BIT              = NULL,
    @idTipoVinculacion  UNIQUEIDENTIFIER = NULL,
    @idDocente          UNIQUEIDENTIFIER = NULL,
    @idUsuario          UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    DECLARE @texto NVARCHAR(50) = NULLIF(TRIM(@busqueda), '');
    DECLARE @textoEscapado NVARCHAR(110) = REPLACE(REPLACE(REPLACE(@texto, '\', '\\'), '%', '\%'), '_', '\_');
    DECLARE @soloDigitos BIT = IIF(@texto IS NOT NULL AND @texto NOT LIKE '%[^0-9]%', 1, 0);
    DECLARE @patron NVARCHAR(120) = IIF(@texto IS NULL, NULL, IIF(@soloDigitos = 1, CONCAT(@textoEscapado, '%'), CONCAT('%', @textoEscapado, '%')));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @contextoPrevio SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioDefecto,
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioDefecto,
                @idEntidadPadre = @idProgramaDefecto,
                @tipoEntidadPadre = 'PROGRAMA',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @idUsuarioDefecto;

        SELECT
            d.idDocentePrograma, d.idDocente, d.idUsuario,
            d.idTipoIdentificacion, d.codigoTipoIdentificacion, d.numeroIdentificacion,
            d.primerNombre, d.segundoNombre, d.primerApellido, d.segundoApellido,
            d.nombreCompleto, d.correo,
            d.idPrograma, d.nombrePrograma, d.idFacultad, d.nombreFacultad, d.idInstitucion,
            d.idTipoVinculacion, d.codigoTipoVinculacion, d.nombreTipoVinculacion,
            d.fechaVinculacionUtc, d.estaActivoVinculacion, d.estaActivoUsuario, d.estaActivoDocentePrograma,
            d.totalGruposPrograma,
            COUNT(*) OVER() AS totalRegistros
        FROM dbo.uv_auth_docente_programa d
        WHERE d.idPrograma = @idProgramaDefecto
          AND (@estaActivo IS NULL OR d.estaActivoDocentePrograma = @estaActivo)
          AND (@idTipoVinculacion IS NULL OR d.idTipoVinculacion = @idTipoVinculacion)
          AND (@idDocente IS NULL OR d.idDocente = @idDocente)
          AND (@idUsuario IS NULL OR d.idUsuario = @idUsuario)
          AND (
                @patron IS NULL
                OR (@soloDigitos = 1 AND CAST(d.numeroIdentificacion AS NVARCHAR(12)) LIKE @patron ESCAPE '\')
                OR (@soloDigitos = 0 AND d.nombreCompleto LIKE @patron ESCAPE '\')
              )
        ORDER BY d.nombreCompleto ASC, d.idDocente ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
        THROW;
    END CATCH;
END;
GO
