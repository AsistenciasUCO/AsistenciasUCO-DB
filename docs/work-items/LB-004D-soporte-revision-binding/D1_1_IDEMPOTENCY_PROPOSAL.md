# Propuesta al owner DB — D1.1: idempotencia de W2 sin soporte y fecha de solicitud UTC

Estado: **PROPUESTA, no aplicada**. Requiere aprobación del owner DB; la autorización de este trabajo no la sustituye. No se creó ninguna constraint.

## Hallazgos (evidencia: lectura de `usp_radicar_solicitud_revision_asistencia_v2.sql`, E2E real y auditoría local 2026-10-20)
1. Con soporte, W2 es idempotente (misma correlación sobre un `ArchivoSoporte` `ATTACHED` → éxito sin segunda solicitud). **Sin soporte no existe idempotencia**: dos POST con la misma `X-Correlation-Id` crean dos `SolicitudRevisionAsistencia`.
2. `SolicitudRevisionAsistencia.fecha = CAST(CURRENT_TIMESTAMP AS DATE)` usa la zona del servidor SQL (hoy `+00:00`); un reclamo radicado a las 20:00 America/Bogota queda con la fecha del día siguiente. Es DATE civil (semántica v1 documentada), no un instante.
3. El contrato no limita a un reclamo por asistencia; no se propone esa restricción.

## Diff contractual propuesto (aditivo)
```sql
ALTER TABLE dbo.SolicitudRevisionAsistencia ADD
    idCorrelacionRadicacion UNIQUEIDENTIFIER NULL,   -- NULL en histórico
    fechaSolicitudUtc       DATETIME2(7)     NULL;   -- NULL en histórico
CREATE UNIQUE INDEX UX_SolicitudRevision_Asistencia_Correlacion
    ON dbo.SolicitudRevisionAsistencia (asistencia, idCorrelacionRadicacion)
    WHERE idCorrelacionRadicacion IS NOT NULL;
```
W2 v2 (mismos parámetros y resultset de 4 columnas): antes del INSERT, si existe fila con `(asistencia, idCorrelacionRadicacion) = (@idAsistencia, @idCorrelacion)` → `@esReintento = 1` (éxito idempotente). El INSERT guarda `idCorrelacionRadicacion = @idCorrelacionDefecto` y `fechaSolicitudUtc = SYSUTCDATETIME()`. Violación de unicidad por carrera → capturar 2601/2627 y devolver el mismo éxito idempotente.

## Efecto
- Backend: ninguno (ya propaga `X-Correlation-Id` como `@idCorrelacion`). Opcional futuro: exponer `fechaSolicitudUtc` en R2 (columna adicional ⇒ decisión separada, R2 no se fuerza a 4 columnas).
- Frontend: ninguno (ya reutiliza la correlación por intento lógico).
- Datos existentes: intactos (columnas NULL). Rollback: `DROP INDEX` + `DROP COLUMN` (sin datos dependientes hasta que se use).
- Pruebas a añadir en el repo DB: reintento sin soporte (misma correlación ⇒ 1 fila), concurrencia 5×, correlaciones distintas ⇒ 2 filas, rollback.
- Mínimo privilegio: sin cambios de permisos (el rol runtime ya ejecuta W2).

## Decisión que se pide
Aprobar / rechazar / modificar D1.1; independientemente, confirmar la aprobación de D1 (W1/W2/R1/R2 con 4/4/10/25 columnas, ADR-LB004D-001).
