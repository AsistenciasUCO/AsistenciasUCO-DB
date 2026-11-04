---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-03
---

# VALIDATION — SES-01 (DB)

Rama `fix/ses01-cierre-estricto-asistencia`. Commits: `f1ff9d6` (RED), `99c3649` (fix), `af00b7c` (docs).

| Verificación | Comando / medio | Resultado |
|---|---|---|
| Sintaxis T-SQL de los 3 SP, seed de mensajes, prueba nueva, prueba de asistencia y fixture Java | `SET PARSEONLY ON` vía `sqlcmd` en `sql_server_asistencias` (no compila ni ejecuta; no modifica la base) | PASS (exit 0, sin errores) |
| Manifiesto de congelamiento | `./scripts/freeze-manifest.ps1 -Mode Verify` | PASS: `FREEZE_MANIFEST_OK entries=10 post_freeze_superseded=4 post_freeze_work_item=11` |
| Suite DB completa (`test_summary.ps1`, incluye 12 IDs `SES01_*` y la regresión de asistencia) | CI del PR (contenedor efímero de GitHub Actions: `deploy_schema.ps1` + `test_summary.ps1`) | **NOT_RUN** localmente; pendiente del CI |
| Ejecución local de la suite contra `sql_server_asistencias` | — | **NOT_RUN**: requiere desplegar los SP en la base compartida; un intento de despliegue transitorio (transacción con `ROLLBACK`) fue bloqueado por la política de permisos. El cambio no se aplica hasta la aprobación del owner DB |
| Carrera en el instante de cierre entre dos conexiones | — | **NOT_RUN** como prueba ejecutable; garantizado por diseño (validación bajo `UPDLOCK, HOLDLOCK` dentro de la transacción y revalidación antes del `COMMIT`); `SES01_WINDOW_LOCK_HELD` verifica el bloqueo |

Limitaciones: `PARSEONLY` no valida nombres de objetos ni semántica. La validación funcional real es el gate del CI.
