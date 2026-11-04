---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-04
---

# VALIDATION — HU058-HU155-catalogos-consulta

| Comando | Resultado |
|---|---|
| T-155-01 (`test_consolidado_auditoria_catalogos.sql`) en el SQL Server local | `TEST_PASS` |
| Gate completo en un contenedor SQL Server 2022 limpio (corridas 1 a 3) | `DB GATE INCOMPLETE`: `SES01_AUTO_CLOSED` marcado como faltante, aunque la prueba imprimió `TEST_STATE_PASS`. Bytes sueltos de sqlcmd (`N`) al inicio de la línea del marcador TECH |
| Gate completo tras el `PRINT '';` en `test_ses01_ventana_asistencia.sql` | `TOTAL_EXECUTED=432`, `PASSED=431`, `FAILED=0`, `SKIPPED=1` (permitido), `CRITICAL_MISSING=0`, `DB GATE PASS`. En el log, el `N` cae en la línea vacía |
