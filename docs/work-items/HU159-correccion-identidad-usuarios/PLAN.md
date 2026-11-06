---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-05
---

# PLAN — HU159-correccion-identidad-usuarios

## Objetivo

HU159, redefinida por John (2026-11-05): corregir los datos de identidad (nombres, apellidos y tipo y número de documento) por jerarquía. No se tocan el correo, la contraseña ni el estado.

| Quién | Corrige a | Dónde |
|---|---|---|
| ADMINISTRADOR | Decano | `usp_corregir_identidad_usuario` (`@tipoUsuario = 'DECANO'`) |
| DECANO de la facultad | Coordinador | `usp_actualizar_coordinador` (HU121, aditivo) |
| COORDINADOR del programa | Docente vinculado | `usp_actualizar_docente_programa` (HU092, aditivo) |
| COORDINADOR del programa | Estudiante del programa (`EstudiantePrograma`) | `usp_corregir_identidad_usuario` (`@tipoUsuario = 'ESTUDIANTE'`) |

- El administrador no se corrige por la app.
- HU160 queda DESCARTADA: el administrador no cambia el estado de un estudiante (`HOJA_DE_RUTA_JERARQUIA_ROLES.md` del repositorio Infra).
- Motivo: obligatorio siempre para estudiante y decano. En HU121 y HU092, solo si cambia el documento.
- Auditoría: `AuditoriaEvento.metadata` guarda `{ idUsuario, motivo, anterior, nuevo }`. Se ve en la auditoría del administrador (HU172).

## Reversibilidad (pedido de John)

- **Apagar sin desplegar código:** `UPDATE dbo.CatalogoParametro SET valor = N'0' WHERE grupo = 'IDENTIDAD' AND clave = 'PERMITIR_CORREGIR_DOCUMENTO'`.
  - Con eso, cualquier cambio de documento se rechaza con `IDE_003` y la corrección de nombres sigue funcionando.
  - El frontend oculta los campos de documento (`GET /api/v1/configuracion/identidad`).
- **Retirar el código:**
  - BD: `usp_corregir_documento_usuario_interno` es el único punto que cambia el documento. Las fachadas solo lo llaman cuando reciben un documento.
  - Backend: los únicos puntos son `CorreccionDocumentoDTO` y el `username` opcional de `ActualizarCuentaIdentidadDTO`.

## Cambios

| Objeto | Cambio |
|---|---|
| `usp_corregir_identidad_usuario` (nuevo, público) | Estudiante o decano. RBAC por tipo; ámbito en tablas base (`GEN_001` sin revelar existencia); motivo `IDE_001`; resultset canónico + `idUsuario`, `correo` y `numeroIdentificacion` |
| `usp_corregir_documento_usuario_interno` (nuevo) | Único punto que corrige el documento. Lee el parámetro, exige motivo si cambia, valida tipo, número y unicidad (UPDLOCK/HOLDLOCK). `@soloValidar` valida sin escribir |
| `usp_corregir_identidad_usuario_interno` (nuevo) | Núcleo de estudiante y decano: documento validado, nombres, documento y auditoría |
| `usp_registrar_auditoria_identidad_interno` (nuevo) | Fila de auditoría con los valores anteriores y nuevos |
| `ufn_obtener_identidad_usuario_json` (nueva) | Instantánea JSON de la identidad (sin correo, contraseña ni estado) |
| `usp_actualizar_coordinador`, `usp_actualizar_docente_programa` | Parámetros opcionales `@idTipoIdIdentificacion`, `@numeroIdentificacion` y `@motivo`. Sin ellos, el comportamiento es el de antes |
| `schema/seed/31_mensajes_correccion_identidad.sql` | `IDE_001` (motivo), `IDE_002` (éxito), `IDE_003` (documento apagado) |
| `schema/seed/32_parametros_identidad.sql` | `IDENTIDAD.PERMITIR_CORREGIR_DOCUMENTO = 1` (no sobrescribe un valor existente) |
| `schema/security/rol_asistencias_runtime_hu159.sql` | `GRANT EXECUTE` de `usp_corregir_identidad_usuario` |
| `test/test_usp_corregir_identidad_usuario.sql` | Éxito, motivo, ámbito, unicidad, RBAC, decano, HU121, HU092 y parámetro en 0 (9 marcadores críticos en `test_summary.ps1`) |
| `test/test_contract_closure.sql` | `usp_corregir_identidad_usuario` entra en la excepción de resultset con columnas extra, como `usp_actualizar_coordinador` |

Sin DDL ni objetos congelados: ningún manifiesto cambia.

## Rollback

- Revertir el commit.
- Para apagar sin revertir: poner el parámetro en 0.
- Los objetos nuevos no tienen dependientes fuera de este paquete.
