# TEST_PLAN — LB-008 JPA-05 DB view identity

Archivo: `test/test_uv_estudiante_programa_identity.sql` (registrado en `test_suite.sql` y en `$criticalIds` de `test_summary.ps1`).

| ID | Verifica |
|---|---|
| `VIEW_ESTUDIANTE_PROGRAMA_SHAPE` | `sys.columns`: exactamente 5 columnas; `column_id` 1..5 = `id, idEstudiante, nombreEstudiante, idPrograma, nombrePrograma` |
| `VIEW_ESTUDIANTE_PROGRAMA_IDENTITY` | `GROUP BY id HAVING COUNT(*) <> 1` no retorna filas sobre el estado actual |
| `VIEW_ESTUDIANTE_PROGRAMA_CARDINALITY` | Fixture: estudiante en dos grupos nuevos + una `EstudiantePrograma` → una fila en la vista; `COUNT(vista) = COUNT(EstudiantePrograma)`; cada `view.id` existe en `EstudiantePrograma` |
| `VIEW_ESTUDIANTE_PROGRAMA_DEPENDENCY` | `sys.sql_expression_dependencies`: depende de `uv_estudiante_identidad` y NO de `uv_estudiante` |

## Fixture
Todo ocurre dentro de `BEGIN TRANSACTION` … `ROLLBACK`, con `TRY/CATCH` que revierte y re-lanza.
Se insertan dos `dbo.Grupo` nuevos clonados del grupo base (misma asignatura, periodo y docente), dos `EstudianteGrupo`
y una `EstudiantePrograma`. No se modifican datos compartidos.

## Evidencia RED (antes del despliegue)
Con la vista anterior desplegada, el test pasó `SHAPE` e `IDENTITY` y falló en:
`Msg 53013 — VIEW_ESTUDIANTE_PROGRAMA_CARDINALITY produjo filas distintas de 1 para una EstudiantePrograma con dos grupos.`
Tras el fallo, la base quedó sin grupos de prueba, `EstudiantePrograma = 0` y `@@TRANCOUNT = 0`.

## Regresión
Deben seguir en PASS: `test_reactive_academic.sql`, `test_usp_registrar_estudiante_en_grupo_usuario_no_existente.sql`,
`test_public_objects.sql`, `test_contract_closure.sql`, y el `test_suite.sql` completo
(incluidos `STUDENT_PROGRAM_REGISTER`, `PUBLIC_VIEWS_REFRESH`, `BROKEN_DEPENDENCIES_ZERO`).
