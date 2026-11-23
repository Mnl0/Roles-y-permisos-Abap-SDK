*&---------------------------------------------------------------------*
*& Report ZGEN_AUDITORIA_CDS_BQ
*&---------------------------------------------------------------------*
*& Utilidad Unificada post-generación BigQuery Toolkit (ABAP SDK GCP)
*& Propósito:
*&   1) Auditar masivamente (~150+ tablas) en modo solo lectura:
*&      - Compatibility Views (DD02L-VIEWREF / Proxy SE16N, ej. MARC ->
*&        NSDM_V_MARC -> nsdm_e_marc) + Código SELECT FROM de reemplazo
*&      - Columnas RAW / LRAW / RAWSTRING -> bintohex( ) o comentar
*&      - Columnas DF34_RAW / DF16_RAW    -> comentar automáticamente
*&      - Columnas QUAN y CURR            -> Ref. SE11 (REFTABLE/REFFIELD),
*&                                           claves JOIN o CAST abap.dec
*&      - Columna de Mandante (CLNT)      -> Nombre exacto o "NO TIENE"
*&      - Objetos tipo VIEW (ej. BPVG)    -> Alerta + Tablas físicas base
*&   2) Modificar y activar automáticamente (individual o masivo) las
*&      vistas CDS de tablas TRANSPARENTES aplicando el código sugerido
*&      (reemplazo opcional de Compatibility View, bintohex RAW, cast de
*&      QUAN/CURR y comentario automático de DF34_RAW/DF16_RAW), usando
*&      la OT abierta sin volver a pedir transporte vista por vista.
*&
*& Interactividad en el reporte ALV (Doble Clic):
*&   - Tabla / Tabla Ref. / Objeto Proxy -> Abre el objeto en la SE11
*&   - Entidad Reemplazo (ej. NSDM_E_*)  -> Muestra DDL estándar de SAP
*&   - Vista CDS / Código CDS / Reempl.  -> Muestra vista previa sugerida
*&   - Est. CDS / Acción CDS             -> Guarda y Activa esa vista CDS
*&---------------------------------------------------------------------*
REPORT zgen_auditoria_cds_bq.

*----------------------------------------------------------------------*
* Variables planas auxiliares para SELECT-OPTIONS
* (No se usa TABLES: ddddlsrc porque contiene un campo STRING profundo)
*----------------------------------------------------------------------*
DATA: gv_sel_tab TYPE dd02l-tabname,
      gv_sel_cds TYPE ddddlsrc-ddlname.

*----------------------------------------------------------------------*
* Tipos de datos para ALV y procesamiento interno
*----------------------------------------------------------------------*
TYPES:
  BEGIN OF ty_detail,
    tabname        TYPE dd02l-tabname,
    ddtext         TYPE dd02t-ddtext,
    es_compat      TYPE c LENGTH 16,
    proxy_obj      TYPE dd02l-viewref,
    cds_target     TYPE c LENGTH 30,
    codigo_repl    TYPE c LENGTH 130,
    cds_view       TYPE ddddlsrc-ddlname,
    estado_cds     TYPE c LENGTH 16,
    tiene_mandt    TYPE c LENGTH 15,
    campo_mandt    TYPE c LENGTH 30,
    categoria      TYPE c LENGTH 18,
    position       TYPE dd03l-position,
    fieldname      TYPE dd03l-fieldname,
    es_clave       TYPE c LENGTH 5,
    datatype       TYPE dd03l-datatype,
    leng           TYPE int4,
    decimals       TYPE int4,
    reftable       TYPE dd03l-reftable,
    reffield       TYPE dd03l-reffield,
    ubicacion_ref  TYPE c LENGTH 32,
    claves_ref     TYPE c LENGTH 80,
    sugerencia_cds TYPE c LENGTH 130,
    nota_tecnica   TYPE c LENGTH 160,
    t_color        TYPE lvc_t_scol,
  END OF ty_detail,

  BEGIN OF ty_summary,
    tabname     TYPE dd02l-tabname,
    ddtext      TYPE dd02t-ddtext,
    estado_tab  TYPE c LENGTH 18,
    es_compat   TYPE c LENGTH 16,
    proxy_obj   TYPE dd02l-viewref,
    cds_target  TYPE c LENGTH 30,
    codigo_repl TYPE c LENGTH 130,
    cds_view    TYPE ddddlsrc-ddlname,
    estado_cds  TYPE c LENGTH 16,
    tiene_mandt TYPE c LENGTH 15,
    campo_mandt TYPE c LENGTH 30,
    cant_raw    TYPE int4,
    lista_raw   TYPE c LENGTH 120,
    cant_dfraw  TYPE int4,
    lista_dfraw TYPE c LENGTH 120,
    cant_curr   TYPE int4,
    cant_quan   TYPE int4,
    cant_ext    TYPE int4,
    lista_qc    TYPE c LENGTH 120,
    accion_cds  TYPE c LENGTH 100,
    t_color     TYPE lvc_t_scol,
  END OF ty_summary,

  BEGIN OF ty_dd02l,
    tabname  TYPE dd02l-tabname,
    as4local TYPE dd02l-as4local,
    as4vers  TYPE dd02l-as4vers,
    tabclass TYPE dd02l-tabclass,
    clidep   TYPE dd02l-clidep,
    viewref  TYPE dd02l-viewref,
  END OF ty_dd02l,

  BEGIN OF ty_dd02t,
    tabname    TYPE dd02t-tabname,
    ddlanguage TYPE dd02t-ddlanguage,
    as4local   TYPE dd02t-as4local,
    as4vers    TYPE dd02t-as4vers,
    ddtext     TYPE dd02t-ddtext,
  END OF ty_dd02t,

  BEGIN OF ty_dd03l,
    tabname   TYPE dd03l-tabname,
    fieldname TYPE dd03l-fieldname,
    as4local  TYPE dd03l-as4local,
    as4vers   TYPE dd03l-as4vers,
    position  TYPE dd03l-position,
    keyflag   TYPE dd03l-keyflag,
    rollname  TYPE dd03l-rollname,
    datatype  TYPE dd03l-datatype,
    leng      TYPE dd03l-leng,
    decimals  TYPE dd03l-decimals,
    reftable  TYPE dd03l-reftable,
    reffield  TYPE dd03l-reffield,
  END OF ty_dd03l,

  BEGIN OF ty_compat_map,
    tabname    TYPE dd02l-tabname,
    tabclass   TYPE dd02l-tabclass,
    proxy_obj  TYPE dd02l-viewref,
    cds_target TYPE c LENGTH 30,
  END OF ty_compat_map,

  BEGIN OF ty_cds_map,
    tabname    TYPE dd02l-tabname,
    ddlname    TYPE ddddlsrc-ddlname,
    from_obj   TYPE c LENGTH 30,
    prio       TYPE i,
    estado_cds TYPE c LENGTH 16,
  END OF ty_cds_map,

  BEGIN OF ty_tab_key,
    tabname TYPE dd02l-tabname,
  END OF ty_tab_key,

  BEGIN OF ty_dep_obj_key,
    objectname TYPE ddldependency-objectname,
  END OF ty_dep_obj_key,

  BEGIN OF ty_dep_ddl_key,
    ddlname TYPE ddldependency-ddlname,
  END OF ty_dep_ddl_key,

  BEGIN OF ty_viewref_key,
    viewref TYPE dd02l-viewref,
  END OF ty_viewref_key,

  BEGIN OF ty_ddl_dep,
    ddlname    TYPE ddldependency-ddlname,
    objectname TYPE ddldependency-objectname,
    state      TYPE ddldependency-state,
    objecttype TYPE ddldependency-objecttype,
  END OF ty_ddl_dep,

  BEGIN OF ty_ref_key,
    tabname   TYPE dd03l-tabname,
    fieldname TYPE dd03l-fieldname,
    as4local  TYPE dd03l-as4local,
    as4vers   TYPE dd03l-as4vers,
    position  TYPE dd03l-position,
  END OF ty_ref_key,

  BEGIN OF ty_view_base,
    viewname TYPE dd26s-viewname,
    tabpos   TYPE dd26s-tabpos,
    as4local TYPE dd26s-as4local,
    as4vers  TYPE dd26s-as4vers,
    tabname  TYPE dd26s-tabname,
  END OF ty_view_base,

  tt_tab_key     TYPE STANDARD TABLE OF ty_tab_key WITH DEFAULT KEY,
  tt_cds_map     TYPE STANDARD TABLE OF ty_cds_map WITH DEFAULT KEY,
  tt_string_list TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

*----------------------------------------------------------------------*
* Tablas y referencias globales para navegación y refresco ALV
*----------------------------------------------------------------------*
DATA: gt_detail  TYPE STANDARD TABLE OF ty_detail,
      gt_summary TYPE STANDARD TABLE OF ty_summary,
      gt_dd02l   TYPE STANDARD TABLE OF ty_dd02l,
      gt_dd03l   TYPE STANDARD TABLE OF ty_dd03l,
      gt_compat  TYPE STANDARD TABLE OF ty_compat_map,
      go_salv    TYPE REF TO cl_salv_table,
      gv_trkorr  TYPE trkorr.

*----------------------------------------------------------------------*
* Pantalla de Selección
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE txt_b1.
  SELECTION-SCREEN COMMENT /1(74) c_tip1.
  SELECT-OPTIONS: s_tab FOR gv_sel_tab.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(26) c_file FOR FIELD p_file.
    PARAMETERS: p_file TYPE c LENGTH 255 LOWER CASE VISIBLE LENGTH 45.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_base AS CHECKBOX DEFAULT abap_false.
    SELECTION-SCREEN COMMENT 4(70) c_base FOR FIELD p_base.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE txt_b2.
  SELECTION-SCREEN COMMENT /1(74) c_tip2.
  SELECT-OPTIONS: s_cds FOR gv_sel_cds.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE txt_b3.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_det RADIOBUTTON GROUP rb1 DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 4(70) c_det FOR FIELD p_det.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_res RADIOBUTTON GROUP rb1.
    SELECTION-SCREEN COMMENT 4(70) c_res FOR FIELD p_res.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN SKIP 1.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_onlyx AS CHECKBOX DEFAULT abap_false.
    SELECTION-SCREEN COMMENT 4(72) c_onlyx FOR FIELD p_onlyx.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b3.

SELECTION-SCREEN BEGIN OF BLOCK b4 WITH FRAME TITLE txt_b4.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_read RADIOBUTTON GROUP rb2 DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 4(72) c_read FOR FIELD p_read.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_apply RADIOBUTTON GROUP rb2.
    SELECTION-SCREEN COMMENT 4(72) c_apply FOR FIELD p_apply.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN SKIP 1.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_comp AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 4(72) c_comp FOR FIELD p_comp.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_actin AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 4(72) c_actin FOR FIELD p_actin.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_revrt AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 4(72) c_revrt FOR FIELD p_revrt.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(36) c_trk FOR FIELD p_trkorr.
    PARAMETERS: p_trkorr TYPE trkorr.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b4.

*----------------------------------------------------------------------*
* Clase Principal de Auditoría, Modificación CDS y Eventos ALV
*----------------------------------------------------------------------*
CLASS lcl_auditor DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      f4_file_open
        CHANGING cv_file TYPE clike,

      run,

      on_double_click
        FOR EVENT double_click OF cl_salv_events_table
        IMPORTING row column.

  PRIVATE SECTION.
    CLASS-METHODS:
      collect_tables
        RETURNING VALUE(rt_tabs) TYPE tt_tab_key,

      get_default_tables
        RETURNING VALUE(rt_tabs) TYPE tt_tab_key,

      strip_ddl_comments_for_tokens
        IMPORTING iv_source        TYPE string
        RETURNING VALUE(rv_tokens) TYPE string,

      extract_from_table_in_ddl
        IMPORTING iv_source         TYPE string
        RETURNING VALUE(rv_tabname) TYPE dd02l-tabname,

      extract_defined_entity_in_ddl
        IMPORTING iv_source        TYPE string
        RETURNING VALUE(rv_entity) TYPE dd02l-tabname,

      load_compat_mapping,

      load_cds_mapping
        IMPORTING it_valid_tabs TYPE tt_tab_key
        EXPORTING et_cds_map    TYPE tt_cds_map,

      clean_alias
        IMPORTING iv_fieldname    TYPE clike
        RETURNING VALUE(rv_alias) TYPE string,

      add_cell_color
        IMPORTING iv_fname TYPE lvc_fname OPTIONAL
                  iv_col   TYPE i
                  iv_int   TYPE i DEFAULT 0
        CHANGING  ct_color TYPE lvc_t_scol,

      set_status_cell_colors
        IMPORTING iv_estado_cds TYPE clike
                  iv_accion_col TYPE i
                  iv_accion_int TYPE i DEFAULT 1
        CHANGING  ct_color      TYPE lvc_t_scol,

      display_detail_alv,

      display_summary_alv,

      set_col_text
        IMPORTING io_cols TYPE REF TO cl_salv_columns_table
                  iv_col  TYPE lvc_fname
                  iv_s    TYPE scrtext_s
                  iv_m    TYPE scrtext_m
                  iv_l    TYPE scrtext_l,

      open_se11_table
        IMPORTING iv_tabname TYPE clike,

      preview_std_cds_target
        IMPORTING iv_cds_target TYPE clike
                  iv_proxy_obj  TYPE clike,

      trim_spaces
        IMPORTING iv_str        TYPE string
        RETURNING VALUE(rv_str) TYPE string,

      strip_internal_baseinfo
        IMPORTING iv_source       TYPE string
        RETURNING VALUE(rv_clean) TYPE string,

      split_inline_comment
        IMPORTING iv_line   TYPE string
        EXPORTING ev_indent TYPE string
                  ev_code   TYPE string
                  ev_cmt    TYPE string,

      count_code_depths
        IMPORTING iv_code        TYPE string
        EXPORTING ev_paren_delta TYPE i
                  ev_brace_delta TYPE i
                  ev_brack_delta TYPE i
                  ev_case_delta  TYPE i,

      rewrite_compat_from_clause
        IMPORTING iv_tabname    TYPE dd02l-tabname
                  iv_proxy_obj  TYPE dd02l-viewref
                  iv_cds_target TYPE clike
        CHANGING  ct_prefix     TYPE tt_string_list
                  cv_compat_chg TYPE abap_bool,

      build_modified_cds_source
        IMPORTING iv_source     TYPE string
                  iv_tabname    TYPE dd02l-tabname
        EXPORTING et_out_lines  TYPE tt_string_list
                  ev_new_source TYPE string
                  ev_changed    TYPE abap_bool
                  ev_change_cnt TYPE i
                  ev_comma_cnt  TYPE i
                  ev_compat_chg TYPE abap_bool,

      preview_cds_code
        IMPORTING iv_ddlname TYPE ddddlsrc-ddlname
                  iv_tabname TYPE dd02l-tabname,

      apply_single_cds
        IMPORTING iv_tabname     TYPE dd02l-tabname
                  iv_tabclass    TYPE dd02l-tabclass
                  iv_ddlname     TYPE ddddlsrc-ddlname
                  iv_act_clean   TYPE abap_bool
                  iv_revert_fail TYPE abap_bool
        EXPORTING ev_estado_cds  TYPE string
                  ev_accion_msg  TYPE string
                  ev_color_col   TYPE i
                  ev_updated     TYPE abap_bool
                  ev_compat_done TYPE abap_bool
        CHANGING  cv_trkorr      TYPE trkorr,

      update_alv_rows_for_table
        IMPORTING iv_tabname     TYPE dd02l-tabname
                  iv_estado_cds  TYPE string
                  iv_accion_msg  TYPE string
                  iv_color_col   TYPE i
                  iv_compat_done TYPE abap_bool DEFAULT abap_false,

      execute_mass_cds_update,

      prompt_single_cds_action
        IMPORTING iv_tabname TYPE dd02l-tabname
                  iv_ddlname TYPE ddddlsrc-ddlname.
ENDCLASS.

