SELECT
    CODIGO_PROVEEDOR,
    PROVEEDOR,
    TIPO_DOCTO_ID || '-' || TIPO_DOCTO TIPO_DOCTO,
    INGRESO_ORDEN,
    DOCUMENTO,
    FECHA,
    SUM(CASE WHEN DIAS BETWEEN -30 AND -1 THEN VALOR + PAGADO ELSE 0 END) VENCIDO_30,
    SUM(CASE WHEN DIAS BETWEEN -60 AND -31 THEN VALOR + PAGADO ELSE 0 END) VENCIDO_60,
    SUM(CASE WHEN DIAS BETWEEN -90 AND -61 THEN VALOR + PAGADO ELSE 0 END) VENCIDO_90,
    SUM(CASE WHEN DIAS BETWEEN -120 AND -91 THEN VALOR + PAGADO ELSE 0 END) VENCIDO_120,
    SUM(CASE WHEN DIAS < -120 THEN VALOR + PAGADO ELSE 0 END) VENCIDO_MAS,
    SUM(CASE WHEN DIAS < 0 THEN VALOR + PAGADO ELSE 0 END) VENCIDO_TOTAL,
    SUM(CASE WHEN DIAS BETWEEN 0 AND 30 THEN VALOR + PAGADO ELSE 0 END) VENCER_30,
    SUM(CASE WHEN DIAS BETWEEN 31 AND 60 THEN VALOR + PAGADO ELSE 0 END) VENCER_60,
    SUM(CASE WHEN DIAS BETWEEN 61 AND 90 THEN VALOR + PAGADO ELSE 0 END) VENCER_90,
    SUM(CASE WHEN DIAS BETWEEN 91 AND 120 THEN VALOR + PAGADO ELSE 0 END) VENCER_120,
    SUM(CASE WHEN DIAS > 120 THEN VALOR + PAGADO ELSE 0 END) VENCER_MAS,
    SUM(CASE WHEN DIAS >= 0 THEN VALOR + PAGADO ELSE 0 END) VENCER_TOTAL,
    ROUND(SUM(VALOR) + SUM(PAGADO), 2) SALDO,
    SUM(DEBITOS) DEBITO_POR_APLICAR,
    ROUND(SUM(VALOR) + SUM(PAGADO) + SUM(DEBITOS), 2) SALDO_APLICADO
