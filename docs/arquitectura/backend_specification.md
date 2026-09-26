# Especificación Técnica: Procedimientos Almacenados y Endpoints del Sistema (Modelo Unificado Jerárquico)

> [!IMPORTANT]
> Este documento integra la **Especificación Técnica de Arquitectura Backend** alineada estrictamente con la **Jerarquía Institucional de Nodos Padre-Raíz**, la **Validación Granular de Roles (RBAC)** y el **Mecanismo de Registro Autónomo con Aprobación del Perfil Superior**.

---

## 🏛️ Matriz de Jerarquía Institucional y Ámbitos de Permisos (Nodo Raíz → Nodo Hoja)

El sistema de datos y la seguridad backend operan bajo una estructura estricta de **árbol jerárquico de pertenencia**:

```
[Institución] (Nodo Raíz Macro - Gestionado por ADMINISTRADOR)
 └── [PeriodoAcademico] (Gestionado por ADMINISTRADOR / COORDINADOR)
 └── [Facultad] (Creada por ADMINISTRADOR)
      └── [Decano] (Designado por ADMINISTRADOR)
           └── [Programa Académico] (Registrado por DECANO)
                └── [Coordinador] (Designado por DECANO)
                     ├── [PlanEstudio / Asignatura] (Estructurado por COORDINADOR)
                     └── [Grupo Académico] (Registrado por COORDINADOR)
                          └── [Docente Titular] (Asignado a Grupo por COORDINADOR)
                               └── [Sesión de Clase] (Creada por DOCENTE TITULAR)
                                    ├── [Asistencia / DetalleAsistencia] (Tomada/Aprobada por DOCENTE)
                                    └── [SolicitudRevisionAsistencia] (Radicada por ESTUDIANTE → Aprobada por DOCENTE)
```

---

## 🔄 Reglas Transversales de Registros Autónomos y Flujo de Aprobaciones

1. **Registros Autónomos por Estudiante / Usuario:**
   - **Inscripción / Matrícula:** Un estudiante puede solicitar matricularse en un grupo autónomamente. La matrícula queda en estado `'PENDIENTE_APROBACION'` hasta que el **Docente Titular** o **Coordinador** la aprueba.
   - **Auto-registro de Asistencia por QR / PIN:** El estudiante marca su presencia en una sesión. La asistencia se registra en modo provisional y se consolida al momento del **Cierre Oficial de Sesión por el Docente Titular**.
   - **Solicitudes de Revisión / Excusas:** El estudiante crea autónomamente un reclamo de inasistencia (`estado = 'PENDIENTE'`). No muta el historial definitivo hasta que el **Docente Titular** o **Coordinador de Programa** lo aprueba explícitamente (`estado = 'APROBADA'`).
2. **Evaluación de Permisos de Titularidad en Cascada:**
   - Cada operación valida la pertenencia en la cadena de nodos. Un Docente no puede crear sesiones ni aprobar asistencias en un grupo donde no figure como `Grupo.docente = idUsuarioAutenticado`.

---

# PARTE 1: Especificación de Transacciones por Módulo (Con Trazabilidad Jerárquica Nodo Padre-Raíz)


## Módulo 1: Gestión de Usuarios e Identidades

### Transacción 1.1: [PR-002] - Registrar Docente Institucional en Grupo (Creación/Actualización Reactiva de Usuario + Rol Docente + Asignación a Grupo)

- **Historias de Usuario:** HU052 (Registro de docentes en grupos con validación de existencia), HU050 (Sincronización de usuarios).
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Permite asignar un docente a un grupo académico en un solo paso. Si la persona no está registrada como usuario o no tiene perfil de docente instituido, la transacción lo crea y categoriza reactivamente antes de vincularlo al grupo, evitando fallos por clave foránea o datos incompletos.
- **Entidades MER:** ``Usuario`, `Docente`, `Grupo`, `Institucion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Docente``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Institucion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.2: [PR-003] - Registrar Estudiante Institucional en Grupo (Sincronización + Perfil Estudiante + Programa + Matrícula en Grupo)

- **Historias de Usuario:** HU053 (Registro e inscripción de estudiantes en grupos académicos), HU051 (Registro en programas académicos), HU050.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Orquesta el enrolamiento completo de un estudiante en un grupo. Registra/actualiza al usuario, le otorga el rol de `Estudiante`, lo inscribe en el `Programa` correspondiente a la asignatura del grupo si no lo está, y finalmente lo matricula en `EstudianteGrupo` con estado activo.
- **Entidades MER:** ``Usuario`, `Estudiante`, `EstudiantePrograma`, `Programa`, `Grupo`, `Asignatura`, `EstudianteGrupo`, `EstadoEstudianteGrupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudiantePrograma``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Validación de Entidad MER `dbo.`Asignatura``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  11. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  12. **Validación de Entidad MER `dbo.`EstadoEstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  13. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.3: [PR-004] - Asignar Decano a Facultad con Validación/Creación de Usuario e Inactivación de Decano Previo

- **Historias de Usuario:** HU102 (Gestión macro de facultades y decanaturas), HU050.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Garantizar que una facultad tenga exactamente un Decano activo titular. Si ya existía un decano previo en la facultad, lo inactiva o desvincula en la misma transacción antes de promover al nuevo usuario y asignarlo a la `Facultad`.
- **Entidades MER:** ``Usuario`, `Decano`, `Facultad`, `Institucion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Decano``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Facultad``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Institucion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.4: [PR-005] - Asignar Coordinador a Programa Académico con Actualización Reactiva y Transferencia de Dirección

- **Historias de Usuario:** HU066 (Gestión de coordinación de programas), HU050.
- **Rol Requerido:** `DECANO`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Intención de Negocio:** Permite asignar la dirección de un programa académico a un profesional. Crea/actualiza la cuenta de usuario, le asigna el rol de `Coordinador` institucional y actualiza la FK `coordinador` en la entidad `Programa`.
- **Entidades MER:** ``Usuario`, `Coordinador`, `Programa`, `Institucion`, `Facultad`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Coordinador``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Institucion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Facultad`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.5: [PR-006] - Actualización Perfilada de Datos Personales de Usuario con Re-validación de Credenciales

- **Historias de Usuario:** HU050 (Gestión de cuentas de usuarios).
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad`
- **Perfil Aprobador Superior:** N/A (Acción Directa de Administrador Macro)
- **Intención de Negocio:** Actualizar de forma segura nombres, apellidos, correo y contraseña de un usuario existente, verificando la no duplicidad del correo con otros usuarios activos antes de confirmar los cambios.
- **Entidades MER:** ``Usuario`, `TipoIdentificacion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`TipoIdentificacion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.6: [PR-007] - Desactivación Reactiva de Usuario con Inactivación en Cascada de Roles

- **Historias de Usuario:** HU050 (Gestión del estado de usuarios y seguridad).
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad`
- **Perfil Aprobador Superior:** N/A (Acción Directa de Administrador Macro)
- **Intención de Negocio:** Cuando un usuario es inhabilitado (ej. por retiro de la universidad), la transacción marca `estado = 0` en `Usuario` y desactiva en cascada todos sus roles activos (`Docente`, `Estudiante`, `Coordinador`, `Decano`), evitando que conserve permisos en el sistema.
- **Entidades MER:** ``Usuario`, `Docente`, `Estudiante`, `Coordinador`, `Decano`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Docente``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Coordinador``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Decano`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.7: [PR-008] - Reactivación Integral de Usuario y Reincorporación a Estructuras Académicas

- **Historias de Usuario:** HU050.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad`
- **Perfil Aprobador Superior:** N/A (Acción Directa de Administrador Macro)
- **Intención de Negocio:** Reactivar un usuario previamente inhabilitado, cambiando su estado a activo y restaurando sus roles institucionales principales tras verificación administrativa.
- **Entidades MER:** ``Usuario`, `Docente`, `Estudiante`, `Coordinador`, `Decano`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Docente``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Coordinador``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Decano`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.8: [PR-010] - Conversión Reactiva de Rol (Promoción de Estudiante/Docente a Coordinador o Decano)

- **Historias de Usuario:** HU050, HU066, HU102.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Permitir que un usuario que ya posee el rol de `Estudiante` o `Docente` adquiera un nuevo rol de gestión (`Coordinador` o `Decano`) sin necesidad de duplicar su cuenta de usuario ni alterar su histórico académico previo.
- **Entidades MER:** ``Usuario`, `Docente`, `Estudiante`, `Coordinador`, `Decano`, `Institucion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Docente``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Coordinador``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Decano``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Validación de Entidad MER `dbo.`Institucion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  11. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.9: [PR-012] - Cambio de Contraseña y Expiración de Credenciales con Auditoría de Seguridad

- **Historias de Usuario:** HU050.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad`
- **Perfil Aprobador Superior:** N/A (Acción Directa de Administrador Macro)
- **Intención de Negocio:** Permite la actualización segura de la clave de acceso de un usuario previa validación de la contraseña anterior o token de recuperación, registrando la traza del cambio.
- **Entidades MER:** ``Usuario`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.10: [PR-017] - Asignación Reactiva de Administrador Institucional con Configuración de Alcance

- **Historias de Usuario:** HU050.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Otorga privilegios de administración global o de sede a un usuario existente o nuevo, vinculándolo a la entidad `Institucion`.
- **Entidades MER:** ``Usuario`, `Institucion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Institucion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.11: [PR-018] - Sincronización de Correo Electrónico Institucional y Actualización de Dominios Habilitados

- **Historias de Usuario:** HU050.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Actualizar el dominio del correo institucional de un grupo de usuarios cuando la universidad cambia su dominio de correo (ej. de `@uco.edu.co` a `@uco.edu`), manteniendo la integridad de las cuentas.
- **Entidades MER:** ``Usuario`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.12: [PR-020] - Inactivación Temporal de Docente con Suspensión de Asignaciones a Grupos Activos

- **Historias de Usuario:** HU052, HU050.
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Suspender temporalmente el rol de un docente (ej. por comisión de estudios o licencia médica) sin borrar su usuario, desvinculándolo reactivamente de los grupos activos donde figura como titular.
- **Entidades MER:** ``Usuario`, `Docente`, `Grupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Docente``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Grupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.13: [PR-021] - Inactivación Temporal de Estudiante con Suspensión de Matrículas en Periodo Académico

- **Historias de Usuario:** HU053, HU050.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Registrar la reserva de cupo o suspensión temporal de estudios de un alumno, inactivando su perfil de `Estudiante` y marcando sus matrículas activas en `EstudianteGrupo` como "SUSPENDIDA / CANCELADA VOLUNTARIA".
- **Entidades MER:** ``Usuario`, `Estudiante`, `EstudianteGrupo`, `EstadoEstudianteGrupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`EstadoEstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.14: [PR-024] - Validación de Unicidad de Correo e Identificación con Generación de Reporte de Inconsistencias

- **Historias de Usuario:** HU050.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad`
- **Perfil Aprobador Superior:** N/A (Acción Directa de Administrador Macro)
- **Intención de Negocio:** Procedimiento reactivo de diagnóstico e higiene de datos para detectar registros homónimos o colisiones de correo/documento antes de migraciones de periodo.
- **Entidades MER:** ``Usuario`, `TipoIdentificacion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`TipoIdentificacion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.15: [PR-032] - Crear Facultad con Vinculación Inmediata de Decano y Áreas Iniciales

- **Historias de Usuario:** HU102 (Gestión de Facultades).
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Dar de alta una `Facultad` académica asociándola a una `Institucion`, nombrando atómicamente a su `Decano` titular e inicializando sus áreas del conocimiento.
- **Entidades MER:** ``Facultad`, `Institucion`, `Decano`, `Area`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Facultad``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Institucion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Decano``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Area`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.16: [PR-033] - Crear Programa Académico con Coordinador Asignado, Tipo de Programa y Facultad

- **Historias de Usuario:** HU051, HU066.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Registrar una carrera profesional o posgrado (ej. Ingeniería de Sistemas). Asigna el `TipoPrograma`, lo vincula a la `Facultad` y nombra atómicamente al `Coordinador` responsable.
- **Entidades MER:** ``Programa`, `Facultad`, `TipoPrograma`, `Coordinador`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Facultad``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`TipoPrograma``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Coordinador`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.17: [PR-034] - Estructurar Plan de Estudio con Asignación Automática de Semestres Académicos

- **Historias de Usuario:** HU018, HU019.
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Crear la malla curricular (`PlanEstudio`) para un programa académico y generar automáticamente los registros de `SemestrePlanEstudio` para la cantidad de semestres definida (ej. 1 a 10 semestres).
- **Entidades MER:** ``PlanEstudio`, `Programa`, `Semestre`, `SemestrePlanEstudio`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`PlanEstudio``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Semestre``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`SemestrePlanEstudio`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.18: [PR-036] - Asociar Asignaturas a Semestres en el Plan de Estudios con Validación de Coherencia Curricular

- **Historias de Usuario:** HU025 (Consultar asignaturas por semestre en el plan de estudios).
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Asociar una asignatura a un semestre de un plan de estudios. La transacción valida atómicamente que no existan ciclos infinitos de prerrequisitos (ej. A depende de B y B depende de A).
- **Entidades MER:** ``Asignatura`, `SemestrePlanEstudio`, `PlanEstudio`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asignatura``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`SemestrePlanEstudio``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`PlanEstudio`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.19: [PR-037] - Inactivar Programa Académico con Verificación de Planes de Estudio y Estudiantes Inscritos

- **Historias de Usuario:** HU051, HU066.
- **Rol Requerido:** `DECANO`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Intención de Negocio:** Inactivar un programa académico que entra en liquidación o sustitución, deshabilitando sus nuevos ingresos mientras se protegen las matrículas de estudiantes activos hasta su graduación.
- **Entidades MER:** ``Programa`, `PlanEstudio`, `EstudiantePrograma`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`PlanEstudio``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudiantePrograma`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.20: [PR-038] - Crear Periodo Académico con Apertura de Calendario y Rangos de Fechas Validados

