USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.8.3, §3.5): tomas cuyo token de asistencia ya debe rotar (uv_token_asistencia_toma.debeRotar = 1).
-- Uso exclusivo del job de rotacion del backend; sin ejecutor (consulta tecnica, sin credenciales). Acotada por
-- ASISTENCIA_QR/LOTE_ROTACION. READ_QUERY_RESULTSET: NON_GOLDEN_PATH_EXTENSION (ver test/test_contract_closure.sql).
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_tomas_qr_por_rotar]
(
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @lote INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'LOTE_ROTACION');
    SET @lote = IIF(@lote IS NULL OR @lote < 1, 200, @lote);

    SELECT TOP (@lote)
        idToma          = v.idToma,
        idGrupo         = v.idGrupo,
        idDocenteEmisor = v.idDocenteEmisor
    FROM dbo.uv_token_asistencia_toma v
    WHERE v.debeRotar = 1
    ORDER BY v.fechaRotacionUtc ASC, v.idToma ASC;
END;
GO