FROM (
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
	        E.EMP_ID = $P{empresaId}
	),
	POLIZAS AS (
	    SELECT ENPO_ID ID, TPPO_ID TIPO, ENPO_POLIZA POLIZA, ENPO_FECHA FECHA, ENPO_MES_ANIO MES
	    FROM CONTADB.CON_ENC_POLIZAS
	    WHERE
	        EMP_ID = 100
	        AND ENPO_FECHA <= TO_DATE($P{fecha}, 'DD/MM/YYYY')
	),
	PROVEEDORES AS (
	    SELECT
	        P.PRO_ID ID, CASE WHEN E.ENT_GENERO = 0 THEN NVL(E.ENT_APELLIDO1, E.ENT_NOMBRE1) ELSE NVL(E.ENT_APELLIDO1, '') || NVL(E.ENT_APELLIDO1, '') || NVL(E.ENT_NOMBRE1, '') || NVL(E.ENT_NOMBRE2, '') END PROVEEDOR
	    FROM GENERAL.GEN_PROVEEDORES P
	    JOIN GENERAL.GEN_ENTIDADES E ON E.ENT_ID = P.ENT_ID
	    JOIN EMPRESA EMP ON 1 = 1
	    WHERE
	      ($P{tipoProveedor} = 1 AND P.PAIS_ID = EMP.PAISID) OR ($P{tipoProveedor} = 2 AND P.PAIS_ID <> EMP.PAISID) OR ($P{tipoProveedor} = 0)
	),
	CARGOS AS (
	    SELECT
	        C.CGPR_ID DOCUMENTO_ID,
	        C.MON_ID MONEDA_ID,
	        PRO.ID CODIGO_PROVEEDOR,
	        PRO.PROVEEDOR,
	        C.TPDC_ID TIPO_DOCTO_ID,
	        TD.TPDC_DESCRIPCION TIPO_DOCTO,
	        NVL(C.CGPR_SERIE, '') || NVL(C.CGPR_CORRELATIVO, 0) DOCUMENTO,
	        NVL(C.CGPR_ING_BODEGA, '') INGRESO_ORDEN,
	        CUO.CTCG_FECHA FECHA_PAGO,
	        CUO.CTCG_ID CUOTA_ID,
	        CUO.CTCG_NUM_CUOTA NUM_CUOTA,
	        CASE WHEN 2 = 0 THEN C.CGPR_FECHA WHEN 2 = 1 THEN C.BIT_CREADO WHEN 2 = 2 THEN P.FECHA ELSE P.FECHA END FECHA,
	        ROUND((CUO.CTCG_VAL_CAPITAL + CUO.CTCG_IVA_CAPITAL) *
	        CASE WHEN C.TPDC_ID = TIPO_CARGODIF THEN
	            CASE WHEN 0 = 0 THEN
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
	        CASE WHEN 0 = 0 THEN
	            CASE WHEN C.MON_ID = EMP.MONEDAID THEN
	                1
	            ELSE
	                C.CGPR_TASA_CAMBIO * C.CGPR_TASA_EXT
	            END                            
	        ELSE
	            C.CGPR_TASA_EXT
	        END, 2) VALOR
	    FROM CXPDB.CXP_CARGOS_PROV C
	    JOIN CXPDB.CXP_TIP_DOCUMENTOS TD ON TD.TPDC_ID = C.TPDC_ID
	    JOIN EMPRESA EMP ON EMP.ID = C.EMP_ID
	    JOIN PROVEEDORES PRO ON PRO.ID = C.PRO_ID
	    LEFT JOIN POLIZAS P ON P.ID = C.ENPO_ID
	    JOIN CXPDB.CXP_CUO_CARGOS CUO ON CUO.CGPR_ID = C.CGPR_ID
	    WHERE
	        C.EMP_ID = $P{empresaId}
	        AND ((INSTR($P{listaTipoDocumentos}, ',' || C.TPDC_ID || ',') = $P{incluyeTipoDocumentos}) OR ($P{listaTipoDocumentos} IS NULL))
	        AND ((INSTR($P{listaProveedores}, ',' || PRO.ID || ',') = $P{incluyeProveedores}) OR ($P{listaProveedores} IS NULL))
	        AND (($P{tipoFecha} = 0 AND C.CGPR_FECHA <= TO_DATE($P{fecha}, 'DD/MM/YYYY')) OR ($P{tipoFecha} = 1 AND TRUNC(C.BIT_CREADO) <= TO_DATE($P{fecha}, 'DD/MM/YYYY')) OR ($P{tipoFecha} = 2 AND P.FECHA <= TO_DATE($P{fecha}, 'DD/MM/YYYY')))
	),
	ABONOS AS (
	    SELECT 
	        A.ENAB_ID DOCUMENTO_ID,
	        A.MON_ID MONEDA_ID,
	        PRO.ID CODIGO_PROVEEDOR,
	        PRO.PROVEEDOR,
	        A.TPDC_ID TIPO_DOCTO_ID,
	        TD.TPDC_DESCRIPCION TIPO_DOCTO,
	        NVL(A.ENAB_SERIE, '') || NVL(A.ENAB_CORRELATIVO, 0) DOCUMENTO,
			'' INGRESO_ORDEN,
	        PA.DTPA_ID PAGO_ID,
	        PA.CTCG_ID CUOTA_ID,
	        CASE WHEN 2 = 0 THEN A.ENAB_FECHA WHEN 2 = 1 THEN A.ENAB_FECHA_CREA WHEN 2 = 2 THEN P.FECHA ELSE P.FECHA END FECHA,
	        CASE WHEN 0 = 0 THEN
	            PA.DTPA_VAL_PAGADO
	        ELSE
	            PA.DTPA_VAL_PAGADO_EXT
	        END VALOR
	    FROM CXPDB.CXP_ENC_ABONOS A
	    JOIN CXPDB.CXP_TIP_DOCUMENTOS TD ON TD.TPDC_ID = A.TPDC_ID
	    JOIN EMPRESA EMP ON EMP.ID = A.EMP_ID
	    JOIN PROVEEDORES PRO ON PRO.ID = A.PRO_ID
	    JOIN CXPDB.CXP_DET_PAG_ABONOS PA ON PA.ENAB_ID = A.ENAB_ID
	    LEFT JOIN POLIZAS P ON P.ID = A.ENPO_ID
	    WHERE
	        A.EMP_ID = $P{empresaId}
	        AND ((INSTR($P{listaTipoDocumentos}, ',' || A.TPDC_ID || ',') = $P{incluyeTipoDocumentos}) OR ($P{listaTipoDocumentos} IS NULL))
	        AND ((INSTR($P{listaProveedores}, ',' || PRO.ID || ',') = $P{incluyeProveedores}) OR ($P{listaProveedores} IS NULL))
	        AND (($P{tipoFecha} = 0 AND A.ENAB_FECHA <= TO_DATE($P{fecha}, 'DD/MM/YYYY')) OR ($P{tipoFecha} = 1 AND TRUNC(A.ENAB_FECHA_CREA) <= TO_DATE($P{fecha}, 'DD/MM/YYYY')) OR ($P{tipoFecha} = 2 AND P.FECHA <= TO_DATE($P{fecha}, 'DD/MM/YYYY')))
	        AND A.ENAB_APLICADO = 1
	        AND A.ENAB_ANULADO = 0
	)
	SELECT
	    C.CODIGO_PROVEEDOR,
	    C.PROVEEDOR,
	    C.DOCUMENTO_ID,
	    C.DOCUMENTO,
	    C.FECHA,
	    C.MONEDA_ID,
	    C.INGRESO_ORDEN,
	    C.TIPO_DOCTO_ID,
	    C.TIPO_DOCTO,
	    C.FECHA_PAGO,
	    C.FECHA_PAGO - TO_DATE($P{fecha}, 'DD/MM/YYYY') DIAS,
	    C.CUOTA_ID,
	    MAX(C.VALOR) VALOR,
	    SUM(NVL(-A.VALOR, 0)) PAGADO,
	    0 DEBITOS
	FROM CARGOS C
	LEFT JOIN ABONOS A ON A.CUOTA_ID = C.CUOTA_ID
	GROUP BY C.CODIGO_PROVEEDOR, C.PROVEEDOR, C.DOCUMENTO_ID, C.DOCUMENTO, C.FECHA, C.MONEDA_ID, C.INGRESO_ORDEN, C.FECHA_PAGO, C.CUOTA_ID, C.TIPO_DOCTO_ID, C.TIPO_DOCTO
	UNION ALL
	SELECT
	    A.CODIGO_PROVEEDOR,
	    A.PROVEEDOR,
	    A.DOCUMENTO_ID,
	    A.DOCUMENTO,
	    A.FECHA,
	    A.MONEDA_ID,
	    A.INGRESO_ORDEN,
	    A.TIPO_DOCTO_ID,
	    A.TIPO_DOCTO,
	    NULL FECHA_PAGO,
		NULL DIAS,
	    NULL CUOTA_ID,
	    0 VALOR,
	    0 PAGADO,
	    SUM(NVL(A.VALOR, 0)) DEBITOS
	FROM ABONOS A
	LEFT JOIN CARGOS C ON C.CUOTA_ID = A.CUOTA_ID
	WHERE
	    C.CUOTA_ID IS NULL AND A.CUOTA_ID IS NOT NULL
	GROUP BY A.CODIGO_PROVEEDOR, A.PROVEEDOR, A.DOCUMENTO_ID, A.DOCUMENTO, A.FECHA, A.MONEDA_ID, A.INGRESO_ORDEN, A.TIPO_DOCTO_ID, A.TIPO_DOCTO
	UNION ALL
	SELECT
	    D.CODIGO_PROVEEDOR,
	    D.PROVEEDOR,
	    D.DOCUMENTO_ID,
	    D.DOCUMENTO,
	    D.FECHA,
	    D.MONEDA_ID,
	    D.INGRESO_ORDEN,
	    D.TIPO_DOCTO_ID,
	    D.TIPO_DOCTO,
	    NULL FECHA_PAGO,
		NULL DIAS,
	    NULL CUOTA_ID,
	    0 VALOR,
	    0 PAGADO,
	    SUM(NVL(D.VALOR, 0)) DEBITOS
	FROM ABONOS D
	WHERE
	    D.CUOTA_ID IS NULL
	GROUP BY D.CODIGO_PROVEEDOR, D.PROVEEDOR, D.DOCUMENTO_ID, D.DOCUMENTO, D.FECHA, D.MONEDA_ID, D.INGRESO_ORDEN, D.TIPO_DOCTO_ID, D.TIPO_DOCTO
) E
GROUP BY E.CODIGO_PROVEEDOR, E.PROVEEDOR, E.TIPO_DOCTO_ID || '-' || E.TIPO_DOCTO, E.INGRESO_ORDEN, E.DOCUMENTO, E.FECHA
HAVING ROUND(SUM(VALOR) + SUM(PAGADO) + SUM(DEBITOS), 2) <> 0
ORDER BY E.CODIGO_PROVEEDOR