# Guía Rápida: `ZGEN_AUDITORIA_CDS_BQ` (Auditoría y Corrección Masiva de Vistas CDS para BigQuery)

Archivo fuente ABAP: `Auditoria_Unificada_CDS_BQ.abap`  
Programa en SAP (`SE38`): `ZGEN_AUDITORIA_CDS_BQ`

---

## 1. Flujo de Trabajo Recomendado (Paso a Paso)

1. **Generar las vistas CDS base** en `SE38` con **`ZGOOG_R_BQTR_GEN_MASS_CDS_VIEW`** (dejando **sin liberar** la Orden de Transporte creada).
2. **Ejecutar `ZGEN_AUDITORIA_CDS_BQ` en Modo Lectura (por defecto):**
   - Pegar tu listado de ~150 tablas en **`S_TAB`** (*Selección múltiple -> Pegar portapapeles*).
   - En **`S_CDS`** ingresar el prefijo de tus vistas, ej. **`ZCDS*`**.
   - Elegir **Vista Resumen** (1 fila por tabla) para revisar de un vistazo:
     - **Compatibility Views / Objetos Proxy** (`¿Compat.?`, `Obj.Proxy`, `Ent.Dest.` y `Reemplazo`, ej. `MARC` $\rightarrow$ `NSDM_V_MARC` $\rightarrow$ `NSDM_E_MARC`).
     - Control de **Mandante (`SI` / `NO TIENE`)** exportable a Excel.
     - Objetos tipo **`VISTA DDIC` (`VIEW`)** (ej. `BPVG`, `COSP`, `COSS`).
3. **Probar corrección en 1 tabla (opcional pero recomendado):**
   - Dentro del ALV, hacer **doble clic en `Est. CDS` o `Acción CDS`** sobre una tabla `TRANSPARENTE` (incluso una con Compatibility View como `MARC`) y elegir **`Guardar/Activar`**. Verificar que pase a **`ACTIVA (OK)`** en verde.
4. **Aplicar corrección y activación masiva:**
   - Volver atrás (`F3`), marcar en la **Sección 4** la opción **`Modificar y Activar Vistas CDS Masivamente con el código sugerido`** (manteniendo marcado el check de *Compatibility Views*) y ejecutar (`F8`).
   - Como la OT de creación sigue abierta, SAP la reutiliza automáticamente sin pedir transporte vista por vista.
5. **Revisar solo las excepciones en rojo (en Eclipse ADT):**
   - Las vistas que queden en rojo (`INACTIVA` o `VISTA DDIC`) son los únicos casos especiales a resolver manualmente antes de pasar a `ZGOOG_R_BQTR_GEN_REPL_OBJECTS`.

---

## 2. Resumen de la Pantalla de Selección

### Sección 1 — Selección de Tablas SAP
* **`S_TAB`:** Rango o lista de tablas a auditar (usar el botón de flecha/selección múltiple para pegar desde Excel).
* **`Archivo TXT/CSV (opc.)`:** Permite cargar las tablas desde un archivo local (toma la 1ª columna).
* **`Incluir también las 122 tablas...`:** Agrega una lista estándar de referencia. Déjalo **desmarcado** si solo quieres evaluar tu propia lista pegada en `S_TAB`.

### Sección 2 — Vínculo con Vistas CDS Creadas
* **`S_CDS`:** Filtro con comodín para enlazar tus vistas (ej. `ZCDS*` o `Z*BQ*`). Reconoce tanto vistas que apuntan directo a la tabla (`marc`) como vistas ya modificadas para apuntar a su entidad de compatibilidad (`nsdm_e_marc`).