CLASS lcl_auditor IMPLEMENTATION.

  METHOD f4_file_open.
    DATA: lt_files TYPE filetable,
          lv_rc    TYPE i.

    cl_gui_frontend_services=>file_open_dialog(
      EXPORTING
        window_title = 'Seleccionar archivo TXT/CSV de tablas'
        file_filter  = 'Archivos TXT/CSV (*.txt;*.csv)|*.txt;*.csv|Todos (*.*)|*.*'
      CHANGING
        file_table   = lt_files
        rc           = lv_rc
      EXCEPTIONS
        OTHERS       = 1 ).

    IF sy-subrc = 0 AND lv_rc >= 1.
      READ TABLE lt_files INTO DATA(ls_file) INDEX 1.
      IF sy-subrc = 0.
        cv_file = ls_file-filename.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD get_default_tables.
    " Lista base de referencia (puede pegarse cualquier lista en S_TAB)
    rt_tabs = VALUE #(
      ( tabname = 'ACDOCA' )           ( tabname = 'ADR6' )
      ( tabname = 'ADRC' )             ( tabname = 'ADRCT' )
      ( tabname = 'ADRT' )             ( tabname = 'AFKO' )
      ( tabname = 'AFPO' )             ( tabname = 'AUFK' )
      ( tabname = 'BKPF' )             ( tabname = 'BSAD_BCK' )
      ( tabname = 'BSEG' )             ( tabname = 'BUT000' )
      ( tabname = 'BUT020' )           ( tabname = 'CEPC' )
      ( tabname = 'CEPCT' )            ( tabname = 'CKMLCR' )
      ( tabname = 'CKMLHD' )           ( tabname = 'CSKS' )
      ( tabname = 'CSKT' )             ( tabname = 'DD03L' )
      ( tabname = 'EKBE' )             ( tabname = 'EKES' )
      ( tabname = 'EKET' )             ( tabname = 'EKKN' )
      ( tabname = 'EKKO' )             ( tabname = 'EKPO' )
      ( tabname = 'FINSC_LD_CMP' )     ( tabname = 'FINSC_LEDGER' )
      ( tabname = 'FINSC_LEDGER_REP' ) ( tabname = 'FINSC_LEDGER_T' )
      ( tabname = 'HRRP_DIRECTORY' )   ( tabname = 'HRRP_NODE' )
      ( tabname = 'HRRP_NODET' )       ( tabname = 'JEST' )
      ( tabname = 'KNA1' )             ( tabname = 'KNVV' )
      ( tabname = 'LFA1' )             ( tabname = 'LIKP' )
      ( tabname = 'LIPS' )             ( tabname = 'MAKT' )
      ( tabname = 'MARA' )             ( tabname = 'MARC' )
      ( tabname = 'MARD' )             ( tabname = 'MARM' )
      ( tabname = 'MAST' )             ( tabname = 'MATDOC' )
      ( tabname = 'MBEW' )             ( tabname = 'MBEWH' )
      ( tabname = 'MCH1' )             ( tabname = 'MCHA' )
      ( tabname = 'MKOL' )             ( tabname = 'MSKA' )
      ( tabname = 'MSKU' )             ( tabname = 'MSLB' )
      ( tabname = 'MVKE' )             ( tabname = 'PRCD_ELEMENTS' )
      ( tabname = 'RBCO' )             ( tabname = 'RBKP' )
      ( tabname = 'RSEG' )             ( tabname = 'SETHANAHIER0101' )
      ( tabname = 'SETHANAHIER0106' )  ( tabname = 'SETHEADER' )
      ( tabname = 'SETHEADERT' )       ( tabname = 'SETLEAF' )
      ( tabname = 'SETNODE' )          ( tabname = 'SKA1' )
      ( tabname = 'SKAT' )             ( tabname = 'STAS' )
      ( tabname = 'STKO' )             ( tabname = 'STPO' )
      ( tabname = 'T001' )             ( tabname = 'T001K' )
      ( tabname = 'T001L' )            ( tabname = 'T001W' )
      ( tabname = 'T002' )             ( tabname = 'T005' )
      ( tabname = 'T005K' )            ( tabname = 'T005S' )
      ( tabname = 'T005T' )            ( tabname = 'T006' )
      ( tabname = 'T006A' )            ( tabname = 'T006T' )
      ( tabname = 'T009' )             ( tabname = 'T009B' )
      ( tabname = 'T023' )             ( tabname = 'T023T' )
      ( tabname = 'T024' )             ( tabname = 'T024E' )
      ( tabname = 'T134' )             ( tabname = 'T134T' )
      ( tabname = 'T148T' )            ( tabname = 'T156T' )
      ( tabname = 'T157E' )            ( tabname = 'T161' )
      ( tabname = 'T161T' )            ( tabname = 'T179' )
      ( tabname = 'T179T' )            ( tabname = 'T881' )
      ( tabname = 'T881T' )            ( tabname = 'TCURC' )
      ( tabname = 'TCURF' )            ( tabname = 'TCURR' )
      ( tabname = 'TCURT' )            ( tabname = 'TCURX' )
      ( tabname = 'TJ02T' )            ( tabname = 'TKA02' )
      ( tabname = 'TSPA' )             ( tabname = 'TSPAT' )
      ( tabname = 'TVARVC' )           ( tabname = 'TVFST' )
      ( tabname = 'TVKO' )             ( tabname = 'TVKOT' )
      ( tabname = 'TVLST' )            ( tabname = 'TVM1T' )
      ( tabname = 'TVTW' )             ( tabname = 'TVTWT' )
      ( tabname = 'VBAK' )             ( tabname = 'VBAP' )
      ( tabname = 'VBEP' )             ( tabname = 'VBFA' )
      ( tabname = 'VBPA' )             ( tabname = 'VBRK' )
      ( tabname = 'VBRP' )
    ).
  ENDMETHOD.

  METHOD collect_tables.
    DATA: lt_raw_lines TYPE STANDARD TABLE OF string.

    " 1. Desde SELECT-OPTIONS S_TAB:
    "    a) Conservar valores individuales (I/EQ) incluso si tienen
    "       error de tipeo para avisar si alguna tabla no existe en SE11
    LOOP AT s_tab INTO DATA(ls_sel)
      WHERE sign = 'I' AND option = 'EQ' AND low IS NOT INITIAL.
      APPEND VALUE #( tabname = to_upper( ls_sel-low ) ) TO rt_tabs.
    ENDLOOP.

    "    b) Expandir comodines o rangos (ej. Z*, T001..T009) contra DD02L
    IF s_tab[] IS NOT INITIAL.
      SELECT tabname
        FROM dd02l
        WHERE tabname  IN @s_tab
          AND as4local  = 'A'
          AND tabclass IN ( 'TRANSP', 'POOL', 'CLUSTER', 'VIEW' )
        INTO TABLE @DATA(lt_from_range).

      LOOP AT lt_from_range INTO DATA(ls_rng).
        APPEND VALUE #( tabname = ls_rng-tabname ) TO rt_tabs.
      ENDLOOP.
    ENDIF.

    " 2. Desde archivo local TXT / CSV opcional (primera columna = tabla)
    IF p_file IS NOT INITIAL.
      DATA(lv_filename) = CONV string( p_file ).
      cl_gui_frontend_services=>gui_upload(
        EXPORTING
          filename = lv_filename
          filetype = 'ASC'
        CHANGING
          data_tab = lt_raw_lines
        EXCEPTIONS
          OTHERS   = 1 ).

      IF sy-subrc <> 0.
        MESSAGE 'No se pudo leer el archivo indicado en P_FILE.'
          TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        LOOP AT lt_raw_lines INTO DATA(lv_line).
          REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf(1)
            IN lv_line WITH ''.
          REPLACE ALL OCCURRENCES OF '"' IN lv_line WITH ''.
          REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab
            IN lv_line WITH ';'.
          REPLACE ALL OCCURRENCES OF ',' IN lv_line WITH ';'.
          SPLIT lv_line AT ';' INTO DATA(lv_col1) DATA(lv_rest).
          lv_col1 = condense( to_upper( lv_col1 ) ).
          IF lv_col1 IS NOT INITIAL
             AND lv_col1 <> 'TABNAME'
             AND lv_col1 <> 'TABLA'
             AND lv_col1 <> 'TABLE'
             AND lv_col1 <> 'TABLE_NAME'.
            APPEND VALUE #( tabname = CONV dd02l-tabname( lv_col1 ) ) TO rt_tabs.
          ENDIF.
        ENDLOOP.
      ENDIF.
    ENDIF.

    " 3. Lista base predefinida si el usuario marcó el checkbox
    IF p_base = abap_true.
      APPEND LINES OF get_default_tables( ) TO rt_tabs.
    ENDIF.

    " 4. Si no ingresó tablas pero sí indicó patrón de vistas CDS en S_CDS,
    "    extraer automáticamente las tablas base desde DDDDLSRC (incluyendo
    "    vistas que ya apunten a una Compatibility View como nsdm_e_marc)
    IF rt_tabs IS INITIAL AND s_cds[] IS NOT INITIAL.
      DATA: lt_cand_objs  TYPE STANDARD TABLE OF ty_dep_obj_key,
            lt_cand_ddls  TYPE STANDARD TABLE OF ty_dep_ddl_key,
            lt_cand_vrefs TYPE STANDARD TABLE OF ty_viewref_key.

      SELECT ddlname, as4local, source
        FROM ddddlsrc
        WHERE ddlname  IN @s_cds
          AND as4local IN ( 'A', 'I', 'N' )
        INTO TABLE @DATA(lt_ddl_tabs).

      LOOP AT lt_ddl_tabs INTO DATA(ls_dt).
        DATA(lv_t_from_cds) = extract_from_table_in_ddl( ls_dt-source ).
        IF lv_t_from_cds IS NOT INITIAL.
          APPEND VALUE #( tabname = lv_t_from_cds ) TO rt_tabs.
          APPEND VALUE #( objectname = lv_t_from_cds ) TO lt_cand_objs.
        ENDIF.
      ENDLOOP.

      " Si alguna CDS apunta a una entidad proxy (ej. NSDM_E_MARC), resolver
      " la tabla física original (ej. MARC) vía DDLDEPENDENCY -> DD02L-VIEWREF
      SORT lt_cand_objs BY objectname.
      DELETE ADJACENT DUPLICATES FROM lt_cand_objs COMPARING objectname.
      IF lt_cand_objs IS NOT INITIAL.
        SELECT ddlname, objectname, state, objecttype
          FROM ddldependency
          FOR ALL ENTRIES IN @lt_cand_objs
          WHERE objectname = @lt_cand_objs-objectname
            AND state      = 'A'
          INTO TABLE @DATA(lt_rev_stob).

        LOOP AT lt_rev_stob INTO DATA(ls_rs).
          APPEND VALUE #( ddlname = ls_rs-ddlname ) TO lt_cand_ddls.
        ENDLOOP.
        SORT lt_cand_ddls BY ddlname.
        DELETE ADJACENT DUPLICATES FROM lt_cand_ddls COMPARING ddlname.

        IF lt_cand_ddls IS NOT INITIAL.
          SELECT ddlname, objectname, state, objecttype
            FROM ddldependency
            FOR ALL ENTRIES IN @lt_cand_ddls
            WHERE ddlname = @lt_cand_ddls-ddlname
              AND state   = 'A'
            INTO TABLE @DATA(lt_rev_views).

          LOOP AT lt_rev_views INTO DATA(ls_rv).
            APPEND VALUE #( objectname = ls_rv-objectname ) TO lt_cand_objs.
          ENDLOOP.
          SORT lt_cand_objs BY objectname.
          DELETE ADJACENT DUPLICATES FROM lt_cand_objs COMPARING objectname.
        ENDIF.

        LOOP AT lt_cand_objs INTO DATA(ls_co).
          IF ls_co-objectname IS NOT INITIAL.
            APPEND VALUE #( viewref = CONV dd02l-viewref( ls_co-objectname ) )
              TO lt_cand_vrefs.
          ENDIF.
        ENDLOOP.
        SORT lt_cand_vrefs BY viewref.
        DELETE ADJACENT DUPLICATES FROM lt_cand_vrefs COMPARING viewref.

        IF lt_cand_vrefs IS NOT INITIAL.
          SELECT tabname
            FROM dd02l
            FOR ALL ENTRIES IN @lt_cand_vrefs
            WHERE viewref  = @lt_cand_vrefs-viewref
              AND as4local = 'A'
            INTO TABLE @DATA(lt_orig_tabs).

          LOOP AT lt_orig_tabs INTO DATA(ls_ot).
            APPEND VALUE #( tabname = ls_ot-tabname ) TO rt_tabs.
          ENDLOOP.
        ENDIF.
      ENDIF.
    ENDIF.

    SORT rt_tabs BY tabname.
    DELETE ADJACENT DUPLICATES FROM rt_tabs COMPARING tabname.
    DELETE rt_tabs WHERE tabname IS INITIAL.
  ENDMETHOD.

  METHOD strip_ddl_comments_for_tokens.
    " Limpia comentarios /*...*/, //... y --... y separadores DDL para
    " extraer tokens SQL/CDS de forma 100% determinística sin REGEX
    DATA: lt_lines TYPE tt_string_list,
          lv_accum TYPE string.

    DATA(lv_src) = strip_internal_baseinfo( iv_source ).

    " Eliminar comentarios de bloque /* ... */
    DO 100 TIMES.
      FIND FIRST OCCURRENCE OF '/*' IN lv_src MATCH OFFSET DATA(lv_b_off).
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      DATA(lv_b_head) = COND string(
        WHEN lv_b_off > 0 THEN substring( val = lv_src len = lv_b_off )
        ELSE '' ).
      DATA(lv_b_tail) = substring( val = lv_src off = lv_b_off ).
      FIND FIRST OCCURRENCE OF '*/' IN lv_b_tail MATCH OFFSET DATA(lv_b_end).
      IF sy-subrc = 0.
        DATA(lv_b_after) = lv_b_end + 2.
        IF lv_b_after < strlen( lv_b_tail ).
          DATA(lv_b_rest) = substring( val = lv_b_tail off = lv_b_after ).
          lv_src = lv_b_head && ` ` && lv_b_rest.
        ELSE.
          lv_src = lv_b_head.
        ENDIF.
      ELSE.
        lv_src = lv_b_head.
        EXIT.
      ENDIF.
    ENDDO.

    SPLIT lv_src AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
    LOOP AT lt_lines INTO DATA(lv_ln).
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf(1) IN lv_ln WITH ` `.
      split_inline_comment(
        EXPORTING iv_line = lv_ln
        IMPORTING ev_code = DATA(lv_code_part) ).
      IF lv_code_part IS NOT INITIAL AND lv_code_part(1) <> '@'.
        lv_accum = lv_accum && ` ` && lv_code_part.
      ENDIF.
    ENDLOOP.

    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN lv_accum WITH ` `.
    REPLACE ALL OCCURRENCES OF '{' IN lv_accum WITH ` `.
    REPLACE ALL OCCURRENCES OF '}' IN lv_accum WITH ` `.
    REPLACE ALL OCCURRENCES OF '(' IN lv_accum WITH ` `.
    REPLACE ALL OCCURRENCES OF ')' IN lv_accum WITH ` `.
    REPLACE ALL OCCURRENCES OF ',' IN lv_accum WITH ` `.
    REPLACE ALL OCCURRENCES OF ';' IN lv_accum WITH ` `.
    rv_tokens = condense( lv_accum ).
  ENDMETHOD.

  METHOD extract_from_table_in_ddl.
    " Extrae la tabla o vista principal luego de 'select [distinct] from <obj>'
    DATA(lv_tokens_str) = strip_ddl_comments_for_tokens( iv_source ).
    IF lv_tokens_str IS INITIAL.
      RETURN.
    ENDIF.

    SPLIT lv_tokens_str AT space INTO TABLE DATA(lt_words).
    DATA(lv_total) = lines( lt_words ).
    DATA(lv_i)     = 1.

    WHILE lv_i <= lv_total.
      DATA(lv_w_up) = to_upper( lt_words[ lv_i ] ).
      IF lv_w_up = 'SELECT'.
        DATA(lv_n1) = lv_i + 1.
        DATA(lv_n2) = lv_i + 2.
        DATA(lv_n3) = lv_i + 3.
        IF lv_n2 <= lv_total AND to_upper( lt_words[ lv_n1 ] ) = 'FROM'.
          DATA(lv_raw_obj) = lt_words[ lv_n2 ].
          REPLACE ALL OCCURRENCES OF '"' IN lv_raw_obj WITH ''.
          rv_tabname = CONV dd02l-tabname( to_upper( lv_raw_obj ) ).
          RETURN.
        ELSEIF lv_n3 <= lv_total
               AND to_upper( lt_words[ lv_n1 ] ) = 'DISTINCT'
               AND to_upper( lt_words[ lv_n2 ] ) = 'FROM'.
          lv_raw_obj = lt_words[ lv_n3 ].
          REPLACE ALL OCCURRENCES OF '"' IN lv_raw_obj WITH ''.
          rv_tabname = CONV dd02l-tabname( to_upper( lv_raw_obj ) ).
          RETURN.
        ENDIF.
      ENDIF.
      lv_i = lv_i + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD extract_defined_entity_in_ddl.
    " Extrae el nombre de la entidad definida en 'define [root] view [entity] <ent>'
    DATA(lv_tokens_str) = strip_ddl_comments_for_tokens( iv_source ).
    IF lv_tokens_str IS INITIAL.
      RETURN.
    ENDIF.

    SPLIT lv_tokens_str AT space INTO TABLE DATA(lt_words).
    DATA(lv_total) = lines( lt_words ).
    DATA(lv_i)     = 1.

    WHILE lv_i <= lv_total.
      IF to_upper( lt_words[ lv_i ] ) = 'DEFINE'.
        DATA(lv_j) = lv_i + 1.
        WHILE lv_j <= lv_total.
          DATA(lv_kw) = to_upper( lt_words[ lv_j ] ).
          IF lv_kw = 'ROOT'
             OR lv_kw = 'CUSTOM'
             OR lv_kw = 'ABSTRACT'
             OR lv_kw = 'TRANSIENT'
             OR lv_kw = 'WRITABLE'.
            lv_j = lv_j + 1.
          ELSE.
            EXIT.
          ENDIF.
        ENDWHILE.

        IF lv_j <= lv_total AND to_upper( lt_words[ lv_j ] ) = 'VIEW'.
          lv_j = lv_j + 1.
          IF lv_j <= lv_total AND to_upper( lt_words[ lv_j ] ) = 'ENTITY'.
            lv_j = lv_j + 1.
          ENDIF.
          IF lv_j <= lv_total.
            DATA(lv_ent) = lt_words[ lv_j ].
            REPLACE ALL OCCURRENCES OF '"' IN lv_ent WITH ''.
            rv_entity = CONV dd02l-tabname( to_upper( lv_ent ) ).
            RETURN.
          ENDIF.
        ENDIF.
      ENDIF.
      lv_i = lv_i + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD load_compat_mapping.
    " Resuelve masivamente las Compatibility Views / Replacement Objects:
    " DD02L-VIEWREF (ej. MARC -> NSDM_V_MARC) -> DDLDEPENDENCY (VIEW -> DDLNAME -> STOB)
    " -> Entidad CDS real (ej. NSDM_E_MARC). También detecta vistas CDS tipo COSP -> V_COSP.
    DATA: lt_lkp_objs TYPE STANDARD TABLE OF ty_dep_obj_key,
          lt_lkp_ddls TYPE STANDARD TABLE OF ty_dep_ddl_key,
          lt_dep_obj  TYPE STANDARD TABLE OF ty_ddl_dep,
          lt_dep_ddl  TYPE STANDARD TABLE OF ty_ddl_dep.

    CLEAR gt_compat.
    IF gt_dd02l IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT gt_dd02l INTO DATA(ls_02).
      IF ls_02-viewref IS NOT INITIAL.
        APPEND VALUE #( objectname = ls_02-viewref ) TO lt_lkp_objs.
      ELSEIF ls_02-tabclass = 'VIEW'.
        APPEND VALUE #( objectname = ls_02-tabname ) TO lt_lkp_objs.
      ENDIF.
    ENDLOOP.

    SORT lt_lkp_objs BY objectname.
    DELETE ADJACENT DUPLICATES FROM lt_lkp_objs COMPARING objectname.
    IF lt_lkp_objs IS INITIAL.
      RETURN.
    ENDIF.

    SELECT ddlname, objectname, state, objecttype
      FROM ddldependency
      FOR ALL ENTRIES IN @lt_lkp_objs
      WHERE objectname = @lt_lkp_objs-objectname
        AND state      = 'A'
      INTO TABLE @lt_dep_obj.

    LOOP AT lt_dep_obj INTO DATA(ls_do).
      APPEND VALUE #( ddlname = ls_do-ddlname ) TO lt_lkp_ddls.
    ENDLOOP.
    LOOP AT lt_lkp_objs INTO DATA(ls_lo).
      APPEND VALUE #( ddlname = CONV ddldependency-ddlname( ls_lo-objectname ) )
        TO lt_lkp_ddls.
    ENDLOOP.

    SORT lt_lkp_ddls BY ddlname.
    DELETE ADJACENT DUPLICATES FROM lt_lkp_ddls COMPARING ddlname.

    IF lt_lkp_ddls IS NOT INITIAL.
      SELECT ddlname, objectname, state, objecttype
        FROM ddldependency
        FOR ALL ENTRIES IN @lt_lkp_ddls
        WHERE ddlname = @lt_lkp_ddls-ddlname
          AND state   = 'A'
        INTO TABLE @lt_dep_ddl.
    ENDIF.

    SORT lt_dep_obj BY objectname objecttype.
    SORT lt_dep_ddl BY ddlname objecttype.

    LOOP AT gt_dd02l INTO ls_02.
      IF ls_02-viewref IS NOT INITIAL.
        DATA(lv_proxy)     = ls_02-viewref.
        DATA(lv_proxy_key) = CONV ddldependency-objectname( lv_proxy ).
        DATA(lv_target)    = VALUE dd02l-tabname( ).
        DATA(lv_ddlnam)    = VALUE ddldependency-ddlname( ).

        " 1) ¿VIEWREF ya es directamente el objeto STOB (CDS Entity)?
        READ TABLE lt_dep_obj INTO DATA(ls_direct_stob)
          WITH KEY objectname = lv_proxy_key
                   objecttype = 'STOB' BINARY SEARCH.
        IF sy-subrc = 0.
          lv_target = CONV dd02l-tabname( ls_direct_stob-objectname ).
          lv_ddlnam = ls_direct_stob-ddlname.
        ELSE.
          " 2) Buscar como SQL View ('VIEW') -> obtener DDLNAME -> leer 'STOB'
          READ TABLE lt_dep_obj INTO DATA(ls_view_dep)
            WITH KEY objectname = lv_proxy_key
                     objecttype = 'VIEW' BINARY SEARCH.
          IF sy-subrc = 0.
            lv_ddlnam = ls_view_dep-ddlname.
          ELSE.
            READ TABLE lt_dep_obj INTO DATA(ls_any_dep)
              WITH KEY objectname = lv_proxy_key BINARY SEARCH.
            IF sy-subrc = 0.
              lv_ddlnam = ls_any_dep-ddlname.
            ELSE.
              lv_ddlnam = CONV ddldependency-ddlname( lv_proxy ).
            ENDIF.
          ENDIF.

          IF lv_ddlnam IS NOT INITIAL.
            READ TABLE lt_dep_ddl INTO DATA(ls_stob_dep)
              WITH KEY ddlname    = lv_ddlnam
                       objecttype = 'STOB' BINARY SEARCH.
            IF sy-subrc = 0.
              lv_target = CONV dd02l-tabname( ls_stob_dep-objectname ).
            ENDIF.
          ENDIF.
        ENDIF.

        " 3) Respaldo puntual desde DDDDLSRC si no figuraba STOB en DDLDEPENDENCY
        "    (Se usa SELECT SINGLE sin FOR ALL ENTRIES porque SOURCE es STRING/LOB)
        IF lv_target IS INITIAL AND lv_ddlnam IS NOT INITIAL.
          DATA(lv_fb_key) = CONV ddddlsrc-ddlname( lv_ddlnam ).
          DATA(lv_fb_src) = VALUE string( ).
          SELECT SINGLE source
            FROM ddddlsrc
            WHERE ddlname  = @lv_fb_key
              AND as4local = 'A'
            INTO @lv_fb_src.
          IF sy-subrc = 0 AND lv_fb_src IS NOT INITIAL.
            lv_target = extract_defined_entity_in_ddl( lv_fb_src ).
          ENDIF.
        ENDIF.

        IF lv_target IS INITIAL.
          lv_target = CONV dd02l-tabname( lv_proxy ).
        ENDIF.

        APPEND VALUE ty_compat_map(
          tabname    = ls_02-tabname
          tabclass   = ls_02-tabclass
          proxy_obj  = lv_proxy
          cds_target = lv_target
        ) TO gt_compat.

      ELSEIF ls_02-tabclass = 'VIEW'.
        " Caso COSP / COSS en S/4HANA (donde la propia vista es SQLView de una CDS estándar)
        DATA(lv_vw_key) = CONV ddldependency-objectname( ls_02-tabname ).
        READ TABLE lt_dep_obj INTO DATA(ls_vw_cds)
          WITH KEY objectname = lv_vw_key
                   objecttype = 'VIEW' BINARY SEARCH.
        IF sy-subrc = 0 AND ls_vw_cds-ddlname IS NOT INITIAL.
          READ TABLE lt_dep_ddl INTO DATA(ls_vw_stob)
            WITH KEY ddlname    = ls_vw_cds-ddlname
                     objecttype = 'STOB' BINARY SEARCH.
          IF sy-subrc = 0 AND ls_vw_stob-objectname IS NOT INITIAL.
            APPEND VALUE ty_compat_map(
              tabname    = ls_02-tabname
              tabclass   = ls_02-tabclass
              proxy_obj  = ls_02-tabname
              cds_target = CONV dd02l-tabname( ls_vw_stob-objectname )
            ) TO gt_compat.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.

    SORT gt_compat BY tabname.
    DELETE ADJACENT DUPLICATES FROM gt_compat COMPARING tabname.
  ENDMETHOD.

  METHOD load_cds_mapping.
    TYPES:
      BEGIN OF ty_ddl_row,
        ddlname  TYPE ddddlsrc-ddlname,
        as4local TYPE ddddlsrc-as4local,
        source   TYPE ddddlsrc-source,
      END OF ty_ddl_row.

    DATA: lt_map TYPE tt_cds_map,
          lt_ddl TYPE STANDARD TABLE OF ty_ddl_row.

    CLEAR et_cds_map.
    IF it_valid_tabs IS INITIAL.
      RETURN.
    ENDIF.

    " Leer vistas CDS desde DDDDLSRC (Activas 'A' e Inactivas 'I'/'N').
    " Reconoce tanto vistas que apuntan directo a la tabla (ej. MARC) como
    " vistas ya modificadas para apuntar a su Compatibility View (ej. NSDM_E_MARC).
    IF s_cds[] IS NOT INITIAL.
      SELECT ddlname, as4local, source
        FROM ddddlsrc
        WHERE ddlname  IN @s_cds
          AND as4local IN ( 'A', 'I', 'N' )
        INTO TABLE @lt_ddl.
    ELSE.
      SELECT ddlname, as4local, source
        FROM ddddlsrc
        WHERE ( ddlname LIKE 'Z%' OR ddlname LIKE 'Y%' )
          AND as4local IN ( 'A', 'I', 'N' )
        INTO TABLE @lt_ddl.
    ENDIF.

    SORT lt_ddl BY ddlname ASCENDING as4local DESCENDING.
    DELETE ADJACENT DUPLICATES FROM lt_ddl COMPARING ddlname.

    LOOP AT lt_ddl INTO DATA(ls_ddl).
      DATA(lv_from_obj) = extract_from_table_in_ddl( ls_ddl-source ).
      IF lv_from_obj IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA(lv_mapped_tab) = VALUE dd02l-tabname( ).
      READ TABLE it_valid_tabs TRANSPORTING NO FIELDS
        WITH KEY tabname = lv_from_obj BINARY SEARCH.
      IF sy-subrc = 0.
        lv_mapped_tab = lv_from_obj.
      ELSEIF gt_compat IS NOT INITIAL.
        LOOP AT gt_compat INTO DATA(ls_cmp)
          WHERE cds_target = lv_from_obj OR proxy_obj = lv_from_obj.
          READ TABLE it_valid_tabs TRANSPORTING NO FIELDS
            WITH KEY tabname = ls_cmp-tabname BINARY SEARCH.
          IF sy-subrc = 0.
            lv_mapped_tab = ls_cmp-tabname.
            IF ls_ddl-ddlname CS ls_cmp-tabname.
              EXIT.
            ENDIF.
          ENDIF.
        ENDLOOP.
      ENDIF.

      IF lv_mapped_tab IS NOT INITIAL.
        DATA(lv_prio) = COND i( WHEN ls_ddl-ddlname CS lv_mapped_tab THEN 1 ELSE 2 ).
        APPEND VALUE ty_cds_map(
          tabname    = lv_mapped_tab
          ddlname    = ls_ddl-ddlname
          from_obj   = lv_from_obj
          prio       = lv_prio
          estado_cds = COND string( WHEN ls_ddl-as4local = 'A'
                                    THEN 'ACTIVA'
                                    ELSE 'INACTIVA' )
        ) TO lt_map.
      ENDIF.
    ENDLOOP.

    SORT lt_map STABLE BY tabname ASCENDING prio ASCENDING ddlname ASCENDING.
    DELETE ADJACENT DUPLICATES FROM lt_map COMPARING tabname.
    et_cds_map = lt_map.
  ENDMETHOD.

  METHOD clean_alias.
    rv_alias = to_lower( CONV string( iv_fieldname ) ).
    REPLACE ALL OCCURRENCES OF '"' IN rv_alias WITH ''.
    IF rv_alias CS '.'.
      SPLIT rv_alias AT '.' INTO DATA(lv_pref) rv_alias.
    ENDIF.
    REPLACE ALL OCCURRENCES OF '/' IN rv_alias WITH '_'.
    IF strlen( rv_alias ) > 1 AND rv_alias(1) = '_'.
      rv_alias = rv_alias+1.
    ENDIF.
  ENDMETHOD.

  METHOD add_cell_color.
    APPEND VALUE lvc_s_scol(
      fname = iv_fname
      color = VALUE lvc_s_colo( col = iv_col int = iv_int inv = 0 )
    ) TO ct_color.
  ENDMETHOD.

  METHOD set_status_cell_colors.
    DELETE ct_color WHERE fname = 'ESTADO_CDS' OR fname = 'ACCION_CDS'.

    IF iv_estado_cds CS 'ACTIVA'.
      add_cell_color( EXPORTING iv_fname = 'ESTADO_CDS'
                                iv_col   = 5
                                iv_int   = 1
                      CHANGING  ct_color = ct_color ).
    ELSEIF iv_estado_cds IS NOT INITIAL.
      add_cell_color( EXPORTING iv_fname = 'ESTADO_CDS'
                                iv_col   = 6
                                iv_int   = 1
                      CHANGING  ct_color = ct_color ).
    ENDIF.

    IF iv_accion_col > 0.
      add_cell_color( EXPORTING iv_fname = 'ACCION_CDS'
                                iv_col   = iv_accion_col
                                iv_int   = iv_accion_int
                      CHANGING  ct_color = ct_color ).
    ENDIF.
  ENDMETHOD.

  METHOD run.
    DATA: lt_dd02t       TYPE STANDARD TABLE OF ty_dd02t,
          lt_valid_tab   TYPE tt_tab_key,
          lt_view_tabs   TYPE tt_tab_key,
          lt_view_bases  TYPE STANDARD TABLE OF ty_view_base,
          lt_reftabs     TYPE tt_tab_key,
          lt_ref_dd02l   TYPE STANDARD TABLE OF ty_dd02l,
          lt_ref_keys    TYPE STANDARD TABLE OF ty_ref_key,
          lt_cds_map     TYPE tt_cds_map,
          lv_tiene_mandt TYPE c LENGTH 15,
          lv_campo_mandt TYPE c LENGTH 30.

    CLEAR: gt_detail, gt_summary, gt_dd02l, gt_dd03l, gt_compat, go_salv.
    gv_trkorr = p_trkorr.

    " 1. Recolectar lista de tablas a auditar
    DATA(lt_req_tabs) = collect_tables( ).
    IF lt_req_tabs IS INITIAL.
      MESSAGE 'Ingrese tablas en S_TAB, indique archivo o marque la lista base.'
        TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    " 2. Consulta masiva #1: Metadatos de cabecera de tablas (DD02L + VIEWREF y DD02T)
    SELECT tabname, as4local, as4vers, tabclass, clidep, viewref
      FROM dd02l
      FOR ALL ENTRIES IN @lt_req_tabs
      WHERE tabname  = @lt_req_tabs-tabname
        AND as4local = 'A'
      INTO TABLE @gt_dd02l.

    SORT gt_dd02l BY tabname as4vers.
    DELETE ADJACENT DUPLICATES FROM gt_dd02l COMPARING tabname.

    " 2B. Resolver Compatibility Views / Objetos Proxy (DD02L-VIEWREF -> DDLDEPENDENCY)
    load_compat_mapping( ).

    SELECT tabname, ddlanguage, as4local, as4vers, ddtext
      FROM dd02t
      FOR ALL ENTRIES IN @lt_req_tabs
      WHERE tabname     = @lt_req_tabs-tabname
        AND ddlanguage IN ( @sy-langu, 'S', 'E' )
        AND as4local    = 'A'
      INTO TABLE @lt_dd02t.

    LOOP AT lt_dd02t ASSIGNING FIELD-SYMBOL(<fs_t>).
      IF <fs_t>-ddlanguage = sy-langu.
        <fs_t>-as4vers = '0000'.
      ELSEIF <fs_t>-ddlanguage = 'S'.
        <fs_t>-as4vers = '0001'.
      ELSE.
        <fs_t>-as4vers = '0002'.
      ENDIF.
    ENDLOOP.
    SORT lt_dd02t BY tabname as4vers.
    DELETE ADJACENT DUPLICATES FROM lt_dd02t COMPARING tabname.

    LOOP AT gt_dd02l INTO DATA(ls_02).
      APPEND VALUE #( tabname = ls_02-tabname ) TO lt_valid_tab.
      IF ls_02-tabclass = 'VIEW'.
        APPEND VALUE #( tabname = ls_02-tabname ) TO lt_view_tabs.
      ENDIF.
    ENDLOOP.
    SORT lt_valid_tab BY tabname.
    DELETE ADJACENT DUPLICATES FROM lt_valid_tab COMPARING tabname.

    " Si hay objetos tipo VIEW (ej. BPVG, COSP, COSS), leer sus tablas base
    IF lt_view_tabs IS NOT INITIAL.
      SELECT viewname, tabpos, as4local, as4vers, tabname
        FROM dd26s
        FOR ALL ENTRIES IN @lt_view_tabs
        WHERE viewname = @lt_view_tabs-tabname
          AND as4local = 'A'
        INTO TABLE @lt_view_bases.
      SORT lt_view_bases BY viewname tabpos.
    ENDIF.

    " 3. Consulta masiva #2: UNA sola lectura a DD03L trae los 4 grupos:
    "    CLNT, RAW/LRAW/RSTR, D34R/D16R/D34S/D16S y QUAN/CURR
    IF lt_valid_tab IS NOT INITIAL.
      SELECT tabname, fieldname, as4local, as4vers, position,
             keyflag, rollname, datatype, leng, decimals,
             reftable, reffield
        FROM dd03l
        FOR ALL ENTRIES IN @lt_valid_tab
        WHERE tabname  = @lt_valid_tab-tabname
          AND as4local = 'A'
          AND datatype IN ( 'CLNT',
                            'RAW', 'LRAW', 'RSTR',
                            'D34R', 'D16R', 'D34S', 'D16S',
                            'QUAN', 'CURR' )
        INTO TABLE @gt_dd03l.

      DELETE gt_dd03l WHERE fieldname(1) = '.'.
      SORT gt_dd03l BY tabname position.
    ENDIF.

    " 4. Consulta masiva #3: Clasificación y claves primarias de REFTABLE
    LOOP AT gt_dd03l INTO DATA(ls_f_ref)
      WHERE ( datatype = 'QUAN' OR datatype = 'CURR' )
        AND reftable IS NOT INITIAL.
      APPEND VALUE #( tabname = ls_f_ref-reftable ) TO lt_reftabs.
    ENDLOOP.
    SORT lt_reftabs BY tabname.
    DELETE ADJACENT DUPLICATES FROM lt_reftabs COMPARING tabname.

    IF lt_reftabs IS NOT INITIAL.
      SELECT tabname, as4local, as4vers, tabclass, clidep, viewref
        FROM dd02l
        FOR ALL ENTRIES IN @lt_reftabs
        WHERE tabname  = @lt_reftabs-tabname
          AND as4local = 'A'
        INTO TABLE @lt_ref_dd02l.

      SORT lt_ref_dd02l BY tabname as4vers.
      DELETE ADJACENT DUPLICATES FROM lt_ref_dd02l COMPARING tabname.

      SELECT tabname, fieldname, as4local, as4vers, position
        FROM dd03l
        FOR ALL ENTRIES IN @lt_reftabs
        WHERE tabname  = @lt_reftabs-tabname
          AND as4local = 'A'
          AND keyflag  = 'X'
        INTO TABLE @lt_ref_keys.

      DELETE lt_ref_keys WHERE fieldname(1) = '.'.
      SORT lt_ref_keys BY tabname position.
    ENDIF.

    " 5. Consulta masiva #4: Mapeo con Vistas CDS existentes
    load_cds_mapping(
      EXPORTING it_valid_tabs = lt_valid_tab
      IMPORTING et_cds_map    = lt_cds_map ).

    " 6. Procesar tabla por tabla
    LOOP AT lt_req_tabs INTO DATA(ls_req).
      DATA(ls_sum) = VALUE ty_summary( tabname = ls_req-tabname ).

      READ TABLE lt_dd02t INTO DATA(ls_txt)
        WITH KEY tabname = ls_req-tabname BINARY SEARCH.
      IF sy-subrc = 0.
        ls_sum-ddtext = ls_txt-ddtext.
      ENDIF.

      READ TABLE lt_cds_map INTO DATA(ls_cds)
        WITH KEY tabname = ls_req-tabname BINARY SEARCH.
      DATA(lv_has_cds_map) = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
      IF lv_has_cds_map = abap_true.
        ls_sum-cds_view   = ls_cds-ddlname.
        ls_sum-estado_cds = ls_cds-estado_cds.
        IF ls_sum-estado_cds = 'INACTIVA'.
          add_cell_color( EXPORTING iv_fname = 'ESTADO_CDS'
                                    iv_col   = 6
                                    iv_int   = 1
                          CHANGING  ct_color = ls_sum-t_color ).
        ELSEIF ls_sum-estado_cds = 'ACTIVA'.
          add_cell_color( EXPORTING iv_fname = 'ESTADO_CDS'
                                    iv_col   = 5
                                    iv_int   = 0
                          CHANGING  ct_color = ls_sum-t_color ).
        ENDIF.
      ENDIF.

      " Verificar existencia de la tabla en DD02L
      READ TABLE gt_dd02l INTO DATA(ls_tab)
        WITH KEY tabname = ls_req-tabname BINARY SEARCH.
      IF sy-subrc <> 0.
        ls_sum-estado_tab  = 'NO EXISTE EN SE11'.
        ls_sum-es_compat   = 'N/A'.
        ls_sum-proxy_obj   = '-'.
        ls_sum-cds_target  = '-'.
        ls_sum-codigo_repl = '-'.
        ls_sum-tiene_mandt = 'N/A'.
        ls_sum-campo_mandt = 'TABLA NO EXISTE'.
        ls_sum-accion_cds  = 'VERIFICAR NOMBRE DE TABLA'.
        add_cell_color( EXPORTING iv_col   = 6
                                  iv_int   = 1
                        CHANGING  ct_color = ls_sum-t_color ).
        APPEND ls_sum TO gt_summary.

        DATA(ls_missing) = VALUE ty_detail(
          tabname       = ls_req-tabname
          es_compat     = 'N/A'
          proxy_obj     = '-'
          cds_target    = '-'
          codigo_repl   = '-'
          tiene_mandt   = 'N/A'
          campo_mandt   = 'TABLA NO EXISTE'
          categoria     = 'ERROR TABLA'
          ubicacion_ref = 'NO EXISTE EN DDIC (SE11)'
          nota_tecnica  = 'Verifique el nombre de la tabla ingresada'
        ).
        add_cell_color( EXPORTING iv_col   = 6
                                  iv_int   = 1
                        CHANGING  ct_color = ls_missing-t_color ).
        APPEND ls_missing TO gt_detail.
        CONTINUE.
      ENDIF.

      " Verificar si la tabla tiene Compatibility View / Objeto Proxy (ej. MARC -> NSDM_E_MARC)
      DATA(lv_has_compat)     = abap_false.
      DATA(lv_compat_pointed) = abap_false.
      ls_sum-es_compat   = 'NO'.
      ls_sum-proxy_obj   = '-'.
      ls_sum-cds_target  = '-'.
      ls_sum-codigo_repl = '-'.

      READ TABLE gt_compat INTO DATA(ls_compat_row)
        WITH KEY tabname = ls_req-tabname BINARY SEARCH.
      IF sy-subrc = 0 AND ls_compat_row-cds_target IS NOT INITIAL.
        lv_has_compat     = abap_true.
        ls_sum-proxy_obj  = ls_compat_row-proxy_obj.
        ls_sum-cds_target = ls_compat_row-cds_target.

        DATA(lv_cds_for_stmt) = COND string(
          WHEN ls_sum-cds_view IS NOT INITIAL THEN CONV string( ls_sum-cds_view )
          ELSE |ZCDS_{ ls_req-tabname }| ).
        DATA(lv_trg_low_stmt) = to_lower( CONV string( ls_compat_row-cds_target ) ).
        DATA(lv_tab_low_stmt) = to_lower( CONV string( ls_req-tabname ) ).
        ls_sum-codigo_repl =
          |define root view entity { lv_cds_for_stmt } | &&
          |as select from { lv_trg_low_stmt } as { lv_tab_low_stmt }|.

        IF lv_has_cds_map = abap_true AND ls_cds-from_obj = ls_compat_row-cds_target.
          lv_compat_pointed = abap_true.
        ENDIF.

        IF ls_tab-tabclass = 'TRANSP'.
          ls_sum-es_compat = COND string(
            WHEN lv_compat_pointed = abap_true THEN 'SI (YA APUNTA)'
            ELSE 'SI (REEMPLAZAR)' ).
        ELSE.
          ls_sum-es_compat = 'SI (VISTA CDS)'.
        ENDIF.
      ENDIF.

      DATA(lv_transp_lbl) = COND string(
        WHEN lv_has_compat = abap_true THEN 'TRANSP (COMPAT.)'
        ELSE 'TRANSPARENTE' ).
      ls_sum-estado_tab = SWITCH string( ls_tab-tabclass
        WHEN 'TRANSP'  THEN lv_transp_lbl
        WHEN 'INTTAB'  THEN 'ESTRUCTURA'
        WHEN 'VIEW'    THEN 'VISTA DDIC'
        WHEN 'CLUSTER' THEN 'CLUSTER'
        WHEN 'POOL'    THEN 'POOL'
        ELSE CONV string( ls_tab-tabclass ) ).

      IF ls_tab-tabclass = 'VIEW'.
        add_cell_color( EXPORTING iv_fname = 'ESTADO_TAB'
                                  iv_col   = 6
                                  iv_int   = 1
                        CHANGING  ct_color = ls_sum-t_color ).
      ELSEIF lv_has_compat = abap_true.
        add_cell_color( EXPORTING iv_fname = 'ESTADO_TAB'
                                  iv_col   = 3
                                  iv_int   = 1
                        CHANGING  ct_color = ls_sum-t_color ).
      ENDIF.

      IF lv_has_compat = abap_true.
        DATA(lv_cmp_col) = COND i( WHEN lv_compat_pointed = abap_true THEN 5 ELSE 7 ).
        DATA(lv_cmp_int) = COND i( WHEN lv_compat_pointed = abap_true THEN 0 ELSE 1 ).
        add_cell_color( EXPORTING iv_fname = 'ES_COMPAT'
                                  iv_col   = lv_cmp_col
                                  iv_int   = lv_cmp_int
                        CHANGING  ct_color = ls_sum-t_color ).
        add_cell_color( EXPORTING iv_fname = 'PROXY_OBJ'
                                  iv_col   = lv_cmp_col
                                  iv_int   = lv_cmp_int
                        CHANGING  ct_color = ls_sum-t_color ).
        add_cell_color( EXPORTING iv_fname = 'CDS_TARGET'
                                  iv_col   = lv_cmp_col
                                  iv_int   = lv_cmp_int
                        CHANGING  ct_color = ls_sum-t_color ).
      ENDIF.

      " Armar lista de tablas base si el objeto es una VISTA DDIC (ej. BPVG)
      DATA(lv_view_bases_str) = VALUE string( ).
      IF ls_tab-tabclass = 'VIEW'.
        READ TABLE lt_view_bases TRANSPORTING NO FIELDS
          WITH KEY viewname = ls_req-tabname BINARY SEARCH.
        IF sy-subrc = 0.
          LOOP AT lt_view_bases INTO DATA(ls_vb) FROM sy-tabix.
            IF ls_vb-viewname <> ls_req-tabname.
              EXIT.
            ENDIF.
            lv_view_bases_str = COND string(
              WHEN lv_view_bases_str IS INITIAL THEN |{ ls_vb-tabname }|
              ELSE |{ lv_view_bases_str }, { ls_vb-tabname }| ).
          ENDLOOP.
        ENDIF.
      ENDIF.

      "----------------------------------------------------------------
      " A) Identificar Columna de Mandante (CLNT)
      "----------------------------------------------------------------
      lv_tiene_mandt = 'NO TIENE'.
      lv_campo_mandt = 'NO TIENE'.

      READ TABLE gt_dd03l TRANSPORTING NO FIELDS
        WITH KEY tabname = ls_req-tabname BINARY SEARCH.
      DATA(lv_start_idx) = sy-tabix.

      IF sy-subrc = 0.
        LOOP AT gt_dd03l INTO DATA(ls_clnt) FROM lv_start_idx.
          IF ls_clnt-tabname <> ls_req-tabname.
            EXIT.
          ENDIF.
          IF ls_clnt-datatype = 'CLNT' AND ls_clnt-keyflag = 'X'.
            lv_tiene_mandt = 'SI'.
            lv_campo_mandt = ls_clnt-fieldname.
            EXIT.
          ENDIF.
        ENDLOOP.

        IF lv_tiene_mandt = 'NO TIENE'.
          LOOP AT gt_dd03l INTO DATA(ls_clnt2) FROM lv_start_idx.
            IF ls_clnt2-tabname <> ls_req-tabname.
              EXIT.
            ENDIF.
            IF ls_clnt2-datatype = 'CLNT'.
              lv_tiene_mandt = 'SI (NO CLAVE)'.
              lv_campo_mandt = ls_clnt2-fieldname.
              EXIT.
            ENDIF.
          ENDLOOP.
        ENDIF.
      ENDIF.

      ls_sum-tiene_mandt = lv_tiene_mandt.
      ls_sum-campo_mandt = lv_campo_mandt.

      "----------------------------------------------------------------
      " B) Analizar Columnas RAW, DF34_RAW/DF16_RAW y QUAN/CURR
      "----------------------------------------------------------------
      DATA(lv_rows_added) = 0.
      DATA(lv_raw_str)    = VALUE string( ).
      DATA(lv_dfraw_str)  = VALUE string( ).
      DATA(lv_qc_str)     = VALUE string( ).

      " Si es una tabla TRANSP con Compatibility View (ej. MARC -> NSDM_E_MARC),
      " agregar fila arquitectónica con el objeto Proxy SE16N y el código de reemplazo
      IF ls_tab-tabclass = 'TRANSP' AND lv_has_compat = abap_true.
        DATA(ls_cmp_det) = VALUE ty_detail(
          tabname        = ls_req-tabname
          ddtext         = ls_sum-ddtext
          es_compat      = ls_sum-es_compat
          proxy_obj      = ls_sum-proxy_obj
          cds_target     = ls_sum-cds_target
          codigo_repl    = ls_sum-codigo_repl
          cds_view       = ls_sum-cds_view
          estado_cds     = ls_sum-estado_cds
          tiene_mandt    = lv_tiene_mandt
          campo_mandt    = lv_campo_mandt
          categoria      = 'COMPATIBILITY VIEW'
          fieldname      = '-'
          reftable       = ls_sum-proxy_obj
          ubicacion_ref  = COND string(
            WHEN lv_compat_pointed = abap_true
            THEN |YA APUNTA A { ls_sum-cds_target }|
            ELSE |APUNTAR A: { ls_sum-cds_target }| )
          sugerencia_cds = ls_sum-codigo_repl
          nota_tecnica   = COND string(
            WHEN lv_compat_pointed = abap_true
            THEN |OK: La vista CDS ya selecciona desde { ls_sum-cds_target } (Proxy SE16N: { ls_sum-proxy_obj })|
            ELSE |Proxy SE16N: { ls_sum-proxy_obj } -> Reemplazar SELECT FROM a { ls_sum-cds_target }| )
        ).
        DATA(lv_cdet_col) = COND i( WHEN lv_compat_pointed = abap_true THEN 5 ELSE 7 ).
        DATA(lv_cdet_int) = COND i( WHEN lv_compat_pointed = abap_true THEN 0 ELSE 1 ).
        add_cell_color( EXPORTING iv_fname = 'CATEGORIA'
                                  iv_col   = lv_cdet_col
                                  iv_int   = lv_cdet_int
                        CHANGING  ct_color = ls_cmp_det-t_color ).
        add_cell_color( EXPORTING iv_fname = 'UBICACION_REF'
                                  iv_col   = lv_cdet_col
                                  iv_int   = lv_cdet_int
                        CHANGING  ct_color = ls_cmp_det-t_color ).
        add_cell_color( EXPORTING iv_fname = 'ES_COMPAT'
                                  iv_col   = lv_cdet_col
                                  iv_int   = lv_cdet_int
                        CHANGING  ct_color = ls_cmp_det-t_color ).
        IF ls_cmp_det-estado_cds = 'INACTIVA'.
          add_cell_color( EXPORTING iv_fname = 'ESTADO_CDS'
                                    iv_col   = 6
                                    iv_int   = 1
                          CHANGING  ct_color = ls_cmp_det-t_color ).
        ELSEIF ls_cmp_det-estado_cds = 'ACTIVA'.
          add_cell_color( EXPORTING iv_fname = 'ESTADO_CDS'
                                    iv_col   = 5
                                    iv_int   = 0
                          CHANGING  ct_color = ls_cmp_det-t_color ).
        ENDIF.
        APPEND ls_cmp_det TO gt_detail.
        lv_rows_added = lv_rows_added + 1.
      ENDIF.

      " Si es una VISTA DDIC (VIEW), agregar fila de alerta arquitectónica
      IF ls_tab-tabclass = 'VIEW'.
        DATA(ls_vw_det) = VALUE ty_detail(
          tabname        = ls_req-tabname
          ddtext         = ls_sum-ddtext
          es_compat      = ls_sum-es_compat
          proxy_obj      = ls_sum-proxy_obj
          cds_target     = ls_sum-cds_target
          codigo_repl    = ls_sum-codigo_repl
          cds_view       = ls_sum-cds_view
          estado_cds     = ls_sum-estado_cds
          tiene_mandt    = lv_tiene_mandt
          campo_mandt    = lv_campo_mandt
          categoria      = 'VISTA DDIC (VIEW)'
          fieldname      = '-'
          ubicacion_ref  = 'NO PERMITIDA EN VIEW ENTITY'
          sugerencia_cds = COND string(
            WHEN lv_has_compat = abap_true
            THEN ls_sum-codigo_repl
            WHEN lv_view_bases_str IS NOT INITIAL
            THEN |Replicar tablas físicas: { lv_view_bases_str } (o Create CDS Obsolete sin CDC)|
            ELSE 'Replicar tablas físicas base (o Create CDS View Obsolete sin CDC)' )
          nota_tecnica   = COND string(
            WHEN lv_has_compat = abap_true
            THEN |Vista CDS estándar ({ ls_sum-cds_target }). Usar entidad destino o Create CDS Obsolete (Full Load)|
            WHEN lv_view_bases_str IS NOT INITIAL
            THEN |Objeto VIEW no soportado en View Entity/CDC. Tablas base: { lv_view_bases_str }|
            ELSE 'Objeto VIEW no soportado en View Entity ni CDC; usar Create CDS Obsolete sin CDC' )
        ).
        add_cell_color( EXPORTING iv_fname = 'CATEGORIA'
                                  iv_col   = 6
                                  iv_int   = 1
                        CHANGING  ct_color = ls_vw_det-t_color ).
        add_cell_color( EXPORTING iv_fname = 'UBICACION_REF'
                                  iv_col   = 6
                                  iv_int   = 1
                        CHANGING  ct_color = ls_vw_det-t_color ).
        APPEND ls_vw_det TO gt_detail.
        lv_rows_added = lv_rows_added + 1.
      ENDIF.

      READ TABLE gt_dd03l TRANSPORTING NO FIELDS
        WITH KEY tabname = ls_req-tabname BINARY SEARCH.
      IF sy-subrc = 0.
        LOOP AT gt_dd03l INTO DATA(ls_col) FROM sy-tabix.
          IF ls_col-tabname <> ls_req-tabname.
            EXIT.
          ENDIF.

          IF ls_col-datatype = 'CLNT'.
            CONTINUE.
          ENDIF.

          DATA(ls_det) = VALUE ty_detail(
            tabname     = ls_req-tabname
            ddtext      = ls_sum-ddtext
            es_compat   = ls_sum-es_compat
            proxy_obj   = ls_sum-proxy_obj
            cds_target  = ls_sum-cds_target
            codigo_repl = ls_sum-codigo_repl
            cds_view    = ls_sum-cds_view
            estado_cds  = ls_sum-estado_cds
            tiene_mandt = lv_tiene_mandt
            campo_mandt = lv_campo_mandt
            position    = ls_col-position
            fieldname   = ls_col-fieldname
            es_clave    = COND string( WHEN ls_col-keyflag = 'X' THEN 'SI' ELSE '' )
            datatype    = ls_col-datatype
            leng        = CONV int4( ls_col-leng )
            decimals    = CONV int4( ls_col-decimals )
            reftable    = ls_col-reftable
            reffield    = ls_col-reffield
          ).

          IF ls_det-estado_cds = 'INACTIVA'.
            add_cell_color( EXPORTING iv_fname = 'ESTADO_CDS'
                                      iv_col   = 6
                                      iv_int   = 1
                            CHANGING  ct_color = ls_det-t_color ).
          ELSEIF ls_det-estado_cds = 'ACTIVA'.
            add_cell_color( EXPORTING iv_fname = 'ESTADO_CDS'
                                      iv_col   = 5
                                      iv_int   = 0
                            CHANGING  ct_color = ls_det-t_color ).
          ENDIF.

          IF lv_tiene_mandt = 'NO TIENE'.
            add_cell_color( EXPORTING iv_fname = 'TIENE_MANDT'
                                      iv_col   = 7
                                      iv_int   = 1
                            CHANGING  ct_color = ls_det-t_color ).
            add_cell_color( EXPORTING iv_fname = 'CAMPO_MANDT'
                                      iv_col   = 7
                                      iv_int   = 1
                            CHANGING  ct_color = ls_det-t_color ).
          ENDIF.

          DATA(lv_key_prefix) = COND string( WHEN ls_col-keyflag = 'X' THEN 'key ' ELSE '' ).
          DATA(lv_field_low)  = to_lower( CONV string( ls_col-fieldname ) ).
          DATA(lv_alias)      = clean_alias( ls_col-fieldname ).

          " --- Caso 1: Campos RAW / LRAW / RSTR (RAWSTRING) ---
          IF ls_col-datatype = 'RAW'
             OR ls_col-datatype = 'LRAW'
             OR ls_col-datatype = 'RSTR'.
            ls_sum-cant_raw = ls_sum-cant_raw + 1.
            lv_raw_str = COND string(
              WHEN lv_raw_str IS INITIAL THEN |{ ls_col-fieldname }|
              ELSE |{ lv_raw_str }, { ls_col-fieldname }| ).

            ls_det-categoria = COND string(
              WHEN ls_col-datatype = 'RSTR' THEN 'RAWSTRING'
              ELSE CONV string( ls_col-datatype ) ).

            IF ls_col-datatype = 'RAW' AND ls_det-leng <= 255.
              ls_det-ubicacion_ref  = 'BINARIO -> USAR BINTOHEX'.
              ls_det-sugerencia_cds =
                |{ lv_key_prefix }bintohex( { lv_field_low } ) as { lv_alias }|.
              ls_det-nota_tecnica   =
                |Convertir RAW({ ls_det-leng }) a CHAR({ ls_det-leng * 2 }) con bintohex|.
              add_cell_color( EXPORTING iv_fname = 'CATEGORIA'
                                        iv_col   = 7
                                        iv_int   = 1
                              CHANGING  ct_color = ls_det-t_color ).
            ELSEIF ls_col-datatype = 'RAW' AND ls_det-leng > 255.
              ls_det-ubicacion_ref  = 'RAW > 255 BYTES (LIMITE CDS)'.
              ls_det-sugerencia_cds =
                |// { lv_field_low } -> RAW({ ls_det-leng }): bintohex máx 255 bytes|.
              ls_det-nota_tecnica   =
                'Excede 255 bytes de BINTOHEX en ABAP CDS; evaluar excluir columna'.
              add_cell_color( EXPORTING iv_fname = 'CATEGORIA'
                                        iv_col   = 6
                                        iv_int   = 1
                              CHANGING  ct_color = ls_det-t_color ).
            ELSE.
              ls_det-ubicacion_ref  = 'NO SOPORTADO EN ODP/CDS'.
              ls_det-sugerencia_cds =
                |// Excluir { lv_field_low } ({ ls_det-categoria } no admite bintohex)|.
              ls_det-nota_tecnica   =
                |Tipo { ls_det-categoria } no admite BINTOHEX ni ODP; comentar/excluir|.
              add_cell_color( EXPORTING iv_fname = 'CATEGORIA'
                                        iv_col   = 6
                                        iv_int   = 1
                              CHANGING  ct_color = ls_det-t_color ).
            ENDIF.

            APPEND ls_det TO gt_detail.
            lv_rows_added = lv_rows_added + 1.

          " --- Caso 2: Campos DF34_RAW (D34R) / DF16_RAW (D16R) / SCL ---
          ELSEIF ls_col-datatype = 'D34R'
              OR ls_col-datatype = 'D16R'
              OR ls_col-datatype = 'D34S'
              OR ls_col-datatype = 'D16S'.
            ls_sum-cant_dfraw = ls_sum-cant_dfraw + 1.

            DATA(lv_df_lbl) = SWITCH string( ls_col-datatype
              WHEN 'D34R' THEN 'DF34_RAW'
              WHEN 'D16R' THEN 'DF16_RAW'
              WHEN 'D34S' THEN 'DF34_SCL'
              WHEN 'D16S' THEN 'DF16_SCL'
              ELSE CONV string( ls_col-datatype ) ).

            lv_dfraw_str = COND string(
              WHEN lv_dfraw_str IS INITIAL THEN |{ ls_col-fieldname }({ lv_df_lbl })|
              ELSE |{ lv_dfraw_str }, { ls_col-fieldname }({ lv_df_lbl })| ).

            ls_det-categoria = lv_df_lbl.

            IF ls_col-keyflag = 'X'.
              ls_det-ubicacion_ref  = 'CLAVE DF*_RAW (REVISAR MANUAL)'.
              ls_det-sugerencia_cds =
                |// CLAVE { lv_field_low } ({ lv_df_lbl }): no se comenta automáticamente|.
              ls_det-nota_tecnica   =
                |{ lv_df_lbl } es clave primaria: revisar manualmente antes de excluir|.
            ELSE.
              ls_det-ubicacion_ref  = 'DECFLOAT RAW -> COMENTAR'.
              ls_det-sugerencia_cds =
                |// { lv_field_low } // Excluido: { lv_df_lbl } no soportado en CDS/BQ|.
              ls_det-nota_tecnica   =
                |{ lv_df_lbl } no admite CAST en CDS ni carga ODP/BQ; el motor lo comenta automáticamente|.
            ENDIF.

            add_cell_color( EXPORTING iv_fname = 'CATEGORIA'
                                      iv_col   = 6
                                      iv_int   = 1
                            CHANGING  ct_color = ls_det-t_color ).
            add_cell_color( EXPORTING iv_fname = 'UBICACION_REF'
                                      iv_col   = 6
                                      iv_int   = 1
                            CHANGING  ct_color = ls_det-t_color ).

            APPEND ls_det TO gt_detail.
            lv_rows_added = lv_rows_added + 1.

          " --- Caso 3: Campos QUAN y CURR ---
          ELSEIF ls_col-datatype = 'QUAN' OR ls_col-datatype = 'CURR'.
            IF ls_col-datatype = 'CURR'.
              ls_sum-cant_curr = ls_sum-cant_curr + 1.
            ELSE.
              ls_sum-cant_quan = ls_sum-cant_quan + 1.
            ENDIF.

            lv_qc_str = COND string(
              WHEN lv_qc_str IS INITIAL THEN |{ ls_col-fieldname }({ ls_col-datatype })|
              ELSE |{ lv_qc_str }, { ls_col-fieldname }({ ls_col-datatype })| ).

            ls_det-categoria = ls_col-datatype.

            DATA(lv_cast_len) = nmax( val1 = ls_det-leng
                                      val2 = ls_det-decimals + 1 ).
            IF lv_cast_len > 31.
              lv_cast_len = 31.
            ENDIF.

            ls_det-sugerencia_cds =
              |{ lv_key_prefix }cast( { lv_field_low } | &&
              |as abap.dec({ lv_cast_len },{ ls_det-decimals }) ) as { lv_alias }|.

            IF ls_col-reftable IS INITIAL OR ls_col-reffield IS INITIAL.
              ls_sum-cant_ext = ls_sum-cant_ext + 1.
              ls_det-ubicacion_ref = 'SIN REFERENCIA EN SE11 (CAST)'.
              ls_det-nota_tecnica  =
                'Sin tabla/campo ref. en SE11: aplicar CAST a abap.dec'.
              add_cell_color( EXPORTING iv_fname = 'UBICACION_REF'
                                        iv_col   = 6
                                        iv_int   = 1
                              CHANGING  ct_color = ls_det-t_color ).

            ELSEIF ls_col-reftable = ls_req-tabname.
              IF p_onlyx = abap_true.
                CONTINUE.
              ENDIF.
              ls_det-ubicacion_ref = 'MISMA TABLA (OK o CAST)'.
              DATA(lv_sem) = COND string(
                WHEN ls_col-datatype = 'CURR' THEN '@Semantics.amount.currencyCode'
                ELSE '@Semantics.quantity.unitOfMeasure' ).
              DATA(lv_ref_low) = to_lower( CONV string( ls_col-reffield ) ).
              ls_det-nota_tecnica =
                |Ref. { ls_col-reffield } está en { ls_req-tabname } | &&
                |({ lv_sem }: '{ lv_ref_low }') o usar CAST|.
              add_cell_color( EXPORTING iv_fname = 'UBICACION_REF'
                                        iv_col   = 5
                                        iv_int   = 0
                              CHANGING  ct_color = ls_det-t_color ).

            ELSE.
              ls_sum-cant_ext = ls_sum-cant_ext + 1.

              DATA(lv_keys_str) = VALUE string( ).
              READ TABLE lt_ref_keys TRANSPORTING NO FIELDS
                WITH KEY tabname = ls_col-reftable BINARY SEARCH.
              IF sy-subrc = 0.
                LOOP AT lt_ref_keys INTO DATA(ls_rk) FROM sy-tabix.
                  IF ls_rk-tabname <> ls_col-reftable.
                    EXIT.
                  ENDIF.
                  lv_keys_str = COND string(
                    WHEN lv_keys_str IS INITIAL THEN |{ ls_rk-fieldname }|
                    ELSE |{ lv_keys_str }, { ls_rk-fieldname }| ).
                ENDLOOP.
              ENDIF.
              ls_det-claves_ref = lv_keys_str.

              READ TABLE lt_ref_dd02l INTO DATA(ls_ref02)
                WITH KEY tabname = ls_col-reftable BINARY SEARCH.
              IF sy-subrc = 0 AND ls_ref02-tabclass = 'TRANSP'.
                ls_det-ubicacion_ref = 'OTRA TABLA (JOIN o CAST)'.
                ls_det-nota_tecnica  =
                  |1) CAST a abap.dec o 2) LEFT OUTER JOIN { ls_col-reftable } | &&
                  |(Claves: { lv_keys_str }) para traer { ls_col-reffield }|.
                add_cell_color( EXPORTING iv_fname = 'UBICACION_REF'
                                          iv_col   = 3
                                          iv_int   = 1
                                CHANGING  ct_color = ls_det-t_color ).
              ELSEIF sy-subrc = 0 AND ls_ref02-tabclass = 'INTTAB'.
                ls_det-ubicacion_ref = 'ESTRUCTURA - NO JOIN (CAST)'.
                ls_det-nota_tecnica  =
                  |{ ls_col-reftable } es ESTRUCTURA SE11 (no admite JOIN en CDS). | &&
                  |Aplicar CAST a abap.dec|.
                add_cell_color( EXPORTING iv_fname = 'UBICACION_REF'
                                          iv_col   = 6
                                          iv_int   = 0
                                CHANGING  ct_color = ls_det-t_color ).
              ELSE.
                ls_det-ubicacion_ref = 'REF. EXTERNA (USAR CAST)'.
                ls_det-nota_tecnica  =
                  |Referencia externa { ls_col-reftable }-{ ls_col-reffield }: | &&
                  |se recomienda CAST a abap.dec|.
                add_cell_color( EXPORTING iv_fname = 'UBICACION_REF'
                                          iv_col   = 3
                                          iv_int   = 1
                                CHANGING  ct_color = ls_det-t_color ).
              ENDIF.
            ENDIF.

            APPEND ls_det TO gt_detail.
            lv_rows_added = lv_rows_added + 1.
          ENDIF.
        ENDLOOP.
      ENDIF.

      IF lv_rows_added = 0.
        DATA(ls_clean_det) = VALUE ty_detail(
          tabname        = ls_req-tabname
          ddtext         = ls_sum-ddtext
          es_compat      = ls_sum-es_compat
          proxy_obj      = ls_sum-proxy_obj
          cds_target     = ls_sum-cds_target
          codigo_repl    = ls_sum-codigo_repl
          cds_view       = ls_sum-cds_view
          estado_cds     = ls_sum-estado_cds
          tiene_mandt    = lv_tiene_mandt
          campo_mandt    = lv_campo_mandt
          categoria      = 'SIN RAW/QUAN/CURR'
          fieldname      = '-'
          ubicacion_ref  = 'SIN AJUSTES DE TIPO'
          sugerencia_cds = '-'
          nota_tecnica   = COND string(
            WHEN lv_tiene_mandt = 'NO TIENE'
            THEN 'Tabla sin RAW ni QUAN/CURR. ATENCIÓN: Tabla SIN columna de Mandante'
            ELSE |Tabla limpia (sin RAW ni QUAN/CURR). Mandante: { lv_campo_mandt }| )
        ).
        IF ls_clean_det-estado_cds = 'INACTIVA'.
          add_cell_color( EXPORTING iv_fname = 'ESTADO_CDS'
                                    iv_col   = 6
                                    iv_int   = 1
                          CHANGING  ct_color = ls_clean_det-t_color ).
        ELSEIF ls_clean_det-estado_cds = 'ACTIVA'.
          add_cell_color( EXPORTING iv_fname = 'ESTADO_CDS'
                                    iv_col   = 5
                                    iv_int   = 0
                          CHANGING  ct_color = ls_clean_det-t_color ).
        ENDIF.
        IF lv_tiene_mandt = 'NO TIENE'.
          add_cell_color( EXPORTING iv_fname = 'TIENE_MANDT'
                                    iv_col   = 7
                                    iv_int   = 1
                          CHANGING  ct_color = ls_clean_det-t_color ).
          add_cell_color( EXPORTING iv_fname = 'CAMPO_MANDT'
                                    iv_col   = 7
                                    iv_int   = 1
                          CHANGING  ct_color = ls_clean_det-t_color ).
        ELSE.
          add_cell_color( EXPORTING iv_fname = 'CATEGORIA'
                                    iv_col   = 5
                                    iv_int   = 0
                          CHANGING  ct_color = ls_clean_det-t_color ).
        ENDIF.
        APPEND ls_clean_det TO gt_detail.
      ENDIF.

      " Completar fila de Resumen por Tabla
      ls_sum-lista_raw   = COND string(
        WHEN lv_raw_str   IS INITIAL THEN 'NINGUNA' ELSE lv_raw_str ).
      ls_sum-lista_dfraw = COND string(
        WHEN lv_dfraw_str IS INITIAL THEN 'NINGUNA' ELSE lv_dfraw_str ).
      ls_sum-lista_qc    = COND string(
        WHEN lv_qc_str    IS INITIAL THEN 'NINGUNA' ELSE lv_qc_str ).

      DATA(lv_has_bin) = COND abap_bool(
        WHEN ls_sum-cant_raw > 0 OR ls_sum-cant_dfraw > 0
        THEN abap_true ELSE abap_false ).
      DATA(lv_has_qc)  = COND abap_bool(
        WHEN ls_sum-cant_curr > 0 OR ls_sum-cant_quan > 0
        THEN abap_true ELSE abap_false ).

      IF ls_tab-tabclass = 'VIEW'.
        ls_sum-accion_cds = COND string(
          WHEN lv_has_compat = abap_true
          THEN |VISTA CDS -> Apuntar a { ls_sum-cds_target } o Create CDS Obsolete (Full)|
          WHEN lv_view_bases_str IS NOT INITIAL
          THEN |NO VIEW ENTITY -> Tablas base: { lv_view_bases_str } (o Obsolete Full)|
          ELSE 'NO VIEW ENTITY -> Usar tablas físicas base (o Obsolete Full)' ).
        add_cell_color( EXPORTING iv_fname = 'ACCION_CDS'
                                  iv_col   = 6
                                  iv_int   = 1
                        CHANGING  ct_color = ls_sum-t_color ).
      ELSEIF lv_has_compat = abap_true AND lv_compat_pointed = abap_false.
        ls_sum-accion_cds = COND string(
          WHEN lv_has_bin = abap_true OR lv_has_qc = abap_true
          THEN |APUNTAR A { ls_sum-cds_target } + AJUSTAR COLUMNAS|
          ELSE |APUNTAR SELECT A { ls_sum-cds_target }| ).
        add_cell_color( EXPORTING iv_fname = 'ACCION_CDS'
                                  iv_col   = 7
                                  iv_int   = 1
                        CHANGING  ct_color = ls_sum-t_color ).
      ELSEIF lv_has_bin = abap_true AND lv_has_qc = abap_true.
        ls_sum-accion_cds = COND string(
          WHEN ls_sum-cant_dfraw > 0 THEN 'COMENTAR DF34_RAW + AJUSTAR RAW/QUAN/CURR'
          ELSE 'CORREGIR RAW + QUAN/CURR' ).
        add_cell_color( EXPORTING iv_fname = 'ACCION_CDS'
                                  iv_col   = 6
                                  iv_int   = 1
                        CHANGING  ct_color = ls_sum-t_color ).
      ELSEIF ls_sum-cant_dfraw > 0.
        ls_sum-accion_cds = 'COMENTAR DF34_RAW / DF16_RAW'.
        add_cell_color( EXPORTING iv_fname = 'ACCION_CDS'
                                  iv_col   = 6
                                  iv_int   = 1
                        CHANGING  ct_color = ls_sum-t_color ).
      ELSEIF ls_sum-cant_raw > 0.
        ls_sum-accion_cds = 'CORREGIR RAW (BINTOHEX)'.
        add_cell_color( EXPORTING iv_fname = 'ACCION_CDS'
                                  iv_col   = 7
                                  iv_int   = 0
                        CHANGING  ct_color = ls_sum-t_color ).
      ELSEIF ls_sum-cant_ext > 0.
        ls_sum-accion_cds = 'CORREGIR QUAN/CURR (REF. EXTERNA)'.
        add_cell_color( EXPORTING iv_fname = 'ACCION_CDS'
                                  iv_col   = 3
                                  iv_int   = 1
                        CHANGING  ct_color = ls_sum-t_color ).
      ELSEIF lv_has_qc = abap_true.
        ls_sum-accion_cds = 'REVISAR QUAN/CURR (REF. INTERNA)'.
        add_cell_color( EXPORTING iv_fname = 'ACCION_CDS'
                                  iv_col   = 3
                                  iv_int   = 0
                        CHANGING  ct_color = ls_sum-t_color ).
      ELSE.
        ls_sum-accion_cds = 'OK - SIN AJUSTES DE TIPO'.
        add_cell_color( EXPORTING iv_fname = 'ACCION_CDS'
                                  iv_col   = 5
                                  iv_int   = 0
                        CHANGING  ct_color = ls_sum-t_color ).
      ENDIF.

      IF ls_sum-cant_dfraw > 0.
        add_cell_color( EXPORTING iv_fname = 'CANT_DFRAW'
                                  iv_col   = 6
                                  iv_int   = 1
                        CHANGING  ct_color = ls_sum-t_color ).
        add_cell_color( EXPORTING iv_fname = 'LISTA_DFRAW'
                                  iv_col   = 6
                                  iv_int   = 1
                        CHANGING  ct_color = ls_sum-t_color ).
      ENDIF.

      IF lv_tiene_mandt = 'NO TIENE'.
        add_cell_color( EXPORTING iv_fname = 'TIENE_MANDT'
                                  iv_col   = 7
                                  iv_int   = 1
                        CHANGING  ct_color = ls_sum-t_color ).
        add_cell_color( EXPORTING iv_fname = 'CAMPO_MANDT'
                                  iv_col   = 7
                                  iv_int   = 1
                        CHANGING  ct_color = ls_sum-t_color ).
      ENDIF.

      APPEND ls_sum TO gt_summary.
    ENDLOOP.

    " 7. Si el usuario eligió Modificar y Activar Masivamente (P_APPLY),
    "    procesar todas las vistas CDS de tablas TRANSPARENTES antes del ALV
    IF p_apply = abap_true.
      execute_mass_cds_update( ).
    ENDIF.

    " 8. Mostrar grilla ALV según vista elegida
    IF p_det = abap_true.
      display_detail_alv( ).
    ELSE.
      display_summary_alv( ).
    ENDIF.
  ENDMETHOD.

  METHOD set_col_text.
    TRY.
        DATA(lo_col) = io_cols->get_column( iv_col ).
        lo_col->set_short_text( iv_s ).
        lo_col->set_medium_text( iv_m ).
        lo_col->set_long_text( iv_l ).
      CATCH cx_salv_not_found.
    ENDTRY.
  ENDMETHOD.

  METHOD display_detail_alv.
    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = go_salv
          CHANGING  t_table      = gt_detail ).

        go_salv->get_functions( )->set_all( abap_true ).

        DATA(lo_disp) = go_salv->get_display_settings( ).
        lo_disp->set_striped_pattern( abap_true ).
        lo_disp->set_list_header(
          |Auditoría CDS BigQuery: Detalle ({ lines( gt_summary ) } tablas) - Doble clic Est.CDS = Activar| ).

        DATA(lo_cols) = go_salv->get_columns( ).
        lo_cols->set_optimize( abap_true ).
        TRY.
            lo_cols->set_color_column( 'T_COLOR' ).
          CATCH cx_salv_data_error.
        ENDTRY.

        set_col_text( io_cols = lo_cols iv_col = 'TABNAME'
                      iv_s = 'Tabla'      iv_m = 'Tabla SAP'
                      iv_l = 'Tabla SAP (Doble clic abre SE11)' ).
        set_col_text( io_cols = lo_cols iv_col = 'DDTEXT'
                      iv_s = 'Descrip.'   iv_m = 'Descripción Tabla'
                      iv_l = 'Descripción de la Tabla (SE11)' ).
        set_col_text( io_cols = lo_cols iv_col = 'ES_COMPAT'
                      iv_s = '¿Compat.?'  iv_m = 'Compatibility View'
                      iv_l = '¿Tiene Compatibility View / Proxy?' ).
        set_col_text( io_cols = lo_cols iv_col = 'PROXY_OBJ'
                      iv_s = 'Obj.Proxy'  iv_m = 'Objeto Proxy SE16N'
                      iv_l = 'Objeto Proxy SE16N (Doble clic SE11)' ).
        set_col_text( io_cols = lo_cols iv_col = 'CDS_TARGET'
                      iv_s = 'Ent.Dest.'  iv_m = 'Entidad Reemplazo'
                      iv_l = 'Entidad CDS Destino (Doble clic ve DDL)' ).
        set_col_text( io_cols = lo_cols iv_col = 'CODIGO_REPL'
                      iv_s = 'Reemplazo'  iv_m = 'Código Reemplazo'
                      iv_l = 'Sentencia DEFINE/SELECT de Reemplazo' ).
        set_col_text( io_cols = lo_cols iv_col = 'CDS_VIEW'
                      iv_s = 'Vista CDS'  iv_m = 'Vista CDS'
                      iv_l = 'Vista CDS (Doble clic ve código)' ).
        set_col_text( io_cols = lo_cols iv_col = 'ESTADO_CDS'
                      iv_s = 'Est. CDS'   iv_m = 'Estado CDS (Act.)'
                      iv_l = 'Estado CDS (Doble clic Modifica/Activa)' ).
        set_col_text( io_cols = lo_cols iv_col = 'TIENE_MANDT'
                      iv_s = '¿Mandante?' iv_m = '¿Tiene Mandante?'
                      iv_l = '¿Tiene Columna de Mandante?' ).
        set_col_text( io_cols = lo_cols iv_col = 'CAMPO_MANDT'
                      iv_s = 'Col.Mandt'  iv_m = 'Columna Mandante'
                      iv_l = 'Columna Mandante (o NO TIENE)' ).
        set_col_text( io_cols = lo_cols iv_col = 'CATEGORIA'
                      iv_s = 'Categoría'  iv_m = 'Categoría Hallazgo'
                      iv_l = 'Categoría (RAW/DF34_RAW/CURR/QUAN)' ).
        set_col_text( io_cols = lo_cols iv_col = 'POSITION'
                      iv_s = 'Pos.'       iv_m = 'Posición SE11'
                      iv_l = 'Posición del Campo en SE11' ).
        set_col_text( io_cols = lo_cols iv_col = 'FIELDNAME'
                      iv_s = 'Columna'    iv_m = 'Columna a Revisar'
                      iv_l = 'Nombre de Columna a Revisar' ).
        set_col_text( io_cols = lo_cols iv_col = 'ES_CLAVE'
                      iv_s = 'Clave'      iv_m = '¿Es Clave (KEY)?'
                      iv_l = '¿Es Clave Primaria (KEY)?' ).
        set_col_text( io_cols = lo_cols iv_col = 'DATATYPE'
                      iv_s = 'Tipo Dato'  iv_m = 'Tipo Dato DDIC'
                      iv_l = 'Tipo de Dato ABAP Dictionary' ).
        set_col_text( io_cols = lo_cols iv_col = 'LENG'
                      iv_s = 'Largo'      iv_m = 'Largo (LENG)'
                      iv_l = 'Longitud del Campo en SE11' ).
        set_col_text( io_cols = lo_cols iv_col = 'DECIMALS'
                      iv_s = 'Decimales'  iv_m = 'Decimales'
                      iv_l = 'Cantidad de Decimales en SE11' ).
        set_col_text( io_cols = lo_cols iv_col = 'REFTABLE'
                      iv_s = 'Tab.Ref.'   iv_m = 'Tabla Ref. SE11'
                      iv_l = 'Tabla Referencia SE11 (Doble clic)' ).
        set_col_text( io_cols = lo_cols iv_col = 'REFFIELD'
                      iv_s = 'Cpo.Ref.'   iv_m = 'Campo Ref. SE11'
                      iv_l = 'Campo Referencia Moneda/UM (SE11)' ).
        set_col_text( io_cols = lo_cols iv_col = 'UBICACION_REF'
                      iv_s = 'Ubic.Ref.'  iv_m = 'Ubicación Ref. SE11'
                      iv_l = 'Diagnóstico Referencia SE11' ).
        set_col_text( io_cols = lo_cols iv_col = 'CLAVES_REF'
                      iv_s = 'Claves Ref' iv_m = 'Claves Tabla Ref.'
                      iv_l = 'Claves Primarias Tabla Ref. (JOIN)' ).
        set_col_text( io_cols = lo_cols iv_col = 'SUGERENCIA_CDS'
                      iv_s = 'Código CDS' iv_m = 'Expresión CDS'
                      iv_l = 'Expresión CDS Sugerida' ).
        set_col_text( io_cols = lo_cols iv_col = 'NOTA_TECNICA'
                      iv_s = 'Guía / Log' iv_m = 'Guía / Resultado'
                      iv_l = 'Guía de Acción o Resultado de Activación' ).

        go_salv->get_layout( )->set_key(
          VALUE salv_s_layout_key( report = sy-repid handle = 'DET' ) ).
        go_salv->get_layout( )->set_save_restriction( if_salv_c_layout=>restrict_none ).

        SET HANDLER on_double_click FOR go_salv->get_event( ).

        go_salv->display( ).

      CATCH cx_salv_msg INTO DATA(lx_msg).
        MESSAGE lx_msg->get_text( ) TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD display_summary_alv.
    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = go_salv
          CHANGING  t_table      = gt_summary ).

        go_salv->get_functions( )->set_all( abap_true ).

        DATA(lo_disp) = go_salv->get_display_settings( ).
        lo_disp->set_striped_pattern( abap_true ).
        lo_disp->set_list_header(
          |Auditoría CDS BigQuery: Resumen ({ lines( gt_summary ) } tablas) - Doble clic Est./Acción = Activar| ).

        DATA(lo_cols) = go_salv->get_columns( ).
        lo_cols->set_optimize( abap_true ).
        TRY.
            lo_cols->set_color_column( 'T_COLOR' ).
          CATCH cx_salv_data_error.
        ENDTRY.

        set_col_text( io_cols = lo_cols iv_col = 'TABNAME'
                      iv_s = 'Tabla'      iv_m = 'Tabla SAP'
                      iv_l = 'Tabla SAP (Doble clic abre SE11)' ).
        set_col_text( io_cols = lo_cols iv_col = 'DDTEXT'
                      iv_s = 'Descrip.'   iv_m = 'Descripción Tabla'
                      iv_l = 'Descripción de la Tabla (SE11)' ).
        set_col_text( io_cols = lo_cols iv_col = 'ESTADO_TAB'
                      iv_s = 'Tipo Tab.'  iv_m = 'Clase Tabla SE11'
                      iv_l = 'Clase de Tabla en SE11 (TRANSP/VIEW)' ).
        set_col_text( io_cols = lo_cols iv_col = 'ES_COMPAT'
                      iv_s = '¿Compat.?'  iv_m = 'Compatibility View'
                      iv_l = '¿Tiene Compatibility View / Proxy?' ).
        set_col_text( io_cols = lo_cols iv_col = 'PROXY_OBJ'
                      iv_s = 'Obj.Proxy'  iv_m = 'Objeto Proxy SE16N'
                      iv_l = 'Objeto Proxy SE16N (Doble clic SE11)' ).
        set_col_text( io_cols = lo_cols iv_col = 'CDS_TARGET'
                      iv_s = 'Ent.Dest.'  iv_m = 'Entidad Reemplazo'
                      iv_l = 'Entidad CDS Destino (Doble clic ve DDL)' ).
        set_col_text( io_cols = lo_cols iv_col = 'CODIGO_REPL'
                      iv_s = 'Reemplazo'  iv_m = 'Código Reemplazo'
                      iv_l = 'Sentencia DEFINE/SELECT de Reemplazo' ).
        set_col_text( io_cols = lo_cols iv_col = 'CDS_VIEW'
                      iv_s = 'Vista CDS'  iv_m = 'Vista CDS'
                      iv_l = 'Vista CDS (Doble clic ve código)' ).
        set_col_text( io_cols = lo_cols iv_col = 'ESTADO_CDS'
                      iv_s = 'Est. CDS'   iv_m = 'Estado CDS (Act.)'
                      iv_l = 'Estado CDS (Doble clic Modifica/Activa)' ).
        set_col_text( io_cols = lo_cols iv_col = 'TIENE_MANDT'
                      iv_s = '¿Mandante?' iv_m = '¿Tiene Mandante?'
                      iv_l = '¿Tiene Columna de Mandante?' ).
        set_col_text( io_cols = lo_cols iv_col = 'CAMPO_MANDT'
                      iv_s = 'Col.Mandt'  iv_m = 'Columna Mandante'
                      iv_l = 'Columna Mandante (o NO TIENE)' ).
        set_col_text( io_cols = lo_cols iv_col = 'CANT_RAW'
                      iv_s = 'Cant.RAW'   iv_m = 'Cantidad RAW'
                      iv_l = 'Cantidad de Columnas RAW / Binarias' ).
        set_col_text( io_cols = lo_cols iv_col = 'LISTA_RAW'
                      iv_s = 'Cols.RAW'   iv_m = 'Columnas RAW'
                      iv_l = 'Listado de Columnas RAW Detectadas' ).
        set_col_text( io_cols = lo_cols iv_col = 'CANT_DFRAW'
                      iv_s = 'Cant.DFRAW' iv_m = 'Cant. DF34/16_RAW'
                      iv_l = 'Cantidad Columnas DF34_RAW / DF16_RAW' ).
        set_col_text( io_cols = lo_cols iv_col = 'LISTA_DFRAW'
                      iv_s = 'Cols.DFRAW' iv_m = 'Columnas DF34_RAW'
                      iv_l = 'Listado Columnas DF34_RAW / DF16_RAW' ).
        set_col_text( io_cols = lo_cols iv_col = 'CANT_CURR'
                      iv_s = 'Cant.CURR'  iv_m = 'Cantidad CURR'
                      iv_l = 'Cantidad de Columnas Moneda (CURR)' ).
        set_col_text( io_cols = lo_cols iv_col = 'CANT_QUAN'
                      iv_s = 'Cant.QUAN'  iv_m = 'Cantidad QUAN'
                      iv_l = 'Cantidad de Columnas Cantidad (QUAN)' ).
        set_col_text( io_cols = lo_cols iv_col = 'CANT_EXT'
                      iv_s = 'Ref.Ext.'   iv_m = 'Refs. Otra Tabla'
                      iv_l = 'QUAN/CURR con Ref. Fuera de Tabla' ).
        set_col_text( io_cols = lo_cols iv_col = 'LISTA_QC'
                      iv_s = 'Cols.Q/C'   iv_m = 'Columnas QUAN/CURR'
                      iv_l = 'Listado Columnas QUAN y CURR' ).
        set_col_text( io_cols = lo_cols iv_col = 'ACCION_CDS'
                      iv_s = 'Acción CDS' iv_m = 'Acción / Resultado'
                      iv_l = 'Acción o Resultado (Doble clic Activa)' ).

        go_salv->get_layout( )->set_key(
          VALUE salv_s_layout_key( report = sy-repid handle = 'RES' ) ).
        go_salv->get_layout( )->set_save_restriction( if_salv_c_layout=>restrict_none ).

        SET HANDLER on_double_click FOR go_salv->get_event( ).

        go_salv->display( ).

      CATCH cx_salv_msg INTO DATA(lx_msg).
        MESSAGE lx_msg->get_text( ) TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD on_double_click.
    IF p_det = abap_true.
      READ TABLE gt_detail INTO DATA(ls_det) INDEX row.
      IF sy-subrc <> 0.
        RETURN.
      ENDIF.

      IF column = 'REFTABLE' AND ls_det-reftable IS NOT INITIAL AND ls_det-reftable <> '-'.
        open_se11_table( ls_det-reftable ).
      ELSEIF column = 'PROXY_OBJ' AND ls_det-proxy_obj IS NOT INITIAL AND ls_det-proxy_obj <> '-'.
        open_se11_table( ls_det-proxy_obj ).
      ELSEIF column = 'CDS_TARGET' AND ls_det-cds_target IS NOT INITIAL AND ls_det-cds_target <> '-'.
        preview_std_cds_target( iv_cds_target = ls_det-cds_target
                                iv_proxy_obj  = ls_det-proxy_obj ).
      ELSEIF column = 'ESTADO_CDS' AND ls_det-cds_view IS NOT INITIAL.
        prompt_single_cds_action( iv_tabname = ls_det-tabname
                                  iv_ddlname = ls_det-cds_view ).
      ELSEIF ( column = 'CDS_VIEW' OR column = 'SUGERENCIA_CDS' OR column = 'CODIGO_REPL' )
             AND ls_det-cds_view IS NOT INITIAL.
        preview_cds_code( iv_ddlname = ls_det-cds_view
                          iv_tabname = ls_det-tabname ).
      ELSEIF column = 'CODIGO_REPL' AND ls_det-codigo_repl IS NOT INITIAL AND ls_det-codigo_repl <> '-'.
        MESSAGE ls_det-codigo_repl TYPE 'I'.
      ELSEIF ls_det-tabname IS NOT INITIAL.
        open_se11_table( ls_det-tabname ).
      ENDIF.

    ELSE.
      READ TABLE gt_summary INTO DATA(ls_sum) INDEX row.
      IF sy-subrc <> 0.
        RETURN.
      ENDIF.

      IF column = 'PROXY_OBJ' AND ls_sum-proxy_obj IS NOT INITIAL AND ls_sum-proxy_obj <> '-'.
        open_se11_table( ls_sum-proxy_obj ).
      ELSEIF column = 'CDS_TARGET' AND ls_sum-cds_target IS NOT INITIAL AND ls_sum-cds_target <> '-'.
        preview_std_cds_target( iv_cds_target = ls_sum-cds_target
                                iv_proxy_obj  = ls_sum-proxy_obj ).
      ELSEIF ( column = 'ESTADO_CDS' OR column = 'ACCION_CDS' )
         AND ls_sum-cds_view IS NOT INITIAL.
        prompt_single_cds_action( iv_tabname = ls_sum-tabname
                                  iv_ddlname = ls_sum-cds_view ).
      ELSEIF ( column = 'CDS_VIEW' OR column = 'CODIGO_REPL' )
             AND ls_sum-cds_view IS NOT INITIAL.
        preview_cds_code( iv_ddlname = ls_sum-cds_view
                          iv_tabname = ls_sum-tabname ).
      ELSEIF column = 'CODIGO_REPL' AND ls_sum-codigo_repl IS NOT INITIAL AND ls_sum-codigo_repl <> '-'.
        MESSAGE ls_sum-codigo_repl TYPE 'I'.
      ELSEIF ls_sum-tabname IS NOT INITIAL.
        open_se11_table( ls_sum-tabname ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD open_se11_table.
    DATA(lv_obj) = CONV dd02l-tabname( iv_tabname ).
    CALL FUNCTION 'RS_TOOL_ACCESS'
      EXPORTING
        operation   = 'SHOW'
        object_name = lv_obj
        object_type = 'TABL'
      EXCEPTIONS
        OTHERS      = 1.
    IF sy-subrc <> 0.
      MESSAGE |No fue posible abrir { lv_obj } en SE11.|
        TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.
  ENDMETHOD.

  METHOD preview_std_cds_target.
    DATA: lv_objname TYPE ddldependency-objectname,
          lv_ddlname TYPE ddddlsrc-ddlname,
          lt_lines   TYPE tt_string_list.

    lv_objname = CONV ddldependency-objectname( iv_cds_target ).
    SELECT SINGLE ddlname
      FROM ddldependency
      WHERE objectname = @lv_objname
        AND state      = 'A'
      INTO @lv_ddlname.

    IF sy-subrc <> 0 OR lv_ddlname IS INITIAL.
      lv_ddlname = CONV ddddlsrc-ddlname( iv_cds_target ).
    ENDIF.

    DATA(lv_src) = VALUE string( ).
    SELECT SINGLE source
      FROM ddddlsrc
      WHERE ddlname  = @lv_ddlname
        AND as4local = 'A'
      INTO @lv_src.

    IF sy-subrc <> 0 OR lv_src IS INITIAL.
      MESSAGE |Entidad destino: { iv_cds_target } (Proxy SE16N: { iv_proxy_obj }).|
        TYPE 'I'.
      RETURN.
    ENDIF.

    DATA(lv_clean) = strip_internal_baseinfo( lv_src ).
    SPLIT lv_clean AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
    cl_demo_output=>display_data(
      value = lt_lines
      name  = |Definición Estándar SAP: { iv_cds_target } (DDL: { lv_ddlname }, Proxy: { iv_proxy_obj })| ).
  ENDMETHOD.

  METHOD trim_spaces.
    rv_str = iv_str.
    SHIFT rv_str LEFT DELETING LEADING space.
    SHIFT rv_str LEFT DELETING LEADING cl_abap_char_utilities=>horizontal_tab.
    SHIFT rv_str LEFT DELETING LEADING space.
    DATA(lv_len) = strlen( rv_str ).
    WHILE lv_len > 0.
      DATA(lv_pos) = lv_len - 1.
      DATA(lv_ch)  = rv_str+lv_pos(1).
      IF lv_ch = ` ` OR lv_ch = cl_abap_char_utilities=>horizontal_tab.
        lv_len = lv_pos.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
    IF lv_len = 0.
      rv_str = ''.
    ELSE.
      rv_str = rv_str(lv_len).
    ENDIF.
  ENDMETHOD.

  METHOD strip_internal_baseinfo.
    " Elimina el bloque /*+[internal] { "BASEINFO": ... }*/ que SAP
    " adjunta automáticamente al final de DDDDLSRC-SOURCE tras activar
    rv_clean = iv_source.
    DO 5 TIMES.
      FIND FIRST OCCURRENCE OF '/*+[internal]' IN rv_clean
        IGNORING CASE MATCH OFFSET DATA(lv_off).
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      DATA(lv_head) = COND string( WHEN lv_off > 0 THEN rv_clean(lv_off) ELSE '' ).
      DATA(lv_tail) = rv_clean+lv_off.
      FIND FIRST OCCURRENCE OF '*/' IN lv_tail MATCH OFFSET DATA(lv_end).
      IF sy-subrc = 0.
        DATA(lv_after) = lv_end + 2.
        IF lv_after < strlen( lv_tail ).
          rv_clean = lv_head && lv_tail+lv_after.
        ELSE.
          rv_clean = lv_head.
        ENDIF.
      ELSE.
        rv_clean = lv_head.
        EXIT.
      ENDIF.
    ENDDO.
  ENDMETHOD.

  METHOD split_inline_comment.
    CLEAR: ev_indent, ev_code, ev_cmt.
    DATA(lv_len) = strlen( iv_line ).
    IF lv_len = 0.
      RETURN.
    ENDIF.

    DATA(lv_i) = 0.
    WHILE lv_i < lv_len.
      DATA(lv_sp) = iv_line+lv_i(1).
      IF lv_sp = ` ` OR lv_sp = cl_abap_char_utilities=>horizontal_tab.
        lv_i = lv_i + 1.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
    ev_indent = COND string( WHEN lv_i > 0 THEN iv_line(lv_i) ELSE '' ).

    DATA(lv_in_sq)   = abap_false.
    DATA(lv_cmt_pos) = -1.
    DATA(lv_pos)     = 0.
    WHILE lv_pos < lv_len.
      DATA(lv_c) = iv_line+lv_pos(1).
      IF lv_c = ''''.
        lv_in_sq = COND abap_bool( WHEN lv_in_sq = abap_true
                                   THEN abap_false ELSE abap_true ).
      ELSEIF lv_in_sq = abap_false AND ( lv_pos + 1 ) < lv_len.
        DATA(lv_two) = iv_line+lv_pos(2).
        IF lv_two = '//' OR lv_two = '--'.
          lv_cmt_pos = lv_pos.
          EXIT.
        ENDIF.
      ENDIF.
      lv_pos = lv_pos + 1.
    ENDWHILE.

    IF lv_cmt_pos >= 0.
      DATA(lv_raw_c) = COND string( WHEN lv_cmt_pos > 0
                                    THEN iv_line(lv_cmt_pos) ELSE '' ).
      DATA(lv_raw_m) = substring( val = iv_line off = lv_cmt_pos ).
      ev_code = trim_spaces( lv_raw_c ).
      ev_cmt  = trim_spaces( lv_raw_m ).
    ELSE.
      ev_code = trim_spaces( iv_line ).
    ENDIF.
  ENDMETHOD.

  METHOD count_code_depths.
    ev_paren_delta = 0.
    ev_brace_delta = 0.
    ev_brack_delta = 0.
    ev_case_delta  = 0.

    DATA(lv_len)   = strlen( iv_code ).
    DATA(lv_in_sq) = abap_false.
    DATA(lv_unq)   = VALUE string( ).
    DATA(lv_pos)   = 0.

    WHILE lv_pos < lv_len.
      DATA(lv_c) = iv_code+lv_pos(1).
      IF lv_c = ''''.
        lv_in_sq = COND abap_bool( WHEN lv_in_sq = abap_true
                                   THEN abap_false ELSE abap_true ).
        lv_unq = lv_unq && ` `.
      ELSEIF lv_in_sq = abap_false.
        CASE lv_c.
          WHEN '('.
            ev_paren_delta = ev_paren_delta + 1.
            lv_unq = lv_unq && ` `.
          WHEN ')'.
            ev_paren_delta = ev_paren_delta - 1.
            lv_unq = lv_unq && ` `.
          WHEN '{'.
            ev_brace_delta = ev_brace_delta + 1.
            lv_unq = lv_unq && ` `.
          WHEN '}'.
            ev_brace_delta = ev_brace_delta - 1.
            lv_unq = lv_unq && ` `.
          WHEN '['.
            ev_brack_delta = ev_brack_delta + 1.
            lv_unq = lv_unq && ` `.
          WHEN ']'.
            ev_brack_delta = ev_brack_delta - 1.
            lv_unq = lv_unq && ` `.
          WHEN ','.
            lv_unq = lv_unq && ` `.
          WHEN OTHERS.
            lv_unq = lv_unq && lv_c.
        ENDCASE.
      ELSE.
        lv_unq = lv_unq && ` `.
      ENDIF.
      lv_pos = lv_pos + 1.
    ENDWHILE.

    lv_unq = condense( to_lower( lv_unq ) ).
    IF lv_unq IS NOT INITIAL.
      SPLIT lv_unq AT space INTO TABLE DATA(lt_words).
      LOOP AT lt_words INTO DATA(lv_w).
        IF lv_w = 'case'.
          ev_case_delta = ev_case_delta + 1.
        ELSEIF lv_w = 'end'.
          ev_case_delta = ev_case_delta - 1.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD rewrite_compat_from_clause.
    " Reescribe en la cabecera (lt_prefix) únicamente la cláusula:
    "   as select [distinct] from <tabla>  -->  as select [distinct] from <cds_target> as <tabla>
    " sin tocar anotaciones (@Analytics / changeDataCapture.automatic: true) ni comentarios.
    cv_compat_chg = abap_false.

    DATA(lv_tab_low) = to_lower( condense( CONV string( iv_tabname ) ) ).
    DATA(lv_prx_low) = to_lower( condense( CONV string( iv_proxy_obj ) ) ).
    DATA(lv_trg_low) = to_lower( condense( CONV string( iv_cds_target ) ) ).
    IF lv_tab_low IS INITIAL OR lv_trg_low IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_in_blk)    = abap_false.
    DATA(lv_seen_sel)  = abap_false.
    DATA(lv_wait_src)  = abap_false.
    DATA(lv_total_prf) = lines( ct_prefix ).

    LOOP AT ct_prefix ASSIGNING FIELD-SYMBOL(<fs_pl>).
      DATA(lv_p_idx) = sy-tabix.
      DATA(lv_pt)    = trim_spaces( <fs_pl> ).

      IF lv_in_blk = abap_true.
        IF lv_pt CS '*/'.
          lv_in_blk = abap_false.
        ENDIF.
        CONTINUE.
      ENDIF.

      IF strlen( lv_pt ) >= 2 AND lv_pt(2) = '/*'.
        IF NOT ( lv_pt CS '*/' ).
          lv_in_blk = abap_true.
        ENDIF.
        CONTINUE.
      ENDIF.

      IF lv_pt IS INITIAL
         OR ( strlen( lv_pt ) >= 2 AND ( lv_pt(2) = '//' OR lv_pt(2) = '--' ) )
         OR lv_pt(1) = '*'
         OR lv_pt(1) = '@'.
        CONTINUE.
      ENDIF.

      split_inline_comment(
        EXPORTING iv_line   = <fs_pl>
        IMPORTING ev_indent = DATA(lv_pind)
                  ev_code   = DATA(lv_pcode)
                  ev_cmt    = DATA(lv_pcmt) ).

      IF lv_pcode IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA(lv_norm) = lv_pcode.
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN lv_norm WITH ` `.
      REPLACE ALL OCCURRENCES OF '{' IN lv_norm WITH ` { `.
      lv_norm = condense( lv_norm ).
      SPLIT lv_norm AT space INTO TABLE DATA(lt_ptoks).
      DATA(lv_ntoks) = lines( lt_ptoks ).
      DATA(lv_ti)    = 1.

      WHILE lv_ti <= lv_ntoks.
        DATA(lv_tok)     = lt_ptoks[ lv_ti ].
        DATA(lv_tok_low) = to_lower( lv_tok ).

        " Caso borde: 'from' quedó al final de la línea anterior y la tabla va aquí
        IF lv_wait_src = abap_true.
          DATA(lv_src_w) = lv_tok_low.
          REPLACE ALL OCCURRENCES OF '"' IN lv_src_w WITH ''.
          IF lv_src_w = lv_trg_low.
            RETURN.
          ENDIF.
          IF lv_src_w = lv_tab_low
             OR ( lv_prx_low IS NOT INITIAL AND lv_src_w = lv_prx_low ).
            DATA(lv_has_al_w) = abap_false.
            DATA(lv_nx_tw)    = lv_ti + 1.
            IF lv_nx_tw <= lv_ntoks AND to_lower( lt_ptoks[ lv_nx_tw ] ) = 'as'.
              lv_has_al_w = abap_true.
            ENDIF.
            DATA(lv_rep_w) = COND string(
              WHEN lv_has_al_w = abap_true THEN lv_trg_low
              ELSE |{ lv_trg_low } as { lv_tab_low }| ).
            DATA(lv_new_cw) = lv_pcode.
            REPLACE FIRST OCCURRENCE OF lv_tok IN lv_new_cw WITH lv_rep_w IGNORING CASE.
            <fs_pl> = lv_pind && lv_new_cw &&
                      COND string( WHEN lv_pcmt IS NOT INITIAL THEN | { lv_pcmt }| ELSE '' ).
            cv_compat_chg = abap_true.
          ENDIF.
          RETURN.
        ENDIF.

        IF lv_tok_low = 'select'.
          lv_seen_sel = abap_true.
        ELSEIF lv_seen_sel = abap_true AND lv_tok_low = 'from'.
          IF lv_ti = lv_ntoks.
            lv_wait_src = abap_true.
            EXIT.
          ENDIF.

          DATA(lv_src_idx)   = lv_ti + 1.
          DATA(lv_src_tok)   = lt_ptoks[ lv_src_idx ].
          DATA(lv_src_clean) = to_lower( lv_src_tok ).
          REPLACE ALL OCCURRENCES OF '"' IN lv_src_clean WITH ''.

          " Si ya apunta a la entidad destino (ej. nsdm_e_marc), no tocar
          IF lv_src_clean = lv_trg_low.
            RETURN.
          ENDIF.

          IF lv_src_clean = lv_tab_low
             OR ( lv_prx_low IS NOT INITIAL AND lv_src_clean = lv_prx_low ).
            " Verificar si ya tiene alias ('as <alias>') en esta misma línea o la siguiente
            DATA(lv_has_alias) = abap_false.
            DATA(lv_as_check)  = lv_ti + 2.
            IF lv_as_check <= lv_ntoks AND to_lower( lt_ptoks[ lv_as_check ] ) = 'as'.
              lv_has_alias = abap_true.
            ELSE.
              DATA(lv_scan_p) = lv_p_idx + 1.
              WHILE lv_scan_p <= lv_total_prf.
                split_inline_comment(
                  EXPORTING iv_line = ct_prefix[ lv_scan_p ]
                  IMPORTING ev_code = DATA(lv_nxt_pcode) ).
                IF lv_nxt_pcode IS NOT INITIAL AND lv_nxt_pcode(1) <> '@'.
                  DATA(lv_nxt_pl) = to_lower( lv_nxt_pcode ).
                  IF strlen( lv_nxt_pl ) >= 4 AND lv_nxt_pl(3) = 'as '.
                    lv_has_alias = abap_true.
                  ENDIF.
                  EXIT.
                ENDIF.
                lv_scan_p = lv_scan_p + 1.
              ENDWHILE.
            ENDIF.

            DATA(lv_rep_str) = COND string(
              WHEN lv_has_alias = abap_true THEN lv_trg_low
              ELSE |{ lv_trg_low } as { lv_tab_low }| ).

            " Reemplazar únicamente después de la palabra 'from' para nunca alterar
            " el nombre de la propia vista CDS (ej. ZCDS_MARC) en la misma línea
            DATA(lv_mask) = to_lower( lv_pcode ).
            REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab
              IN lv_mask WITH ` `.
            REPLACE ALL OCCURRENCES OF '{' IN lv_mask WITH ` `.
            DATA(lv_padded) = ` ` && lv_mask && ` `.

            DATA(lv_after_from_pos) = -1.
            FIND FIRST OCCURRENCE OF ' select ' IN lv_padded MATCH OFFSET DATA(lv_sel_off).
            IF sy-subrc = 0.
              DATA(lv_sub_sel) = substring( val = lv_padded off = lv_sel_off ).
              FIND FIRST OCCURRENCE OF ' from ' IN lv_sub_sel MATCH OFFSET DATA(lv_rel_fr).
              IF sy-subrc = 0.
                lv_after_from_pos = lv_sel_off + lv_rel_fr + 4.
              ENDIF.
            ELSE.
              FIND FIRST OCCURRENCE OF ' from ' IN lv_padded MATCH OFFSET DATA(lv_fr_off).
              IF sy-subrc = 0.
                lv_after_from_pos = lv_fr_off + 4.
              ENDIF.
            ENDIF.

            IF lv_after_from_pos >= 0 AND lv_after_from_pos < strlen( lv_pcode ).
              DATA(lv_head_fr) = substring( val = lv_pcode len = lv_after_from_pos ).
              DATA(lv_tail_fr) = substring( val = lv_pcode off = lv_after_from_pos ).
              REPLACE FIRST OCCURRENCE OF lv_src_tok IN lv_tail_fr
                WITH lv_rep_str IGNORING CASE.
              DATA(lv_new_code) = lv_head_fr && lv_tail_fr.
              <fs_pl> = lv_pind && lv_new_code &&
                        COND string( WHEN lv_pcmt IS NOT INITIAL THEN | { lv_pcmt }| ELSE '' ).
              cv_compat_chg = abap_true.
            ENDIF.
          ENDIF.
          RETURN.
        ENDIF.

        lv_ti = lv_ti + 1.
      ENDWHILE.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_modified_cds_source.
    " Motor unificado (Vista Previa + Modificación Real):
    " 1) Elimina el bloque interno /*+[internal] { "BASEINFO": ... }*/
    " 2) Separa limpiamente cabecera, cuerpo de proyección { ... } y pie
    " 2B) Si P_COMP = 'X' y la tabla tiene Compatibility View (ej. MARC),
    "     reescribe 'as select from marc' -> 'as select from nsdm_e_marc as marc'
    "     sin tocar changeDataCapture.automatic: true
    " 3) Aplica bintohex(RAW <= 255), cast(QUAN/CURR as abap.dec),
    "    comenta automáticamente DF34_RAW/DF16_RAW/LRAW/RSTR no clave
    "    y comenta @Semantics del campo casteado o comentado
    " 4) Normaliza TODAS las comas del bloque { ... }:
    "    - Cada elemento activo (1..N-1) termina exactamente con una coma ','
    "    - El último elemento activo (N) antes de '}' NO lleva coma final
    TYPES:
      BEGIN OF ty_stage_line,
        text        TYPE string,
        is_new_cast TYPE abap_bool,
        is_active   TYPE abap_bool,
        indent      TYPE string,
        code_clean  TYPE string,
        cmt         TYPE string,
        had_lead_c  TYPE abap_bool,
        had_trail_c TYPE abap_bool,
        end_cand    TYPE abap_bool,
      END OF ty_stage_line.

    DATA: lt_raw_lines     TYPE tt_string_list,
          lt_clean_orig    TYPE tt_string_list,
          lt_prefix        TYPE tt_string_list,
          lt_body          TYPE tt_string_list,
          lt_suffix        TYPE tt_string_list,
          lt_pending_annot TYPE tt_string_list,
          lt_stage         TYPE STANDARD TABLE OF ty_stage_line WITH DEFAULT KEY,
          lt_end_indices   TYPE STANDARD TABLE OF i WITH DEFAULT KEY.

    CLEAR: et_out_lines, ev_new_source.
    ev_changed    = abap_false.
    ev_change_cnt = 0.
    ev_comma_cnt  = 0.
    ev_compat_chg = abap_false.

    " Paso 1: Limpiar /*+[internal] { "BASEINFO" ... }*/ y saltos CR
    DATA(lv_clean_src) = strip_internal_baseinfo( iv_source ).
    SPLIT lv_clean_src AT cl_abap_char_utilities=>newline INTO TABLE lt_raw_lines.

    LOOP AT lt_raw_lines INTO DATA(lv_rl).
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf(1) IN lv_rl WITH ''.
      APPEND lv_rl TO lt_clean_orig.
    ENDLOOP.

    WHILE lines( lt_clean_orig ) > 0.
      DATA(lv_last_idx) = lines( lt_clean_orig ).
      IF trim_spaces( lt_clean_orig[ lv_last_idx ] ) IS INITIAL.
        DELETE lt_clean_orig INDEX lv_last_idx.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.

    DATA(lv_orig_norm_str) = VALUE string( ).
    CONCATENATE LINES OF lt_clean_orig INTO lv_orig_norm_str
      SEPARATED BY cl_abap_char_utilities=>newline.

    " Paso 2: Dividir en lt_prefix (hasta '{'), lt_body (proyección) y lt_suffix ('}' y resto)
    "         lv_state: 0=antes de DEFINE, 1=buscando '{', 2=dentro de '{...}', 3=después de '}'
    DATA(lv_state)      = 0.
    DATA(lv_proj_brace) = 0.
    DATA(lv_blk_cmt)    = abap_false.

    LOOP AT lt_clean_orig INTO DATA(lv_line).
      IF lv_state = 3.
        APPEND lv_line TO lt_suffix.
        CONTINUE.
      ENDIF.

      DATA(lv_t) = trim_spaces( lv_line ).

      IF lv_blk_cmt = abap_true.
        IF lv_state < 2.
          APPEND lv_line TO lt_prefix.
        ELSE.
          APPEND lv_line TO lt_body.
        ENDIF.
        IF lv_t CS '*/'.
          lv_blk_cmt = abap_false.
        ENDIF.
        CONTINUE.
      ENDIF.

      IF strlen( lv_t ) >= 2 AND lv_t(2) = '/*'.
        IF lv_state < 2.
          APPEND lv_line TO lt_prefix.
        ELSE.
          APPEND lv_line TO lt_body.
        ENDIF.
        IF NOT ( lv_t CS '*/' ).
          lv_blk_cmt = abap_true.
        ENDIF.
        CONTINUE.
      ENDIF.

      IF ( strlen( lv_t ) >= 2 AND ( lv_t(2) = '//' OR lv_t(2) = '--' ) )
         OR ( strlen( lv_t ) >= 1 AND lv_t(1) = '*' ).
        IF lv_state < 2.
          APPEND lv_line TO lt_prefix.
        ELSE.
          APPEND lv_line TO lt_body.
        ENDIF.
        CONTINUE.
      ENDIF.

      IF lv_state = 0.
        IF lv_t IS NOT INITIAL AND lv_t(1) <> '@'.
          DATA(lv_low_h) = to_lower( lv_t ).
          IF ( strlen( lv_low_h ) >= 7 AND lv_low_h(7) = 'define ' )
             OR lv_low_h CS 'select from'.
            lv_state = 1.
          ENDIF.
        ENDIF.
        IF lv_state = 0.
          APPEND lv_line TO lt_prefix.
          CONTINUE.
        ENDIF.
      ENDIF.

      split_inline_comment(
        EXPORTING iv_line = lv_line
        IMPORTING ev_code = DATA(lv_c_only) ).

      IF lv_state = 1.
        IF lv_c_only CS '{'.
          " Buscar posición exacta del primer '{' fuera de comillas
          DATA(lv_open_pos) = -1.
          DATA(lv_sq1)      = abap_false.
          DATA(lv_p1)       = 0.
          DATA(lv_l1)       = strlen( lv_line ).
          WHILE lv_p1 < lv_l1.
            DATA(lv_ch1) = lv_line+lv_p1(1).
            IF lv_ch1 = ''''.
              lv_sq1 = COND abap_bool( WHEN lv_sq1 = abap_true
                                         THEN abap_false ELSE abap_true ).
            ELSEIF lv_sq1 = abap_false AND lv_ch1 = '{'.
              lv_open_pos = lv_p1.
              EXIT.
            ENDIF.
            lv_p1 = lv_p1 + 1.
          ENDWHILE.

          IF lv_open_pos >= 0.
            DATA(lv_upto_b)  = COND string( WHEN lv_open_pos > 0
                                            THEN lv_line(lv_open_pos) && '{'
                                            ELSE '{' ).
            DATA(lv_aft_pos) = lv_open_pos + 1.
            DATA(lv_rest_b)  = COND string( WHEN lv_aft_pos < lv_l1
                                            THEN lv_line+lv_aft_pos ELSE '' ).
            split_inline_comment(
              EXPORTING iv_line = lv_rest_b
              IMPORTING ev_code = DATA(lv_rest_code) ).

            IF lv_rest_code IS INITIAL.
              APPEND lv_line TO lt_prefix.
              lv_state      = 2.
              lv_proj_brace = 1.
            ELSE.
              APPEND lv_upto_b TO lt_prefix.
              count_code_depths(
                EXPORTING iv_code        = lv_rest_code
                IMPORTING ev_brace_delta = DATA(lv_bd1) ).
              IF ( 1 + lv_bd1 ) <= 0 AND lv_rest_b CS '}'.
                SPLIT lv_rest_b AT '}' INTO DATA(lv_in_one) DATA(lv_af_one).
                IF trim_spaces( lv_in_one ) IS NOT INITIAL.
                  APPEND |  { trim_spaces( lv_in_one ) }| TO lt_body.
                ENDIF.
                APPEND '}' && lv_af_one TO lt_suffix.
                lv_state = 3.
              ELSE.
                APPEND |  { trim_spaces( lv_rest_b ) }| TO lt_body.
                lv_state      = 2.
                lv_proj_brace = 1 + lv_bd1.
              ENDIF.
            ENDIF.
          ELSE.
            APPEND lv_line TO lt_prefix.
          ENDIF.
        ELSE.
          APPEND lv_line TO lt_prefix.
        ENDIF.
        CONTINUE.
      ENDIF.

      " lv_state = 2 (dentro de '{ ... }')
      count_code_depths(
        EXPORTING iv_code        = lv_c_only
        IMPORTING ev_brace_delta = DATA(lv_bd2) ).

      IF ( lv_proj_brace + lv_bd2 ) <= 0.
        " Encontrar posición exacta del '}' que cierra la proyección
        DATA(lv_close_pos) = -1.
        DATA(lv_sq2)       = abap_false.
        DATA(lv_p2)        = 0.
        DATA(lv_l2)        = strlen( lv_line ).
        WHILE lv_p2 < lv_l2.
          DATA(lv_ch2) = lv_line+lv_p2(1).
          IF lv_ch2 = ''''.
            lv_sq2 = COND abap_bool( WHEN lv_sq2 = abap_true
                                       THEN abap_false ELSE abap_true ).
          ELSEIF lv_sq2 = abap_false.
            IF lv_ch2 = '{'.
              lv_proj_brace = lv_proj_brace + 1.
            ELSEIF lv_ch2 = '}'.
              lv_proj_brace = lv_proj_brace - 1.
              IF lv_proj_brace = 0.
                lv_close_pos = lv_p2.
                EXIT.
              ENDIF.
            ENDIF.
          ENDIF.
          lv_p2 = lv_p2 + 1.
        ENDWHILE.

        IF lv_close_pos >= 0.
          DATA(lv_bef_cl) = COND string( WHEN lv_close_pos > 0
                                         THEN lv_line(lv_close_pos) ELSE '' ).
          DATA(lv_frm_cl) = lv_line+lv_close_pos.
          IF trim_spaces( lv_bef_cl ) IS NOT INITIAL.
            APPEND lv_bef_cl TO lt_body.
          ENDIF.
          APPEND lv_frm_cl TO lt_suffix.
          lv_state = 3.
        ELSE.
          APPEND lv_line TO lt_suffix.
          lv_state = 3.
        ENDIF.
      ELSE.
        lv_proj_brace = lv_proj_brace + lv_bd2.
        APPEND lv_line TO lt_body.
      ENDIF.
    ENDLOOP.

    " Si no se encontró un bloque '{ ... }' válido, devolver fuente limpio sin tocar
    IF lt_body IS INITIAL AND lv_state < 2.
      et_out_lines  = lt_clean_orig.
      ev_new_source = lv_orig_norm_str.
      RETURN.
    ENDIF.

    " Paso 2B: Si P_COMP está marcado y la tabla TRANSP tiene Compatibility View,
    "          reemplazar 'as select from <tabla>' -> 'as select from <cds_target> as <tabla>'
    IF p_comp = abap_true AND gt_compat IS NOT INITIAL.
      READ TABLE gt_compat INTO DATA(ls_cmp_src)
        WITH KEY tabname = iv_tabname BINARY SEARCH.
      IF sy-subrc = 0
         AND ls_cmp_src-tabclass = 'TRANSP'
         AND ls_cmp_src-cds_target IS NOT INITIAL.
        rewrite_compat_from_clause(
          EXPORTING
            iv_tabname    = iv_tabname
            iv_proxy_obj  = ls_cmp_src-proxy_obj
            iv_cds_target = ls_cmp_src-cds_target
          CHANGING
            ct_prefix     = lt_prefix
            cv_compat_chg = ev_compat_chg ).
      ENDIF.
    ENDIF.

    " Paso 3A: Unir líneas partidas del tipo "campo \n as alias"
    DATA(lv_bi) = 1.
    WHILE lv_bi < lines( lt_body ).
      split_inline_comment(
        EXPORTING iv_line = lt_body[ lv_bi ]
        IMPORTING ev_code = DATA(lv_cur_c)
                  ev_cmt  = DATA(lv_cur_m) ).
      IF lv_cur_c IS NOT INITIAL
         AND lv_cur_c(1) <> '@'
         AND lv_cur_c(1) <> '/'
         AND lv_cur_c(1) <> '*'
         AND lv_cur_m IS INITIAL
         AND NOT ( to_lower( lv_cur_c ) CS ' as ' ).
        count_code_depths(
          EXPORTING iv_code        = lv_cur_c
          IMPORTING ev_paren_delta = DATA(lv_pd_m) ).
        IF lv_pd_m = 0.
          DATA(lv_nx_idx) = lv_bi + 1.
          split_inline_comment(
            EXPORTING iv_line = lt_body[ lv_nx_idx ]
            IMPORTING ev_code = DATA(lv_nxt_c) ).
          DATA(lv_nxt_low) = to_lower( lv_nxt_c ).
          IF strlen( lv_nxt_low ) >= 4 AND lv_nxt_low(3) = 'as '.
            lt_body[ lv_bi ] = lt_body[ lv_bi ] && ` ` && trim_spaces( lt_body[ lv_nx_idx ] ).
            DELETE lt_body INDEX lv_nx_idx.
            CONTINUE.
          ENDIF.
        ENDIF.
      ENDIF.
      lv_bi = lv_bi + 1.
    ENDWHILE.

    " Paso 3B: Transformar campos RAW / DF34_RAW / QUAN / CURR y @Semantics
    DATA(lv_blk_b) = abap_false.
    DATA(lv_p_run) = 0.

    LOOP AT lt_body INTO DATA(lv_bline).
      DATA(lv_bt) = trim_spaces( lv_bline ).

      IF lv_blk_b = abap_true.
        APPEND VALUE ty_stage_line( text = lv_bline ) TO lt_stage.
        IF lv_bt CS '*/'.
          lv_blk_b = abap_false.
        ENDIF.
        CONTINUE.
      ENDIF.

      IF strlen( lv_bt ) >= 2 AND lv_bt(2) = '/*'.
        APPEND VALUE ty_stage_line( text = lv_bline ) TO lt_stage.
        IF NOT ( lv_bt CS '*/' ).
          lv_blk_b = abap_true.
        ENDIF.
        CONTINUE.
      ENDIF.

      IF lv_bt IS INITIAL
         OR ( strlen( lv_bt ) >= 2 AND ( lv_bt(2) = '//' OR lv_bt(2) = '--' ) )
         OR lv_bt(1) = '*'.
        APPEND VALUE ty_stage_line( text = lv_bline ) TO lt_stage.
        CONTINUE.
      ENDIF.

      split_inline_comment(
        EXPORTING iv_line   = lv_bline
        IMPORTING ev_indent = DATA(lv_ind)
                  ev_code   = DATA(lv_bcode)
                  ev_cmt    = DATA(lv_bcmt) ).

      IF lv_ind IS INITIAL.
        lv_ind = `  `.
      ENDIF.

      " Detectar si es anotación '@' (incluso si traía coma inicial ', @Semantics...')
      DATA(lv_chk_ann) = lv_bcode.
      IF lv_p_run = 0 AND strlen( lv_chk_ann ) > 0 AND lv_chk_ann(1) = ','.
        DATA(lv_tmp_ann) = substring( val = lv_chk_ann off = 1 ).
        lv_chk_ann = trim_spaces( lv_tmp_ann ).
      ENDIF.

      IF strlen( lv_chk_ann ) > 0 AND lv_chk_ann(1) = '@'.
        DATA(lv_low_ann) = to_lower( lv_chk_ann ).
        DATA(lv_clean_ann_line) = lv_ind && lv_chk_ann.
        IF lv_bcmt IS NOT INITIAL.
          lv_clean_ann_line = lv_clean_ann_line && ` ` && lv_bcmt.
        ENDIF.

        IF lv_low_ann CS '@semantics.amount.currencycode'
           OR lv_low_ann CS '@semantics.quantity.unitofmeasure'.
          APPEND lv_clean_ann_line TO lt_pending_annot.
        ELSE.
          " Si venía con coma inicial antes de '@', dejarla limpia sin la coma
          IF lv_chk_ann <> lv_bcode.
            APPEND VALUE ty_stage_line( text = lv_clean_ann_line ) TO lt_stage.
          ELSE.
            APPEND VALUE ty_stage_line( text = lv_bline ) TO lt_stage.
          ENDIF.
        ENDIF.
        CONTINUE.
      ENDIF.

      " Si ya está dentro de expresión multilínea o ya tiene bintohex/cast, no envolver
      " (EXCEPTO si era un cast previo de un campo DF34_RAW/DF16_RAW no clave: comentarlo)
      DATA(lv_low_bc) = to_lower( lv_bcode ).
      IF lv_p_run <> 0
         OR lv_low_bc CS 'bintohex('
         OR lv_low_bc CS 'cast('
         OR lv_low_bc CS 'get_numeric_value('
         OR lv_low_bc CS 'curr_to_decfloat_amount('.
        count_code_depths(
          EXPORTING iv_code        = lv_bcode
          IMPORTING ev_paren_delta = DATA(lv_pd_skip) ).

        DATA(lv_commented_prev_df) = abap_false.
        IF lv_p_run = 0 AND lv_pd_skip = 0 AND lv_low_bc CS 'cast('.
          DATA(lv_cchk) = lv_bcode.
          REPLACE ALL OCCURRENCES OF '(' IN lv_cchk WITH ` `.
          REPLACE ALL OCCURRENCES OF ')' IN lv_cchk WITH ` `.
          REPLACE ALL OCCURRENCES OF ',' IN lv_cchk WITH ` `.
          lv_cchk = condense( lv_cchk ).
          SPLIT lv_cchk AT space INTO TABLE DATA(lt_ctoks).
          IF lines( lt_ctoks ) >= 2 AND to_lower( lt_ctoks[ 1 ] ) = 'cast'.
            DATA(lv_cfld) = to_upper( lt_ctoks[ 2 ] ).
            REPLACE ALL OCCURRENCES OF '"' IN lv_cfld WITH ''.
            IF lv_cfld CS '.'.
              SPLIT lv_cfld AT '.' INTO DATA(lv_cpref) lv_cfld.
            ENDIF.
            READ TABLE gt_dd03l TRANSPORTING NO FIELDS
              WITH KEY tabname = iv_tabname BINARY SEARCH.
            IF sy-subrc = 0.
              LOOP AT gt_dd03l INTO DATA(ls_gdf) FROM sy-tabix.
                IF ls_gdf-tabname <> iv_tabname.
                  EXIT.
                ENDIF.
                IF ls_gdf-fieldname = lv_cfld
                   AND ls_gdf-keyflag <> 'X'
                   AND ( ls_gdf-datatype = 'D34R'
                         OR ls_gdf-datatype = 'D16R'
                         OR ls_gdf-datatype = 'D34S'
                         OR ls_gdf-datatype = 'D16S' ).
                  LOOP AT lt_pending_annot INTO DATA(lv_pa_df).
                    APPEND VALUE ty_stage_line(
                      text = |{ lv_ind }// { trim_spaces( lv_pa_df ) }|
                    ) TO lt_stage.
                  ENDLOOP.
                  CLEAR lt_pending_annot.
                  APPEND VALUE ty_stage_line(
                    text = |{ lv_ind }// { lv_bcode } // Excluido: { ls_gdf-datatype } no soportado en CDS/BQ|
                  ) TO lt_stage.
                  ev_change_cnt        = ev_change_cnt + 1.
                  lv_commented_prev_df = abap_true.
                  EXIT.
                ENDIF.
              ENDLOOP.
            ENDIF.
          ENDIF.
        ENDIF.

        IF lv_commented_prev_df = abap_true.
          CONTINUE.
        ENDIF.

        LOOP AT lt_pending_annot INTO DATA(lv_pa_keep).
          APPEND VALUE ty_stage_line( text = lv_pa_keep ) TO lt_stage.
        ENDLOOP.
        CLEAR lt_pending_annot.
        APPEND VALUE ty_stage_line( text = lv_bline ) TO lt_stage.
        lv_p_run = lv_p_run + lv_pd_skip.
        IF lv_p_run < 0.
          lv_p_run = 0.
        ENDIF.
        CONTINUE.
      ENDIF.

      " Tokenizar el campo candidato sin comas separadoras
      DATA(lv_work) = lv_bcode.
      REPLACE ALL OCCURRENCES OF ',' IN lv_work WITH ` `.
      lv_work = condense( lv_work ).

      SPLIT lv_work AT space INTO TABLE DATA(lt_tokens).
      IF lt_tokens IS INITIAL.
        LOOP AT lt_pending_annot INTO lv_pa_keep.
          APPEND VALUE ty_stage_line( text = lv_pa_keep ) TO lt_stage.
        ENDLOOP.
        CLEAR lt_pending_annot.
        APPEND VALUE ty_stage_line( text = lv_bline ) TO lt_stage.
        CONTINUE.
      ENDIF.

      DATA(lv_idx)    = 1.
      DATA(lv_is_key) = abap_false.
      IF to_lower( lt_tokens[ 1 ] ) = 'key' AND lines( lt_tokens ) >= 2.
        lv_idx    = 2.
        lv_is_key = abap_true.
      ENDIF.

      DATA(lv_raw_token)  = lt_tokens[ lv_idx ].
      DATA(lv_lookup_fld) = to_upper( lv_raw_token ).
      REPLACE ALL OCCURRENCES OF '"' IN lv_lookup_fld WITH ''.
      IF lv_lookup_fld CS '.'.
        SPLIT lv_lookup_fld AT '.' INTO DATA(lv_tab_pref) lv_lookup_fld.
      ENDIF.

      DATA(ls_match) = VALUE ty_dd03l( ).
      DATA(lv_found) = abap_false.
      READ TABLE gt_dd03l TRANSPORTING NO FIELDS
        WITH KEY tabname = iv_tabname BINARY SEARCH.
      IF sy-subrc = 0.
        LOOP AT gt_dd03l INTO DATA(ls_g) FROM sy-tabix.
          IF ls_g-tabname <> iv_tabname.
            EXIT.
          ENDIF.
          IF ls_g-fieldname = lv_lookup_fld
             AND ( ls_g-datatype = 'RAW'
                   OR ls_g-datatype = 'LRAW'
                   OR ls_g-datatype = 'RSTR'
                   OR ls_g-datatype = 'D34R'
                   OR ls_g-datatype = 'D16R'
                   OR ls_g-datatype = 'D34S'
                   OR ls_g-datatype = 'D16S'
                   OR ls_g-datatype = 'QUAN'
                   OR ls_g-datatype = 'CURR' ).
            ls_match = ls_g.
            lv_found = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.

      " Si es LRAW/RSTR/RAW>255/DF34_RAW/DF16_RAW pero es CLAVE primaria, no comentar
      IF lv_found = abap_true
         AND lv_is_key = abap_true
         AND ( ls_match-datatype = 'LRAW'
               OR ls_match-datatype = 'RSTR'
               OR ls_match-datatype = 'D34R'
               OR ls_match-datatype = 'D16R'
               OR ls_match-datatype = 'D34S'
               OR ls_match-datatype = 'D16S'
               OR ( ls_match-datatype = 'RAW' AND CONV int4( ls_match-leng ) > 255 ) ).
        lv_found = abap_false.
      ENDIF.

      " Si P_ONLYX está activo, no castear QUAN/CURR con referencia en la misma tabla
      IF lv_found = abap_true
         AND p_onlyx = abap_true
         AND ( ls_match-datatype = 'QUAN' OR ls_match-datatype = 'CURR' )
         AND ls_match-reftable = iv_tabname.
        lv_found = abap_false.
      ENDIF.

      IF lv_found = abap_true.
        LOOP AT lt_pending_annot INTO DATA(lv_pa).
          APPEND VALUE ty_stage_line(
            text = |{ lv_ind }// { trim_spaces( lv_pa ) }|
          ) TO lt_stage.
        ENDLOOP.
        CLEAR lt_pending_annot.

        DATA(lv_alias_out) = clean_alias( lv_raw_token ).
        DATA(lv_as_pos)    = lv_idx + 1.
        DATA(lv_al_pos)    = lv_idx + 2.
        IF lines( lt_tokens ) >= lv_al_pos
           AND to_lower( lt_tokens[ lv_as_pos ] ) = 'as'.
          lv_alias_out = lt_tokens[ lv_al_pos ].
        ENDIF.

        DATA(lv_k_txt)   = COND string( WHEN lv_is_key = abap_true THEN 'key ' ELSE '' ).
        DATA(lv_cmt_sfx) = COND string( WHEN lv_bcmt IS NOT INITIAL THEN | { lv_bcmt }| ELSE '' ).

        IF ls_match-datatype = 'LRAW'
           OR ls_match-datatype = 'RSTR'
           OR ( ls_match-datatype = 'RAW' AND CONV int4( ls_match-leng ) > 255 ).
          APPEND VALUE ty_stage_line(
            text = |{ lv_ind }// { lv_work } // Excluido: { ls_match-datatype } no soportado en BQ|
          ) TO lt_stage.
        ELSEIF ls_match-datatype = 'RAW'.
          APPEND VALUE ty_stage_line(
            text        = |{ lv_ind }{ lv_k_txt }bintohex( { lv_raw_token } ) | &&
                          |as { lv_alias_out }{ lv_cmt_sfx }|
            is_new_cast = abap_true
          ) TO lt_stage.
        ELSEIF ls_match-datatype = 'D34R'
            OR ls_match-datatype = 'D16R'
            OR ls_match-datatype = 'D34S'
            OR ls_match-datatype = 'D16S'.
          DATA(lv_df_tag) = SWITCH string( ls_match-datatype
            WHEN 'D34R' THEN 'DF34_RAW'
            WHEN 'D16R' THEN 'DF16_RAW'
            WHEN 'D34S' THEN 'DF34_SCL'
            WHEN 'D16S' THEN 'DF16_SCL'
            ELSE CONV string( ls_match-datatype ) ).
          APPEND VALUE ty_stage_line(
            text = |{ lv_ind }// { lv_work } // Excluido: { lv_df_tag } no soportado en CDS/BQ|
          ) TO lt_stage.
        ELSE.
          DATA(lv_len_i) = nmax( val1 = CONV int4( ls_match-leng )
                                 val2 = CONV int4( ls_match-decimals ) + 1 ).
          IF lv_len_i > 31.
            lv_len_i = 31.
          ENDIF.
          DATA(lv_dec_i) = CONV int4( ls_match-decimals ).
          APPEND VALUE ty_stage_line(
            text        = |{ lv_ind }{ lv_k_txt }cast( { lv_raw_token } | &&
                          |as abap.dec({ lv_len_i },{ lv_dec_i }) ) | &&
                          |as { lv_alias_out }{ lv_cmt_sfx }|
            is_new_cast = abap_true
          ) TO lt_stage.
        ENDIF.

        ev_change_cnt = ev_change_cnt + 1.
      ELSE.
        LOOP AT lt_pending_annot INTO lv_pa_keep.
          APPEND VALUE ty_stage_line( text = lv_pa_keep ) TO lt_stage.
        ENDLOOP.
        CLEAR lt_pending_annot.
        APPEND VALUE ty_stage_line( text = lv_bline ) TO lt_stage.
      ENDIF.

      count_code_depths(
        EXPORTING iv_code        = lv_bcode
        IMPORTING ev_paren_delta = DATA(lv_pd_end) ).
      lv_p_run = lv_p_run + lv_pd_end.
      IF lv_p_run < 0.
        lv_p_run = 0.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_pending_annot INTO lv_pa_keep.
      APPEND VALUE ty_stage_line( text = lv_pa_keep ) TO lt_stage.
    ENDLOOP.
    CLEAR lt_pending_annot.

    " Paso 3C: Normalizador Determinístico de Comas en todo el bloque '{ ... }'
    DATA(lv_blk_c)    = abap_false.
    DATA(lv_ann_nest) = 0.
    DATA(lv_pdepth)   = 0.
    DATA(lv_cdepth)   = 0.

    LOOP AT lt_stage ASSIGNING FIELD-SYMBOL(<fs_st>).
      DATA(lv_st_t) = trim_spaces( <fs_st>-text ).

      IF lv_blk_c = abap_true.
        IF lv_st_t CS '*/'.
          lv_blk_c = abap_false.
        ENDIF.
        CONTINUE.
      ENDIF.

      IF strlen( lv_st_t ) >= 2 AND lv_st_t(2) = '/*'.
        IF NOT ( lv_st_t CS '*/' ).
          lv_blk_c = abap_true.
        ENDIF.
        CONTINUE.
      ENDIF.

      IF lv_st_t IS INITIAL
         OR ( strlen( lv_st_t ) >= 2 AND ( lv_st_t(2) = '//' OR lv_st_t(2) = '--' ) )
         OR lv_st_t(1) = '*'.
        CONTINUE.
      ENDIF.

      split_inline_comment(
        EXPORTING iv_line   = <fs_st>-text
        IMPORTING ev_indent = DATA(lv_s_ind)
                  ev_code   = DATA(lv_s_code)
                  ev_cmt    = DATA(lv_s_cmt) ).

      IF lv_s_code IS INITIAL.
        CONTINUE.
      ENDIF.

      " Ignorar líneas de anotación '@...' (incluyendo anotaciones multilínea [...]/ {...})
      IF lv_ann_nest > 0 OR lv_s_code(1) = '@'.
        count_code_depths(
          EXPORTING iv_code        = lv_s_code
          IMPORTING ev_brace_delta = DATA(lv_ab1)
                    ev_brack_delta = DATA(lv_ak1)
                    ev_paren_delta = DATA(lv_ap1) ).
        lv_ann_nest = lv_ann_nest + lv_ab1 + lv_ak1 + lv_ap1.
        IF lv_ann_nest < 0.
          lv_ann_nest = 0.
        ENDIF.
        CONTINUE.
      ENDIF.

      <fs_st>-is_active  = abap_true.
      <fs_st>-indent     = COND string( WHEN lv_s_ind IS NOT INITIAL THEN lv_s_ind ELSE `  ` ).
      <fs_st>-cmt        = lv_s_cmt.
      <fs_st>-code_clean = lv_s_code.

      " Quitar cualquier coma inicial a nivel 0
      IF lv_pdepth = 0 AND lv_cdepth = 0.
        WHILE strlen( <fs_st>-code_clean ) > 0 AND <fs_st>-code_clean(1) = ','.
          <fs_st>-had_lead_c = abap_true.
          DATA(lv_tmp_lead)  = substring( val = <fs_st>-code_clean off = 1 ).
          <fs_st>-code_clean = trim_spaces( lv_tmp_lead ).
        ENDWHILE.
      ENDIF.

      count_code_depths(
        EXPORTING iv_code        = <fs_st>-code_clean
        IMPORTING ev_paren_delta = DATA(lv_dp)
                  ev_case_delta  = DATA(lv_dc) ).
      lv_pdepth = lv_pdepth + lv_dp.
      lv_cdepth = lv_cdepth + lv_dc.
      IF lv_pdepth < 0.
        lv_pdepth = 0.
      ENDIF.
      IF lv_cdepth < 0.
        lv_cdepth = 0.
      ENDIF.

      IF lv_pdepth = 0 AND lv_cdepth = 0.
        " Quitar coma final a nivel 0 para normalizar
        WHILE strlen( <fs_st>-code_clean ) > 0.
          DATA(lv_lpos) = strlen( <fs_st>-code_clean ) - 1.
          IF <fs_st>-code_clean+lv_lpos(1) = ','.
            <fs_st>-had_trail_c = abap_true.
            IF lv_lpos > 0.
              DATA(lv_tmp_trl)   = substring( val = <fs_st>-code_clean len = lv_lpos ).
              <fs_st>-code_clean = trim_spaces( lv_tmp_trl ).
            ELSE.
              <fs_st>-code_clean = ''.
            ENDIF.
          ELSE.
            EXIT.
          ENDIF.
        ENDWHILE.
        <fs_st>-end_cand = abap_true.
      ELSE.
        " Primera parte de expresión multilínea: asegurar que no quede coma inicial
        IF <fs_st>-had_lead_c = abap_true.
          <fs_st>-text = <fs_st>-indent && <fs_st>-code_clean &&
            COND string( WHEN <fs_st>-cmt IS NOT INITIAL THEN | { <fs_st>-cmt }| ELSE '' ).
          ev_comma_cnt = ev_comma_cnt + 1.
        ENDIF.
      ENDIF.
    ENDLOOP.

    " Filtrar candidatos de fin de elemento verificando que la siguiente línea
    " activa no sea continuación ('as <alias>' u operador aritmético)
    DATA(lv_total_st) = lines( lt_stage ).
    LOOP AT lt_stage INTO DATA(ls_cand) WHERE end_cand = abap_true.
      DATA(lv_cur_st_idx) = sy-tabix.
      DATA(lv_is_cont)    = abap_false.
      DATA(lv_scan)       = lv_cur_st_idx + 1.

      WHILE lv_scan <= lv_total_st.
        DATA(ls_nx) = lt_stage[ lv_scan ].
        DATA(lv_nx_t) = trim_spaces( ls_nx-text ).
        IF lv_nx_t IS NOT INITIAL AND lv_nx_t(1) = '@'.
          EXIT.
        ENDIF.
        IF ls_nx-is_active = abap_true AND ls_nx-code_clean IS NOT INITIAL.
          DATA(lv_nx_l) = to_lower( ls_nx-code_clean ).
          IF ( strlen( lv_nx_l ) >= 4 AND lv_nx_l(3) = 'as ' )
             OR lv_nx_l(1) = '+'
             OR lv_nx_l(1) = '*'
             OR ( strlen( lv_nx_l ) >= 2 AND lv_nx_l(2) = '&&' ).
            lv_is_cont = abap_true.
          ENDIF.
          EXIT.
        ENDIF.
        lv_scan = lv_scan + 1.
      ENDWHILE.

      IF lv_is_cont = abap_true.
        IF ls_cand-had_trail_c = abap_true OR ls_cand-had_lead_c = abap_true.
          lt_stage[ lv_cur_st_idx ]-text =
            ls_cand-indent && ls_cand-code_clean &&
            COND string( WHEN ls_cand-cmt IS NOT INITIAL THEN | { ls_cand-cmt }| ELSE '' ).
          ev_comma_cnt = ev_comma_cnt + 1.
        ENDIF.
      ELSE.
        APPEND lv_cur_st_idx TO lt_end_indices.
      ENDIF.
    ENDLOOP.

    " Aplicar regla exacta de comas sobre los N elementos proyectados:
    " - Elementos 1 .. N-1 -> DEBEN llevar coma final ','
    " - Elemento N (último antes de '}') -> NO DEBE llevar coma final
    DATA(lv_num_elems) = lines( lt_end_indices ).
    LOOP AT lt_end_indices INTO DATA(lv_e_idx).
      DATA(lv_elem_pos)   = sy-tabix.
      DATA(lv_must_comma) = COND abap_bool(
        WHEN lv_elem_pos < lv_num_elems THEN abap_true ELSE abap_false ).

      ASSIGN lt_stage[ lv_e_idx ] TO FIELD-SYMBOL(<fs_el>).
      DATA(lv_sfx_c) = COND string(
        WHEN <fs_el>-cmt IS NOT INITIAL THEN | { <fs_el>-cmt }| ELSE '' ).

      IF lv_must_comma = abap_true.
        IF <fs_el>-is_new_cast = abap_true.
          <fs_el>-text = |{ <fs_el>-indent }{ <fs_el>-code_clean },{ lv_sfx_c }|.
        ELSEIF <fs_el>-had_trail_c = abap_false OR <fs_el>-had_lead_c = abap_true.
          <fs_el>-text = |{ <fs_el>-indent }{ <fs_el>-code_clean },{ lv_sfx_c }|.
          ev_comma_cnt = ev_comma_cnt + 1.
        ENDIF.
      ELSE.
        IF <fs_el>-is_new_cast = abap_true.
          <fs_el>-text = |{ <fs_el>-indent }{ <fs_el>-code_clean }{ lv_sfx_c }|.
        ELSEIF <fs_el>-had_trail_c = abap_true OR <fs_el>-had_lead_c = abap_true.
          <fs_el>-text = |{ <fs_el>-indent }{ <fs_el>-code_clean }{ lv_sfx_c }|.
          ev_comma_cnt = ev_comma_cnt + 1.
        ENDIF.
      ENDIF.
    ENDLOOP.

    " Paso 4: Reensamblar código final limpio
    APPEND LINES OF lt_prefix TO et_out_lines.
    LOOP AT lt_stage INTO DATA(ls_final_st).
      APPEND ls_final_st-text TO et_out_lines.
    ENDLOOP.
    APPEND LINES OF lt_suffix TO et_out_lines.

    WHILE lines( et_out_lines ) > 0.
      DATA(lv_out_last) = lines( et_out_lines ).
      IF trim_spaces( et_out_lines[ lv_out_last ] ) IS INITIAL.
        DELETE et_out_lines INDEX lv_out_last.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.

    CONCATENATE LINES OF et_out_lines INTO ev_new_source
      SEPARATED BY cl_abap_char_utilities=>newline.

    IF ev_new_source <> lv_orig_norm_str
       OR ev_change_cnt > 0
       OR ev_comma_cnt > 0
       OR ev_compat_chg = abap_true.
      ev_changed = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD preview_cds_code.
    SELECT as4local, source
      FROM ddddlsrc
      WHERE ddlname  = @iv_ddlname
        AND as4local IN ( 'A', 'I', 'N' )
      INTO TABLE @DATA(lt_src).

    IF sy-subrc <> 0 OR lt_src IS INITIAL.
      MESSAGE |No se encontró código fuente en DDDDLSRC para { iv_ddlname }.|
        TYPE 'I'.
      RETURN.
    ENDIF.

    SORT lt_src BY as4local DESCENDING.
    READ TABLE lt_src INTO DATA(ls_src) INDEX 1.

    build_modified_cds_source(
      EXPORTING
        iv_source     = ls_src-source
        iv_tabname    = iv_tabname
      IMPORTING
        et_out_lines  = DATA(lt_out)
        ev_change_cnt = DATA(lv_cnt)
        ev_comma_cnt  = DATA(lv_cm_cnt)
        ev_compat_chg = DATA(lv_cmp_chg) ).

    DATA(lv_cmp_note) = COND string(
      WHEN lv_cmp_chg = abap_true THEN 'SELECT Compat. reemplazado, '
      ELSE '' ).

    cl_demo_output=>display_data(
      value = lt_out
      name  = |Código Sugerido { iv_ddlname } ({ iv_tabname }) - { lv_cmp_note }{ lv_cnt } cols, { lv_cm_cnt } comas| ).
  ENDMETHOD.

  METHOD apply_single_cds.
    DATA: ls_ddddlsrcv  TYPE ddddlsrcv,
          lv_tadir_name TYPE tadir-obj_name,
          lv_devclass   TYPE tadir-devclass.

    ev_updated     = abap_false.
    ev_compat_done = abap_false.
    ev_color_col   = 6.

    " 1. Validaciones de seguridad: solo tablas TRANSPARENTES y vistas Z*/Y*
    IF iv_tabclass <> 'TRANSP'.
      ev_estado_cds = 'OMITIDA'.
      ev_accion_msg = |OMITIDA: { iv_tabname } es { iv_tabclass } (solo se modifican TRANSP)|.
      RETURN.
    ENDIF.

    IF iv_ddlname IS INITIAL.
      ev_estado_cds = ''.
      ev_accion_msg = 'OMITIDA: Sin vista CDS asociada (verifique S_CDS)'.
      ev_color_col  = 3.
      RETURN.
    ENDIF.

    IF iv_ddlname(1) <> 'Z' AND iv_ddlname(1) <> 'Y' AND iv_ddlname(1) <> '/'.
      ev_estado_cds = 'OMITIDA'.
      ev_accion_msg = 'OMITIDA: Por seguridad solo se modifican vistas Z*/Y*'.
      RETURN.
    ENDIF.

    " 2. Consultar estado actual en DDDDLSRC y respaldar versión activa
    SELECT as4local, source
      FROM ddddlsrc
      WHERE ddlname  = @iv_ddlname
        AND as4local IN ( 'A', 'I', 'N' )
      INTO TABLE @DATA(lt_cur).

    IF sy-subrc <> 0 OR lt_cur IS INITIAL.
      ev_estado_cds = 'NO EXISTE'.
      ev_accion_msg = |No existe fuente en DDDDLSRC para { iv_ddlname }|.
      RETURN.
    ENDIF.

    DATA(lv_was_active)   = abap_false.
    DATA(lv_was_inactive) = abap_false.
    DATA(lv_backup_src)   = VALUE string( ).

    LOOP AT lt_cur INTO DATA(ls_c).
      IF ls_c-as4local = 'A'.
        lv_was_active = abap_true.
        lv_backup_src = ls_c-source.
      ELSEIF ls_c-as4local = 'I' OR ls_c-as4local = 'N'.
        lv_was_inactive = abap_true.
      ENDIF.
    ENDLOOP.

    " 3. Leer definición completa mediante la API estándar DDLS de SAP
    TRY.
        DATA(lo_ddl) = cl_dd_ddl_handler_factory=>create( ).

        lo_ddl->read(
          EXPORTING
            name         = iv_ddlname
            get_state    = 'M'
          IMPORTING
            ddddlsrcv_wa = ls_ddddlsrcv ).

        IF ls_ddddlsrcv-source IS INITIAL.
          lo_ddl->read(
            EXPORTING
              name         = iv_ddlname
              get_state    = 'A'
            IMPORTING
              ddddlsrcv_wa = ls_ddddlsrcv ).
        ENDIF.
      CATCH cx_root INTO DATA(lx_read).
        ev_estado_cds = 'ERR.LECT.'.
        ev_accion_msg = |Error leyendo { iv_ddlname }: { lx_read->get_text( ) }|.
        RETURN.
    ENDTRY.

    " 4. Generar código fuente transformado (idempotente + normalización de comas)
    build_modified_cds_source(
      EXPORTING
        iv_source     = ls_ddddlsrcv-source
        iv_tabname    = iv_tabname
      IMPORTING
        ev_new_source = DATA(lv_new_source)
        ev_changed    = DATA(lv_changed)
        ev_change_cnt = DATA(lv_chg_cnt)
        ev_comma_cnt  = DATA(lv_cm_cnt)
        ev_compat_chg = DATA(lv_cmp_chg) ).

    " Si no había columnas por modificar en el código:
    IF lv_changed = abap_false.
      IF lv_was_active = abap_true AND lv_was_inactive = abap_false.
        ev_estado_cds = 'ACTIVA'.
        ev_accion_msg = 'YA ACTIVA Y OK (sin cambios pendientes)'.
        ev_color_col  = 5.
        RETURN.
      ELSEIF iv_act_clean = abap_false.
        ev_estado_cds = COND string( WHEN lv_was_inactive = abap_true
                                     THEN 'INACTIVA' ELSE 'ACTIVA' ).
        ev_accion_msg = 'SIN CAMBIOS DE CÓDIGO SUGERIDOS'.
        ev_color_col  = 3.
        RETURN.
      ENDIF.
    ENDIF.

    " 5. Validar / Reutilizar Orden de Transporte abierta (CTS)
    "    - En $TMP no pide OT.
    "    - Si la vista ya está en una OT abierta (del generador BQ), SAP
    "      la reutiliza automáticamente sin mostrar ventana emergente.
    lv_tadir_name = iv_ddlname.
    SELECT SINGLE devclass
      FROM tadir
      WHERE pgmid    = 'R3TR'
        AND object   = 'DDLS'
        AND obj_name = @lv_tadir_name
      INTO @lv_devclass.

    IF sy-subrc = 0
       AND lv_devclass IS NOT INITIAL
       AND lv_devclass <> '$TMP'
       AND lv_devclass(1) <> '$'.

      CALL FUNCTION 'RS_CORR_INSERT'
        EXPORTING
          object              = iv_ddlname
          object_class        = 'DDLS'
          mode                = ' '
          global_lock         = 'X'
          devclass            = lv_devclass
          korrnum             = cv_trkorr
          master_language     = sy-langu
        IMPORTING
          korrnum             = cv_trkorr
        EXCEPTIONS
          cancelled           = 1
          permission_failure  = 2
          unknown_objectclass = 3
          OTHERS              = 4.

      IF sy-subrc = 1 OR sy-subrc = 2 OR sy-subrc = 4.
        ev_estado_cds = COND string( WHEN lv_was_inactive = abap_true
                                     THEN 'INACTIVA' ELSE 'ACTIVA' ).
        ev_accion_msg = 'CANCELADO / SIN PERMISO O BLOQUEADO EN OTRA OT'.
        ev_color_col  = 6.
        RETURN.
      ENDIF.
    ENDIF.

    " 6. Guardar nuevo código fuente (si hubo cambios)
    IF lv_changed = abap_true.
      ls_ddddlsrcv-source = lv_new_source.
      IF ls_ddddlsrcv-ddlanguage IS INITIAL.
        ls_ddddlsrcv-ddlanguage = sy-langu.
      ENDIF.

      TRY.
          lo_ddl->save(
            EXPORTING
              name         = iv_ddlname
              put_state    = 'N'
              ddddlsrcv_wa = ls_ddddlsrcv ).
          COMMIT WORK AND WAIT.
        CATCH cx_root INTO DATA(lx_save).
          ev_estado_cds = 'ERR.GUARD.'.
          ev_accion_msg = |ERROR AL GUARDAR: { lx_save->get_text( ) }|.
          ev_color_col  = 6.
          RETURN.
      ENDTRY.
    ENDIF.

    " 7. Activar la vista CDS
    DATA(lv_act_err) = VALUE string( ).
    TRY.
        lo_ddl->activate(
          EXPORTING
            name = iv_ddlname ).
        COMMIT WORK AND WAIT.
      CATCH cx_root INTO DATA(lx_act).
        lv_act_err = lx_act->get_text( ).
        IF lx_act->previous IS BOUND.
          lv_act_err = |{ lv_act_err } - { lx_act->previous->get_text( ) }|.
        ENDIF.
    ENDTRY.

    " 8. Verificar en DDDDLSRC si quedó realmente ACTIVA ('A' sin 'N'/'I')
    SELECT as4local
      FROM ddddlsrc
      WHERE ddlname  = @iv_ddlname
        AND as4local IN ( 'A', 'I', 'N' )
      INTO TABLE @DATA(lt_post).

    DATA(lv_now_act)   = abap_false.
    DATA(lv_still_ina) = abap_false.
    LOOP AT lt_post INTO DATA(ls_post).
      IF ls_post-as4local = 'A'.
        lv_now_act = abap_true.
      ELSEIF ls_post-as4local = 'I' OR ls_post-as4local = 'N'.
        lv_still_ina = abap_true.
      ENDIF.
    ENDLOOP.

    IF lv_now_act = abap_true AND lv_still_ina = abap_false AND lv_act_err IS INITIAL.
      ev_estado_cds = 'ACTIVA (OK)'.
      ev_color_col  = 5.
      ev_updated    = abap_true.
      IF lv_cmp_chg = abap_true.
        ev_compat_done = abap_true.
      ENDIF.
      IF lv_changed = abap_true.
        DATA(lv_cmp_tag) = VALUE string( ).
        IF lv_cmp_chg = abap_true.
          READ TABLE gt_compat INTO DATA(ls_cmp_ok)
            WITH KEY tabname = iv_tabname BINARY SEARCH.
          IF sy-subrc = 0.
            lv_cmp_tag = |SELECT->{ ls_cmp_ok-cds_target }, |.
          ENDIF.
        ENDIF.
        IF lv_cm_cnt > 0.
          ev_accion_msg =
            |MODIF. Y ACTIVADA OK ({ lv_cmp_tag }{ lv_chg_cnt } cols, { lv_cm_cnt } comas)|.
        ELSE.
          ev_accion_msg =
            |MODIFICADA Y ACTIVADA OK ({ lv_cmp_tag }{ lv_chg_cnt } cols ajustadas)|.
        ENDIF.
      ELSE.
        ev_accion_msg = 'ACTIVADA OK (código ya estaba limpio)'.
      ENDIF.
    ELSE.
      IF lv_act_err IS INITIAL.
        TRY.
            lo_ddl->check( EXPORTING name = iv_ddlname ).
          CATCH cx_root INTO DATA(lx_chk).
            lv_act_err = lx_chk->get_text( ).
        ENDTRY.
      ENDIF.

      " Si estaba ACTIVA antes y el usuario marcó restaurar en caso de error
      IF lv_changed = abap_true
         AND iv_revert_fail = abap_true
         AND lv_was_active = abap_true
         AND lv_was_inactive = abap_false
         AND lv_backup_src IS NOT INITIAL.
        TRY.
            ls_ddddlsrcv-source = lv_backup_src.
            lo_ddl->save(
              EXPORTING
                name         = iv_ddlname
                put_state    = 'N'
                ddddlsrcv_wa = ls_ddddlsrcv ).
            lo_ddl->activate( EXPORTING name = iv_ddlname ).
            COMMIT WORK AND WAIT.
            ev_estado_cds = 'ACTIVA (REV)'.
            ev_accion_msg = |ERROR ACTIVAR (restaurada orig.): { lv_act_err }|.
            ev_color_col  = 3.
          CATCH cx_root.
            ev_estado_cds = 'INACTIVA'.
            ev_accion_msg = |GUARDADA INACTIVA - Revisar Eclipse: { lv_act_err }|.
            ev_color_col  = 6.
        ENDTRY.
      ELSE.
        ev_estado_cds = 'INACTIVA'.
        ev_color_col  = 6.
        ev_accion_msg = COND string(
          WHEN lv_act_err IS NOT INITIAL
          THEN |GUARDADA INACTIVA - Revisar Eclipse: { lv_act_err }|
          ELSE 'GUARDADA INACTIVA - Ver detalle de error en Eclipse (Ctrl+F3)' ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD update_alv_rows_for_table.
    LOOP AT gt_summary ASSIGNING FIELD-SYMBOL(<fs_sum>)
      WHERE tabname = iv_tabname.
      <fs_sum>-estado_cds = iv_estado_cds.
      <fs_sum>-accion_cds = iv_accion_msg.
      IF iv_compat_done = abap_true.
        <fs_sum>-es_compat = 'SI (YA APUNTA)'.
        DELETE <fs_sum>-t_color
          WHERE fname = 'ES_COMPAT' OR fname = 'PROXY_OBJ' OR fname = 'CDS_TARGET'.
        add_cell_color( EXPORTING iv_fname = 'ES_COMPAT'
                                  iv_col   = 5
                                  iv_int   = 0
                        CHANGING  ct_color = <fs_sum>-t_color ).
        add_cell_color( EXPORTING iv_fname = 'PROXY_OBJ'
                                  iv_col   = 5
                                  iv_int   = 0
                        CHANGING  ct_color = <fs_sum>-t_color ).
        add_cell_color( EXPORTING iv_fname = 'CDS_TARGET'
                                  iv_col   = 5
                                  iv_int   = 0
                        CHANGING  ct_color = <fs_sum>-t_color ).
      ENDIF.
      set_status_cell_colors(
        EXPORTING iv_estado_cds = iv_estado_cds
                  iv_accion_col = iv_color_col
        CHANGING  ct_color      = <fs_sum>-t_color ).
    ENDLOOP.

    LOOP AT gt_detail ASSIGNING FIELD-SYMBOL(<fs_det>)
      WHERE tabname = iv_tabname.
      <fs_det>-estado_cds   = iv_estado_cds.
      <fs_det>-nota_tecnica = iv_accion_msg.
      IF iv_compat_done = abap_true.
        <fs_det>-es_compat = 'SI (YA APUNTA)'.
        IF <fs_det>-categoria = 'COMPATIBILITY VIEW'.
          <fs_det>-ubicacion_ref = |YA APUNTA A { <fs_det>-cds_target }|.
        ENDIF.
      ENDIF.
      set_status_cell_colors(
        EXPORTING iv_estado_cds = iv_estado_cds
                  iv_accion_col = 0
        CHANGING  ct_color      = <fs_det>-t_color ).
    ENDLOOP.
  ENDMETHOD.

  METHOD execute_mass_cds_update.
    DATA: lv_cand_cnt  TYPE i VALUE 0,
          lv_skip_view TYPE i VALUE 0,
          lv_no_cds    TYPE i VALUE 0,
          lv_ans       TYPE c LENGTH 1,
          lv_title     TYPE c LENGTH 70,
          lv_quest     TYPE c LENGTH 250,
          lv_pct       TYPE i,
          lv_prog_txt  TYPE c LENGTH 100,
          lv_ok_mod    TYPE i VALUE 0,
          lv_ok_already TYPE i VALUE 0,
          lv_err_cnt   TYPE i VALUE 0.

    LOOP AT gt_summary INTO DATA(ls_chk).
      READ TABLE gt_dd02l INTO DATA(ls_02)
        WITH KEY tabname = ls_chk-tabname BINARY SEARCH.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      IF ls_02-tabclass <> 'TRANSP'.
        lv_skip_view = lv_skip_view + 1.
      ELSEIF ls_chk-cds_view IS INITIAL.
        lv_no_cds = lv_no_cds + 1.
      ELSE.
        lv_cand_cnt = lv_cand_cnt + 1.
      ENDIF.
    ENDLOOP.

    IF lv_cand_cnt = 0.
      MESSAGE |No se hallaron vistas CDS sobre tablas TRANSP (verifique el filtro S_CDS, ej. ZCDS*).|
        TYPE 'I'.
      RETURN.
    ENDIF.

    lv_title = 'Modificación y Activación Masiva de Vistas CDS'.
    lv_quest =
      |Se procesarán { lv_cand_cnt } vistas CDS de tablas TRANSPARENTES | &&
      |({ lv_skip_view } vistas DDIC omitidas). ¿Guardar y activar ahora?|.

    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = lv_title
        text_question         = lv_quest
        text_button_1         = 'Sí, Aplicar'
        text_button_2         = 'Solo Auditar'
        default_button        = '2'
        display_cancel_button = ''
      IMPORTING
        answer                = lv_ans
      EXCEPTIONS
        OTHERS                = 1.

    IF lv_ans <> '1'.
      MESSAGE 'Modificación masiva cancelada; se muestra el reporte en modo lectura.'
        TYPE 'S'.
      RETURN.
    ENDIF.

    DATA(lv_curr_idx) = 0.
    LOOP AT gt_summary INTO DATA(ls_row).
      READ TABLE gt_dd02l INTO DATA(ls_tab_info)
        WITH KEY tabname = ls_row-tabname BINARY SEARCH.
      IF sy-subrc <> 0 OR ls_tab_info-tabclass <> 'TRANSP' OR ls_row-cds_view IS INITIAL.
        CONTINUE.
      ENDIF.

      lv_curr_idx = lv_curr_idx + 1.
      lv_pct      = ( lv_curr_idx * 100 ) / lv_cand_cnt.
      lv_prog_txt =
        |[{ lv_curr_idx }/{ lv_cand_cnt }] Actualizando { ls_row-cds_view } ({ ls_row-tabname })...|.

      CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
        EXPORTING
          percentage = lv_pct
          text       = lv_prog_txt.

      apply_single_cds(
        EXPORTING
          iv_tabname     = ls_row-tabname
          iv_tabclass    = ls_tab_info-tabclass
          iv_ddlname     = ls_row-cds_view
          iv_act_clean   = p_actin
          iv_revert_fail = p_revrt
        IMPORTING
          ev_estado_cds  = DATA(lv_est)
          ev_accion_msg  = DATA(lv_msg)
          ev_color_col   = DATA(lv_col)
          ev_updated     = DATA(lv_upd)
          ev_compat_done = DATA(lv_cmp_ok)
        CHANGING
          cv_trkorr      = gv_trkorr ).

      update_alv_rows_for_table(
        iv_tabname     = ls_row-tabname
        iv_estado_cds  = lv_est
        iv_accion_msg  = lv_msg
        iv_color_col   = lv_col
        iv_compat_done = lv_cmp_ok ).

      IF lv_upd = abap_true.
        lv_ok_mod = lv_ok_mod + 1.
      ELSEIF lv_est CS 'ACTIVA' AND lv_col = 5.
        lv_ok_already = lv_ok_already + 1.
      ELSE.
        lv_err_cnt = lv_err_cnt + 1.
      ENDIF.
    ENDLOOP.

    MESSAGE
      |Proceso finalizado: { lv_ok_mod } activadas/modif. OK, | &&
      |{ lv_ok_already } ya activas OK, { lv_err_cnt } pendientes/revisar.|
      TYPE 'S'.
  ENDMETHOD.

  METHOD prompt_single_cds_action.
    DATA: lv_ans   TYPE c LENGTH 1,
          lv_title TYPE c LENGTH 70,
          lv_quest TYPE c LENGTH 250.

    READ TABLE gt_dd02l INTO DATA(ls_tab)
      WITH KEY tabname = iv_tabname BINARY SEARCH.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    IF ls_tab-tabclass <> 'TRANSP'.
      MESSAGE |{ iv_tabname } es tipo { ls_tab-tabclass }: solo se modifican tablas TRANSP.|
        TYPE 'I'.
      RETURN.
    ENDIF.

    lv_title = |Actualizar Vista CDS { iv_ddlname }|.
    lv_quest =
      |¿Desea aplicar el código sugerido y activar la vista { iv_ddlname } | &&
      |(tabla { iv_tabname }) en SAP ahora?|.

    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = lv_title
        text_question         = lv_quest
        text_button_1         = 'Guardar/Activar'
        text_button_2         = 'Solo Ver Código'
        default_button        = '1'
        display_cancel_button = 'X'
      IMPORTING
        answer                = lv_ans
      EXCEPTIONS
        OTHERS                = 1.

    IF lv_ans = '2'.
      preview_cds_code( iv_ddlname = iv_ddlname
                        iv_tabname = iv_tabname ).
      RETURN.
    ELSEIF lv_ans <> '1'.
      RETURN.
    ENDIF.

    apply_single_cds(
      EXPORTING
        iv_tabname     = iv_tabname
        iv_tabclass    = ls_tab-tabclass
        iv_ddlname     = iv_ddlname
        iv_act_clean   = abap_true
        iv_revert_fail = p_revrt
      IMPORTING
        ev_estado_cds  = DATA(lv_est)
        ev_accion_msg  = DATA(lv_msg)
        ev_color_col   = DATA(lv_col)
        ev_compat_done = DATA(lv_cmp_ok2)
      CHANGING
        cv_trkorr      = gv_trkorr ).

    update_alv_rows_for_table(
      iv_tabname     = iv_tabname
      iv_estado_cds  = lv_est
      iv_accion_msg  = lv_msg
      iv_color_col   = lv_col
      iv_compat_done = lv_cmp_ok2 ).

    IF go_salv IS BOUND.
      go_salv->refresh( ).
    ENDIF.

    IF lv_col = 5.
      MESSAGE |{ iv_ddlname }: { lv_msg }| TYPE 'S'.
    ELSE.
      MESSAGE |{ iv_ddlname }: { lv_msg }| TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Inicialización de textos en pantalla (sin requerir Text Elements SE38)
*----------------------------------------------------------------------*
INITIALIZATION.
  txt_b1  = '1. Selección de Tablas SAP a Auditar (~150+ tablas)'.
  c_tip1  = 'Tip: En S_TAB use "Selección múltiple" para pegar su lista desde Excel.'.
  c_file  = 'Archivo TXT/CSV (opc.):'.
  c_base  = 'Incluir también las 122 tablas de la lista base de referencia'.

  txt_b2  = '2. Vínculo con Vistas CDS Creadas (Ej: ZCDS*)'.
  c_tip2  = 'Ingrese el prefijo ej. ZCDS* para asociar vistas activas e inactivas.'.

  txt_b3  = '3. Modo de Visualización ALV (Exportable a Excel)'.
  c_det   = 'Vista Detallada (Compat. View, RAW, DF34_RAW, QUAN/CURR + Mandante)'.
  c_res   = 'Vista Resumen (1 fila por tabla: Compat. View + Mandante + Conteos)'.
  c_onlyx = 'No tocar/ocultar QUAN/CURR cuya moneda/unidad ya está en la misma tabla'.

  txt_b4  = '4. Modificación y Activación Automática de Vistas CDS (Solo TRANSP)'.
  c_read  = 'Solo Auditoría / Lectura (No modifica vistas ni pide OT)'.
  c_apply = 'Modificar y Activar Vistas CDS Masivamente con el código sugerido'.
  c_comp  = 'Reemplazar SELECT FROM en Compatibility Views (ej. nsdm_e_marc as marc)'.
  c_actin = 'Activar también vistas CDS INACTIVAS (TRANSP) que ya estén limpias'.
  c_revrt = 'Si falla activar una vista que estaba ACTIVA, restaurar su original'.
  c_trk   = 'OT opcional (vacío = OT abierta):'.

*----------------------------------------------------------------------*
* Ayuda de búsqueda F4 para archivo local
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  lcl_auditor=>f4_file_open( CHANGING cv_file = p_file ).

*----------------------------------------------------------------------*
* Ejecución Principal
*----------------------------------------------------------------------*
START-OF-SELECTION.
  lcl_auditor=>run( ).
