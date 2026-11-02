---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-02
---

# VALIDATION — F2: precarga de las sesiones del grupo

## Evidencia ejecutada (2026-11-02, BD local `sql_server_asistencias`)

| Comando | Resultado |
|---|---|
| `./deploy_schema.ps1` | Exit 0 |
| `test/test_usp_precargar_sesiones_grupo.sql` (sqlcmd, solo) | Pasan `PRELOAD_CREATES`, `PRELOAD_IDEMPOTENT`, `PRELOAD_REGENERATE`, `PRELOAD_SCOPE`, `PRELOAD_REQUIRES_SCHEDULE` y `PRELOAD_NO_PAST` |

## Pendiente

- **Gate completo (`test_summary.ps1`):** lo confirmará el job "DB Quality Gate" del PR; en la BD local la suite se corta antes por objetos viejos sin borrar (migraciones 08 y 09).
- Integración con el backend (alta y edición del grupo) y prueba manual.
- Asistencia ya registrada: la protección contra el borrado de sesiones con asistencia se probó por diseño (`NOT EXISTS` sobre `Asistencia`) y no con un caso propio; conviene agregarlo en la prueba manual.

## Estado

`PARCIAL`: BD lista y probada en local; falta el gate completo en CI, el backend y la prueba manual.
