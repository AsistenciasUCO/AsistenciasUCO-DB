USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B: ventana de matricula con sus datos de presentacion. NO expone tokenHash ni tokenHashAnterior.
-- estaVigente: ventana ACTIVA que no ha llegado a su fin. debeRotar: vigente y ya transcurrio ROTACION_SEGUNDOS
-- desde la ultima rotacion (D2). Los valores de estado y los tiempos salen de los parametros MATRICULA_QR/*.
CREATE OR ALTER VIEW [dbo].[uv_token_matricula_grupo]
AS
SELECT  id                 = t.id,
        grupo              = t.grupo,
        docenteEmisor      = t.docenteEmisor,
        pin                = t.pin,
        pinAnterior        = t.pinAnterior,
        estado             = t.estado,
        fechaEmisionUtc    = t.fechaEmisionUtc,
        fechaRotacionUtc   = t.fechaRotacionUtc,
        fechaExpiracionUtc = t.fechaExpiracionUtc,
        fechaCierreUtc     = t.fechaCierreUtc,
        totalMatriculas    = t.totalMatriculas,
        estaVigente        = IIF(t.estado = p.estadoActiva AND SYSUTCDATETIME() < t.fechaExpiracionUtc, 1, 0),
        debeRotar          = IIF(t.estado = p.estadoActiva
                                 AND SYSUTCDATETIME() < t.fechaExpiracionUtc
                                 AND SYSUTCDATETIME() >= DATEADD(SECOND, p.rotacionSegundos, t.fechaRotacionUtc), 1, 0),
        nombreAsignatura   = vg.nombreAsignatura,
        nombreGrupo        = vg.nombre,
        nombreDocente      = CONCAT(u.primerNombre, N' ', u.primerApellido),
        cupoDisponible     = vg.cuposDisponibles
FROM    dbo.TokenMatriculaGrupo t
INNER JOIN dbo.uv_grupo vg ON vg.id = t.grupo
INNER JOIN dbo.Docente d   ON d.id = t.docenteEmisor
INNER JOIN dbo.Usuario u   ON u.id = d.usuario
CROSS APPLY (
    SELECT estadoActiva     = CAST(dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA') AS NVARCHAR(10)),
           rotacionSegundos = dbo.ufn_obtener_parametro_int(NULL, 'MATRICULA_QR', 'ROTACION_SEGUNDOS')
) p;
GO
