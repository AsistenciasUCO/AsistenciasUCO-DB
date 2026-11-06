# PR — SES-04 (DB): reclamo aprobado deja la asistencia JUSTIFICADA (EX, asistio = 0)

**Base:** `develop` · **Rama:** `fix/ses04-reclamo-justificada` · **Orden:** 1/3 (DB → Backend → Frontend). Independiente de SES-01.

## Alcance
`usp_resolver_solicitud_revision_asistencia`: la aprobación cambia la causal a `EX` con `asistio = 0` (antes ponía `asistio = 1` y dejaba SJC); el rechazo no toca la asistencia. Acciones exactas, una sola rectificación (bloqueo + solo pendientes), reintento idempotente, decisión contradictoria rechazada, auditoría oficial con estado previo y nuevo.

## Contrato
Firma y resultset de 4 columnas sin cambio. Nuevos mensajes `REV_001` acción inválida, `REV_002` ya resuelto con otra decisión, `REV_003` presencia no justificable, `REV_004` sin detalle, `REV_005` inexistente (antes `VAL_002`). `VAL_007` (no titular) se conserva.

## Pruebas
`test/test_ses04_reclamo_justificada.sql` (11 IDs). `REVIEW_RESOLVE_SUCCESS` corregido (afirmaba el defecto) y REC3 TX-02 reapuntado a la nueva escritura. Local: PARSEONLY PASS; suite **NOT_RUN** local (política del entorno) → **certifica el CI de este PR**.

## Excepción de congelamiento
El SP no está congelado; los cambios de SP de SES-01..05 están autorizados expresamente por el responsable del proyecto (2026-11-03). **@johnjduque: se solicita revisión como owner DB.**

## Despliegue / reversión
Mecanismo oficial (SP + filas `REV_001..005`). Reversión con `CREATE OR ALTER` de la versión anterior. Rectificaciones históricas hechas con la versión anterior no se migran aquí (requiere decisión, SES-05).

## Dependencias
Backend `fix/ses04-reclamo-justificada` (400/404/409 para `REV_00x`) y Frontend `fix/ses04-reclamo-justificada`.