- **Historias de Usuario:** HU028, HU034, HU027.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Registrar un nuevo ciclo lectivo (ej. "2026-1"), definiendo atómicamente la fecha de inicio (`fechaInicio`) y fin (`fechaFin`) que regirán los rangos válidos para abrir sesiones y registrar asistencias.
- **Entidades MER:** ``PeriodoAcademico`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`PeriodoAcademico`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.21: [PR-039] - Actualizar Periodo Académico con Reprogramación de Rangos de Fechas en Sesiones y Grupos

- **Historias de Usuario:** HU028.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Reajustar las fechas de inicio o fin de un periodo lectivo en curso (ej. por extensiones del calendario académico), actualizando reactivamente los límites de vigencia de todos sus grupos y sesiones programadas.
- **Entidades MER:** ``PeriodoAcademico`, `Grupo`, `Sesion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`PeriodoAcademico``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.22: [PR-040] - Cierre Oficial de Periodo Académico con Consolidación de Estadísticas de Ausentismo

- **Historias de Usuario:** HU001, HU002, HU066, HU102.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Concluir formalmente un periodo académico. Cierra reactivamente todas las sesiones pendientes, congela las asistencias, calcula los porcentajes finales de inasistencia por estudiante/grupo y cambia `estado = 0` en `PeriodoAcademico`.
- **Entidades MER:** ``PeriodoAcademico`, `Grupo`, `Sesion`, `Asistencia`, `EstudianteGrupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`PeriodoAcademico``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.23: [PR-051] - Inactivar Facultad con Reubicación o Inactivación de Programas Académicos

- **Historias de Usuario:** HU102.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Inactivar una facultad universitaria reubicando o cerrando en cascada sus programas académicos adscritos.
- **Entidades MER:** ``Facultad`, `Programa`, `Decano`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Facultad``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Decano`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.24: [PR-053] - Actualizar Créditos y Horas Semanales de Asignatura con Recálculo de Intensidad

- **Historias de Usuario:** HU007.
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Modificar la intensidad horaria o créditos académicos de una materia, recalculando el número estimado de sesiones teóricas del periodo.
- **Entidades MER:** ``Asignatura`, `Grupo`, `Horario`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asignatura``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Horario`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.25: [PR-059] - Auditoría Cambios Malla Curricular y Planes de Estudio

- **Historias de Usuario:** HU019.
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Registrar en la bitácora de auditoría cualquier adición, modificación o retiro de asignaturas en los planes de estudio.
- **Entidades MER:** ``PlanEstudio`, `Asignatura`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`PlanEstudio``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asignatura`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.26: [PR-062] - Programación de Horario para Grupo con Validación de Cruces Horarios de Docente y Día

- **Historias de Usuario:** HU048 (Crear horarios para clases), HU034 (Validar cruce horario docente).
- **Rol Requerido:** `DECANO`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Intención de Negocio:** Asignar la franja horaria (`horaInicio` a `horaFin`) y el día (`Dia`) a un grupo. La transacción valida reactivamente que el docente asignado al grupo no tenga otra clase programada a esa misma hora en otro grupo.
- **Entidades MER:** ``Horario`, `Grupo`, `Dia`, `Docente`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Horario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Dia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Docente`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.27: [PR-064] - Cancelación de Grupo Académico con Desinscripción en Cascada y Liberación de Horarios

- **Historias de Usuario:** HU047 (Cancelar sesión/grupo), HU051 (Retirar estudiantes).
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Cancelar un grupo por baja matrícula u orden administrativa. Inactiva el grupo (`estado = 0`), cambia todas sus matrículas en `EstudianteGrupo` a "GRUPO_CANCELADO" e inactiva sus franjas horarias en una sola transacción atómica.
- **Entidades MER:** ``Grupo`, `EstudianteGrupo`, `Horario`, `Sesion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Horario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.28: [PR-065] - Modificación de Cupo Máximo de Grupo con Verificación de Matriculados Activos

- **Historias de Usuario:** HU044.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Ampliar o reducir la capacidad de estudiantes de un grupo, asegurando que el nuevo cupo no sea inferior al número de estudiantes ya matriculados activos.
- **Entidades MER:** ``Grupo`, `EstudianteGrupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.29: [PR-066] - Reprogramación de Horario de Grupo con Actualización Masiva de Fechas de Sesiones

- **Historias de Usuario:** HU049 (Modificar horarios), HU046 (Cambiar datos de sesión).
- **Rol Requerido:** `DECANO`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Intención de Negocio:** Modificar el día u hora de una clase ya iniciada en el periodo y recalcular atómicamente las fechas de las futuras sesiones programadas en la tabla `Sesion`.
- **Entidades MER:** ``Horario`, `Grupo`, `Sesion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Horario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.30: [PR-071] - Apertura Masiva de Grupos para Periodo Académico Basado en Oferta del Periodo Anterior

- **Historias de Usuario:** HU043.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Clonar la estructura de grupos de un periodo anterior para el nuevo periodo lectivo, agilizando la preparación del calendario académico.
- **Entidades MER:** ``Grupo`, `Horario`, `PeriodoAcademico`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Horario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`PeriodoAcademico`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.31: [PR-073] - Validar Cruces Horarios de Docente en Múltiples Grupos e Instituciones

- **Historias de Usuario:** HU034 (Validar consistencia horaria).
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Procedimiento de diagnóstico atómico que escanea todas las asignaciones horarias de un profesor en la universidad para certificar que no tenga traslapes de horas.
- **Entidades MER:** ``Docente`, `Grupo`, `Horario`, `Dia`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Docente``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Horario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Dia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.32: [PR-086] - Cierre Definitivo de Grupo Académico al Concluir el Periodo

- **Historias de Usuario:** HU044.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Concluir las actividades de un grupo, deshabilitando cualquier modificación a su plantilla y asistencias.
- **Entidades MER:** ``Grupo`, `Sesion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.33: [PR-092] - Matrícula Reactiva de Estudiante en Grupo con Validación de Asignaturas y Plan de Estudios, Cupos y Cruces Horarios

- **Historias de Usuario:** HU053 (Inscripción de estudiantes en grupo), HU026, HU034.
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Inscribir a un estudiante en una asignatura/grupo específica. Valida atómicamente el cupo disponible, la vigencia del grupo, los prerrequisitos de la asignatura y que el alumno no tenga colisión de horario con otras materias matriculadas.
- **Entidades MER:** ``EstudianteGrupo`, `Grupo`, `Estudiante`, `EstadoEstudianteGrupo`, `Horario`, `Asignatura`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`EstadoEstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Horario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Validación de Entidad MER `dbo.`Asignatura`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  11. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.34: [PR-093] - Matrícula Masiva por Lote de Estudiantes en Lista de Clases

- **Historias de Usuario:** HU053.
- **Rol Requerido:** `ESTUDIANTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`
- **Perfil Aprobador Superior:** DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)
- **Intención de Negocio:** Procesar masivamente el listado de alumnos para una sección antes del inicio de clases (ej. carga de archivo plano de admisiones).
- **Entidades MER:** ``EstudianteGrupo`, `Grupo`, `Estudiante`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ESTUDIANTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estudiante`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.35: [PR-094] - Cambio de Estado de Estudiante en Grupo (Activo, Retirado, Cancelado por Ausentismo)

- **Historias de Usuario:** HU004 (Ver estado de estudiante en grupo).
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Actualizar la condición administrativa de un estudiante dentro de un grupo (ej. cambiar de "MATRICULADO" a "RETIRADO_DISCIPLINARIO" o "CANCELADO_AUSENTISMO").
- **Entidades MER:** ``EstudianteGrupo`, `EstadoEstudianteGrupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstadoEstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.36: [PR-095] - Cancelación de Matrícula de Estudiante en Grupo por Solicitud Voluntaria

- **Historias de Usuario:** HU026, HU051.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Procesar el retiro voluntario de una materia por parte del alumno dentro de las fechas límites permitidas por el reglamento académico.
- **Entidades MER:** ``EstudianteGrupo`, `EstadoEstudianteGrupo`, `Grupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstadoEstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Grupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.37: [PR-096] - Cancelación Automática de Matrícula en Grupo por Exceso de Inasistencias

- **Historias de Usuario:** HU013, HU096.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Aplicar la norma reglamentaria de pérdida de materia por faltas. Cuando el porcentaje de inasistencias supera el límite (ej. 20%), el procedimiento cancela automáticamente la matrícula.
- **Entidades MER:** ``EstudianteGrupo`, `Asistencia`, `EstadoEstudianteGrupo`, `Sesion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstadoEstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.38: [PR-099] - Rechazo de Solicitud de Inscripción de Estudiante con Notificación y Liberación de Cupo

- **Historias de Usuario:** HU054 (Rechazar solicitud para unirse a grupo).
- **Rol Requerido:** `ESTUDIANTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`
- **Perfil Aprobador Superior:** DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)
- **Intención de Negocio:** Rechazar formalmente una petición de ingreso a un grupo con sobre-demanda.
- **Entidades MER:** ``EstudianteGrupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ESTUDIANTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.39: [PR-100] - Inactivación de Estudiante en Programa Académico por Retiro Definitivo o Graduación

- **Historias de Usuario:** HU051, HU100.
- **Rol Requerido:** `DECANO`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Intención de Negocio:** Dar de baja la vinculación de un alumno con su programa académico por graduación o deserción formal.
- **Entidades MER:** ``EstudiantePrograma`, `Programa`, `Estudiante`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudiantePrograma``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estudiante`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.40: [PR-101] - Reincorporación/Reingreso de Estudiante a Programa Académico

- **Historias de Usuario:** HU051.
- **Rol Requerido:** `DECANO`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Intención de Negocio:** Reactivar la ficha académica de un estudiante que vuelve a la universidad tras un periodo de retiro.
- **Entidades MER:** ``EstudiantePrograma`, `Estudiante`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudiantePrograma``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Estudiante`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.41: [PR-103] - Registro de Estudiante en Plan de Estudio Específico

- **Historias de Usuario:** HU019, HU051.
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Asignar la versión exacta de la malla curricular (`PlanEstudio`) a un estudiante dentro de su programa.
- **Entidades MER:** ``EstudiantePrograma`, `PlanEstudio`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudiantePrograma``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`PlanEstudio`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.42: [PR-106] - Enrolamiento Directo por Archivo Masivo CSV/Excel de Estudiantes en Grupos

- **Historias de Usuario:** HU053, HU050.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Importar la lista definitiva de matriculados enviada por la oficina de registro académico.
- **Entidades MER:** ``Usuario`, `Estudiante`, `EstudianteGrupo`, `Grupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Grupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.43: [PR-113] - Bloqueo Administrativo de Matrícula de Estudiante en Grupos

- **Historias de Usuario:** HU051.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Bloquear la facultad de un estudiante para inscribir nuevas materias por sanción disciplinaria o mora.
- **Entidades MER:** ``Estudiante`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Estudiante`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.44: [PR-114] - Desbloqueo Administrativo de Matrícula de Estudiante

- **Historias de Usuario:** HU051.
- **Rol Requerido:** `ESTUDIANTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`
- **Perfil Aprobador Superior:** DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)
- **Intención de Negocio:** Retirar la sanción administrativa permitiendo al alumno matricularse nuevamente.
- **Entidades MER:** ``Estudiante`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ESTUDIANTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Estudiante`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.45: [PR-122] - Toma de Asistencia Masiva por Lote en Sesión por el Docente

- **Historias de Usuario:** HU027 (Registrar asistencia), HU029, HU033.
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Guardar en un solo envío atómico desde la app toda la lista de clase con los estados de asistencia asignados a cada estudiante (Asistió, Faltó, Tarde).
- **Entidades MER:** ``Asistencia`, `Sesion`, `EstudianteGrupo`, `Estado`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Estado`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.46: [PR-123] - Registro de Asistencia Autónoma por Estudiante mediante QR/Token Dinámico

- **Historias de Usuario:** HU027 (Auto-registro de asistencia estudiante), HU053.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Permitir que el estudiante escanee el QR dinámico o ingrese el token de clase en su celular para registrar de forma autónoma su asistencia a la sesión activa.
- **Entidades MER:** ``Asistencia`, `Sesion`, `EstudianteGrupo`, `Estudiante`, `Estado`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Estado`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.47: [PR-125] - Modificación Atómica de Registro de Asistencia de un Estudiante en Sesión Específica

- **Historias de Usuario:** HU033 (Modificar asistencia tomada), HU027.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Permitir al docente corregir de forma individual la asistencia de un alumno (ej. cambiar de "FALTA" a "ASISTIO" o "JUSTIFICADA") tras verificar su presencia.
- **Entidades MER:** ``Asistencia`, `Estado`, `EstudianteGrupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Estado``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.48: [PR-126] - Cancelación de Sesión de Clase Programada con Notificación a Estudiantes

- **Historias de Usuario:** HU047 (Cancelar sesión).
- **Rol Requerido:** `DECANO`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Intención de Negocio:** Marcar una sesión como cancelada (ej. por calamidad del docente o suspensión institucional), evitando que compute como falta para los estudiantes.
- **Entidades MER:** ``Sesion`, `Asistencia`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.49: [PR-127] - Reprogramación de Sesión Cancelada en Nueva Fecha/Hora sin Cruces Horarios

- **Historias de Usuario:** HU045, HU046.
- **Rol Requerido:** `DECANO`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Intención de Negocio:** Agendar la reposición de una clase cancelada en una nueva fecha/hora, verificando previamente la disponibilidad del docente y del aula.
- **Entidades MER:** ``Sesion`, `Grupo`, `Docente`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Docente`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.50: [PR-129] - Toma de Asistencia por Escaneo Masivo de Código de Estudiante (Barcode/NFC)

- **Historias de Usuario:** HU027.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Permitir que el docente escanee rápidamente con el carné de los estudiantes (código de barras o NFC) para registrar la asistencia en tiempo real.
- **Entidades MER:** ``Asistencia`, `Sesion`, `Usuario`, `EstudianteGrupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.51: [PR-130] - Corrección Lote de Asistencia en Sesión por Error del Docente en el Llamado

- **Historias de Usuario:** HU033.
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Permitir re-enviar la plantilla completa de asistencia de una sesión previa para sobrescribir errores de marcaje cometidos por el docente.
- **Entidades MER:** ``Asistencia`, `Sesion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.52: [PR-132] - Consolidar Cierre Automático Nocturno de Sesiones Olvidadas Abiertas por Docentes

- **Historias de Usuario:** HU028, Configuración Ecosistema.
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Proceso batch automático ejecutado a medianoche. Detecta sesiones que quedaron en estado "ABIERTA" por olvido del docente, marcando las inasistencias omitidas y cerrándolas de forma segura.
- **Entidades MER:** ``Sesion`, `Asistencia`, `EstudianteGrupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.53: [PR-134] - Consulta de Plantilla de Asistencia en Tiempo Real para Sesión Activa

- **Historias de Usuario:** HU029 (Consultar listado de asistencia de sesión).
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Retornar al dispositivo del docente el estado actual de la toma de lista de la sesión en curso (cuántos asistieron, cuántos faltan y cuántos han marcado por QR).
- **Entidades MER:** ``Sesion`, `Asistencia`, `EstudianteGrupo`, `Usuario`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Usuario`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.54: [PR-136] - Bloqueo de Edición de Asistencia en Sesiones con Fecha Mayor a Límite Reglamentario

- **Historias de Usuario:** HU033.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Impedir que un docente modifique planillas de asistencia de clases dictadas hace más de 8 o 15 días, exigiendo solicitud de desbloqueo al coordinador (`PR-137`).
- **Entidades MER:** ``Sesion`, `Asistencia`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.55: [PR-139] - Generación de Token Dinámico / Código QR Temporal para Sesión por el Docente

