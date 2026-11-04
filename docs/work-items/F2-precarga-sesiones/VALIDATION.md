---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-04
---

# VALIDATION — F2: precarga de las sesiones del grupo

## Evidencia ejecutada (2026-11-02, BD local `sql_server_asistencias`)

| Comando | Resultado |
|---|---|
| `./deploy_schema.ps1` | Exit 0 |
| `test/test_usp_precargar_sesiones_grupo.sql` (sqlcmd, solo) | Pasan `PRELOAD_CREATES`, `PRELOAD_IDEMPOTENT`, `PRELOAD_REGENERATE`, `PRELOAD_SCOPE`, `PRELOAD_REQUIRES_SCHEDULE` y `PRELOAD_NO_PAST` |

## Pendiente

- La evidencia de arriba corresponde al código de 2026-11-02. La continuación del 2026-11-04 agrega los casos de preservación, RBAC, períodos variables, permisos runtime y concurrencia, además de una regresión para período vencido. Estos casos todavía no se ejecutan localmente porque el único SQL disponible es la instancia compartida `sql_server_asistencias`; la validación actual debe venir del job oficial `DB Quality Gate` del Draft PR.
- El chequeo local `test_summary.ps1 -ParserSelfTestOnly` aprobó sus diez casos de parser antes de estos cambios; no equivale a ejecutar la suite SQL.
- La integración del Backend ya está presente en `origin/develop`. La prueba de extremo a extremo de navegador queda pendiente: el Backend y Frontend no están activos en los puertos 8080/4200 y los `.env` locales apuntan al realm legado `asistencias-uco` en 8081, mientras el Keycloak activo está en 19090 con el realm `security-baseline`. No se modificaron `.env` ni se autenticó contra otro realm.
- La política de feriados, recesos y suspensiones no está definida en el contrato de este flujo. Actualmente se generan los días semanales configurados dentro del período académico.

## Inventario de la instancia local (solo metadatos, 2026-11-04)

Se inspeccionó únicamente el catálogo de objetos de `gestionasistenciadb` en el contenedor compartido `sql_server_asistencias` (SQL Server Developer, instancia `2f41e9118416`). No se desplegaron scripts ni se consultaron filas de negocio.

| Objeto | Estado | Evidencia |
|---|---|---|
| `dbo.usp_validar_sesion_ventana_registro_interno` | Ausente | Metadatos de objeto SQL Server |
| `dbo.usp_precargar_sesiones_grupo` | Ausente | Metadatos de objeto SQL Server |
| `dbo.usp_precargar_sesiones_grupo_interno` | Ausente | Metadatos de objeto SQL Server |
| `dbo.usp_validar_gestion_grupo_coordinador_o_titular_interno` | Ausente | Dependencia directa del flujo F2 en el código fuente |
| `dbo.usp_resolver_solicitud_revision_asistencia` | Presente, fuente desactualizada | La firma coincide con el código fuente actual (6 parámetros: solicitud, docente, acción, respuesta, correlación y ejecutor), pero el cuerpo local difiere. Definición local normalizada: 14,776 bytes, SHA-256 `1FD4B2790098BDED5D2D42A098F53046ED08B6B80F3285FDDFBD524B6C7FAF64`; fuente actual: 29,036 bytes, SHA-256 `D3B68D17A6BCE55E96FA744A4FC64EE7E0057BEDCF05D70EE2E8D973BD5FC5C2`. |

La suite SQL y la prueba de concurrencia quedan sin ejecutar en local porque faltan objetos requeridos en esa instancia compartida. El resultado autoritativo queda pendiente del job `DB Quality Gate` del Draft PR; no se debe interpretar la evidencia histórica del 2026-11-02 como validación de estos cambios.

## Estado

`PARCIAL`: el cambio está preparado para el gate oficial; la instancia compartida carece de dependencias actuales, falta resultado de CI y queda pendiente una prueba E2E autenticada con un proveedor configurado para este sistema.
