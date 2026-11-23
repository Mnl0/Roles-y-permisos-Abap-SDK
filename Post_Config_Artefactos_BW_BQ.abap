*&---------------------------------------------------------------------*
*& Report ZGEN_BQTR_POST_REPL_BW
*&---------------------------------------------------------------------*
*& Automatización Post-Generación de Artefactos BW para BigQuery Toolkit
*& (Complemento directo de ZGOOG_R_BQTR_GEN_REPL_OBJECTS)
*&
*& Propósito (ejecutado en orden seguro de dependencias por cada tabla):
*&   1) Fuente de Datos (RSDS -> Pestaña Campos):
*&      Detecta si algún campo tiene filtro en "Clase de campo" (ej. 'L'
*&      de idioma en tablas de texto como MAKT, SKAT, T005T), lo deja en
*&      blanco, guarda y activa la RSDS (CL_RSDS_RSDS).
*&   2) Transformación (TRFN) + Rutina de Inicio (ROUT):
*&      Abre la transformación existente (CL_RSTRAN_TRFN), aplica un
*&      toque inocuo (espacio/marca de sincronización) en el código ABAP
*&      de la Start Routine (CL_RSTRAN_STEP_ROUT), guarda y fuerza la
*&      activación para consolidar las versiones activas 'A' de TRFN y
*&      ROUT de cara a la Conexión de Transporte de RSA1.
*&   3) DTP Full (DTPA, UPDMODE = 'F'):
*&      Verifica si ya existe un DTP Full entre la RSDS y el ADSO; si
*&      solo existe el DTP Delta ('D'), crea automáticamente el DTP Full
*&      con extracción directa del sistema fuente (sin PSA), lo guarda y
*&      lo activa (CL_RSBK_DTP / CL_RSBK_DTP_COLLECTION).
*&   4) Cadena de Procesos (RSPC):
*&      Activa la cadena de procesos (CL_RSPC_CHAIN->ACTIVATE) pasando
*&      de versión 'M' a 'A' SIN planificarla ni disparar jobs en SM37.
*&---------------------------------------------------------------------*
REPORT zgen_bqtr_post_repl_bw.

*----------------------------------------------------------------------*
* Tipos globales para ALV y orquestación de flujos BW
*----------------------------------------------------------------------*
TYPES:
  BEGIN OF ty_flow,
    adso          TYPE rsoadsonm,
    datasource    TYPE roosourcer,
    logsys        TYPE rsslogsys,
    sourcename    TYPE rstran-sourcename,
    ds_filter_inf TYPE c LENGTH 55,
    ds_need_fix   TYPE abap_bool,
    tranid        TYPE rstranid,
    trfn_stat     TYPE c LENGTH 10,
    startroutine  TYPE rscodeid,
    dtp_delta     TYPE rsbkdtpnm,
    dtp_full      TYPE rsbkdtpnm,
    dtp_full_stat TYPE c LENGTH 18,
    chain_id      TYPE rspc_chain,
    chain_stat    TYPE c LENGTH 16,
    estado_global TYPE c LENGTH 22,
    accion_res    TYPE c LENGTH 110,
    t_color       TYPE lvc_t_scol,
  END OF ty_flow,

  BEGIN OF ty_rsds_schema,
    col_ds       TYPE fieldname,
    col_logsys   TYPE fieldname,
    col_objvers  TYPE fieldname,
    col_fieldnm  TYPE fieldname,
    col_datatype TYPE fieldname,
    col_fldclass TYPE fieldname,
    col_seltype  TYPE fieldname,
  END OF ty_rsds_schema,

  BEGIN OF ty_rsaabap_schema,
    col_codeid  TYPE fieldname,
    col_objvers TYPE fieldname,
    col_lineno  TYPE fieldname,
    col_line    TYPE fieldname,
  END OF ty_rsaabap_schema,

  tt_flow   TYPE STANDARD TABLE OF ty_flow WITH DEFAULT KEY,
  tt_string TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

*----------------------------------------------------------------------*
* Variables auxiliares para SELECT-OPTIONS y estado global
*----------------------------------------------------------------------*
DATA: gv_sel_adso   TYPE rsoadsonm,
      gv_sel_ds     TYPE roosourcer,
      gv_sel_chain  TYPE rspc_chain,
      gs_rsds_sch   TYPE ty_rsds_schema,
      gs_abap_sch   TYPE ty_rsaabap_schema,
      gt_flows      TYPE tt_flow,
      gt_flows_view TYPE tt_flow,
      go_salv       TYPE REF TO cl_salv_table.

*----------------------------------------------------------------------*
* Pantalla de Selección (sin requerir Text Elements en SE38)
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE txt_b1.
  SELECTION-SCREEN COMMENT /1(77) c_tip1.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(28) c_trkey FOR FIELD p_trkey.
    PARAMETERS: p_trkey TYPE /goog/trkey MATCHCODE OBJECT /goog/sh_bqtr_transf_key.
  SELECTION-SCREEN END OF LINE.

  SELECT-OPTIONS: s_adso  FOR gv_sel_adso,
                  s_ds    FOR gv_sel_ds,
                  s_chain FOR gv_sel_chain.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE txt_b2.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_s1_ds AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 4(74) c_s1_ds FOR FIELD p_s1_ds.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_onlylg AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 7(71) c_onlylg FOR FIELD p_onlylg.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_s2_tr AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 4(74) c_s2_tr FOR FIELD p_s2_tr.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_s3_dt AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 4(74) c_s3_dt FOR FIELD p_s3_dt.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_s4_pc AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 4(74) c_s4_pc FOR FIELD p_s4_pc.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN SKIP 1.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_cto AS CHECKBOX DEFAULT abap_false.
    SELECTION-SCREEN COMMENT 4(74) c_cto FOR FIELD p_cto.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE txt_b3.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_onlyp AS CHECKBOX DEFAULT abap_false.
    SELECTION-SCREEN COMMENT 4(74) c_onlyp FOR FIELD p_onlyp.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b3.

SELECTION-SCREEN BEGIN OF BLOCK b4 WITH FRAME TITLE txt_b4.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_read RADIOBUTTON GROUP rb1 DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 4(74) c_read FOR FIELD p_read.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_apply RADIOBUTTON GROUP rb1.
    SELECTION-SCREEN COMMENT 4(74) c_apply FOR FIELD p_apply.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b4.

*----------------------------------------------------------------------*
* Clase Principal de Automatización Post-Generación BW
*----------------------------------------------------------------------*
CLASS lcl_bw_post_auto DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
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

      get_dfies_merged
        IMPORTING iv_tabname      TYPE tabname
        RETURNING VALUE(rt_dfies) TYPE ddfields,

      resolve_dynamic_schemas
        EXPORTING ev_error_msg TYPE string,

      collect_bqtr_datasources_by_tr
        IMPORTING iv_trkey       TYPE /goog/trkey
        EXPORTING et_upper_names TYPE tt_string,

      routine_mentions_trkey
        IMPORTING iv_codeid       TYPE rscodeid
                  iv_trkey        TYPE /goog/trkey
        RETURNING VALUE(rv_match) TYPE abap_bool,

      inspect_rsds_filter
        IMPORTING iv_datasource TYPE roosourcer
                  iv_logsys     TYPE rsslogsys
        EXPORTING ev_need_fix   TYPE abap_bool
                  ev_info_text  TYPE string,

      discover_bw_flows
        EXPORTING ev_error_msg TYPE string,

      refresh_flow_status_and_colors
        CHANGING cs_flow TYPE ty_flow,

      rebuild_view_table,

      step1_fix_and_activate_rsds
        IMPORTING is_flow      TYPE ty_flow
        EXPORTING ev_changed   TYPE abap_bool
                  ev_msg       TYPE string
                  ev_error     TYPE abap_bool,

      read_routine_lines_from_db
        IMPORTING iv_codeid       TYPE rscodeid
        RETURNING VALUE(rt_lines) TYPE rstran_t_abapsource,

      step2_touch_and_activate_trfn
        IMPORTING is_flow    TYPE ty_flow
        EXPORTING ev_msg     TYPE string
                  ev_error   TYPE abap_bool,

      step3_ensure_full_dtp
        IMPORTING is_flow     TYPE ty_flow
        EXPORTING ev_dtp_full TYPE rsbkdtpnm
                  ev_created  TYPE abap_bool
                  ev_msg      TYPE string
                  ev_error    TYPE abap_bool,

      step4_activate_chain_no_sched
        IMPORTING is_flow  TYPE ty_flow
        EXPORTING ev_msg   TYPE string
                  ev_error TYPE abap_bool,

      process_single_flow
        EXPORTING ev_error TYPE abap_bool
        CHANGING  cs_flow  TYPE ty_flow,

      execute_mass_processing,

      prompt_single_flow_action
        IMPORTING iv_adso       TYPE rsoadsonm
                  iv_sourcename TYPE rstran-sourcename,

      preview_start_routine
        IMPORTING is_flow TYPE ty_flow,

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

      display_alv.
ENDCLASS.

