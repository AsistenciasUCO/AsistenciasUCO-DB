---
name: modelo-jerarquico-rbac
description: >-
  Estándar canónico del modelo jerárquico de custodia, delimitación de dominios y matriz de permisos RBAC para todos los procedimientos almacenados y vistas en gestionasistenciadb.
---

# Modelo Jerárquico de Custodia y Matriz de Permisos RBAC (`modelo-jerarquico-rbac`)

## 1. Principio de Delimitación de Dominio y Jerarquía Institucional

Esta documentación establece las reglas de arquitectura y custodia jerárquica para la base de datos `gestionasistenciadb`. Ningún procedimiento almacenado (`usp_*`) ni vista autorizada (`uv_auth_*`) debe violar los límites de custodia definidos para cada perfil institucional.

```
[INSTITUCIÓN]
    │
    ├── [ADMINISTRADOR DE INSTITUCIÓN] (AD)
    │      └── Alcance: Decanos, Facultades, Periodos Académicos e Institución.
    │          (NO interfiere en Grupos, Docentes en Grupos, Estudiantes ni Asistencias).
    │
    └── [FACULTAD] (DECANO - DE)
           │   └── Alcance: Programas Académicos y Coordinadores de su Facultad.
           │
           └── [PROGRAMA ACADÉMICO] (COORDINADOR - CD)
                  │   └── Alcance: Asignaturas, Plan de Estudio, Docentes, Grupos y Aprobación de Docentes en Grupos.
                  │
                  └── [GRUPO / ASIGNATURA] (DOCENTE - DO)
                         │   └── Alcance: Sesiones, Asistencias y Aprobación de Estudiantes en sus Grupos.
                         │
                         └── [ESTUDIANTE] (ES)
                                └── Alcance: Su propia identidad, consulta de sus horarios/asistencias y solicitudes de revisión.
```

---

## 2. Matriz de Permisos RBAC por Nivel Jerárquico

### A. Administrador (`AD`)
* **Dominio Permitido**: Gestión de **Decanos**, **Facultades**, **Periodos Académicos** e **Institución**.
* **Prohibición de Sobreachipamiento (Out of Scope)**: El Administrador **NO** debe ser incluido en la validación RBAC de procedimientos o endpoints pertenecientes a niveles inferiores de la jerarquía (ej. `usp_registrar_estudiante_en_grupo`, `usp_aprobar_docente_grupo`, `usp_registrar_asistencia_estudiante`).

### B. Decano (`DE`)
* **Dominio Permitido**: Gestión de **Facultad a su cargo**, **Programas Académicos** y **Coordinadores**.
* **Delimitación**: Únicamente puede administrar y consultar entidades pertenecientes a la facultad donde figura como Decano titular.

### C. Coordinador (`CD`)
* **Dominio Permitido**: Gestión de **Programa Académico a su cargo**, **Asignaturas**, **Docentes**, **Grupos** y aprobación/asignación de docentes en grupos (ej. `usp_aprobar_docente_grupo`).
* **Delimitación RBAC**: Para `usp_aprobar_docente_grupo`, la validación RBAC exige que el ejecutor sea **COORDINADOR** (o Decano), excluyendo explícitamente al Administrador.

### D. Docente (`DO`)
* **Dominio Permitido**: Gestión de sus **Grupos asignados**, dictado de **Sesiones**, toma de **Asistencias** y aprobación de solicitudes de inscripción/matrícula de estudiantes en sus grupos (ej. `usp_registrar_estudiante_en_grupo`, `usp_aprobar_matricula_estudiante`).
* **Delimitación**: Su alcance está estrictamente acotado a los grupos donde es docente titular.

### E. Estudiante (`ES`)
* **Dominio Permitido**: Consulta de sus **Horarios**, **Asistencias** individuales, **Revisiones** de asistencia y postulación autónoma (`usp_registrar_estudiante_en_grupo_autonomo`).

---

## 3. Reglas de Validación en Procedimientos Almacenados (`usp_*`)

1. **Validación Estricta de RBAC**: Todo procedimiento almacenado debe validar explícitamente `@idUsuarioEjecutor` utilizando `dbo.usp_validar_permiso_rbac_usuario_interno` con la lista exacta de perfiles permitidos para ese nivel.
2. **Ejemplo de Aprobación de Docente en Grupo (`usp_aprobar_docente_grupo`)**:
   ```sql
   -- Exige que el ejecutor sea COORDINADOR (excluye explícitamente a ADMINISTRADOR)
   EXEC dbo.usp_validar_permiso_rbac_usuario_interno
       @idUsuario = @idUsuarioEjecutorDefecto,
       @codigoPerfilRequerido = 'COORDINADOR',
       @idCorrelacion = @idCorrelacionDefecto,
       @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
       @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
       @estadoResultado = @estadoResultado OUTPUT;
   ```
3. **Ejemplo de Aprobación/Registro de Estudiante en Grupo (`usp_registrar_estudiante_en_grupo`)**:
   ```sql
   -- Exige que el ejecutor sea DOCENTE o COORDINADOR (excluye explícitamente a ADMINISTRADOR)
   EXEC dbo.usp_validar_permiso_rbac_usuario_interno
       @idUsuario = @idUsuarioEjecutorDefecto,
       @codigoPerfilRequerido = 'DOCENTE,COORDINADOR',
       @idCorrelacion = @idCorrelacionDefecto,
       @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
       @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
       @estadoResultado = @estadoResultado OUTPUT;
   ```