- **Historias de Usuario:** HU028.
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Generar la clave encriptada/QR que cambia cada 30 segundos y que se proyecta en el aula para que los estudiantes registren su presencia.
- **Entidades MER:** ``Sesion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.56: [PR-140] - Validación de Token Dinámico de Asistencia y Expulsión por Token Vencido

- **Historias de Usuario:** HU027.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Verificar la autenticidad del token enviado por el celular del estudiante al hacer marcaje autónomo (`PR-123`).
- **Entidades MER:** ``Sesion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.57: [PR-141] - Registro de Asistencia en Modalidad Virtual / Remota con Enlace de Conexión

- **Historias de Usuario:** HU027.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Registrar el ingreso y tiempo de permanencia de estudiantes en clases dictadas a través de plataformas virtuales (Teams, Zoom).
- **Entidades MER:** ``Asistencia`, `Sesion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.58: [PR-143] - Marcaje de Asistencia Grupal Total por Evento Institucional / Salida de Campo

- **Historias de Usuario:** HU027, HU028.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Marcar atómicamente a TODO el grupo como "ASISTIO_EVENTO_INSTITUCIONAL" por actividades académicas autorizadas fuera del campus.
- **Entidades MER:** ``Asistencia`, `Sesion`, `Estado`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estado`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.59: [PR-145] - Verificación de Integridad entre `Sesion`, `EstudianteGrupo` y `Asistencia`

- **Historias de Usuario:** Configuración Ecosistema.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Procedimiento reactivo de mantenimiento que detecta asistencias registradas para estudiantes desvinculados o sesiones inconsistentes.
- **Entidades MER:** ``Asistencia`, `Sesion`, `EstudianteGrupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.60: [PR-146] - Re-apertura de Sesión Cerrada para Inclusión de Estudiante Extemporáneo

- **Historias de Usuario:** HU028, HU053.
- **Rol Requerido:** `ESTUDIANTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`
- **Perfil Aprobador Superior:** DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)
- **Intención de Negocio:** Reabrir temporalmente una sesión concluida para agregar la asistencia de un alumno matriculado tardíamente.
- **Entidades MER:** ``Sesion`, `Asistencia`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ESTUDIANTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.61: [PR-148] - Reporte Reactivo de Faltas Consecutivas en el Transcurso de las Sesiones

- **Historias de Usuario:** HU013, HU066.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Detectar cuando un estudiante acumula 3 o más faltas consecutivas en las últimas sesiones del grupo para alerta temprana de deserción.
- **Entidades MER:** ``Asistencia`, `Sesion`, `EstudianteGrupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.62: [PR-149] - Notificación Push / Correo Inmediata al Estudiante por Inasistencia Registrada

- **Historias de Usuario:** HU001, HU013.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Notificar al instante al estudiante en su celular cada vez que un profesor le marca una falta o llegada tarde en clase.
- **Entidades MER:** ``Asistencia`, `Usuario`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Usuario`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.63: [PR-152] - Resolver Solicitud de Justificación por el Docente (Aprobación/Rechazo + Cambio Atómico en `Asistencia`)

- **Historias de Usuario:** HU035 (Ver solicitudes de revisión pendientes), HU037 (Aprobar/Rechazar justificaciones).
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Permite al profesor evaluar la solicitud del alumno. Si se aprueba, la transacción actualiza atómicamente la solicitud a "APROBADA" y modifica el campo `estado` en `Asistencia` a "JUSTIFICADA", recalculando el porcentaje de faltas acumuladas en un solo paso.
- **Entidades MER:** ``SolicitudRevisionAsistencia`, `Asistencia`, `Estado`, `EstudianteGrupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`SolicitudRevisionAsistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estado``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.64: [PR-154] - Cancelación de Solicitud de Revisión por el Estudiante antes de ser Evaluada

- **Historias de Usuario:** HU010.
- **Rol Requerido:** `ESTUDIANTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`
- **Perfil Aprobador Superior:** DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)
- **Intención de Negocio:** Permitir que el estudiante retire voluntariamente su solicitud de revisión si la radicó por error o con datos incorrectos.
- **Entidades MER:** ``SolicitudRevisionAsistencia`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ESTUDIANTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`SolicitudRevisionAsistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.65: [PR-155] - Generación de Alerta Temprana de Ausentismo Crítico al Superar Umbral

- **Historias de Usuario:** HU013 (Recibir alertas de ausentismo), HU066.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad`
- **Perfil Aprobador Superior:** N/A (Acción Directa de Administrador Macro)
- **Intención de Negocio:** Disparar de forma reactiva una alerta visual y por correo cuando el % de inasistencias de un alumno alcanza el 15% (Advertencia) o el 20% (Pérdida por inasistencias).
- **Entidades MER:** ``Asistencia`, `EstudianteGrupo`, `Grupo`, `Usuario`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Usuario`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.66: [PR-156] - Envío de Notificación Consolidada a Coordinación por Estudiantes en Riesgo

- **Historias de Usuario:** HU066, HU013.
- **Rol Requerido:** `ESTUDIANTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`
- **Perfil Aprobador Superior:** DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)
- **Intención de Negocio:** Generar un reporte periódico automático para la coordinación con la lista de alumnos que superaron el umbral crítico de faltas en cualquier asignatura de la facultad.
- **Entidades MER:** ``EstudianteGrupo`, `Grupo`, `Programa`, `Usuario`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ESTUDIANTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Usuario`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.67: [PR-157] - Emisión de Certificado Oficial de Porcentaje de Asistencia por Asignatura

- **Historias de Usuario:** HU001, HU002.
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Generar el reporte oficial en PDF/XML de asistencias acumuladas de un estudiante para trámites de becas o patrocinios institucionales.
- **Entidades MER:** ``Estudiante`, `EstudianteGrupo`, `Asistencia`, `Grupo`, `Sesion`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.68: [PR-158] - Registro de Razón / Causa de Inasistencia Institucional (Mantenimiento de Catálogo)

- **Historias de Usuario:** HU005, HU016, HU042.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Dar de alta o actualizar las opciones del catálogo `RazonCausa` (ej. "Incapacidad Médica EPS", "Calamidad Doméstica Comprobada", "Cita Judicial", "Representación Deportiva").
- **Entidades MER:** ``RazonCausa`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`RazonCausa`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.69: [PR-159] - Consulta Consolidada de Histórico de Asistencias del Estudiante (`uv_asistencia`)

- **Historias de Usuario:** HU001 (Ver detalles de inasistencias), HU002 (Consultar histórico).
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Retornar en una vista/procedimiento de lectura ultra-rápida todo el expediente de asistencias del estudiante a lo largo de su carrera.
- **Entidades MER:** ``Asistencia`, `EstudianteGrupo`, `Sesion`, `Grupo`, `Asignatura`, `Estado`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Asignatura``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Validación de Entidad MER `dbo.`Estado`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  11. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.70: [PR-160] - Consulta Consolidada de Estadísticas de Asistencia por Grupo (`uv_estadistica_grupo`)

- **Historias de Usuario:** HU060, HU066.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Retornar a la coordinación el resumen estadístico de un grupo (% de asistencia promedio, número de estudiantes en riesgo, total de clases dictadas).
- **Entidades MER:** ``Grupo`, `Sesion`, `Asistencia`, `EstudianteGrupo`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.71: [PR-161] - Generación de Reporte Macro de Deserción y Ausentismo para Decanatura por Facultad

- **Historias de Usuario:** HU102 (Reportes macro decanatura).
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Consolidar métricas a nivel gerencial para el Decano, mostrando los programas académicos y materias con mayor índice de inasistencias en la Facultad.
- **Entidades MER:** ``Facultad`, `Programa`, `Grupo`, `Asistencia`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Facultad``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Asistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.72: [PR-163] - Reabrir Solicitud de Revisión Rechazada por Presentación de Nuevo Soporte Oficial

- **Historias de Usuario:** HU010, HU037.
- **Rol Requerido:** `ESTUDIANTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`
- **Perfil Aprobador Superior:** DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)
- **Intención de Negocio:** Permitir que una solicitud que fue rechazada se reabra si el estudiante presenta una excusa oficial expedida posteriormente por bienestar o secretaría académica.
- **Entidades MER:** ``SolicitudRevisionAsistencia`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ESTUDIANTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`SolicitudRevisionAsistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.73: [PR-169] - Generación de Indicador KPI de Cumplimiento de Toma de Lista por Docente

- **Historias de Usuario:** HU060 (Monitorear docentes que no siguen el proceso).
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Calcular el porcentaje de clases en las que cada profesor tomó asistencia a tiempo vs sesiones olvidadas o cerradas por el sistema.
- **Entidades MER:** ``Docente`, `Grupo`, `Sesion`, `Asistencia`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Docente``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Asistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.74: [PR-170] - Exportación Registros de Asistencia a Formato Oficial de Acta de Notas y Faltas

- **Historias de Usuario:** HU027, HU029, HU040.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Consolidar en un solo archivo plano u objeto de salida la lista de estudiantes de un grupo con sus calificaciones y faltas totales al cerrar el semestre.
- **Entidades MER:** ``Grupo`, `EstudianteGrupo`, `Asistencia`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Asistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.75: [PR-171] - Consulta de Solicitudes de Justificación Vencidas Sin Respuesta del Docente

- **Historias de Usuario:** HU035, HU171.
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Listar aquellas solicitudes de revisión de asistencia que llevan más de 5 días hábiles en estado "PENDIENTE" sin que el docente las haya aprobado o rechazado.
- **Entidades MER:** ``SolicitudRevisionAsistencia`, `Grupo`, `Docente`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`SolicitudRevisionAsistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Docente`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.76: [PR-172] - Aprobación Automática de Justificación por Silencio Administrativo del Docente

- **Historias de Usuario:** HU010, HU037.
- **Rol Requerido:** `COORDINADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Intención de Negocio:** Aplicar el principio de silencio administrativo positivo. Si un docente no responde una justificación médica en más de 10 días, el sistema aprueba automáticamente la excusa y marca la asistencia como "JUSTIFICADA".
- **Entidades MER:** ``SolicitudRevisionAsistencia`, `Asistencia`, `Estado`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`SolicitudRevisionAsistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estado`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.77: [PR-175] - Consolidación de Histórico Académico de Asistencias para Proceso de Graduación

