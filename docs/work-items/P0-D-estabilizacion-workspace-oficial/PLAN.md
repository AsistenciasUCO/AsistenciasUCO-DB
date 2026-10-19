---
status: active
type: normative
scope: database-ci-preparation
owner: database-team
last-reviewed: 2026-10-18
---

# P0-D — Preparación CI del workspace oficial DB

## Objetivo

Preparar el repositorio DB oficial para que su quality gate sea reproducible y no
oculte fallos de configuración. Esta fase no cambia schema, migraciones,
procedimientos, vistas, fixtures ni datos.

## Fuentes

- AGENTS.md
- docs/contracts/DB_BASELINE_CONTRACT.md
- test_summary.ps1
- .github/workflows/ci.yml

## Clase y alcance

- Clase: CI_WORKFLOW_HARDENING y DOCUMENTATION_ONLY.
- Permitido: .github/workflows/ci.yml, run_local_env.ps1,
  sonar-project.properties y este work item.
- Prohibido: schema/**, migrations/**, test_suite.sql, test/**,
  despliegue, cambios de ramas oficiales, push, merge, contenedores o datos.

## Cambios autorizados

1. El password SQL debe venir de un secret/entorno explícito; no existe fallback
   hardcodeado.
2. SonarCloud requiere SONAR_TOKEN, SONAR_ORGANIZATION y
   SONAR_PROJECT_KEY; si faltan, el job debe fallar de forma explícita.
3. El resumen CI debe reflejar TOTAL_EXPECTED, TOTAL_EXECUTED, PASSED,
   FAILED y SKIPPED emitidos por test_summary.ps1.
4. La configuración de Sonar no conserva una organización personal como source
   of truth del repositorio.

## Definition of Ready
