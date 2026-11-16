# Guía Rápida: `ZGEN_AUDITORIA_CDS_BQ` (Auditoría y Corrección Masiva de Vistas CDS para BigQuery)

Archivo fuente ABAP: `Auditoria_Unificada_CDS_BQ.abap`  
Programa en SAP (`SE38`): `ZGEN_AUDITORIA_CDS_BQ`

---

## 1. Flujo de Trabajo Recomendado (Paso a Paso)

1. **Generar las vistas CDS base** en `SE38` con **`ZGOOG_R_BQTR_GEN_MASS_CDS_VIEW`** (dejando **sin liberar** la Orden de Transporte creada).
2. **Ejecutar `ZGEN_AUDITORIA_CDS_BQ` en Modo Lectura (por defecto):**
   - Pegar tu listado de ~150 tablas en **`S_TAB`** (*Selección múltiple -> Pegar portapapeles*).
   - En **`S_CDS`** ingresar el prefijo de tus vistas, ej. **`ZCDS*`**.
   - Elegir **Vista Resumen** (1 fila por tabla) para ver el panorama general, exportar a Excel el control de **Mandante (`SI` / `NO TIENE`)**, e identificar si hay objetos tipo **`VISTA DDIC` (`VIEW`)**.
3. **Probar corrección en 1 tabla (opcional pero recomendado):**
   - Dentro del ALV, hacer **doble clic en `Est. CDS` o `Acción CDS`** sobre una tabla `TRANSPARENTE` y elegir **`Guardar/Activar`**. Verificar que cambie a **`ACTIVA (OK)`** en verde.
4. **Aplicar corrección y activación masiva:**
   - Volver atrás (`F3`), marcar en la **Sección 4** la opción **`Modificar y Activar Vistas CDS Masivamente con el código sugerido`** y ejecutar (`F8`).
   - Como la OT de creación sigue abierta, SAP la reutiliza automáticamente sin pedir transporte vista por vista.
5. **Revisar solo las excepciones en rojo (en Eclipse ADT):**
   - Las vistas que queden en rojo (`INACTIVA` o `VISTA DDIC`) son los únicos casos especiales a resolver manualmente antes de pasar a `ZGOOG_R_BQTR_GEN_REPL_OBJECTS`.

---

## 2. Resumen de la Pantalla de Selección

### Sección 1 — Selección de Tablas SAP
* **`S_TAB`:** Rango o lista de tablas a auditar (usar el botón de flecha/selección múltiple para pegar desde Excel).
* **`Archivo TXT/CSV (opc.)`:** Permite cargar las tablas desde un archivo local (toma la 1ª columna).
* **`Incluir también las 122 tablas...`:** Agrega una lista estándar de referencia (SAP Cortex). Déjalo **desmarcado** si solo quieres evaluar tu propia lista pegada en `S_TAB`.

### Sección 2 — Vínculo con Vistas CDS Creadas
* **`S_CDS`:** Filtro con comodín para enlazar tus vistas (ej. `ZCDS*` o `Z*BQ*`). Busca tanto vistas **activas** como **inactivas**.

### Sección 3 — Modo de Visualización ALV
* **`Vista Detallada`:** 1 fila por cada columna especial detectada (`RAW`, `DF34_RAW`, `QUAN`, `CURR`), mostrando tabla/campo de referencia en `SE11` (`REFTABLE`/`REFFIELD`), claves primarias y expresión CDS sugerida.
* **`Vista Resumen`:** 1 fila por tabla con conteos, listado de columnas afectadas, tipo de objeto (`TRANSPARENTE` vs `VISTA DDIC`) y columna de **Mandante** (`MANDT`, `RCLNT`, `CLIENT` o `NO TIENE`).
* **`No tocar/ocultar QUAN/CURR cuya moneda/unidad ya está en la misma tabla`:**
  * **Desmarcado (por defecto):** Audita y castea a `abap.dec` **todos** los campos `QUAN` y `CURR`.
  * **Marcado:** Respeta sin castear los `QUAN`/`CURR` cuya moneda/unidad ya existe en la misma tabla y solo castea los que apuntan a tablas/estructuras externas.

### Sección 4 — Modificación y Activación Automática de Vistas CDS (Solo `TRANSP`)
* **`Solo Auditoría / Lectura` *(por defecto)*:** No modifica nada en SAP ni pide OT.
* **`Modificar y Activar Vistas CDS Masivamente...`:** Aplica el código sugerido y activa todas las vistas CDS de tablas **`TRANSPARENTES`** (omite automáticamente objetos `VIEW`). Muestra confirmación previa antes de guardar.
* **`Activar también vistas CDS INACTIVAS (TRANSP) que ya estén limpias`:** Si una vista `TRANSP` no necesita cambios de código pero estaba `INACTIVA`, la activa también.
* **`Si falla activar una vista que estaba ACTIVA, restaurar su original`:** Seguro automático; si una vista ya funcionaba activa y por un caso borde falla la nueva activación, revierte al código original activo (`ACTIVA (REV)`).
* **`OT opcional (vacío = OT abierta)`:** Déjalo **vacío** mientras trabajes sobre la misma OT sin liberar. Solo llénalo si ya liberaste la OT anterior y deseas fijar una nueva OT para todo el lote.

