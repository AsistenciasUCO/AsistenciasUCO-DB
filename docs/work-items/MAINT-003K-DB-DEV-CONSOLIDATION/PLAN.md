---
status: VALIDATED_LOCAL_DEV
type: work-item
scope: db
work_item: MAINT-003K-DB-DEV-CONSOLIDATION
date: 2026-10-10
---

# MAINT-003K-DB-DEV-CONSOLIDATION — rama SQL consolidada y DB de desarrollo reconstruida desde Git

## Identidad y objetivo

- Rama: `feat/maint-003k-db-dev-consolidation`, creada desde `origin/feat/cc-003g-01-public-user-plan-providers` (`3f6afec`),
  que ya incorpora UTC-D06 (`6946a73`), el endurecimiento de permisos (`3842f70`) y CC-003G-01 (`f64abb6`..`3f6afec`).
- Objetivo: una sola DB principal de desarrollo, `gestionasistenciadb` en el contenedor `sql_server_asistencias`, desplegada **solo
  desde scripts versionados**, con datos sinteticos reproducibles, y los contenedores/BD temporales retirados.
- Pareja backend: `alejovh12/AsistenciasUCO`, rama `jose-valencia/maint-003k-backend-only-release-gate` (work item
  `docs/work-items/MAINT-003K-backend-only-release-gate`).
- **No** hay merge a `develop`, despliegue a produccion ni cambio del proveedor de identidad.

## Clase de cambio y alcance

- Clase: `INFRASTRUCTURE` + correccion de dos defectos hallados por validacion real (seed 14 y `uv_estudiante_programa`).
- Rutas modificadas: `schema/seed/14_grupos_sesiones.sql`, `schema/views/uv_estudiante_programa.sql`,
  `test/test_utc_d06_procedencia_temporal.sql`, `test/test_uv_estudiante_programa_no_duplicates.sql`, `test_suite.sql`,
  `test_summary.ps1`, `test/fixtures/dev/**`, `docs/work-items/MAINT-003K-DB-DEV-CONSOLIDATION/**`.
- Rutas **no** modificadas: vistas/SP congelados del contrato v1, SP/tablas/trigger/roles de UTC-D06 y CC-003G-01, manifiestos
  (`FREEZE_MANIFEST_OK` se verifica en el gate y sigue PASS).

## Contratos incorporados (todos presentes en la rama base y verificados en el despliegue)

UTC-D06 (`procedenciaTemporal`, `uv_sesion_v2`, `usp_crear/actualizar_sesion_v2`, `usp_clasificar_procedencia_sesion`, trigger
`tr_Sesion_procedencia_temporal`, bitacora `SesionProcedenciaClasificacion`), SP v1 de sesiones (compatibilidad intacta),
generacion de sesiones en UTC (`usp_generar_sesiones_grupo`, marca `UTC_GENERADOR`), `usp_sincronizar_usuario`,
`usp_registrar_o_actualizar_plan_estudio`, roles de minimo privilegio (`rol_asistencias_runtime`, `rol_asistencias_clasificador_temporal`),
auditoria, catalogos de mensajes y parametros. Ver `UTC-D06-POST-FREEZE` y `CC-003G-01-public-user-plan-providers`.

## Decisiones

| # | Decision | Motivo |
|---|---|---|
| 1 | La DB de desarrollo se **reconstruye** (DROP + `deploy_schema.ps1`) en lugar de limpiar selectivamente. | Es la opcion mas simple y verificable: el estado final sale solo de Git, sin dependencias de FK ni residuos; los datos previos eran sinteticos (47 `*.invalid` + 6 del seed + 1 cuenta dev), con respaldo verificado. |
| 2 | Seed 14 inserta sesiones **UTC exactas** `DATETIME2(7)` con `procedenciaTemporal = 'UTC_V2'`. | `UTC_OWNER` esta reservada a `usp_clasificar_procedencia_sesion` (bitacora append-only); un seed no es una reclasificacion. Las filas historicas existentes **no** se reescriben desde el seed. |
| 3 | `uv_estudiante_programa` une `SELECT DISTINCT id, nombreCompleto FROM uv_estudiante`. | La vista multiplicaba cada `EstudiantePrograma` por el numero de grupos del estudiante (hallado por `EstudianteProgramaJpaParityIT` con fixtures multigrupo). Mismas 5 columnas y misma semantica de presencia. |
| 4 | Fixtures de desarrollo fuera de `schema/seed` (`test/fixtures/dev`) con prefijo de id reservado `DE0000`. | No forman parte de ningun despliegue; el limpiador solo toca ese prefijo; guardas: Developer Edition + nombre de DB + `OPERACION/AMBIENTE` no productivo. |
| 5 | El addendum adjunto `DB_DEV_ADDENDUM.md` **no estaba disponible en disco** al ejecutar. | Se siguieron las instrucciones del prompt de la fase; se deja constancia en `docs/work-items/MAINT-003K-backend-only-release-gate/DB_DEV_ADDENDUM.md` (backend). |

