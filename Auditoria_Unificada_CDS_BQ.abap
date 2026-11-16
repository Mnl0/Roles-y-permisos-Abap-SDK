*&---------------------------------------------------------------------*
*& Report ZGEN_AUDITORIA_CDS_BQ
*&---------------------------------------------------------------------*
*& Utilidad Unificada post-generación BigQuery Toolkit (ABAP SDK GCP)
*& Propósito:
*&   Analizar de forma masiva (~150+ tablas) sin pedir Orden de
*&   Transporte (100% solo lectura) las 3 validaciones clave para CDS:
*&     1) Columnas RAW / binarias -> Expresión bintohex( ) lista
*&     2) Columnas QUAN y CURR    -> Tabla y Campo Referencia SE11
*&                                   (REFTABLE / REFFIELD), claves para
*&                                   JOIN o expresión CAST abap.dec(L,D)
*&     3) Columna de Mandante     -> Nombre exacto (MANDT, RCLNT,
*&                                   CLIENT, etc.) o "NO TIENE"
*&
*& Interactividad en el reporte ALV (Doble Clic):
*&   - Doble clic en Tabla o Tabla Ref. -> Abre la tabla en la SE11
*&   - Doble clic en Vista CDS          -> Genera vista previa del
*&     código CDS corregido (bintohex + cast) listo para copiar a
*&     Eclipse ADT sin modificar objetos ni pedir OT.
*&---------------------------------------------------------------------*
REPORT zgen_auditoria_cds_bq.

TABLES: dd02l, ddddlsrc.

*----------------------------------------------------------------------*
* Tipos de datos para ALV y procesamiento interno
*----------------------------------------------------------------------*
TYPES:
  BEGIN OF ty_detail,
    tabname        TYPE dd02l-tabname,
    ddtext         TYPE dd02t-ddtext,
    cds_view       TYPE ddddlsrc-ddlname,
    estado_cds     TYPE c LENGTH 12,
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
    sugerencia_cds TYPE c LENGTH 120,
    nota_tecnica   TYPE c LENGTH 140,
    t_color        TYPE lvc_t_scol,
  END OF ty_detail,

  BEGIN OF ty_summary,
    tabname     TYPE dd02l-tabname,
    ddtext      TYPE dd02t-ddtext,
    estado_tab  TYPE c LENGTH 18,
    cds_view    TYPE ddddlsrc-ddlname,
    estado_cds  TYPE c LENGTH 12,
    tiene_mandt TYPE c LENGTH 15,
    campo_mandt TYPE c LENGTH 30,
    cant_raw    TYPE int4,
    lista_raw   TYPE c LENGTH 120,
    cant_curr   TYPE int4,
    cant_quan   TYPE int4,
    cant_ext    TYPE int4,
    lista_qc    TYPE c LENGTH 120,
    accion_cds  TYPE c LENGTH 45,
    t_color     TYPE lvc_t_scol,
  END OF ty_summary,

  BEGIN OF ty_dd02l,
    tabname  TYPE dd02l-tabname,
    as4local TYPE dd02l-as4local,
    as4vers  TYPE dd02l-as4vers,
    tabclass TYPE dd02l-tabclass,
    clidep   TYPE dd02l-clidep,
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

  BEGIN OF ty_cds_map,
    tabname    TYPE dd02l-tabname,
    ddlname    TYPE ddddlsrc-ddlname,
    estado_cds TYPE c LENGTH 12,
  END OF ty_cds_map,

  BEGIN OF ty_tab_key,
    tabname TYPE dd02l-tabname,
  END OF ty_tab_key,

  BEGIN OF ty_ref_key,
    tabname   TYPE dd03l-tabname,
    fieldname TYPE dd03l-fieldname,
    as4local  TYPE dd03l-as4local,
    as4vers   TYPE dd03l-as4vers,
    position  TYPE dd03l-position,
  END OF ty_ref_key,

  tt_tab_key TYPE STANDARD TABLE OF ty_tab_key WITH DEFAULT KEY,
  tt_cds_map TYPE STANDARD TABLE OF ty_cds_map WITH DEFAULT KEY.

*----------------------------------------------------------------------*
* Tablas globales de resultados para navegación ALV
*----------------------------------------------------------------------*
DATA: gt_detail  TYPE STANDARD TABLE OF ty_detail,
      gt_summary TYPE STANDARD TABLE OF ty_summary,
      gt_dd03l   TYPE STANDARD TABLE OF ty_dd03l.

*----------------------------------------------------------------------*
* Pantalla de Selección
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE txt_b1.
  SELECTION-SCREEN COMMENT /1(74) c_tip1.
  SELECT-OPTIONS: s_tab FOR dd02l-tabname.

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
  SELECT-OPTIONS: s_cds FOR ddddlsrc-ddlname.
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
    SELECTION-SCREEN COMMENT 4(70) c_onlyx FOR FIELD p_onlyx.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b3.