- **Historias de Usuario:** HU002.
- **Rol Requerido:** `DOCENTE`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Intención de Negocio:** Certificar que un estudiante candidato a grado cumplió con el requisito institucional de porcentaje mínimo de asistencia en todas las asignaturas de su plan de estudio.
- **Entidades MER:** ``Estudiante`, `EstudiantePrograma`, `EstudianteGrupo`, `Asistencia`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstudiantePrograma``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Asistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.

### Transacción 1.78: [PR-179] - Respaldar y Archivar Registros de Asistencia de Periodos Académicos Históricos

- **Historias de Usuario:** Mantenimiento y Rendimiento BD.
- **Rol Requerido:** `ADMINISTRADOR`
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Intención de Negocio:** Mover registros de `Asistencia` y `Sesion` de hace más de 5 años a tablas de archivo histórico para optimizar la velocidad y el tamaño de las tablas operativas principales.
- **Entidades MER:** ``Asistencia`, `Sesion`, `PeriodoAcademico`.`
- **Lógica de Validación Específica Línea por Línea:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`PeriodoAcademico`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
- **Procedimientos internos invocados:** `usp_validar_id_correlacion_esta_presente_interno`, `usp_validar_unicidad_usuario_interno`, `usp_obtener_mensaje_catalogo`.


---

# PARTE 2: Matriz Técnica de Mapeo Jerárquico (SP vs API Rest Backend)


## Módulo 1: Gestión de Usuarios e Identidades

| Entidad MER | Accion de Negocio | Procedimiento BD | Método API Backend | Rol Operador | Perfil Aprobador | Trazabilidad Nodo Padre-Raíz |
|:---|:---|:---|:---|:---|:---|:---|
| ``Usuario`` | Registrar Docente Institucional en Grupo (Creación/Actualización Reactiva de Usuario + Rol Docente + Asignación a Grupo) | `dbo.usp_registrar_docente_en_grupo_usuario_no_existente` | `POST /api/v1/operaciones/pr_002` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``Usuario`` | Registrar Estudiante Institucional en Grupo (Sincronización + Perfil Estudiante + Programa + Matrícula en Grupo) | `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente` | `POST /api/v1/operaciones/pr_003` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``Usuario`` | Asignar Decano a Facultad con Validación/Creación de Usuario e Inactivación de Decano Previo | `dbo.usp_crear_decano` | `POST /api/v1/operaciones/pr_004` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``Usuario`` | Asignar Coordinador a Programa Académico con Actualización Reactiva y Transferencia de Dirección | `dbo.usp_crear_coordinador` | `POST /api/v1/operaciones/pr_005` | `DECANO` | DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa) | `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador` |
| ``Usuario`` | Actualización Perfilada de Datos Personales de Usuario con Re-validación de Credenciales | `dbo.usp_sincronizar_usuario` | `POST /api/v1/operaciones/pr_006` | `ADMINISTRADOR` | N/A (Acción Directa de Administrador Macro) | `Institución (Nodo Raíz) -> Facultad` |
| ``Usuario`` | Desactivación Reactiva de Usuario con Inactivación en Cascada de Roles | `dbo.usp_sincronizar_usuario` | `POST /api/v1/operaciones/pr_007` | `ADMINISTRADOR` | N/A (Acción Directa de Administrador Macro) | `Institución (Nodo Raíz) -> Facultad` |
| ``Usuario`` | Reactivación Integral de Usuario y Reincorporación a Estructuras Académicas | `dbo.usp_sincronizar_usuario` | `POST /api/v1/operaciones/pr_008` | `ADMINISTRADOR` | N/A (Acción Directa de Administrador Macro) | `Institución (Nodo Raíz) -> Facultad` |
| ``Usuario`` | Conversión Reactiva de Rol (Promoción de Estudiante/Docente a Coordinador o Decano) | `dbo.usp_crear_decano` | `POST /api/v1/operaciones/pr_010` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``Usuario`.` | Cambio de Contraseña y Expiración de Credenciales con Auditoría de Seguridad | `dbo.usp_sincronizar_usuario` | `POST /api/v1/operaciones/pr_012` | `ADMINISTRADOR` | N/A (Acción Directa de Administrador Macro) | `Institución (Nodo Raíz) -> Facultad` |
| ``Usuario`` | Asignación Reactiva de Administrador Institucional con Configuración de Alcance | `dbo.usp_sincronizar_usuario` | `POST /api/v1/operaciones/pr_017` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``Usuario`.` | Sincronización de Correo Electrónico Institucional y Actualización de Dominios Habilitados | `dbo.usp_sincronizar_usuario` | `POST /api/v1/operaciones/pr_018` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``Usuario`` | Inactivación Temporal de Docente con Suspensión de Asignaciones a Grupos Activos | `dbo.usp_registrar_docente_en_grupo_usuario_no_existente` | `POST /api/v1/operaciones/pr_020` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``Usuario`` | Inactivación Temporal de Estudiante con Suspensión de Matrículas en Periodo Académico | `dbo.usp_ejecutar_cierre_masivo_periodo` | `POST /api/v1/operaciones/pr_021` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``Usuario`` | Validación de Unicidad de Correo e Identificación con Generación de Reporte de Inconsistencias | `dbo.usp_sincronizar_usuario` | `GET /api/v1/operaciones/pr_024` | `ADMINISTRADOR` | N/A (Acción Directa de Administrador Macro) | `Institución (Nodo Raíz) -> Facultad` |
| ``Facultad`` | Crear Facultad con Vinculación Inmediata de Decano y Áreas Iniciales | `dbo.usp_crear_decano` | `POST /api/v1/operaciones/pr_032` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``Programa`` | Crear Programa Académico con Coordinador Asignado, Tipo de Programa y Facultad | `dbo.usp_crear_coordinador` | `POST /api/v1/operaciones/pr_033` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``PlanEstudio`` | Estructurar Plan de Estudio con Asignación Automática de Semestres Académicos | `dbo.usp_registrar_o_actualizar_plan_estudio` | `POST /api/v1/operaciones/pr_034` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``Asignatura`` | Asociar Asignaturas a Semestres en el Plan de Estudios con Validación de Coherencia Curricular | `dbo.usp_registrar_o_actualizar_asignatura` | `POST /api/v1/operaciones/pr_036` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``Programa`` | Inactivar Programa Académico con Verificación de Planes de Estudio y Estudiantes Inscritos | `dbo.usp_registrar_o_actualizar_programa_academico` | `POST /api/v1/operaciones/pr_037` | `DECANO` | DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa) | `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador` |
| ``PeriodoAcademico`.` | Crear Periodo Académico con Apertura de Calendario y Rangos de Fechas Validados | `dbo.usp_ejecutar_cierre_masivo_periodo` | `POST /api/v1/operaciones/pr_038` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``PeriodoAcademico`` | Actualizar Periodo Académico con Reprogramación de Rangos de Fechas en Sesiones y Grupos | `dbo.usp_registrar_o_actualizar_programa_academico` | `POST /api/v1/operaciones/pr_039` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``PeriodoAcademico`` | Cierre Oficial de Periodo Académico con Consolidación de Estadísticas de Ausentismo | `dbo.usp_ejecutar_cierre_masivo_periodo` | `POST /api/v1/operaciones/pr_040` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``Facultad`` | Inactivar Facultad con Reubicación o Inactivación de Programas Académicos | `dbo.usp_registrar_o_actualizar_programa_academico` | `POST /api/v1/operaciones/pr_051` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``Asignatura`` | Actualizar Créditos y Horas Semanales de Asignatura con Recálculo de Intensidad | `dbo.usp_registrar_o_actualizar_asignatura` | `POST /api/v1/operaciones/pr_053` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``PlanEstudio`` | Auditoría Cambios Malla Curricular y Planes de Estudio | `dbo.usp_registrar_o_actualizar_plan_estudio` | `POST /api/v1/operaciones/pr_059` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``Horario`` | Programación de Horario para Grupo con Validación de Cruces Horarios de Docente y Día | `dbo.usp_registrar_docente_en_grupo_usuario_no_existente` | `POST /api/v1/operaciones/pr_062` | `DECANO` | DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa) | `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador` |
| ``Grupo`` | Cancelación de Grupo Académico con Desinscripción en Cascada y Liberación de Horarios | `dbo.usp_crear_grupo` | `POST /api/v1/operaciones/pr_064` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``Grupo`` | Modificación de Cupo Máximo de Grupo con Verificación de Matriculados Activos | `dbo.usp_crear_grupo` | `POST /api/v1/operaciones/pr_065` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``Horario`` | Reprogramación de Horario de Grupo con Actualización Masiva de Fechas de Sesiones | `dbo.usp_registrar_o_actualizar_programa_academico` | `POST /api/v1/operaciones/pr_066` | `DECANO` | DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa) | `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador` |
| ``Grupo`` | Apertura Masiva de Grupos para Periodo Académico Basado en Oferta del Periodo Anterior | `dbo.usp_crear_grupo` | `POST /api/v1/operaciones/pr_071` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``Docente`` | Validar Cruces Horarios de Docente en Múltiples Grupos e Instituciones | `dbo.usp_registrar_docente_en_grupo_usuario_no_existente` | `POST /api/v1/operaciones/pr_073` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``Grupo`` | Cierre Definitivo de Grupo Académico al Concluir el Periodo | `dbo.usp_crear_grupo` | `POST /api/v1/operaciones/pr_086` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``EstudianteGrupo`` | Matrícula Reactiva de Estudiante en Grupo con Validación de Asignaturas y Plan de Estudios, Cupos y Cruces Horarios | `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente` | `POST /api/v1/operaciones/pr_092` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``EstudianteGrupo`` | Matrícula Masiva por Lote de Estudiantes en Lista de Clases | `dbo.usp_sincronizar_usuario` | `POST /api/v1/operaciones/pr_093` | `ESTUDIANTE` | DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA) | `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia` |
| ``EstudianteGrupo`` | Cambio de Estado de Estudiante en Grupo (Activo, Retirado, Cancelado por Ausentismo) | `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente` | `POST /api/v1/operaciones/pr_094` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``EstudianteGrupo`` | Cancelación de Matrícula de Estudiante en Grupo por Solicitud Voluntaria | `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente` | `POST /api/v1/operaciones/pr_095` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``EstudianteGrupo`` | Cancelación Automática de Matrícula en Grupo por Exceso de Inasistencias | `dbo.usp_crear_grupo` | `POST /api/v1/operaciones/pr_096` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``EstudianteGrupo`.` | Rechazo de Solicitud de Inscripción de Estudiante con Notificación y Liberación de Cupo | `dbo.usp_radicar_solicitud_revision_asistencia` | `POST /api/v1/operaciones/pr_099` | `ESTUDIANTE` | DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA) | `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia` |
| ``EstudiantePrograma`` | Inactivación de Estudiante en Programa Académico por Retiro Definitivo o Graduación | `dbo.usp_registrar_o_actualizar_programa_academico` | `POST /api/v1/operaciones/pr_100` | `DECANO` | DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa) | `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador` |
| ``EstudiantePrograma`` | Reincorporación/Reingreso de Estudiante a Programa Académico | `dbo.usp_registrar_o_actualizar_programa_academico` | `POST /api/v1/operaciones/pr_101` | `DECANO` | DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa) | `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador` |
| ``EstudiantePrograma`` | Registro de Estudiante en Plan de Estudio Específico | `dbo.usp_registrar_o_actualizar_plan_estudio` | `POST /api/v1/operaciones/pr_103` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``Usuario`` | Enrolamiento Directo por Archivo Masivo CSV/Excel de Estudiantes en Grupos | `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente` | `POST /api/v1/operaciones/pr_106` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``Estudiante`.` | Bloqueo Administrativo de Matrícula de Estudiante en Grupos | `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente` | `POST /api/v1/operaciones/pr_113` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``Estudiante`.` | Desbloqueo Administrativo de Matrícula de Estudiante | `dbo.usp_sincronizar_usuario` | `POST /api/v1/operaciones/pr_114` | `ESTUDIANTE` | DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA) | `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia` |
| ``Asistencia`` | Toma de Asistencia Masiva por Lote en Sesión por el Docente | `dbo.usp_registrar_asistencias_sesion` | `POST /api/v1/operaciones/pr_122` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``Asistencia`` | Registro de Asistencia Autónoma por Estudiante mediante QR/Token Dinámico | `dbo.usp_registrar_asistencias_sesion` | `POST /api/v1/operaciones/pr_123` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``Asistencia`` | Modificación Atómica de Registro de Asistencia de un Estudiante en Sesión Específica | `dbo.usp_registrar_asistencias_sesion` | `POST /api/v1/operaciones/pr_125` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``Sesion`` | Cancelación de Sesión de Clase Programada con Notificación a Estudiantes | `dbo.usp_registrar_o_actualizar_programa_academico` | `POST /api/v1/operaciones/pr_126` | `DECANO` | DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa) | `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador` |
| ``Sesion`` | Reprogramación de Sesión Cancelada en Nueva Fecha/Hora sin Cruces Horarios | `dbo.usp_registrar_o_actualizar_programa_academico` | `POST /api/v1/operaciones/pr_127` | `DECANO` | DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa) | `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador` |
| ``Asistencia`` | Toma de Asistencia por Escaneo Masivo de Código de Estudiante (Barcode/NFC) | `dbo.usp_registrar_asistencias_sesion` | `POST /api/v1/operaciones/pr_129` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``Asistencia`` | Corrección Lote de Asistencia en Sesión por Error del Docente en el Llamado | `dbo.usp_registrar_asistencias_sesion` | `POST /api/v1/operaciones/pr_130` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``Sesion`` | Consolidar Cierre Automático Nocturno de Sesiones Olvidadas Abiertas por Docentes | `dbo.usp_crear_sesion` | `POST /api/v1/operaciones/pr_132` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``Sesion`` | Consulta de Plantilla de Asistencia en Tiempo Real para Sesión Activa | `dbo.usp_registrar_o_actualizar_plan_estudio` | `GET /api/v1/operaciones/pr_134` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``Sesion`` | Bloqueo de Edición de Asistencia en Sesiones con Fecha Mayor a Límite Reglamentario | `dbo.usp_crear_sesion` | `POST /api/v1/operaciones/pr_136` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``Sesion`.` | Generación de Token Dinámico / Código QR Temporal para Sesión por el Docente | `dbo.usp_sincronizar_usuario` | `POST /api/v1/operaciones/pr_139` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``Sesion`.` | Validación de Token Dinámico de Asistencia y Expulsión por Token Vencido | `dbo.usp_registrar_asistencias_sesion` | `POST /api/v1/operaciones/pr_140` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``Asistencia`` | Registro de Asistencia en Modalidad Virtual / Remota con Enlace de Conexión | `dbo.usp_registrar_asistencias_sesion` | `POST /api/v1/operaciones/pr_141` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``Asistencia`` | Marcaje de Asistencia Grupal Total por Evento Institucional / Salida de Campo | `dbo.usp_registrar_asistencias_sesion` | `POST /api/v1/operaciones/pr_143` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``Asistencia`` | Verificación de Integridad entre `Sesion`, `EstudianteGrupo` y `Asistencia` | `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente` | `POST /api/v1/operaciones/pr_145` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``Sesion`` | Re-apertura de Sesión Cerrada para Inclusión de Estudiante Extemporáneo | `dbo.usp_sincronizar_usuario` | `POST /api/v1/operaciones/pr_146` | `ESTUDIANTE` | DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA) | `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia` |
| ``Asistencia`` | Reporte Reactivo de Faltas Consecutivas en el Transcurso de las Sesiones | `dbo.usp_crear_sesion` | `GET /api/v1/operaciones/pr_148` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``Asistencia`` | Notificación Push / Correo Inmediata al Estudiante por Inasistencia Registrada | `dbo.usp_registrar_asistencias_sesion` | `POST /api/v1/operaciones/pr_149` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``SolicitudRevisionAsistencia`` | Resolver Solicitud de Justificación por el Docente (Aprobación/Rechazo + Cambio Atómico en `Asistencia`) | `dbo.usp_registrar_asistencias_sesion` | `POST /api/v1/operaciones/pr_152` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``SolicitudRevisionAsistencia`.` | Cancelación de Solicitud de Revisión por el Estudiante antes de ser Evaluada | `dbo.usp_radicar_solicitud_revision_asistencia` | `POST /api/v1/operaciones/pr_154` | `ESTUDIANTE` | DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA) | `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia` |
| ``Asistencia`` | Generación de Alerta Temprana de Ausentismo Crítico al Superar Umbral | `dbo.usp_sincronizar_usuario` | `POST /api/v1/operaciones/pr_155` | `ADMINISTRADOR` | N/A (Acción Directa de Administrador Macro) | `Institución (Nodo Raíz) -> Facultad` |
| ``EstudianteGrupo`` | Envío de Notificación Consolidada a Coordinación por Estudiantes en Riesgo | `dbo.usp_sincronizar_usuario` | `POST /api/v1/operaciones/pr_156` | `ESTUDIANTE` | DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA) | `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia` |
| ``Estudiante`` | Emisión de Certificado Oficial de Porcentaje de Asistencia por Asignatura | `dbo.usp_registrar_o_actualizar_asignatura` | `POST /api/v1/operaciones/pr_157` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``RazonCausa`.` | Registro de Razón / Causa de Inasistencia Institucional (Mantenimiento de Catálogo) | `dbo.usp_registrar_asistencias_sesion` | `POST /api/v1/operaciones/pr_158` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``Asistencia`` | Consulta Consolidada de Histórico de Asistencias del Estudiante (`uv_asistencia`) | `dbo.usp_registrar_asistencias_sesion` | `GET /api/v1/operaciones/pr_159` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``Grupo`` | Consulta Consolidada de Estadísticas de Asistencia por Grupo (`uv_estadistica_grupo`) | `dbo.usp_crear_grupo` | `GET /api/v1/operaciones/pr_160` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``Facultad`` | Generación de Reporte Macro de Deserción y Ausentismo para Decanatura por Facultad | `dbo.usp_sincronizar_usuario` | `GET /api/v1/operaciones/pr_161` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |
| ``SolicitudRevisionAsistencia`.` | Reabrir Solicitud de Revisión Rechazada por Presentación de Nuevo Soporte Oficial | `dbo.usp_radicar_solicitud_revision_asistencia` | `POST /api/v1/operaciones/pr_163` | `ESTUDIANTE` | DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA) | `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia` |
| ``Docente`` | Generación de Indicador KPI de Cumplimiento de Toma de Lista por Docente | `dbo.usp_sincronizar_usuario` | `POST /api/v1/operaciones/pr_169` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``Grupo`` | Exportación Registros de Asistencia a Formato Oficial de Acta de Notas y Faltas | `dbo.usp_registrar_asistencias_sesion` | `POST /api/v1/operaciones/pr_170` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``SolicitudRevisionAsistencia`` | Consulta de Solicitudes de Justificación Vencidas Sin Respuesta del Docente | `dbo.usp_radicar_solicitud_revision_asistencia` | `GET /api/v1/operaciones/pr_171` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``SolicitudRevisionAsistencia`` | Aprobación Automática de Justificación por Silencio Administrativo del Docente | `dbo.usp_sincronizar_usuario` | `POST /api/v1/operaciones/pr_172` | `COORDINADOR` | COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular) | `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente` |
| ``Estudiante`` | Consolidación de Histórico Académico de Asistencias para Proceso de Graduación | `dbo.usp_registrar_asistencias_sesion` | `POST /api/v1/operaciones/pr_175` | `DOCENTE` | DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones) | `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante` |
| ``Asistencia`` | Respaldar y Archivar Registros de Asistencia de Periodos Académicos Históricos | `dbo.usp_registrar_asistencias_sesion` | `POST /api/v1/operaciones/pr_179` | `ADMINISTRADOR` | N/A (Nivel Superior Administrador) | `Institución (Nodo Raíz) -> Facultad / Periodo` |

## Operaciones Simples sin SP (Backend Directo con Jerarquía de Ámbito)

| Tabla | Acción de Negocio | Adaptador Backend | Endpoint API | Rol Operador | Jerarquía Padre-Raíz |
|:---|:---|:---|:---|:---|:---|
| `Institucion` | Crear Institución | `InstitucionRepositorySqlServerAdapter` | `POST /api/v1/admin/instituciones` | `ADMINISTRADOR` | Nodo Raíz Macro |
| `Facultad` | Crear Facultad | `FacultadRepositorySqlServerAdapter` | `POST /api/v1/admin/facultades` | `ADMINISTRADOR` | Institución -> Facultad |
| `PlanEstudio` | Crear Plan de Estudio | `PlanEstudioRepositorySqlServerAdapter` | `POST /api/v1/coordinador/planes` | `COORDINADOR` | Facultad -> Programa -> PlanEstudio |
| `Horario` | Asignar Franja Horaria | `HorarioRepositorySqlServerAdapter` | `POST /api/v1/grupos/horarios` | `COORDINADOR` / `DOCENTE` | Programa -> Grupo -> Horario |


## Consultas sobre Vistas Relacionales (`uv_*` con Filtro de Jerarquía)

| Vista SQL | Propósito de Consulta | Endpoint API | Rol Operador | Filtro Jerárquico en Query |
|:---|:---|:---|:---|:---|
| `uv_estudiante` | Directorio de estudiantes | `GET /api/v1/estudiantes` | `COORDINADOR` | Filtrar por programa del coordinador |
| `uv_docente` | Directorio de docentes | `GET /api/v1/docentes` | `COORDINADOR` | Filtrar por programa/facultad |
| `uv_grupo` | Consulta de grupos | `GET /api/v1/grupos` | `DOCENTE` | `WHERE docenteId = idUsuario` |
| `uv_sesion` | Consulta de sesiones de clase | `GET /api/v1/sesiones` | `DOCENTE` | `WHERE docenteId = idUsuario` |
| `uv_asistencia` | Histórico de asistencias | `GET /api/v1/asistencias` | `ESTUDIANTE` | `WHERE estudianteId = idUsuario` |


---

# PARTE 3: Especificación Detallada de Endpoints y Contratos REST API

### Endpoint 3.1: `POST /api/v1/operaciones/pr_002`

- **Transacción / PR:** `[PR-002]` - Registrar Docente Institucional en Grupo (Creación/Actualización Reactiva de Usuario + Rol Docente + Asignación a Grupo)
- **Historia de Usuario Satisfecha:** HU052 (Registro de docentes en grupos con validación de existencia), HU050 (Sincronización de usuarios).
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_registrar_docente_en_grupo_usuario_no_existente`
- **Propósito:** Permite asignar un docente a un grupo académico en un solo paso. Si la persona no está registrada como usuario o no tiene perfil de docente instituido, la transacción lo crea y categoriza reactivamente antes de vincularlo al grupo, evitando fallos por clave foránea o datos incompletos.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-002",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Docente``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Institucion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_docente_en_grupo_usuario_no_existente` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-002 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-002",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.2: `POST /api/v1/operaciones/pr_003`

