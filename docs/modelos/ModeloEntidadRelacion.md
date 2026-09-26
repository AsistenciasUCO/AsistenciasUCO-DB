# Diagrama de Entidad Relación (MER) - Especificación del Esquema

Especificación técnica de las 33 entidades, claves primarias, claves foráneas y catálogos sueltos del modelo de base de datos (`gestionasistenciadb`).

```mermaid
erDiagram
    Usuario {
        UUID id PK
        UUID tipoIdIdentificacion FK
        INT numeroIdentificacion
        NVARCHAR primerApellido
        NVARCHAR segundoApellido
        NVARCHAR primerNombre
        NVARCHAR segundoNombre
        NVARCHAR correo
        NVARCHAR password
        BIT estado
    }

    TipoIdentificacion {
        UUID id PK
        VARCHAR tipoIdentificacion
        NVARCHAR nombre
    }

    Institucion {
        UUID id PK
        NVARCHAR nombre
        BIT estado
    }

    Administrador {
        UUID id PK
        UUID usuario FK
        UUID institucion FK
        BIT estado
    }

    Decano {
        UUID id PK
        UUID usuario FK
        UUID institucion FK
        BIT estado
    }

    Coordinador {
        UUID id PK
        UUID usuario FK
        UUID institucion FK
        BIT estado
    }

    Docente {
        UUID id PK
        UUID usuario FK
        UUID institucion FK
        BIT estado
    }

    Estudiante {
        UUID id PK
        UUID usuario FK
        UUID institucion FK
        BIT estado
    }

    Facultad {
        UUID id PK
        UUID institucion FK
        NVARCHAR nombre
        UUID decano FK
        BIT estado
    }

    Programa {
        UUID id PK
        UUID facultad FK
        NVARCHAR nombre
        UUID tipoDePrograma FK
        UUID coordinador FK
        BIT estado
    }

    TipoPrograma {
        UUID id PK
        NVARCHAR nombre
        NVARCHAR codigo
    }

    Area {
        UUID id PK
        NVARCHAR nombre
        UUID facultad FK
        BIT estado
    }

    Componente {
        UUID id PK
        NVARCHAR nombre
        BIT estado
    }

    PlanEstudio {
        UUID id PK
        UUID programa FK
        NVARCHAR nombre
        BIT estado
    }

    Semestre {
        UUID id PK
        INT numero
        BIT estado
    }

    SemestrePlanEstudio {
        UUID id PK
        UUID planEstudio FK
        UUID semestre FK
        BIT estado
    }

    Asignatura {
        UUID id PK
        NVARCHAR nombre
        UUID area FK
        UUID componente FK
        UUID semestrePlanEstudio FK
        BIT estado
    }

    PeriodoAcademico {
        UUID id PK
        UUID institucion FK
        NVARCHAR nombre
        INT codigo
        DATE fechaInicio
        DATE fechaFin
        INT anio
    }

    Grupo {
        UUID id PK
        UUID asignatura FK
        UUID periodoAcademico FK
        UUID docente FK
        NVARCHAR nombre
        INT cupoMaximo
        NVARCHAR aula
        BIT estado
    }

    EstadoEstudianteGrupo {
        UUID id PK
        NVARCHAR nombre
        NVARCHAR codigo
    }

    EstudianteGrupo {
        UUID id PK
        UUID estudiante FK
        UUID grupo FK
        UUID estado FK
    }

    EstudiantePrograma {
        UUID id PK
        UUID estudiante FK
        UUID programa FK
        BIT estado
    }

    Dia {
        UUID id PK
        NVARCHAR nombre
        NVARCHAR codigo
    }

    Horario {
        UUID id PK
        UUID grupo FK
        UUID dia FK
        TIME horaInicio
        TIME horaFin
        BIT estado
    }

    Sesion {
        UUID id PK
        UUID grupo FK
        DATETIME fechaHoraInicio
        DATETIME fechaHoraFin
        NVARCHAR descripcion
        NVARCHAR aula
        NVARCHAR tipo
        BIT estado
    }

    Asistencia {
        UUID id PK
        UUID estudianteGrupo FK
        UUID sesion FK
        DATETIME fechaHora
        UUID estado FK
    }

    Estado {
        UUID id PK
        NVARCHAR nombre
        CHAR codigo
    }

    RazonCausa {
        UUID id PK
        NVARCHAR nombre
        NVARCHAR codigo
    }

    DetalleAsistencia {
        UUID id PK
        UUID asistencia FK
        UUID razonCausa FK
        NVARCHAR observacion
        DATETIME fecha
    }

    SolicitudRevisionAsistencia {
        UUID id PK
        UUID asistencia FK
        UUID estado FK
        NVARCHAR observacion
        DATETIME fechaSolicitud
    }

    %% TABLAS SUELTAS / CATÁLOGOS AUTÓNOMOS
    Mensaje {
        VARCHAR codigo PK
        NVARCHAR tipo PK
        NVARCHAR contenido
    }

    Parametro {
        VARCHAR grupo PK
        VARCHAR clave PK
        NVARCHAR valor
        NVARCHAR descripcion
    }

    Perfil {
        UUID id PK
        NVARCHAR nombre
        INT nivel_acceso
        NVARCHAR codigo
    }

    %% RELACIONES DEL MODELO DE DATOS
    Usuario }|--|| TipoIdentificacion : "tipoIdIdentificacion"
    Administrador }|--|| Usuario : "usuario"
    Administrador }|--|| Institucion : "institucion"
    Decano }|--|| Usuario : "usuario"
    Decano }|--|| Institucion : "institucion"
    Coordinador }|--|| Usuario : "usuario"
    Coordinador }|--|| Institucion : "institucion"
    Docente }|--|| Usuario : "usuario"
    Docente }|--|| Institucion : "institucion"
    Estudiante }|--|| Usuario : "usuario"
    Estudiante }|--|| Institucion : "institucion"
    
    Facultad }|--|| Institucion : "institucion"
    Facultad }|--o| Decano : "decano"
    Area }|--|| Facultad : "facultad"

    Programa }|--|| Facultad : "facultad"
    Programa }|--|| TipoPrograma : "tipoDePrograma"
    Programa }|--o| Coordinador : "coordinador"
    PlanEstudio }|--|| Programa : "programa"

    SemestrePlanEstudio }|--|| PlanEstudio : "planEstudio"
    SemestrePlanEstudio }|--|| Semestre : "semestre"

    Asignatura }|--|| Area : "area"
    Asignatura }|--|| Componente : "componente"
    Asignatura }|--|| SemestrePlanEstudio : "semestrePlanEstudio"

    PeriodoAcademico }|--|| Institucion : "institucion"

    Grupo }|--|| Asignatura : "asignatura"
    Grupo }|--|| PeriodoAcademico : "periodoAcademico"
    Grupo }|--o| Docente : "docente"

    EstudianteGrupo }|--|| Estudiante : "estudiante"
    EstudianteGrupo }|--|| Grupo : "grupo"
    EstudianteGrupo }|--|| EstadoEstudianteGrupo : "estado"

    EstudiantePrograma }|--|| Estudiante : "estudiante"
    EstudiantePrograma }|--|| Programa : "programa"

    Horario }|--|| Grupo : "grupo"
    Horario }|--|| Dia : "dia"

    Sesion }|--|| Grupo : "grupo"

    Asistencia }|--|| EstudianteGrupo : "estudianteGrupo"
    Asistencia }|--|| Sesion : "sesion"

    DetalleAsistencia }|--|| Asistencia : "asistencia"
    DetalleAsistencia }|--|| RazonCausa : "razonCausa"

    SolicitudRevisionAsistencia }|--|| Asistencia : "asistencia"
    SolicitudRevisionAsistencia }|--|| Estado : "estado"
```