*----------------------------------------------------------------------*
* Clase Principal de Auditoría y Eventos ALV
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

      load_cds_mapping
        IMPORTING it_valid_tabs TYPE tt_tab_key
        EXPORTING et_cds_map    TYPE tt_cds_map,

      extract_from_table_in_ddl
        IMPORTING iv_source         TYPE string
        RETURNING VALUE(rv_tabname) TYPE dd02l-tabname,

      clean_alias
        IMPORTING iv_fieldname    TYPE clike
        RETURNING VALUE(rv_alias) TYPE string,

      add_cell_color
        IMPORTING iv_fname TYPE lvc_fname OPTIONAL
                  iv_col   TYPE i
                  iv_int   TYPE i DEFAULT 0
        CHANGING  ct_color TYPE lvc_t_scol,

      display_detail_alv,

      display_summary_alv,

      set_col_text
        IMPORTING io_cols TYPE REF TO cl_salv_columns_table
                  iv_col  TYPE lvc_fname
                  iv_s    TYPE scrtext_s
                  iv_m    TYPE scrtext_m
                  iv_l    TYPE scrtext_l,

      open_se11_table
        IMPORTING iv_tabname TYPE dd02l-tabname,

      preview_cds_code
        IMPORTING iv_ddlname TYPE ddddlsrc-ddlname
                  iv_tabname TYPE dd02l-tabname.
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
        INTO TABLE @DATA(lt_from_range)
        WHERE tabname  IN @s_tab
          AND as4local  = 'A'
          AND tabclass IN ( 'TRANSP', 'POOL', 'CLUSTER', 'VIEW' ).

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

    SORT rt_tabs BY tabname.
    DELETE ADJACENT DUPLICATES FROM rt_tabs COMPARING tabname.
    DELETE rt_tabs WHERE tabname IS INITIAL.
  ENDMETHOD.

  METHOD extract_from_table_in_ddl.
    " Extrae la tabla principal luego de 'as select from <tabla>'
    DATA(lv_clean) = iv_source.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf(1)
      IN lv_clean WITH ` `.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline
      IN lv_clean WITH ` `.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab
      IN lv_clean WITH ` `.
    REPLACE ALL OCCURRENCES OF '{' IN lv_clean WITH ` { `.
    lv_clean = condense( lv_clean ).

    FIND REGEX 'select\s+(?:distinct\s+)?from\s+([A-Za-z0-9_/]+)'
      IN lv_clean IGNORING CASE SUBMATCHES DATA(lv_found) ##REGEX_POSIX.
    IF sy-subrc = 0 AND lv_found IS NOT INITIAL.
      rv_tabname = CONV dd02l-tabname( to_upper( lv_found ) ).
    ENDIF.
  ENDMETHOD.

  METHOD load_cds_mapping.
    DATA: lt_map TYPE tt_cds_map.

    CLEAR et_cds_map.
    IF it_valid_tabs IS INITIAL.
      RETURN.
    ENDIF.

    " A) Si el usuario indicó un filtro de vistas CDS (ej. Z*BQ* o ZCDS*),
    "    leemos DDDDLSRC incluyendo vistas INACTIVAS ('I'/'N') y View Entities
    IF s_cds[] IS NOT INITIAL.
      SELECT ddlname, as4local, source
        FROM ddddlsrc
        INTO TABLE @DATA(lt_ddl)
        WHERE ddlname  IN @s_cds
          AND as4local IN ( 'A', 'I', 'N' ).

      " Priorizar versión en edición ('N'/'I') sobre activa ('A')
      SORT lt_ddl BY ddlname ASCENDING as4local DESCENDING.
      DELETE ADJACENT DUPLICATES FROM lt_ddl COMPARING ddlname.

      LOOP AT lt_ddl INTO DATA(ls_ddl).
        DATA(lv_base_tab) = extract_from_table_in_ddl( ls_ddl-source ).
        IF lv_base_tab IS NOT INITIAL.
          READ TABLE it_valid_tabs TRANSPORTING NO FIELDS
            WITH KEY tabname = lv_base_tab BINARY SEARCH.
          IF sy-subrc = 0.
            APPEND VALUE ty_cds_map(
              tabname    = lv_base_tab
              ddlname    = ls_ddl-ddlname
              estado_cds = COND string( WHEN ls_ddl-as4local = 'A'
                                        THEN 'ACTIVA'
                                        ELSE 'INACTIVA' )
            ) TO lt_map.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " B) Búsqueda automática rápida en DD26S + DDLDEPENDENCY para vistas
    "    CDS clásicas Z* / Y* activas sobre las tablas analizadas
    SELECT viewname, tabpos, as4local, as4vers, tabname
      FROM dd26s
      INTO TABLE @DATA(lt_dd26s)
      FOR ALL ENTRIES IN @it_valid_tabs
      WHERE tabname  = @it_valid_tabs-tabname
        AND as4local = 'A'.

    DELETE lt_dd26s WHERE viewname(1) <> 'Z' AND viewname(1) <> 'Y'.

    IF s_cds[] IS INITIAL AND lt_dd26s IS NOT INITIAL.
      SORT lt_dd26s BY viewname.
      SELECT ddlname, objectname, state, objecttype
        FROM ddldependency
        INTO TABLE @DATA(lt_dep)
        FOR ALL ENTRIES IN @lt_dd26s
        WHERE objectname = @lt_dd26s-viewname
          AND objecttype = 'VIEW'
          AND state      = 'A'.

      SORT lt_dep BY objectname.
      LOOP AT lt_dd26s INTO DATA(ls_26).
        READ TABLE lt_dep INTO DATA(ls_dep)
          WITH KEY objectname = ls_26-viewname BINARY SEARCH.
        IF sy-subrc = 0.
          APPEND VALUE ty_cds_map(
            tabname    = ls_26-tabname
            ddlname    = ls_dep-ddlname
            estado_cds = 'ACTIVA'
          ) TO lt_map.
        ENDIF.
      ENDLOOP.

    ELSEIF s_cds[] IS NOT INITIAL AND lt_dd26s IS NOT INITIAL.
      SORT lt_dd26s BY viewname.
      SELECT ddlname, objectname, state, objecttype
        FROM ddldependency
        INTO TABLE @DATA(lt_dep_f)
        FOR ALL ENTRIES IN @lt_dd26s
        WHERE objectname = @lt_dd26s-viewname
          AND ddlname   IN @s_cds
          AND objecttype = 'VIEW'
          AND state      = 'A'.

      SORT lt_dep_f BY objectname.
      LOOP AT lt_dd26s INTO DATA(ls_26f).
        READ TABLE lt_dep_f INTO DATA(ls_depf)
          WITH KEY objectname = ls_26f-viewname BINARY SEARCH.
        IF sy-subrc = 0.
          APPEND VALUE ty_cds_map(
            tabname    = ls_26f-tabname
            ddlname    = ls_depf-ddlname
            estado_cds = 'ACTIVA'
          ) TO lt_map.
        ENDIF.
      ENDLOOP.
    ENDIF.

    SORT lt_map STABLE BY tabname ddlname.
    DELETE ADJACENT DUPLICATES FROM lt_map COMPARING tabname.
    et_cds_map = lt_map.
  ENDMETHOD.

  METHOD clean_alias.
    rv_alias = to_lower( CONV string( iv_fieldname ) ).
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

  METHOD run.
    DATA: lt_dd02l     TYPE STANDARD TABLE OF ty_dd02l,
          lt_dd02t     TYPE STANDARD TABLE OF ty_dd02t,
          lt_valid_tab TYPE tt_tab_key,
          lt_reftabs   TYPE tt_tab_key,
          lt_ref_dd02l TYPE STANDARD TABLE OF ty_dd02l,
          lt_ref_keys  TYPE STANDARD TABLE OF ty_ref_key,
          lt_cds_map   TYPE tt_cds_map.

    CLEAR: gt_detail, gt_summary, gt_dd03l.

    " 1. Recolectar lista de tablas a auditar
    DATA(lt_req_tabs) = collect_tables( ).
    IF lt_req_tabs IS INITIAL.
      MESSAGE 'Ingrese tablas en S_TAB (Pegar portapapeles), indique un archivo o marque la lista base.'
        TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    " 2. Consulta masiva #1: Metadatos de cabecera de tablas (DD02L y DD02T)
    SELECT tabname, as4local, as4vers, tabclass, clidep
      FROM dd02l
      INTO TABLE @lt_dd02l
      FOR ALL ENTRIES IN @lt_req_tabs
      WHERE tabname  = @lt_req_tabs-tabname
        AND as4local = 'A'.

    SORT lt_dd02l BY tabname as4vers.
    DELETE ADJACENT DUPLICATES FROM lt_dd02l COMPARING tabname.

    SELECT tabname, ddlanguage, as4local, as4vers, ddtext
      FROM dd02t
      INTO TABLE @lt_dd02t
      FOR ALL ENTRIES IN @lt_req_tabs
      WHERE tabname     = @lt_req_tabs-tabname
        AND ddlanguage IN ( @sy-langu, 'S', 'E' )
        AND as4local    = 'A'.

    " Priorizar idioma de conexión del usuario
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

    LOOP AT lt_dd02l INTO DATA(ls_02).
      APPEND VALUE #( tabname = ls_02-tabname ) TO lt_valid_tab.
    ENDLOOP.
    SORT lt_valid_tab BY tabname.
    DELETE ADJACENT DUPLICATES FROM lt_valid_tab COMPARING tabname.

    " 3. Consulta masiva #2: UNA sola lectura a DD03L trae los 3 grupos:
    "    - CLNT (Mandante)
    "    - RAW / LRAW / RAWSTRING (Binarios -> bintohex)
    "    - QUAN / CURR + su REFTABLE y REFFIELD de la SE11
    IF lt_valid_tab IS NOT INITIAL.
      SELECT tabname, fieldname, as4local, as4vers, position,
             keyflag, rollname, datatype, leng, decimals,
             reftable, reffield
        FROM dd03l
        INTO TABLE @gt_dd03l
        FOR ALL ENTRIES IN @lt_valid_tab
        WHERE tabname  = @lt_valid_tab-tabname
          AND as4local = 'A'
          AND datatype IN ( 'CLNT', 'RAW', 'LRAW', 'RAWSTRING', 'QUAN', 'CURR' ).

      DELETE gt_dd03l WHERE fieldname(1) = '.'.
      SORT gt_dd03l BY tabname position.
    ENDIF.

    " 4. Consulta masiva #3: Clasificación y claves primarias de REFTABLE
    "    para informar si la referencia SE11 permite JOIN o exige CAST
    LOOP AT gt_dd03l INTO DATA(ls_f_ref)
      WHERE datatype IN ( 'QUAN', 'CURR' ) AND reftable IS NOT INITIAL.
      APPEND VALUE #( tabname = ls_f_ref-reftable ) TO lt_reftabs.
    ENDLOOP.
    SORT lt_reftabs BY tabname.
    DELETE ADJACENT DUPLICATES FROM lt_reftabs COMPARING tabname.

    IF lt_reftabs IS NOT INITIAL.
      SELECT tabname, as4local, as4vers, tabclass, clidep
        FROM dd02l
        INTO TABLE @lt_ref_dd02l
        FOR ALL ENTRIES IN @lt_reftabs
        WHERE tabname  = @lt_reftabs-tabname
          AND as4local = 'A'.

      SORT lt_ref_dd02l BY tabname as4vers.
      DELETE ADJACENT DUPLICATES FROM lt_ref_dd02l COMPARING tabname.

      SELECT tabname, fieldname, as4local, as4vers, position
        FROM dd03l
        INTO TABLE @lt_ref_keys
        FOR ALL ENTRIES IN @lt_reftabs
        WHERE tabname  = @lt_reftabs-tabname
          AND as4local = 'A'
          AND keyflag  = 'X'.

      DELETE lt_ref_keys WHERE fieldname(1) = '.'.
      SORT lt_ref_keys BY tabname position.
    ENDIF.

    " 5. Consulta masiva #4: Mapeo opcional con Vistas CDS existentes
    load_cds_mapping(
      EXPORTING it_valid_tabs = lt_valid_tab
      IMPORTING et_cds_map    = lt_cds_map ).

    " 6. Procesar tabla por tabla (garantiza que TODAS las ~150 tablas
    "    aparezcan en el reporte, tengan o no mandante / RAW / QUAN / CURR)
    LOOP AT lt_req_tabs INTO DATA(ls_req).
      DATA(ls_sum) = VALUE ty_summary( tabname = ls_req-tabname ).

      READ TABLE lt_dd02t INTO DATA(ls_txt)
        WITH KEY tabname = ls_req-tabname BINARY SEARCH.
      IF sy-subrc = 0.
        ls_sum-ddtext = ls_txt-ddtext.
      ENDIF.

      READ TABLE lt_cds_map INTO DATA(ls_cds)
        WITH KEY tabname = ls_req-tabname BINARY SEARCH.
      IF sy-subrc = 0.
        ls_sum-cds_view   = ls_cds-ddlname.
        ls_sum-estado_cds = ls_cds-estado_cds.
      ENDIF.

      " Verificar existencia de la tabla en DD02L
      READ TABLE lt_dd02l INTO DATA(ls_tab)
        WITH KEY tabname = ls_req-tabname BINARY SEARCH.
      IF sy-subrc <> 0.
        ls_sum-estado_tab  = 'NO EXISTE EN SE11'.
        ls_sum-tiene_mandt = 'N/A'.
        ls_sum-campo_mandt = 'TABLA NO EXISTE'.
        ls_sum-accion_cds  = 'VERIFICAR NOMBRE DE TABLA'.
        add_cell_color( EXPORTING iv_col   = 6
                                  iv_int   = 1
                        CHANGING  ct_color = ls_sum-t_color ).
        APPEND ls_sum TO gt_summary.

        DATA(ls_missing) = VALUE ty_detail(
          tabname       = ls_req-tabname
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

      ls_sum-estado_tab = SWITCH string( ls_tab-tabclass
        WHEN 'TRANSP'  THEN 'TRANSPARENTE'
        WHEN 'INTTAB'  THEN 'ESTRUCTURA'
        WHEN 'VIEW'    THEN 'VISTA DDIC'
        WHEN 'CLUSTER' THEN 'CLUSTER'
        WHEN 'POOL'    THEN 'POOL'
        ELSE CONV string( ls_tab-tabclass ) ).

      "----------------------------------------------------------------
      " A) Identificar Columna de Mandante (CLNT)
      "----------------------------------------------------------------
      DATA(lv_tiene_mandt) = VALUE ty_detail-tiene_mandt( 'NO TIENE' ).
      DATA(lv_campo_mandt) = VALUE ty_detail-campo_mandt( 'NO TIENE' ).

      READ TABLE gt_dd03l TRANSPORTING NO FIELDS
        WITH KEY tabname = ls_req-tabname BINARY SEARCH.
      DATA(lv_start_idx) = sy-tabix.

      IF sy-subrc = 0.
        " Priorizar columna CLNT que sea clave primaria (MANDT, RCLNT, CLIENT)
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

        " Si no tenía CLNT clave pero posee un campo CLNT no clave
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
      " B) Analizar Columnas RAW/Binarias y QUAN/CURR de esta tabla
      "----------------------------------------------------------------
      DATA(lv_rows_added) = 0.
      DATA(lv_raw_str)    = VALUE string( ).
      DATA(lv_qc_str)     = VALUE string( ).

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

          " --- Caso 1: Campos RAW / LRAW / RAWSTRING ---
          IF ls_col-datatype = 'RAW'
             OR ls_col-datatype = 'LRAW'
             OR ls_col-datatype = 'RAWSTRING'.
            ls_sum-cant_raw = ls_sum-cant_raw + 1.
            lv_raw_str = COND string(
              WHEN lv_raw_str IS INITIAL THEN |{ ls_col-fieldname }|
              ELSE |{ lv_raw_str }, { ls_col-fieldname }| ).

            ls_det-categoria = ls_col-datatype.

            IF ls_col-datatype = 'RAW' AND ls_det-leng <= 255.
              ls_det-ubicacion_ref  = 'BINARIO -> USAR BINTOHEX'.
              ls_det-sugerencia_cds =
                |{ lv_key_prefix }bintohex( { lv_field_low } ) as { lv_alias }|.
              ls_det-nota_tecnica   =
                |Convertir RAW({ ls_det-leng }) a CHAR({ ls_det-leng * 2 }) con bintohex en Eclipse|.
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
                |// Excluir { lv_field_low } ({ ls_col-datatype } no admite bintohex)|.
              ls_det-nota_tecnica   =
                |Tipo { ls_col-datatype } no admite BINTOHEX ni ODP; comentar/excluir|.
              add_cell_color( EXPORTING iv_fname = 'CATEGORIA'
                                        iv_col   = 6
                                        iv_int   = 1
                              CHANGING  ct_color = ls_det-t_color ).
            ENDIF.

            APPEND ls_det TO gt_detail.
            lv_rows_added = lv_rows_added + 1.

          " --- Caso 2: Campos QUAN y CURR ---
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

            " Longitud segura para abap.dec(L,D) respetando precisión DDIC
            DATA(lv_cast_len) = nmax( val1 = ls_det-leng
                                      val2 = ls_det-decimals + 1 ).
            IF lv_cast_len > 31.
              lv_cast_len = 31.
            ENDIF.

            ls_det-sugerencia_cds =
              |{ lv_key_prefix }cast( { lv_field_low } | &&
              |as abap.dec({ lv_cast_len },{ ls_det-decimals }) ) as { lv_alias }|.

            " Analizar dónde está definida la referencia SE11 (REFTABLE / REFFIELD)
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
              " La moneda/unidad YA está en la misma tabla
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
              " La referencia apunta FUERA de la tabla -> revisar Tabla vs Estructura
              ls_sum-cant_ext = ls_sum-cant_ext + 1.

              " Armar lista de claves primarias de REFTABLE para facilitar JOIN
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

      " Si la tabla no tuvo filas de detalle (no tiene RAW ni QUAN/CURR mostrables),
      " insertamos una fila de estado para que la tabla y su Mandante SIEMPRE salgan
      IF lv_rows_added = 0.
        DATA(ls_clean_det) = VALUE ty_detail(
          tabname        = ls_req-tabname
          ddtext         = ls_sum-ddtext
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
      ls_sum-lista_raw = COND string(
        WHEN lv_raw_str IS INITIAL THEN 'NINGUNA' ELSE lv_raw_str ).
      ls_sum-lista_qc  = COND string(
        WHEN lv_qc_str  IS INITIAL THEN 'NINGUNA' ELSE lv_qc_str ).

      IF ls_sum-cant_raw > 0 AND ( ls_sum-cant_curr > 0 OR ls_sum-cant_quan > 0 ).
        ls_sum-accion_cds = 'CORREGIR RAW + QUAN/CURR'.
        add_cell_color( EXPORTING iv_fname = 'ACCION_CDS'
                                  iv_col   = 7
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
      ELSEIF ls_sum-cant_curr > 0 OR ls_sum-cant_quan > 0.
        ls_sum-accion_cds = 'REVISAR QUAN/CURR (REF. INTERNA)'.
        add_cell_color( EXPORTING iv_fname = 'ACCION_CDS'
                                  iv_col   = 3
                                  iv_int   = 0
                        CHANGING  ct_color = ls_sum-t_color ).
      ELSE.
        ls_sum-accion_cds = 'OK - SIN RAW NI QUAN/CURR'.
        add_cell_color( EXPORTING iv_fname = 'ACCION_CDS'
                                  iv_col   = 5
                                  iv_int   = 0
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

    " 7. Mostrar grilla ALV según vista elegida
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
          IMPORTING r_salv_table = DATA(lo_salv)
          CHANGING  t_table      = gt_detail ).

        lo_salv->get_functions( )->set_all( abap_true ).

        DATA(lo_disp) = lo_salv->get_display_settings( ).
        lo_disp->set_striped_pattern( abap_true ).
        lo_disp->set_list_header(
          |Auditoría CDS BigQuery: Detalle RAW, QUAN/CURR y Mandante ({ lines( gt_summary ) } tablas)| ).

        DATA(lo_cols) = lo_salv->get_columns( ).
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
        set_col_text( io_cols = lo_cols iv_col = 'CDS_VIEW'
                      iv_s = 'Vista CDS'  iv_m = 'Vista CDS'
                      iv_l = 'Vista CDS (Doble clic genera código)' ).
        set_col_text( io_cols = lo_cols iv_col = 'ESTADO_CDS'
                      iv_s = 'Est. CDS'   iv_m = 'Estado Vista CDS'
                      iv_l = 'Estado Vista CDS (Activa/Inactiva)' ).
        set_col_text( io_cols = lo_cols iv_col = 'TIENE_MANDT'
                      iv_s = '¿Mandante?' iv_m = '¿Tiene Mandante?'
                      iv_l = '¿Tiene Columna de Mandante?' ).
        set_col_text( io_cols = lo_cols iv_col = 'CAMPO_MANDT'
                      iv_s = 'Col.Mandt'  iv_m = 'Columna Mandante'
                      iv_l = 'Columna Mandante (o NO TIENE)' ).
        set_col_text( io_cols = lo_cols iv_col = 'CATEGORIA'
                      iv_s = 'Categoría'  iv_m = 'Categoría Hallazgo'
                      iv_l = 'Categoría (RAW / CURR / QUAN)' ).
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
                      iv_l = 'Expresión CDS Lista para Eclipse' ).
        set_col_text( io_cols = lo_cols iv_col = 'NOTA_TECNICA'
                      iv_s = 'Guía'       iv_m = 'Guía de Acción'
                      iv_l = 'Guía para Ajuste en Eclipse' ).

        lo_salv->get_layout( )->set_key(
          VALUE salv_s_layout_key( report = sy-repid handle = 'DET' ) ).
        lo_salv->get_layout( )->set_save_restriction( if_salv_c_layout=>restrict_none ).

        SET HANDLER on_double_click FOR lo_salv->get_event( ).

        lo_salv->display( ).

      CATCH cx_salv_msg INTO DATA(lx_msg).
        MESSAGE lx_msg->get_text( ) TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD display_summary_alv.
    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = DATA(lo_salv)
          CHANGING  t_table      = gt_summary ).

        lo_salv->get_functions( )->set_all( abap_true ).

        DATA(lo_disp) = lo_salv->get_display_settings( ).
        lo_disp->set_striped_pattern( abap_true ).
        lo_disp->set_list_header(
          |Auditoría CDS BigQuery: Resumen por Tabla ({ lines( gt_summary ) } tablas)| ).

        DATA(lo_cols) = lo_salv->get_columns( ).
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
                      iv_l = 'Clase de Tabla en SE11' ).
        set_col_text( io_cols = lo_cols iv_col = 'CDS_VIEW'
                      iv_s = 'Vista CDS'  iv_m = 'Vista CDS'
                      iv_l = 'Vista CDS (Doble clic genera código)' ).
        set_col_text( io_cols = lo_cols iv_col = 'ESTADO_CDS'
                      iv_s = 'Est. CDS'   iv_m = 'Estado Vista CDS'
                      iv_l = 'Estado Vista CDS (Activa/Inactiva)' ).
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
                      iv_s = 'Acción CDS' iv_m = 'Resumen Acción CDS'
                      iv_l = 'Resumen de Corrección en Eclipse' ).

        lo_salv->get_layout( )->set_key(
          VALUE salv_s_layout_key( report = sy-repid handle = 'RES' ) ).
        lo_salv->get_layout( )->set_save_restriction( if_salv_c_layout=>restrict_none ).

        SET HANDLER on_double_click FOR lo_salv->get_event( ).

        lo_salv->display( ).

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

      IF column = 'REFTABLE' AND ls_det-reftable IS NOT INITIAL.
        open_se11_table( ls_det-reftable ).
      ELSEIF ( column = 'CDS_VIEW' OR column = 'SUGERENCIA_CDS' )
             AND ls_det-cds_view IS NOT INITIAL.
        preview_cds_code( iv_ddlname = ls_det-cds_view
                          iv_tabname = ls_det-tabname ).
      ELSEIF ls_det-tabname IS NOT INITIAL.
        open_se11_table( ls_det-tabname ).
      ENDIF.

    ELSE.
      READ TABLE gt_summary INTO DATA(ls_sum) INDEX row.
      IF sy-subrc <> 0.
        RETURN.
      ENDIF.

      IF column = 'CDS_VIEW' AND ls_sum-cds_view IS NOT INITIAL.
        preview_cds_code( iv_ddlname = ls_sum-cds_view
                          iv_tabname = ls_sum-tabname ).
      ELSEIF ls_sum-tabname IS NOT INITIAL.
        open_se11_table( ls_sum-tabname ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD open_se11_table.
    CALL FUNCTION 'RS_TOOL_ACCESS'
      EXPORTING
        operation   = 'SHOW'
        object_name = iv_tabname
        object_type = 'TABL'
      EXCEPTIONS
        OTHERS      = 1.
    IF sy-subrc <> 0.
      MESSAGE |No fue posible abrir { iv_tabname } en SE11.|
        TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.
  ENDMETHOD.

  METHOD preview_cds_code.
    " Genera en memoria (sin pedir OT ni modificar nada en SAP) el código
    " fuente sugerido unificando bintohex(RAW) + cast(QUAN/CURR)
    SELECT as4local, source
      FROM ddddlsrc
      INTO TABLE @DATA(lt_src)
      WHERE ddlname  = @iv_ddlname
        AND as4local IN ( 'A', 'I', 'N' ).

    IF sy-subrc <> 0 OR lt_src IS INITIAL.
      MESSAGE |No se encontró código fuente en DDDDLSRC para { iv_ddlname }.|
        TYPE 'I'.
      RETURN.
    ENDIF.

    " Priorizar versión en edición ('N'/'I') sobre activa ('A')
    SORT lt_src BY as4local DESCENDING.
    READ TABLE lt_src INTO DATA(ls_src) INDEX 1.

    DATA: lt_lines         TYPE STANDARD TABLE OF string,
          lt_out           TYPE STANDARD TABLE OF string,
          lt_pending_annot TYPE STANDARD TABLE OF string.

    SPLIT ls_src-source AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.

    DATA(lv_in_braces) = abap_false.

    LOOP AT lt_lines INTO DATA(lv_line).
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf(1)
        IN lv_line WITH ''.
      DATA(lv_orig) = lv_line.
      DATA(lv_trim) = condense( lv_line ).

      IF lv_trim CS '{'.
        lv_in_braces = abap_true.
        IF lv_trim = '{'.
          APPEND lv_orig TO lt_out.
          CONTINUE.
        ENDIF.
      ENDIF.

      IF lv_trim CS '}'.
        APPEND LINES OF lt_pending_annot TO lt_out.
        CLEAR lt_pending_annot.
        lv_in_braces = abap_false.
        APPEND lv_orig TO lt_out.
        CONTINUE.
      ENDIF.

      IF lv_in_braces = abap_false OR lv_trim IS INITIAL.
        APPEND lv_orig TO lt_out.
        CONTINUE.
      ENDIF.

      " Ignorar líneas de comentarios puros
      IF ( strlen( lv_trim ) >= 2
           AND ( lv_trim(2) = '//' OR lv_trim(2) = '/*' OR lv_trim(2) = '--' ) )
         OR lv_trim(1) = '*'.
        APPEND lv_orig TO lt_out.
        CONTINUE.
      ENDIF.

      " Retener anotaciones @Semantics de moneda/cantidad por si el campo
      " siguiente se castea a abap.dec (para comentarlas y evitar error ADT)
      IF lv_trim(1) = '@'.
        DATA(lv_low_ann) = to_lower( lv_trim ).
        IF lv_low_ann CS '@semantics.amount.currencycode'
           OR lv_low_ann CS '@semantics.quantity.unitofmeasure'.
          APPEND lv_orig TO lt_pending_annot.
        ELSE.
          APPEND lv_orig TO lt_out.
        ENDIF.
        CONTINUE.
      ENDIF.

      " Detectar coma inicial o final para respetar estilo del generador
      DATA(lv_lead_comma)  = abap_false.
      DATA(lv_trail_comma) = abap_false.
      IF lv_trim(1) = ','.
        lv_lead_comma = abap_true.
      ELSEIF lv_trim CS ','.
        lv_trail_comma = abap_true.
      ENDIF.

      DATA(lv_work) = lv_trim.
      IF lv_work CS '//'.
        SPLIT lv_work AT '//' INTO lv_work DATA(lv_inline_comment).
      ENDIF.
      REPLACE ALL OCCURRENCES OF ',' IN lv_work WITH ` `.
      lv_work = condense( lv_work ).

      SPLIT lv_work AT space INTO TABLE DATA(lt_tokens).
      IF lt_tokens IS INITIAL.
        APPEND LINES OF lt_pending_annot TO lt_out.
        CLEAR lt_pending_annot.
        APPEND lv_orig TO lt_out.
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
      IF lv_lookup_fld CS '.'.
        SPLIT lv_lookup_fld AT '.' INTO DATA(lv_tab_pref) lv_lookup_fld.
      ENDIF.

      " Buscar si el token corresponde a un campo RAW, QUAN o CURR de la tabla
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
                   OR ls_g-datatype = 'QUAN'
                   OR ls_g-datatype = 'CURR' ).
            ls_match = ls_g.
            lv_found = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.

      " Si P_ONLYX está activo, no castear QUAN/CURR con referencia interna
      IF lv_found = abap_true
         AND p_onlyx = abap_true
         AND ( ls_match-datatype = 'QUAN' OR ls_match-datatype = 'CURR' )
         AND ls_match-reftable = iv_tabname.
        lv_found = abap_false.
      ENDIF.

      IF lv_found = abap_true.
        LOOP AT lt_pending_annot INTO DATA(lv_pa).
          APPEND |  // { condense( lv_pa ) }| TO lt_out.
        ENDLOOP.
        CLEAR lt_pending_annot.

        DATA(lv_alias_out) = clean_alias( lv_raw_token ).
        DATA(lv_as_pos)    = lv_idx + 1.
        DATA(lv_al_pos)    = lv_idx + 2.
        IF lines( lt_tokens ) >= lv_al_pos
           AND to_lower( lt_tokens[ lv_as_pos ] ) = 'as'.
          lv_alias_out = lt_tokens[ lv_al_pos ].
        ENDIF.

        DATA(lv_k_txt)  = COND string( WHEN lv_is_key = abap_true THEN 'key ' ELSE '' ).
        DATA(lv_lc_txt) = COND string( WHEN lv_lead_comma  = abap_true THEN ', ' ELSE '' ).
        DATA(lv_tc_txt) = COND string( WHEN lv_trail_comma = abap_true THEN ','  ELSE '' ).

        IF ls_match-datatype = 'RAW'.
          APPEND
            |  { lv_lc_txt }{ lv_k_txt }bintohex( { lv_raw_token } ) as { lv_alias_out }{ lv_tc_txt }|
            TO lt_out.
        ELSE.
          DATA(lv_len_i) = nmax( val1 = CONV int4( ls_match-leng )
                                 val2 = CONV int4( ls_match-decimals ) + 1 ).
          IF lv_len_i > 31.
            lv_len_i = 31.
          ENDIF.
          DATA(lv_dec_i) = CONV int4( ls_match-decimals ).
          APPEND
            |  { lv_lc_txt }{ lv_k_txt }cast( { lv_raw_token } | &&
            |as abap.dec({ lv_len_i },{ lv_dec_i }) ) as { lv_alias_out }{ lv_tc_txt }|
            TO lt_out.
        ENDIF.
      ELSE.
        APPEND LINES OF lt_pending_annot TO lt_out.
        CLEAR lt_pending_annot.
        APPEND lv_orig TO lt_out.
      ENDIF.
    ENDLOOP.

    APPEND LINES OF lt_pending_annot TO lt_out.

    cl_demo_output=>display_data(
      value = lt_out
      name  = |Vista Previa CDS Sugerida (Solo Lectura): { iv_ddlname } ({ iv_tabname })| ).
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

  txt_b2  = '2. Vínculo Opcional con Vistas CDS ya Creadas'.
  c_tip2  = 'Opcional: filtro ej. Z*BQ* o ZCDS* para asociar vistas activas/inactivas.'.

  txt_b3  = '3. Modo de Visualización ALV (Exportable a Excel)'.
  c_det   = 'Vista Detallada (RAW, QUAN/CURR + Ref. SE11 + Mandante + Código CDS)'.
  c_res   = 'Vista Resumen (1 fila por tabla: Mandante SI/NO + Conteos + Acción)'.
  c_onlyx = 'Ocultar QUAN/CURR cuya moneda/unidad ya está en la misma tabla'.

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