CLASS lcl_bw_post_auto IMPLEMENTATION.

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

  METHOD get_dfies_merged.
    DATA: lt_sy       TYPE ddfields,
          lt_en       TYPE ddfields,
          lv_ddobj    TYPE ddobjname,
          lv_langu_en TYPE sy-langu VALUE 'E'.

    lv_ddobj = iv_tabname.

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

    IF lt_sy IS NOT INITIAL.
      rt_dfies = lt_sy.
      LOOP AT rt_dfies ASSIGNING FIELD-SYMBOL(<fs_sy>).
        READ TABLE lt_en INTO DATA(ls_en)
          WITH KEY fieldname = <fs_sy>-fieldname.
        IF sy-subrc = 0.
          " Concatenar etiqueta EN en reptext si estaba vacío para facilitar búsqueda bilingüe
          IF <fs_sy>-fieldtext IS INITIAL.
            <fs_sy>-fieldtext = ls_en-fieldtext.
          ELSEIF ls_en-fieldtext IS NOT INITIAL AND <fs_sy>-fieldtext <> ls_en-fieldtext.
            <fs_sy>-fieldtext = |{ <fs_sy>-fieldtext } / { ls_en-fieldtext }|.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ELSE.
      rt_dfies = lt_en.
    ENDIF.

    SORT rt_dfies BY position ASCENDING.
  ENDMETHOD.

  METHOD resolve_dynamic_schemas.
    CLEAR: ev_error_msg, gs_rsds_sch, gs_abap_sch.

    " 1. Inspeccionar RSDSSEGFD (pestaña Campos de la Fuente de Datos RSDS)
    DATA(lt_rsds_df) = get_dfies_merged( 'RSDSSEGFD' ).
    IF lt_rsds_df IS INITIAL.
      ev_error_msg = 'No se pudo leer la estructura DDIC de la tabla estándar RSDSSEGFD.'.
      RETURN.
    ENDIF.

    LOOP AT lt_rsds_df INTO DATA(ls_rf).
      DATA(lv_rtxt) = to_upper(
        |{ ls_rf-fieldname } { ls_rf-rollname } { ls_rf-fieldtext } | &&
        |{ ls_rf-reptext } { ls_rf-scrtext_s } { ls_rf-scrtext_m } { ls_rf-scrtext_l }| ).

      CASE ls_rf-fieldname.
        WHEN 'DATASOURCE'.
          gs_rsds_sch-col_ds = ls_rf-fieldname.
        WHEN 'LOGSYS'.
          gs_rsds_sch-col_logsys = ls_rf-fieldname.
        WHEN 'OBJVERS'.
          gs_rsds_sch-col_objvers = ls_rf-fieldname.
        WHEN 'FIELDNM' OR 'FIELDNAME'.
          IF gs_rsds_sch-col_fieldnm IS INITIAL.
            gs_rsds_sch-col_fieldnm = ls_rf-fieldname.
          ENDIF.
        WHEN 'DATATYPE'.
          gs_rsds_sch-col_datatype = ls_rf-fieldname.
      ENDCASE.

      " Identificar columna "Clase de campo" / "Field Type" / "Selection Type"
      IF ls_rf-keyflag <> 'X'
         AND ls_rf-datatype = 'CHAR'
         AND ls_rf-leng <= 4
         AND ls_rf-fieldname <> 'OBJVERS'
         AND ls_rf-fieldname <> 'DATATYPE'
         AND ls_rf-fieldname <> 'INTTYPE'
         AND ls_rf-fieldname <> 'KEYFLAG'
         AND ls_rf-fieldname <> 'LOWERCASE'
         AND ls_rf-fieldname <> 'SIGN'
         AND ls_rf-fieldname <> 'TRANSFER'.

        IF ls_rf-fieldname = 'FDTYPE'
           OR ls_rf-fieldname = 'FIELDTYPE'
           OR ls_rf-fieldname = 'FELDART'
           OR lv_rtxt CS 'CLASE DE CAMPO'
           OR lv_rtxt CS 'CLASE CAMPO'
           OR lv_rtxt CS 'CLASE CPO'
           OR lv_rtxt CS 'FIELD TYPE'.
          IF gs_rsds_sch-col_fldclass IS INITIAL.
            gs_rsds_sch-col_fldclass = ls_rf-fieldname.
          ENDIF.
        ELSEIF ls_rf-fieldname = 'SELTYPE'
               OR ls_rf-fieldname = 'SELECTION'
               OR lv_rtxt CS 'SELTYPE'
               OR lv_rtxt CS 'SELECTION TYPE'
               OR lv_rtxt CS 'TIPO DE SELECC'.
          IF gs_rsds_sch-col_seltype IS INITIAL.
            gs_rsds_sch-col_seltype = ls_rf-fieldname.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF gs_rsds_sch-col_fldclass IS INITIAL AND gs_rsds_sch-col_seltype IS NOT INITIAL.
      gs_rsds_sch-col_fldclass = gs_rsds_sch-col_seltype.
    ENDIF.

    " 2. Inspeccionar RSAABAP (código ABAP de Start/End Routines BW)
    DATA(lt_abap_df) = get_dfies_merged( 'RSAABAP' ).
    IF lt_abap_df IS INITIAL.
      ev_error_msg = 'No se pudo leer la estructura DDIC de la tabla estándar RSAABAP.'.
      RETURN.
    ENDIF.

    LOOP AT lt_abap_df INTO DATA(ls_af).
      IF ls_af-fieldname = 'CODEID'.
        gs_abap_sch-col_codeid = ls_af-fieldname.
      ELSEIF ls_af-fieldname = 'OBJVERS'.
        gs_abap_sch-col_objvers = ls_af-fieldname.
      ELSEIF ls_af-keyflag = 'X'
             AND ls_af-datatype <> 'CLNT'
             AND ls_af-fieldname <> 'CODEID'
             AND ls_af-fieldname <> 'OBJVERS'
             AND gs_abap_sch-col_lineno IS INITIAL.
        gs_abap_sch-col_lineno = ls_af-fieldname.
      ELSEIF ls_af-keyflag <> 'X'
             AND ( ls_af-inttype = 'C' OR ls_af-inttype = 'g' )
             AND gs_abap_sch-col_line IS INITIAL.
        gs_abap_sch-col_line = ls_af-fieldname.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD collect_bqtr_datasources_by_tr.
    DATA: lt_df    TYPE ddfields,
          col_trk  TYPE fieldname,
          col_dsrc TYPE fieldname,
          lr_tab   TYPE REF TO data,
          lv_tr_in TYPE string,
          lv_tr_up TYPE string.

    FIELD-SYMBOLS: <lt_rows> TYPE STANDARD TABLE,
                   <lv_tk>   TYPE any,
                   <lv_ds>   TYPE any.

    CLEAR et_upper_names.
    lv_tr_in = any_to_str( iv_trkey ).
    IF lv_tr_in IS INITIAL.
      RETURN.
    ENDIF.
    lv_tr_up = to_upper( lv_tr_in ).

    SELECT SINGLE tabname
      FROM dd02l
      WHERE tabname  = '/GOOG/BQTR_TABLE'
        AND as4local = 'A'
      INTO @DATA(lv_bqtab).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    lt_df = get_dfies_merged( '/GOOG/BQTR_TABLE' ).
    LOOP AT lt_df INTO DATA(ls_d) WHERE datatype <> 'CLNT' AND keyflag = 'X'.
      IF col_trk IS INITIAL.
        col_trk = ls_d-fieldname.
      ELSEIF col_dsrc IS INITIAL.
        col_dsrc = ls_d-fieldname.
      ENDIF.
    ENDLOOP.

    IF col_trk IS INITIAL OR col_dsrc IS INITIAL.
      RETURN.
    ENDIF.

    CREATE DATA lr_tab TYPE STANDARD TABLE OF ('/GOOG/BQTR_TABLE').
    ASSIGN lr_tab->* TO <lt_rows>.
    SELECT * FROM ('/GOOG/BQTR_TABLE') INTO TABLE <lt_rows>.

    LOOP AT <lt_rows> ASSIGNING FIELD-SYMBOL(<ls_r>).
      UNASSIGN: <lv_tk>, <lv_ds>.
      ASSIGN COMPONENT col_trk  OF STRUCTURE <ls_r> TO <lv_tk>.
      ASSIGN COMPONENT col_dsrc OF STRUCTURE <ls_r> TO <lv_ds>.
      IF <lv_tk> IS NOT ASSIGNED OR <lv_ds> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.
      IF to_upper( any_to_str( <lv_tk> ) ) = lv_tr_up.
        DATA(lv_src_up) = to_upper( any_to_str( <lv_ds> ) ).
        IF lv_src_up IS NOT INITIAL.
          APPEND lv_src_up TO et_upper_names.
        ENDIF.
      ENDIF.
    ENDLOOP.

    SORT et_upper_names.
    DELETE ADJACENT DUPLICATES FROM et_upper_names.
  ENDMETHOD.

  METHOD routine_mentions_trkey.
    DATA lt_src TYPE rstran_t_abapsource.
    rv_match = abap_false.

    IF iv_codeid IS INITIAL OR iv_trkey IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_needle) = to_upper( any_to_str( iv_trkey ) ).
    lt_src = read_routine_lines_from_db( iv_codeid ).
    LOOP AT lt_src INTO DATA(ls_ln).
      IF to_upper( ls_ln-line ) CS lv_needle.
        rv_match = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD inspect_rsds_filter.
    DATA: lr_segfd TYPE REF TO data,
          lv_where TYPE string,
          lt_found TYPE tt_string.

    FIELD-SYMBOLS: <lt_segfd> TYPE STANDARD TABLE,
                   <lv_fnm>   TYPE any,
                   <lv_dtp>   TYPE any,
                   <lv_cls>   TYPE any,
                   <lv_slt>   TYPE any.

    CLEAR: ev_need_fix, ev_info_text.

    IF gs_rsds_sch-col_ds IS INITIAL
       OR gs_rsds_sch-col_logsys IS INITIAL
       OR ( gs_rsds_sch-col_fldclass IS INITIAL AND gs_rsds_sch-col_seltype IS INITIAL ).
      ev_info_text = 'SIN COLUMNA FILTRO DETECTADA'.
      RETURN.
    ENDIF.

    CREATE DATA lr_segfd TYPE STANDARD TABLE OF ('RSDSSEGFD').
    ASSIGN lr_segfd->* TO <lt_segfd>.

    lv_where =
      |{ gs_rsds_sch-col_ds } = { cl_abap_dyn_prg=>quote( any_to_str( iv_datasource ) ) } AND | &&
      |{ gs_rsds_sch-col_logsys } = { cl_abap_dyn_prg=>quote( any_to_str( iv_logsys ) ) } AND | &&
      |{ gs_rsds_sch-col_objvers } = 'A'|.

    SELECT * FROM ('RSDSSEGFD') INTO TABLE <lt_segfd> WHERE (lv_where).
    IF <lt_segfd> IS INITIAL.
      lv_where =
        |{ gs_rsds_sch-col_ds } = { cl_abap_dyn_prg=>quote( any_to_str( iv_datasource ) ) } AND | &&
        |{ gs_rsds_sch-col_logsys } = { cl_abap_dyn_prg=>quote( any_to_str( iv_logsys ) ) } AND | &&
        |{ gs_rsds_sch-col_objvers } = 'M'|.
      SELECT * FROM ('RSDSSEGFD') INTO TABLE <lt_segfd> WHERE (lv_where).
    ENDIF.

    LOOP AT <lt_segfd> ASSIGNING FIELD-SYMBOL(<ls_sf>).
      UNASSIGN: <lv_fnm>, <lv_dtp>, <lv_cls>, <lv_slt>.
      IF gs_rsds_sch-col_fieldnm IS NOT INITIAL.
        ASSIGN COMPONENT gs_rsds_sch-col_fieldnm OF STRUCTURE <ls_sf> TO <lv_fnm>.
      ENDIF.
      IF gs_rsds_sch-col_datatype IS NOT INITIAL.
        ASSIGN COMPONENT gs_rsds_sch-col_datatype OF STRUCTURE <ls_sf> TO <lv_dtp>.
      ENDIF.
      IF gs_rsds_sch-col_fldclass IS NOT INITIAL.
        ASSIGN COMPONENT gs_rsds_sch-col_fldclass OF STRUCTURE <ls_sf> TO <lv_cls>.
      ENDIF.
      IF gs_rsds_sch-col_seltype IS NOT INITIAL
         AND gs_rsds_sch-col_seltype <> gs_rsds_sch-col_fldclass.
        ASSIGN COMPONENT gs_rsds_sch-col_seltype OF STRUCTURE <ls_sf> TO <lv_slt>.
      ENDIF.

      DATA(lv_fnm_s) = COND string( WHEN <lv_fnm> IS ASSIGNED THEN any_to_str( <lv_fnm> ) ELSE '' ).
      DATA(lv_dtp_s) = COND string( WHEN <lv_dtp> IS ASSIGNED THEN to_upper( any_to_str( <lv_dtp> ) ) ELSE '' ).
      DATA(lv_cls_s) = COND string( WHEN <lv_cls> IS ASSIGNED THEN any_to_str( <lv_cls> ) ELSE '' ).
      DATA(lv_slt_s) = COND string( WHEN <lv_slt> IS ASSIGNED THEN any_to_str( <lv_slt> ) ELSE '' ).

      DATA(lv_hit_col) = VALUE string( ).
      DATA(lv_hit_val) = VALUE string( ).

      IF lv_cls_s IS NOT INITIAL.
        IF p_onlylg = abap_true.
          IF to_upper( lv_cls_s ) = 'L' OR lv_dtp_s = 'LANG'.
            lv_hit_col = gs_rsds_sch-col_fldclass.
            lv_hit_val = lv_cls_s.
          ENDIF.
        ELSE.
          lv_hit_col = gs_rsds_sch-col_fldclass.
          lv_hit_val = lv_cls_s.
        ENDIF.
      ENDIF.

      IF lv_hit_val IS INITIAL AND lv_slt_s IS NOT INITIAL.
        IF to_upper( lv_slt_s ) = 'L'
           OR ( lv_dtp_s = 'LANG' AND p_onlylg = abap_true )
           OR ( p_onlylg = abap_false AND gs_rsds_sch-col_seltype = 'SELTYPE' ).
          lv_hit_col = gs_rsds_sch-col_seltype.
          lv_hit_val = lv_slt_s.
        ENDIF.
      ENDIF.

      IF lv_hit_val IS NOT INITIAL.
        ev_need_fix = abap_true.
        DATA(lv_tag) = |{ lv_fnm_s }({ lv_hit_col }={ lv_hit_val })|.
        READ TABLE lt_found TRANSPORTING NO FIELDS WITH KEY table_line = lv_tag.
        IF sy-subrc <> 0.
          APPEND lv_tag TO lt_found.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF ev_need_fix = abap_true.
      CONCATENATE LINES OF lt_found INTO DATA(lv_joined) SEPARATED BY ', '.
      ev_info_text = |QUITAR: { lv_joined }|.
    ELSE.
      ev_info_text = 'OK (Sin filtro)'.
    ENDIF.
  ENDMETHOD.

  METHOD discover_bw_flows.
    TYPES:
      BEGIN OF ty_rstran_row,
        tranid       TYPE rstran-tranid,
        objvers      TYPE rstran-objvers,
        sourcetlogo  TYPE rstran-sourcetlogo,
        sourcename   TYPE rstran-sourcename,
        targettlogo  TYPE rstran-targettlogo,
        targetname   TYPE rstran-targetname,
        startroutine TYPE rstran-startroutine,
        objstat      TYPE rstran-objstat,
      END OF ty_rstran_row,

      BEGIN OF ty_dtp_row,
        dtp     TYPE rsbkdtp-dtp,
        objvers TYPE rsbkdtp-objvers,
        updmode TYPE rsbkdtp-updmode,
        src     TYPE rsbkdtp-src,
        tgt     TYPE rsbkdtp-tgt,
      END OF ty_dtp_row,

      BEGIN OF ty_chain_step,
        chain_id TYPE rspcchain-chain_id,
        objvers  TYPE rspcchain-objvers,
        type     TYPE rspcchain-type,
        variante TYPE rspcchain-variante,
      END OF ty_chain_step,

      BEGIN OF ty_chain_attr,
        chain_id TYPE rspcchainattr-chain_id,
        objvers  TYPE rspcchainattr-objvers,
      END OF ty_chain_attr.

    DATA: lt_trfn       TYPE STANDARD TABLE OF ty_rstran_row,
          lt_dtps       TYPE STANDARD TABLE OF ty_dtp_row,
          lt_ch_steps   TYPE STANDARD TABLE OF ty_chain_step,
          lt_ch_attrs   TYPE STANDARD TABLE OF ty_chain_attr,
          lt_bq_sources TYPE tt_string.

    CLEAR: ev_error_msg, gt_flows, gt_flows_view.

    IF p_trkey IS INITIAL
       AND s_adso[] IS INITIAL
       AND s_ds[] IS INITIAL
       AND s_chain[] IS INITIAL.
      ev_error_msg =
        'Indique al menos un filtro (Data Transfer P_TRKEY, ADSO S_ADSO, Fuente S_DS o Cadena S_CHAIN) para acotar el alcance.'.
      RETURN.
    ENDIF.

    IF p_trkey IS NOT INITIAL.
      collect_bqtr_datasources_by_tr(
        EXPORTING iv_trkey       = p_trkey
        IMPORTING et_upper_names = lt_bq_sources ).
    ENDIF.

    " 1. Leer Transformaciones RSDS -> ADSO (priorizando versión 'A', respaldando 'M')
    SELECT tranid, objvers, sourcetlogo, sourcename, targettlogo, targetname, startroutine, objstat
      FROM rstran
      WHERE sourcetlogo = 'RSDS'
        AND targettlogo = 'ADSO'
        AND objvers    IN ( 'A', 'M' )
        AND targetname IN @s_adso
      INTO TABLE @lt_trfn.

    IF lt_trfn IS INITIAL.
      ev_error_msg = 'No se encontraron Transformaciones BW (RSDS -> ADSO) para el filtro indicado.'.
      RETURN.
    ENDIF.

    " Ordenar para quedarnos con 'A' primero si existen 'A' y 'M' del mismo TRANID
    SORT lt_trfn BY tranid ASCENDING objvers ASCENDING.
    DELETE ADJACENT DUPLICATES FROM lt_trfn COMPARING tranid.

    " 2. Leer todos los DTPs hacia ADSOs
    SELECT dtp, objvers, updmode, src, tgt
      FROM rsbkdtp
      WHERE objvers IN ( 'A', 'M' )
        AND tgttp    = 'ADSO'
      INTO TABLE @lt_dtps.

    SORT lt_dtps BY dtp ASCENDING objvers ASCENDING.

    " 3. Leer pasos de Cadenas de Procesos (DTP Load y ADSO Activate) + cabeceras activas
    SELECT chain_id, objvers, type, variante
      FROM rspcchain
      WHERE objvers IN ( 'A', 'M' )
        AND ( type = @rspc1_c_type-dtpload OR type = @rspc1_c_type-adsoact )
      INTO TABLE @lt_ch_steps.

    SELECT chain_id, objvers
      FROM rspcchainattr
      WHERE objvers IN ( 'A', 'M' )
      INTO TABLE @lt_ch_attrs.

    SORT lt_ch_attrs BY chain_id ASCENDING objvers ASCENDING.

    " 4. Ensamblar cada flujo extremo a extremo
    LOOP AT lt_trfn INTO DATA(ls_tr).
      DATA(lv_ds_name) = CONV roosourcer( ls_tr-sourcename(30) ).
      DATA(lv_logsys)  = CONV rsslogsys( ls_tr-sourcename+30(10) ).
      DATA(lv_adso)    = CONV rsoadsonm( ls_tr-targetname ).

      IF s_ds[] IS NOT INITIAL AND NOT ( lv_ds_name IN s_ds ).
        CONTINUE.
      ENDIF.

      " Si se filtró por P_TRKEY, validar que pertenezca al Data Transfer
      " (ya sea por coincidencia de nombre base con /GOOG/BQTR_TABLE o mención en RSAABAP)
      IF p_trkey IS NOT INITIAL.
        DATA(lv_ds_up)   = to_upper( any_to_str( lv_ds_name ) ).
        DATA(lv_ds_base) = lv_ds_up.
        REPLACE FIRST OCCURRENCE OF '$F' IN lv_ds_base WITH ''.
        REPLACE FIRST OCCURRENCE OF '$P' IN lv_ds_base WITH ''.
        REPLACE FIRST OCCURRENCE OF '$T' IN lv_ds_base WITH ''.

        DATA(lv_tr_ok) = abap_false.
        IF routine_mentions_trkey( iv_codeid = ls_tr-startroutine
                                   iv_trkey  = p_trkey ) = abap_true.
          lv_tr_ok = abap_true.
        ELSEIF lt_bq_sources IS NOT INITIAL.
          READ TABLE lt_bq_sources TRANSPORTING NO FIELDS
            WITH KEY table_line = lv_ds_base BINARY SEARCH.
          IF sy-subrc = 0.
            lv_tr_ok = abap_true.
          ENDIF.
        ENDIF.

        IF lv_tr_ok = abap_false.
          CONTINUE.
        ENDIF.
      ENDIF.

      DATA(ls_flow) = VALUE ty_flow(
        adso         = lv_adso
        datasource   = lv_ds_name
        logsys       = lv_logsys
        sourcename   = ls_tr-sourcename
        tranid       = ls_tr-tranid
        startroutine = ls_tr-startroutine ).

      ls_flow-trfn_stat = COND #(
        WHEN ls_tr-objvers = 'A' AND ls_tr-objstat = 'ACT' THEN 'ACTIVA'
        ELSE 'INACTIVA' ).

      " Buscar DTP Delta ('D') y DTP Full ('F') entre esta RSDS y este ADSO
      DATA(lv_full_is_act) = abap_false.
      LOOP AT lt_dtps INTO DATA(ls_dtp)
        WHERE src = ls_tr-sourcename
          AND tgt = ls_tr-targetname.
        IF ls_dtp-updmode = 'D'.
          IF ls_flow-dtp_delta IS INITIAL OR ls_dtp-objvers = 'A'.
            ls_flow-dtp_delta = ls_dtp-dtp.
          ENDIF.
        ELSEIF ls_dtp-updmode = 'F'.
          IF ls_flow-dtp_full IS INITIAL OR ls_dtp-objvers = 'A'.
            ls_flow-dtp_full = ls_dtp-dtp.
            IF ls_dtp-objvers = 'A'.
              lv_full_is_act = abap_true.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDLOOP.

      IF ls_flow-dtp_full IS INITIAL.
        ls_flow-dtp_full_stat = 'FALTA CREAR'.
      ELSEIF lv_full_is_act = abap_true.
        ls_flow-dtp_full_stat = 'ACTIVO (OK)'.
      ELSE.
        ls_flow-dtp_full_stat = 'INACTIVO (M)'.
      ENDIF.

      " Vincular Cadena de Procesos (RSPC) por variante ADSO o DTP Delta
      DATA(lv_adso_var) = CONV rspc_variant( lv_adso ).
      DATA(lv_dtp_var)  = CONV rspc_variant( ls_flow-dtp_delta ).

      LOOP AT lt_ch_steps INTO DATA(ls_cs).
        IF ( ls_cs-type = rspc1_c_type-dtpload AND lv_dtp_var IS NOT INITIAL AND ls_cs-variante = lv_dtp_var )
           OR ( ls_cs-type = rspc1_c_type-adsoact AND ls_cs-variante = lv_adso_var ).
          ls_flow-chain_id = ls_cs-chain_id.
          IF ls_cs-objvers = 'A'.
            EXIT.
          ENDIF.
        ENDIF.
      ENDLOOP.

      IF s_chain[] IS NOT INITIAL AND NOT ( ls_flow-chain_id IN s_chain ).
        CONTINUE.
      ENDIF.

      IF ls_flow-chain_id IS INITIAL.
        ls_flow-chain_stat = 'SIN CADENA'.
      ELSE.
        READ TABLE lt_ch_attrs TRANSPORTING NO FIELDS
          WITH KEY chain_id = ls_flow-chain_id
                   objvers  = 'A' BINARY SEARCH.
        IF sy-subrc = 0.
          ls_flow-chain_stat = 'ACTIVA (A)'.
        ELSE.
          ls_flow-chain_stat = 'INACTIVA (M)'.
        ENDIF.
      ENDIF.

      " Evaluar pestaña Campos de la RSDS (Clase de campo / Idioma)
      inspect_rsds_filter(
        EXPORTING iv_datasource = ls_flow-datasource
                  iv_logsys     = ls_flow-logsys
        IMPORTING ev_need_fix   = ls_flow-ds_need_fix
                  ev_info_text  = DATA(lv_ds_inf) ).
      ls_flow-ds_filter_inf = lv_ds_inf.

      refresh_flow_status_and_colors( CHANGING cs_flow = ls_flow ).
      APPEND ls_flow TO gt_flows.
    ENDLOOP.

    SORT gt_flows BY adso ASCENDING datasource ASCENDING.

    IF gt_flows IS INITIAL.
      ev_error_msg =
        'No quedaron flujos BW tras aplicar los filtros (verifique P_TRKEY / S_ADSO / S_DS / S_CHAIN).'.
      RETURN.
    ENDIF.

    rebuild_view_table( ).
  ENDMETHOD.

  METHOD refresh_flow_status_and_colors.
    DATA: lt_todo TYPE tt_string.

    CLEAR cs_flow-t_color.

    " Colorear Paso 1: RSDS
    IF cs_flow-ds_need_fix = abap_true.
      add_cell_color( EXPORTING iv_fname = 'DS_FILTER_INF' iv_col = 3 iv_int = 1
                      CHANGING  ct_color = cs_flow-t_color ).
      IF p_s1_ds = abap_true.
        APPEND '1:Filtro RSDS' TO lt_todo.
      ENDIF.
    ELSE.
      add_cell_color( EXPORTING iv_fname = 'DS_FILTER_INF' iv_col = 5 iv_int = 0
                      CHANGING  ct_color = cs_flow-t_color ).
    ENDIF.

    " Colorear Paso 2: TRFN + Rutina
    IF cs_flow-trfn_stat = 'ACTIVA (SYNC)'.
      add_cell_color( EXPORTING iv_fname = 'TRFN_STAT' iv_col = 5 iv_int = 1
                      CHANGING  ct_color = cs_flow-t_color ).
    ELSEIF cs_flow-trfn_stat = 'ACTIVA'.
      add_cell_color( EXPORTING iv_fname = 'TRFN_STAT' iv_col = 3 iv_int = 0
                      CHANGING  ct_color = cs_flow-t_color ).
      IF p_s2_tr = abap_true.
        APPEND '2:Re-guardar Rutina/TRFN' TO lt_todo.
      ENDIF.
    ELSE.
      add_cell_color( EXPORTING iv_fname = 'TRFN_STAT' iv_col = 6 iv_int = 1
                      CHANGING  ct_color = cs_flow-t_color ).
      IF p_s2_tr = abap_true.
        APPEND '2:Activar TRFN' TO lt_todo.
      ENDIF.
    ENDIF.

    " Colorear Paso 3: DTP Full
    IF cs_flow-dtp_full_stat = 'ACTIVO (OK)'.
      add_cell_color( EXPORTING iv_fname = 'DTP_FULL_STAT' iv_col = 5 iv_int = 0
                      CHANGING  ct_color = cs_flow-t_color ).
    ELSE.
      add_cell_color( EXPORTING iv_fname = 'DTP_FULL_STAT' iv_col = 3 iv_int = 1
                      CHANGING  ct_color = cs_flow-t_color ).
      IF p_s3_dt = abap_true.
        APPEND '3:Crear DTP Full' TO lt_todo.
      ENDIF.
    ENDIF.

    " Colorear Paso 4: Cadena RSPC
    IF cs_flow-chain_stat = 'ACTIVA (A)'.
      add_cell_color( EXPORTING iv_fname = 'CHAIN_STAT' iv_col = 5 iv_int = 0
                      CHANGING  ct_color = cs_flow-t_color ).
    ELSEIF cs_flow-chain_stat = 'INACTIVA (M)'.
      add_cell_color( EXPORTING iv_fname = 'CHAIN_STAT' iv_col = 3 iv_int = 1
                      CHANGING  ct_color = cs_flow-t_color ).
      IF p_s4_pc = abap_true.
        APPEND '4:Activar Cadena' TO lt_todo.
      ENDIF.
    ELSE.
      add_cell_color( EXPORTING iv_fname = 'CHAIN_STAT' iv_col = 7 iv_int = 0
                      CHANGING  ct_color = cs_flow-t_color ).
    ENDIF.

    IF lt_todo IS NOT INITIAL.
      cs_flow-estado_global = 'PENDIENTE PROCESAR'.
      IF cs_flow-accion_res IS INITIAL OR cs_flow-accion_res CP 'Pendiente:*'.
        CONCATENATE LINES OF lt_todo INTO DATA(lv_todo_txt) SEPARATED BY ' + '.
        cs_flow-accion_res = |Pendiente: { lv_todo_txt } (Doble clic = Ejecutar esta fila)|.
      ENDIF.
      add_cell_color( EXPORTING iv_fname = 'ESTADO_GLOBAL' iv_col = 3 iv_int = 1
                      CHANGING  ct_color = cs_flow-t_color ).
    ELSE.
      cs_flow-estado_global = 'LISTO (100% OK)'.
      IF cs_flow-accion_res IS INITIAL OR cs_flow-accion_res CP 'Pendiente:*'.
        cs_flow-accion_res = 'OK - Todos los pasos seleccionados están listos'.
      ENDIF.
      add_cell_color( EXPORTING iv_fname = 'ESTADO_GLOBAL' iv_col = 5 iv_int = 1
                      CHANGING  ct_color = cs_flow-t_color ).
    ENDIF.
  ENDMETHOD.

  METHOD rebuild_view_table.
    CLEAR gt_flows_view.
    IF p_onlyp = abap_true.
      LOOP AT gt_flows INTO DATA(ls_f)
        WHERE estado_global <> 'LISTO (100% OK)'.
        APPEND ls_f TO gt_flows_view.
      ENDLOOP.
    ELSE.
      gt_flows_view = gt_flows.
    ENDIF.
  ENDMETHOD.

  METHOD step1_fix_and_activate_rsds.
    DATA: lr_segfd TYPE REF TO data,
          lr_upd   TYPE REF TO data,
          lv_where TYPE string,
          lo_ds    TYPE REF TO cl_rsds_rsds,
          lv_subrc TYPE sysubrc,
          lv_cto   TYPE rs_bool,
          lx_err   TYPE REF TO cx_root.

    FIELD-SYMBOLS: <lt_segfd> TYPE STANDARD TABLE,
                   <lt_upd>   TYPE STANDARD TABLE,
                   <lv_dtp>   TYPE any,
                   <lv_cls>   TYPE any,
                   <lv_slt>   TYPE any.

    CLEAR: ev_changed, ev_msg, ev_error.

    IF is_flow-ds_need_fix = abap_false.
      ev_msg = 'RSDS sin filtro'.
      RETURN.
    ENDIF.

    lv_cto = COND rs_bool( WHEN p_cto = abap_true THEN rs_c_true ELSE rs_c_false ).

    CREATE DATA lr_segfd TYPE STANDARD TABLE OF ('RSDSSEGFD').
    ASSIGN lr_segfd->* TO <lt_segfd>.
    CREATE DATA lr_upd TYPE STANDARD TABLE OF ('RSDSSEGFD').
    ASSIGN lr_upd->* TO <lt_upd>.

    lv_where =
      |{ gs_rsds_sch-col_ds } = { cl_abap_dyn_prg=>quote( any_to_str( is_flow-datasource ) ) } AND | &&
      |{ gs_rsds_sch-col_logsys } = { cl_abap_dyn_prg=>quote( any_to_str( is_flow-logsys ) ) }|.

    SELECT * FROM ('RSDSSEGFD') INTO TABLE <lt_segfd> WHERE (lv_where).

    LOOP AT <lt_segfd> ASSIGNING FIELD-SYMBOL(<ls_sf>).
      UNASSIGN: <lv_dtp>, <lv_cls>, <lv_slt>.
      IF gs_rsds_sch-col_datatype IS NOT INITIAL.
        ASSIGN COMPONENT gs_rsds_sch-col_datatype OF STRUCTURE <ls_sf> TO <lv_dtp>.
      ENDIF.
      IF gs_rsds_sch-col_fldclass IS NOT INITIAL.
        ASSIGN COMPONENT gs_rsds_sch-col_fldclass OF STRUCTURE <ls_sf> TO <lv_cls>.
      ENDIF.
      IF gs_rsds_sch-col_seltype IS NOT INITIAL
         AND gs_rsds_sch-col_seltype <> gs_rsds_sch-col_fldclass.
        ASSIGN COMPONENT gs_rsds_sch-col_seltype OF STRUCTURE <ls_sf> TO <lv_slt>.
      ENDIF.

      DATA(lv_dtp_s) = COND string(
        WHEN <lv_dtp> IS ASSIGNED THEN to_upper( any_to_str( <lv_dtp> ) ) ELSE '' ).
      DATA(lv_row_chg) = abap_false.

      IF <lv_cls> IS ASSIGNED AND any_to_str( <lv_cls> ) IS NOT INITIAL.
        IF p_onlylg = abap_false
           OR to_upper( any_to_str( <lv_cls> ) ) = 'L'
           OR lv_dtp_s = 'LANG'.
          CLEAR <lv_cls>.
          lv_row_chg = abap_true.
        ENDIF.
      ENDIF.

      IF <lv_slt> IS ASSIGNED AND any_to_str( <lv_slt> ) IS NOT INITIAL.
        IF to_upper( any_to_str( <lv_slt> ) ) = 'L'
           OR ( lv_dtp_s = 'LANG' AND p_onlylg = abap_true )
           OR ( p_onlylg = abap_false AND gs_rsds_sch-col_seltype = 'SELTYPE' ).
          CLEAR <lv_slt>.
          lv_row_chg = abap_true.
        ENDIF.
      ENDIF.

      IF lv_row_chg = abap_true.
        APPEND <ls_sf> TO <lt_upd>.
      ENDIF.
    ENDLOOP.

    IF <lt_upd> IS NOT INITIAL.
      MODIFY ('RSDSSEGFD') FROM TABLE <lt_upd>.
      COMMIT WORK AND WAIT.
    ENDIF.

    " Instanciar CL_RSDS_RSDS con la versión limpia en BD, guardar y activar
    TRY.
        CALL METHOD cl_rsds_rsds=>create_object
          EXPORTING
            i_datasource   = is_flow-datasource
            i_logsys       = is_flow-logsys
            i_new          = rs_c_false
            i_modify       = rs_c_true
            i_with_cto     = lv_cto
          RECEIVING
            r_r_datasource = lo_ds.

        lo_ds->if_rso_tlogo_maintain~prepare( ).

        lo_ds->if_rso_tlogo_maintain~save(
          EXPORTING
            i_with_cto = lv_cto ).

        cl_rso_application_log=>appl_log_delete( ).

        lo_ds->if_rso_tlogo_maintain~activate(
          EXPORTING
            i_with_cto = lv_cto
          IMPORTING
            e_subrc    = lv_subrc ).

        IF lv_subrc <> 0.
          ev_error = abap_true.
          ev_msg   = |Error activar RSDS (subrc={ lv_subrc })|.
          ROLLBACK WORK.
          RETURN.
        ENDIF.

        COMMIT WORK AND WAIT.

        " Reasegurar que la versión 'A' en RSDSSEGFD quedó en blanco tras activar
        IF <lt_upd> IS NOT INITIAL.
          MODIFY ('RSDSSEGFD') FROM TABLE <lt_upd>.
          COMMIT WORK AND WAIT.
        ENDIF.

        ev_changed = abap_true.
        ev_msg     = 'RSDS filtro quitado y activada'.
      CATCH cx_root INTO lx_err.
        ev_error = abap_true.
        ev_msg   = |Excepción RSDS: { lx_err->get_text( ) }|.
        ROLLBACK WORK.
    ENDTRY.
  ENDMETHOD.

  METHOD read_routine_lines_from_db.
    DATA: lr_abap  TYPE REF TO data,
          lv_where TYPE string.

    FIELD-SYMBOLS: <lt_abap> TYPE STANDARD TABLE,
                   <lv_line> TYPE any.

    CLEAR rt_lines.
    IF iv_codeid IS INITIAL
       OR gs_abap_sch-col_codeid IS INITIAL
       OR gs_abap_sch-col_line IS INITIAL.
      RETURN.
    ENDIF.

    CREATE DATA lr_abap TYPE STANDARD TABLE OF ('RSAABAP').
    ASSIGN lr_abap->* TO <lt_abap>.

    lv_where =
      |{ gs_abap_sch-col_codeid } = { cl_abap_dyn_prg=>quote( any_to_str( iv_codeid ) ) } AND | &&
      |{ gs_abap_sch-col_objvers } = 'A'|.
    SELECT * FROM ('RSAABAP') INTO TABLE <lt_abap> WHERE (lv_where).

    IF <lt_abap> IS INITIAL.
      lv_where =
        |{ gs_abap_sch-col_codeid } = { cl_abap_dyn_prg=>quote( any_to_str( iv_codeid ) ) } AND | &&
        |{ gs_abap_sch-col_objvers } = 'M'|.
      SELECT * FROM ('RSAABAP') INTO TABLE <lt_abap> WHERE (lv_where).
    ENDIF.

    IF <lt_abap> IS INITIAL.
      RETURN.
    ENDIF.

    IF gs_abap_sch-col_lineno IS NOT INITIAL.
      SORT <lt_abap> BY (gs_abap_sch-col_lineno) ASCENDING.
    ENDIF.

    LOOP AT <lt_abap> ASSIGNING FIELD-SYMBOL(<ls_row>).
      UNASSIGN <lv_line>.
      ASSIGN COMPONENT gs_abap_sch-col_line OF STRUCTURE <ls_row> TO <lv_line>.
      IF sy-subrc = 0 AND <lv_line> IS ASSIGNED.
        DATA(ls_src) = VALUE abapsource( ).
        ls_src-line = <lv_line>.
        APPEND ls_src TO rt_lines.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD step2_touch_and_activate_trfn.
    DATA: ls_source        TYPE rstran_s_tlogo,
          ls_target        TYPE rstran_s_tlogo,
          lo_trfn          TYPE REF TO cl_rstran_trfn,
          lo_routine_start TYPE REF TO cl_rstran_step_rout,
          lv_codeid_start  TYPE rscodeid,
          lt_abap_source   TYPE rstran_t_abapsource,
          ls_touch_line    TYPE abapsource,
          lv_subrc         TYPE sysubrc,
          lv_cto           TYPE rs_bool,
          lx_err           TYPE REF TO cx_root.

    CLEAR: ev_msg, ev_error.
    lv_cto = COND rs_bool( WHEN p_cto = abap_true THEN rs_c_true ELSE rs_c_false ).

    ls_source-tlogo = 'RSDS'.
    ls_source-objnm = is_flow-sourcename.
    ls_target-tlogo = 'ADSO'.
    ls_target-objnm = is_flow-adso.

    TRY.
        lo_trfn = cl_rstran_trfn=>factory(
          EXPORTING
            i_s_source = ls_source
            i_s_target = ls_target ).

        lo_trfn->if_rso_tlogo_maintain~prepare( ).

        lo_routine_start = lo_trfn->get_start_routine( ).
        IF lo_routine_start IS BOUND.
          lo_routine_start->get_codeid(
            IMPORTING
              e_codid = lv_codeid_start ).

          IF lv_codeid_start IS NOT INITIAL.
            lt_abap_source = read_routine_lines_from_db( lv_codeid_start ).
            IF lt_abap_source IS NOT INITIAL.
              " Toque idempotente: actualiza marca final o agrega un comentario/espacio
              " sin acumular líneas basura en ejecuciones repetidas
              ls_touch_line-line = |*" BQTR-SYNC { sy-datum }-{ sy-uzeit } |.
              DATA(lv_cnt) = lines( lt_abap_source ).
              READ TABLE lt_abap_source ASSIGNING FIELD-SYMBOL(<ls_last>) INDEX lv_cnt.
              IF sy-subrc = 0 AND <ls_last>-line CP '*" BQTR-SYNC*'.
                <ls_last>-line = ls_touch_line-line.
              ELSE.
                APPEND ls_touch_line TO lt_abap_source.
              ENDIF.

              lo_routine_start->store_routine(
                i_codeid   = lv_codeid_start
                i_t_source = lt_abap_source ).
            ENDIF.
          ENDIF.
        ENDIF.

        lo_trfn->if_rso_tlogo_maintain~save(
          EXPORTING
            i_with_cto = lv_cto
          IMPORTING
            e_subrc    = lv_subrc ).

        IF lv_subrc <> 0.
          ev_error = abap_true.
          ev_msg   = |Error guardar TRFN (subrc={ lv_subrc })|.
          ROLLBACK WORK.
          RETURN.
        ENDIF.

        lo_trfn->if_rso_tlogo_maintain~activate(
          EXPORTING
            i_force_activation = abap_true
            i_with_cto         = lv_cto
          IMPORTING
            e_subrc            = lv_subrc ).

        IF lv_subrc <> 0.
          ev_error = abap_true.
          ev_msg   = |Error activar TRFN (subrc={ lv_subrc })|.
          ROLLBACK WORK.
          RETURN.
        ENDIF.

        COMMIT WORK AND WAIT.
        ev_msg = 'TRFN+Rutina guardada y activada'.
      CATCH cx_root INTO lx_err.
        ev_error = abap_true.
        ev_msg   = |Excepción TRFN: { lx_err->get_text( ) }|.
        ROLLBACK WORK.
    ENDTRY.
  ENDMETHOD.

  METHOD step3_ensure_full_dtp.
    DATA: lo_dtp         TYPE REF TO cl_rsbk_dtp,
          lv_dtpnm_empty TYPE rsbkdtpnm,
          ls_dtp         TYPE rsbkdtp,
          lo_collection  TYPE REF TO cl_rsbk_dtp_collection,
          lv_objnm       TYPE sobj_name,
          ls_tlogo       TYPE rstran_s_tlogo,
          lt_tlogo       TYPE rstran_t_tlogo,
          lv_updmode     TYPE rsbupdmode VALUE 'F',
          lv_cto         TYPE rs_bool,
          lx_err         TYPE REF TO cx_root.

    CLEAR: ev_dtp_full, ev_created, ev_msg, ev_error.
    lv_cto = COND rs_bool( WHEN p_cto = abap_true THEN rs_c_true ELSE rs_c_false ).

    " 1. Si ya existe un DTP Full activo, no duplicar
    IF is_flow-dtp_full IS NOT INITIAL AND is_flow-dtp_full_stat = 'ACTIVO (OK)'.
      ev_dtp_full = is_flow-dtp_full.
      ev_msg      = |DTP Full ya activo ({ is_flow-dtp_full })|.
      RETURN.
    ENDIF.

    TRY.
        IF is_flow-dtp_full IS NOT INITIAL.
          " Existe en versión M inactiva -> solo activar
          lv_objnm    = is_flow-dtp_full.
          ev_dtp_full = is_flow-dtp_full.

          CREATE OBJECT lo_collection.
          lo_collection->add_tlogo( EXPORTING i_objnm = lv_objnm ).
          lo_collection->activate(
            EXPORTING
              i_with_cto            = lv_cto
              i_force_activation    = abap_true
              i_show_check_protocol = abap_false
              i_with_check          = abap_false ).
          COMMIT WORK AND WAIT.
          ev_created = abap_true.
          ev_msg     = |DTP Full activado ({ ev_dtp_full })|.
          RETURN.
        ENDIF.

        " 2. Crear nuevo DTP Full (extracción directa desde RSDS ODP sin PSA)
        ls_tlogo-tlogo = 'RSDS'.
        ls_tlogo-objnm = is_flow-sourcename.
        APPEND ls_tlogo TO lt_tlogo.

        ls_tlogo-tlogo = 'TRFN'.
        ls_tlogo-objnm = is_flow-tranid.
        APPEND ls_tlogo TO lt_tlogo.

        ls_tlogo-tlogo = 'ADSO'.
        ls_tlogo-objnm = is_flow-adso.
        APPEND ls_tlogo TO lt_tlogo.

        lo_dtp = cl_rsbk_dtp=>factory( i_dtp = lv_dtpnm_empty ).
        lo_dtp->copy_nvers_from_tlogo_list( i_t_tlogo = lt_tlogo ).
        lo_dtp->if_rsbk_dtp_maintain~set_updmode( lv_updmode ).

        ls_dtp      = lo_dtp->if_rsbk_dtp_display~get_dtp( ).
        lv_objnm    = ls_dtp-dtp.
        ev_dtp_full = ls_dtp-dtp.

        CREATE OBJECT lo_collection.
        lo_collection->add_tlogo( EXPORTING i_objnm = lv_objnm ).
        lo_collection->save( EXPORTING i_with_cto = lv_cto ).
        lo_collection->activate(
          EXPORTING
            i_with_cto            = lv_cto
            i_force_activation    = abap_true
            i_show_check_protocol = abap_false
            i_with_check          = abap_false ).

        lo_dtp->dequeue_dtp_for_request( ).
        COMMIT WORK AND WAIT.

        ev_created = abap_true.
        ev_msg     = |DTP Full creado ({ ev_dtp_full })|.
      CATCH cx_root INTO lx_err.
        ev_error = abap_true.
        ev_msg   = |Excepción DTP Full: { lx_err->get_text( ) }|.
        ROLLBACK WORK.
    ENDTRY.
  ENDMETHOD.

  METHOD step4_activate_chain_no_sched.
    DATA: lo_chain   TYPE REF TO cl_rspc_chain,
          lt_variant TYPE rspc_t_variante,
          lv_act_chk TYPE rspcchainattr-chain_id.

    CLEAR: ev_msg, ev_error.

    IF is_flow-chain_id IS INITIAL.
      ev_msg = 'Sin cadena asociada'.
      RETURN.
    ENDIF.

    CREATE OBJECT lo_chain
      EXPORTING
        i_chain         = is_flow-chain_id
        i_objvers       = rs_c_objvers-modified
        i_t_variant     = lt_variant
        i_with_dialog   = ''
        i_new           = abap_false
      EXCEPTIONS
        aborted_by_user = 1
        not_unique      = 2
        wrong_name      = 3
        display_only    = 4
        OTHERS          = 5.

    IF sy-subrc <> 0 OR lo_chain IS NOT BOUND.
      ev_error = abap_true.
      ev_msg   = |No se pudo abrir cadena { is_flow-chain_id } (subrc={ sy-subrc })|.
      RETURN.
    ENDIF.

    " Activa metadatos ('M' -> 'A') SIN invocar schedule/start (no planifica en SM37)
    lo_chain->activate(
      IMPORTING
        e_t_conflicts = DATA(lt_co)
      EXCEPTIONS
        errors        = 1
        warnings      = 2
        OTHERS        = 3 ).

    IF sy-subrc = 1 OR sy-subrc = 3.
      ev_error = abap_true.
      ev_msg   = |Error al activar cadena { is_flow-chain_id } (conflictos={ lines( lt_co ) })|.
      ROLLBACK WORK.
      RETURN.
    ENDIF.

    COMMIT WORK AND WAIT.

    SELECT SINGLE chain_id
      FROM rspcchainattr
      WHERE chain_id = @is_flow-chain_id
        AND objvers  = 'A'
      INTO @lv_act_chk.

    IF sy-subrc = 0.
      ev_msg = |Cadena { is_flow-chain_id } activa (sin planificar)|.
    ELSE.
      ev_error = abap_true.
      ev_msg   = |Cadena { is_flow-chain_id } no registró versión A en RSPCCHAINATTR|.
    ENDIF.
  ENDMETHOD.

  METHOD process_single_flow.
    DATA: lt_msgs  TYPE tt_string,
          lv_err   TYPE abap_bool,
          lv_s_msg TYPE string.

    CLEAR ev_error.

    " 1º Fuente de Datos (RSDS) - ANTES de TRFN para no desactivar la transformación
    IF p_s1_ds = abap_true AND cs_flow-ds_need_fix = abap_true.
      step1_fix_and_activate_rsds(
        EXPORTING is_flow    = cs_flow
        IMPORTING ev_changed = DATA(lv_ds_chg)
                  ev_msg     = lv_s_msg
                  ev_error   = lv_err ).
      APPEND lv_s_msg TO lt_msgs.
      IF lv_err = abap_true.
        ev_error = abap_true.
      ELSEIF lv_ds_chg = abap_true.
        cs_flow-ds_need_fix   = abap_false.
        cs_flow-ds_filter_inf = 'OK (Filtro eliminado)'.
      ENDIF.
    ENDIF.

    " 2º Transformación + Start Routine
    IF p_s2_tr = abap_true AND ev_error = abap_false.
      step2_touch_and_activate_trfn(
        EXPORTING is_flow  = cs_flow
        IMPORTING ev_msg   = lv_s_msg
                  ev_error = lv_err ).
      APPEND lv_s_msg TO lt_msgs.
      IF lv_err = abap_true.
        ev_error = abap_true.
      ELSE.
        cs_flow-trfn_stat = 'ACTIVA (SYNC)'.
      ENDIF.
    ENDIF.

    " 3º Crear / Activar DTP Full (directo sin PSA)
    IF p_s3_dt = abap_true AND ev_error = abap_false.
      step3_ensure_full_dtp(
        EXPORTING is_flow     = cs_flow
        IMPORTING ev_dtp_full = DATA(lv_new_dtp)
                  ev_msg      = lv_s_msg
                  ev_error    = lv_err ).
      APPEND lv_s_msg TO lt_msgs.
      IF lv_err = abap_true.
        ev_error = abap_true.
      ELSEIF lv_new_dtp IS NOT INITIAL.
        cs_flow-dtp_full      = lv_new_dtp.
        cs_flow-dtp_full_stat = 'ACTIVO (OK)'.
      ENDIF.
    ENDIF.

    " 4º Activar Cadena de Procesos RSPC (sin planificar)
    IF p_s4_pc = abap_true AND ev_error = abap_false AND cs_flow-chain_id IS NOT INITIAL.
      step4_activate_chain_no_sched(
        EXPORTING is_flow  = cs_flow
        IMPORTING ev_msg   = lv_s_msg
                  ev_error = lv_err ).
      APPEND lv_s_msg TO lt_msgs.
      IF lv_err = abap_true.
        ev_error = abap_true.
      ELSE.
        cs_flow-chain_stat = 'ACTIVA (A)'.
      ENDIF.
    ENDIF.

    CONCATENATE LINES OF lt_msgs INTO DATA(lv_summary_msg) SEPARATED BY ' | '.
    cs_flow-accion_res = lv_summary_msg.

    refresh_flow_status_and_colors( CHANGING cs_flow = cs_flow ).
    IF ev_error = abap_true.
      cs_flow-estado_global = 'CON ERROR (REVISAR)'.
      DELETE cs_flow-t_color WHERE fname = 'ESTADO_GLOBAL' OR fname = 'ACCION_RES'.
      add_cell_color( EXPORTING iv_fname = 'ESTADO_GLOBAL' iv_col = 6 iv_int = 1
                      CHANGING  ct_color = cs_flow-t_color ).
      add_cell_color( EXPORTING iv_fname = 'ACCION_RES'    iv_col = 6 iv_int = 0
                      CHANGING  ct_color = cs_flow-t_color ).
    ENDIF.
  ENDMETHOD.

  METHOD execute_mass_processing.
    DATA: lv_cand  TYPE i VALUE 0,
          lv_ans   TYPE c LENGTH 1,
          lv_title TYPE c LENGTH 70,
          lv_quest TYPE c LENGTH 250,
          lv_idx   TYPE i VALUE 0,
          lv_pct   TYPE i,
          lv_ok    TYPE i VALUE 0,
          lv_errc  TYPE i VALUE 0.

    LOOP AT gt_flows INTO DATA(ls_chk)
      WHERE estado_global = 'PENDIENTE PROCESAR'.
      lv_cand = lv_cand + 1.
    ENDLOOP.

    IF lv_cand = 0.
      MESSAGE 'Todos los flujos evaluados ya cumplen los pasos seleccionados.' TYPE 'S'.
      RETURN.
    ENDIF.

    lv_title = 'Ejecución Masiva Post-Generación BW'.
    lv_quest =
      |Se procesarán { lv_cand } flujos BW (RSDS -> TRFN/Rutina -> DTP Full -> RSPC sin planificar). ¿Ejecutar ahora?|.

    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = lv_title
        text_question         = lv_quest
        text_button_1         = 'Sí, Ejecutar'
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

    LOOP AT gt_flows ASSIGNING FIELD-SYMBOL(<fs_flow>)
      WHERE estado_global = 'PENDIENTE PROCESAR'.
      lv_idx = lv_idx + 1.
      lv_pct = ( lv_idx * 100 ) / lv_cand.
      show_progress(
        iv_pct  = lv_pct
        iv_text = |[{ lv_idx }/{ lv_cand }] Procesando ADSO { <fs_flow>-adso } ({ <fs_flow>-datasource })...| ).

      process_single_flow(
        IMPORTING ev_error = DATA(lv_has_err)
        CHANGING  cs_flow  = <fs_flow> ).

      IF lv_has_err = abap_true.
        lv_errc = lv_errc + 1.
      ELSE.
        lv_ok = lv_ok + 1.
      ENDIF.
    ENDLOOP.

    rebuild_view_table( ).

    IF lv_errc = 0.
      MESSAGE |Proceso finalizado OK: { lv_ok } flujos BW actualizados y activados.| TYPE 'S'.
    ELSE.
      MESSAGE
        |Proceso finalizado: { lv_ok } flujos OK, { lv_errc } con observaciones (revisar columna Acción).|
        TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.
  ENDMETHOD.

  METHOD prompt_single_flow_action.
    DATA: lv_ans   TYPE c LENGTH 1,
          lv_title TYPE c LENGTH 70,
          lv_quest TYPE c LENGTH 250.

    READ TABLE gt_flows ASSIGNING FIELD-SYMBOL(<fs_flow>)
      WITH KEY adso       = iv_adso
               sourcename = iv_sourcename.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    lv_title = |Ejecutar Flujo BW: { iv_adso }|.
    lv_quest =
      |¿Ejecutar los pasos marcados (RSDS / TRFN+Rutina / DTP Full / Cadena RSPC) solo para el ADSO { iv_adso } ({ <fs_flow>-datasource })?|.

    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = lv_title
        text_question         = lv_quest
        text_button_1         = 'Ejecutar Flujo'
        text_button_2         = 'Ver Start Routine'
        default_button        = '1'
        display_cancel_button = 'X'
      IMPORTING
        answer                = lv_ans
      EXCEPTIONS
        OTHERS                = 1.

    IF lv_ans = '2'.
      preview_start_routine( <fs_flow> ).
      RETURN.
    ELSEIF lv_ans <> '1'.
      RETURN.
    ENDIF.

    show_progress(
      iv_pct  = 50
      iv_text = |Procesando flujo individual { iv_adso }...| ).

    process_single_flow(
      IMPORTING ev_error = DATA(lv_err)
      CHANGING  cs_flow  = <fs_flow> ).

    rebuild_view_table( ).

    IF go_salv IS BOUND.
      go_salv->set_top_of_list( build_alv_header( ) ).
      go_salv->refresh( ).
    ENDIF.

    IF lv_err = abap_false.
      MESSAGE |{ iv_adso }: { <fs_flow>-accion_res }| TYPE 'S'.
    ELSE.
      MESSAGE |{ iv_adso }: { <fs_flow>-accion_res }| TYPE 'I' DISPLAY LIKE 'E'.
    ENDIF.
  ENDMETHOD.

  METHOD preview_start_routine.
    IF is_flow-startroutine IS INITIAL.
      MESSAGE |La transformación { is_flow-tranid } no tiene Start Routine asignada.| TYPE 'I'.
      RETURN.
    ENDIF.

    DATA(lt_code) = read_routine_lines_from_db( is_flow-startroutine ).
    IF lt_code IS INITIAL.
      MESSAGE |No se halló código en RSAABAP para CODEID { is_flow-startroutine }.| TYPE 'I'.
      RETURN.
    ENDIF.

    cl_demo_output=>display_data(
      value = lt_code
      name  = |Start Routine de { is_flow-adso } (TRANID: { is_flow-tranid })| ).
  ENDMETHOD.

  METHOD on_double_click.
    IF row <= 0.
      RETURN.
    ENDIF.

    READ TABLE gt_flows_view INTO DATA(ls_v) INDEX row.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    IF column = 'TRANID' OR column = 'STARTROUTINE'.
      preview_start_routine( ls_v ).
    ELSE.
      prompt_single_flow_action(
        iv_adso       = ls_v-adso
        iv_sourcename = ls_v-sourcename ).
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
    DATA: lv_tot      TYPE i,
          lv_ds_pend  TYPE i,
          lv_dtp_pend TYPE i,
          lv_pc_pend  TYPE i,
          lv_ok_all   TYPE i,
          lv_h1       TYPE string,
          lv_h2       TYPE string,
          lv_h3       TYPE string,
          lv_h4       TYPE string.

    lv_tot = lines( gt_flows ).
    LOOP AT gt_flows INTO DATA(ls_f).
      IF ls_f-ds_need_fix = abap_true.
        lv_ds_pend = lv_ds_pend + 1.
      ENDIF.
      IF ls_f-dtp_full_stat <> 'ACTIVO (OK)'.
        lv_dtp_pend = lv_dtp_pend + 1.
      ENDIF.
      IF ls_f-chain_stat = 'INACTIVA (M)'.
        lv_pc_pend = lv_pc_pend + 1.
      ENDIF.
      IF ls_f-estado_global = 'LISTO (100% OK)'.
        lv_ok_all = lv_ok_all + 1.
      ENDIF.
    ENDLOOP.

    DATA(lv_tr_lbl) = COND string(
      WHEN p_trkey IS NOT INITIAL THEN any_to_str( p_trkey ) ELSE '(Todos los filtrados)' ).
    DATA(lv_cls_col) = COND string(
      WHEN gs_rsds_sch-col_fldclass IS NOT INITIAL THEN gs_rsds_sch-col_fldclass ELSE '(N/A)' ).

    lv_h1 = |Post-Configuración Artefactos BW -> BigQuery  [Transfer: { lv_tr_lbl }]|.
    lv_h2 =
      |Flujos BW: { lv_tot }  | &&
      |(RSDS con filtro: { lv_ds_pend }  | &&
      |Falta DTP Full: { lv_dtp_pend }  | &&
      |Cadenas inactivas M: { lv_pc_pend }  | &&
      |Listos OK: { lv_ok_all })|.
    lv_h3 =
      |Orden automático seguro: 1º RSDS (col. { lv_cls_col }) -> 2º TRFN + Start Routine -> 3º DTP Full (sin PSA) -> 4º Activar RSPC (sin planificar)|.
    lv_h4 =
      'Atajos Doble Clic: [Estado / ADSO / Acción] = Ejecutar solo ese flujo en vivo  |  [Transformación / Start Routine] = Ver código ABAP'.

    CREATE OBJECT ro_grid.
    ro_grid->create_header_information( row = 1 column = 1 text = lv_h1 tooltip = lv_h1 ).
    ro_grid->create_text( row = 2 column = 1 text = lv_h2 ).
    ro_grid->create_text( row = 3 column = 1 text = lv_h3 ).
    ro_grid->create_text( row = 4 column = 1 text = lv_h4 ).
  ENDMETHOD.

  METHOD display_alv.
    IF gt_flows_view IS INITIAL.
      MESSAGE 'Todos los flujos están listos (desmarque P_ONLYP para visualizar la lista completa).'
        TYPE 'S'.
      gt_flows_view = gt_flows.
    ENDIF.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = go_salv
          CHANGING  t_table      = gt_flows_view ).

        go_salv->get_functions( )->set_all( abap_true ).
        go_salv->get_display_settings( )->set_striped_pattern( abap_true ).
        go_salv->set_top_of_list( build_alv_header( ) ).

        DATA(lo_cols) = go_salv->get_columns( ).
        lo_cols->set_optimize( abap_true ).
        TRY.
            lo_cols->set_color_column( 'T_COLOR' ).
          CATCH cx_salv_data_error.
        ENDTRY.

        TRY.
            lo_cols->get_column( 'SOURCENAME' )->set_visible( if_salv_c_bool_sap=>false ).
            lo_cols->get_column( 'DS_NEED_FIX' )->set_visible( if_salv_c_bool_sap=>false ).
          CATCH cx_salv_not_found.
        ENDTRY.

        set_col_text( io_cols = lo_cols iv_col = 'ADSO'          iv_s = 'ADSO'       iv_m = 'ADSO Destino'        iv_l = 'ADSO Destino (Doble clic=Ejecutar)' ).
        set_col_text( io_cols = lo_cols iv_col = 'DATASOURCE'    iv_s = 'Fuente'     iv_m = 'Fuente Datos RSDS'   iv_l = 'Fuente de Datos BW (RSDS)' ).
        set_col_text( io_cols = lo_cols iv_col = 'LOGSYS'        iv_s = 'Sist.Lóg.'  iv_m = 'Sistema Lógico'      iv_l = 'Sistema Lógico Fuente' ).
        set_col_text( io_cols = lo_cols iv_col = 'DS_FILTER_INF' iv_s = '1.FiltroDS' iv_m = '1.Filtro RSDS'       iv_l = '1. Pestaña Campos RSDS (Clase Campo)' ).
        set_col_text( io_cols = lo_cols iv_col = 'TRANID'        iv_s = '2.Transf.'  iv_m = '2.Transformación'    iv_l = '2. ID Transformación (Doble clic=Código)' ).
        set_col_text( io_cols = lo_cols iv_col = 'TRFN_STAT'     iv_s = 'Est.TRFN'   iv_m = 'Estado TRFN'         iv_l = 'Estado Transformación + Start Routine' ).
        set_col_text( io_cols = lo_cols iv_col = 'STARTROUTINE'  iv_s = 'StartRout.' iv_m = 'ID Start Routine'    iv_l = 'CODEID Start Routine (Doble clic=Código)' ).
        set_col_text( io_cols = lo_cols iv_col = 'DTP_DELTA'     iv_s = 'DTP Delta'  iv_m = 'DTP Delta Exist.'    iv_l = 'DTP Delta Generado por Toolkit' ).
        set_col_text( io_cols = lo_cols iv_col = 'DTP_FULL'      iv_s = '3.DTP Full' iv_m = '3.DTP Full'          iv_l = '3. DTP Full (Directo sin PSA)' ).
        set_col_text( io_cols = lo_cols iv_col = 'DTP_FULL_STAT' iv_s = 'Est.Full'   iv_m = 'Estado DTP Full'     iv_l = 'Estado DTP Full' ).
        set_col_text( io_cols = lo_cols iv_col = 'CHAIN_ID'      iv_s = '4.Cadena'   iv_m = '4.Cadena RSPC'       iv_l = '4. Cadena de Procesos RSPC' ).
        set_col_text( io_cols = lo_cols iv_col = 'CHAIN_STAT'    iv_s = 'Est.Cadena' iv_m = 'Estado Cadena RSPC'  iv_l = 'Estado Cadena RSPC (Activa sin Planif.)' ).
        set_col_text( io_cols = lo_cols iv_col = 'ESTADO_GLOBAL' iv_s = 'Estado'     iv_m = 'Estado Global Flujo' iv_l = 'Estado Global (Doble clic=Ejecutar Fila)' ).
        set_col_text( io_cols = lo_cols iv_col = 'ACCION_RES'    iv_s = 'Acción'     iv_m = 'Detalle / Resultado' iv_l = 'Acciones Pendientes / Resultado Ejecución' ).

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
      iv_text = 'Inspeccionando estructuras BW (RSDSSEGFD / RSAABAP)...' ).

    resolve_dynamic_schemas( IMPORTING ev_error_msg = lv_err ).
    IF lv_err IS NOT INITIAL.
      MESSAGE lv_err TYPE 'I' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    show_progress(
      iv_pct  = 45
      iv_text = 'Descubriendo flujos BW (RSDS -> TRFN -> ADSO -> DTP -> RSPC)...' ).

    discover_bw_flows( IMPORTING ev_error_msg = lv_err ).
    IF lv_err IS NOT INITIAL.
      MESSAGE lv_err TYPE 'I' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    IF p_apply = abap_true.
      execute_mass_processing( ).
    ENDIF.

    display_alv( ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Textos de Pantalla de Selección (sin requerir Text Elements en SE38)
*----------------------------------------------------------------------*
INITIALIZATION.
  txt_b1   = '1. Alcance de Flujos BW Generados por ZGOOG_R_BQTR_GEN_REPL_OBJECTS'.
  c_tip1   = 'Puede filtrar por Data Transfer (F4), ADSO, Fuente RSDS o Cadena RSPC.'.
  c_trkey  = 'Data Transfer (opc. con F4):'.

  txt_b2   = '2. Pasos a Automatizar (Orden Seguro: RSDS -> TRFN -> DTP Full -> RSPC)'.
  c_s1_ds  = 'Paso 1: Quitar filtro en pestaña Campos de RSDS, guardar y activar'.
  c_onlylg = 'Limpiar solo filtros de Idioma (tipo LANG / valor L en Clase de campo)'.
  c_s2_tr  = 'Paso 2: Tocar Start Routine (espacio/marca), guardar y activar TRFN'.
  c_s3_dt  = 'Paso 3: Crear y activar DTP Full (directo del sistema fuente sin PSA)'.
  c_s4_pc  = 'Paso 4: Activar Cadenas en RSPC (versión A) SIN planificar jobs'.
  c_cto    = 'Registrar directo en OT al activar (dejar vacío si usa Conexión Transp.)'.

  txt_b3   = '3. Filtro de Visualización ALV'.
  c_onlyp  = 'Mostrar únicamente flujos con tareas pendientes'.

  txt_b4   = '4. Modo de Ejecución'.
  c_read   = 'Solo Diagnóstico / Simulación (Previsualizar los ~150 flujos sin tocar BD)'.
  c_apply  = 'Ejecutar Automatización Masiva sobre los flujos encontrados'.

*----------------------------------------------------------------------*
* Ejecución Principal
*----------------------------------------------------------------------*
START-OF-SELECTION.
  lcl_bw_post_auto=>run( ).
