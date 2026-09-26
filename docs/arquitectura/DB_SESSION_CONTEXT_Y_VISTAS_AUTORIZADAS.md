# SESSION_CONTEXT y vistas autorizadas (`uv_auth_*`)

Estado: **FROZEN** a partir de DB-GP-001C. Extensiones de `develop`, **no** parte del Golden Path
(`docs/contracts/DB_BASELINE_CONTRACT.md`, sin cambios).

## Politica de vistas

| Familia | Semantica | Sin identidad |
| --- | --- | --- |
| `uv_*` | Interna / base. Datos completos. Mantenimiento y administracion SQL directa. | Datos completos |
| `uv_auth_*` | Externa / autorizada por `SESSION_CONTEXT('idUsuarioEjecutor')`. **Fail closed.** | **0 filas** |

- `NULL` (contexto ausente) **no** equivale a acceso total. Un UUID inexistente tampoco equivale a administrador.
- Las tareas de mantenimiento usan `uv_*`, no la ausencia de identidad como bypass.
- Alcance por rol (sin cambios): `ADMINISTRADOR` (su institucion), `DECANO` (su facultad), `COORDINADOR` (sus programas),
  `DOCENTE` (sus grupos), `ESTUDIANTE` (grupos donde esta inscrito y su propia fila).
- Las vistas filtran por rol/titularidad, no por `Usuario.estado`; la validacion de usuario activo es `SEC_001` en los SP publicos.

### Inventario (12)

| Clasificacion | Vistas |
| --- | --- |
| `DIRECT_CONTEXT_FILTER` (`ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL AND (...)`) | `uv_auth_institucion`, `uv_auth_facultad`, `uv_auth_programa`, `uv_auth_grupo`, `uv_auth_decano`, `uv_auth_coordinador`, `uv_auth_docente`, `uv_auth_estudiante` |
| `INHERITS_AUTH_VIEW` (heredan fail-closed) | `uv_auth_periodo_academico` (← institucion), `uv_auth_sesion` (← grupo), `uv_auth_asistencia` (← sesion), `uv_auth_solicitud_revision_asistencia` (← asistencia) |

Una vista `uv_auth_*` nueva debe clasificarse en `test/test_authorized_views_rbac.sql` o el gate falla.

## SESSION_CONTEXT y pool de conexiones

> **`SESSION_CONTEXT` es estado de la conexion fisica**, no de la peticion HTTP.

- Debe **restaurarse**: no puede asumirse limpieza automatica por request. Con un pool de conexiones, un contexto
  que se deja establecido es visible para la siguiente peticion que reutilice esa conexion (fuga de identidad).
- `usp_consultar_grupos_paginado` captura el contexto previo, aplica el temporal y **siempre** restaura el previo
  (exito y excepcion). Nunca deja `NULL` si antes habia un valor.
- Una futura integracion backend/JPA debe **disenar el ciclo de vida del contexto por conexion** (establecer al tomar la
  conexion, restaurar/limpiar al devolverla, incluso en error) antes de usar `uv_auth_*`.
- **LB-002.1 (piloto JPA) NO usa `uv_auth_*` ni `SESSION_CONTEXT`**: usa las vistas base congeladas.

## Clasificacion de `usp_consultar_grupos_paginado`

`NON_GOLDEN_PATH_EXTENSION` · `NOT_BACKEND_CONSUMED` · `NOT_PART_OF_LB002_JPA_PILOT`.

Su resultset es `READ_QUERY_RESULTSET` (filas de datos + `totalRegistros`), **no** `MUTATION_COMMAND_RESULTSET`.
El resultset canonico de 4 columnas (`idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`,
`estadoResultado`) es exclusivo de los SP de comando/mutacion del Golden Path; forzarlo aqui destruiria el contrato de
lectura paginada. Por eso esta excluido de esa regla en `test/test_contract_closure.sql`.

## Permisos SQL (no incluido)

```text
DB_PRINCIPAL_HARDENING: FUTURE_DECISION
```

No existen usuarios/roles de aplicacion ni `GRANT/REVOKE/DENY` versionados: **no** se afirma minimo privilegio SQL.
Se decidira en un work item propio (otra variable arquitectonica).

## Bases con datos existentes: indices unicos

Los indices `UX_Asistencia_EstudianteGrupo_Sesion`, `UX_DetalleAsistencia_Asistencia` y `UX_RazonCausa_Codigo` rechazan
duplicados. Antes de desplegar sobre una base con datos ejecute `scripts/precheck_unique_indexes.sql` (solo lectura,
esperado 0). Si hay duplicados: detener el despliegue en ese ambiente; no se borran datos automaticamente.
