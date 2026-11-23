*&---------------------------------------------------------------------*
*& Report ZGEN_BQTR_CAMPOS_TECNICOS
*&---------------------------------------------------------------------*
*& Automatización post-configuración BigQuery Data Transfer (/GOOG/BQTR)
*& Propósito:
*&   1) Leer un Data Transfer ya creado en /GOOG/BQTR_SETTINGS
*&      (tablas /GOOG/BQTR_MASTR, /GOOG/BQTR_TABLE y /GOOG/BQTR_FIELD)
*&      detectando dinámicamente los nombres exactos de columna DDIC
*&      para evitar errores de compilación entre versiones del SDK.
*&   2) Copiar de forma masiva el nombre técnico "SAP Field Name" hacia
*&      "Temp Field" y "Ext Field Name" (normalizado a minúsculas según
*&      reglas de BigQuery: ej. DATE_FROM -> date_from, ADDRNUMBER ->
*&      addrnumber, /CWM/MENGE -> cwm_menge, _DATAAGING -> _dataaging),
*&      respetando intactos los campos extra (recordstamp / operation_flag)
*&      y todos los tipos de datos BigQuery ya calculados por el SDK.
*&   3) Modo Simulación ALV (por defecto) + Actualización individual
*&      (doble clic sobre una tabla) o Masiva (~150+ tablas en segundos).
*&   4) Opción adicional para generar filas en /GOOG/BQTR_FIELD desde
*&      DDIC/CDS si alguna tabla de /GOOG/BQTR_TABLE aún tiene 0 campos
*&      porque todavía no se ingresó a "Display Field" (@10@).
*&---------------------------------------------------------------------*
REPORT zgen_bqtr_campos_tecnicos.

*----------------------------------------------------------------------*
* Tipos globales y variable auxiliar para SELECT-OPTIONS
*----------------------------------------------------------------------*
TYPES:
  ty_dsrc_name TYPE c LENGTH 40,
  ty_ext_tname TYPE c LENGTH 60,

  BEGIN OF ty_summary,
    datasource  TYPE ty_dsrc_name,
    ext_table   TYPE ty_ext_tname,
    total_flds  TYPE int4,
    ok_flds     TYPE int4,
    pend_flds   TYPE int4,
    extra_flds  TYPE int4,
    ejemplo_chg TYPE c LENGTH 120,
    estado      TYPE c LENGTH 22,
    accion      TYPE c LENGTH 90,
    t_color     TYPE lvc_t_scol,
  END OF ty_summary,

  BEGIN OF ty_detail,
    datasource  TYPE ty_dsrc_name,
    ext_table   TYPE ty_ext_tname,
    sap_field   TYPE c LENGTH 40,
    is_key      TYPE c LENGTH 5,
    sap_type    TYPE c LENGTH 12,
    bq_type     TYPE c LENGTH 20,
    curr_tmpf   TYPE c LENGTH 60,
    curr_extf   TYPE c LENGTH 60,
    new_tech    TYPE c LENGTH 60,
    description TYPE c LENGTH 100,
    estado      TYPE c LENGTH 22,
    nota        TYPE c LENGTH 100,
    t_color     TYPE lvc_t_scol,
  END OF ty_detail,

  BEGIN OF ty_dsrc_info,
    datasource TYPE ty_dsrc_name,
    ext_table  TYPE ty_ext_tname,
  END OF ty_dsrc_info,

  BEGIN OF ty_schema_map,
    tab_mastr      TYPE tabname,
    tab_table      TYPE tabname,
    tab_field      TYPE tabname,
    " Columnas detectadas en /GOOG/BQTR_MASTR
    mst_trkey      TYPE fieldname,
    mst_ckey       TYPE fieldname,
    mst_dataset    TYPE fieldname,
    " Columnas detectadas en /GOOG/BQTR_TABLE
    tbl_trkey      TYPE fieldname,
    tbl_dsrc       TYPE fieldname,
    tbl_exttab     TYPE fieldname,
    " Columnas detectadas en /GOOG/BQTR_FIELD
    fld_mandt      TYPE fieldname,
    fld_trkey      TYPE fieldname,
    fld_dsrc       TYPE fieldname,
    fld_pos        TYPE fieldname,
    fld_sapf       TYPE fieldname,
    fld_keyflg     TYPE fieldname,
    fld_saptype    TYPE fieldname,
    fld_leng       TYPE fieldname,
    fld_inttype    TYPE fieldname,
    fld_bqtype     TYPE fieldname,
    fld_tmpf       TYPE fieldname,
    fld_extf       TYPE fieldname,
    fld_desc       TYPE fieldname,
    fld_actflg     TYPE fieldname,
    fld_uname      TYPE fieldname,
    fld_datum      TYPE fieldname,
    fld_uzeit      TYPE fieldname,
  END OF ty_schema_map,

  BEGIN OF ty_type_tpl,
    datatype TYPE string,
    inttype  TYPE string,
    bq_type  TYPE string,
  END OF ty_type_tpl,

  tt_summary   TYPE STANDARD TABLE OF ty_summary WITH DEFAULT KEY,
  tt_detail    TYPE STANDARD TABLE OF ty_detail WITH DEFAULT KEY,
  tt_dsrc_info TYPE STANDARD TABLE OF ty_dsrc_info WITH DEFAULT KEY,
  tt_type_tpl  TYPE STANDARD TABLE OF ty_type_tpl WITH DEFAULT KEY.

DATA: gv_sel_dsrc   TYPE ty_dsrc_name,
      gs_schema     TYPE ty_schema_map,
      gv_real_trkey TYPE string,
      gt_dsrc_list  TYPE tt_dsrc_info,
      gt_summary    TYPE tt_summary,
      gt_detail     TYPE tt_detail,
      gt_detail_vw  TYPE tt_detail,
      gr_fld_db_all TYPE REF TO data,
      go_salv       TYPE REF TO cl_salv_table.

*----------------------------------------------------------------------*
* Pantalla de Selección
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE txt_b1.
  SELECTION-SCREEN COMMENT /1(76) c_tip1.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(28) c_trkey FOR FIELD p_trkey.
    PARAMETERS: p_trkey TYPE c LENGTH 60 LOWER CASE VISIBLE LENGTH 42 OBLIGATORY.
  SELECTION-SCREEN END OF LINE.
  SELECT-OPTIONS: s_dsrc FOR gv_sel_dsrc.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE txt_b2.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_tmpf AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 4(73) c_tmpf FOR FIELD p_tmpf.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_extf AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 4(73) c_extf FOR FIELD p_extf.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_lower AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 4(73) c_lower FOR FIELD p_lower.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN SKIP 1.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_gen AS CHECKBOX DEFAULT abap_false.
    SELECTION-SCREEN COMMENT 4(73) c_gen FOR FIELD p_gen.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE txt_b3.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_res RADIOBUTTON GROUP rb1 DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 4(73) c_res FOR FIELD p_res.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_det RADIOBUTTON GROUP rb1.
    SELECTION-SCREEN COMMENT 4(73) c_det FOR FIELD p_det.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_onlyc AS CHECKBOX DEFAULT abap_false.
    SELECTION-SCREEN COMMENT 4(73) c_onlyc FOR FIELD p_onlyc.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b3.

SELECTION-SCREEN BEGIN OF BLOCK b4 WITH FRAME TITLE txt_b4.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_read RADIOBUTTON GROUP rb2 DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 4(73) c_read FOR FIELD p_read.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_apply RADIOBUTTON GROUP rb2.
    SELECTION-SCREEN COMMENT 4(73) c_apply FOR FIELD p_apply.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b4.

SELECTION-SCREEN BEGIN OF BLOCK b5 WITH FRAME TITLE txt_b5.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(28) c_tmst FOR FIELD p_tmst.
    PARAMETERS: p_tmst TYPE tabname DEFAULT '/GOOG/BQTR_MASTR'.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(28) c_ttab FOR FIELD p_ttab.
    PARAMETERS: p_ttab TYPE tabname DEFAULT '/GOOG/BQTR_TABLE' OBLIGATORY.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(28) c_tfld FOR FIELD p_tfld.
    PARAMETERS: p_tfld TYPE tabname DEFAULT '/GOOG/BQTR_FIELD' OBLIGATORY.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b5.

*----------------------------------------------------------------------*
* Clase Principal de Sincronización de Nombres Técnicos BQTR
*----------------------------------------------------------------------*
CLASS lcl_bqtr_sync DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      f4_transfer_key
        CHANGING cv_trkey TYPE clike,

      run,

      on_double_click
        FOR EVENT double_click OF cl_salv_events_table
        IMPORTING row column.

  PRIVATE SECTION.
    CLASS-METHODS:
      any_to_str
        IMPORTING iv_val        TYPE any
        RETURNING VALUE(rv_str) TYPE string,

      show_progress
        IMPORTING iv_pct  TYPE i
                  iv_text TYPE clike,

      table_exists
        IMPORTING iv_tabname       TYPE tabname
        RETURNING VALUE(rv_exists) TYPE abap_bool,

      get_dfies_merged
        IMPORTING iv_tabname      TYPE tabname
        RETURNING VALUE(rt_dfies) TYPE ddfields,

      meta_label_upper
        IMPORTING is_dfies      TYPE dfies
        RETURNING VALUE(rv_txt) TYPE string,

      resolve_schema
        IMPORTING iv_tmst      TYPE tabname
                  iv_ttab      TYPE tabname
                  iv_tfld      TYPE tabname
        EXPORTING es_schema    TYPE ty_schema_map
                  ev_error_msg TYPE string,

      resolve_actual_trkey
        IMPORTING iv_input_key TYPE clike
        EXPORTING ev_real_key  TYPE string
                  ev_found     TYPE abap_bool,

      format_tech_name
        IMPORTING iv_sap_field   TYPE clike
        RETURNING VALUE(rv_tech) TYPE string,

      load_transfer_data
        EXPORTING ev_error_msg TYPE string,

      get_source_dfies
        IMPORTING iv_dsrc         TYPE clike
        RETURNING VALUE(rt_dfies) TYPE ddfields,

      map_default_bq_type
        IMPORTING iv_datatype      TYPE clike
                  iv_inttype       TYPE clike
                  it_tpl           TYPE tt_type_tpl
        RETURNING VALUE(rv_bqtype) TYPE string,

      generate_missing_fields_in_mem
        IMPORTING it_missing_dsrc TYPE tt_dsrc_info
        CHANGING  ct_fld_db       TYPE STANDARD TABLE,

      rebuild_alv_models,

      apply_updates_to_db
        IMPORTING iv_single_dsrc TYPE clike OPTIONAL
        EXPORTING ev_upd_rows    TYPE i
                  ev_upd_tabs    TYPE i
                  ev_ins_rows    TYPE i
                  ev_error_msg   TYPE string,

      execute_mass_apply,

      prompt_single_table_apply
        IMPORTING iv_dsrc TYPE clike,

      show_table_detail_popup
        IMPORTING iv_dsrc TYPE clike,

      add_cell_color
        IMPORTING iv_fname TYPE lvc_fname OPTIONAL
                  iv_col   TYPE i
                  iv_int   TYPE i DEFAULT 0
        CHANGING  ct_color TYPE lvc_t_scol,

      set_col_text
        IMPORTING io_cols TYPE REF TO cl_salv_columns_table
                  iv_col  TYPE lvc_fname
                  iv_s    TYPE scrtext_s
                  iv_m    TYPE scrtext_m
                  iv_l    TYPE scrtext_l,

      build_alv_header
        RETURNING VALUE(ro_grid) TYPE REF TO cl_salv_form_layout_grid,

      display_summary_alv,

      display_detail_alv.
ENDCLASS.

