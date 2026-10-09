# LB-008 JPA-05 — DB view identity alignment

## Propósito
Resolver la identidad estable de `dbo.uv_estudiante_programa` para permitir el mapeo JPA `@Entity @Immutable`
sin cambiar tablas ni el contrato de conexión (wire contract).

## Clasificación del cambio
```text
CHANGE_TYPE:                    POST_FREEZE NON_GOLDEN VIEW SEMANTIC CORRECTION
OBJECT:                         dbo.uv_estudiante_programa
TABLE_CHANGE:                   NO
STORED_PROCEDURE_CHANGE:        NO
PUBLIC_OBJECT_RENAME:           NO
VIEW_OUTPUT_SHAPE_CHANGE:       NO
GOLDEN_PATH_CHANGE:             NO
DB_BASELINE_CONTRACT_CHANGE:    NO
GOLDEN_PATH_MANIFEST_CHANGE:    NO
```

`uv_estudiante_programa` no aparece en `docs/contracts/DB_DEVELOP_FREEZE_MANIFEST.sha256`. Por tanto
`DB_BASELINE_CONTRACT.md`, `DB_BASELINE_CONTRACT.sha256` y `DB_DEVELOP_FREEZE_MANIFEST.sha256` no se modifican.

## Defecto
La vista unía `uv_estudiante` (cardinalidad estudiante × grupo × asignatura × programa). Un mismo
`EstudiantePrograma.id` se expandía en N filas, lo que destruye la identidad requerida por JPA.

## Corrección
Fuente canónica: `schema/views/uv_estudiante_programa.sql`. Se sustituye el join a `uv_estudiante` por
`uv_estudiante_identidad` (una fila por estudiante). Las columnas, alias, tipos y orden no cambian.

```text
BEFORE: EstudiantePrograma ep JOIN uv_estudiante e (estudiante x grupo)   -> N filas por ep.id
AFTER:  EstudiantePrograma ep JOIN uv_estudiante_identidad ei            -> 1 fila por ep.id
```

## Decisiones
- No se agregan columnas a `EstudiantePrograma`. La tabla ya tiene `PK_EstudiantePrograma (id UNIQUEIDENTIFIER)`.
- No se crean IDs artificiales ni `idEstudianteGrupo`.
- No se usa `ALTER TABLE` ni `migrations/04...` (SUPERSEDED). El flujo vigente es `schema/<objeto>` → `deploy_schema.ps1`.
- No se cambian SPs, nombres de objetos ni contratos HTTP.

## Invariante
Mientras las FKs de `EstudiantePrograma` sean válidas:
```text
FOR EACH dbo.EstudiantePrograma.id  -> EXACTLY ONE dbo.uv_estudiante_programa.id
COUNT(uv_estudiante_programa) = COUNT(EstudiantePrograma)
COUNT(*) = COUNT(DISTINCT id) en la vista
```

## Alcance del efecto observable
- Estudiantes sin grupo que tengan `EstudiantePrograma` ahora aparecen en la vista (antes el join a `uv_estudiante_grupo` los excluía). Es el comportamiento correcto de identidad.
- Consumidores actuales (`usp_registrar_estudiante_en_programa_interno` vía `test_reactive_academic.sql` y `test_usp_registrar_estudiante_en_grupo_usuario_no_existente.sql`) usan `EXISTS`; siguen válidos.