- **Transacción / PR:** `[PR-003]` - Registrar Estudiante Institucional en Grupo (Sincronización + Perfil Estudiante + Programa + Matrícula en Grupo)
- **Historia de Usuario Satisfecha:** HU053 (Registro e inscripción de estudiantes en grupos académicos), HU051 (Registro en programas académicos), HU050.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente`
- **Propósito:** Orquesta el enrolamiento completo de un estudiante en un grupo. Registra/actualiza al usuario, le otorga el rol de `Estudiante`, lo inscribe en el `Programa` correspondiente a la asignatura del grupo si no lo está, y finalmente lo matricula en `EstudianteGrupo` con estado activo.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-003",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudiantePrograma``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Validación de Entidad MER `dbo.`Asignatura``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  11. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  12. **Validación de Entidad MER `dbo.`EstadoEstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  13. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-003 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-003",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.3: `POST /api/v1/operaciones/pr_004`

- **Transacción / PR:** `[PR-004]` - Asignar Decano a Facultad con Validación/Creación de Usuario e Inactivación de Decano Previo
- **Historia de Usuario Satisfecha:** HU102 (Gestión macro de facultades y decanaturas), HU050.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_crear_decano`
- **Propósito:** Garantizar que una facultad tenga exactamente un Decano activo titular. Si ya existía un decano previo en la facultad, lo inactiva o desvincula en la misma transacción antes de promover al nuevo usuario y asignarlo a la `Facultad`.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-004",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Decano``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Facultad``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Institucion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_crear_decano` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-004 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-004",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.4: `POST /api/v1/operaciones/pr_005`

- **Transacción / PR:** `[PR-005]` - Asignar Coordinador a Programa Académico con Actualización Reactiva y Transferencia de Dirección
- **Historia de Usuario Satisfecha:** HU066 (Gestión de coordinación de programas), HU050.
- **Rol Operador:** `DECANO`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Objeto BD:** `dbo.usp_crear_coordinador`
- **Propósito:** Permite asignar la dirección de un programa académico a un profesional. Crea/actualiza la cuenta de usuario, le asigna el rol de `Coordinador` institucional y actualiza la FK `coordinador` en la entidad `Programa`.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-005",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DECANO`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
* **Flujo de Registro Autónomo y Aprobación:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Coordinador``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Institucion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Facultad`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_crear_coordinador` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-005 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-005",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DECANO` o violó la jerarquía de pertenencia de nodo padre (`Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.5: `POST /api/v1/operaciones/pr_006`

- **Transacción / PR:** `[PR-006]` - Actualización Perfilada de Datos Personales de Usuario con Re-validación de Credenciales
- **Historia de Usuario Satisfecha:** HU050 (Gestión de cuentas de usuarios).
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Acción Directa de Administrador Macro)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Actualizar de forma segura nombres, apellidos, correo y contraseña de un usuario existente, verificando la no duplicidad del correo con otros usuarios activos antes de confirmar los cambios.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-006",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`TipoIdentificacion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-006 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-006",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Acción Directa de Administrador Macro)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.6: `POST /api/v1/operaciones/pr_007`

- **Transacción / PR:** `[PR-007]` - Desactivación Reactiva de Usuario con Inactivación en Cascada de Roles
- **Historia de Usuario Satisfecha:** HU050 (Gestión del estado de usuarios y seguridad).
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Acción Directa de Administrador Macro)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Cuando un usuario es inhabilitado (ej. por retiro de la universidad), la transacción marca `estado = 0` en `Usuario` y desactiva en cascada todos sus roles activos (`Docente`, `Estudiante`, `Coordinador`, `Decano`), evitando que conserve permisos en el sistema.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-007",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Docente``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Coordinador``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Decano`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-007 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-007",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Acción Directa de Administrador Macro)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.7: `POST /api/v1/operaciones/pr_008`

- **Transacción / PR:** `[PR-008]` - Reactivación Integral de Usuario y Reincorporación a Estructuras Académicas
- **Historia de Usuario Satisfecha:** HU050.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Acción Directa de Administrador Macro)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Reactivar un usuario previamente inhabilitado, cambiando su estado a activo y restaurando sus roles institucionales principales tras verificación administrativa.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-008",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Docente``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Coordinador``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Decano`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-008 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-008",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Acción Directa de Administrador Macro)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.8: `POST /api/v1/operaciones/pr_010`

- **Transacción / PR:** `[PR-010]` - Conversión Reactiva de Rol (Promoción de Estudiante/Docente a Coordinador o Decano)
- **Historia de Usuario Satisfecha:** HU050, HU066, HU102.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_crear_decano`
- **Propósito:** Permitir que un usuario que ya posee el rol de `Estudiante` o `Docente` adquiera un nuevo rol de gestión (`Coordinador` o `Decano`) sin necesidad de duplicar su cuenta de usuario ni alterar su histórico académico previo.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-010",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Docente``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Coordinador``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Decano``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Validación de Entidad MER `dbo.`Institucion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  11. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_crear_decano` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-010 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-010",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.9: `POST /api/v1/operaciones/pr_012`

- **Transacción / PR:** `[PR-012]` - Cambio de Contraseña y Expiración de Credenciales con Auditoría de Seguridad
- **Historia de Usuario Satisfecha:** HU050.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Acción Directa de Administrador Macro)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Permite la actualización segura de la clave de acceso de un usuario previa validación de la contraseña anterior o token de recuperación, registrando la traza del cambio.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-012",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-012 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-012",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Acción Directa de Administrador Macro)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.10: `POST /api/v1/operaciones/pr_017`

- **Transacción / PR:** `[PR-017]` - Asignación Reactiva de Administrador Institucional con Configuración de Alcance
- **Historia de Usuario Satisfecha:** HU050.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Otorga privilegios de administración global o de sede a un usuario existente o nuevo, vinculándolo a la entidad `Institucion`.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-017",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Institucion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-017 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-017",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.11: `POST /api/v1/operaciones/pr_018`

- **Transacción / PR:** `[PR-018]` - Sincronización de Correo Electrónico Institucional y Actualización de Dominios Habilitados
- **Historia de Usuario Satisfecha:** HU050.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Actualizar el dominio del correo institucional de un grupo de usuarios cuando la universidad cambia su dominio de correo (ej. de `@uco.edu.co` a `@uco.edu`), manteniendo la integridad de las cuentas.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-018",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-018 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-018",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.12: `POST /api/v1/operaciones/pr_020`

- **Transacción / PR:** `[PR-020]` - Inactivación Temporal de Docente con Suspensión de Asignaciones a Grupos Activos
- **Historia de Usuario Satisfecha:** HU052, HU050.
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_registrar_docente_en_grupo_usuario_no_existente`
- **Propósito:** Suspender temporalmente el rol de un docente (ej. por comisión de estudios o licencia médica) sin borrar su usuario, desvinculándolo reactivamente de los grupos activos donde figura como titular.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-020",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Docente``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Grupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_docente_en_grupo_usuario_no_existente` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-020 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-020",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.13: `POST /api/v1/operaciones/pr_021`

- **Transacción / PR:** `[PR-021]` - Inactivación Temporal de Estudiante con Suspensión de Matrículas en Periodo Académico
- **Historia de Usuario Satisfecha:** HU053, HU050.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_ejecutar_cierre_masivo_periodo`
- **Propósito:** Registrar la reserva de cupo o suspensión temporal de estudios de un alumno, inactivando su perfil de `Estudiante` y marcando sus matrículas activas en `EstudianteGrupo` como "SUSPENDIDA / CANCELADA VOLUNTARIA".

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-021",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`EstadoEstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_ejecutar_cierre_masivo_periodo` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-021 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-021",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.14: `GET /api/v1/operaciones/pr_024`

- **Transacción / PR:** `[PR-024]` - Validación de Unicidad de Correo e Identificación con Generación de Reporte de Inconsistencias
- **Historia de Usuario Satisfecha:** HU050.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Acción Directa de Administrador Macro)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Procedimiento reactivo de diagnóstico e higiene de datos para detectar registros homónimos o colisiones de correo/documento antes de migraciones de periodo.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-024",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`TipoIdentificacion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-024 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-024",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Acción Directa de Administrador Macro)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.15: `POST /api/v1/operaciones/pr_032`