---

## 3. Atajos de Doble Clic dentro del ALV

| Columna donde haces Doble Clic | Acción que ejecuta |
| :--- | :--- |
| **`Tabla`** (`TABNAME`) | Abre la tabla directamente en la **`SE11`**. |
| **`Tab.Ref.`** (`REFTABLE` en Vista Detallada) | Abre la tabla/estructura de referencia de moneda o unidad en la **`SE11`**. |
| **`Vista CDS`** o **`Código CDS`** | Abre **Vista Previa** del código CDS completo corregido (solo lectura, listo para copiar si lo necesitas). |
| **`Est. CDS`** o **`Acción CDS`** | Abre ventana para **`Guardar/Activar`** esa única vista CDS en SAP en vivo (solo tablas `TRANSP`). |

---

## 4. ¿Qué corrige exactamente el motor de código CDS?

1. **Campos `RAW` (hasta 255 bytes):** Los convierte con `bintohex( campo ) as alias`.
2. **Campos `QUAN` y `CURR`:** Los castea a `cast( campo as abap.dec(Largo, Decimales) ) as alias` y comenta automáticamente su anotación `@Semantics.amount.currencyCode` / `@Semantics.quantity.unitOfMeasure` para evitar errores de compilación en Eclipse.
3. **Campos `DF34_RAW` / `DF16_RAW`:** Los castea a `abap.dec(23,6)` / `abap.dec(16,6)` (soportado en S/4HANA 2022+; en versiones anteriores, si no compila, comentar la columna en Eclipse).
4. **Campos `LRAW` / `RAWSTRING` / `RAW > 255` (no clave):** Los comenta automáticamente porque ODP/BigQuery no los soporta.
5. **Limpieza y sintaxis:**
   * Elimina el bloque interno `/*+[internal] { "BASEINFO": ... }*/` de `DDDDLSRC`.
   * **Normaliza todas las comas dentro de `{ ... }`:** asegura coma `,` al final de los elementos `1` a `N-1`, y **quita cualquier coma final** en el último elemento antes de `}`.
   * **Es idempotente:** si vuelves a correr el programa sobre vistas que ya tienen `bintohex(` o `cast(`, no duplica los cambios.

---

## 5. Recordatorios de Casos Especiales (Cheat Sheet)

### A) ¿Por qué usar `CAST` en vez de `JOIN` en `QUAN` y `CURR`?
* **Mantiene vivo el Delta CDC (`@Analytics.dataExtraction.delta.changeDataCapture.automatic: true`):** Agregar `JOIN` en la CDS rompe el CDC automático de tabla única en `DHCDCMON` / `ODQMON`.
* **Estructuras en `SE11`:** Muchas referencias apuntan a estructuras (`INTTAB`, ej. `CKMLCR`), contra las cuales es imposible hacer `JOIN` en SQL.
* **Ojo en BigQuery con monedas sin decimales (`CLP`, `JPY`, `KRW`):** SAP guarda internamente `10.000 CLP` como `100.00` en campos `DEC(2)`. Al llevar la tabla `TCURX` a BigQuery, aplica el factor `10^(2 - CURRDEC)` en tu capa de vistas/reportes de BigQuery.

### B) Error `Base object ... of type VIEW is not allowed for view entities` (Ej: `BPVG`, `COSP`, `COSS`)
Las **CDS View Entities** (`define view entity`) y el **Delta CDC** no permiten usar vistas clásicas de diccionario (`SE11` tipo `VIEW`) ni *Compatibility Views* de S/4HANA:
* **Opción recomendada (con Delta CDC):** Replicar las **tablas físicas transparentes (`TRANSP`) base** y armar la unión en BigQuery:
  * **`BPVG`** $\rightarrow$ Replicar **`BPGE`** y **`BPJA`** (el reporte `ZGEN_AUDITORIA_CDS_BQ` te muestra las tablas base en la columna `Acción CDS`).
  * **`COSP` / `COSS` (en S/4HANA)** $\rightarrow$ Los reales actuales ya están en **`ACDOCA`**; si requieres saldos históricos/estadísticos/plan fuera de `ACDOCA`, replicar **`COSP_BAK`** y **`COSS_BAK`** (y/o `ACDOCP`).
* **Opción alternativa (solo para *Full Load* sin CDC en vistas chicas como `BPVG`):** Cambiar en Eclipse esa vista puntual de `define view entity` a CDS clásica (`define view` + `@AbapCatalog.sqlViewName: 'ZV_...'`) y quitar la anotación `changeDataCapture`.
