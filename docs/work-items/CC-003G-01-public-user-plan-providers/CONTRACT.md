---
status: IMPLEMENTED_PENDING_OWNER_REVIEW
work_item: CC-003G-01
type: db-contract
scope: gestionasistenciadb
base: feat/utc-d06-post-freeze@3842f70
independent_of: UTC-D06-POST-FREEZE (sin tocar sus archivos ni su manifiesto)
consumer_backend: AsistenciasUCO MAINT-003H
---

# CC-003G-01 — Proveedores publicos `usp_sincronizar_usuario` y `usp_registrar_o_actualizar_plan_estudio`

## Origen y problema

El backend (`UsuarioJpaRepository.SQL_SINCRONIZAR_USUARIO`, `PlanEstudioJpaRepository.SQL_REGISTRAR_O_ACTUALIZAR_PLAN`)
invoca dos SP publicos que **no existian en la DB publicada** (`feat/utc-d06-post-freeze@3842f70`): los dos archivos
fueron eliminados en `daeac11` y el estado «TD-043 CLOSED» del backend no tenia respaldo en el arbol DB. La auditoria
independiente MAINT-003H pidio definir los proveedores en un work item DB **separado de D06**, sin SP simulados,
sin alias a `usp_sincronizar_usuario_interno` y sin conceder `EXECUTE` sobre el esquema.

## Decisiones de contrato (evidencia: SP historicos en `daeac11^`, estandar canonico, consumidores backend)

### `dbo.usp_sincronizar_usuario` — ALTA IDEMPOTENTE (find-or-create), nunca UPSERT destructivo

| Aspecto | Decision | Motivo |
|---|---|---|
| Firma | La exigida por el backend, sin cambios: `@idTipoIdIdentificacion, @numeroIdentificacion, @primerApellido, @segundoApellido, @primerNombre, @segundoNombre, @correo, @password, @idCorrelacion` | `SqlStoredProcedureContractIT` y `UsuarioJpaRepository` |
| Semantica | Identidad nueva => alta (`GEN_004`). Reintento **exacto de un usuario ACTIVO** (tipo, numero, correo, nombres y apellidos iguales) => exito sin escribir; un usuario inactivo no se reconfirma ni se reactiva (se rechaza como documento en uso). Documento o correo en uso con datos distintos => rechazo (`ERR_UNICIDAD_DOCUMENTO` / `VAL_006`) sin modificar nada | `POST /api/v1/usuarios` es `authenticated()`; un UPSERT permitiria a cualquier autenticado reescribir nombre, correo o password de otro usuario |
| Password | Se persiste solo en el alta; en un reintento **no se compara ni se sobreescribe**; nunca se devuelve ni entra en mensajes. `uv_usuario.password` ya es `'*****'` | Evita toma de cuenta y fuga del hash |
| Id del usuario | No va en el resultset canonico (4 columnas); el backend lo resuelve por `uv_usuario` (tipo + numero) | Contrato canonico del owner |
| Autorizacion | Sin `@idUsuarioEjecutor` (el contrato HTTP es AUTENTICADO). Defensa DB = minimo privilegio: `EXECUTE` solo al rol runtime, `DENY` del nucleo interno y del DML directo sobre `dbo.Usuario` | No inventar un actor que el endpoint no tiene |
| Transaccion | Dueña de su transaccion (o `SAVE TRANSACTION usp_sincronizar_usuario` si el llamador ya tiene una); rollback ante `estadoResultado = 0` o excepcion; commit solo en exito | `docs/arquitectura/transaccion-procedimiento.md` |
| Concurrencia | Barrido `SERIALIZABLE` + `UPDLOCK` sobre `dbo.Usuario` dentro de la transaccion (no hay indices unicos de negocio). **No** `sp_getapplock`: impide que `sys.dm_exec_describe_first_result_set_for_object` descubra el resultset canonico que exige `PUBLIC_CANONICAL_RESULTSET` | Verificado empiricamente (error 11520) |
| Limites | Nombres/apellidos <= 50, correo <= 100 se validan **antes** de escribir (`VAL_004` / `VAL_005`) | Un overflow SQL (error 2628) incluye el valor truncado |
| Delegacion | Valida tipo, unicidad, formatos y password y hace el INSERT el nucleo `usp_sincronizar_usuario_interno` (no se le cambia el nombre ni se expone) | Estandar de orquestadores |

### `dbo.usp_registrar_o_actualizar_plan_estudio` — UPSERT por id con unicidad (programa, inp) y autorizacion en DB