CLASS lcl_bqtr_sync IMPLEMENTATION.

  METHOD any_to_str.
    rv_str = |{ iv_val }|.
    SHIFT rv_str RIGHT DELETING TRAILING space.
    SHIFT rv_str LEFT DELETING LEADING space.
  ENDMETHOD.

  METHOD show_progress.
    DATA lv_txt TYPE c LENGTH 100.
    lv_txt = iv_text.
    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING
        percentage = iv_pct
        text       = lv_txt.
  ENDMETHOD.

  METHOD table_exists.
    DATA lv_tab TYPE tabname.
    SELECT SINGLE tabname
      FROM dd02l
      WHERE tabname  = @iv_tabname
        AND as4local = 'A'
      INTO @lv_tab.
    rv_exists = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD get_dfies_merged.
    DATA: lt_en       TYPE ddfields,
          lt_sy       TYPE ddfields,
          lv_ddobj    TYPE ddobjname,
          lv_langu_en TYPE sy-langu VALUE 'E'.

    lv_ddobj = iv_tabname.

    CALL FUNCTION 'DDIF_FIELDINFO_GET'
      EXPORTING
        tabname        = lv_ddobj
        langu          = lv_langu_en
      TABLES
        dfies_tab      = lt_en
      EXCEPTIONS
        not_found      = 1
        internal_error = 2
        OTHERS         = 3.

    CALL FUNCTION 'DDIF_FIELDINFO_GET'
      EXPORTING
        tabname        = lv_ddobj
        langu          = sy-langu
      TABLES
        dfies_tab      = lt_sy
      EXCEPTIONS
        not_found      = 1
        internal_error = 2
        OTHERS         = 3.

    IF lt_en IS NOT INITIAL.
      rt_dfies = lt_en.
      LOOP AT rt_dfies ASSIGNING FIELD-SYMBOL(<fs_en>).
        IF <fs_en>-fieldtext IS INITIAL.
          READ TABLE lt_sy INTO DATA(ls_sy)
            WITH KEY fieldname = <fs_en>-fieldname.
          IF sy-subrc = 0.
            <fs_en>-fieldtext = ls_sy-fieldtext.
            <fs_en>-reptext   = ls_sy-reptext.
            <fs_en>-scrtext_s = ls_sy-scrtext_s.
            <fs_en>-scrtext_m = ls_sy-scrtext_m.
            <fs_en>-scrtext_l = ls_sy-scrtext_l.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ELSE.
      rt_dfies = lt_sy.
    ENDIF.

    SORT rt_dfies BY position ASCENDING.
  ENDMETHOD.

  METHOD meta_label_upper.
    rv_txt = to_upper(
      |{ is_dfies-fieldname } { is_dfies-rollname } { is_dfies-fieldtext } | &&
      |{ is_dfies-reptext } { is_dfies-scrtext_s } { is_dfies-scrtext_m } { is_dfies-scrtext_l }| ).
  ENDMETHOD.

  METHOD resolve_schema.
    CLEAR: es_schema, ev_error_msg.

    es_schema-tab_mastr = COND tabname(
      WHEN iv_tmst IS NOT INITIAL THEN iv_tmst ELSE '/GOOG/BQTR_MASTR' ).
    es_schema-tab_table = COND tabname(
      WHEN iv_ttab IS NOT INITIAL THEN iv_ttab ELSE '/GOOG/BQTR_TABLE' ).
    es_schema-tab_field = COND tabname(
      WHEN iv_tfld IS NOT INITIAL THEN iv_tfld ELSE '/GOOG/BQTR_FIELD' ).

    IF table_exists( es_schema-tab_table ) = abap_false.
      ev_error_msg = |No existe la tabla { es_schema-tab_table } en DD02L.|.
      RETURN.
    ENDIF.

    IF table_exists( es_schema-tab_field ) = abap_false.
      SELECT SINGLE tabname
        FROM dd02l
        WHERE tabname  LIKE '/GOOG/BQTR%F%'
          AND tabclass = 'TRANSP'
          AND as4local = 'A'
        INTO @DATA(lv_alt_fld).
      IF sy-subrc = 0 AND lv_alt_fld IS NOT INITIAL.
        es_schema-tab_field = lv_alt_fld.
      ELSE.
        ev_error_msg = |No existe la tabla de campos { es_schema-tab_field } en DD02L.|.
        RETURN.
      ENDIF.
    ENDIF.

    " 1. Inspeccionar /GOOG/BQTR_MASTR (opcional, para ayuda F4)
    IF table_exists( es_schema-tab_mastr ) = abap_true.
      DATA(lt_mst_df) = get_dfies_merged( es_schema-tab_mastr ).
      LOOP AT lt_mst_df INTO DATA(ls_mdf) WHERE datatype <> 'CLNT'.
        DATA(lv_mtxt) = meta_label_upper( ls_mdf ).
        IF ls_mdf-keyflag = 'X' AND es_schema-mst_trkey IS INITIAL.
          es_schema-mst_trkey = ls_mdf-fieldname.
        ELSEIF es_schema-mst_ckey IS INITIAL
               AND ( ls_mdf-fieldname CS 'KEY' OR lv_mtxt CS 'CLIENT KEY' OR lv_mtxt CS 'CLOUD KEY' ).
          es_schema-mst_ckey = ls_mdf-fieldname.
        ELSEIF es_schema-mst_dataset IS INITIAL
               AND ( ls_mdf-fieldname CS 'DATA' OR ls_mdf-fieldname CS 'DSET' OR lv_mtxt CS 'DATASET' ).
          es_schema-mst_dataset = ls_mdf-fieldname.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " 2. Inspeccionar /GOOG/BQTR_TABLE
    DATA(lt_tbl_df) = get_dfies_merged( es_schema-tab_table ).
    DATA: lv_tbl_trkey_roll TYPE rollname,
          lv_tbl_dsrc_roll  TYPE rollname.

    LOOP AT lt_tbl_df INTO DATA(ls_tdf) WHERE datatype <> 'CLNT'.
      DATA(lv_ttxt) = meta_label_upper( ls_tdf ).
      IF ls_tdf-keyflag = 'X'.
        IF es_schema-tbl_trkey IS INITIAL.
          es_schema-tbl_trkey = ls_tdf-fieldname.
          lv_tbl_trkey_roll   = ls_tdf-rollname.
        ELSEIF es_schema-tbl_dsrc IS INITIAL.
          es_schema-tbl_dsrc = ls_tdf-fieldname.
          lv_tbl_dsrc_roll  = ls_tdf-rollname.
        ENDIF.
      ELSEIF es_schema-tbl_exttab IS INITIAL
             AND ( ( ls_tdf-inttype = 'C' AND ls_tdf-leng >= 10 ) OR ls_tdf-inttype = 'g' ).
        IF ls_tdf-fieldname CS 'EXT'
           OR ls_tdf-fieldname CS 'TARGET'
           OR lv_ttxt CS 'EXT TABLE'
           OR lv_ttxt CS 'EXTERNAL TABLE'
           OR sy-tabix <= 5.
          es_schema-tbl_exttab = ls_tdf-fieldname.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF es_schema-tbl_trkey IS INITIAL OR es_schema-tbl_dsrc IS INITIAL.
      ev_error_msg =
        |No se pudieron identificar las claves (Transfer Key / Datasource) en { es_schema-tab_table }.|.
      RETURN.
    ENDIF.

    " 3. Inspeccionar /GOOG/BQTR_FIELD
    DATA(lt_fld_df) = get_dfies_merged( es_schema-tab_field ).

    " 3.a) Claves principales: MANDT, TR_KEY y DATASOURCE
    LOOP AT lt_fld_df INTO DATA(ls_fdf).
      IF ls_fdf-datatype = 'CLNT' AND es_schema-fld_mandt IS INITIAL.
        es_schema-fld_mandt = ls_fdf-fieldname.
        CONTINUE.
      ENDIF.
      IF ls_fdf-fieldname = es_schema-tbl_trkey
         OR ( lv_tbl_trkey_roll IS NOT INITIAL
              AND ls_fdf-rollname = lv_tbl_trkey_roll
              AND ls_fdf-keyflag  = 'X' ).
        IF es_schema-fld_trkey IS INITIAL.
          es_schema-fld_trkey = ls_fdf-fieldname.
          CONTINUE.
        ENDIF.
      ENDIF.
      IF ls_fdf-fieldname = es_schema-tbl_dsrc
         OR ( lv_tbl_dsrc_roll IS NOT INITIAL
              AND ls_fdf-rollname = lv_tbl_dsrc_roll
              AND ls_fdf-keyflag  = 'X' ).
        IF es_schema-fld_dsrc IS INITIAL.
          es_schema-fld_dsrc = ls_fdf-fieldname.
          CONTINUE.
        ENDIF.
      ENDIF.
    ENDLOOP.

    " Respaldo por orden de claves si los nombres difieren entre tablas
    LOOP AT lt_fld_df INTO ls_fdf WHERE datatype <> 'CLNT' AND keyflag = 'X'.
      IF es_schema-fld_trkey IS INITIAL AND ls_fdf-fieldname <> es_schema-fld_dsrc.
        es_schema-fld_trkey = ls_fdf-fieldname.
      ELSEIF es_schema-fld_dsrc IS INITIAL AND ls_fdf-fieldname <> es_schema-fld_trkey.
        es_schema-fld_dsrc = ls_fdf-fieldname.
      ENDIF.
    ENDLOOP.

    " 3.b) SAP Field Name (clave #3 o campo CHAR>=16 / STRING)
    LOOP AT lt_fld_df INTO ls_fdf
      WHERE datatype  <> 'CLNT'
        AND fieldname <> es_schema-fld_trkey
        AND fieldname <> es_schema-fld_dsrc.

      IF ls_fdf-keyflag = 'X'
         AND ( ls_fdf-inttype = 'N' OR ls_fdf-inttype = 'I' OR ls_fdf-fieldname CS 'POS' )
         AND es_schema-fld_pos IS INITIAL.
        es_schema-fld_pos = ls_fdf-fieldname.
        CONTINUE.
      ENDIF.

      IF ls_fdf-keyflag = 'X'
         AND ( ( ls_fdf-inttype = 'C' AND ls_fdf-leng >= 16 ) OR ls_fdf-inttype = 'g' )
         AND es_schema-fld_sapf IS INITIAL.
        es_schema-fld_sapf = ls_fdf-fieldname.
      ENDIF.
    ENDLOOP.

    " Si SAP_FIELD no era clave primaria, buscar en columnas no clave
    IF es_schema-fld_sapf IS INITIAL.
      LOOP AT lt_fld_df INTO ls_fdf
        WHERE datatype  <> 'CLNT'
          AND fieldname <> es_schema-fld_trkey
          AND fieldname <> es_schema-fld_dsrc
          AND ( ( inttype = 'C' AND leng >= 16 ) OR inttype = 'g' ).
        DATA(lv_sf_txt) = meta_label_upper( ls_fdf ).
        IF ls_fdf-fieldname = 'FIELDNAME'
           OR ls_fdf-fieldname = 'SAP_FIELD'
           OR ls_fdf-fieldname = 'SAP_FIELDNAME'
           OR ls_fdf-fieldname = 'FNAME'
           OR ls_fdf-rollname  = 'FIELDNAME'
           OR lv_sf_txt CS 'SAP FIELD'.
          es_schema-fld_sapf = ls_fdf-fieldname.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " 3.c) Clasificar el resto de columnas no clave de /GOOG/BQTR_FIELD
    DATA lt_rem_char_cols TYPE STANDARD TABLE OF fieldname WITH DEFAULT KEY.

    LOOP AT lt_fld_df INTO ls_fdf
      WHERE keyflag   <> 'X'
        AND datatype  <> 'CLNT'
        AND fieldname <> es_schema-fld_trkey
        AND fieldname <> es_schema-fld_dsrc
        AND fieldname <> es_schema-fld_sapf.

      DATA(lv_ftxt) = meta_label_upper( ls_fdf ).

      " Posición numérica (si existe como no-clave)
      IF es_schema-fld_pos IS INITIAL
         AND ( ls_fdf-inttype = 'N' OR ls_fdf-inttype = 'I' )
         AND ( ls_fdf-fieldname CS 'POS' OR lv_ftxt CS 'POSITION' ).
        es_schema-fld_pos = ls_fdf-fieldname.
        CONTINUE.
      ENDIF.

      " Fecha y hora de modificación
      IF ls_fdf-datatype = 'DATS' AND es_schema-fld_datum IS INITIAL.
        es_schema-fld_datum = ls_fdf-fieldname.
        CONTINUE.
      ENDIF.
      IF ls_fdf-datatype = 'TIMS' AND es_schema-fld_uzeit IS INITIAL.
        es_schema-fld_uzeit = ls_fdf-fieldname.
        CONTINUE.
      ENDIF.

      " Largo numérico (ej. LENG = 8, 10, 60)
      IF ( ls_fdf-inttype = 'N' OR ls_fdf-inttype = 'I' )
         AND es_schema-fld_leng IS INITIAL
         AND ( ls_fdf-fieldname CS 'LEN' OR lv_ftxt CS 'LENGTH' OR lv_ftxt CS 'LENG' ).
        es_schema-fld_leng = ls_fdf-fieldname.
        CONTINUE.
      ENDIF.

      " Usuario de modificación (UNAME / CHAR 12)
      IF es_schema-fld_uname IS INITIAL
         AND ls_fdf-datatype = 'CHAR'
         AND ls_fdf-leng     = 12
         AND ( ls_fdf-rollname = 'UNAME'
               OR ls_fdf-rollname = 'SYUNAME'
               OR ls_fdf-rollname = 'AENAM'
               OR ls_fdf-rollname = 'ERNAM'
               OR ls_fdf-rollname = 'USNAM'
               OR ls_fdf-fieldname CS 'USER'
               OR ls_fdf-fieldname CS 'UNAM'
               OR ls_fdf-fieldname CS 'NAM'
               OR lv_ftxt CS 'CHANGED BY'
               OR lv_ftxt CS 'CREATED BY'
               OR lv_ftxt CS 'USER NAME' ).
        es_schema-fld_uname = ls_fdf-fieldname.
        CONTINUE.
      ENDIF.

      " Flags CHAR(1) e INTTYPE CHAR(1) y DATATYPE SAP CHAR(4)
      IF ls_fdf-datatype = 'CHAR' AND ls_fdf-leng = 1.
        IF es_schema-fld_inttype IS INITIAL
           AND ( ls_fdf-rollname = 'INTTYPE' OR ls_fdf-fieldname CS 'INTTYPE' OR lv_ftxt CS 'INTERNAL TYPE' ).
          es_schema-fld_inttype = ls_fdf-fieldname.
        ELSEIF es_schema-fld_keyflg IS INITIAL
               AND ( ls_fdf-fieldname CS 'KEY' OR lv_ftxt CS 'KEY' ).
          es_schema-fld_keyflg = ls_fdf-fieldname.
        ELSEIF es_schema-fld_actflg IS INITIAL
               AND ( ls_fdf-fieldname CS 'ACT' OR ls_fdf-fieldname CS 'SEL' OR ls_fdf-fieldname CS 'TRFM' OR lv_ftxt CS 'ACTIVE' ).
          es_schema-fld_actflg = ls_fdf-fieldname.
        ENDIF.
        CONTINUE.
      ENDIF.

      IF ls_fdf-datatype = 'CHAR'
         AND ls_fdf-leng <= 5
         AND es_schema-fld_saptype IS INITIAL
         AND ( ls_fdf-rollname = 'DATATYPE_D' OR ls_fdf-fieldname CS 'DATATYPE' OR ls_fdf-fieldname CS 'DTYPE' ).
        es_schema-fld_saptype = ls_fdf-fieldname.
        CONTINUE.
      ENDIF.

      " Ignorar íconos (@GO@, @10@, etc. CHAR 4 / ICON_D)
      IF ls_fdf-rollname = 'ICON_D'
         OR ls_fdf-domname = 'ICON'
         OR ( ls_fdf-datatype = 'CHAR' AND ls_fdf-leng <= 5 ).
        CONTINUE.
      ENDIF.

      " Descripción del campo (Fecha válido de..., Nº dirección, Calle...)
      IF es_schema-fld_desc IS INITIAL
         AND ( ( ls_fdf-inttype = 'C' AND ls_fdf-leng >= 25 ) OR ls_fdf-inttype = 'g' )
         AND ( ls_fdf-fieldname CS 'DESC'
               OR ls_fdf-fieldname CS 'TEXT'
               OR ls_fdf-fieldname CS 'DDTEXT'
               OR ls_fdf-rollname  CS 'DESC'
               OR ls_fdf-rollname  CS 'TEXT'
               OR lv_ftxt CS 'DESCRIPTION'
               OR lv_ftxt CS 'DESCRIP' ).
        es_schema-fld_desc = ls_fdf-fieldname.
        CONTINUE.
      ENDIF.

      " Primero identificar Temp Field y Ext Field Name con criterios específicos de campo
      IF ( ls_fdf-inttype = 'C' AND ls_fdf-leng >= 15 ) OR ls_fdf-inttype = 'g'.
        IF es_schema-fld_tmpf IS INITIAL
           AND ( ls_fdf-fieldname CS 'TEMP'
                 OR ls_fdf-fieldname CS 'TMP'
                 OR lv_ftxt CS 'TEMP FIELD'
                 OR lv_ftxt CS 'TEMPORARY FIELD'
                 OR lv_ftxt CS 'TEMP. FIELD' ).
          es_schema-fld_tmpf = ls_fdf-fieldname.
          CONTINUE.
        ENDIF.

        IF es_schema-fld_extf IS INITIAL
           AND ( ls_fdf-fieldname = 'EXT_FIELD'
                 OR ls_fdf-fieldname = 'EXT_FNAME'
                 OR ls_fdf-fieldname = 'EXT_FIELDNAME'
                 OR ls_fdf-fieldname = 'TARGET_FIELD'
                 OR ( ls_fdf-fieldname CS 'EXT'
                      AND ( ls_fdf-fieldname CS 'FIELD'
                            OR ls_fdf-fieldname CS 'FLD'
                            OR ls_fdf-fieldname CS 'NAM' ) )
                 OR lv_ftxt CS 'EXTERNAL FIELD'
                 OR lv_ftxt CS 'EXT FIELD'
                 OR lv_ftxt CS 'EXT. FIELD'
                 OR lv_ftxt CS 'TARGET FIELD' ).
          es_schema-fld_extf = ls_fdf-fieldname.
          CONTINUE.
        ENDIF.
      ENDIF.

      " Tipo de dato externo BigQuery (DATE, STRING, INTEGER, NUMERIC...)
      IF es_schema-fld_bqtype IS INITIAL
         AND ( ( ls_fdf-inttype = 'C' AND ls_fdf-leng >= 6 AND ls_fdf-leng <= 45 ) OR ls_fdf-inttype = 'g' )
         AND ( ls_fdf-fieldname CS 'DTE'
               OR ls_fdf-fieldname CS 'DTEL'
               OR ls_fdf-fieldname CS 'ELEM'
               OR ls_fdf-fieldname CS 'BQ_TYPE'
               OR ls_fdf-fieldname CS 'EXT_TYPE'
               OR ls_fdf-fieldname CS 'EXT_DATA'
               OR lv_ftxt CS 'DATA ELEMENT'
               OR lv_ftxt CS 'DATA TYPE'
               OR lv_ftxt CS 'BQ TYPE' ).
        es_schema-fld_bqtype = ls_fdf-fieldname.
        CONTINUE.
      ENDIF.

      IF ( ls_fdf-inttype = 'C' AND ls_fdf-leng >= 15 ) OR ls_fdf-inttype = 'g'.
        APPEND ls_fdf-fieldname TO lt_rem_char_cols.
      ENDIF.
    ENDLOOP.

    " Respaldo posicional si alguna columna tenía nombre distinto al esperado
    IF es_schema-fld_extf IS INITIAL AND lines( lt_rem_char_cols ) >= 1.
      es_schema-fld_extf = lt_rem_char_cols[ 1 ].
      DELETE lt_rem_char_cols INDEX 1.
    ENDIF.
    IF es_schema-fld_tmpf IS INITIAL AND lines( lt_rem_char_cols ) >= 1.
      es_schema-fld_tmpf = lt_rem_char_cols[ 1 ].
    ENDIF.

    IF es_schema-fld_sapf IS INITIAL
       OR ( es_schema-fld_tmpf IS INITIAL AND es_schema-fld_extf IS INITIAL ).
      ev_error_msg =
        |No fue posible identificar SAP_FIELD o TEMP_FIELD/EXT_FIELD en { es_schema-tab_field }.|.
    ENDIF.
  ENDMETHOD.

  METHOD f4_transfer_key.
    " Se usan elementos de datos DDIC estándar para compatibilidad total con F4IF_INT_TABLE_VALUE_REQUEST
    TYPES:
      BEGIN OF ty_f4_tr,
        tr_key     TYPE dd02t-ddtext,
        client_key TYPE scrtext_l,
        dataset    TYPE dd02t-ddtext,
        num_tables TYPE int4,
      END OF ty_f4_tr.

    DATA: lt_f4       TYPE STANDARD TABLE OF ty_f4_tr,
          lt_ret      TYPE STANDARD TABLE OF ddshretval,
          ls_sch      TYPE ty_schema_map,
          lv_err      TYPE string,
          lv_retfield TYPE dfies-fieldname VALUE 'TR_KEY',
          lv_wtitle   TYPE c LENGTH 60 VALUE 'Seleccionar BigQuery Data Transfer',
          lr_mst      TYPE REF TO data,
          lr_tbl      TYPE REF TO data.

    FIELD-SYMBOLS: <lt_mst> TYPE STANDARD TABLE,
                   <lt_tbl> TYPE STANDARD TABLE,
                   <lv_mk>  TYPE any,
                   <lv_ck>  TYPE any,
                   <lv_ds>  TYPE any,
                   <lv_tk>  TYPE any.

    resolve_schema(
      EXPORTING iv_tmst      = p_tmst
                iv_ttab      = p_ttab
                iv_tfld      = p_tfld
      IMPORTING es_schema    = ls_sch
                ev_error_msg = lv_err ).

    IF ls_sch-tbl_trkey IS INITIAL.
      MESSAGE 'No se pudo inspeccionar /GOOG/BQTR_TABLE para ayuda F4.' TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    " Leer cabeceras de /GOOG/BQTR_MASTR si existe
    IF ls_sch-mst_trkey IS NOT INITIAL AND table_exists( ls_sch-tab_mastr ) = abap_true.
      CREATE DATA lr_mst TYPE STANDARD TABLE OF (ls_sch-tab_mastr).
      ASSIGN lr_mst->* TO <lt_mst>.
      SELECT * FROM (ls_sch-tab_mastr) INTO TABLE <lt_mst>.

      LOOP AT <lt_mst> ASSIGNING FIELD-SYMBOL(<ls_m>).
        UNASSIGN <lv_mk>.
        ASSIGN COMPONENT ls_sch-mst_trkey OF STRUCTURE <ls_m> TO <lv_mk>.
        IF sy-subrc <> 0 OR <lv_mk> IS NOT ASSIGNED.
          CONTINUE.
        ENDIF.
        DATA(lv_mk_str) = any_to_str( <lv_mk> ).
        IF lv_mk_str IS INITIAL.
          CONTINUE.
        ENDIF.

        DATA(ls_item) = VALUE ty_f4_tr( tr_key = CONV dd02t-ddtext( lv_mk_str ) ).
        IF ls_sch-mst_ckey IS NOT INITIAL.
          UNASSIGN <lv_ck>.
          ASSIGN COMPONENT ls_sch-mst_ckey OF STRUCTURE <ls_m> TO <lv_ck>.
          IF sy-subrc = 0 AND <lv_ck> IS ASSIGNED.
            ls_item-client_key = CONV scrtext_l( any_to_str( <lv_ck> ) ).
          ENDIF.
        ENDIF.
        IF ls_sch-mst_dataset IS NOT INITIAL.
          UNASSIGN <lv_ds>.
          ASSIGN COMPONENT ls_sch-mst_dataset OF STRUCTURE <ls_m> TO <lv_ds>.
          IF sy-subrc = 0 AND <lv_ds> IS ASSIGNED.
            ls_item-dataset = CONV dd02t-ddtext( any_to_str( <lv_ds> ) ).
          ENDIF.
        ENDIF.
        APPEND ls_item TO lt_f4.
      ENDLOOP.
    ENDIF.

    " Contar tablas por Mass Transfer Key en /GOOG/BQTR_TABLE
    CREATE DATA lr_tbl TYPE STANDARD TABLE OF (ls_sch-tab_table).
    ASSIGN lr_tbl->* TO <lt_tbl>.
    SELECT * FROM (ls_sch-tab_table) INTO TABLE <lt_tbl>.

    LOOP AT <lt_tbl> ASSIGNING FIELD-SYMBOL(<ls_t>).
      UNASSIGN <lv_tk>.
      ASSIGN COMPONENT ls_sch-tbl_trkey OF STRUCTURE <ls_t> TO <lv_tk>.
      IF sy-subrc <> 0 OR <lv_tk> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.
      DATA(lv_tk_str) = any_to_str( <lv_tk> ).
      IF lv_tk_str IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA(lv_tk_key) = CONV dd02t-ddtext( lv_tk_str ).
      READ TABLE lt_f4 ASSIGNING FIELD-SYMBOL(<fs_f4>)
        WITH KEY tr_key = lv_tk_key.
      IF sy-subrc = 0.
        <fs_f4>-num_tables = <fs_f4>-num_tables + 1.
      ELSE.
        APPEND VALUE ty_f4_tr( tr_key     = lv_tk_key
                               num_tables = 1 ) TO lt_f4.
      ENDIF.
    ENDLOOP.

    IF lt_f4 IS INITIAL.
      MESSAGE 'No existen Data Transfers registrados en /GOOG/BQTR_MASTR ni /GOOG/BQTR_TABLE.'
        TYPE 'I'.
      RETURN.
    ENDIF.

    SORT lt_f4 BY tr_key ASCENDING.

    CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
      EXPORTING
        retfield        = lv_retfield
        value_org       = 'S'
        window_title    = lv_wtitle
      TABLES
        value_tab       = lt_f4
        return_tab      = lt_ret
      EXCEPTIONS
        parameter_error = 1
        no_values_found = 2
        OTHERS          = 3.

    IF sy-subrc = 0 AND lt_ret IS NOT INITIAL.
      cv_trkey = lt_ret[ 1 ]-fieldval.
    ENDIF.
  ENDMETHOD.

  METHOD resolve_actual_trkey.
    DATA: lr_tbl   TYPE REF TO data,
          lv_in    TYPE string,
          lv_in_up TYPE string,
          lv_where TYPE string.

    FIELD-SYMBOLS: <lt_tbl> TYPE STANDARD TABLE,
                   <lv_k>   TYPE any.

    CLEAR: ev_real_key, ev_found.
    lv_in = any_to_str( iv_input_key ).
    IF lv_in IS INITIAL.
      RETURN.
    ENDIF.
    lv_in_up = to_upper( lv_in ).

    CREATE DATA lr_tbl TYPE STANDARD TABLE OF (gs_schema-tab_table).
    ASSIGN lr_tbl->* TO <lt_tbl>.

    " 1) Intento exacto
    lv_where = |{ gs_schema-tbl_trkey } = { cl_abap_dyn_prg=>quote( lv_in ) }|.
    SELECT * FROM (gs_schema-tab_table) INTO TABLE <lt_tbl> UP TO 1 ROWS WHERE (lv_where).
    IF <lt_tbl> IS NOT INITIAL.
      ev_real_key = lv_in.
      ev_found    = abap_true.
      RETURN.
    ENDIF.

    " 2) Intento en mayúsculas
    lv_where = |{ gs_schema-tbl_trkey } = { cl_abap_dyn_prg=>quote( lv_in_up ) }|.
    SELECT * FROM (gs_schema-tab_table) INTO TABLE <lt_tbl> UP TO 1 ROWS WHERE (lv_where).
    IF <lt_tbl> IS NOT INITIAL.
      ev_real_key = lv_in_up.
      ev_found    = abap_true.
      RETURN.
    ENDIF.

    " 3) Búsqueda case-insensitive sobre las entradas de /GOOG/BQTR_TABLE
    SELECT * FROM (gs_schema-tab_table) INTO TABLE <lt_tbl>.
    LOOP AT <lt_tbl> ASSIGNING FIELD-SYMBOL(<ls_r>).
      UNASSIGN <lv_k>.
      ASSIGN COMPONENT gs_schema-tbl_trkey OF STRUCTURE <ls_r> TO <lv_k>.
      IF sy-subrc = 0 AND <lv_k> IS ASSIGNED.
        DATA(lv_cand) = any_to_str( <lv_k> ).
        IF to_upper( lv_cand ) = lv_in_up.
          ev_real_key = lv_cand.
          ev_found    = abap_true.
          RETURN.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD format_tech_name.
    DATA: lv_raw TYPE string,
          lv_out TYPE string,
          lv_len TYPE i,
          lv_idx TYPE i,
          lv_ch  TYPE c LENGTH 1.

    lv_raw = any_to_str( iv_sap_field ).
    IF lv_raw IS INITIAL.
      RETURN.
    ENDIF.

    IF p_lower = abap_false.
      rv_tech = lv_raw.
      RETURN.
    ENDIF.

    lv_raw = to_lower( lv_raw ).

    " Si es un campo con namespace SAP (ej. /cwm/menge -> cwm_menge),
    " quitamos la primera '/' y reemplazamos las demás por '_'.
    " Si empieza originalmente con '_' (ej. _dataaging), se respeta '_dataaging'.
    IF lv_raw(1) = '/'.
      SHIFT lv_raw LEFT DELETING LEADING '/'.
    ENDIF.
    REPLACE ALL OCCURRENCES OF '/' IN lv_raw WITH '_'.

    " Sanitizar carácter por carácter según reglas de columna BigQuery [a-z0-9_]
    lv_len = strlen( lv_raw ).
    lv_idx = 0.
    WHILE lv_idx < lv_len.
      lv_ch = lv_raw+lv_idx(1).
      IF ( lv_ch >= 'a' AND lv_ch <= 'z' )
         OR ( lv_ch >= '0' AND lv_ch <= '9' )
         OR lv_ch = '_'.
        lv_out = lv_out && lv_ch.
      ELSE.
        lv_out = lv_out && '_'.
      ENDIF.
      lv_idx = lv_idx + 1.
    ENDWHILE.

    " En BigQuery una columna no puede comenzar con dígito [0-9]
    IF lv_out IS NOT INITIAL AND lv_out(1) >= '0' AND lv_out(1) <= '9'.
      lv_out = '_' && lv_out.
    ENDIF.

    rv_tech = lv_out.
  ENDMETHOD.

  METHOD get_source_dfies.
    DATA: lv_ddobj  TYPE ddobjname,
          lo_type   TYPE REF TO cl_abap_typedescr,
          lo_struct TYPE REF TO cl_abap_structdescr.

    lv_ddobj = CONV ddobjname( to_upper( any_to_str( iv_dsrc ) ) ).
    IF lv_ddobj IS INITIAL.
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_FIELDINFO_GET'
      EXPORTING
        tabname        = lv_ddobj
        langu          = sy-langu
      TABLES
        dfies_tab      = rt_dfies
      EXCEPTIONS
        not_found      = 1
        internal_error = 2
        OTHERS         = 3.

    IF rt_dfies IS INITIAL.
      cl_abap_typedescr=>describe_by_name(
        EXPORTING
          p_name         = lv_ddobj
        RECEIVING
          p_descr_ref    = lo_type
        EXCEPTIONS
          type_not_found = 1
          OTHERS         = 2 ).
      IF sy-subrc = 0 AND lo_type IS BOUND AND lo_type->kind = cl_abap_typedescr=>kind_struct.
        lo_struct ?= lo_type.
        lo_struct->get_ddic_field_list(
          EXPORTING
            p_langu      = sy-langu
          RECEIVING
            p_field_list = rt_dfies
          EXCEPTIONS
            no_ddic_type = 1
            not_found    = 2
            OTHERS       = 3 ).
      ENDIF.
    ENDIF.

    DELETE rt_dfies WHERE fieldname IS INITIAL OR fieldname(1) = '.'.
    SORT rt_dfies BY position ASCENDING.
  ENDMETHOD.

  METHOD map_default_bq_type.
    DATA(lv_dt) = to_upper( any_to_str( iv_datatype ) ).
    DATA(lv_it) = to_upper( any_to_str( iv_inttype ) ).

    READ TABLE it_tpl INTO DATA(ls_t1)
      WITH KEY datatype = lv_dt inttype = lv_it.
    IF sy-subrc = 0 AND ls_t1-bq_type IS NOT INITIAL.
      rv_bqtype = ls_t1-bq_type.
      RETURN.
    ENDIF.

    READ TABLE it_tpl INTO DATA(ls_t2)
      WITH KEY datatype = lv_dt.
    IF sy-subrc = 0 AND ls_t2-bq_type IS NOT INITIAL.
      rv_bqtype = ls_t2-bq_type.
      RETURN.
    ENDIF.

    CASE lv_dt.
      WHEN 'DATS' OR 'DATN'.
        rv_bqtype = 'DATE'.
      WHEN 'TIMS' OR 'TIMN'.
        rv_bqtype = 'TIME'.
      WHEN 'UTCLONG'.
        rv_bqtype = 'TIMESTAMP'.
      WHEN 'INT1' OR 'INT2' OR 'INT4' OR 'INT8'.
        rv_bqtype = 'INTEGER'.
      WHEN 'DEC' OR 'CURR' OR 'QUAN' OR 'DECFLOAT16' OR 'DF16_DEC' OR 'DF34_DEC'.
        rv_bqtype = 'NUMERIC'.
      WHEN 'FLTP'.
        rv_bqtype = 'FLOAT'.
      WHEN OTHERS.
        CASE lv_it.
          WHEN 'I' OR 'B' OR 'S' OR '8'.
            rv_bqtype = 'INTEGER'.
          WHEN 'P' OR 'A' OR 'E'.
            rv_bqtype = 'NUMERIC'.
          WHEN 'F'.
            rv_bqtype = 'FLOAT'.
          WHEN 'D'.
            rv_bqtype = 'DATE'.
          WHEN 'T'.
            rv_bqtype = 'TIME'.
          WHEN OTHERS.
            rv_bqtype = 'STRING'.
        ENDCASE.
    ENDCASE.
  ENDMETHOD.

  METHOD generate_missing_fields_in_mem.
    DATA: lt_tpl         TYPE tt_type_tpl,
          lr_extra_rows  TYPE REF TO data,
          lr_new_row     TYPE REF TO data,
          lv_ref_dsrc    TYPE string,
          lv_act_default TYPE c LENGTH 1 VALUE 'X'.

    FIELD-SYMBOLS: <lt_extras> TYPE STANDARD TABLE,
                   <ls_new>    TYPE any,
                   <lv_edsrc>  TYPE any,
                   <lv_esapf>  TYPE any,
                   <lv_edt>    TYPE any,
                   <lv_eit>    TYPE any,
                   <lv_ebq>    TYPE any,
                   <lv_eact>   TYPE any,
                   <lv_nmandt> TYPE any,
                   <lv_ntr>    TYPE any,
                   <lv_nds>    TYPE any,
                   <lv_nsf>    TYPE any,
                   <lv_npos>   TYPE any,
                   <lv_nkf>    TYPE any,
                   <lv_ndt>    TYPE any,
                   <lv_nln>    TYPE any,
                   <lv_nit>    TYPE any,
                   <lv_nbq>    TYPE any,
                   <lv_next>   TYPE any,
                   <lv_ndsc>   TYPE any,
                   <lv_nact>   TYPE any,
                   <lv_xds>    TYPE any,
                   <lv_xpos>   TYPE any.

    IF it_missing_dsrc IS INITIAL.
      RETURN.
    ENDIF.

    CREATE DATA lr_extra_rows TYPE STANDARD TABLE OF (gs_schema-tab_field).
    ASSIGN lr_extra_rows->* TO <lt_extras>.

    CREATE DATA lr_new_row TYPE (gs_schema-tab_field).
    ASSIGN lr_new_row->* TO <ls_new>.

    " Calibrar tipos BigQuery, flags y campos extra (recordstamp / operation_flag)
    " tomando como referencia cualquier tabla ya generada en el mismo Data Transfer
    LOOP AT ct_fld_db ASSIGNING FIELD-SYMBOL(<ls_existing>).
      UNASSIGN: <lv_edsrc>, <lv_esapf>.
      ASSIGN COMPONENT gs_schema-fld_dsrc OF STRUCTURE <ls_existing> TO <lv_edsrc>.
      ASSIGN COMPONENT gs_schema-fld_sapf OF STRUCTURE <ls_existing> TO <lv_esapf>.
      IF <lv_edsrc> IS NOT ASSIGNED OR <lv_esapf> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

      DATA(lv_cur_dsrc) = any_to_str( <lv_edsrc> ).
      DATA(lv_cur_sapf) = any_to_str( <lv_esapf> ).
      IF lv_ref_dsrc IS INITIAL AND lv_cur_dsrc IS NOT INITIAL.
        lv_ref_dsrc = lv_cur_dsrc.
      ENDIF.

      IF gs_schema-fld_saptype IS NOT INITIAL AND gs_schema-fld_bqtype IS NOT INITIAL.
        UNASSIGN: <lv_edt>, <lv_eit>, <lv_ebq>.
        ASSIGN COMPONENT gs_schema-fld_saptype OF STRUCTURE <ls_existing> TO <lv_edt>.
        ASSIGN COMPONENT gs_schema-fld_bqtype  OF STRUCTURE <ls_existing> TO <lv_ebq>.
        IF gs_schema-fld_inttype IS NOT INITIAL.
          ASSIGN COMPONENT gs_schema-fld_inttype OF STRUCTURE <ls_existing> TO <lv_eit>.
        ENDIF.
        IF <lv_edt> IS ASSIGNED AND <lv_ebq> IS ASSIGNED.
          DATA(lv_t_dt) = to_upper( any_to_str( <lv_edt> ) ).
          DATA(lv_t_bq) = any_to_str( <lv_ebq> ).
          DATA(lv_t_it) = COND string(
            WHEN <lv_eit> IS ASSIGNED THEN to_upper( any_to_str( <lv_eit> ) ) ELSE '' ).
          IF lv_t_dt IS NOT INITIAL AND lv_t_bq IS NOT INITIAL.
            READ TABLE lt_tpl TRANSPORTING NO FIELDS
              WITH KEY datatype = lv_t_dt inttype = lv_t_it.
            IF sy-subrc <> 0.
              APPEND VALUE ty_type_tpl( datatype = lv_t_dt
                                        inttype  = lv_t_it
                                        bq_type  = lv_t_bq ) TO lt_tpl.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.

      IF gs_schema-fld_actflg IS NOT INITIAL.
        UNASSIGN <lv_eact>.
        ASSIGN COMPONENT gs_schema-fld_actflg OF STRUCTURE <ls_existing> TO <lv_eact>.
        IF sy-subrc = 0 AND <lv_eact> IS ASSIGNED AND <lv_eact> IS NOT INITIAL.
          lv_act_default = <lv_eact>.
        ENDIF.
      ENDIF.

      " Capturar campos extra (ej. recordstamp / operation_flag) de la 1ª tabla de referencia
      IF lv_cur_dsrc = lv_ref_dsrc.
        DATA(lv_low_sapf) = to_lower( lv_cur_sapf ).
        IF lv_cur_sapf IS INITIAL
           OR lv_low_sapf = 'recordstamp'
           OR lv_low_sapf = 'operation_flag'
           OR lv_low_sapf = 'is_deleted'.
          APPEND <ls_existing> TO <lt_extras>.
        ENDIF.
      ENDIF.
    ENDLOOP.

    " Generar filas en memoria para cada Datasource sin campos
    LOOP AT it_missing_dsrc INTO DATA(ls_miss).
      DATA(lt_src_df) = get_source_dfies( ls_miss-datasource ).
      IF lt_src_df IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA(lv_pos_num) = 0.
      LOOP AT lt_src_df INTO DATA(ls_sdf).
        CLEAR <ls_new>.
        lv_pos_num = lv_pos_num + 1.

        IF gs_schema-fld_mandt IS NOT INITIAL.
          UNASSIGN <lv_nmandt>.
          ASSIGN COMPONENT gs_schema-fld_mandt OF STRUCTURE <ls_new> TO <lv_nmandt>.
          IF <lv_nmandt> IS ASSIGNED. <lv_nmandt> = sy-mandt. ENDIF.
        ENDIF.

        UNASSIGN: <lv_ntr>, <lv_nds>, <lv_nsf>.
        ASSIGN COMPONENT gs_schema-fld_trkey OF STRUCTURE <ls_new> TO <lv_ntr>.
        ASSIGN COMPONENT gs_schema-fld_dsrc  OF STRUCTURE <ls_new> TO <lv_nds>.
        ASSIGN COMPONENT gs_schema-fld_sapf  OF STRUCTURE <ls_new> TO <lv_nsf>.
        IF <lv_ntr> IS ASSIGNED. <lv_ntr> = gv_real_trkey. ENDIF.
        IF <lv_nds> IS ASSIGNED. <lv_nds> = ls_miss-datasource. ENDIF.
        IF <lv_nsf> IS ASSIGNED. <lv_nsf> = ls_sdf-fieldname. ENDIF.

        IF gs_schema-fld_pos IS NOT INITIAL.
          UNASSIGN <lv_npos>.
          ASSIGN COMPONENT gs_schema-fld_pos OF STRUCTURE <ls_new> TO <lv_npos>.
          IF <lv_npos> IS ASSIGNED. <lv_npos> = lv_pos_num. ENDIF.
        ENDIF.

        IF gs_schema-fld_keyflg IS NOT INITIAL.
          UNASSIGN <lv_nkf>.
          ASSIGN COMPONENT gs_schema-fld_keyflg OF STRUCTURE <ls_new> TO <lv_nkf>.
          IF <lv_nkf> IS ASSIGNED. <lv_nkf> = ls_sdf-keyflag. ENDIF.
        ENDIF.

        IF gs_schema-fld_saptype IS NOT INITIAL.
          UNASSIGN <lv_ndt>.
          ASSIGN COMPONENT gs_schema-fld_saptype OF STRUCTURE <ls_new> TO <lv_ndt>.
          IF <lv_ndt> IS ASSIGNED. <lv_ndt> = ls_sdf-datatype. ENDIF.
        ENDIF.

        IF gs_schema-fld_leng IS NOT INITIAL.
          UNASSIGN <lv_nln>.
          ASSIGN COMPONENT gs_schema-fld_leng OF STRUCTURE <ls_new> TO <lv_nln>.
          IF <lv_nln> IS ASSIGNED. <lv_nln> = ls_sdf-leng. ENDIF.
        ENDIF.

        IF gs_schema-fld_inttype IS NOT INITIAL.
          UNASSIGN <lv_nit>.
          ASSIGN COMPONENT gs_schema-fld_inttype OF STRUCTURE <ls_new> TO <lv_nit>.
          IF <lv_nit> IS ASSIGNED. <lv_nit> = ls_sdf-inttype. ENDIF.
        ENDIF.

        IF gs_schema-fld_bqtype IS NOT INITIAL.
          UNASSIGN <lv_nbq>.
          ASSIGN COMPONENT gs_schema-fld_bqtype OF STRUCTURE <ls_new> TO <lv_nbq>.
          IF <lv_nbq> IS ASSIGNED.
            <lv_nbq> = map_default_bq_type( iv_datatype = ls_sdf-datatype
                                            iv_inttype  = ls_sdf-inttype
                                            it_tpl      = lt_tpl ).
          ENDIF.
        ENDIF.

        " Marca temporal corta '(NUEVO)' para identificar inserción pendiente en simulación
        IF gs_schema-fld_extf IS NOT INITIAL.
          UNASSIGN <lv_next>.
          ASSIGN COMPONENT gs_schema-fld_extf OF STRUCTURE <ls_new> TO <lv_next>.
          IF <lv_next> IS ASSIGNED. <lv_next> = '(NUEVO)'. ENDIF.
        ENDIF.

        IF gs_schema-fld_desc IS NOT INITIAL.
          UNASSIGN <lv_ndsc>.
          ASSIGN COMPONENT gs_schema-fld_desc OF STRUCTURE <ls_new> TO <lv_ndsc>.
          IF <lv_ndsc> IS ASSIGNED. <lv_ndsc> = ls_sdf-fieldtext. ENDIF.
        ENDIF.

        IF gs_schema-fld_actflg IS NOT INITIAL.
          UNASSIGN <lv_nact>.
          ASSIGN COMPONENT gs_schema-fld_actflg OF STRUCTURE <ls_new> TO <lv_nact>.
          IF <lv_nact> IS ASSIGNED. <lv_nact> = lv_act_default. ENDIF.
        ENDIF.

        APPEND <ls_new> TO ct_fld_db.
      ENDLOOP.

      " Replicar también filas extra (recordstamp / operation_flag) si existían en la plantilla
      LOOP AT <lt_extras> ASSIGNING FIELD-SYMBOL(<ls_ext_tpl>).
        <ls_new> = <ls_ext_tpl>.
        lv_pos_num = lv_pos_num + 1.
        UNASSIGN <lv_xds>.
        ASSIGN COMPONENT gs_schema-fld_dsrc OF STRUCTURE <ls_new> TO <lv_xds>.
        IF <lv_xds> IS ASSIGNED. <lv_xds> = ls_miss-datasource. ENDIF.
        IF gs_schema-fld_pos IS NOT INITIAL.
          UNASSIGN <lv_xpos>.
          ASSIGN COMPONENT gs_schema-fld_pos OF STRUCTURE <ls_new> TO <lv_xpos>.
          IF <lv_xpos> IS ASSIGNED. <lv_xpos> = lv_pos_num. ENDIF.
        ENDIF.
        APPEND <ls_new> TO ct_fld_db.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD load_transfer_data.
    DATA: lr_tbl_db   TYPE REF TO data,
          lv_where_tb TYPE string,
          lv_where_fl TYPE string,
          lt_missing  TYPE tt_dsrc_info,
          lv_found    TYPE abap_bool.

    FIELD-SYMBOLS: <lt_tbl_db> TYPE STANDARD TABLE,
                   <lt_fld_db> TYPE STANDARD TABLE,
                   <lv_ds>     TYPE any,
                   <lv_et>     TYPE any,
                   <lv_fd>     TYPE any.

    CLEAR: ev_error_msg, gt_dsrc_list, gt_summary, gt_detail, gt_detail_vw.

    resolve_actual_trkey(
      EXPORTING iv_input_key = p_trkey
      IMPORTING ev_real_key  = gv_real_trkey
                ev_found     = lv_found ).

    IF lv_found = abap_false.
      ev_error_msg =
        |No se encontró el Data Transfer "{ p_trkey }" en { gs_schema-tab_table }. Use F4 en P_TRKEY.|.
      RETURN.
    ENDIF.

    " 1. Leer todas las tablas configuradas para este Data Transfer en /GOOG/BQTR_TABLE
    CREATE DATA lr_tbl_db TYPE STANDARD TABLE OF (gs_schema-tab_table).
    ASSIGN lr_tbl_db->* TO <lt_tbl_db>.

    lv_where_tb = |{ gs_schema-tbl_trkey } = { cl_abap_dyn_prg=>quote( gv_real_trkey ) }|.
    SELECT * FROM (gs_schema-tab_table) INTO TABLE <lt_tbl_db> WHERE (lv_where_tb).

    LOOP AT <lt_tbl_db> ASSIGNING FIELD-SYMBOL(<ls_t>).
      UNASSIGN <lv_ds>.
      ASSIGN COMPONENT gs_schema-tbl_dsrc OF STRUCTURE <ls_t> TO <lv_ds>.
      IF sy-subrc <> 0 OR <lv_ds> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

      DATA(lv_dsrc_str) = any_to_str( <lv_ds> ).
      IF lv_dsrc_str IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA(lv_dsrc_chk) = CONV ty_dsrc_name( to_upper( lv_dsrc_str ) ).
      IF s_dsrc[] IS NOT INITIAL AND NOT ( lv_dsrc_chk IN s_dsrc ).
        CONTINUE.
      ENDIF.

      DATA(lv_ext_tab) = VALUE string( ).
      IF gs_schema-tbl_exttab IS NOT INITIAL.
        UNASSIGN <lv_et>.
        ASSIGN COMPONENT gs_schema-tbl_exttab OF STRUCTURE <ls_t> TO <lv_et>.
        IF sy-subrc = 0 AND <lv_et> IS ASSIGNED.
          lv_ext_tab = any_to_str( <lv_et> ).
        ENDIF.
      ENDIF.

      APPEND VALUE ty_dsrc_info(
        datasource = CONV ty_dsrc_name( lv_dsrc_str )
        ext_table  = CONV ty_ext_tname( lv_ext_tab ) ) TO gt_dsrc_list.
    ENDLOOP.

    SORT gt_dsrc_list BY datasource ASCENDING.
    DELETE ADJACENT DUPLICATES FROM gt_dsrc_list COMPARING datasource.

    IF gt_dsrc_list IS INITIAL.
      ev_error_msg =
        |El Data Transfer "{ gv_real_trkey }" no tiene fuentes que coincidan con el filtro S_DSRC.|.
      RETURN.
    ENDIF.

    " 2. Leer todos los registros de /GOOG/BQTR_FIELD para este Data Transfer
    CREATE DATA gr_fld_db_all TYPE STANDARD TABLE OF (gs_schema-tab_field).
    ASSIGN gr_fld_db_all->* TO <lt_fld_db>.

    lv_where_fl = |{ gs_schema-fld_trkey } = { cl_abap_dyn_prg=>quote( gv_real_trkey ) }|.
    SELECT * FROM (gs_schema-tab_field) INTO TABLE <lt_fld_db> WHERE (lv_where_fl).

    " 3. Si el usuario marcó P_GEN, detectar tablas con 0 filas en /GOOG/BQTR_FIELD
    IF p_gen = abap_true.
      LOOP AT gt_dsrc_list INTO DATA(ls_ds_chk).
        DATA(lv_has_any) = abap_false.
        LOOP AT <lt_fld_db> ASSIGNING FIELD-SYMBOL(<ls_fchk>).
          UNASSIGN <lv_fd>.
          ASSIGN COMPONENT gs_schema-fld_dsrc OF STRUCTURE <ls_fchk> TO <lv_fd>.
          IF sy-subrc = 0 AND <lv_fd> IS ASSIGNED.
            IF to_upper( any_to_str( <lv_fd> ) ) = to_upper( any_to_str( ls_ds_chk-datasource ) ).
              lv_has_any = abap_true.
              EXIT.
            ENDIF.
          ENDIF.
        ENDLOOP.
        IF lv_has_any = abap_false.
          APPEND ls_ds_chk TO lt_missing.
        ENDIF.
      ENDLOOP.

      IF lt_missing IS NOT INITIAL.
        generate_missing_fields_in_mem(
          EXPORTING it_missing_dsrc = lt_missing
          CHANGING  ct_fld_db       = <lt_fld_db> ).
      ENDIF.
    ENDIF.

    " 4. Construir modelos de Resumen y Detalle ALV
    rebuild_alv_models( ).
  ENDMETHOD.

  METHOD rebuild_alv_models.
    TYPES:
      BEGIN OF ty_used_name,
        dsrc_up  TYPE string,
        tech_nam TYPE string,
      END OF ty_used_name.

    DATA: lt_used TYPE HASHED TABLE OF ty_used_name WITH UNIQUE KEY dsrc_up tech_nam.

    FIELD-SYMBOLS: <lt_fld_db> TYPE STANDARD TABLE,
                   <lv_dsrc>   TYPE any,
                   <lv_sapf>   TYPE any,
                   <lv_kf>     TYPE any,
                   <lv_st>     TYPE any,
                   <lv_bt>     TYPE any,
                   <lv_dc>     TYPE any,
                   <lv_tf>     TYPE any,
                   <lv_ef>     TYPE any.

    CLEAR: gt_summary, gt_detail, gt_detail_vw.
    IF gr_fld_db_all IS NOT BOUND.
      RETURN.
    ENDIF.
    ASSIGN gr_fld_db_all->* TO <lt_fld_db>.

    LOOP AT <lt_fld_db> ASSIGNING FIELD-SYMBOL(<ls_f>).
      UNASSIGN <lv_dsrc>.
      ASSIGN COMPONENT gs_schema-fld_dsrc OF STRUCTURE <ls_f> TO <lv_dsrc>.
      IF sy-subrc <> 0 OR <lv_dsrc> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.
      DATA(lv_dsrc_str) = any_to_str( <lv_dsrc> ).
      DATA(lv_dsrc_up)  = to_upper( lv_dsrc_str ).

      " Verificar que pertenezca a nuestra lista filtrada de /GOOG/BQTR_TABLE
      DATA(lv_ext_tab)  = VALUE ty_ext_tname( ).
      DATA(lv_dsrc_key) = VALUE ty_dsrc_name( ).
      DATA(lv_in_list)  = abap_false.

      LOOP AT gt_dsrc_list INTO DATA(ls_dl).
        IF to_upper( any_to_str( ls_dl-datasource ) ) = lv_dsrc_up.
          lv_in_list  = abap_true.
          lv_dsrc_key = ls_dl-datasource.
          lv_ext_tab  = ls_dl-ext_table.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF lv_in_list = abap_false.
        CONTINUE.
      ENDIF.

      DATA(ls_det) = VALUE ty_detail(
        datasource = lv_dsrc_key
        ext_table  = lv_ext_tab ).

      " SAP Field Name
      UNASSIGN <lv_sapf>.
      ASSIGN COMPONENT gs_schema-fld_sapf OF STRUCTURE <ls_f> TO <lv_sapf>.
      DATA(lv_sapf_str) = COND string(
        WHEN <lv_sapf> IS ASSIGNED THEN any_to_str( <lv_sapf> ) ELSE '' ).
      ls_det-sap_field = lv_sapf_str.

      " Metadatos informativos (Clave, Tipo SAP, Tipo BQ, Descripción)
      IF gs_schema-fld_keyflg IS NOT INITIAL.
        UNASSIGN <lv_kf>.
        ASSIGN COMPONENT gs_schema-fld_keyflg OF STRUCTURE <ls_f> TO <lv_kf>.
        IF <lv_kf> IS ASSIGNED
           AND any_to_str( <lv_kf> ) IS NOT INITIAL
           AND any_to_str( <lv_kf> ) <> '0'.
          ls_det-is_key = 'SI'.
        ENDIF.
      ENDIF.

      IF gs_schema-fld_saptype IS NOT INITIAL.
        UNASSIGN <lv_st>.
        ASSIGN COMPONENT gs_schema-fld_saptype OF STRUCTURE <ls_f> TO <lv_st>.
        IF <lv_st> IS ASSIGNED.
          ls_det-sap_type = any_to_str( <lv_st> ).
        ENDIF.
      ENDIF.

      IF gs_schema-fld_bqtype IS NOT INITIAL.
        UNASSIGN <lv_bt>.
        ASSIGN COMPONENT gs_schema-fld_bqtype OF STRUCTURE <ls_f> TO <lv_bt>.
        IF <lv_bt> IS ASSIGNED.
          ls_det-bq_type = any_to_str( <lv_bt> ).
        ENDIF.
      ENDIF.

      IF gs_schema-fld_desc IS NOT INITIAL.
        UNASSIGN <lv_dc>.
        ASSIGN COMPONENT gs_schema-fld_desc OF STRUCTURE <ls_f> TO <lv_dc>.
        IF <lv_dc> IS ASSIGNED.
          ls_det-description = any_to_str( <lv_dc> ).
        ENDIF.
      ENDIF.

      " Valores actuales en Temp Field y Ext Field
      DATA(lv_cur_tmp) = VALUE string( ).
      DATA(lv_cur_ext) = VALUE string( ).

      IF gs_schema-fld_tmpf IS NOT INITIAL.
        UNASSIGN <lv_tf>.
        ASSIGN COMPONENT gs_schema-fld_tmpf OF STRUCTURE <ls_f> TO <lv_tf>.
        IF <lv_tf> IS ASSIGNED.
          lv_cur_tmp = any_to_str( <lv_tf> ).
        ENDIF.
      ENDIF.

      IF gs_schema-fld_extf IS NOT INITIAL.
        UNASSIGN <lv_ef>.
        ASSIGN COMPONENT gs_schema-fld_extf OF STRUCTURE <ls_f> TO <lv_ef>.
        IF <lv_ef> IS ASSIGNED.
          lv_cur_ext = any_to_str( <lv_ef> ).
        ENDIF.
      ENDIF.

      ls_det-curr_tmpf = lv_cur_tmp.
      ls_det-curr_extf = lv_cur_ext.

      " ¿Es un campo extra del SDK sin SAP_FIELD (ej. recordstamp / operation_flag)?
      DATA(lv_low_sap) = to_lower( lv_sapf_str ).
      DATA(lv_low_ext) = to_lower( lv_cur_ext ).
      IF lv_sapf_str IS INITIAL
         OR ( ( lv_low_ext = 'recordstamp' OR lv_low_ext = 'operation_flag' )
              AND lv_low_sap = lv_low_ext ).
        ls_det-new_tech = COND string( WHEN lv_cur_ext IS NOT INITIAL THEN lv_cur_ext ELSE lv_cur_tmp ).
        ls_det-estado   = 'CAMPO EXTRA (OK)'.
        ls_det-nota     = 'Campo técnico de control BigQuery Toolkit (se respeta intacto)'.
        add_cell_color( EXPORTING iv_fname = 'ESTADO' iv_col = 5 iv_int = 0
                        CHANGING  ct_color = ls_det-t_color ).
        APPEND ls_det TO gt_detail.
        CONTINUE.
      ENDIF.

      " Calcular el nombre técnico destino para BigQuery
      DATA(lv_new_tech) = format_tech_name( lv_sapf_str ).

      " Evitar colisión de nombres duplicados dentro de la misma tabla
      DATA(lv_base_tech) = lv_new_tech.
      DATA(lv_dup_idx)   = 1.
      WHILE line_exists( lt_used[ dsrc_up = lv_dsrc_up tech_nam = lv_new_tech ] ).
        lv_dup_idx  = lv_dup_idx + 1.
        lv_new_tech = |{ lv_base_tech }_{ lv_dup_idx }|.
      ENDWHILE.
      INSERT VALUE ty_used_name( dsrc_up = lv_dsrc_up tech_nam = lv_new_tech ) INTO TABLE lt_used.

      ls_det-new_tech = lv_new_tech.

      " Determinar si requiere actualización
      DATA(lv_need_upd) = abap_false.
      IF lv_cur_ext = '(NUEVO)'.
        lv_need_upd = abap_true.
      ENDIF.
      IF p_tmpf = abap_true AND gs_schema-fld_tmpf IS NOT INITIAL AND lv_cur_tmp <> lv_new_tech.
        lv_need_upd = abap_true.
      ENDIF.
      IF p_extf = abap_true AND gs_schema-fld_extf IS NOT INITIAL AND lv_cur_ext <> lv_new_tech.
        lv_need_upd = abap_true.
      ENDIF.

      IF lv_need_upd = abap_true.
        ls_det-estado = 'PENDIENTE ACTUALIZAR'.
        DATA(lv_old_ref) = COND string(
          WHEN lv_cur_ext IS NOT INITIAL THEN lv_cur_ext
          WHEN lv_cur_tmp IS NOT INITIAL THEN lv_cur_tmp
          ELSE '(vacío)' ).
        ls_det-nota = |Cambiará: { lv_old_ref } -> { lv_new_tech }|.
        add_cell_color( EXPORTING iv_fname = 'ESTADO'   iv_col = 3 iv_int = 1
                        CHANGING  ct_color = ls_det-t_color ).
        add_cell_color( EXPORTING iv_fname = 'NEW_TECH' iv_col = 5 iv_int = 0
                        CHANGING  ct_color = ls_det-t_color ).
      ELSE.
        ls_det-estado = 'YA TÉCNICO (OK)'.
        ls_det-nota   = 'Ya tiene el nombre técnico asignado'.
        add_cell_color( EXPORTING iv_fname = 'ESTADO' iv_col = 5 iv_int = 0
                        CHANGING  ct_color = ls_det-t_color ).
      ENDIF.

      APPEND ls_det TO gt_detail.
    ENDLOOP.

    " Construir Vista Resumen (1 fila por cada Datasource de /GOOG/BQTR_TABLE)
    LOOP AT gt_dsrc_list INTO DATA(ls_dsrc).
      DATA(ls_sum) = VALUE ty_summary(
        datasource = ls_dsrc-datasource
        ext_table  = ls_dsrc-ext_table ).

      DATA(lv_samples) = VALUE string( ).
      DATA(lv_smp_cnt) = 0.

      LOOP AT gt_detail INTO DATA(ls_d)
        WHERE datasource = ls_dsrc-datasource.
        ls_sum-total_flds = ls_sum-total_flds + 1.
        IF ls_d-estado = 'CAMPO EXTRA (OK)'.
          ls_sum-extra_flds = ls_sum-extra_flds + 1.
        ELSEIF ls_d-estado = 'PENDIENTE ACTUALIZAR'.
          ls_sum-pend_flds = ls_sum-pend_flds + 1.
          IF lv_smp_cnt < 3.
            lv_smp_cnt = lv_smp_cnt + 1.
            DATA(lv_prev) = COND string(
              WHEN ls_d-curr_extf IS NOT INITIAL THEN any_to_str( ls_d-curr_extf )
              WHEN ls_d-curr_tmpf IS NOT INITIAL THEN any_to_str( ls_d-curr_tmpf )
              ELSE '""' ).
            DATA(lv_nt)   = any_to_str( ls_d-new_tech ).
            DATA(lv_pair) = |{ lv_prev }->{ lv_nt }|.
            lv_samples = COND string(
              WHEN lv_samples IS INITIAL THEN lv_pair
              ELSE |{ lv_samples }, { lv_pair }| ).
          ENDIF.
        ELSE.
          ls_sum-ok_flds = ls_sum-ok_flds + 1.
        ENDIF.
      ENDLOOP.

      IF ls_sum-total_flds = 0.
        ls_sum-estado      = 'SIN CAMPOS (0 FILAS)'.
        ls_sum-ejemplo_chg = 'No existen filas en /GOOG/BQTR_FIELD para esta vista'.
        ls_sum-accion      = 'Abra Display Field (@10@) o marque "Generar filas de CDS"'.
        add_cell_color( EXPORTING iv_fname = 'ESTADO' iv_col = 7 iv_int = 1
                        CHANGING  ct_color = ls_sum-t_color ).
        add_cell_color( EXPORTING iv_fname = 'ACCION' iv_col = 7 iv_int = 0
                        CHANGING  ct_color = ls_sum-t_color ).
      ELSEIF ls_sum-pend_flds > 0.
        ls_sum-estado      = 'PENDIENTE ACTUALIZAR'.
        ls_sum-ejemplo_chg = lv_samples.
        DATA(lv_ds_lbl)    = any_to_str( ls_dsrc-datasource ).
        ls_sum-accion      =
          |Doble clic aquí para actualizar solo { lv_ds_lbl } ({ ls_sum-pend_flds } cols)|.
        add_cell_color( EXPORTING iv_fname = 'ESTADO'    iv_col = 3 iv_int = 1
                        CHANGING  ct_color = ls_sum-t_color ).
        add_cell_color( EXPORTING iv_fname = 'PEND_FLDS' iv_col = 3 iv_int = 0
                        CHANGING  ct_color = ls_sum-t_color ).
        add_cell_color( EXPORTING iv_fname = 'ACCION'    iv_col = 3 iv_int = 0
                        CHANGING  ct_color = ls_sum-t_color ).
      ELSE.
        ls_sum-estado      = 'YA TÉCNICO (OK)'.
        ls_sum-ejemplo_chg = 'Todas las columnas ya tienen el nombre técnico SAP'.
        ls_sum-accion      = 'OK - Sin cambios pendientes'.
        add_cell_color( EXPORTING iv_fname = 'ESTADO' iv_col = 5 iv_int = 1
                        CHANGING  ct_color = ls_sum-t_color ).
        add_cell_color( EXPORTING iv_fname = 'ACCION' iv_col = 5 iv_int = 0
                        CHANGING  ct_color = ls_sum-t_color ).
      ENDIF.

      APPEND ls_sum TO gt_summary.
    ENDLOOP.

    " Filtrar vista detallada si el usuario pidió ver solo pendientes
    IF p_onlyc = abap_true.
      LOOP AT gt_detail INTO DATA(ls_only)
        WHERE estado = 'PENDIENTE ACTUALIZAR'.
        APPEND ls_only TO gt_detail_vw.
      ENDLOOP.
    ELSE.
      gt_detail_vw = gt_detail.
    ENDIF.
  ENDMETHOD.

  METHOD apply_updates_to_db.
    TYPES:
      BEGIN OF ty_used_name,
        dsrc_up  TYPE string,
        tech_nam TYPE string,
      END OF ty_used_name,
      BEGIN OF ty_touched_tab,
        dsrc_up TYPE string,
      END OF ty_touched_tab.

    DATA: lr_upd_tab  TYPE REF TO data,
          lt_used     TYPE HASHED TABLE OF ty_used_name WITH UNIQUE KEY dsrc_up tech_nam,
          lt_touched  TYPE HASHED TABLE OF ty_touched_tab WITH UNIQUE KEY dsrc_up,
          lv_lock_tab TYPE rstable-tabname,
          lv_filt_up  TYPE string.

    FIELD-SYMBOLS: <lt_fld_db> TYPE STANDARD TABLE,
                   <lt_upd_db> TYPE STANDARD TABLE,
                   <lv_dsrc>   TYPE any,
                   <lv_sapf>   TYPE any,
                   <lv_tmpf>   TYPE any,
                   <lv_extf>   TYPE any,
                   <lv_un>     TYPE any,
                   <lv_dt>     TYPE any,
                   <lv_uz>     TYPE any.

    CLEAR: ev_upd_rows, ev_upd_tabs, ev_ins_rows, ev_error_msg.
    IF gr_fld_db_all IS NOT BOUND.
      ev_error_msg = 'No hay datos cargados en memoria.'.
      RETURN.
    ENDIF.

    IF p_tmpf = abap_false AND p_extf = abap_false.
      ev_error_msg = 'Debe marcar al menos "Actualizar Temp Field" o "Actualizar Ext Field".'.
      RETURN.
    ENDIF.

    lv_filt_up = to_upper( any_to_str( iv_single_dsrc ) ).

    ASSIGN gr_fld_db_all->* TO <lt_fld_db>.
    CREATE DATA lr_upd_tab TYPE STANDARD TABLE OF (gs_schema-tab_field).
    ASSIGN lr_upd_tab->* TO <lt_upd_db>.

    " Bloquear tabla /GOOG/BQTR_FIELD para evitar colisión si /GOOG/BQTR_SETTINGS sigue abierta
    lv_lock_tab = gs_schema-tab_field.
    CALL FUNCTION 'ENQUEUE_E_TABLE'
      EXPORTING
        mode_rstable   = 'E'
        tabname        = lv_lock_tab
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.

    IF sy-subrc = 1.
      ev_error_msg =
        |La tabla { gs_schema-tab_field } está bloqueada ({ sy-msgv1 }). Cierre /GOOG/BQTR_SETTINGS en modo edición e intente de nuevo.|.
      RETURN.
    ENDIF.

    LOOP AT <lt_fld_db> ASSIGNING FIELD-SYMBOL(<ls_db>).
      UNASSIGN <lv_dsrc>.
      ASSIGN COMPONENT gs_schema-fld_dsrc OF STRUCTURE <ls_db> TO <lv_dsrc>.
      IF sy-subrc <> 0 OR <lv_dsrc> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

      DATA(lv_dsrc_str) = any_to_str( <lv_dsrc> ).
      DATA(lv_dsrc_up)  = to_upper( lv_dsrc_str ).

      " Si es ejecución individual por doble clic, procesar solo esa tabla
      IF lv_filt_up IS NOT INITIAL AND lv_dsrc_up <> lv_filt_up.
        CONTINUE.
      ENDIF.

      " Validar que pertenezca al filtro S_DSRC activo
      DATA(lv_in_scope) = abap_false.
      LOOP AT gt_dsrc_list INTO DATA(ls_dl).
        IF to_upper( any_to_str( ls_dl-datasource ) ) = lv_dsrc_up.
          lv_in_scope = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF lv_in_scope = abap_false.
        CONTINUE.
      ENDIF.

      UNASSIGN <lv_sapf>.
      ASSIGN COMPONENT gs_schema-fld_sapf OF STRUCTURE <ls_db> TO <lv_sapf>.
      DATA(lv_sapf_str) = COND string(
        WHEN <lv_sapf> IS ASSIGNED THEN any_to_str( <lv_sapf> ) ELSE '' ).

      DATA(lv_cur_tmp) = VALUE string( ).
      DATA(lv_cur_ext) = VALUE string( ).
      UNASSIGN: <lv_tmpf>, <lv_extf>.

      IF gs_schema-fld_tmpf IS NOT INITIAL.
        ASSIGN COMPONENT gs_schema-fld_tmpf OF STRUCTURE <ls_db> TO <lv_tmpf>.
        IF <lv_tmpf> IS ASSIGNED.
          lv_cur_tmp = any_to_str( <lv_tmpf> ).
        ENDIF.
      ENDIF.

      IF gs_schema-fld_extf IS NOT INITIAL.
        ASSIGN COMPONENT gs_schema-fld_extf OF STRUCTURE <ls_db> TO <lv_extf>.
        IF <lv_extf> IS ASSIGNED.
          lv_cur_ext = any_to_str( <lv_extf> ).
        ENDIF.
      ENDIF.

      " Si es una fila extra recién generada por P_GEN (recordstamp/operation_flag), persistirla
      DATA(lv_low_sap) = to_lower( lv_sapf_str ).
      DATA(lv_low_ext) = to_lower( lv_cur_ext ).
      IF lv_sapf_str IS INITIAL
         OR ( ( lv_low_ext = 'recordstamp' OR lv_low_ext = 'operation_flag' )
              AND lv_low_sap = lv_low_ext ).
        IF p_gen = abap_true.
          APPEND <ls_db> TO <lt_upd_db>.
        ENDIF.
        CONTINUE.
      ENDIF.

      DATA(lv_new_tech) = format_tech_name( lv_sapf_str ).
      DATA(lv_base_t)   = lv_new_tech.
      DATA(lv_dup_n)    = 1.
      WHILE line_exists( lt_used[ dsrc_up = lv_dsrc_up tech_nam = lv_new_tech ] ).
        lv_dup_n    = lv_dup_n + 1.
        lv_new_tech = |{ lv_base_t }_{ lv_dup_n }|.
      ENDWHILE.
      INSERT VALUE ty_used_name( dsrc_up = lv_dsrc_up tech_nam = lv_new_tech ) INTO TABLE lt_used.

      DATA(lv_chg)     = abap_false.
      DATA(lv_was_gen) = xsdbool( lv_cur_ext = '(NUEVO)' ).

      IF p_tmpf = abap_true AND <lv_tmpf> IS ASSIGNED AND lv_cur_tmp <> lv_new_tech.
        <lv_tmpf> = lv_new_tech.
        lv_chg    = abap_true.
      ENDIF.

      IF p_extf = abap_true AND <lv_extf> IS ASSIGNED AND lv_cur_ext <> lv_new_tech.
        <lv_extf> = lv_new_tech.
        lv_chg    = abap_true.
      ELSEIF lv_was_gen = abap_true AND <lv_extf> IS ASSIGNED.
        <lv_extf> = lv_new_tech.
        lv_chg    = abap_true.
      ENDIF.

      IF lv_chg = abap_true.
        IF gs_schema-fld_uname IS NOT INITIAL.
          UNASSIGN <lv_un>.
          ASSIGN COMPONENT gs_schema-fld_uname OF STRUCTURE <ls_db> TO <lv_un>.
          IF <lv_un> IS ASSIGNED. <lv_un> = sy-uname. ENDIF.
        ENDIF.
        IF gs_schema-fld_datum IS NOT INITIAL.
          UNASSIGN <lv_dt>.
          ASSIGN COMPONENT gs_schema-fld_datum OF STRUCTURE <ls_db> TO <lv_dt>.
          IF <lv_dt> IS ASSIGNED. <lv_dt> = sy-datum. ENDIF.
        ENDIF.
        IF gs_schema-fld_uzeit IS NOT INITIAL.
          UNASSIGN <lv_uz>.
          ASSIGN COMPONENT gs_schema-fld_uzeit OF STRUCTURE <ls_db> TO <lv_uz>.
          IF <lv_uz> IS ASSIGNED. <lv_uz> = sy-uzeit. ENDIF.
        ENDIF.

        APPEND <ls_db> TO <lt_upd_db>.
        ev_upd_rows = ev_upd_rows + 1.
        IF lv_was_gen = abap_true.
          ev_ins_rows = ev_ins_rows + 1.
        ENDIF.
        IF NOT line_exists( lt_touched[ dsrc_up = lv_dsrc_up ] ).
          INSERT VALUE ty_touched_tab( dsrc_up = lv_dsrc_up ) INTO TABLE lt_touched.
        ENDIF.
      ENDIF.
    ENDLOOP.

    ev_upd_tabs = lines( lt_touched ).

    IF <lt_upd_db> IS NOT INITIAL.
      show_progress(
        iv_pct  = 80
        iv_text = |Guardando { lines( <lt_upd_db> ) } campos en { gs_schema-tab_field }...| ).

      MODIFY (gs_schema-tab_field) FROM TABLE <lt_upd_db>.
      IF sy-subrc = 0.
        COMMIT WORK AND WAIT.
      ELSE.
        ROLLBACK WORK.
        ev_error_msg = |Error OpenSQL (SY-SUBRC={ sy-subrc }) al actualizar { gs_schema-tab_field }.|.
      ENDIF.
    ENDIF.

    CALL FUNCTION 'DEQUEUE_E_TABLE'
      EXPORTING
        mode_rstable = 'E'
        tabname      = lv_lock_tab.

    IF ev_error_msg IS INITIAL AND <lt_upd_db> IS NOT INITIAL.
      rebuild_alv_models( ).
    ENDIF.
  ENDMETHOD.

  METHOD execute_mass_apply.
    DATA: lv_pend_tabs TYPE i VALUE 0,
          lv_pend_flds TYPE i VALUE 0,
          lv_zero_tabs TYPE i VALUE 0,
          lv_ans       TYPE c LENGTH 1,
          lv_title     TYPE c LENGTH 70,
          lv_quest     TYPE c LENGTH 250.

    LOOP AT gt_summary INTO DATA(ls_s).
      IF ls_s-total_flds = 0.
        lv_zero_tabs = lv_zero_tabs + 1.
      ELSEIF ls_s-pend_flds > 0.
        lv_pend_tabs = lv_pend_tabs + 1.
        lv_pend_flds = lv_pend_flds + ls_s-pend_flds.
      ENDIF.
    ENDLOOP.

    IF lv_pend_flds = 0.
      MESSAGE
        |No hay columnas pendientes de actualizar en "{ gv_real_trkey }" ({ lv_zero_tabs } tablas sin campos).|
        TYPE 'S'.
      RETURN.
    ENDIF.

    lv_title = |Actualización Masiva - Transfer { gv_real_trkey }|.
    lv_quest =
      |Se actualizarán { lv_pend_flds } columnas en { lv_pend_tabs } vistas CDS de { gs_schema-tab_field }. ¿Aplicar ahora?|.

    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = lv_title
        text_question         = lv_quest
        text_button_1         = 'Sí, Actualizar'
        text_button_2         = 'Solo Simular'
        default_button        = '2'
        display_cancel_button = ''
      IMPORTING
        answer                = lv_ans
      EXCEPTIONS
        OTHERS                = 1.

    IF lv_ans <> '1'.
      MESSAGE 'Ejecución masiva cancelada; se muestra el reporte en modo simulación.' TYPE 'S'.
      RETURN.
    ENDIF.

    apply_updates_to_db(
      IMPORTING
        ev_upd_rows  = DATA(lv_rows)
        ev_upd_tabs  = DATA(lv_tabs)
        ev_ins_rows  = DATA(lv_ins)
        ev_error_msg = DATA(lv_err) ).

    IF lv_err IS NOT INITIAL.
      MESSAGE lv_err TYPE 'I' DISPLAY LIKE 'E'.
    ELSEIF lv_ins > 0.
      MESSAGE
        |¡Listo! { lv_rows } columnas actualizadas ({ lv_ins } generadas nuevas) en { lv_tabs } tablas de { gv_real_trkey }.|
        TYPE 'S'.
    ELSE.
      MESSAGE
        |¡Listo! { lv_rows } columnas actualizadas con nombres técnicos en { lv_tabs } tablas de { gv_real_trkey }.|
        TYPE 'S'.
    ENDIF.
  ENDMETHOD.

  METHOD prompt_single_table_apply.
    DATA: lv_ans      TYPE c LENGTH 1,
          lv_title    TYPE c LENGTH 70,
          lv_quest    TYPE c LENGTH 250,
          lv_key_dsrc TYPE ty_dsrc_name.

    lv_key_dsrc = CONV ty_dsrc_name( iv_dsrc ).

    READ TABLE gt_summary INTO DATA(ls_sum)
      WITH KEY datasource = lv_key_dsrc.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA(lv_ds_lbl) = any_to_str( lv_key_dsrc ).
    DATA(lv_et_lbl) = any_to_str( ls_sum-ext_table ).

    IF ls_sum-total_flds = 0.
      MESSAGE
        |{ lv_ds_lbl } tiene 0 filas en { gs_schema-tab_field }. Abra Display Field (@10@) o ejecute marcando "Generar filas de CDS".|
        TYPE 'I'.
      RETURN.
    ENDIF.

    IF ls_sum-pend_flds = 0.
      show_table_detail_popup( lv_key_dsrc ).
      RETURN.
    ENDIF.

    lv_title = |Actualizar Campos de { lv_ds_lbl }|.
    lv_quest =
      |¿Actualizar las { ls_sum-pend_flds } columnas pendientes de { lv_ds_lbl } (-> { lv_et_lbl }) con nombres técnicos ahora?|.

    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = lv_title
        text_question         = lv_quest
        text_button_1         = 'Actualizar Tabla'
        text_button_2         = 'Ver Columnas'
        default_button        = '1'
        display_cancel_button = 'X'
      IMPORTING
        answer                = lv_ans
      EXCEPTIONS
        OTHERS                = 1.

    IF lv_ans = '2'.
      show_table_detail_popup( lv_key_dsrc ).
      RETURN.
    ELSEIF lv_ans <> '1'.
      RETURN.
    ENDIF.

    apply_updates_to_db(
      EXPORTING
        iv_single_dsrc = lv_key_dsrc
      IMPORTING
        ev_upd_rows    = DATA(lv_rows)
        ev_error_msg   = DATA(lv_err) ).

    IF lv_err IS NOT INITIAL.
      MESSAGE lv_err TYPE 'I' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    IF go_salv IS BOUND.
      go_salv->set_top_of_list( build_alv_header( ) ).
      go_salv->refresh( ).
    ENDIF.

    MESSAGE |{ lv_ds_lbl }: { lv_rows } columnas actualizadas a nombre técnico OK.| TYPE 'S'.
  ENDMETHOD.

  METHOD show_table_detail_popup.
    DATA: lt_sub      TYPE tt_detail,
          lo_pop      TYPE REF TO cl_salv_table,
          lv_key_dsrc TYPE ty_dsrc_name.

    lv_key_dsrc = CONV ty_dsrc_name( iv_dsrc ).

    LOOP AT gt_detail INTO DATA(ls_d)
      WHERE datasource = lv_key_dsrc.
      APPEND ls_d TO lt_sub.
    ENDLOOP.

    DATA(lv_ds_lbl) = any_to_str( lv_key_dsrc ).
    IF lt_sub IS INITIAL.
      MESSAGE |{ lv_ds_lbl } aún no tiene columnas cargadas en { gs_schema-tab_field }.| TYPE 'I'.
      RETURN.
    ENDIF.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_pop
          CHANGING  t_table      = lt_sub ).

        lo_pop->get_functions( )->set_all( abap_true ).
        DATA(lo_cols) = lo_pop->get_columns( ).
        lo_cols->set_optimize( abap_true ).
        TRY.
            lo_cols->set_color_column( 'T_COLOR' ).
          CATCH cx_salv_data_error.
        ENDTRY.

        set_col_text( io_cols = lo_cols iv_col = 'DATASOURCE'  iv_s = 'Fuente'    iv_m = 'SAP Datasource'     iv_l = 'SAP Datasource Name' ).
        set_col_text( io_cols = lo_cols iv_col = 'EXT_TABLE'   iv_s = 'Ext.Table' iv_m = 'Ext Table Name'     iv_l = 'Ext Table Name (BigQuery)' ).
        set_col_text( io_cols = lo_cols iv_col = 'SAP_FIELD'   iv_s = 'SAP Field' iv_m = 'SAP Field Name'     iv_l = 'SAP Field Name (Técnico)' ).
        set_col_text( io_cols = lo_cols iv_col = 'IS_KEY'      iv_s = 'Clave'     iv_m = '¿Clave?'            iv_l = '¿Campo Clave?' ).
        set_col_text( io_cols = lo_cols iv_col = 'SAP_TYPE'    iv_s = 'Tipo SAP'  iv_m = 'Tipo Dato SAP'      iv_l = 'Tipo de Dato SAP' ).
        set_col_text( io_cols = lo_cols iv_col = 'BQ_TYPE'     iv_s = 'Tipo BQ'   iv_m = 'Tipo BigQuery'      iv_l = 'Tipo Dato BigQuery' ).
        set_col_text( io_cols = lo_cols iv_col = 'CURR_TMPF'   iv_s = 'Temp.Act.' iv_m = 'Temp Field Actual'  iv_l = 'Temp Field Actual' ).
        set_col_text( io_cols = lo_cols iv_col = 'CURR_EXTF'   iv_s = 'Ext.Act.'  iv_m = 'Ext Field Actual'   iv_l = 'Ext Field Name Actual' ).
        set_col_text( io_cols = lo_cols iv_col = 'NEW_TECH'    iv_s = 'NuevoTéc.' iv_m = 'Nuevo Nombre Téc.'  iv_l = 'Nuevo Nombre Técnico BQ' ).
        set_col_text( io_cols = lo_cols iv_col = 'DESCRIPTION' iv_s = 'Descrip.'  iv_m = 'Descripción Campo'  iv_l = 'Descripción Campo SAP' ).
        set_col_text( io_cols = lo_cols iv_col = 'ESTADO'      iv_s = 'Estado'    iv_m = 'Estado Columna'     iv_l = 'Estado Columna' ).
        set_col_text( io_cols = lo_cols iv_col = 'NOTA'        iv_s = 'Detalle'   iv_m = 'Detalle de Cambio'  iv_l = 'Detalle de Cambio' ).

        DATA(lv_hdr) = CONV lvc_title( |Detalle de Columnas: { lv_ds_lbl } ({ lines( lt_sub ) } campos)| ).
        lo_pop->get_display_settings( )->set_list_header( lv_hdr ).
        lo_pop->set_screen_popup(
          start_column = 4
          end_column   = 175
          start_line   = 3
          end_line     = 26 ).
        lo_pop->display( ).
      CATCH cx_salv_msg INTO DATA(lx_pop).
        MESSAGE lx_pop->get_text( ) TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

  METHOD on_double_click.
    IF row <= 0.
      RETURN.
    ENDIF.

    IF p_res = abap_true.
      READ TABLE gt_summary INTO DATA(ls_sum) INDEX row.
      IF sy-subrc <> 0.
        RETURN.
      ENDIF.
      IF column = 'ESTADO' OR column = 'ACCION' OR column = 'PEND_FLDS'.
        prompt_single_table_apply( ls_sum-datasource ).
      ELSE.
        show_table_detail_popup( ls_sum-datasource ).
      ENDIF.
    ELSE.
      READ TABLE gt_detail_vw INTO DATA(ls_det) INDEX row.
      IF sy-subrc <> 0.
        RETURN.
      ENDIF.
      IF column = 'ESTADO' OR column = 'NOTA' OR column = 'NEW_TECH'.
        prompt_single_table_apply( ls_det-datasource ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD add_cell_color.
    APPEND VALUE lvc_s_scol(
      fname = iv_fname
      color = VALUE lvc_s_colo( col = iv_col int = iv_int inv = 0 )
    ) TO ct_color.
  ENDMETHOD.

  METHOD set_col_text.
    TRY.
        DATA(lo_c) = io_cols->get_column( iv_col ).
        lo_c->set_short_text( iv_s ).
        lo_c->set_medium_text( iv_m ).
        lo_c->set_long_text( iv_l ).
      CATCH cx_salv_not_found.
    ENDTRY.
  ENDMETHOD.

  METHOD build_alv_header.
    DATA: lv_tot_tabs  TYPE i,
          lv_pend_tabs TYPE i,
          lv_zero_tabs TYPE i,
          lv_tot_flds  TYPE i,
          lv_pend_flds TYPE i,
          lv_ok_flds   TYPE i,
          lv_h1        TYPE string,
          lv_h2        TYPE string,
          lv_h3        TYPE string,
          lv_h4        TYPE string.

    lv_tot_tabs = lines( gt_summary ).
    LOOP AT gt_summary INTO DATA(ls_s).
      lv_tot_flds  = lv_tot_flds  + ls_s-total_flds.
      lv_pend_flds = lv_pend_flds + ls_s-pend_flds.
      lv_ok_flds   = lv_ok_flds   + ls_s-ok_flds + ls_s-extra_flds.
      IF ls_s-total_flds = 0.
        lv_zero_tabs = lv_zero_tabs + 1.
      ELSEIF ls_s-pend_flds > 0.
        lv_pend_tabs = lv_pend_tabs + 1.
      ENDIF.
    ENDLOOP.

    DATA(lv_tmp_lbl) = COND string(
      WHEN gs_schema-fld_tmpf IS NOT INITIAL THEN gs_schema-fld_tmpf ELSE '(solo UI)' ).
    DATA(lv_ext_lbl) = COND string(
      WHEN gs_schema-fld_extf IS NOT INITIAL THEN gs_schema-fld_extf ELSE '(N/A)' ).

    lv_h1 = |BigQuery Data Transfer: { gv_real_trkey }|.
    lv_h2 =
      |Tablas evaluadas: { lv_tot_tabs } ({ lv_pend_tabs } con cambios, { lv_zero_tabs } sin filas)   | &&
      |Columnas totales: { lv_tot_flds } ({ lv_pend_flds } pendientes, { lv_ok_flds } ya OK)|.
    lv_h3 =
      |Esquema DDIC [{ gs_schema-tab_field }]: Fuente={ gs_schema-fld_dsrc }, | &&
      |SAP Field={ gs_schema-fld_sapf }, Temp Field={ lv_tmp_lbl }, Ext Field={ lv_ext_lbl }|.
    lv_h4 =
      'Atajos Doble Clic: [Fuente SAP] = Ver columnas de esa tabla  |  [Estado / Acción] = Actualizar solo esa tabla en vivo'.

    CREATE OBJECT ro_grid.
    ro_grid->create_header_information( row = 1 column = 1 text = lv_h1 tooltip = lv_h1 ).
    ro_grid->create_text( row = 2 column = 1 text = lv_h2 ).
    ro_grid->create_text( row = 3 column = 1 text = lv_h3 ).
    ro_grid->create_text( row = 4 column = 1 text = lv_h4 ).
  ENDMETHOD.

  METHOD display_summary_alv.
    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = go_salv
          CHANGING  t_table      = gt_summary ).

        go_salv->get_functions( )->set_all( abap_true ).
        go_salv->get_display_settings( )->set_striped_pattern( abap_true ).
        go_salv->set_top_of_list( build_alv_header( ) ).

        DATA(lo_cols) = go_salv->get_columns( ).
        lo_cols->set_optimize( abap_true ).
        TRY.
            lo_cols->set_color_column( 'T_COLOR' ).
          CATCH cx_salv_data_error.
        ENDTRY.

        set_col_text( io_cols = lo_cols iv_col = 'DATASOURCE'  iv_s = 'Fuente SAP' iv_m = 'SAP Datasource'     iv_l = 'SAP Datasource Name (Doble clic=Ver)' ).
        set_col_text( io_cols = lo_cols iv_col = 'EXT_TABLE'   iv_s = 'Ext.Table'  iv_m = 'Ext Table Name'     iv_l = 'Ext Table Name en BigQuery' ).
        set_col_text( io_cols = lo_cols iv_col = 'TOTAL_FLDS'  iv_s = 'Tot.Cols.'  iv_m = 'Total Columnas'     iv_l = 'Total Columnas en BQTR_FIELD' ).
        set_col_text( io_cols = lo_cols iv_col = 'OK_FLDS'     iv_s = 'Ya Técn.'   iv_m = 'Ya con Nom.Técnico' iv_l = 'Columnas Ya con Nombre Técnico' ).
        set_col_text( io_cols = lo_cols iv_col = 'PEND_FLDS'   iv_s = 'Pendientes' iv_m = 'Cols. a Actualizar' iv_l = 'Columnas Pendientes de Actualizar' ).
        set_col_text( io_cols = lo_cols iv_col = 'EXTRA_FLDS'  iv_s = 'Extras SDK' iv_m = 'Campos Extra SDK'   iv_l = 'Campos Extra (recordstamp/operation)' ).
        set_col_text( io_cols = lo_cols iv_col = 'EJEMPLO_CHG' iv_s = 'Ejemplos'   iv_m = 'Ejemplo Antes->Desp' iv_l = 'Ejemplos de Cambio (Antes -> Después)' ).
        set_col_text( io_cols = lo_cols iv_col = 'ESTADO'      iv_s = 'Estado'     iv_m = 'Estado Tabla'       iv_l = 'Estado Tabla (Doble clic=Aplicar)' ).
        set_col_text( io_cols = lo_cols iv_col = 'ACCION'      iv_s = 'Acción'     iv_m = 'Acción / Resultado' iv_l = 'Acción Disponible (Doble clic=Aplicar)' ).

        DATA(lo_events) = go_salv->get_event( ).
        SET HANDLER on_double_click FOR lo_events.

        go_salv->display( ).
      CATCH cx_salv_msg INTO DATA(lx_salv).
        MESSAGE lx_salv->get_text( ) TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD display_detail_alv.
    IF gt_detail_vw IS INITIAL.
      MESSAGE 'No hay columnas que mostrar con el filtro actual (ej. todas están ya en nombre técnico).'
        TYPE 'S'.
      display_summary_alv( ).
      RETURN.
    ENDIF.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = go_salv
          CHANGING  t_table      = gt_detail_vw ).

        go_salv->get_functions( )->set_all( abap_true ).
        go_salv->get_display_settings( )->set_striped_pattern( abap_true ).
        go_salv->set_top_of_list( build_alv_header( ) ).

        DATA(lo_cols) = go_salv->get_columns( ).
        lo_cols->set_optimize( abap_true ).
        TRY.
            lo_cols->set_color_column( 'T_COLOR' ).
          CATCH cx_salv_data_error.
        ENDTRY.

        set_col_text( io_cols = lo_cols iv_col = 'DATASOURCE'  iv_s = 'Fuente SAP' iv_m = 'SAP Datasource'    iv_l = 'SAP Datasource Name' ).
        set_col_text( io_cols = lo_cols iv_col = 'EXT_TABLE'   iv_s = 'Ext.Table'  iv_m = 'Ext Table Name'    iv_l = 'Ext Table Name en BigQuery' ).
        set_col_text( io_cols = lo_cols iv_col = 'SAP_FIELD'   iv_s = 'SAP Field'  iv_m = 'SAP Field Name'    iv_l = 'SAP Field Name (Original)' ).
        set_col_text( io_cols = lo_cols iv_col = 'IS_KEY'      iv_s = 'Clave'      iv_m = '¿Clave?'           iv_l = '¿Campo Clave?' ).
        set_col_text( io_cols = lo_cols iv_col = 'SAP_TYPE'    iv_s = 'Tipo SAP'   iv_m = 'Tipo Dato SAP'     iv_l = 'Tipo de Dato SAP' ).
        set_col_text( io_cols = lo_cols iv_col = 'BQ_TYPE'     iv_s = 'Tipo BQ'    iv_m = 'Tipo BigQuery'     iv_l = 'Tipo Dato BigQuery' ).
        set_col_text( io_cols = lo_cols iv_col = 'CURR_TMPF'   iv_s = 'Temp.Act.'  iv_m = 'Temp Field Actual' iv_l = 'Temp Field Actual' ).
        set_col_text( io_cols = lo_cols iv_col = 'CURR_EXTF'   iv_s = 'Ext.Act.'   iv_m = 'Ext Field Actual'  iv_l = 'Ext Field Name Actual' ).
        set_col_text( io_cols = lo_cols iv_col = 'NEW_TECH'    iv_s = 'NuevoTéc.'  iv_m = 'Nuevo Nombre Téc.' iv_l = 'Nuevo Nombre Técnico BQ' ).
        set_col_text( io_cols = lo_cols iv_col = 'DESCRIPTION' iv_s = 'Descrip.'   iv_m = 'Descripción SAP'   iv_l = 'Descripción Campo SAP' ).
        set_col_text( io_cols = lo_cols iv_col = 'ESTADO'      iv_s = 'Estado'     iv_m = 'Estado Columna'    iv_l = 'Estado (Doble clic=Aplicar Tabla)' ).
        set_col_text( io_cols = lo_cols iv_col = 'NOTA'        iv_s = 'Detalle'    iv_m = 'Detalle de Cambio' iv_l = 'Detalle de Cambio' ).

        DATA(lo_events) = go_salv->get_event( ).
        SET HANDLER on_double_click FOR lo_events.

        go_salv->display( ).
      CATCH cx_salv_msg INTO DATA(lx_salv).
        MESSAGE lx_salv->get_text( ) TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD run.
    DATA lv_err TYPE string.

    show_progress(
      iv_pct  = 15
      iv_text = 'Inspeccionando diccionario DDIC de /GOOG/BQTR*...' ).

    resolve_schema(
      EXPORTING iv_tmst      = p_tmst
                iv_ttab      = p_ttab
                iv_tfld      = p_tfld
      IMPORTING es_schema    = gs_schema
                ev_error_msg = lv_err ).

    IF lv_err IS NOT INITIAL.
      MESSAGE lv_err TYPE 'I' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    show_progress(
      iv_pct  = 45
      iv_text = |Leyendo tablas y columnas del Data Transfer { p_trkey }...| ).

    load_transfer_data( IMPORTING ev_error_msg = lv_err ).
    IF lv_err IS NOT INITIAL.
      MESSAGE lv_err TYPE 'I' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    IF p_apply = abap_true.
      execute_mass_apply( ).
    ENDIF.

    IF p_res = abap_true.
      display_summary_alv( ).
    ELSE.
      display_detail_alv( ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Textos de Pantalla de Selección (sin requerir Text Elements en SE38)
*----------------------------------------------------------------------*
INITIALIZATION.
  txt_b1  = '1. Selección del BigQuery Data Transfer (/GOOG/BQTR_SETTINGS)'.
  c_tip1  = 'Use F4 en Data Transfer; S_DSRC vacío procesa las ~150 vistas del transfer.'.
  c_trkey = 'Data Transfer (Mass Tr.Key):'.

  txt_b2  = '2. Reglas de Copia de Nombres Técnicos (SAP Field -> Temp / Ext Field)'.
  c_tmpf  = 'Copiar SAP Field Name hacia columna Temp Field'.
  c_extf  = 'Copiar SAP Field Name hacia columna Ext Field Name (destino BigQuery)'.
  c_lower = 'Formatear en minúsculas y caracteres válidos BigQuery (ej. date_from)'.
  c_gen   = 'Si una vista de BQTR_TABLE tiene 0 filas en BQTR_FIELD, generarlas de CDS'.

  txt_b3  = '3. Modo de Visualización ALV (Exportable a Excel)'.
  c_res   = 'Vista Resumen (1 fila por CDS View: conteos + doble clic interactivo)'.
  c_det   = 'Vista Detallada (1 fila por columna: Temp/Ext actual vs Nuevo técnico)'.
  c_onlyc = 'En Vista Detallada, mostrar solo columnas pendientes de cambio'.

  txt_b4  = '4. Modo de Ejecución'.
  c_read  = 'Solo Simulación / Lectura (Previsualizar cambios sin modificar BD)'.
  c_apply = 'Actualizar Masivamente el Data Transfer en /GOOG/BQTR_FIELD'.

  txt_b5  = '5. Tablas Técnicas del SDK (Auto-detectadas)'.
  c_tmst  = 'Tabla Cabecera Transfer:'.
  c_ttab  = 'Tabla Fuentes Transfer:'.
  c_tfld  = 'Tabla Campos Transfer:'.

*----------------------------------------------------------------------*
* Ayuda de búsqueda F4 para Data Transfer (Mass Transfer Key)
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_trkey.
  lcl_bqtr_sync=>f4_transfer_key( CHANGING cv_trkey = p_trkey ).

*----------------------------------------------------------------------*
* Ejecución Principal
*----------------------------------------------------------------------*
START-OF-SELECTION.
  lcl_bqtr_sync=>run( ).
