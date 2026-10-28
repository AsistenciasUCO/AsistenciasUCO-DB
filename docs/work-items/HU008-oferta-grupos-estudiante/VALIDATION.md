---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-27
---

# VALIDATION — HU008-oferta-grupos-estudiante

| Comando | Resultado |
|---|---|
| `scripts/freeze-manifest.ps1 -Mode Verify` | exit 0: ningún objeto congelado modificado |
| `deploy_schema.ps1` + `test/prepare_lb004d_fixture.ps1` + `test_summary.ps1` sobre SQL Server 2022 limpio (réplica del job `DB Quality Gate CI/CD`), 2026-10-27 | `TEST_PASS:HU008_OFERTA_*` (5), `TEST_PASS:HU008_RI01..RI03` y `TEST_PASS:S-01..S-12` (regresión de HU053-055). `TOTAL_EXECUTED=348`, `FAILED=0`, `CRITICAL_MISSING=0`, `DB GATE PASS`, exit 0 |
| `scripts/maintenance/hu008_depurar_estudiante_programa_transversales.sql` con `@soloConteo = 1` en la BD local de John | `HU008_DEPURACION_CANDIDATAS=0` (`EstudiantePrograma` local = 0 filas). No hubo borrado. |
| GitHub Actions `DB Quality Gate CI/CD` | Pendiente: la rama está en commits locales, sin subir |

## Incidencia corregida durante la validación

La primera corrida tuvo `FAILED=1`. La prueba de regresión no borraba las tablas temporales `#r` y `#rx`, que siguen vivas entre lotes de `sqlcmd`, y por eso la prueba siguiente (`test_usp_vincular_docente_programa`) falló al crearlas. Se corrigió con `DROP TABLE IF EXISTS` al final de la prueba.

## Desviación

Las pruebas se escribieron junto con el código, sin un commit RED separado.

## Limitación

La prueba manual en pantalla queda pendiente (MV-008).
