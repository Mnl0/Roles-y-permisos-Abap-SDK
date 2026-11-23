# Guía Rápida: `ZGEN_BQTR_POST_REPL_BW` (Automatización Post-Generación BW en `RSA1` y `RSPC`)

Archivo fuente ABAP: [Post_Config_Artefactos_BW_BQ.abap](file:///G:/ABAP-SDK/Post_Config_Artefactos_BW_BQ.abap)  
Programa sugerido en SAP (`SE38`): `ZGEN_BQTR_POST_REPL_BW`

---

## 1. ¿Qué automatiza este programa?

Después de ejecutar **`ZGOOG_R_BQTR_GEN_REPL_OBJECTS`** (con *Enable Streaming* marcado y *Activate Process Chain* desmarcado para no planificar las cadenas en DEV), este programa descubre automáticamente toda la cadena de objetos BW por cada una de las ~150 tablas (`RSDS` $\rightarrow$ `TRFN` + `Start Routine` $\rightarrow$ `ADSO` $\rightarrow$ `DTP Delta` / `DTP Full` $\rightarrow$ `Cadena RSPC`) y ejecuta los **4 pasos manuales en el orden exacto de dependencias**:

1. **Paso 1 — Fuente de Datos (`RSDS` $\rightarrow$ pestaña *Campos*):**
   * Revisa si existe filtro en **`Clase de campo`** (ej. `'L'` de idioma en tablas de textos como `MAKT`, `SKAT`, `T005T`).
   * Si lo encuentra, lo deja en blanco, guarda y activa la `RSDS` (**antes** de tocar la transformación para no dejarla inactiva).
2. **Paso 2 — Transformación (`TRFN`) + Rutina de Inicio (`ROUT`):**
   * Abre la `Start Routine`, le aplica un toque inocuo (`*" BQTR-SYNC ...` sin acumular líneas repetidas si lo corres más de una vez), guarda y fuerza la activación de la `TRFN` para que tanto la transformación como sus rutinas queden consolidadas en versión activa `'A'` y viajen completas desde la *Conexión de Transporte* (`RSA1`).
3. **Paso 3 — DTP Full (`DTPA`, `UPDMODE = 'F'`):**
   * Verifica si ya existe un DTP `Full` entre esa `RSDS` y ese `ADSO` (para no duplicar).
   * Si solo existe el DTP `Delta`, crea, guarda y activa el **DTP `Full`** con extracción directa del sistema fuente sin PSA.
4. **Paso 4 — Cadena de Procesos (`RSPC`):**
   * Activa la cadena de procesos (`M` $\rightarrow$ `A` vía `CL_RSPC_CHAIN->ACTIVATE`) **sin planificarla ni disparar jobs** en `SM37`.

---

## 2. Flujo de Uso Recomendado (Seguro y Gradual)

1. **Crear y activar en `SE38`:**
   * Crea el reporte ejecutable **`ZGEN_BQTR_POST_REPL_BW`**, pega el contenido de [Post_Config_Artefactos_BW_BQ.abap](file:///G:/ABAP-SDK/Post_Config_Artefactos_BW_BQ.abap) y activa con **`Ctrl+F3`** (no requiere configurar *Text Elements*).
2. **Ejecutar primero en Modo Diagnóstico / Simulación (por defecto):**
   * Elige tu **`Data Transfer`** con **`F4`** en `P_TRKEY` (o filtra por rango de ADSO en `S_ADSO`, ej. `Z*`) y presiona **`F8`**.
   * Verás una fila por cada tabla con el diagnóstico completo: qué `RSDS` tienen filtro de idioma, estado de la `TRFN`, cuál es su `DTP Delta`, si falta crear el `DTP Full`, y qué cadenas `RSPC` están en `INACTIVA (M)`.
3. **Probar primero en 1 sola tabla desde el ALV (recomendado):**
   * Haz **doble clic** sobre **1 fila** (ej. un ADSO de textos o `ADRC`) y pulsa **`Ejecutar Flujo`**.
   * Revisa ese ADSO en `RSA1` y su cadena en `RSPC` para confirmar que los 4 puntos quedaron exactos (y que en `SM37` no se planificó nada).
4. **Ejecutar para las ~150 tablas restantes:**
   * Vuelve atrás (`F3`), marca **`Ejecutar Automatización Masiva sobre los flujos encontrados`** en el **Bloque 4**, presiona **`F8`** y confirma.
   * Una vez todo figure en **`LISTO (100% OK)`** en verde, ya puedes recolectar tus objetos normalmente desde la **Conexión de Transporte** de `RSA1` rumbo a `QA` y `PRD`.

---

## 3. Atajos de Doble Clic en el ALV

| Columna donde haces Doble Clic | Acción que ejecuta |
| :--- | :--- |
| **`2.Transformación` / `ID Start Routine`** | Muestra en pantalla el código ABAP actual de la *Start Routine* en `RSAABAP`. |
| **`ADSO` / `Estado` / `Acción` (o cualquier otra)** | Abre confirmación para ejecutar los pasos seleccionados **únicamente sobre ese flujo BW** en caliente y refresca el ALV. |
