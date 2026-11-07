---
status: active
type: catalog
scope: database
owner: database-team
generated-by: scripts/generar-catalogo-mensajes.ps1
---

# Catálogo de mensajes

> Documento **generado** desde `schema/seed/*.sql` (MERGE sobre `CatalogoMensajeUsuario` y `CatalogoMensajeTecnico`). No editar a mano: agregue o cambie el seed y ejecute `./scripts/generar-catalogo-mensajes.ps1`. Verificación: `./scripts/generar-catalogo-mensajes.ps1 -Check`.

Uso en SP: `EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = '<CODIGO>', @p_param1 = ...`. Los marcadores `{}` / `{0}` se reemplazan con los parámetros. El mensaje técnico se entrega como `DBCODE=<CODIGO>|<texto>` (ver `docs/contracts/DB_BASELINE_CONTRACT.md`).

Total de códigos: **198**.

## AQR

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `AQR_001` | BUSINESS_ERROR | BAJO | El código QR o el PIN no es válido o ya venció. Pide el PIN vigente al docente. | Token/PIN sin coincidencia vigente. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_002` | SECURITY_ERROR | MEDIO | Debes estar conectado a la red Wi-Fi del campus para registrar tu asistencia. | IP [{}] fuera de RED/CIDRS_CAMPUS. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_003` | BUSINESS_ERROR | BAJO | Esta toma es manual; no admite código QR. | Toma [{}] con usaCodigoQr = 0. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_004` | BUSINESS_ERROR | BAJO | No estás matriculado en el grupo de esta clase. | Estudiante [{}] sin matrícula A en grupo [{}]. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_005` | BUSINESS_ERROR | BAJO | La toma de asistencia ya se cerró. | Toma/token [{}] cerrado o expirado. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_006` | TECHNICAL_ERROR | BAJO | No fue posible generar el código. Intenta de nuevo. | PIN [{}] repetido entre activos/anteriores vigentes; reintentar. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_007` | VALIDATION_ERROR | BAJO | Escanea el código QR o digita el PIN. | Se requiere exactamente uno de @tokenHash o @pin. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_008` | SUCCESS | BAJO | Tu asistencia a esta toma ya estaba registrada. | Detalle existente para estudiante [{}] toma [{}]; sin cambios. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_009` | SUCCESS | BAJO | ¡Listo! Tu asistencia quedó registrada. | Asistencia AN por token: estudiante [{}] toma [{}]. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_010` | BUSINESS_ERROR | BAJO | El registro de asistencia por QR no está disponible. | ASISTENCIA_QR/HABILITADA != true. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_011` | SECURITY_ERROR | BAJO | Hiciste demasiados intentos. Espera un minuto e intenta de nuevo. | Límite [{}] superado para clave [{}]. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_012` | SUCCESS | BAJO | Código QR listo para proyectar. | Token de asistencia [{}] emitido para toma [{}]. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_013` | SUCCESS | BAJO | Se dejó de proyectar el código QR. | Token de la toma [{}] cerrado. | `35_mensajes_toma_asistencia_qr.sql` |

## ARC

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `ARC_001` | BUSINESS_ERROR | ALTO | El soporte indicado no esta disponible para esta solicitud. | Soporte no disponible para radicar: inexistente, de otro propietario, ya vinculado o no vigente. | `15_lb004d_archivo_soporte.sql` |
| `ARC_002` | BUSINESS_ERROR | ALTO | No fue posible registrar el soporte. | Registro de soporte rechazado: el identificador ya existe con otro propietario o con metadata distinta. | `15_lb004d_archivo_soporte.sql` |
| `ARC_003` | BUSINESS_ERROR | MEDIO | Los datos del soporte no son validos. | Metadata de soporte invalida: identificador, nombre, tipo de contenido, tamano o checksum fuera de contrato. | `15_lb004d_archivo_soporte.sql` |
| `ARC_005` | BUSINESS_ERROR | ALTO | El estudiante indicado no corresponde al usuario autenticado. | El idEstudiante no pertenece al idUsuarioEjecutor. | `15_lb004d_archivo_soporte.sql` |

## ARE

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `ARE_001` | BUSINESS_ERROR | MEDIO | El área de conocimiento especificada no existe en el sistema. | Error de búsqueda: No se encontró el área de conocimiento en uv_area: {}. | `04_mensaje.sql` |
| `ARE_002` | BUSINESS_ERROR | ALTO | Ya existe un área de conocimiento con el mismo código o nombre. | Error de unicidad: código o nombre duplicado en área de conocimiento. | `04_mensaje.sql` |

## ASI

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `ASI_001` | BUSINESS_ERROR | MEDIO | Los créditos de la asignatura son obligatorios y deben ser mayores que cero. | Validacion: @creditos nulo o menor o igual a cero; no se asigna un valor por defecto. | `29_mensajes_asignatura.sql` |

## ATT

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `ATT_001` | BUSINESS_ERROR | MEDIO | El payload JSON de asistencia no cumple el contrato requerido. | Payload JSON inválido: se requiere un arreglo no nulo de objetos con exactamente idEstudiante y estado. | `04_mensaje.sql` |
| `ATT_002` | BUSINESS_ERROR | MEDIO | El lote de asistencia no puede estar vacío. | Payload JSON válido pero vacío: no hay operación de negocio que ejecutar. | `04_mensaje.sql` |
| `ATT_003` | BUSINESS_ERROR | MEDIO | El estudiante {} aparece más de una vez en el lote de asistencia. | Duplicidad en payload JSON: idEstudiante [{}] aparece más de una vez. | `04_mensaje.sql` |

## COO

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `COO_001` | BUSINESS_ERROR | ALTO | No se puede desactivar al coordinador mientras tenga un programa activo a cargo. Reasigne o desactive el programa primero. | Regla de negocio: el coordinador {} coordina el programa activo {}. | `04_mensaje.sql` |

## CORR

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `CORR_001` | BUSINESS_ERROR | ALTO | El identificador de correlación no está presente o está vacío. | Validación fallida: idCorrelacion no está presente o no es un UUID válido. Transacción no procesable. | `04_mensaje.sql` |