### Sección 3 — Modo de Visualización ALV
* **`Vista Detallada`:** 1 fila por cada hallazgo (`COMPATIBILITY VIEW`, `RAW`, `DF34_RAW`, `QUAN`, `CURR`, `VISTA DDIC`), mostrando objeto proxy, entidad destino, tabla/campo de referencia en `SE11` (`REFTABLE`/`REFFIELD`) y código CDS sugerido.
* **`Vista Resumen`:** 1 fila por tabla con detección de **Compatibility View**, conteos, listado de columnas afectadas, tipo de objeto (`TRANSPARENTE`, `TRANSP (COMPAT.)`, `VISTA DDIC`) y columna de **Mandante** (`MANDT`, `RCLNT`, `CLIENT` o `NO TIENE`).
* **`No tocar/ocultar QUAN/CURR cuya moneda/unidad ya está en la misma tabla`:**
  * **Desmarcado (por defecto):** Audita y castea a `abap.dec` **todos** los campos `QUAN` y `CURR`.
  * **Marcado:** Respeta sin castear los `QUAN`/`CURR` cuya moneda/unidad ya existe en la misma tabla y solo castea los que apuntan a tablas/estructuras externas.

### Sección 4 — Modificación y Activación Automática de Vistas CDS (Solo `TRANSP`)
* **`Solo Auditoría / Lectura` *(por defecto)*:** No modifica nada en SAP ni pide OT.
* **`Modificar y Activar Vistas CDS Masivamente...`:** Aplica el código sugerido y activa todas las vistas CDS de tablas **`TRANSPARENTES`** (incluyendo las híbridas con *Compatibility View* como `MARC`, `MARD`, `MBEW`; omite objetos `VIEW` puros).
* **`Reemplazar SELECT FROM en Compatibility Views (ej. nsdm_e_marc as marc)` *(marcado por defecto)*:**
  * Si la tabla tiene objeto proxy en `DD02L-VIEWREF` (ej. `MARC` $\rightarrow$ `NSDM_V_MARC` $\rightarrow$ `NSDM_E_MARC`), reescribe automáticamente `as select from marc` por **`as select from nsdm_e_marc as marc`** conservando intactas todas las anotaciones `@Analytics` (incluido `changeDataCapture.automatic: true`).
  * Si lo desmarcas, el ALV igual muestra las columnas informativas de Compatibility View, pero no cambia el `select from`.
* **`Activar también vistas CDS INACTIVAS (TRANSP) que ya estén limpias`:** Si una vista `TRANSP` no necesita cambios de código pero estaba `INACTIVA`, la activa también.
* **`Si falla activar una vista que estaba ACTIVA, restaurar su original`:** Seguro automático; si una vista ya funcionaba activa y falla la nueva activación, revierte al código original activo (`ACTIVA (REV)`).
* **`OT opcional (vacío = OT abierta)`:** Déjalo **vacío** mientras trabajes sobre la misma OT sin liberar.

---

## 3. Columnas de Compatibility View y Atajos de Doble Clic en el ALV

| Columna donde haces Doble Clic | Qué muestra / Acción que ejecuta |
| :--- | :--- |
| **`Tabla`** (`TABNAME`) | Abre la tabla directamente en la **`SE11`**. |
| **`¿Compat.?`** (`ES_COMPAT`) | Indica `SI (REEMPLAZAR)` en naranjo, `SI (YA APUNTA)` en verde, o `NO`. |
| **`Obj.Proxy`** (`PROXY_OBJ`) | Objeto Proxy visible en `SE16N` / `DD02L-VIEWREF` (ej. `NSDM_V_MARC`). **Doble clic** lo abre en `SE11`. |
| **`Ent.Dest.`** (`CDS_TARGET`) | Entidad CDS real a la que apunta el proxy (ej. `NSDM_E_MARC`). **Doble clic** muestra el DDL estándar SAP. |
| **`Reemplazo`** (`CODIGO_REPL`) | Sentencia lista: `define root view entity ZCDS_MARC as select from nsdm_e_marc as marc`. **Doble clic** abre la vista previa completa. |
| **`Tab.Ref.`** (`REFTABLE` en Detalle) | Abre la tabla/estructura de referencia en la **`SE11`**. |
| **`Vista CDS`** o **`Código CDS`** | Abre **Vista Previa** del código CDS completo corregido (solo lectura). |
| **`Est. CDS`** o **`Acción CDS`** | Abre ventana para **`Guardar/Activar`** esa única vista CDS en SAP en vivo (solo tablas `TRANSP`). |

