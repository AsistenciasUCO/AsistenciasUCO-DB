---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-05
---

# VALIDATION — HU159-correccion-identidad-usuarios

| Comando | Resultado |
|---|---|
| Pruebas puntuales en el SQL Server local (`test_usp_corregir_identidad_usuario.sql`, `test_usp_actualizar_coordinador.sql`, `test_usp_actualizar_docente_programa.sql`) | Los 9 marcadores HU159/HU121/HU092/PARAMETER_OFF y las pruebas existentes de HU121 y HU092 en `TEST_PASS` |
| Gate completo en un contenedor SQL Server 2022 limpio, corrida 1 | `DB GATE INCOMPLETE`: `PUBLIC_CANONICAL_RESULTSET usp_corregir_identidad_usuario canonical_columns=7`. El `THROW` de `test_contract_closure.sql` cortó el resto de la suite, de ahí las fallas en cascada |
| Gate completo, corrida 2 (SP en la excepción de resultset con columnas extra, como `usp_actualizar_coordinador`) | `FREEZE_EXIT=0`, `DEPLOY_EXIT=0`, `PASSED=440`, `FAILED=0`, `CRITICAL_MISSING=0`, `DB GATE PASS` |

Ningún manifiesto congelado cambia: sin DDL y sin tocar objetos de LB-004D ni del Golden Path.