- **Transacción / PR:** `[PR-032]` - Crear Facultad con Vinculación Inmediata de Decano y Áreas Iniciales
- **Historia de Usuario Satisfecha:** HU102 (Gestión de Facultades).
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_crear_decano`
- **Propósito:** Dar de alta una `Facultad` académica asociándola a una `Institucion`, nombrando atómicamente a su `Decano` titular e inicializando sus áreas del conocimiento.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-032",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Facultad``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Institucion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Decano``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Area`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_crear_decano` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-032 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-032",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.16: `POST /api/v1/operaciones/pr_033`

- **Transacción / PR:** `[PR-033]` - Crear Programa Académico con Coordinador Asignado, Tipo de Programa y Facultad
- **Historia de Usuario Satisfecha:** HU051, HU066.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_crear_coordinador`
- **Propósito:** Registrar una carrera profesional o posgrado (ej. Ingeniería de Sistemas). Asigna el `TipoPrograma`, lo vincula a la `Facultad` y nombra atómicamente al `Coordinador` responsable.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-033",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Facultad``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`TipoPrograma``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Coordinador`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_crear_coordinador` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-033 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-033",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.17: `POST /api/v1/operaciones/pr_034`

- **Transacción / PR:** `[PR-034]` - Estructurar Plan de Estudio con Asignación Automática de Semestres Académicos
- **Historia de Usuario Satisfecha:** HU018, HU019.
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_registrar_o_actualizar_plan_estudio`
- **Propósito:** Crear la malla curricular (`PlanEstudio`) para un programa académico y generar automáticamente los registros de `SemestrePlanEstudio` para la cantidad de semestres definida (ej. 1 a 10 semestres).

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-034",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`PlanEstudio``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Semestre``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`SemestrePlanEstudio`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_o_actualizar_plan_estudio` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-034 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-034",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.18: `POST /api/v1/operaciones/pr_036`

- **Transacción / PR:** `[PR-036]` - Asociar Asignaturas a Semestres en el Plan de Estudios con Validación de Coherencia Curricular
- **Historia de Usuario Satisfecha:** HU025 (Consultar asignaturas por semestre en el plan de estudios).
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_registrar_o_actualizar_asignatura`
- **Propósito:** Asociar una asignatura a un semestre de un plan de estudios. La transacción valida atómicamente que no existan ciclos infinitos de prerrequisitos (ej. A depende de B y B depende de A).

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-036",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asignatura``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`SemestrePlanEstudio``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`PlanEstudio`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_o_actualizar_asignatura` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-036 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-036",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.19: `POST /api/v1/operaciones/pr_037`