---

## 4. ¿Qué corrige exactamente el motor de código CDS?

1. **Compatibility Views (`DD02L-VIEWREF` $\rightarrow$ `DDLDEPENDENCY`):** Cambia `as select from <tabla>` por `as select from <entidad_reemplazo> as <tabla>` (ej. `as select from nsdm_e_marc as marc`) sin alterar `changeDataCapture.automatic: true` ni el resto de anotaciones de cabecera.
2. **Campos `RAW` (hasta 255 bytes):** Los convierte con `bintohex( campo ) as alias`.
3. **Campos `QUAN` y `CURR`:** Los castea a `cast( campo as abap.dec(Largo, Decimales) ) as alias` y comenta automáticamente su anotación `@Semantics.amount.currencyCode` / `@Semantics.quantity.unitOfMeasure`.
4. **Campos `DF34_RAW` / `DF16_RAW` / `DF34_SCL` / `DF16_SCL` (no clave):** Los **comenta automáticamente** (`// campo // Excluido: DF34_RAW no soportado en CDS/BQ`) junto con cualquier `@Semantics` asociada (incluso si ya tenían un `cast(` fallido de una corrida previa).
5. **Campos `LRAW` / `RAWSTRING` / `RAW > 255` (no clave):** Los comenta automáticamente porque ODP/BigQuery no los soporta.
6. **Limpieza y sintaxis:**
   * Elimina el bloque interno `/*+[internal] { "BASEINFO": ... }*/` de `DDDDLSRC`.
   * **Normaliza todas las comas dentro de `{ ... }`:** asegura coma `,` al final de los elementos activos `1` a `N-1`, y **quita cualquier coma final** en el último elemento activo antes de `}` (por ejemplo, cuando se comenta un `DF34_RAW` al final de la vista).
   * **Es idempotente:** si vuelves a correr el programa sobre vistas que ya apuntan a `nsdm_e_marc` o ya tienen `bintohex(` / `cast(`, no duplica los cambios.

---

## 5. Recordatorios de Casos Especiales (Cheat Sheet)

### A) Tablas con Palabras Reservadas CDS como `PRHI` (`left` / `right`)
* En tablas como `PRHI`, las columnas `left` y `right` chocan con palabras reservadas de ABAP CDS. En Eclipse ADT, usa alias de tabla (`as select from prhi as _prhi`) y califica + renombra (`_prhi.left as left_node`, `_prhi.right as right_node`), o comenta `left`/`right` (ya que `posnr`, `psphi` y `up` contienen toda la jerarquía Padre-Hijo).

### B) Tablas con Claves Primarias `RAW` y Delta CDC (Ej: `MATDOC`)
* Validar siempre con **`RODPS_REPL_TEST`** (*Initialization of Delta Process*) en `SE38` si una vista con Delta CDC tiene `bintohex(...)` en sus campos `key` (`key1..key6`), para confirmar que `DHCDCMON` acepte el mapeo o dejar las `key` directas sin `bintohex`.

### C) Objetos tipo `VIEW` en `SE11` (`BPVG`, `COSP`, `COSS`)
* Las *View Entities* no admiten vistas clásicas `VIEW` de diccionario:
  * Para carga **Full Load (sin CDC)**, elimínalas en Eclipse y recréalas marcando **`Create CDS View (Obsolete)`** desmarcando CDC.
  * Para **Delta CDC**, replica sus tablas físicas transparentes (`BPGE` + `BPJA` para `BPVG`; `ACDOCA` + `COSP_BAK`/`COSS_BAK` para `COSP`/`COSS`).
