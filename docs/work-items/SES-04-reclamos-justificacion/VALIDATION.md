---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-03
---

# VALIDATION — SES-04 (DB)

Commits: `5ab6a44` (RED), `d8fc1c7` (fix).

| Verificación | Resultado |
|---|---|
| `SET PARSEONLY ON` del SP, seed de mensajes, prueba nueva, `test_attendance_review.sql`, `test_rec3_falla_intermedia_transaccion.sql` | PASS (exit 0) |
| Suite DB completa (`test_summary.ps1`, incluye 11 IDs `SES04_*`) | **NOT_RUN** localmente; certificación en el CI del PR |
| Ejecución local en `sql_server_asistencias` | **BLOCKED** por la política de permisos del entorno (despliegue de SP en la instancia compartida, incluso transitorio con ROLLBACK). Falta: una regla de permiso del usuario o el despliegue por el mecanismo oficial |
| Concurrencia entre dos conexiones (aprobación/rechazo simultáneos) | **NOT_RUN** como prueba ejecutable; garantizada por `UPDLOCK, HOLDLOCK` sobre la solicitud dentro de la transacción y la regla "solo P se resuelve" |
