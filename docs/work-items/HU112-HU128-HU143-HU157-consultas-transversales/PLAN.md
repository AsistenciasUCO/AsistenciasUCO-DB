---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-02
---

# PLAN — HU112-HU128-HU143-HU157-consultas-transversales

## Identidad y objetivo

- HU112: tabla unificada de programas y créditos del decano (una fila por programa y plan, con la suma real de créditos de `Asignatura.credito`).
- HU128: directorio de docentes de la facultad del decano, filtrable por programa (vínculo `DocentePrograma` activo).
- HU143: búsqueda transversal de asignaturas por código o nombre: el ADMINISTRADOR busca en todas las facultades de su institución y el DECANO solo en su facultad (decisión de John, 2026-11-02).
- HU157: ficha unificada del estudiante con historial completo (datos, programas, grupos por período y resumen de asistencia): buscador del ADMINISTRADOR e historial para ADMINISTRADOR (su institución) y DECANO (su facultad).
- Solo consultas: sin DDL, sin tablas ni objetos congelados del baseline, sin mensajes nuevos de catálogo.
- Contrato HTTP, decisiones y validación de las 3 capas: work item homónimo en el backend (`docs/work-items/HU112-HU128-HU143-HU157-consultas-transversales/`).

## Objetos de base de datos

| Objeto | Cambio |
|---|---|
| `usp_validar_consulta_paginada_interno` | Nuevo interno compartido con el triplete OUTPUT: correlación, ejecutor (`VAL_001`), perfil (`SEC_001`) y paginación (`PAG_001`); fija el `SESSION_CONTEXT`. Evita repetir el bloque en cada consulta nueva (SonarCloud > 3 % de duplicación en código nuevo) |
| `usp_consultar_programas_creditos_facultad_paginado` | Nuevo (HU112, `PAG_001`) |
| `usp_consultar_docentes_facultad_paginado` | Nuevo (HU128, `PAG_001`) |
| `usp_buscar_asignaturas_paginado` | Nuevo (HU143, `PAG_001`) |
| `usp_buscar_estudiantes_institucion_paginado` | Nuevo (HU157 buscador del administrador, `PAG_001`) |
| `usp_consultar_historial_estudiante` | Nuevo (HU157 ficha unificada, `VAL_001`/`SEC_001`) |
| `schema/security/rol_asistencias_runtime_hu112_hu157.sql` | `GRANT EXECUTE` aditivo sobre los 5 SP públicos (el interno no recibe permisos) |
| `test/test_consultas_transversales_hu112_hu157.sql` | Pruebas nuevas registradas en `test_suite.sql` |
| `test/test_contract_closure.sql` | Exclusiones READ_QUERY_RESULTSET para los 5 SP públicos |

## Decisiones

- **Reutilización (HU157):** `usp_consultar_ficha_estudiante_programa` y `usp_consultar_resumen_asistencia_estudiante_programa` (HU069) resuelven el ámbito solo para el coordinador (`usp_resolver_programa_coordinador_interno`), así que no se pueden invocar para el administrador o el decano. El historial reutiliza las mismas vistas (`uv_usuario`, `uv_estudiante_grupo`, `uv_resumen_asistencia_estudiante_grupo`) y el ámbito sale de `uv_auth_estudiante`.
- **HU128:** `usp_consultar_docentes_programa` exige un programa y es del coordinador; extenderlo cambiaría su firma pública (AGENTS.md §5). Se agrega una consulta propia de la facultad.
- **HU143 ámbito:** transversal a los programas y planes del ámbito del ejecutor: ADMINISTRADOR, todas las facultades de su institución; DECANO, solo su facultad (John, 2026-11-02). Por eso el SP se llama `usp_buscar_asignaturas_paginado` y no lleva "institución" en el nombre.
- **HU112 totales:** cuentan todas las asignaturas del plan (activas o no), igual que la malla de `GET /decano/planes-estudio/{id}/asignaturas` que hoy usa la pantalla.

## Reglas aplicadas (AGENTS.md)

- Skills del repo: `procedimientos-externos-condiciones` (DECLARE en la cabecera, `-- PASO n`, `IF` con `BEGIN/END`, READ_QUERY_RESULTSET con `THROW`, `ISNULL` solo sobre agregaciones), `procedimientos-internos-condiciones` (interno con el triplete OUTPUT, correlación en el mensaje técnico y `SYS_001` en el CATCH), `consulta-a-bd` (lecturas solo por vistas: `uv_auth_*` para las filas y `uv_decano`/`uv_administrador` para el ámbito, sin tablas físicas), `modelo-jerarquico-rbac` (`usp_validar_permiso_rbac_usuario_interno` con la lista exacta de perfiles) y `cobertura-pruebas-objetos-bd` (camino exitoso, `VAL_001`, `SEC_001`, `PAG_001`, aislamiento por rol y el interno probado directamente).
- Ningún objeto congelado del baseline se tocó; firmas existentes intactas.
- Mensajes por catálogo (`usp_obtener_mensaje_catalogo`), sin textos quemados.
- `rol_asistencias_runtime` solo recibe `EXECUTE` sobre los SP públicos nuevos, en un archivo aditivo.
- Ámbito forzado dentro del SP; `SESSION_CONTEXT` capturado y restaurado.
- Sin la subcadena prohibida por el gate en `schema/`, `test/` ni `migrations/`.

## Rollback

Revertir los commits del work item; los SP nuevos se eliminan con `DROP PROCEDURE` y los permisos con `REVOKE` (sin cambios de tablas ni datos).
