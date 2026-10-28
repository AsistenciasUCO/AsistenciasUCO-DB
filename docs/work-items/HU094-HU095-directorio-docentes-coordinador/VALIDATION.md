---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-27
---

# VALIDATION — HU094-HU095-directorio-docentes-coordinador

| Comando | Resultado |
|---|---|
| `scripts/freeze-manifest.ps1 -Mode Verify` | exit 0: ningún objeto congelado se modificó |
| `deploy_schema.ps1` + `test/prepare_lb004d_fixture.ps1` + `test_summary.ps1` sobre SQL Server 2022 limpio (réplica del job `DB Quality Gate CI/CD`), 2026-10-27 | `TEST_PASS:HU094_HISTORIAL_*` (6), `TEST_PASS:HU095_RESUMEN_*` (3), `PUBLIC_SP_MISSING=0`, `TOTAL_EXECUTED=349`, `FAILED=0`, `DB GATE PASS`, exit 0 |
| GitHub Actions `DB Quality Gate CI/CD` | pendiente: rama sin subir (commits locales) |

**Desviación del proceso:** las pruebas se escribieron junto con los SP, sin un commit RED separado. El fallo esperado sin los SP es "objeto inexistente".

**Limitación:** la prueba manual en pantalla queda pendiente (MV-008).
