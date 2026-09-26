# DB-GP-001C - Validation

Entorno: SQL Server 2022 Developer en **contenedor efimero** (no se toco `sql_server_asistencias` ni ninguna base de desarrollo). Password generado al azar, pasado por parametro; nunca impreso ni versionado.

```text
COMMIT_DEPLOYED: dcc69f19ffe3c246b78fa1996299ad97df229bbf
DATABASE: gestionasistenciadb (contenedor temporal, removido al terminar)
FRESH  (DROP DATABASE + deploy_schema.ps1): 2026-09-26T21:58:28Z  deploy exit 0  gate exit 0
REDEPLOY same DB (idempotencia):           2026-09-26T22:00:02Z  deploy exit 0  gate exit 0
```

## Quality gate (identico en FRESH y REDEPLOY)

```text
TOTAL_EXPECTED=151
TOTAL_EXECUTED=152
PASSED=151
FAILED=0
SKIPPED=1   (XACT_STATE_MINUS_ONE_RUNTIME, unico skip autorizado; UNAUTHORIZED_SKIPS=0)
CRITICAL_MISSING=0  SQLCMD_EXIT_CODE=0  SQL_ERROR_COUNT=0
@@TRANCOUNT=0
DB GATE PASS
```

Baseline previo al hardening: 131 esperados / 138 ejecutados / 137 pasados / 1 skip. Los +20 esperados son los gates nuevos (RBAC, restauracion de contexto, inmutabilidad Golden Path, secret gate, manifest).

## RBAC / contexto

```text
NULL auth context (12 vistas):        0 rows
unknown context (12 vistas):          0 rows
ADMIN / DECANO / COORDINADOR / DOCENTE / ESTUDIANTE: alcance exacto, sin fugas (PASS)
usuario inactivo: sin alcance mayor que su institucion (PASS)
context restored: YES (previo NULL, previo A, y ante excepcion)
context leaked: NO (0)
```

## Golden Path

Shapes de `uv_horario_docente`, `uv_sesion`, `uv_estudiante_grupo`, `uv_asistencia`, `uv_detalle_asistencia` y firmas de `usp_crear_sesion`, `usp_actualizar_sesion`, `usp_generar_sesiones_grupo`, `usp_registrar_asistencias_sesion`: sin cambios (gate + manifest). Los tests Golden Path existentes (sesion create/update, generacion, comandos y revision de asistencia, ownership transaccional, cierre de contrato, objetos publicos, upsert concurrente, reglas temporales) pasan en el mismo gate.

```text
git diff c30ecc5 HEAD -- <5 vistas + 4 SP Golden Path> : vacio
DB_BASELINE_CONTRACT.md sha256 = 45e48c5a0ab321d0c8cbffb55ee224e3b6fd29febc39a62ca723b2b209945aec (UNCHANGED)
```

## Precheck de duplicados (read-only, base limpia)

```text
Asistencia(estudianteGrupo, sesion)  0
DetalleAsistencia(asistencia)        0
RazonCausa(codigo)                   0
```

## Secretos

```text
SECRET_TEMPLATE: SAFE (.env.template y .env.example = placeholder CHANGE_ME; los scripts rechazan CHANGE_ME como password)
NO_HARDCODED_DB_PASSWORD: PASS (deploy_schema.ps1, test_summary.ps1, .github/workflows/**, .env.template, .env.example, .vscode/settings.json, sonar-project.properties, scripts/**, config versionada)
REAL_SECRET_FOUND (worktree/staged): 0
SECRET_WAS_PRESENT_IN_HISTORY: YES     ROTATION_REQUIRED: YES (operacional, fuera del repo)
CI_SECRET_CONFIGURATION: EXTERNAL_PRECONDITION
```

Historial: no reescrito, sin force push. El valor estuvo en `.env.template`/`deploy_schema.ps1` en commits previos (y aparece en el texto de un mensaje de commit previo); no se imprime aqui. Quien administra el ambiente debe rotar esa credencial si se uso en algun entorno real. El workflow exige `secrets.MSSQL_SA_PASSWORD` (GitHub secret); desde el codigo no se puede certificar que exista, por lo que el CI no se marca PASS solo por el YAML.