- **Transacción / PR:** `[PR-037]` - Inactivar Programa Académico con Verificación de Planes de Estudio y Estudiantes Inscritos
- **Historia de Usuario Satisfecha:** HU051, HU066.
- **Rol Operador:** `DECANO`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Objeto BD:** `dbo.usp_registrar_o_actualizar_programa_academico`
- **Propósito:** Inactivar un programa académico que entra en liquidación o sustitución, deshabilitando sus nuevos ingresos mientras se protegen las matrículas de estudiantes activos hasta su graduación.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-037",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DECANO`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
* **Flujo de Registro Autónomo y Aprobación:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`PlanEstudio``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudiantePrograma`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_o_actualizar_programa_academico` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-037 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-037",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DECANO` o violó la jerarquía de pertenencia de nodo padre (`Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.20: `POST /api/v1/operaciones/pr_038`

- **Transacción / PR:** `[PR-038]` - Crear Periodo Académico con Apertura de Calendario y Rangos de Fechas Validados
- **Historia de Usuario Satisfecha:** HU028, HU034, HU027.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_ejecutar_cierre_masivo_periodo`
- **Propósito:** Registrar un nuevo ciclo lectivo (ej. "2026-1"), definiendo atómicamente la fecha de inicio (`fechaInicio`) y fin (`fechaFin`) que regirán los rangos válidos para abrir sesiones y registrar asistencias.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-038",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`PeriodoAcademico`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_ejecutar_cierre_masivo_periodo` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-038 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-038",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.21: `POST /api/v1/operaciones/pr_039`

- **Transacción / PR:** `[PR-039]` - Actualizar Periodo Académico con Reprogramación de Rangos de Fechas en Sesiones y Grupos
- **Historia de Usuario Satisfecha:** HU028.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_registrar_o_actualizar_programa_academico`
- **Propósito:** Reajustar las fechas de inicio o fin de un periodo lectivo en curso (ej. por extensiones del calendario académico), actualizando reactivamente los límites de vigencia de todos sus grupos y sesiones programadas.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-039",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`PeriodoAcademico``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_o_actualizar_programa_academico` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-039 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-039",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.22: `POST /api/v1/operaciones/pr_040`

- **Transacción / PR:** `[PR-040]` - Cierre Oficial de Periodo Académico con Consolidación de Estadísticas de Ausentismo
- **Historia de Usuario Satisfecha:** HU001, HU002, HU066, HU102.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_ejecutar_cierre_masivo_periodo`
- **Propósito:** Concluir formalmente un periodo académico. Cierra reactivamente todas las sesiones pendientes, congela las asistencias, calcula los porcentajes finales de inasistencia por estudiante/grupo y cambia `estado = 0` en `PeriodoAcademico`.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-040",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`PeriodoAcademico``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_ejecutar_cierre_masivo_periodo` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-040 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-040",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.23: `POST /api/v1/operaciones/pr_051`

- **Transacción / PR:** `[PR-051]` - Inactivar Facultad con Reubicación o Inactivación de Programas Académicos
- **Historia de Usuario Satisfecha:** HU102.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_registrar_o_actualizar_programa_academico`
- **Propósito:** Inactivar una facultad universitaria reubicando o cerrando en cascada sus programas académicos adscritos.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-051",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Facultad``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Decano`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_o_actualizar_programa_academico` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-051 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-051",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.24: `POST /api/v1/operaciones/pr_053`

- **Transacción / PR:** `[PR-053]` - Actualizar Créditos y Horas Semanales de Asignatura con Recálculo de Intensidad
- **Historia de Usuario Satisfecha:** HU007.
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_registrar_o_actualizar_asignatura`
- **Propósito:** Modificar la intensidad horaria o créditos académicos de una materia, recalculando el número estimado de sesiones teóricas del periodo.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-053",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asignatura``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Horario`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_o_actualizar_asignatura` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-053 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-053",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.25: `POST /api/v1/operaciones/pr_059`

- **Transacción / PR:** `[PR-059]` - Auditoría Cambios Malla Curricular y Planes de Estudio
- **Historia de Usuario Satisfecha:** HU019.
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_registrar_o_actualizar_plan_estudio`
- **Propósito:** Registrar en la bitácora de auditoría cualquier adición, modificación o retiro de asignaturas en los planes de estudio.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-059",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`PlanEstudio``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asignatura`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_o_actualizar_plan_estudio` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-059 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-059",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.26: `POST /api/v1/operaciones/pr_062`

- **Transacción / PR:** `[PR-062]` - Programación de Horario para Grupo con Validación de Cruces Horarios de Docente y Día
- **Historia de Usuario Satisfecha:** HU048 (Crear horarios para clases), HU034 (Validar cruce horario docente).
- **Rol Operador:** `DECANO`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Objeto BD:** `dbo.usp_registrar_docente_en_grupo_usuario_no_existente`
- **Propósito:** Asignar la franja horaria (`horaInicio` a `horaFin`) y el día (`Dia`) a un grupo. La transacción valida reactivamente que el docente asignado al grupo no tenga otra clase programada a esa misma hora en otro grupo.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-062",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DECANO`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
* **Flujo de Registro Autónomo y Aprobación:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Horario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Dia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Docente`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_docente_en_grupo_usuario_no_existente` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-062 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-062",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DECANO` o violó la jerarquía de pertenencia de nodo padre (`Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.27: `POST /api/v1/operaciones/pr_064`

- **Transacción / PR:** `[PR-064]` - Cancelación de Grupo Académico con Desinscripción en Cascada y Liberación de Horarios
- **Historia de Usuario Satisfecha:** HU047 (Cancelar sesión/grupo), HU051 (Retirar estudiantes).
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_crear_grupo`
- **Propósito:** Cancelar un grupo por baja matrícula u orden administrativa. Inactiva el grupo (`estado = 0`), cambia todas sus matrículas en `EstudianteGrupo` a "GRUPO_CANCELADO" e inactiva sus franjas horarias en una sola transacción atómica.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-064",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Horario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_crear_grupo` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-064 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-064",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.28: `POST /api/v1/operaciones/pr_065`

- **Transacción / PR:** `[PR-065]` - Modificación de Cupo Máximo de Grupo con Verificación de Matriculados Activos
- **Historia de Usuario Satisfecha:** HU044.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_crear_grupo`
- **Propósito:** Ampliar o reducir la capacidad de estudiantes de un grupo, asegurando que el nuevo cupo no sea inferior al número de estudiantes ya matriculados activos.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-065",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_crear_grupo` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-065 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-065",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.29: `POST /api/v1/operaciones/pr_066`

- **Transacción / PR:** `[PR-066]` - Reprogramación de Horario de Grupo con Actualización Masiva de Fechas de Sesiones
- **Historia de Usuario Satisfecha:** HU049 (Modificar horarios), HU046 (Cambiar datos de sesión).
- **Rol Operador:** `DECANO`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Objeto BD:** `dbo.usp_registrar_o_actualizar_programa_academico`
- **Propósito:** Modificar el día u hora de una clase ya iniciada en el periodo y recalcular atómicamente las fechas de las futuras sesiones programadas en la tabla `Sesion`.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-066",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DECANO`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
* **Flujo de Registro Autónomo y Aprobación:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Horario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_o_actualizar_programa_academico` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-066 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-066",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DECANO` o violó la jerarquía de pertenencia de nodo padre (`Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.30: `POST /api/v1/operaciones/pr_071`

- **Transacción / PR:** `[PR-071]` - Apertura Masiva de Grupos para Periodo Académico Basado en Oferta del Periodo Anterior
- **Historia de Usuario Satisfecha:** HU043.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_crear_grupo`
- **Propósito:** Clonar la estructura de grupos de un periodo anterior para el nuevo periodo lectivo, agilizando la preparación del calendario académico.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-071",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Horario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`PeriodoAcademico`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_crear_grupo` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-071 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-071",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.31: `POST /api/v1/operaciones/pr_073`

- **Transacción / PR:** `[PR-073]` - Validar Cruces Horarios de Docente en Múltiples Grupos e Instituciones
- **Historia de Usuario Satisfecha:** HU034 (Validar consistencia horaria).
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_registrar_docente_en_grupo_usuario_no_existente`
- **Propósito:** Procedimiento de diagnóstico atómico que escanea todas las asignaciones horarias de un profesor en la universidad para certificar que no tenga traslapes de horas.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-073",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Docente``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Horario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Dia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_docente_en_grupo_usuario_no_existente` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-073 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-073",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.32: `POST /api/v1/operaciones/pr_086`

- **Transacción / PR:** `[PR-086]` - Cierre Definitivo de Grupo Académico al Concluir el Periodo
- **Historia de Usuario Satisfecha:** HU044.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_crear_grupo`
- **Propósito:** Concluir las actividades de un grupo, deshabilitando cualquier modificación a su plantilla y asistencias.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-086",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_crear_grupo` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-086 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-086",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.33: `POST /api/v1/operaciones/pr_092`

- **Transacción / PR:** `[PR-092]` - Matrícula Reactiva de Estudiante en Grupo con Validación de Asignaturas y Plan de Estudios, Cupos y Cruces Horarios
- **Historia de Usuario Satisfecha:** HU053 (Inscripción de estudiantes en grupo), HU026, HU034.
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente`
- **Propósito:** Inscribir a un estudiante en una asignatura/grupo específica. Valida atómicamente el cupo disponible, la vigencia del grupo, los prerrequisitos de la asignatura y que el alumno no tenga colisión de horario con otras materias matriculadas.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-092",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`EstadoEstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Horario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Validación de Entidad MER `dbo.`Asignatura`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  11. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-092 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-092",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.34: `POST /api/v1/operaciones/pr_093`

- **Transacción / PR:** `[PR-093]` - Matrícula Masiva por Lote de Estudiantes en Lista de Clases
- **Historia de Usuario Satisfecha:** HU053.
- **Rol Operador:** `ESTUDIANTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Procesar masivamente el listado de alumnos para una sección antes del inicio de clases (ej. carga de archivo plano de admisiones).

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-093",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ESTUDIANTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ESTUDIANTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estudiante`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-093 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-093",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ESTUDIANTE` o violó la jerarquía de pertenencia de nodo padre (`Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.35: `POST /api/v1/operaciones/pr_094`

- **Transacción / PR:** `[PR-094]` - Cambio de Estado de Estudiante en Grupo (Activo, Retirado, Cancelado por Ausentismo)
- **Historia de Usuario Satisfecha:** HU004 (Ver estado de estudiante en grupo).
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente`
- **Propósito:** Actualizar la condición administrativa de un estudiante dentro de un grupo (ej. cambiar de "MATRICULADO" a "RETIRADO_DISCIPLINARIO" o "CANCELADO_AUSENTISMO").

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-094",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstadoEstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-094 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-094",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.36: `POST /api/v1/operaciones/pr_095`

- **Transacción / PR:** `[PR-095]` - Cancelación de Matrícula de Estudiante en Grupo por Solicitud Voluntaria
- **Historia de Usuario Satisfecha:** HU026, HU051.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente`
- **Propósito:** Procesar el retiro voluntario de una materia por parte del alumno dentro de las fechas límites permitidas por el reglamento académico.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-095",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstadoEstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Grupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-095 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-095",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.37: `POST /api/v1/operaciones/pr_096`

- **Transacción / PR:** `[PR-096]` - Cancelación Automática de Matrícula en Grupo por Exceso de Inasistencias
- **Historia de Usuario Satisfecha:** HU013, HU096.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_crear_grupo`
- **Propósito:** Aplicar la norma reglamentaria de pérdida de materia por faltas. Cuando el porcentaje de inasistencias supera el límite (ej. 20%), el procedimiento cancela automáticamente la matrícula.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-096",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstadoEstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_crear_grupo` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-096 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-096",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.38: `POST /api/v1/operaciones/pr_099`

- **Transacción / PR:** `[PR-099]` - Rechazo de Solicitud de Inscripción de Estudiante con Notificación y Liberación de Cupo
- **Historia de Usuario Satisfecha:** HU054 (Rechazar solicitud para unirse a grupo).
- **Rol Operador:** `ESTUDIANTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`
- **Objeto BD:** `dbo.usp_radicar_solicitud_revision_asistencia`
- **Propósito:** Rechazar formalmente una petición de ingreso a un grupo con sobre-demanda.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-099",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ESTUDIANTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ESTUDIANTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_radicar_solicitud_revision_asistencia` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-099 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-099",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ESTUDIANTE` o violó la jerarquía de pertenencia de nodo padre (`Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.39: `POST /api/v1/operaciones/pr_100`

- **Transacción / PR:** `[PR-100]` - Inactivación de Estudiante en Programa Académico por Retiro Definitivo o Graduación
- **Historia de Usuario Satisfecha:** HU051, HU100.
- **Rol Operador:** `DECANO`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Objeto BD:** `dbo.usp_registrar_o_actualizar_programa_academico`
- **Propósito:** Dar de baja la vinculación de un alumno con su programa académico por graduación o deserción formal.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-100",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DECANO`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
* **Flujo de Registro Autónomo y Aprobación:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudiantePrograma``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estudiante`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_o_actualizar_programa_academico` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-100 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-100",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DECANO` o violó la jerarquía de pertenencia de nodo padre (`Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.40: `POST /api/v1/operaciones/pr_101`

- **Transacción / PR:** `[PR-101]` - Reincorporación/Reingreso de Estudiante a Programa Académico
- **Historia de Usuario Satisfecha:** HU051.
- **Rol Operador:** `DECANO`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Objeto BD:** `dbo.usp_registrar_o_actualizar_programa_academico`
- **Propósito:** Reactivar la ficha académica de un estudiante que vuelve a la universidad tras un periodo de retiro.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-101",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DECANO`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
* **Flujo de Registro Autónomo y Aprobación:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudiantePrograma``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Estudiante`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_o_actualizar_programa_academico` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-101 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-101",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DECANO` o violó la jerarquía de pertenencia de nodo padre (`Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.41: `POST /api/v1/operaciones/pr_103`

- **Transacción / PR:** `[PR-103]` - Registro de Estudiante en Plan de Estudio Específico
- **Historia de Usuario Satisfecha:** HU019, HU051.
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_registrar_o_actualizar_plan_estudio`
- **Propósito:** Asignar la versión exacta de la malla curricular (`PlanEstudio`) a un estudiante dentro de su programa.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-103",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudiantePrograma``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`PlanEstudio`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_o_actualizar_plan_estudio` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-103 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-103",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.42: `POST /api/v1/operaciones/pr_106`

- **Transacción / PR:** `[PR-106]` - Enrolamiento Directo por Archivo Masivo CSV/Excel de Estudiantes en Grupos
- **Historia de Usuario Satisfecha:** HU053, HU050.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente`
- **Propósito:** Importar la lista definitiva de matriculados enviada por la oficina de registro académico.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-106",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Grupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-106 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-106",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.43: `POST /api/v1/operaciones/pr_113`

- **Transacción / PR:** `[PR-113]` - Bloqueo Administrativo de Matrícula de Estudiante en Grupos
- **Historia de Usuario Satisfecha:** HU051.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente`
- **Propósito:** Bloquear la facultad de un estudiante para inscribir nuevas materias por sanción disciplinaria o mora.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-113",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Estudiante`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-113 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-113",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.44: `POST /api/v1/operaciones/pr_114`

- **Transacción / PR:** `[PR-114]` - Desbloqueo Administrativo de Matrícula de Estudiante
- **Historia de Usuario Satisfecha:** HU051.
- **Rol Operador:** `ESTUDIANTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Retirar la sanción administrativa permitiendo al alumno matricularse nuevamente.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-114",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ESTUDIANTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ESTUDIANTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Estudiante`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-114 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-114",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ESTUDIANTE` o violó la jerarquía de pertenencia de nodo padre (`Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.45: `POST /api/v1/operaciones/pr_122`

- **Transacción / PR:** `[PR-122]` - Toma de Asistencia Masiva por Lote en Sesión por el Docente
- **Historia de Usuario Satisfecha:** HU027 (Registrar asistencia), HU029, HU033.
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_registrar_asistencias_sesion`
- **Propósito:** Guardar en un solo envío atómico desde la app toda la lista de clase con los estados de asistencia asignados a cada estudiante (Asistió, Faltó, Tarde).

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-122",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Estado`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_asistencias_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-122 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-122",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.46: `POST /api/v1/operaciones/pr_123`

- **Transacción / PR:** `[PR-123]` - Registro de Asistencia Autónoma por Estudiante mediante QR/Token Dinámico
- **Historia de Usuario Satisfecha:** HU027 (Auto-registro de asistencia estudiante), HU053.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_registrar_asistencias_sesion`
- **Propósito:** Permitir que el estudiante escanee el QR dinámico o ingrese el token de clase en su celular para registrar de forma autónoma su asistencia a la sesión activa.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-123",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Estado`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_asistencias_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-123 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-123",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.47: `POST /api/v1/operaciones/pr_125`

- **Transacción / PR:** `[PR-125]` - Modificación Atómica de Registro de Asistencia de un Estudiante en Sesión Específica
- **Historia de Usuario Satisfecha:** HU033 (Modificar asistencia tomada), HU027.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_registrar_asistencias_sesion`
- **Propósito:** Permitir al docente corregir de forma individual la asistencia de un alumno (ej. cambiar de "FALTA" a "ASISTIO" o "JUSTIFICADA") tras verificar su presencia.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-125",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Estado``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_asistencias_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-125 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-125",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.48: `POST /api/v1/operaciones/pr_126`

- **Transacción / PR:** `[PR-126]` - Cancelación de Sesión de Clase Programada con Notificación a Estudiantes
- **Historia de Usuario Satisfecha:** HU047 (Cancelar sesión).
- **Rol Operador:** `DECANO`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Objeto BD:** `dbo.usp_registrar_o_actualizar_programa_academico`
- **Propósito:** Marcar una sesión como cancelada (ej. por calamidad del docente o suspensión institucional), evitando que compute como falta para los estudiantes.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-126",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DECANO`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
* **Flujo de Registro Autónomo y Aprobación:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_o_actualizar_programa_academico` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-126 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-126",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DECANO` o violó la jerarquía de pertenencia de nodo padre (`Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.49: `POST /api/v1/operaciones/pr_127`

- **Transacción / PR:** `[PR-127]` - Reprogramación de Sesión Cancelada en Nueva Fecha/Hora sin Cruces Horarios
- **Historia de Usuario Satisfecha:** HU045, HU046.
- **Rol Operador:** `DECANO`
- **Perfil Aprobador Superior:** DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`
- **Objeto BD:** `dbo.usp_registrar_o_actualizar_programa_academico`
- **Propósito:** Agendar la reposición de una clase cancelada en una nueva fecha/hora, verificando previamente la disponibilidad del docente y del aula.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-127",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DECANO`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
* **Flujo de Registro Autónomo y Aprobación:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DECANO` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Docente`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El Coordinador o Programa queda registrado y vinculado a la Facultad tras la validación de la Decanatura.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_o_actualizar_programa_academico` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-127 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-127",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DECANO` o violó la jerarquía de pertenencia de nodo padre (`Institución (Raíz) -> Facultad -> Decano -> Programa -> Coordinador`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DECANO (Acepta/Nombra al Coordinador y aprueba la apertura del Programa)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.50: `POST /api/v1/operaciones/pr_129`

- **Transacción / PR:** `[PR-129]` - Toma de Asistencia por Escaneo Masivo de Código de Estudiante (Barcode/NFC)
- **Historia de Usuario Satisfecha:** HU027.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_registrar_asistencias_sesion`
- **Propósito:** Permitir que el docente escanee rápidamente con el carné de los estudiantes (código de barras o NFC) para registrar la asistencia en tiempo real.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-129",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Usuario``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_asistencias_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-129 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-129",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.51: `POST /api/v1/operaciones/pr_130`

- **Transacción / PR:** `[PR-130]` - Corrección Lote de Asistencia en Sesión por Error del Docente en el Llamado
- **Historia de Usuario Satisfecha:** HU033.
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_registrar_asistencias_sesion`
- **Propósito:** Permitir re-enviar la plantilla completa de asistencia de una sesión previa para sobrescribir errores de marcaje cometidos por el docente.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-130",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_asistencias_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-130 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-130",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.52: `POST /api/v1/operaciones/pr_132`

- **Transacción / PR:** `[PR-132]` - Consolidar Cierre Automático Nocturno de Sesiones Olvidadas Abiertas por Docentes
- **Historia de Usuario Satisfecha:** HU028, Configuración Ecosistema.
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_crear_sesion`
- **Propósito:** Proceso batch automático ejecutado a medianoche. Detecta sesiones que quedaron en estado "ABIERTA" por olvido del docente, marcando las inasistencias omitidas y cerrándolas de forma segura.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-132",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_crear_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-132 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-132",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.53: `GET /api/v1/operaciones/pr_134`

- **Transacción / PR:** `[PR-134]` - Consulta de Plantilla de Asistencia en Tiempo Real para Sesión Activa
- **Historia de Usuario Satisfecha:** HU029 (Consultar listado de asistencia de sesión).
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_registrar_o_actualizar_plan_estudio`
- **Propósito:** Retornar al dispositivo del docente el estado actual de la toma de lista de la sesión en curso (cuántos asistieron, cuántos faltan y cuántos han marcado por QR).

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-134",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Usuario`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_o_actualizar_plan_estudio` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-134 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-134",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.54: `POST /api/v1/operaciones/pr_136`

- **Transacción / PR:** `[PR-136]` - Bloqueo de Edición de Asistencia en Sesiones con Fecha Mayor a Límite Reglamentario
- **Historia de Usuario Satisfecha:** HU033.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_crear_sesion`
- **Propósito:** Impedir que un docente modifique planillas de asistencia de clases dictadas hace más de 8 o 15 días, exigiendo solicitud de desbloqueo al coordinador (`PR-137`).

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-136",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_crear_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-136 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-136",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.55: `POST /api/v1/operaciones/pr_139`

- **Transacción / PR:** `[PR-139]` - Generación de Token Dinámico / Código QR Temporal para Sesión por el Docente
- **Historia de Usuario Satisfecha:** HU028.
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Generar la clave encriptada/QR que cambia cada 30 segundos y que se proyecta en el aula para que los estudiantes registren su presencia.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-139",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-139 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-139",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.56: `POST /api/v1/operaciones/pr_140`

- **Transacción / PR:** `[PR-140]` - Validación de Token Dinámico de Asistencia y Expulsión por Token Vencido
- **Historia de Usuario Satisfecha:** HU027.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_registrar_asistencias_sesion`
- **Propósito:** Verificar la autenticidad del token enviado por el celular del estudiante al hacer marcaje autónomo (`PR-123`).

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-140",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_asistencias_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-140 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-140",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.57: `POST /api/v1/operaciones/pr_141`

- **Transacción / PR:** `[PR-141]` - Registro de Asistencia en Modalidad Virtual / Remota con Enlace de Conexión
- **Historia de Usuario Satisfecha:** HU027.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_registrar_asistencias_sesion`
- **Propósito:** Registrar el ingreso y tiempo de permanencia de estudiantes en clases dictadas a través de plataformas virtuales (Teams, Zoom).

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-141",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_asistencias_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-141 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-141",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.58: `POST /api/v1/operaciones/pr_143`

- **Transacción / PR:** `[PR-143]` - Marcaje de Asistencia Grupal Total por Evento Institucional / Salida de Campo
- **Historia de Usuario Satisfecha:** HU027, HU028.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_registrar_asistencias_sesion`
- **Propósito:** Marcar atómicamente a TODO el grupo como "ASISTIO_EVENTO_INSTITUCIONAL" por actividades académicas autorizadas fuera del campus.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-143",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estado`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_asistencias_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-143 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-143",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.59: `POST /api/v1/operaciones/pr_145`

- **Transacción / PR:** `[PR-145]` - Verificación de Integridad entre `Sesion`, `EstudianteGrupo` y `Asistencia`
- **Historia de Usuario Satisfecha:** Configuración Ecosistema.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente`
- **Propósito:** Procedimiento reactivo de mantenimiento que detecta asistencias registradas para estudiantes desvinculados o sesiones inconsistentes.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-145",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-145 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-145",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.60: `POST /api/v1/operaciones/pr_146`

- **Transacción / PR:** `[PR-146]` - Re-apertura de Sesión Cerrada para Inclusión de Estudiante Extemporáneo
- **Historia de Usuario Satisfecha:** HU028, HU053.
- **Rol Operador:** `ESTUDIANTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Reabrir temporalmente una sesión concluida para agregar la asistencia de un alumno matriculado tardíamente.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-146",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ESTUDIANTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ESTUDIANTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-146 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-146",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ESTUDIANTE` o violó la jerarquía de pertenencia de nodo padre (`Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.61: `GET /api/v1/operaciones/pr_148`

- **Transacción / PR:** `[PR-148]` - Reporte Reactivo de Faltas Consecutivas en el Transcurso de las Sesiones
- **Historia de Usuario Satisfecha:** HU013, HU066.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_crear_sesion`
- **Propósito:** Detectar cuando un estudiante acumula 3 o más faltas consecutivas en las últimas sesiones del grupo para alerta temprana de deserción.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-148",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_crear_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-148 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-148",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.62: `POST /api/v1/operaciones/pr_149`

- **Transacción / PR:** `[PR-149]` - Notificación Push / Correo Inmediata al Estudiante por Inasistencia Registrada
- **Historia de Usuario Satisfecha:** HU001, HU013.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_registrar_asistencias_sesion`
- **Propósito:** Notificar al instante al estudiante en su celular cada vez que un profesor le marca una falta o llegada tarde en clase.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-149",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Usuario`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_asistencias_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-149 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-149",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.63: `POST /api/v1/operaciones/pr_152`

- **Transacción / PR:** `[PR-152]` - Resolver Solicitud de Justificación por el Docente (Aprobación/Rechazo + Cambio Atómico en `Asistencia`)
- **Historia de Usuario Satisfecha:** HU035 (Ver solicitudes de revisión pendientes), HU037 (Aprobar/Rechazar justificaciones).
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_registrar_asistencias_sesion`
- **Propósito:** Permite al profesor evaluar la solicitud del alumno. Si se aprueba, la transacción actualiza atómicamente la solicitud a "APROBADA" y modifica el campo `estado` en `Asistencia` a "JUSTIFICADA", recalculando el porcentaje de faltas acumuladas en un solo paso.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-152",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`SolicitudRevisionAsistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estado``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_asistencias_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-152 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-152",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.64: `POST /api/v1/operaciones/pr_154`

- **Transacción / PR:** `[PR-154]` - Cancelación de Solicitud de Revisión por el Estudiante antes de ser Evaluada
- **Historia de Usuario Satisfecha:** HU010.
- **Rol Operador:** `ESTUDIANTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`
- **Objeto BD:** `dbo.usp_radicar_solicitud_revision_asistencia`
- **Propósito:** Permitir que el estudiante retire voluntariamente su solicitud de revisión si la radicó por error o con datos incorrectos.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-154",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ESTUDIANTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ESTUDIANTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`SolicitudRevisionAsistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_radicar_solicitud_revision_asistencia` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-154 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-154",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ESTUDIANTE` o violó la jerarquía de pertenencia de nodo padre (`Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.65: `POST /api/v1/operaciones/pr_155`

- **Transacción / PR:** `[PR-155]` - Generación de Alerta Temprana de Ausentismo Crítico al Superar Umbral
- **Historia de Usuario Satisfecha:** HU013 (Recibir alertas de ausentismo), HU066.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Acción Directa de Administrador Macro)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Disparar de forma reactiva una alerta visual y por correo cuando el % de inasistencias de un alumno alcanza el 15% (Advertencia) o el 20% (Pérdida por inasistencias).

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-155",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Usuario`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-155 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-155",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Acción Directa de Administrador Macro)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.66: `POST /api/v1/operaciones/pr_156`

- **Transacción / PR:** `[PR-156]` - Envío de Notificación Consolidada a Coordinación por Estudiantes en Riesgo
- **Historia de Usuario Satisfecha:** HU066, HU013.
- **Rol Operador:** `ESTUDIANTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Generar un reporte periódico automático para la coordinación con la lista de alumnos que superaron el umbral crítico de faltas en cualquier asignatura de la facultad.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-156",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ESTUDIANTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ESTUDIANTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Usuario`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-156 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-156",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ESTUDIANTE` o violó la jerarquía de pertenencia de nodo padre (`Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.67: `POST /api/v1/operaciones/pr_157`

- **Transacción / PR:** `[PR-157]` - Emisión de Certificado Oficial de Porcentaje de Asistencia por Asignatura
- **Historia de Usuario Satisfecha:** HU001, HU002.
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_registrar_o_actualizar_asignatura`
- **Propósito:** Generar el reporte oficial en PDF/XML de asistencias acumuladas de un estudiante para trámites de becas o patrocinios institucionales.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-157",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Sesion`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_o_actualizar_asignatura` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-157 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-157",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.68: `POST /api/v1/operaciones/pr_158`

- **Transacción / PR:** `[PR-158]` - Registro de Razón / Causa de Inasistencia Institucional (Mantenimiento de Catálogo)
- **Historia de Usuario Satisfecha:** HU005, HU016, HU042.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_registrar_asistencias_sesion`
- **Propósito:** Dar de alta o actualizar las opciones del catálogo `RazonCausa` (ej. "Incapacidad Médica EPS", "Calamidad Doméstica Comprobada", "Cita Judicial", "Representación Deportiva").

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-158",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`RazonCausa`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_asistencias_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-158 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-158",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.69: `GET /api/v1/operaciones/pr_159`

- **Transacción / PR:** `[PR-159]` - Consulta Consolidada de Histórico de Asistencias del Estudiante (`uv_asistencia`)
- **Historia de Usuario Satisfecha:** HU001 (Ver detalles de inasistencias), HU002 (Consultar histórico).
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_registrar_asistencias_sesion`
- **Propósito:** Retornar en una vista/procedimiento de lectura ultra-rápida todo el expediente de asistencias del estudiante a lo largo de su carrera.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-159",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Validación de Entidad MER `dbo.`Asignatura``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  10. **Validación de Entidad MER `dbo.`Estado`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  11. **Flujo de Aprobación de Perfil Superior:** El estudiante puede solicitar auto-inscripción a grupo o marcar asistencia autónoma (QR/PIN). La solicitud entra en estado `PENDIENTE` y requiere la aprobación explícita del DOCENTE o COORDINADOR.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_asistencias_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-159 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-159",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.70: `GET /api/v1/operaciones/pr_160`

- **Transacción / PR:** `[PR-160]` - Consulta Consolidada de Estadísticas de Asistencia por Grupo (`uv_estadistica_grupo`)
- **Historia de Usuario Satisfecha:** HU060, HU066.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_crear_grupo`
- **Propósito:** Retornar a la coordinación el resumen estadístico de un grupo (% de asistencia promedio, número de estudiantes en riesgo, total de clases dictadas).

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-160",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`EstudianteGrupo`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_crear_grupo` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-160 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-160",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.71: `GET /api/v1/operaciones/pr_161`

- **Transacción / PR:** `[PR-161]` - Generación de Reporte Macro de Deserción y Ausentismo para Decanatura por Facultad
- **Historia de Usuario Satisfecha:** HU102 (Reportes macro decanatura).
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Consolidar métricas a nivel gerencial para el Decano, mostrando los programas académicos y materias con mayor índice de inasistencias en la Facultad.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-161",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Facultad``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Programa``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Asistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-161 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-161",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.72: `POST /api/v1/operaciones/pr_163`

- **Transacción / PR:** `[PR-163]` - Reabrir Solicitud de Revisión Rechazada por Presentación de Nuevo Soporte Oficial
- **Historia de Usuario Satisfecha:** HU010, HU037.
- **Rol Operador:** `ESTUDIANTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`
- **Objeto BD:** `dbo.usp_radicar_solicitud_revision_asistencia`
- **Propósito:** Permitir que una solicitud que fue rechazada se reabra si el estudiante presenta una excusa oficial expedida posteriormente por bienestar o secretaría académica.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-163",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ESTUDIANTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
* **Flujo de Registro Autónomo y Aprobación:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ESTUDIANTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`SolicitudRevisionAsistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Flujo de Aprobación de Perfil Superior:** El estudiante crea autónomamente la Solicitud de Revisión (`estado = "PENDIENTE"`). El Docente titular del grupo revisa la evidencia adjunta y resuelve la solicitud aprobando o rechazando el ajuste de asistencia.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_radicar_solicitud_revision_asistencia` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-163 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-163",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ESTUDIANTE` o violó la jerarquía de pertenencia de nodo padre (`Grupo -> Sesión -> Estudiante -> SolicitudRevisionAsistencia`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR / COORDINADOR (Revisa la solicitud autónoma creada por el estudiante y emite resolución APROBADA / RECHAZADA)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.73: `POST /api/v1/operaciones/pr_169`

- **Transacción / PR:** `[PR-169]` - Generación de Indicador KPI de Cumplimiento de Toma de Lista por Docente
- **Historia de Usuario Satisfecha:** HU060 (Monitorear docentes que no siguen el proceso).
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Calcular el porcentaje de clases en las que cada profesor tomó asistencia a tiempo vs sesiones olvidadas o cerradas por el sistema.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-169",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Docente``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Asistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-169 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-169",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.74: `POST /api/v1/operaciones/pr_170`

- **Transacción / PR:** `[PR-170]` - Exportación Registros de Asistencia a Formato Oficial de Acta de Notas y Faltas
- **Historia de Usuario Satisfecha:** HU027, HU029, HU040.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_registrar_asistencias_sesion`
- **Propósito:** Consolidar en un solo archivo plano u objeto de salida la lista de estudiantes de un grupo con sus calificaciones y faltas totales al cerrar el semestre.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-170",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Asistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_asistencias_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-170 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-170",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.75: `GET /api/v1/operaciones/pr_171`

- **Transacción / PR:** `[PR-171]` - Consulta de Solicitudes de Justificación Vencidas Sin Respuesta del Docente
- **Historia de Usuario Satisfecha:** HU035, HU171.
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_radicar_solicitud_revision_asistencia`
- **Propósito:** Listar aquellas solicitudes de revisión de asistencia que llevan más de 5 días hábiles en estado "PENDIENTE" sin que el docente las haya aprobado o rechazado.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-171",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`SolicitudRevisionAsistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Grupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Docente`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_radicar_solicitud_revision_asistencia` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-171 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-171",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.76: `POST /api/v1/operaciones/pr_172`

- **Transacción / PR:** `[PR-172]` - Aprobación Automática de Justificación por Silencio Administrativo del Docente
- **Historia de Usuario Satisfecha:** HU010, HU037.
- **Rol Operador:** `COORDINADOR`
- **Perfil Aprobador Superior:** COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`
- **Objeto BD:** `dbo.usp_sincronizar_usuario`
- **Propósito:** Aplicar el principio de silencio administrativo positivo. Si un docente no responde una justificación médica en más de 10 días, el sistema aprueba automáticamente la excusa y marca la asistencia como "JUSTIFICADA".

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-172",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `COORDINADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `COORDINADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`SolicitudRevisionAsistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`Estado`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_sincronizar_usuario` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-172 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-172",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `COORDINADOR` o violó la jerarquía de pertenencia de nodo padre (`Facultad -> Programa -> Coordinador -> PlanEstudio / Asignatura -> Grupo -> Docente`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`COORDINADOR (Aprueba la asignación de Docentes a Grupos y valida la malla curricular)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.77: `POST /api/v1/operaciones/pr_175`

- **Transacción / PR:** `[PR-175]` - Consolidación de Histórico Académico de Asistencias para Proceso de Graduación
- **Historia de Usuario Satisfecha:** HU002.
- **Rol Operador:** `DOCENTE`
- **Perfil Aprobador Superior:** DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`
- **Objeto BD:** `dbo.usp_registrar_asistencias_sesion`
- **Propósito:** Certificar que un estudiante candidato a grado cumplió con el requisito institucional de porcentaje mínimo de asistencia en todas las asignaturas de su plan de estudio.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-175",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `DOCENTE`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `DOCENTE` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Estudiante``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`EstudiantePrograma``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`EstudianteGrupo``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Validación de Entidad MER `dbo.`Asistencia`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  9. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_asistencias_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-175 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-175",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `DOCENTE` o violó la jerarquía de pertenencia de nodo padre (`Programa -> Grupo -> Docente Titular -> Sesión -> Asistencia Estudiante`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`DOCENTE TITULAR (Crea sesiones de sus grupos, aprueba auto-registros QR y resuelve revisiones)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---

### Endpoint 3.78: `POST /api/v1/operaciones/pr_179`

- **Transacción / PR:** `[PR-179]` - Respaldar y Archivar Registros de Asistencia de Periodos Académicos Históricos
- **Historia de Usuario Satisfecha:** Mantenimiento y Rendimiento BD.
- **Rol Operador:** `ADMINISTRADOR`
- **Perfil Aprobador Superior:** N/A (Nivel Superior Administrador)
- **Cadena Jerárquica Nodo Padre-Raíz:** `Institución (Nodo Raíz) -> Facultad / Periodo`
- **Objeto BD:** `dbo.usp_registrar_asistencias_sesion`
- **Propósito:** Mover registros de `Asistencia` y `Sesion` de hace más de 5 años a tablas de archivo histórico para optimizar la velocidad y el tamaño de las tablas operativas principales.

#### 1. Contrato de Entrada (Request)
```json
{
  "idCorrelacion": "string (UUID v4 obligatorio)",
  "datos": {
    "codigoOperacion": "PR-179",
    "parametroEjemplo": "string (Requerido)"
  }
}
```

#### 2. Flujo y Responsabilidades del Backend
* **Validación de Rol Operador (RBAC):** Verificar Claim JWT (`User.Claims["role"]`) contra el rol `ADMINISTRADOR`.
* **Validación de Jerarquía Nodo Padre-Raíz:** Verificar que la entidad operada esté correctamente adscrita a la cadena `Institución (Nodo Raíz) -> Facultad / Periodo`.
* **Flujo de Registro Autónomo y Aprobación:** Operación directa de control de la plataforma.
* **Secuencia de Validaciones Específicas sobre el MER:**
  1. **Validación de Correlación:** Verificar la presencia del GUID de trazabilidad `idCorrelacion` (`usp_validar_id_correlacion_esta_presente_interno`).
  2. **Validación de Rol (RBAC):** Verificar que el Claim JWT del usuario autenticado tenga el rol `ADMINISTRADOR` activo en `dbo.UsuarioPerfil`.
  3. **Validación de Vinculación Jerárquica Nodo Padre-Raíz:** Verificar la cadena de custodia: `Institución (Nodo Raíz) -> Facultad / Periodo`.
  4. **Validación de Permiso / Titularidad de Ámbito:** Comprobar que la entidad padre pertenezca al usuario autenticado (ej: `Grupo.docente = idUsuario`, `Programa.coordinador = idUsuario`, `Facultad.decano = idUsuario`).
  5. **Validación de Entidad MER `dbo.`Asistencia``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  6. **Validación de Entidad MER `dbo.`Sesion``:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  7. **Validación de Entidad MER `dbo.`PeriodoAcademico`.`:** Consultar existencia por ID y comprobar estado de vigencia activo (`estado = 1` o `estado = "ACTIVO"`).
  8. **Flujo de Aprobación de Perfil Superior:** Operación directa de control de la plataforma.
* **Mapeo hacia BD:** Invocación asíncrona a `dbo.usp_registrar_asistencias_sesion` enviando los parámetros de la entidad.
* **Catálogo de Mensajes:** Traducción del código devuelto desde `uv_mensaje_usuario` a código de respuesta HTTP.

#### 3. Contrato de Salida (Response Envelope)
* **Código HTTP:** `200 OK` / `201 Created`
```json
{
  "success": true,
  "message": "Operación PR-179 procesada exitosamente.",
  "data": {
    "codigoPR": "PR-179",
    "estadoTransaccion": "COMPLETADO"
  },
  "pagination": null
}
```

* **Manejo de Errores Específicos:**
  - `401 Unauthorized`: Token JWT ausente o expirado.
  - `403 Forbidden`: El usuario no posee el rol `ADMINISTRADOR` o violó la jerarquía de pertenencia de nodo padre (`Institución (Nodo Raíz) -> Facultad / Periodo`).
  - `400 Bad Request`: Parámetros incompletos o malformados.
  - `404 Not Found`: Entidad del MER no encontrada o inactiva.
  - `422 Unprocessable Entity`: Regla de negocio no satisfecha o pendiente de aprobación por perfil superior (`N/A (Nivel Superior Administrador)`).
  - `500 Internal Server Error`: Fallo transaccional con ROLLBACK en BD.

---


*Fin de la Especificación Técnica Unificada con Trazabilidad Jerárquica y Aprobaciones por Perfil Superior.*