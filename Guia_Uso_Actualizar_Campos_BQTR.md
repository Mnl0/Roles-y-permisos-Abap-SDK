# Guía Rápida: `ZGEN_BQTR_CAMPOS_TECNICOS` (Nombres Técnicos Masivos en BigQuery Data Transfer)

Archivo fuente ABAP: [Actualizar_Campos_BQTR_Tecnicos.abap](file:///G:/ABAP-SDK/Actualizar_Campos_BQTR_Tecnicos.abap)  
Programa sugerido en SAP (`SE38`): `ZGEN_BQTR_CAMPOS_TECNICOS`

---

## 1. ¿Qué resuelve este programa?

Cuando configuras un Data Transfer en **`/GOOG/BQTR_SETTINGS`** apuntando a vistas CDS (ej. `ZCDS_ACDOCA` $\rightarrow$ `acdoca`, `ZCDS_ADR6` $\rightarrow$ `adr6`), el conector toma por defecto las etiquetas/descripciones de los elementos de datos SAP (`from`, `address_number`, `company_code`, etc.) en lugar de los nombres técnicos de columna (`date_from`, `addrnumber`, `rbukrs`).

Este programa evita entrar tabla por tabla a **`Display Field` (`@10@`)** en las ~150 vistas CDS:
* **Auto-detecta dinámicamente** las columnas exactas de `/GOOG/BQTR_MASTR`, `/GOOG/BQTR_TABLE` y `/GOOG/BQTR_FIELD` en tu versión del *ABAP SDK for Google Cloud* (sin riesgo de error de sintaxis al activar en `SE38`).
* Copia masivamente **`SAP Field Name` $\rightarrow$ `Temp Field` y `Ext Field Name`** en minúsculas según estándar BigQuery (`DATE_FROM` $\rightarrow$ `date_from`, `/CWM/MENGE` $\rightarrow$ `cwm_menge`, `_DATAAGING` $\rightarrow$ `_dataaging`).
* **Respeta intactos** todos los tipos de datos BigQuery (`DATE`, `STRING`, `NUMERIC`, `INTEGER`, etc.) y los campos extra de control del toolkit (`recordstamp`, `operation_flag`).

---

## 2. Paso a Paso Recomendado (Seguro y Gradual)

1. **Cerrar `/GOOG/BQTR_SETTINGS` (o dejarla solo en visualización):**
   - Así evitas que la transacción mantenga bloqueada la tabla `/GOOG/BQTR_FIELD`.
2. **Crear el programa en `SE38`:**
   - Crear el reporte ejecutable **`ZGEN_BQTR_CAMPOS_TECNICOS`**, pegar el contenido de [Actualizar_Campos_BQTR_Tecnicos.abap](file:///G:/ABAP-SDK/Actualizar_Campos_BQTR_Tecnicos.abap) y activar (`Ctrl+F3`). No requiere configurar *Text Elements*.
3. **Ejecutar primero en Modo Simulación (por defecto):**
   - En **`Data Transfer (Mass Tr.Key)`** presiona **`F4`** y elige tu Data Transfer.
   - Deja **`S_DSRC` vacío** para ver las ~150 tablas de un vistazo y ejecuta (`F8`).
   - En el ALV Resumen verás:
     - En **verde (`YA TÉCNICO (OK)`)** las tablas que ya habías corregido manualmente (como `ZCDS_ADRC`).
     - En **amarillo (`PENDIENTE ACTUALIZAR`)** las demás tablas con el conteo de columnas a corregir y ejemplos `Antes -> Después`.
     - *(Nota)* Si las tablas donde aún no habías presionado `@10@` aparecen en naranjo como **`SIN CAMPOS (0 FILAS)`**, vuelve atrás (`F3`) y marca el check **`Si una vista de BQTR_TABLE tiene 0 filas en BQTR_FIELD, generarlas de CDS`**.
4. **Probar primero con 1 sola tabla desde el ALV (opcional pero recomendado):**
   - Haz **doble clic en `Fuente SAP`** sobre una tabla pequeña (ej. `ZCDS_ADR6`) para inspeccionar todas sus columnas en una ventana emergente.
   - Haz **doble clic en `Estado` o `Acción`** sobre `ZCDS_ADR6` y elige **`Actualizar Tabla`**.
   - Entra a **`/GOOG/BQTR_SETTINGS`** $\rightarrow$ `Display Field` (`@10@`) de `ZCDS_ADR6` y verifica que haya quedado idéntica a `ZCDS_ADRC`.
5. **Aplicar a todas las ~150 tablas restantes en segundos:**
   - Vuelve al programa, selecciona en el **Bloque 4** la opción **`Actualizar Masivamente el Data Transfer en /GOOG/BQTR_FIELD`**, presiona **`F8`** y confirma el diálogo.

---

## 3. Atajos Interactivos en el ALV

| Columna donde haces Doble Clic | Acción que ejecuta |
| :--- | :--- |
| **`Fuente SAP`** (`DATASOURCE`) | Abre un popup ALV con todas las columnas de esa vista CDS (`SAP Field`, `Tipo BQ`, `Temp Field Actual`, `Ext Field Actual`, `Nuevo Nombre Técnico`, `Descripción`). |
| **`Estado` / `Acción` / `Pendientes`** | Permite aplicar y guardar en `/GOOG/BQTR_FIELD` **únicamente esa tabla** en caliente y refresca el ALV. |
