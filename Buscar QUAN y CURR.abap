REPORT zgen_cds_cast.

PARAMETERS: p_cds TYPE ddddlsrc-ddlname OBLIGATORY,
            p_tab TYPE dd03l-tabname   OBLIGATORY.

START-OF-SELECTION.

  " 1. Extraer metadatos de campos QUAN y CURR
  SELECT fieldname, datatype
    FROM dd03l
    INTO TABLE @DATA(lt_fields)
    WHERE tabname = @p_tab
      AND datatype IN ('QUAN', 'CURR')
      AND as4local = 'A'.

  IF sy-subrc <> 0.
    WRITE: / 'No se encontraron campos de cantidad o moneda para la tabla', p_tab.
    RETURN.
  ENDIF.

  " 2. Extraer el código fuente de la CDS (Activa o Inactiva)
  DATA: lv_source TYPE string.
  SELECT SINGLE source FROM ddddlsrc INTO @lv_source
    WHERE ddlname = @p_cds AND as4local IN ('A', 'I', 'N').

  IF sy-subrc <> 0.
    WRITE: / 'No se encontró el código fuente para la vista CDS', p_cds.
    RETURN.
  ENDIF.

  DATA: lt_lines TYPE TABLE OF string,
        lt_out   TYPE TABLE OF string,
        lv_line  TYPE string.

  SPLIT lv_source AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.

  " 3. El Motor V2: Análisis palabra por palabra (Tokenización)
  LOOP AT lt_lines INTO lv_line.
    DATA(lv_original_line) = lv_line.
    DATA(lv_temp) = condense( val = lv_line ).

    " Ignorar llaves, anotaciones o líneas vacías
    IF lv_temp IS INITIAL OR lv_temp(1) = '{' OR lv_temp(1) = '}' OR lv_temp(1) = '@'.
      APPEND lv_original_line TO lt_out.
      CONTINUE.
    ENDIF.

    " Detectar y aislar la coma final
    DATA(lv_has_comma) = abap_false.
    IF lv_temp CS ','.
      lv_has_comma = abap_true.
      REPLACE ALL OCCURRENCES OF ',' IN lv_temp WITH space.
    ENDIF.
    lv_temp = condense( lv_temp ).

    " Separar la línea en palabras (tokens)
    SPLIT lv_temp AT space INTO TABLE DATA(lt_tokens).
    IF lines( lt_tokens ) = 0.
      APPEND lv_original_line TO lt_out.
      CONTINUE.
    ENDIF.

    " Identificar si la línea empieza con 'key'
    DATA(lv_idx) = 1.
    DATA(lv_is_key) = abap_false.
    IF to_lower( lt_tokens[ 1 ] ) = 'key'.
      lv_idx = 2.
      lv_is_key = abap_true.
    ENDIF.

    " Validar si la palabra actual es un campo de nuestra tabla
    DATA(lv_fieldname) = lt_tokens[ lv_idx ].
    DATA(lv_fieldname_upper) = to_upper( lv_fieldname ).

    READ TABLE lt_fields INTO DATA(ls_field) WITH KEY fieldname = lv_fieldname_upper.
    
    IF sy-subrc = 0. " ¡Bingo! Es un campo QUAN o CURR
      DATA(lv_decimals) = COND string( WHEN ls_field-datatype = 'QUAN' THEN '3' ELSE '2' ).
      
      " Determinar el Alias
      DATA(lv_alias) = lv_fieldname.
      " Si es un namespace (/cwm/menge), el alias limpio por defecto debe ser cwm_menge
      REPLACE ALL OCCURRENCES OF '/' IN lv_alias WITH '_'.
      IF lv_alias(1) = '_'. lv_alias = lv_alias+1. ENDIF.

      " Si el usuario ya había puesto un 'AS alias', lo respetamos
      DATA(lv_as_idx) = lv_idx + 1.
      DATA(lv_alias_idx) = lv_idx + 2.
      IF lines( lt_tokens ) >= lv_alias_idx.
        IF to_lower( lt_tokens[ lv_as_idx ] ) = 'as'.
          lv_alias = lt_tokens[ lv_alias_idx ].
        ENDIF.
      ENDIF.

      " Reconstruir la línea con la sintaxis perfecta
      DATA(lv_key_str) = COND string( WHEN lv_is_key = abap_true THEN 'key ' ELSE '' ).
      DATA(lv_comma_str) = COND string( WHEN lv_has_comma = abap_true THEN ' ,' ELSE '' ).
      
      " Mantenemos una indentación limpia
      lv_line = |  { lv_key_str }cast( { lv_fieldname } as abap.dec(23,{ lv_decimals }) ) as { lv_alias }{ lv_comma_str }|.
      APPEND lv_line TO lt_out.
      
    ELSE.
      " No es un campo a castear, lo dejamos exactamente como estaba
      APPEND lv_original_line TO lt_out.
    ENDIF.

  ENDLOOP.

  " 4. Mostrar el código final
  cl_demo_output=>display_data( 
    value = lt_out 
    name  = |Código Generado para { p_cds }| 
  ).