| Aspecto | Decision | Motivo |
|---|---|---|
| Firma | `@idPlanEstudio, @idPrograma, @inp, @idCorrelacion, @idUsuarioEjecutor = NULL` | **P1 de la auditoria**: el adapter no enviaba el ejecutor; el SP no puede confiar solo en el controlador |
| Ejecutor | Obligatorio (NULL => `GEN_002`, fail-closed), activo, perfil `COORDINADOR` (`usp_validar_permiso_rbac_usuario_interno`) y **titular del programa** (`usp_validar_titularidad_jerarquica_interno`, `PROGRAMA`) | Mismo patron que `usp_crear_asignatura`/`usp_crear_coordinador` |
| Registro existente | Lo identifica `@idPlanEstudio` (PK). No existe => alta activa con ese id. Existe en el **mismo** programa con igual inp => exito sin escribir (idempotente). Otro inp => actualiza solo `inp`. Existe en **otro** programa => `SEC_002`, sin cambios | El coordinador no puede mutar planes ajenos |
| Unicidad de negocio | (programa, inp) unica: otro plan del mismo programa con ese inp => `GEN_003` | Sin duplicados silenciosos |
| Validaciones | `inp` entero positivo (`GEN_002`), programa inexistente (`PROG_001`), correlacion (`CORR_001`) | Sin reglas inventadas: no hay rango de inp documentado |
| Transaccion / concurrencia | Igual que arriba; la exclusion mutua bloquea la fila del programa (`UPDLOCK, HOLDLOCK`) | Serializa por programa |
| Respuesta | Exito alta `GEN_004`, actualizacion/reintento `GEN_005`; 4 columnas canonicas con correlacion en el mensaje tecnico | Estandar canonico |

### Permisos (`schema/security/rol_asistencias_runtime_cc003g01.sql`)

Script aditivo, idempotente, independiente del orden de despliegue y que **no modifica** `rol_asistencias_runtime.sql`
(su hash esta en `DB_UTC_D06_POST_FREEZE_MANIFEST.sha256`): `GRANT EXECUTE` solo a los dos SP; `DENY EXECUTE` a
`usp_sincronizar_usuario_interno`; `DENY INSERT/UPDATE/DELETE` sobre `dbo.Usuario` y `dbo.PlanEstudio`. Sin
`GRANT EXECUTE ON SCHEMA::dbo`. Crea el rol si falta; no crea logins ni membresias (decision de despliegue).

## Matriz de codigos de resultado (todos con `estadoResultado = 0` salvo exito)

| Escenario | Codigo | Clasificacion backend |
|---|---|---|
| Correlacion ausente | `CORR_001` | validacion |
| Ejecutor ausente (plan) | `GEN_002` | validacion |
| Ejecutor inexistente / inactivo | `USU_001` / `USU_002` | 404 / usuario inactivo |
| Ejecutor sin perfil coordinador | `SEC_001` | 403 |
| Programa ajeno / plan ajeno | `SEC_002` | 403 |
| Programa inexistente | `PROG_001` | 404 |
| `inp` invalido | `GEN_002` | validacion |
| Plan duplicado (programa, inp) | `GEN_003` | **409 (nuevo mapeo backend)** |
| Documento ya registrado | `ERR_UNICIDAD_DOCUMENTO` | 409 |
| Correo ya registrado | `VAL_006` | 409 |
| Formatos / password | `VAL_001..005`, `VAL_007` | validacion |
| Fallo inesperado | `SYS_001` | tecnico |

## Limitaciones declaradas

- La unicidad se serializa con un barrido completo de `dbo.Usuario` (no hay indices sobre documento ni correo): correcto y simple a la escala actual; si el volumen crece, el owner debe crear indices no unicos y revisar el costo del bloqueo de rango. `usp_registrar_o_actualizar_plan_estudio` no valida que el programa este activo (no hay regla documentada).
- `dbo.Usuario`/`dbo.PlanEstudio` siguen sin indices unicos: otros creadores de usuario (`usp_crear_coordinador`,
  `usp_crear_decano`, matricula) no usan este barrido; la serializacion cubre solo las altas via `usp_sincronizar_usuario`.
- En un reintento exacto el password enviado se ignora: si Keycloak se creo con otro password tras un fallo parcial del
  aprovisionamiento, el hash de DB conserva el original (DB no es la fuente de autenticacion).
- El mensaje de overflow/truncation de nombres/correo se evita por validacion previa; no se audita otro canal de fuga.
- No se aplico ni desplego nada en produccion; validado solo en contenedores aislados.
