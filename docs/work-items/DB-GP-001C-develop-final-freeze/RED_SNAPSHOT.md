# DB-GP-001C - RED snapshot

Contexto: HEAD `c30ecc56a070ae9c9de01e02b2f3f43f6a474abd` desplegado en un SQL Server 2022 efimero (contenedor temporal, base nueva); tests/gates nuevos aplicados **antes** de cambiar el codigo de produccion. Los tests no se editaron despues para acomodar la produccion.

## Baseline previo (gate historico del mismo HEAD, sin tests nuevos)

```text
TOTAL_EXPECTED=131  TOTAL_EXECUTED=138  PASSED=137  FAILED=0  SKIPPED=1  @@TRANCOUNT=0  DB GATE PASS
NO_HARDCODED_DB_PASSWORD: PASS   <- el gate viejo NO detectaba el secreto de .env.template
```

## RED (tests nuevos contra codigo actual)

```text
test_authorized_views_rbac.sql
  Msg 52011 TEST FAILED: definicion uv_auth_* no es fail-closed (IS NULL bypass o falta IS NOT NULL / herencia).
  Msg 52001 TEST FAILED: contexto NULL debe retornar 0 filas; uv_auth_coordinador retorno 1.
  TEST_PASS:RBAC_UNKNOWN_CONTEXT_NO_ROWS            (UUID desconocido ya era 0 filas: se conserva como regresion)
  TEST_PASS:RBAC_*_ISOLATION (admin/decano/coord/docente/estudiante)  (alcance por rol ya correcto)

test_usp_consultar_grupos_paginado.sql
  TEST_PASS:..._CONTEXT_CLEANUP                     (previo NULL => NULL)
  Msg 51308 TEST FAILED: el contexto previo (A) no fue restaurado tras la consulta.   <- SP dejaba NULL

test_golden_path_immutability.sql
  TEST_PASS:GOLDEN_PATH_VIEW_SHAPES_FROZEN / SP_SIGNATURES_FROZEN / MUTATION_RESULTSET_FROZEN   (linea base correcta)

test_summary.ps1 (suite completa; sqlcmd -b aborta en el primer error SQL)
  TOTAL_EXPECTED=151  TOTAL_EXECUTED=135  PASSED=131  FAILED=3  CRITICAL_MISSING=20  SQL_ERROR_COUNT=1  => DB GATE INCOMPLETE (exit 1)
  RESULT_FAILURES=NO_HARDCODED_DB_PASSWORD hits=.env.template:11:HARDCODED_PASSWORD_LITERAL
  GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED: falla (manifest aun no existia)
```

El Caso C (excepcion) queda cubierto por la misma causa raiz (el SP asignaba NULL en el CATCH) y pasa a GREEN con el fix; en RED la suite se detiene antes en el Caso B.

Causales RED demostrados: (1) NULL => acceso total (uv_auth_coordinador, y por inspeccion de definicion las 8 directas); (2) contexto previo destruido; (3) secreto en `.env.template` no detectado por el gate viejo y detectado por el nuevo (file:line:type, sin valor).