## DEC

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `DEC_001` | BUSINESS_ERROR | MEDIO | El decano especificado no existe en el sistema. | Error de búsqueda: No se encontró el decano en uv_decano_identidad: {}. | `04_mensaje.sql` |
| `DEC_002` | BUSINESS_ERROR | ALTO | No se puede desactivar al decano de una facultad con programas activos. | Regla: el decano [{}] dirige una facultad con el programa activo [{}]; no se desactiva. | `33_culm001_a_mensajes.sql` |
| `DEC_003` | SUCCESS | BAJO | Se actualizó el estado del decano. | Actualizacion: Decano.estado del decano [{}] actualizado (regla D1 aplicada a Usuario.estado). | `33_culm001_a_mensajes.sql` |

## DOC

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `DOC_001` | BUSINESS_ERROR | MEDIO | El docente especificado no existe o se encuentra inactivo. | Error de búsqueda: Docente no encontrado o deshabilitado en uv_docente: {}. | `04_mensaje.sql` |
| `DOC_002` | BUSINESS_ERROR | MEDIO | El usuario ya se encuentra registrado como docente. | Unicidad: el usuario ya tiene un registro en dbo.Docente. | `17_mensaje_docente_programa.sql` |
| `DOC_003` | BUSINESS_ERROR | ALTO | Ya existe una persona registrada con ese documento o correo. Use la opción "Vincular docente existente". | Conflicto de identidad: documento o correo ya existen en dbo.Usuario; el modo nuevo no hace find-or-create. | `17_mensaje_docente_programa.sql` |
| `DOC_004` | BUSINESS_ERROR | MEDIO | El tipo de vinculación indicado no existe o está inactivo. | Validación: TipoVinculacion inexistente o con estado = 0. | `17_mensaje_docente_programa.sql` |
| `DOC_005` | BUSINESS_ERROR | MEDIO | Debe indicar un docente existente o los datos de un docente nuevo, pero no ambos. | Validación de modo: exactamente uno entre @idDocente, @idUsuario o el bloque de datos de persona nueva. | `17_mensaje_docente_programa.sql` |
| `DOC_006` | BUSINESS_ERROR | MEDIO | El docente ya está vinculado a este programa. | Unicidad: ya existe dbo.DocentePrograma para el par (docente, programa). | `17_mensaje_docente_programa.sql` |
| `DOC_007` | BUSINESS_ERROR | BAJO | La búsqueda de candidatos requiere al menos 3 caracteres. | Validación: @busqueda de candidatos con menos caracteres que DOCENTE/BUSQUEDA_MIN_CARACTERES. | `17_mensaje_docente_programa.sql` |
| `DOC_008` | BUSINESS_ERROR | MEDIO | El docente no está vinculado a este programa. | Existencia: no hay dbo.DocentePrograma para el par (docente, programa) indicado. | `17_mensaje_docente_programa.sql` |
| `DOC_009` | BUSINESS_ERROR | MEDIO | El docente no tiene una vinculación activa con el programa. | Regla: el docente no tiene dbo.DocentePrograma con estado = 1 en el programa del grupo. | `17_mensaje_docente_programa.sql` |

## ERR

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `ERR_CAPACIDAD_GRUPO_INVALIDA` | SYSTEM_ERROR | CRITICO | No fue posible determinar una capacidad máxima válida para el grupo. | El parametro GRUPO/CAPACIDAD_MAXIMA_DEFECTO es nulo, cero o negativo: {}. | `04_mensaje.sql` |
| `ERR_CORRELACION_REQUERIDA` | BUSINESS_ERROR | ALTO | El codigo de correlacion es requerido. | Error: idCorrelacion no esta presente o es invalido. | `04_mensaje.sql` |
| `ERR_CRUCE_HORARIO_DOCENTE` | BUSINESS_ERROR | ALTO | Existe un cruce de horario para el docente en la misma franja horaria. | Cruce detectado en uv_horario para Docente con GrupoID: {}. | `04_mensaje.sql` |
| `ERR_CRUCE_HORARIO_ESTUDIANTE` | BUSINESS_ERROR | ALTO | No es posible realizar el registro. Existe un cruce de horario con otra asignatura. | Cruce detectado en uv_horario para Estudiante con GrupoID: {}. | `04_mensaje.sql` |
| `ERR_CUPO_INFERIOR_OCUPACION` | BUSINESS_ERROR | ALTO | La capacidad del grupo no puede ser menor al número actual de estudiantes activos. | Grupo {}: capacidad solicitada {} es menor a los estudiantes activos {}. | `04_mensaje.sql` |
| `ERR_CUPO_SUPERADO` | BUSINESS_ERROR | ALTO | El grupo ha superado la capacidad maxima de estudiantes permitida. | Cupo lleno. Maximo de estudiantes alcanzado para Grupo: {}. | `04_mensaje.sql` |
| `ERR_DOCENTE_NO_EXISTE` | BUSINESS_ERROR | MEDIO | El docente especificado no existe o esta inactivo. | Error: No se encontro el ID de Docente especificado: {}. | `04_mensaje.sql` |
| `ERR_DOCENTE_NO_TITULAR_GRUPO` | BUSINESS_ERROR | ALTO | El docente indicado no es el titular del grupo seleccionado. | Docente {} no es titular del Grupo {} (uv_grupo.idDocente). | `04_mensaje.sql` |
| `ERR_ESTUDIANTE_NO_EXISTE` | BUSINESS_ERROR | MEDIO | El estudiante especificado no existe. | Error: No se encontro el ID de Estudiante especificado: {}. | `04_mensaje.sql` |
| `ERR_ESTUDIANTE_NO_PERTENECE_SESION` | BUSINESS_ERROR | ALTO | El estudiante no pertenece al grupo de la sesion seleccionada. | Validacion fallida: Estudiante no pertenece al grupo de la sesion: {}. | `04_mensaje.sql` |
| `ERR_GRUPO_NO_EXISTE` | BUSINESS_ERROR | MEDIO | El grupo seleccionado no existe o no esta habilitado. | Error: No existe un grupo habilitado con el identificador: {}. | `04_mensaje.sql` |
| `ERR_GRUPO_NO_HABILITADO` | BUSINESS_ERROR | MEDIO | El grupo seleccionado no se encuentra habilitado para matricula. | Grupo existente, pero fuera de ventana habilitada para matricula: {}. | `04_mensaje.sql` |
| `ERR_INESPERADO_REGISTRO_ASISTENCIA` | SYSTEM_ERROR | CRITICO | Hubo un error inesperado al registrar la asistencia del estudiante. | Error critico en orquestador [usp_registrar_asistencia_estudiante]: {}. | `04_mensaje.sql` |
| `ERR_INESPERADO_REGISTRO_DOCENTE` | SYSTEM_ERROR | CRITICO | Hubo un error inesperado al procesar el registro completo del docente. | Error critico en orquestador [usp_registrar_docente_en_grupo_usuario_no_existente]: {}. | `04_mensaje.sql` |
| `ERR_INESPERADO_REGISTRO_ESTUDIANTE` | SYSTEM_ERROR | CRITICO | Hubo un error inesperado al procesar el registro completo del estudiante. | Error critico en orquestador [usp_registrar_estudiante_en_grupo_usuario_no_existente]: {}. | `04_mensaje.sql` |
| `ERR_MATRICULA_DUPLICADA` | BUSINESS_ERROR | ALTO | Usted ya se encuentra registrado o matriculado en este grupo. | Registro duplicado detectado en uv_estudiante_grupo para Estudiante en Grupo: {}. | `04_mensaje.sql` |
| `ERR_PROGRAMA_FACULTAD_INCONSISTENTE` | BUSINESS_ERROR | CRITICO | El programa académico indicado no pertenece a la facultad especificada. | Programa {} no pertenece a la Facultad {} indicada en uv_programa.idFacultad. | `04_mensaje.sql` |
| `ERR_PROGRAMA_GRUPO_NO_ENCONTRADO` | BUSINESS_ERROR | ALTO | No se encontro un programa academico asociado a este grupo. | Error: Trazabilidad rota para Grupo ID {}. | `04_mensaje.sql` |
| `ERR_SESION_NO_EXISTE` | BUSINESS_ERROR | MEDIO | La sesion de clase no existe o no esta abierta. | Error: No se encontro una sesion activa para el ID especificado: {}. | `04_mensaje.sql` |
| `ERR_TOKEN_VERIFICACION_INVALIDO` | BUSINESS_ERROR | MEDIO | El codigo de verificacion de asistencia es incorrecto o ha expirado. | Fallo: Codigo de verificacion incorrecto o expirado para Sesion: {}. | `04_mensaje.sql` |
| `ERR_UNICIDAD_CORREO` | BUSINESS_ERROR | ALTO | El correo electronico ya se encuentra registrado. | Fallo unicidad: El correo [{}] ya existe en uv_usuario. | `04_mensaje.sql` |
| `ERR_UNICIDAD_DOCUMENTO` | BUSINESS_ERROR | ALTO | El numero de documento ya esta registrado para este tipo de identificacion. | Fallo unicidad: Duplicado en idTipoIdentificacion y numeroIdentificacion [{}]. | `04_mensaje.sql` |
| `ERR_USUARIO_NO_EXISTE` | BUSINESS_ERROR | MEDIO | El usuario especificado no existe. | Error: No se encontro el ID de Usuario especificado: {}. | `04_mensaje.sql` |

