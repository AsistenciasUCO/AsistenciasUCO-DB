---
status: active
type: work-item
scope: db
owner: fullstack-team
last-reviewed: 2026-11-06
---

# CERT-F3-CORRECCIONES — Seed de EstudiantePrograma (HU006/HU008)

## Causa

`schema/seed/14_grupos_sesiones.sql` inscribía a los estudiantes base en el Grupo 001 (asignatura ESP) directamente en `EstudianteGrupo`, sin `EstudiantePrograma`. En cambio, `usp_registrar_estudiante_en_grupo_interno`, el registro autónomo y la reactivación de `usp_resolver_solicitud_ingreso_grupo` sí crean esa fila para asignaturas ESP (regla HU008 de John, 2026-10-27).

Efecto en pantalla: el perfil (HU006) decía "No tienes vínculos académicos registrados" y la oferta (HU008) salía vacía.

## Cambio

Se agrega al seed 14 un bloque idempotente (`INSERT … WHERE NOT EXISTS`) que crea `EstudiantePrograma` para esas inscripciones, con la misma regla ESP. El seed 14 no está en ningún manifiesto congelado. En el seed no cambian objetos de esquema, SP ni vistas.

## Semestres del plan con una sola regla (decisión de John, 2026-11-06)

El coordinador veía el mayor número de semestre del plan (8, regla HU082/HU083) y el decano contaba los semestres creados (1). Ahora los dos SP del decano usan la regla del coordinador:

- `usp_consultar_estructura_facultad` (HU109/HU119): `totalSemestres = ISNULL(MAX(numeroSemestre), 0)`.
- `usp_consultar_programas_creditos_facultad_paginado` (HU112): igual.

Ninguno está en un manifiesto congelado. Pruebas: `test_consultas_decano_facultad.sql` (T-119-01, THROW 52968) y `test_consultas_transversales_hu112_hu157.sql` (T-112-01, THROW 56178) comparan `totalSemestres` con el mayor número de semestre del plan.

## Rollback

Revertir el commit; las filas ya sembradas no afectan otros datos.

> **Retirado en CULM-001 A (2026-11-07):** las solicitudes de ingreso (HU053-HU055) se descartaron; la reactivacion de la matricula retirada vive en `usp_internal_reactivar_matricula_retirada` (DEC-009). Ver `docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`, addendum CULM-001 A.
