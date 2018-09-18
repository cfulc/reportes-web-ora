create or replace FUNCTION                                                                                                                                                                                                                                                                                                                               DOCUMENTOS_CARGOS_ABONOS (
    EMPRESA_ID NUMBER,
    FECHA_REP DATE,
    LOCAL_EXT NUMBER /* PROVEEDORES  0 - TODOS  1 - LOCALES  2 - EXTRANJEROS */,
    TIPO_MONEDA NUMBER /* TIPO DE MONEDA  0 - LOCAL  1 - EXTRANJERA */,
    TIPO_FECHA NUMBER /* TIPO DE FECHA  0 - DOCUMENTO  1 - OPERACION  2 - JORNALIZACION */,
    INCLUYE_TIPO_DOCTOS NUMBER,
    LISTA_TIPO_DOCTOS VARCHAR2,
    INCLUYE_PROVEEDORES NUMBER,
    LISTA_PROVEEDORES VARCHAR2)
RETURN CXPDB.T_DOCUMENTOS AS
    RESULTFN T_DOCUMENTOS := T_DOCUMENTOS();
    INDEXFN INTEGER := 0;
BEGIN
    FOR DOC IN (
        WITH EMPRESA AS (
            SELECT
                E.EMP_ID ID,
                E.MON_ID MONEDAID,
                E.MON_ID_E MONEDAEXTID,
                DEP.PAIS_ID PAISID,
                NVL(CNF.TPDC_CAR_DIF_CAM_ID, 0) TIPO_CARGODIF
            FROM GENERAL.GEN_EMPRESAS E
            JOIN GENERAL.GEN_CIUDADES CIU ON CIU.CIU_ID = E.CIU_ID
            JOIN GENERAL.GEN_DEPTOS DEP ON DEP.DEP_ID = CIU.DEP_ID
            LEFT JOIN CXPDB.CXP_CONFIGURACIONES CNF ON CNF.EMP_ID = E.EMP_ID
            WHERE
                E.EMP_ID = EMPRESA_ID
        ),
        POLIZAS AS (
            SELECT ENPO_ID ID, TPPO_ID TIPO, ENPO_POLIZA POLIZA, ENPO_FECHA FECHA, ENPO_MES_ANIO MES
            FROM CONTADB.CON_ENC_POLIZAS
            WHERE
                EMP_ID = EMPRESA_ID
                AND ENPO_FECHA <= FECHA_REP
        ),
        PROVEEDORES AS (
            SELECT
                P.PRO_ID ID, CASE WHEN E.ENT_GENERO = 0 THEN NVL(E.ENT_APELLIDO1, E.ENT_NOMBRE1) ELSE NVL(E.ENT_APELLIDO1, '') || NVL(E.ENT_APELLIDO1, '') || NVL(E.ENT_NOMBRE1, '') || NVL(E.ENT_NOMBRE2, '') END PROVEEDOR
            FROM GENERAL.GEN_PROVEEDORES P
            JOIN GENERAL.GEN_ENTIDADES E ON E.ENT_ID = P.ENT_ID
            JOIN EMPRESA EMP ON 1 = 1
            WHERE
              (LOCAL_EXT = 1 AND P.PAIS_ID = EMP.PAISID) OR (LOCAL_EXT = 2 AND P.PAIS_ID <> EMP.PAISID) OR (LOCAL_EXT = 0)
        ),
        CARGOS AS (
            SELECT
                C.CGPR_ID ID,
                C.MON_ID,
                PRO.ID PRO_ID,
                PRO.PROVEEDOR,
                C.TPDC_ID TIPO_DOCTO_ID,
                TD.TPDC_DESCRIPCION TIPO_DOCTO,
                NVL(C.CGPR_SERIE, '') || NVL(C.CGPR_CORRELATIVO, 0) DOCUMENTO,
                NVL(C.CGPR_ING_BODEGA, '') INGRESO_ORDEN,
                CUO.CTCG_FECHA FECHA_CUOTA,
                CUO.CTCG_ID CUOTAID,
                CUO.CTCG_NUM_CUOTA NUM_CUOTA,
                CASE WHEN TIPO_FECHA = 0 THEN C.CGPR_FECHA WHEN TIPO_FECHA = 1 THEN C.BIT_CREADO WHEN TIPO_FECHA = 2 THEN P.FECHA ELSE P.FECHA END FECHA,
                ROUND((CUO.CTCG_VAL_CAPITAL + CUO.CTCG_IVA_CAPITAL) *
                CASE WHEN C.TPDC_ID = TIPO_CARGODIF THEN
                    CASE WHEN TIPO_MONEDA = 0 THEN
                        CASE WHEN C.MON_ID = EMP.MONEDAID THEN
                            1
                        ELSE
                            0
                        END
                    ELSE
                        CASE WHEN C.MON_ID = EMP.MONEDAEXTID THEN
                            1
                        ELSE
                            0
                        END
                    END
                ELSE
                    1
                END *
                CASE WHEN TIPO_MONEDA = 0 THEN
                    CASE WHEN C.MON_ID = EMP.MONEDAID THEN
                        1
                    ELSE
                        C.CGPR_TASA_CAMBIO * C.CGPR_TASA_EXT
                    END                            
                ELSE
                    C.CGPR_TASA_EXT
                END, 2) CUOTA
            FROM CXPDB.CXP_CARGOS_PROV C
            JOIN CXPDB.CXP_TIP_DOCUMENTOS TD ON TD.TPDC_ID = C.TPDC_ID
            JOIN EMPRESA EMP ON EMP.ID = C.EMP_ID
            JOIN PROVEEDORES PRO ON PRO.ID = C.PRO_ID
            LEFT JOIN POLIZAS P ON P.ID = C.ENPO_ID
            JOIN CXPDB.CXP_CUO_CARGOS CUO ON CUO.CGPR_ID = C.CGPR_ID
            WHERE
                C.EMP_ID = EMPRESA_ID
                AND ((INSTR(LISTA_TIPO_DOCTOS, ',' || C.TPDC_ID || ',') = INCLUYE_TIPO_DOCTOS) OR (LISTA_TIPO_DOCTOS IS NULL))
                AND ((INSTR(LISTA_PROVEEDORES, ',' || PRO.ID || ',') = INCLUYE_PROVEEDORES) OR (LISTA_PROVEEDORES IS NULL))
                AND ((TIPO_FECHA = 0 AND C.CGPR_FECHA <= FECHA_REP) OR (TIPO_FECHA = 1 AND TRUNC(C.BIT_CREADO) <= FECHA_REP) OR (TIPO_FECHA = 2 AND P.FECHA <= FECHA_REP))
        ),
        ABONOS AS (
            SELECT 
                A.ENAB_ID ID,
                A.MON_ID,
                PRO.ID PRO_ID,
                PRO.PROVEEDOR,
                A.TPDC_ID TIPO_DOCTO_ID,
                TD.TPDC_DESCRIPCION TIPO_DOCTO,
                NVL(A.ENAB_SERIE, '') || NVL(A.ENAB_CORRELATIVO, 0) DOCUMENTO,
                PA.DTPA_ID PAGOID,
                PA.CTCG_ID CUOTAID,
                CASE WHEN TIPO_FECHA = 0 THEN A.ENAB_FECHA WHEN TIPO_FECHA = 1 THEN A.ENAB_FECHA_CREA WHEN TIPO_FECHA = 2 THEN P.FECHA ELSE P.FECHA END FECHA,
                CASE WHEN TIPO_MONEDA = 0 THEN
                    PA.DTPA_VAL_PAGADO
                ELSE
                    PA.DTPA_VAL_PAGADO_EXT
                END PAGADO
            FROM CXPDB.CXP_ENC_ABONOS A
            JOIN CXPDB.CXP_TIP_DOCUMENTOS TD ON TD.TPDC_ID = A.TPDC_ID
            JOIN EMPRESA EMP ON EMP.ID = A.EMP_ID
            JOIN PROVEEDORES PRO ON PRO.ID = A.PRO_ID
            JOIN CXPDB.CXP_DET_PAG_ABONOS PA ON PA.ENAB_ID = A.ENAB_ID
            LEFT JOIN POLIZAS P ON P.ID = A.ENPO_ID
            WHERE
                A.EMP_ID = EMPRESA_ID
                AND ((INSTR(LISTA_TIPO_DOCTOS, ',' || A.TPDC_ID || ',') = INCLUYE_TIPO_DOCTOS) OR (LISTA_TIPO_DOCTOS IS NULL))
                AND ((INSTR(LISTA_PROVEEDORES, ',' || PRO.ID || ',') = INCLUYE_PROVEEDORES) OR (LISTA_PROVEEDORES IS NULL))
                AND ((TIPO_FECHA = 0 AND A.ENAB_FECHA <= FECHA_REP) OR (TIPO_FECHA = 1 AND TRUNC(A.ENAB_FECHA_CREA) <= FECHA_REP) OR (TIPO_FECHA = 2 AND P.FECHA <= FECHA_REP))
                AND A.ENAB_APLICADO = 1
                AND A.ENAB_ANULADO = 0
        ),
        CARGOS_ABONOS AS (
            SELECT  'C' TIPO, C.ID, C.PRO_ID, C.PROVEEDOR, C.TIPO_DOCTO_ID, C.TIPO_DOCTO, C.INGRESO_ORDEN, C.DOCUMENTO, C.MON_ID, C.FECHA_CUOTA, C.CUOTAID, C.NUM_CUOTA CUOTA, C.FECHA, C.CUOTA VALOR
            FROM CARGOS C
            UNION ALL
            SELECT 'A' TIPO, A.ID, A.PRO_ID, A.PROVEEDOR, A.TIPO_DOCTO_ID, A.TIPO_DOCTO, '', A.DOCUMENTO, A.MON_ID, NULL FECHA_CUOTA, A.CUOTAID, NULL CUOTA, A.FECHA, -A.PAGADO VALOR
            FROM ABONOS A
            ORDER BY CUOTAID, TIPO DESC, FECHA DESC
        )
        SELECT * FROM CARGOS_ABONOS
    )
    LOOP
        RESULTFN.EXTEND;
        INDEXFN := INDEXFN + 1;
        RESULTFN(INDEXFN) := O_DOCUMENTOS(
        DOC.ID, DOC.PRO_ID, DOC.PROVEEDOR, DOC.TIPO_DOCTO_ID, DOC.TIPO_DOCTO, DOC.INGRESO_ORDEN, DOC.DOCUMENTO, DOC.MON_ID, DOC.FECHA, DOC.FECHA_CUOTA, DOC.TIPO, DOC.CUOTAID, DOC.CUOTA, DOC.VALOR);
    END LOOP;
    RETURN RESULTFN;
END DOCUMENTOS_CARGOS_ABONOS;