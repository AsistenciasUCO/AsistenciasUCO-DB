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
2. SonarCloud requiere `SONAR_TOKEN` desde GitHub Secrets. La organización y la
   clave de proyecto se leen de `sonar-project.properties`, que conserva la
   configuración oficial `johnjduque` / `johnjduque_gestion-asistencia-db`;
   el workflow no exige variables vacías `SONAR_ORGANIZATION` ni
   `SONAR_PROJECT_KEY`.
3. El resumen CI debe reflejar TOTAL_EXPECTED, TOTAL_EXECUTED, PASSED,
   FAILED y SKIPPED emitidos por test_summary.ps1.
4. El análisis debe ejecutarse sin `continue-on-error` y esperar el Quality Gate;
   un análisis omitido se reporta como `NOT_RUN` y falla la verificación crítica.

## Definition of Ready

## Addendum de cierre P0 autorizado — 2026-10-18

La autorización explícita de cierre de P0 permite, dentro de este mismo work
item y sin crear una fase nueva, corregir el contrato ya identificado de
`usp_crear_facultad` HU116 y sus pruebas/fixtures directamente asociados. El
alcance queda limitado a:

- `schema/stored-procedures/usp_crear_facultad.sql`;
- `test/test_usp_crear_facultad.sql`, `test_suite.sql` y
  `test_summary.ps1` para ejecutar y contabilizar el caso;
- `scripts/secret-hygiene.ps1` para corregir el falso positivo del gate sin
  reducir su protección.

El cambio no introduce migraciones, no modifica el resultado público canónico
de cuatro columnas, no cambia otros procedimientos ni datos persistentes, y
no autoriza merge hasta contar con la suite CI completa y revisión del owner DB.