## EST

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `EST_001` | BUSINESS_ERROR | MEDIO | El estudiante especificado no existe en el sistema. | Error de búsqueda: No se encontró el estudiante especificado en uv_estudiante: {}. | `04_mensaje.sql` |
| `EST_002` | BUSINESS_ERROR | ALTO | El estudiante ya se encuentra matriculado o registrado en este grupo. | Registro duplicado: El estudiante {} ya se encuentra asociado al grupo {} en uv_estudiante_grupo. | `04_mensaje.sql` |
| `EST_003` | BUSINESS_ERROR | ALTO | El estudiante ya pertenece a este programa académico. | Registro duplicado: El estudiante {} ya está asociado al programa en uv_estudiante_programa. | `04_mensaje.sql` |
| `EST_004` | BUSINESS_ERROR | ALTO | El estudiante no pertenece al grupo de la sesion seleccionada. | Validación de pertenencia fallida: El estudiante {} no está inscrito en el grupo de la sesión {}. | `04_mensaje.sql` |

## FAC

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `FAC_001` | BUSINESS_ERROR | MEDIO | La facultad especificada no existe en el sistema. | Error de búsqueda: No se encontró la facultad en uv_facultad: {}. | `04_mensaje.sql` |
| `FAC_002` | BUSINESS_ERROR | ALTO | El decano seleccionado ya es titular de otra facultad activa. | Regla de unicidad de titularidad: el decano {} ya es titular de otra facultad activa. | `04_mensaje.sql` |

