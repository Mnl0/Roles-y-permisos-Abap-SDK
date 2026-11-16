*&---------------------------------------------------------------------*
*& Report ZGEN_FIND_RAW_FIELDS
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ZGEN_FIND_RAW_FIELDS.

" Estructura para mostrar el resultado limpio
TYPES: BEGIN OF ty_result,
         tabname   TYPE tabname,
         fieldname TYPE fieldname,
       END OF ty_result.

DATA: lt_tables  TYPE TABLE OF tabname,
      lt_results TYPE TABLE OF ty_result.

START-OF-SELECTION.

  " 1. Hardcodeamos tu lista exacta de 120 tablas
  lt_tables = VALUE #(
		( 'ACDOCA' ) ( 'ADR6' ) ( 'ADRC' ) ( 'ADRCT' ) ( 'ADRT' ) ( 'AFKO' ) ( 'AFPO' ) ( 'AUFK' ) ( 'BKPF' )
		( 'BSAD_BCK' ) ( 'BSEG' ) ( 'BUT000' ) ( 'BUT020' ) ( 'CEPC' ) ( 'CEPCT' ) ( 'CKMLCR' ) ( 'CKMLHD' )
		( 'CSKS' ) ( 'CSKT' ) ( 'DD03L' ) ( 'EKBE' ) ( 'EKES' ) ( 'EKET' ) ( 'EKKN' ) ( 'EKKO' ) ( 'EKPO' )
		( 'FINSC_LD_CMP' ) ( 'FINSC_LEDGER' ) ( 'FINSC_LEDGER_REP' ) ( 'FINSC_LEDGER_T' ) ( 'HRRP_DIRECTORY' )
		( 'HRRP_NODE' ) ( 'HRRP_NODET' ) ( 'JEST' ) ( 'KNA1' ) ( 'KNVV' ) ( 'LFA1' ) ( 'LIKP' ) ( 'LIPS' )
		( 'MAKT' ) ( 'MARA' ) ( 'MARC' ) ( 'MARD' ) ( 'MARM' ) ( 'MAST' ) ( 'MATDOC' ) ( 'MBEW' ) ( 'MBEWH' )
		( 'MCH1' ) ( 'MCHA' ) ( 'MKOL' ) ( 'MSKA' ) ( 'MSKU' ) ( 'MSLB' ) ( 'MVKE' ) ( 'PRCD_ELEMENTS' )
		( 'RBCO' ) ( 'RBKP' ) ( 'RSEG' ) ( 'SETHANAHIER0101' ) ( 'SETHANAHIER0106' ) ( 'SETHEADER' )
		( 'SETHEADERT' ) ( 'SETLEAF' ) ( 'SETNODE' ) ( 'SKA1' ) ( 'SKAT' ) ( 'STAS' ) ( 'STKO' ) ( 'STPO' )
		( 'T001' ) ( 'T001K' ) ( 'T001L' ) ( 'T001W' ) ( 'T002' ) ( 'T005' ) ( 'T005K' ) ( 'T005S' ) ( 'T005T' )
		( 'T006' ) ( 'T006A' ) ( 'T006T' ) ( 'T009' ) ( 'T009B' ) ( 'T023' ) ( 'T023T' ) ( 'T024' ) ( 'T024E' )
		( 'T134' ) ( 'T134T' ) ( 'T148T' ) ( 'T156T' ) ( 'T157E' ) ( 'T161' ) ( 'T161T' ) ( 'T179' ) ( 'T179T' )
		( 'T881' ) ( 'T881T' ) ( 'TCURC' ) ( 'TCURF' ) ( 'TCURR' ) ( 'TCURT' ) ( 'TCURX' ) ( 'TJ02T' )
		( 'TKA02' ) ( 'TSPA' ) ( 'TSPAT' ) ( 'TVARVC' ) ( 'TVFST' ) ( 'TVKO' ) ( 'TVKOT' ) ( 'TVLST' )
		( 'TVM1T' ) ( 'TVTW' ) ( 'TVTWT' ) ( 'VBAK' ) ( 'VBAP' ) ( 'VBEP' ) ( 'VBFA' ) ( 'VBPA' ) ( 'VBRK' ) ( 'VBRP' ) 
  ).

  " 2. Buscar campos RAW en DD03L de forma masiva (Alta performance)
  IF lt_tables IS NOT INITIAL.
    SELECT tabname, fieldname
      FROM dd03l
      INTO TABLE @DATA(lt_raw_fields)
      FOR ALL ENTRIES IN @lt_tables
      WHERE tabname  = @lt_tables-table_line
        AND datatype = 'RAW'
        AND as4local = 'A'.

    IF sy-subrc = 0.
      " Trasladar a nuestra tabla de salida
      LOOP AT lt_raw_fields INTO DATA(ls_raw).
        APPEND VALUE #( tabname = ls_raw-tabname fieldname = ls_raw-fieldname ) TO lt_results.
      ENDLOOP.

      " Ordenar alfabéticamente por tabla y luego por campo
      SORT lt_results BY tabname fieldname.
    ENDIF.
  ENDIF.

  " 3. Mostrar el reporte en una grilla limpia
  IF lt_results IS INITIAL.
    cl_demo_output=>display( 'No se encontraron campos RAW en ninguna de las tablas.' ).
  ELSE.
    cl_demo_output=>display_data(
      value = lt_results
      name  = 'Campos RAW (Hexadecimales / UUIDs) identificados'
    ).
  ENDIF.