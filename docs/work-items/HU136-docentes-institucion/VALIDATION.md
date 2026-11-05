---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-05
---

# VALIDATION — HU136-docentes-institucion

| Comando | Resultado |
|---|---|
| `test_consultas_transversales_hu112_hu157.sql` en el SQL Server local | T-128-01, el nuevo T-136-01 y el ajuste T-136-02 (docentes sin vínculo) (`HU136_ADMIN_TEACHERS_INSTITUTION`) en `TEST_PASS` |
| Gate completo en un contenedor SQL Server 2022 limpio | `FREEZE_EXIT=0`, `DEPLOY_EXIT=0`, `TOTAL_EXECUTED=442`, `PASSED=441`, `FAILED=0`, `CRITICAL_MISSING=0`, `DB GATE PASS` |
