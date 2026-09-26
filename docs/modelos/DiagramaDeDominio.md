# Diagrama de Dominio (Modelo Conceptual)

Documentación del Modelo de Dominio del Sistema de Gestión de Asistencias.

```mermaid
classDiagram
    class Institucion {
        +UUID id
        +NVARCHAR nombre
        +BIT estado
    }

    class Facultad {
        +UUID id
        +NVARCHAR nombre
        +UUID institucion
        +UUID decano
        +BIT estado
    }

    class Decano {
        +UUID id
        +UUID usuario
        +UUID institucion
        +BIT estado
    }

    class Coordinador {
        +UUID id
        +UUID usuario
        +UUID institucion
        +BIT estado
    }

    class Administrador {
        +UUID id
        +UUID usuario
        +UUID institucion
        +BIT estado
    }

    class Programa {
        +UUID id
        +NVARCHAR nombre
        +UUID facultad
        +UUID tipoDePrograma
        +UUID coordinador
        +BIT estado
    }

    class TipoPrograma {
        +UUID id
        +NVARCHAR nombre
        +NVARCHAR codigo
    }

    class Area {
        +UUID id
        +NVARCHAR nombre
        +UUID facultad
        +BIT estado
    }

    class Componente {
        +UUID id
        +NVARCHAR nombre
        +BIT estado
    }

    class PlanEstudio {
        +UUID id
        +NVARCHAR nombre
        +UUID programa
        +BIT estado
    }

    class SemestrePlanEstudio {
        +UUID id
        +UUID planEstudio
        +UUID semestre
        +BIT estado
    }

    class Asignatura {
        +UUID id
        +NVARCHAR nombre
        +UUID area
        +UUID componente
        +UUID semestrePlanEstudio
        +BIT estado
    }

    class Grupo {
        +UUID id
        +UUID asignatura
        +UUID periodoAcademico
        +UUID docente
        +NVARCHAR nombre
        +INT cupoMaximo
        +BIT estado
    }

    class Docente {
        +UUID id
        +UUID usuario
        +UUID institucion
        +BIT estado
    }

    class Estudiante {
        +UUID id
        +UUID usuario
        +UUID institucion
        +BIT estado
    }

    class EstudianteGrupo {
        +UUID id
        +UUID estudiante
        +UUID grupo
        +UUID estado
    }

    class Sesion {
        +UUID id
        +UUID grupo
        +DATETIME fechaHoraInicio
        +DATETIME fechaHoraFin
        +BIT estado
    }

    class Asistencia {
        +UUID id
        +UUID estudianteGrupo
        +UUID sesion
        +DATETIME fechaHora
        +UUID estado
    }

    class DetalleAsistencia {
        +UUID id
        +UUID asistencia
        +UUID razonCausa
        +NVARCHAR observacion
        +DATETIME fecha
    }

    class Mensaje {
        +VARCHAR codigo
        +NVARCHAR tipo
        +NVARCHAR contenido
    }

    class Parametro {
        +VARCHAR grupo
        +VARCHAR clave
        +NVARCHAR valor
        +NVARCHAR descripcion
    }

    class Perfil {
        +UUID id
        +NVARCHAR nombre
        +INT nivel_acceso
        +NVARCHAR codigo
    }

    Institucion "1" -- "0..*" Facultad : posee
    Institucion "1" -- "0..*" Administrador : gestiona
    Facultad "1" -- "0..*" Programa : pertenece
    Programa "1" -- "0..*" PlanEstudio : posee
    Programa "0..*" -- "1" TipoPrograma : clasificado en
    Facultad "1" -- "0..*" Area : contiene
    Area "1" -- "0..*" Asignatura : pertenece
    PlanEstudio "1" -- "0..*" SemestrePlanEstudio : agrupa
    SemestrePlanEstudio "1" -- "0..*" Asignatura : contiene
    Asignatura "1" -- "0..*" Grupo : oferta
    Grupo "1" -- "0..*" EstudianteGrupo : matricula
    Estudiante "1" -- "0..*" EstudianteGrupo : cursa
    Grupo "1" -- "0..*" Sesion : imparte
    EstudianteGrupo "1" -- "0..*" Asistencia : registra
    Sesion "1" -- "0..*" Asistencia : valida
    Asistencia "1" -- "0..1" DetalleAsistencia : detalla
    Docente "1" -- "0..*" Grupo : dicta
    Decano "1" -- "0..*" Facultad : lidera
    Coordinador "1" -- "0..*" Programa : coordina
```