## FES

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `FES_001` | VALIDATION_ERROR | BAJO | El año de festivos no es válido. | @anio [{}] fuera de FESTIVOS/ANIO_MINIMO..ANIO_MAXIMO. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_002` | VALIDATION_ERROR | MEDIO | El listado de festivos recibido no es válido. | @festivosJSON inválido: {}. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_003` | VALIDATION_ERROR | MEDIO | El listado de festivos no tiene una cantidad válida de días. | Total [{}] fuera de FESTIVOS/MINIMO_POR_ANIO..MAXIMO_POR_ANIO. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_004` | VALIDATION_ERROR | MEDIO | La fuente de festivos no es válida. | @fuente [{}] no está en FESTIVOS/FUENTES_VALIDAS. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_005` | SUCCESS | BAJO | Se cargaron {} días festivos de {}. | Carga [{}]: insertados {}, actualizados {}, desactivados {}. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_006` | VALIDATION_ERROR | BAJO | Indica el periodo académico o el año, no ambos. | @idPeriodoAcademico y @anio: exactamente uno. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_007` | BUSINESS_ERROR | BAJO | El periodo académico no existe. | Periodo [{}] inexistente. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_008` | SUCCESS | BAJO | Se cancelaron {} sesiones por festivo; {} sesiones con asistencia quedaron sin cambios. | Aplicación de festivos grupo/periodo [{}]. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_009` | BUSINESS_ERROR | MEDIO | Algunos grupos no se pudieron actualizar con los festivos. | {} grupos con error; ver log con la correlación. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_010` | TECHNICAL_ERROR | ALTO | No fue posible obtener los festivos del año; se usó el cálculo local. | Proveedores [{}] fallaron; respaldo CALCULO_LOCAL. | `34_mensajes_sesion_cancelada_festivos.sql` |

## GEN

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `GEN_001` | BUSINESS_ERROR | MEDIO | El {} especificado no existe en el sistema. | Error de existencia: No se encontró el registro para la entidad [{}] con el identificador proporcionado. | `04_mensaje.sql` |
| `GEN_002` | BUSINESS_ERROR | MEDIO | El {} no puede estar vacío o no está presente. | Error de validación: El parámetro o campo [{}] es requerido y no contiene un valor válido. | `04_mensaje.sql` |
| `GEN_003` | BUSINESS_ERROR | ALTO | Ya existe un {} registrado con este {}. | Error de unicidad: Se detectó un registro duplicado para la entidad [{}] con la propiedad [{}]. | `04_mensaje.sql` |
| `GEN_004` | SUCCESS | BAJO | {} registrado(a) exitosamente. | Operación exitosa: Se completó la creación/registro de la entidad [{}] de manera correcta. | `04_mensaje.sql` |
| `GEN_005` | SUCCESS | BAJO | {} actualizado(a) exitosamente. | Operación exitosa: Se completó la actualización de la entidad [{}] de manera correcta. | `04_mensaje.sql` |

## GRUP

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `GRUP_001` | BUSINESS_ERROR | MEDIO | El grupo seleccionado no existe o no se encuentra habilitado. | Error de búsqueda: Grupo inexistente o deshabilitado en uv_grupo: {}. | `04_mensaje.sql` |
| `GRUP_002` | BUSINESS_ERROR | ALTO | El grupo ha alcanzado o superado la capacidad máxima de estudiantes permitida. | Límite alcanzado: Capacidad máxima superada para el grupo seleccionado: {}. | `04_mensaje.sql` |
| `GRUP_003` | BUSINESS_ERROR | ALTO | No se encontró un programa académico asociado a este grupo. | Inconsistencia de trazabilidad: Grupo {} sin programa académico vinculado. | `04_mensaje.sql` |

## HOR

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `HOR_001` | BUSINESS_ERROR | ALTO | No es posible realizar el registro. Existe un cruce de horario con otra asignatura. | Colisión horaria: Se detectó una superposición de horario para el estudiante en la misma franja: {}. | `04_mensaje.sql` |
| `HOR_002` | BUSINESS_ERROR | ALTO | Existe un cruce de horario para el docente: ya tiene el grupo {} en la misma franja ({}). | Colisión horaria del docente con el grupo {} en la franja {}. GrupoID evaluado: {}. | `04_mensaje.sql` |
| `HOR_003` | BUSINESS_ERROR | MEDIO | Las franjas del horario del grupo no pueden cruzarse: {} se cruza con {}. | Franjas traslapadas en el horario del grupo: {} y {}. | `04_mensaje.sql` |
| `HOR_004` | BUSINESS_ERROR | MEDIO | El horario del grupo no es válido: {}. | Horario de grupo invalido: {}. | `04_mensaje.sql` |
| `HOR_005` | BUSINESS_ERROR | MEDIO | El grupo ya tiene un horario definido. Para cambiarlo, solicita la aprobación del coordinador. | El docente ejecutor intento reemplazar un horario ya definido del grupo. | `04_mensaje.sql` |

## IAM

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `IAM_001` | SYSTEM_ERROR | ALTO | El registro se guardó, pero la cuenta de acceso no pudo crearse en este momento. Intente de nuevo. | Aprovisionamiento IAM falló después del commit en DB (TD-015): reintentar crearCuenta de forma idempotente. | `17_mensaje_docente_programa.sql` |

## IDE

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `IDE_001` | BUSINESS_ERROR | MEDIO | El motivo de la corrección es obligatorio y no puede superar 500 caracteres. | Validacion: @motivo nulo, vacio o de mas de 500 caracteres. | `31_mensajes_correccion_identidad.sql` |
| `IDE_002` | SUCCESS | BAJO | Los datos de identidad fueron corregidos. | Actualizacion: dbo.Usuario (documento, nombres y apellidos) y registro en dbo.AuditoriaEvento. | `31_mensajes_correccion_identidad.sql` |
| `IDE_003` | BUSINESS_ERROR | MEDIO | La corrección del tipo o número de documento no está habilitada. | Regla de negocio: IDENTIDAD.PERMITIR_CORREGIR_DOCUMENTO distinto de 1; el documento no se modifica. | `31_mensajes_correccion_identidad.sql` |

## INST

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `INST_001` | BUSINESS_ERROR | CRITICO | El estudiante, programa y facultad deben pertenecer a la misma institución. | Inconsistencia institucional: Los identificadores de institución no coinciden entre la facultad, programa y estudiante: {}. | `04_mensaje.sql` |

## KPI

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `KPI_001` | BUSINESS_ERROR | ALTO | No tiene un programa académico a su cargo para consultar estos indicadores. | Ámbito: el ejecutor {} no coordina ningún programa en uv_programa. | `18_mensajes_kpis_coordinador.sql` |
| `KPI_002` | BUSINESS_ERROR | CRITICO | No fue posible calcular los indicadores porque falta la configuración de umbrales de asistencia. | Falta el parámetro ASISTENCIA/UMBRAL_ALERTA_ADVERTENCIA o ASISTENCIA/UMBRAL_ALERTA_PERDIDA en CatalogoParametro. | `18_mensajes_kpis_coordinador.sql` |
| `KPI_003` | BUSINESS_ERROR | ALTO | No tiene una facultad a su cargo para consultar estos indicadores. | Ámbito: el ejecutor {} no es decano de ninguna facultad en uv_facultad. | `19_mensajes_kpis_decano.sql` |
| `KPI_004` | BUSINESS_ERROR | ALTO | No tiene una institución a su cargo para consultar estos indicadores. | Ámbito: el ejecutor {} no es administrador de ninguna institución en uv_administrador. | `20_mensajes_kpis_admin.sql` |

## MQR

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `MQR_001` | BUSINESS_ERROR | MEDIO | El código de matrícula no es válido o ya no está disponible. Solicítale al docente uno nuevo. | Token o PIN de matrícula inexistente, cerrado, expirado o fuera de la tolerancia de rotación. | `29_mensajes_matricula_qr.sql` |
| `MQR_002` | BUSINESS_ERROR | MEDIO | La matrícula por código solo está disponible desde la red Wi-Fi del campus UCO. | Regla: la IP del cliente no pertenece a asistencias:red:cidrs-campus. | `29_mensajes_matricula_qr.sql` |
| `MQR_003` | BUSINESS_ERROR | BAJO | Demasiados intentos. Espera un momento antes de volver a intentarlo. | Límite de intentos por IP o por token superado en la ventana de tiempo. | `29_mensajes_matricula_qr.sql` |
| `MQR_004` | BUSINESS_ERROR | BAJO | Ya estás matriculado en este grupo. | Regla: el estudiante ya tiene matrícula en el grupo. | `29_mensajes_matricula_qr.sql` |
| `MQR_005` | BUSINESS_ERROR | MEDIO | Ya tienes una cuenta registrada. Inicia sesión para completar tu matrícula. | Existencia: el documento o el correo ya pertenecen a un usuario registrado. | `29_mensajes_matricula_qr.sql` |
| `MQR_006` | BUSINESS_ERROR | BAJO | No fue posible generar un código único. Inténtalo de nuevo. | Unicidad: el PIN ya está en uso por el token vigente o anterior de otra ventana activa. | `29_mensajes_matricula_qr.sql` |
| `MQR_007` | BUSINESS_ERROR | MEDIO | Debes indicar el código QR o el PIN, pero no ambos. | Validación: debe indicarse exactamente uno entre tokenHash y pin. | `29_mensajes_matricula_qr.sql` |

## NTF

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `NTF_001` | BUSINESS_ERROR | MEDIO | Los datos de la notificación no son válidos. | Datos de la notificación o parámetros de invocación no cumplen el contrato. | `04_mensaje.sql` |
| `NTF_002` | BUSINESS_ERROR | MEDIO | La notificación especificada no existe en el sistema. | Notificación no encontrada por identificador. | `04_mensaje.sql` |
| `NTF_003` | BUSINESS_ERROR | MEDIO | La notificación ya no está reservada por este proceso. | La notificación no está reservada por la instancia o la reserva ya venció. | `04_mensaje.sql` |
| `NTF_004` | BUSINESS_ERROR | MEDIO | La plantilla de notificación no contiene todos los marcadores obligatorios o incluye marcadores no permitidos para este tipo. | Validación de plantilla fallida: marcadores obligatorios ausentes o marcadores no permitidos para el tipo. | `04_mensaje.sql` |
| `NTF_005` | BUSINESS_ERROR | MEDIO | No existe la versión de plantilla solicitada para el tipo e idioma indicados. | No existe la versión de plantilla solicitada para el tipo e idioma indicados. | `04_mensaje.sql` |
| `NTF_006` | SUCCESS | BAJO | La plantilla de correo se actualizó y activó correctamente en una nueva versión. | La plantilla de correo se actualizó y activó correctamente en una nueva versión. | `04_mensaje.sql` |
| `NTF_007` | SUCCESS | BAJO | La notificación fallida fue reencolada exitosamente para un nuevo intento de envío. | La notificación fallida fue reencolada exitosamente para un nuevo intento de envío. | `04_mensaje.sql` |
| `NTF_008` | BUSINESS_ERROR | MEDIO | Solo se pueden reencolar notificaciones en estado fallido definitivo o reintentable. | Solo se pueden reencolar notificaciones en estado fallido definitivo o reintentable. | `04_mensaje.sql` |
| `NTF_009` | SUCCESS | BAJO | Correo de prueba encolado correctamente. | Correo de prueba encolado correctamente. | `04_mensaje.sql` |

## PAG

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `PAG_001` | BUSINESS_ERROR | MEDIO | Los parámetros de paginación no son válidos. | Paginación inválida: numeroPagina={} y tamanoPagina={} fuera de rango (máximo según PAGINACION/TAMANO_MAXIMO). | `17_mensajes_programa_academico.sql` |

## PER

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `PER_001` | BUSINESS_ERROR | MEDIO | El período académico indicado no existe. | Existencia: no hay dbo.PeriodoAcademico con el id indicado en la institucion del ejecutor. | `17_mensajes_periodo_academico.sql` |
| `PER_002` | BUSINESS_ERROR | MEDIO | La fecha de inicio del período debe ser anterior a la fecha de fin. | Validacion: fechaInicio y fechaFin obligatorias y fechaInicio < fechaFin. | `17_mensajes_periodo_academico.sql` |
| `PER_003` | BUSINESS_ERROR | MEDIO | Ya existe un período académico con ese nombre en la institución. | Unicidad: ya existe dbo.PeriodoAcademico con el mismo id o nombre en la institucion. | `17_mensajes_periodo_academico.sql` |
| `PER_004` | BUSINESS_ERROR | MEDIO | El período académico tiene grupos o sesiones asociados y no se puede eliminar. | Regla: existe dbo.Grupo que referencia el periodo a eliminar. | `17_mensajes_periodo_academico.sql` |
| `PER_005` | BUSINESS_ERROR | MEDIO | No tiene una institución activa asignada como administrador para gestionar períodos académicos. | Ambito: el ejecutor no tiene dbo.Administrador en una institucion activa. | `17_mensajes_periodo_academico.sql` |
| `PER_006` | SUCCESS | BAJO | Período académico eliminado exitosamente. | Eliminacion: dbo.PeriodoAcademico eliminado. | `17_mensajes_periodo_academico.sql` |

## PLA

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `PLA_002` | BUSINESS_ERROR | MEDIO | El plan de estudios indicado no existe. | Existencia: no hay dbo.PlanEstudio con el id indicado. | `17_mensajes_plan_estudio.sql` |
| `PLA_003` | BUSINESS_ERROR | MEDIO | El plan de estudios ya tiene el número máximo de semestres. | Regla: no existe dbo.Semestre con numero MAX(numero del plan) + 1. | `17_mensajes_plan_estudio.sql` |
| `PLA_004` | BUSINESS_ERROR | MEDIO | El semestre indicado no pertenece al plan de estudios. | Existencia: no hay dbo.SemestrePlanEstudio del plan con el numero de semestre indicado. | `17_mensajes_plan_estudio.sql` |
| `PLA_005` | BUSINESS_ERROR | MEDIO | Solo se puede quitar el último semestre del plan de estudios. | Regla: el numero de semestre indicado no es el mayor del plan; la malla debe seguir consecutiva. | `17_mensajes_plan_estudio.sql` |
| `PLA_006` | BUSINESS_ERROR | MEDIO | El semestre tiene asignaturas asociadas. Reubíquelas o elimínelas primero. | Regla: existe dbo.Asignatura que referencia el dbo.SemestrePlanEstudio a quitar. | `17_mensajes_plan_estudio.sql` |

## PROG

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `PROG_001` | BUSINESS_ERROR | ALTO | El programa académico especificado no existe en el sistema. | Error de búsqueda: No se encontró el programa en uv_programa: {}. | `04_mensaje.sql` |
| `PROG_002` | BUSINESS_ERROR | ALTO | Ya existe un programa académico con el identificador indicado. | Registro duplicado: ya existe un programa con el id {} en uv_programa. | `17_mensajes_programa_academico.sql` |
| `PROG_003` | BUSINESS_ERROR | ALTO | Ya existe un programa académico con ese nombre en la facultad. | Regla de unicidad: el nombre [{}] ya existe en la facultad (comparación sin distinguir mayúsculas). | `17_mensajes_programa_academico.sql` |
| `PROG_004` | BUSINESS_ERROR | MEDIO | El tipo de programa indicado no existe o está inactivo. | Error de búsqueda: tipo de programa {} inexistente o inactivo en uv_tipo_programa. | `17_mensajes_programa_academico.sql` |
| `PROG_005` | BUSINESS_ERROR | ALTO | El coordinador seleccionado no está disponible: no existe, está inactivo o ya tiene un programa asignado. | Regla 1 a 1: el coordinador {} no existe, está inactivo o ya figura en otro programa. | `17_mensajes_programa_academico.sql` |
| `PROG_006` | BUSINESS_ERROR | MEDIO | La modalidad o la jornada indicada no existe o está inactiva. | Error de búsqueda: modalidad/jornada {} inexistente o inactiva. | `17_mensajes_programa_academico.sql` |
| `PROG_007` | BUSINESS_ERROR | ALTO | No se puede desactivar el programa porque tiene grupos activos en el período vigente. | Regla D4: el programa {} tiene grupos habilitados en uv_grupo_programa. | `17_mensajes_programa_academico.sql` |
| `PROG_008` | BUSINESS_ERROR | ALTO | No se puede activar el programa porque su facultad está inactiva. | Regla de jerarquía: la facultad del programa {} está inactiva. | `17_mensajes_programa_academico.sql` |

## RC

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `RC_001` | BUSINESS_ERROR | MEDIO | El estado de asistencia {} no corresponde a una razón de causa válida. | RazonCausa.codigo = [{}] no existe o no es válido para el contrato de asistencia. | `04_mensaje.sql` |

## RET

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `RET_001` | BUSINESS_ERROR | MEDIO | El grupo indicado no existe o no es un grupo a su cargo. | Ambito: no existe dbo.Grupo con el id indicado cuyo Docente.usuario sea el ejecutor. | `21_mensajes_retiro_estudiante_grupo.sql` |
| `RET_002` | BUSINESS_ERROR | MEDIO | El estudiante no tiene una matrícula activa en este grupo. | Existencia: no hay dbo.EstudianteGrupo activo (estado A) para el estudiante en el grupo. | `21_mensajes_retiro_estudiante_grupo.sql` |
| `RET_003` | BUSINESS_ERROR | MEDIO | El período académico del grupo ya terminó; no se puede retirar al estudiante. | Regla: PeriodoAcademico.fechaFin es anterior a la fecha local (TIEMPO.ZONA_HORARIA_SQLSERVER). | `21_mensajes_retiro_estudiante_grupo.sql` |
| `RET_004` | BUSINESS_ERROR | MEDIO | El motivo del retiro es obligatorio y no puede superar 500 caracteres. | Validacion: @motivo nulo, vacio o de mas de 500 caracteres. | `21_mensajes_retiro_estudiante_grupo.sql` |
| `RET_005` | SUCCESS | BAJO | El estudiante fue retirado del grupo. | Actualizacion: dbo.EstudianteGrupo pasa a estado I (inactivo) y se registra dbo.AuditoriaEvento. | `21_mensajes_retiro_estudiante_grupo.sql` |

## REV

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `REV_001` | BUSINESS_ERROR | MEDIO | La acción sobre el reclamo no es válida; use APROBADA o RECHAZADA. | SES-04 resolución de reclamo: acción [{}] fuera del contrato (APROBADA \| RECHAZADA); sin escrituras. | `04_mensaje.sql` |
| `REV_002` | BUSINESS_ERROR | MEDIO | El reclamo ya fue resuelto con una decisión distinta. | SES-04 resolución de reclamo: la solicitud [{}] ya está resuelta con otra decisión; sin escrituras. | `04_mensaje.sql` |
| `REV_003` | BUSINESS_ERROR | MEDIO | La asistencia del reclamo no es una inasistencia justificable. | SES-04 resolución de reclamo: la solicitud [{}] apunta a una asistencia presente (AN / asistio = 1); sin escrituras. | `04_mensaje.sql` |
| `REV_004` | BUSINESS_ERROR | MEDIO | El reclamo no tiene un registro de asistencia que se pueda justificar. | SES-04 resolución de reclamo: la solicitud [{}] no tiene DetalleAsistencia; no se simula la justificación. | `04_mensaje.sql` |
| `REV_005` | BUSINESS_ERROR | MEDIO | El reclamo indicado no existe. | SES-04 resolución de reclamo: la solicitud [{}] no existe o no tiene asistencia, sesión y grupo válidos. | `04_mensaje.sql` |
| `REV_006` | BUSINESS_ERROR | MEDIO | La solicitud de revisión no existe. | Ambito: la solicitud de revision [{}] no existe o no es del estudiante ejecutor; sin escrituras. | `33_culm001_a_mensajes.sql` |
| `REV_007` | BUSINESS_ERROR | MEDIO | Solo se puede retirar una solicitud de revisión pendiente. | Regla: la solicitud de revision [{}] no esta en el estado de RECLAMO/ESTADO_PENDIENTE; sin escrituras. | `33_culm001_a_mensajes.sql` |
| `REV_008` | SUCCESS | BAJO | La solicitud de revisión fue retirada. | Actualizacion: la solicitud de revision [{}] paso al estado de RECLAMO/ESTADO_RETIRADO. | `33_culm001_a_mensajes.sql` |
| `REV_020` | BUSINESS_ERROR | MEDIO | El plazo para justificar esta inasistencia venció el {}. | HU026B: instante {} >= límite {} (ASISTENCIA/DIAS_LIMITE_JUSTIFICACION={}). | `51_culm001_d1_mensajes.sql` |
| `REV_025` | TECHNICAL_ERROR | ALTO | No es posible validar el plazo de justificación en este momento. | HU026B: falta ASISTENCIA/DIAS_LIMITE_JUSTIFICACION o TIEMPO/ZONA_HORARIA_SQLSERVER. | `51_culm001_d1_mensajes.sql` |

## SEC

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `SEC_001` | BUSINESS_ERROR | ALTO | No tiene permisos suficientes para realizar esta operación. | RBAC denegado: el usuario no posee perfil activo requerido o no existe/está inactivo. | `04_mensaje.sql` |
| `SEC_002` | BUSINESS_ERROR | ALTO | No tiene autorización sobre el recurso solicitado. | Titularidad denegada: el usuario no está autorizado sobre el recurso solicitado. | `04_mensaje.sql` |

## SES

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `SES_001` | BUSINESS_ERROR | MEDIO | La sesión de clase especificada no existe o no se encuentra activa. | Error de búsqueda: Sesión no encontrada o cerrada en uv_sesion: {}. | `04_mensaje.sql` |
| `SES_002` | BUSINESS_ERROR | MEDIO | El código de verificación de asistencia es incorrecto o ha expirado. | Validación fallida: Token QR o código de verificación no coincide o venció para Sesión: {}. | `04_mensaje.sql` |
| `SES_003` | BUSINESS_ERROR | MEDIO | El cierre de sesión no está soportado por el contrato vigente de base de datos. | LEGACY_NOT_SUPPORTED: dbo.Sesion no posee columna de cierre/estado; usp_cerrar_sesion no persiste cierre real. | `04_mensaje.sql` |
| `SES_004` | BUSINESS_ERROR | MEDIO | La fecha y hora de fin de sesión debe ser posterior a la fecha y hora de inicio. | Validación temporal fallida: fechaHoraFin [{}] debe ser posterior a fechaHoraInicio [{}]. | `04_mensaje.sql` |
| `SES_005` | BUSINESS_ERROR | MEDIO | El horario institucional incluye una hora local inexistente por cambio de horario; no se generaron sesiones. | Validación temporal fallida: la zona [{}] no contiene la hora local [{}] (salto DST); generación abortada sin escrituras. | `04_mensaje.sql` |
| `SES_006` | BUSINESS_ERROR | ALTO | La sesión no coincide con el manifiesto de clasificación aprobado; no se modificó. | Clasificación UTC_OWNER rechazada: la sesión [{}] no coincide con el manifiesto [{}] (procedencia no NULL u horas distintas). | `04_mensaje.sql` |
| `SES_007` | BUSINESS_ERROR | MEDIO | La sesión de clase aún no ha iniciado; la asistencia solo se registra durante la sesión. | SES-01 ventana de registro: la sesión [{}] no ha iniciado (SYSUTCDATETIME() < fechaHoraInicio); lote rechazado sin escrituras. | `04_mensaje.sql` |
| `SES_008` | BUSINESS_ERROR | MEDIO | La sesión de clase ya finalizó; la asistencia solo puede modificarse mediante un reclamo. | SES-01 ventana de registro: la sesión [{}] está cerrada (SYSUTCDATETIME() >= fechaHoraFin); lote rechazado sin escrituras. | `04_mensaje.sql` |
| `SES_009` | BUSINESS_ERROR | MEDIO | El horario de la sesión no está confirmado; no es posible registrar asistencia. | SES-01 ventana de registro: la sesión [{}] tiene procedencia temporal INDETERMINADA (procedenciaTemporal NULL); lote rechazado sin escrituras. | `04_mensaje.sql` |
| `SES_010` | BUSINESS_ERROR | MEDIO | La sesión fue cancelada; no admite registro de asistencia. | Sesión [{}] cancelada (SesionCancelacion existe); operación rechazada sin escrituras. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `SES_011` | BUSINESS_ERROR | BAJO | La sesión ya estaba cancelada. | Sesión [{}] con SesionCancelacion previa; se conserva el motivo original. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `SES_012` | BUSINESS_ERROR | MEDIO | No es posible cancelar una sesión que ya tiene asistencia registrada. | Sesión [{}] con Asistencia o TomaAsistencia; cancelación rechazada. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `SES_013` | VALIDATION_ERROR | BAJO | El motivo de cancelación debe tener entre {} y {} caracteres. | Longitud de @motivo fuera de SESION/MOTIVO_CANCELACION_LONGITUD_*. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `SES_014` | SUCCESS | BAJO | La sesión fue cancelada y se avisó a los estudiantes. | SesionCancelacion creada para [{}] tipo [{}]. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `SES_016` | BUSINESS_ERROR | MEDIO | La sesión ya terminó y tiene asistencia registrada; no se puede cancelar. Las correcciones se hacen por reclamo. | Sesión [{}] con Asistencia o TomaAsistencia y SYSUTCDATETIME() >= fin + MARGEN_RETARDO_MINUTOS; cancelación rechazada. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `SES_017` | BUSINESS_ERROR | MEDIO | La sesión se cruza con otra sesión del grupo o del docente en ese horario. | Regla: la sesion se cruza con la sesion [{}] del mismo grupo o de otro grupo del mismo docente (inicio < fin y fin > inicio); sin escrituras. | `33_culm001_a_mensajes.sql` |

## SUC

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `SUC_REGISTRO_ASISTENCIA` | SUCCESS | BAJO | Asistencia registrada de forma satisfactoria. | Sincronizacion de asistencia completa. Registrada para: {}. | `04_mensaje.sql` |
| `SUC_REGISTRO_DOCENTE_GRUPO` | SUCCESS | BAJO | Se ha registrado el docente en el grupo de forma satisfactoria. | Operacion exitosa completa. Orquestador finalizado para Docente en Grupo: {}. | `04_mensaje.sql` |
| `SUC_REGISTRO_ESTUDIANTE_GRUPO` | SUCCESS | BAJO | Se ha registrado el estudiante en el grupo de forma satisfactoria. | Operacion exitosa completa. Orquestador finalizado para Estudiante en Grupo: {}. | `04_mensaje.sql` |

## SYS

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `SYS_001` | SYSTEM_ERROR | CRITICO | Ocurrió un error inesperado al procesar la solicitud. | Excepción de sistema no controlada capturada en bloque CATCH: {}. | `04_mensaje.sql` |

## TOM

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `TOM_001` | BUSINESS_ERROR | BAJO | La toma de asistencia no existe. | Toma [{}] inexistente o de otra sesión. | `35_mensajes_toma_asistencia_qr.sql` |
| `TOM_002` | VALIDATION_ERROR | BAJO | El modo de la toma no es válido. | @codigoModo [{}] no existe en ModoTomaAsistencia. | `35_mensajes_toma_asistencia_qr.sql` |
| `TOM_003` | BUSINESS_ERROR | BAJO | Ya hay una toma abierta en esta sesión; ciérrala antes de abrir otra. | Sesión [{}] con toma abierta [{}]. | `35_mensajes_toma_asistencia_qr.sql` |
| `TOM_004` | BUSINESS_ERROR | BAJO | La sesión ya tiene el máximo de {} tomas. | TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION alcanzado en [{}]. | `35_mensajes_toma_asistencia_qr.sql` |
| `TOM_008` | SUCCESS | BAJO | Toma {} abierta. | TomaAsistencia [{}] abierta modo [{}]. | `35_mensajes_toma_asistencia_qr.sql` |
| `TOM_009` | SUCCESS | BAJO | Toma cerrada. {} estudiantes quedaron como ausentes. | TomaAsistencia [{}] cerrada; ausentes marcados {}. | `35_mensajes_toma_asistencia_qr.sql` |
| `TOM_010` | SUCCESS | BAJO | Asistencia de la toma guardada. | Lote de toma [{}] con {} registros. | `35_mensajes_toma_asistencia_qr.sql` |
| `TOM_011` | SUCCESS | BAJO | La toma ya estaba cerrada. | TomaAsistencia [{}] ya cerrada; sin escrituras. | `35_mensajes_toma_asistencia_qr.sql` |

## TPR

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `TPR_001` | BUSINESS_ERROR | MEDIO | El tipo de programa especificado no existe en el sistema. | Error de búsqueda: No se encontró el tipo de programa en uv_tipo_programa: {}. | `04_mensaje.sql` |
| `TPR_002` | BUSINESS_ERROR | ALTO | Ya existe un tipo de programa con el mismo código o nombre. | Error de unicidad: código o nombre duplicado en tipo de programa. | `04_mensaje.sql` |

## USU

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `USU_001` | BUSINESS_ERROR | MEDIO | El usuario especificado no existe en el sistema. | Error de búsqueda: No se encontró el usuario con el ID especificado: {}. | `04_mensaje.sql` |
| `USU_002` | BUSINESS_ERROR | ALTO | El usuario especificado se encuentra inactivo en la plataforma. | Restricción de acceso: El usuario [{}] tiene estaActivo = 0. | `04_mensaje.sql` |

## VAL

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `VAL_001` | BUSINESS_ERROR | MEDIO | El número de identificación es obligatorio. | Validación de campo: numeroIdentificacion no está presente o es nulo. | `04_mensaje.sql` |
| `VAL_002` | BUSINESS_ERROR | MEDIO | El número de identificación debe tener entre {} y {} dígitos. | Validación de rango: numeroIdentificacion debe tener una longitud de entre {} y {} dígitos. | `04_mensaje.sql` |
| `VAL_003` | BUSINESS_ERROR | MEDIO | Los nombres y apellidos son obligatorios. | Validación de campo: nombres o apellidos vacíos o no proporcionados. | `04_mensaje.sql` |
| `VAL_004` | BUSINESS_ERROR | MEDIO | El campo {} contiene caracteres no permitidos. | Validación de formato: El valor enviado para [{}] contiene caracteres especiales no válidos. | `04_mensaje.sql` |
| `VAL_005` | BUSINESS_ERROR | MEDIO | El correo electrónico es obligatorio y debe tener un formato válido. | Validación de formato: La dirección de correo electrónico no cumple con la estructura estándar. | `04_mensaje.sql` |
| `VAL_006` | BUSINESS_ERROR | ALTO | La dirección de correo electrónico ya se encuentra registrada. | Fallo de unicidad: El correo electrónico ya existe en la vista uv_usuario. | `04_mensaje.sql` |
| `VAL_007` | BUSINESS_ERROR | ALTO | La contraseña no cumple con los requisitos mínimos de seguridad. | Validación de seguridad: La contraseña no satisface las políticas de complejidad establecidas. | `04_mensaje.sql` |

## VCE

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `VCE_001` | BUSINESS_ERROR | MEDIO | El correo del estudiante debe ser institucional y terminar en {}. | Regla: el correo de un alta nueva no cumple REGISTRO/DOMINIO_CORREO_ESTUDIANTE ({}). | `27_mensajes_ident001.sql` |
| `VCE_002` | BUSINESS_ERROR | MEDIO | El enlace de verificación no es válido o ya venció. | Token de verificación inexistente, vencido, usado, revocado o de usuario inactivo. | `27_mensajes_ident001.sql` |
| `VCE_003` | BUSINESS_ERROR | BAJO | Debe esperar unos minutos antes de volver a enviar el enlace de verificación. | Regla: aún no transcurre VERIFICACION_CORREO/REENVIO_ESPERA_MINUTOS desde la última emisión. | `27_mensajes_ident001.sql` |
| `VCE_004` | BUSINESS_ERROR | MEDIO | El estudiante no pertenece a un grupo a su cargo. | Ámbito: el ejecutor no es titular del grupo ni coordinador de su programa, o el estudiante no pertenece al grupo. | `27_mensajes_ident001.sql` |
| `VCE_005` | BUSINESS_ERROR | BAJO | El correo de este estudiante ya fue verificado. | Estado: Usuario.correoConfirmado ya es 1. | `27_mensajes_ident001.sql` |
| `VCE_006` | SUCCESS | BAJO | Su correo fue verificado. Ya puede iniciar sesión. | Token consumido y Usuario.correoConfirmado = 1. | `27_mensajes_ident001.sql` |
| `VCE_007` | BUSINESS_ERROR | MEDIO | El usuario no existe o no está activo. | Existencia: no hay dbo.Usuario activo con el id indicado. | `27_mensajes_ident001.sql` |