## Variable principal, riesgos, rollback

- `PRIMARY_VARIABLE`: `DEV_DB_REBUILT_FROM_GIT`.
- Riesgos: (a) los ITs Java `EstudianteAcademicFilterJpaParityIT` y `CoreViewQueriesJpaParityIT` asumian <=500/<=100 estudiantes; se hicieron
  independientes del volumen en el backend; (b) `prepare_java_integration_fixture.ps1` elige el grupo con `ORDER BY g.id` y puede sembrar su
  sesion `IT-MAINT003G-ATTENDANCE` en un grupo fixture (la validacion de fixtures cuenta solo filas `DE0000`).
- Rollback: ver `VALIDATION.md` (respaldos `.bak` verificados con `CHECKSUM`, restauracion de prueba y `DBCC CHECKDB`). El rollback de Git es
  `git revert` de los commits de esta rama; produccion no se toca.

## Definition of Ready

READY: fuentes, entorno (contenedor Developer local), rollback y pruebas identificados. Despliegue en staging/produccion: `NOT_READY` (decision del owner DB).

## MAINT-003K-Sonar follow-up (PR #36)

El comentario oficial de SonarCloud en PR #36 reporto `6.2% Duplication on New Code` (umbral `<= 3%`). La vista de
SonarCloud confirmo dos componentes afectados: `usp_crear_sesion_interno.sql` (61 lineas duplicadas) y
`usp_actualizar_sesion_interno.sql` (61 lineas duplicadas). El desglose de rangos no fue expuesto por la interfaz,
por lo que la matriz de rangos locales se conserva como evidencia complementaria y no como hallazgo independiente.

| Evidencia | Antes | Despues | Decision |
|---|---|---|---|
| Bloque Sonar confirmado | 61 lineas en cada nucleo de sesion; contraparte entre crear/actualizar | Extraido a `usp_validar_sesion_operacion_interno.sql` | Refactor seguro: procedencia `NULL/UTC_V2`, correlacion, ejecutor/RBAC DOCENTE y fechas son reglas comunes |
| Candidato local adicional | 37 lineas de fechas dentro del bloque comun | Incluido en el mismo helper | Candidato local, no presentado como bloque Sonar separado |
| Contratos explicitos de wrappers v1/v2 | Sin cambios | Sin cambios | Se mantienen las cuatro columnas y las marcas `NULL`/`UTC_V2` |
| Limpieza de temporales | `catch {}` silencioso en dos limpiezas | Errores observables; SQL cleanup se intenta aunque falle el archivo | El gate acumula fallo sin imprimir credenciales |

La rama de trabajo sigue siendo `feat/maint-003k-db-dev-consolidation`; no se cambia `develop`, esquema fisico ni
contratos publicos. La validacion SQL y el nuevo analisis remoto deben ejecutarse sobre el commit final.

## MAINT-003K error-priority follow-up

La comparacion entre `af37ccc8` y su padre confirmó un cambio funcional observable:

| Flujo | Prioridad histórica | Prioridad tras la refactorización | Decisión |
|---|---|---|---|
| Crear con grupo inexistente y fechas invertidas | `ERR_GRUPO_NO_EXISTE` | `SES_004` | Restaurada la prioridad histórica |
| Actualizar sesión inexistente y fechas invertidas | `SES_001` | `SES_004` | Restaurada la prioridad histórica |

La prioridad se considera parte del contrato porque el código de catálogo viaja en `mensajeTecnicoResultado` del
resultset público. La corrección mantiene correlación, procedencia, RBAC y titularidad como validaciones tempranas;
solo separa la fase de fechas del helper común para ejecutarla después de validar la entidad. No se modifican tablas,
firmas públicas, marcas v1/v2, transacciones ni el acceso directo del runtime a los procedimientos internos.

## Entorno local definitivo

Desde el 2026-10-11 el único entorno SQL local autorizado para despliegue y validación es
`sql_server_asistencias/gestionasistenciadb`. El contenedor efímero `maint003k_cert_20261011` fue inspeccionado y
retirado sin volumen; no se creó otra base, no se reconstruyó la principal y los conteos de las vistas antes y después
del gate permanecieron idénticos. El backup `maint003k_pre_priority_20261011.bak` quedó fuera de Git y fue verificado
con `RESTORE VERIFYONLY ... WITH CHECKSUM` antes de aplicar los tres procedimientos corregidos.
