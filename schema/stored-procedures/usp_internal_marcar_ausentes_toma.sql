USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_marcar_ausentes_toma (CULM-001 B.2; CONTRACT §2.8.2, DEC-013) - NUCLEO, no se concede EXECUTE.
--
-- Inserta, en conjunto (sin iterar estudiante por estudiante), un detalle SJC en la toma para cada matricula ACTIVA
-- (MATRICULA/ESTADO_INSCRITA) del grupo que no tiene detalle en ella; crea antes la cabecera Asistencia que falte.
-- registradoPorEstudiante = 0 y fechaRegistroUtc = @fechaRegistroUtc (= fechaCierreUtc de la toma: asi uv_faltantes_toma
-- reconoce el SJC marcado al cerrar). Nunca sobrescribe un detalle existente. No abre transaccion: la del llamador, que ya
-- tiene bloqueadas la sesion y la toma. Codigo desde dbo.seq_detalle_asistencia_codigo.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_marcar_ausentes_toma]
(
    @idToma           UNIQUEIDENTIFIER,
    @idSesion         UNIQUEIDENTIFIER,
    @idGrupo          UNIQUEIDENTIFIER,
    @fechaRegistroUtc DATETIME2(0),
    @totalMarcados    INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @codigoActiva NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @codigoSjc    NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'CODIGO_RAZON_SIN_JUSTA_CAUSA') AS NVARCHAR(10));
    DECLARE @idRazonSjc   UNIQUEIDENTIFIER = (SELECT rc.id FROM dbo.RazonCausa rc WHERE rc.codigo = @codigoSjc);
    SET @totalMarcados = 0;

    IF @idRazonSjc IS NULL OR @codigoActiva IS NULL
        THROW 52520, 'CULM001_B2_CATALOGO_INCONSISTENTE: ASISTENCIA/CODIGO_RAZON_SIN_JUSTA_CAUSA o MATRICULA/ESTADO_INSCRITA no resuelven.', 1;

    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
    SELECT NEWID(), eg.id, @idSesion
    FROM dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN dbo.EstadoEstudianteGrupo e ON e.id = eg.estado AND e.codigo = @codigoActiva
    WHERE eg.grupo = @idGrupo
      AND NOT EXISTS (SELECT 1 FROM dbo.Asistencia a WITH (UPDLOCK, HOLDLOCK) WHERE a.estudianteGrupo = eg.id AND a.sesion = @idSesion);

    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma,
                                       registradoPorEstudiante, fechaRegistroUtc)
    SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, a.id, 0, @idRazonSjc, s.fechaHoraInicio, s.fechaHoraFin, @idToma,
           0, @fechaRegistroUtc
    FROM dbo.Asistencia a
    INNER JOIN dbo.EstudianteGrupo eg ON eg.id = a.estudianteGrupo
    INNER JOIN dbo.EstadoEstudianteGrupo e ON e.id = eg.estado AND e.codigo = @codigoActiva
    INNER JOIN dbo.Sesion s ON s.id = a.sesion
    WHERE a.sesion = @idSesion
      AND eg.grupo = @idGrupo
      AND NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia da WITH (UPDLOCK, HOLDLOCK) WHERE da.asistencia = a.id AND da.toma = @idToma);

    SET @totalMarcados = @@ROWCOUNT;
END;
GO
