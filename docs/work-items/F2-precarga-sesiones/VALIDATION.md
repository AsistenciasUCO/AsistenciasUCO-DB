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

## Evidencia CI (PR #83, commit `c98ab41e5cd1a9b99b28cd078bf48173595452ba`)

El job `Database Deployment & Quality Gate` completó con `failure` el 2026-11-04. El despliegue del esquema y el manifiesto pasaron; `test_summary.ps1` reportó 310 pases, 4 errores SQL, 60 críticos ausentes y el fallo del probe de concurrencia. Los ausentes posteriores a F2 son cascada del error de compilación del batch F2, no una serie de regresiones independientes.

| Falla del primer run | Causa raíz | Corrección |
|---|---|---|
| `Msg 102: Incorrect syntax near '+'` (4 errores) | Cuatro argumentos `@codigo` de `EXEC dbo.usp_crear_grupo` contenían sumas inline, sintaxis no admitida en esos argumentos. El batch de prueba F2 no compiló, por lo que no imprimió sus tokens y dejó críticos posteriores ausentes. | Calcular los cuatro códigos de grupo en variables antes de las llamadas y pasar esas variables. |
| `PRELOAD_CONCURRENT_IDEMPOTENT`: `sqlcmd ... worker.sql: Invalid filename` | El helper escribió el archivo worker local, pero no lo copió ni habilitó lectura en el contenedor antes de lanzar los dos jobs. | Copiar el worker al contenedor y habilitar lectura antes de iniciar los procesos concurrentes. |

La segunda ejecución de CI, para el commit `ad9f03e7c0d1b039b29d8597b7418d301cc5bc0f`, confirmó que la compilación SQL y la prueba de concurrencia ya pasan (`PRELOAD_CONCURRENT_IDEMPOTENT`). El gate sigue fallando porque el fixture RBAC buscaba en el seed una asignatura de otro programa, pero el seed CI contiene uno solo. El test abortó antes de emitir los tokens F2: 311 pruebas pasaron, hubo 1 error SQL y 59 críticos quedaron ausentes como cascada. La corrección en curso crea dentro de la transacción de prueba un coordinador y programa ajenos, y prueba al actor contra el grupo del programa titular. No se repitió contra SQL local compartido.

## Pendiente

- La evidencia de arriba corresponde al código de 2026-11-02. La continuación del 2026-11-04 agrega los casos de preservación, RBAC, períodos variables, permisos runtime y concurrencia, además de una regresión para período vencido. Los primeros dos defectos están corregidos y pasan en CI; el nuevo fixture RBAC debe confirmarse en el siguiente `DB Quality Gate`.
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

`PARCIAL`: el segundo `DB Quality Gate` falló por la dependencia del seed en el test RBAC; el fixture autocontenido está en preparación. Falta el siguiente resultado de CI. La instancia compartida carece de dependencias actuales y queda pendiente una prueba E2E autenticada con un proveedor configurado para este sistema.
