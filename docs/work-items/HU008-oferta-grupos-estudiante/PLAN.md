---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-27
---

# PLAN — HU008-oferta-grupos-estudiante: oferta de grupos y regla de inscripción en el programa

## Identidad y objetivo

- **Oferta (HU008):** el estudiante ve los grupos de los períodos vigentes y próximos que puede solicitar:
  - las asignaturas **específicas (ESP)** de sus programas;
  - las **transversales (BAS/INS)** de su institución.
- **Regla de matrícula (John, 2026-10-27):** solo una asignatura ESP inscribe al estudiante en el programa (`EstudiantePrograma`).
- **Opción configurable:** con el parámetro `OFERTA.INCLUIR_TRANSVERSALES` en 0, las transversales se ocultan de la oferta.
- **Contrato HTTP, análisis de impacto y validación de las 3 capas:** están en el work item homónimo del backend.

## Objetos de base de datos

| Objeto | Cambio |
|---|---|
| `usp_consultar_oferta_grupos_estudiante` | Nuevo (READ_QUERY_RESULTSET + `totalRegistros`; paginación R2) |
| `usp_registrar_estudiante_en_grupo_interno` | Regla J4: `INNER JOIN Componente ... codigo = 'ESP'` en la consulta del programa del grupo (1 línea + comentario). No cambia la firma ni el resultset. **No está congelado.** |
| `usp_registrar_estudiante_en_grupo_autonomo` | El mismo cambio (inactivo hoy; HU176B en 501), para que la regla sea única |
| `schema/seed/24_parametro_oferta_grupos.sql` | Parámetro `OFERTA.INCLUIR_TRANSVERSALES = 1` (MERGE que no sobrescribe un valor ya cambiado) |
| `schema/security/rol_asistencias_runtime_hu008.sql` | `GRANT EXECUTE` aditivo (THROW 52191 si falta el SP) |
| `test/test_usp_consultar_oferta_grupos_estudiante.sql` | Nuevo (O-01..O-05) |
| `test/test_hu008_regla_inscripcion_programa.sql` | Nuevo: regresión de HU053-055 (RI-01 ESP inscribe; RI-02 INS y RI-03 BAS no inscriben) |
| `test_suite.sql`, `test/test_contract_closure.sql` | Registro de las pruebas y exclusión READ_QUERY_RESULTSET del SP de oferta |

## Reglas aplicadas (AGENTS.md)

- Sin cambios de tablas ni de objetos congelados (`freeze-manifest -Mode Verify` = 0).
- Se leen objetos existentes: `Componente` (BAS/ESP/INS), `EstudiantePrograma`, `Programa`, `Facultad`, `Horario`, `Dia`, `SolicitudIngresoGrupo`, `EstudianteGrupo`, `CatalogoParametro`.
- El ámbito queda en el SP: el estudiante ejecutor por `Estudiante.usuario`; cualquier otro rol obtiene 0 filas.
- No se agregan mensajes nuevos; se usa `VAL_001`.

## Para ocultar las transversales (opción futura J5)

```sql
UPDATE dbo.CatalogoParametro SET valor = '0' WHERE grupo = 'OFERTA' AND clave = 'INCLUIR_TRANSVERSALES';
```

Se vuelve a mostrar con `'1'`. El efecto es inmediato y no hay que desplegar código.

## Rollback

1. `DROP PROCEDURE` de la oferta.
2. `REVOKE` del permiso.
3. Borrar el parámetro.
4. Quitar el `JOIN` de los 2 SP de matrícula.

Sin cambios de datos. Las filas `EstudiantePrograma` creadas antes por transversales no se tocan.
