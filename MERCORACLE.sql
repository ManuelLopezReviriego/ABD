--1.
--  a) Cada empleado utilizará un usuario de Oracle DISTINTO para conectarse a la base de datos. Modificar el modelo (si es necesario) para
--    almacenar dicho usuario.

DESC EMPLEADO; -- Ya existe un campo denominado USUARIO pero no es único, así que añadimos la restricción de unicidad sobre ese campo.

ALTER TABLE EMPLEADO
ADD CONSTRAINT EMPLEADO_USUARIO_UNIQUE UNIQUE(USUARIO);

--  b) Crear un role para las categorías de empleado: Director, Supervisor y Cajero-Reponedor. Los roles se llamarán R_DIRECTOR, R_SUPERVISOR, R_CAJERO.
-- Desde SYSTEM:
CREATE ROLE R_DIRECTOR;
CREATE ROLE R_SUPERVISOR;
CREATE ROLE R_CAJERO;


-- 2.
--   a) Crear una tabla denominada REVISION con la fecha, código de barras del producto e id del pasillo.
DESC REVISION;

--   b) Procedimiento P_REVISA que insertará en REVISION aquellos productos para los que SABEMOS su temperatura
--      de conservación y que NO cumplen que:
--        i) Teniendo una temperatura menor de 0ºC no se encuentran en Congelados.
--       ii) Teniendo una temperatura entre 0ºC y 6ºC no se encuentran en Refrigerados.

SELECT CODIGO_BARRAS, pas.DESCRIPCION, TEMPERATURA FROM PRODUCTO pro
JOIN PASILLO pas ON PASILLO = ID
WHERE TEMPERATURA IS NOT NULL;

CREATE OR REPLACE PROCEDURE P_REVISA IS
CURSOR C_PRODUCTOS IS SELECT CODIGO_BARRAS, pas.DESCRIPCION, pro.PASILLO, TEMPERATURA FROM PRODUCTO pro
                      JOIN PASILLO pas ON PASILLO = ID
                      WHERE TEMPERATURA IS NOT NULL;
BEGIN
    FOR VAR_PRODUCTO IN C_PRODUCTOS
    LOOP
        IF VAR_PRODUCTO.TEMPERATURA < 0 AND UPPER(VAR_PRODUCTO.DESCRIPCION) != 'CONGELADOS' THEN
            DBMS_OUTPUT.PUT_LINE(VAR_PRODUCTO.CODIGO_BARRAS || ' debería estar en Congelados pero está en ' || VAR_PRODUCTO.DESCRIPCION);
            INSERT INTO REVISION VALUES (SYSDATE, VAR_PRODUCTO.CODIGO_BARRAS, VAR_PRODUCTO.PASILLO);
        ELSIF (VAR_PRODUCTO.TEMPERATURA BETWEEN 0 AND 6) AND (UPPER(VAR_PRODUCTO.DESCRIPCION) != 'REFRIGERADOS') THEN
            DBMS_OUTPUT.PUT_LINE(VAR_PRODUCTO.CODIGO_BARRAS || ' debería estar en Refrigerados pero está en ' || VAR_PRODUCTO.DESCRIPCION);
            INSERT INTO REVISION VALUES (SYSDATE, VAR_PRODUCTO.CODIGO_BARRAS, VAR_PRODUCTO.PASILLO);
        END IF;
    END LOOP;
END;
/

--   c) Crear vista denominada V_REVISION_HOY con los datos de REVISION correspondientes al día de hoy.
CREATE OR REPLACE VIEW V_REVISION_HOY AS SELECT * FROM REVISION WHERE TRUNC(FECHA) = TRUNC(SYSDATE);

--SELECT * FROM REVISION;
--SELECT * FROM V_REVISION_HOY;

--   d) Otorgar permiso a R_CAJERO para seleccionar V_REVISION_HOY.
GRANT SELECT ON V_REVISION_HOY TO R_CAJERO;

--   e) Dar permiso de ejecución sobre el procedimiento P_REVISA a R_SUPERVISOR
GRANT EXECUTE ON P_REVISA TO R_SUPERVISOR;

-- 3. 
--   a) Crear vista V_IVA_TRIMESTRE con los atributos AÑO, TRIMESTRE (num entre 1 y 4), IVA_TOTAL (suma del IVA de los productos vendidos en ese trimestre).
CREATE OR REPLACE VIEW V_IVA_TRIMESTRE AS
(SELECT AÑO, TRIMESTRE, SUM(CANTIDAD*PRECIO_ACTUAL*IVA/100)"IVA_TOTAL" FROM 
    (SELECT ROUND(EXTRACT(YEAR FROM FECHA_PEDIDO)) "AÑO", ROUND(EXTRACT(MONTH FROM FECHA_PEDIDO)/3) "TRIMESTRE", IVA, PRECIO_ACTUAL, CANTIDAD FROM TICKET t
    JOIN DETALLE d ON t.ID = d.TICKET
    JOIN (SELECT CODIGO_BARRAS, IVA, PRECIO_ACTUAL FROM PRODUCTO p JOIN CATEGORIA c ON p.CATEGORIA = c.ID) iva_producto
    ON d.PRODUCTO = iva_producto.CODIGO_BARRAS)
GROUP BY AÑO, TRIMESTRE);

--   b) Dar permiso de selección a los supervisores y directores.
GRANT SELECT ON V_IVA_TRIMESTRE TO R_SUPERVISOR, R_DIRECTOR;

 
