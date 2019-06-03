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

/*
DELETE FROM REVISION;
EXECUTE P_REVISA;
SELECT R.CODIGO_BARRAS, P.TEMPERATURA, PA.DESCRIPCION FROM REVISION R
JOIN PRODUCTO P ON P.CODIGO_BARRAS = R.CODIGO_BARRAS
JOIN PASILLO PA ON R.PASILLO = PA.ID;
*/

--   c) Crear vista denominada V_REVISION_HOY con los datos de REVISION correspondientes al día de hoy.
CREATE OR REPLACE VIEW V_REVISION_HOY AS SELECT * FROM REVISION WHERE TRUNC(FECHA) = TRUNC(SYSDATE);

/*
SELECT * FROM REVISION;
SELECT * FROM V_REVISION_HOY;
*/

--   d) Otorgar permiso a R_CAJERO para seleccionar V_REVISION_HOY.
GRANT SELECT ON V_REVISION_HOY TO R_CAJERO;

--   e) Dar permiso de ejecución sobre el procedimiento P_REVISA a R_SUPERVISOR
GRANT EXECUTE ON P_REVISA TO R_SUPERVISOR;

--SELECT * FROM ROLE_TAB_PRIVS WHERE ROLE != 'R_DIRECTOR';



-- 3. 
--   a) Crear vista V_IVA_TRIMESTRE con los atributos AÑO, TRIMESTRE (num entre 1 y 4), IVA_TOTAL (suma del IVA de los productos vendidos en ese trimestre).
CREATE OR REPLACE VIEW V_IVA_PRODUCTO AS 
    SELECT CODIGO_BARRAS, IVA, PRECIO_ACTUAL
    FROM PRODUCTO p
    JOIN CATEGORIA c ON p.CATEGORIA = c.ID;

CREATE OR REPLACE VIEW V_VENTAS AS 
    SELECT ROUND(EXTRACT(YEAR FROM FECHA_PEDIDO)) "AÑO", ROUND(EXTRACT(MONTH FROM FECHA_PEDIDO)/3) "TRIMESTRE", IVA, PRECIO_ACTUAL, CANTIDAD
    FROM TICKET t
    JOIN DETALLE d ON t.ID = d.TICKET
    NATURAL JOIN V_IVA_PRODUCTO iva_producto;

CREATE OR REPLACE VIEW V_IVA_TRIMESTRE AS 
    SELECT AÑO, TRIMESTRE, SUM(CANTIDAD*PRECIO_ACTUAL*IVA/100)"IVA_TOTAL"
    FROM V_VENTAS
    GROUP BY AÑO, TRIMESTRE;

--   b) Dar permiso de selección a los supervisores y directores.
GRANT SELECT ON V_IVA_TRIMESTRE TO R_SUPERVISOR, R_DIRECTOR;



-- 4. Crear un paquete en PL/SQL de análisis de datos.
CREATE OR REPLACE PACKAGE PK_ANALISIS IS

TYPE T_PRODUCTO IS RECORD(CODIGO_BARRAS NUMBER, PRECIO_ACTUAL NUMBER, VENDIDAS NUMBER);
TYPE T_VALORES IS RECORD(MINIMO NUMBER, MAXIMO NUMBER, MEDIA NUMBER);
TYPE T_VAL_FLUCTUACION IS RECORD(PRODUCTO NUMBER, MINIMO NUMBER, MAXIMO NUMBER);

FUNCTION F_CALCULAR_ESTADISTICAS(PRODUCTO NUMBER, DESDE DATE, HASTA DATE) RETURN T_VALORES;
FUNCTION F_CALCULAR_FLUCTUACION(DESDE DATE, HASTA DATE) RETURN T_VAL_FLUCTUACION;
PROCEDURE P_REASIGNAR_METROS(DESDE DATE);
END;
/

CREATE OR REPLACE PACKAGE BODY PK_ANALISIS AS

--  a) La función F_Calcular_Estadisticas devolverá la media, mínimo y máximo precio de un producto determinado entre dos fechas.

    FUNCTION F_CALCULAR_ESTADISTICAS(PRODUCTO NUMBER, DESDE DATE, HASTA DATE) RETURN T_VALORES AS
        resultado    T_VALORES;
        error_fechas EXCEPTION;
    BEGIN
        IF DESDE > HASTA THEN
            RAISE error_fechas;
        END IF;
        SELECT MIN(PRECIO), MAX(PRECIO), AVG(PRECIO) INTO resultado FROM HISTORICO_PRECIO H WHERE H.PRODUCTO = PRODUCTO AND FECHA >= DESDE AND FECHA <= HASTA;
        DBMS_OUTPUT.PUT_LINE('ESTADISTICAS DEL PRODUCTO ' || PRODUCTO || ' DESDE ' || DESDE || ' HASTA ' || HASTA || ':');
        DBMS_OUTPUT.PUT_LINE(' -Precio minimo: ' || resultado.minimo);
        DBMS_OUTPUT.PUT_LINE(' -Precio maximo: ' || resultado.maximo);
        DBMS_OUTPUT.PUT_LINE(' -Precio medio: ' || resultado.media);
        RETURN resultado;
    END F_CALCULAR_ESTADISTICAS;

--  b) La función F_Calcular_Fluctuacion devolverá el mínimo y el máximo del producto que haya tenido mayor fluctuación porcentualmente
--     en su precio de todos entre dos fechas.
    
    FUNCTION F_CALCULAR_FLUCTUACION(DESDE DATE, HASTA DATE) RETURN T_VAL_FLUCTUACION AS
        CURSOR c_hist IS
            SELECT PRODUCTO, MAX(PRECIO)-MIN(PRECIO) "DIFF", MIN(PRECIO) "MIN_PRECIO"
            FROM HISTORICO_PRECIO
            WHERE FECHA >= DESDE AND FECHA <= HASTA
            GROUP BY PRODUCTO;
        producto_id NUMBER;
        max_diff NUMBER;
        resultado T_VAL_FLUCTUACION;
        error_fechas EXCEPTION;
    BEGIN
        IF DESDE > HASTA THEN
            RAISE error_fechas;
        END IF;
        
        FOR var_producto IN c_hist LOOP
            IF max_diff IS NULL OR var_producto.diff > max_diff THEN
                max_diff := var_producto.diff;
                producto_id := var_producto.producto;
            END IF;
        END LOOP;
        
        SELECT PRODUCTO, MIN(PRECIO), MAX(PRECIO) INTO resultado FROM HISTORICO_PRECIO WHERE PRODUCTO = producto_id GROUP BY PRODUCTO;
        DBMS_OUTPUT.PUT_LINE('EL PRODUCTO CUYO PRECIO HA FLUCTUADO MÁS DESDE ' || DESDE || ' HASTA ' || HASTA || ':');
        DBMS_OUTPUT.PUT_LINE(' -Codigo de barras: ' || resultado.producto);
        DBMS_OUTPUT.PUT_LINE(' -Precio minimo: ' || resultado.minimo);
        DBMS_OUTPUT.PUT_LINE(' -Precio maximo: ' || resultado.maximo);
        RETURN resultado;
    END F_CALCULAR_FLUCTUACION;
    
--  c) El procedimiento P_Reasignar_metros encuentra el producto más y menos vendido (en unidades) desde una fecha hasta hoy.
--     Extrae 0.5 metros lineales del de menor ventas y se lo asigna al de mayor ventas si es posible. Si hay varios productos
--     que se han vendido el mismo número de veces se obtendrá el de menor ventas y menos precio y se le asigna al de mayor ventas
--     y mayor precio.

    PROCEDURE P_REASIGNAR_METROS(DESDE DATE) AS
        CURSOR C_UNIDADES_VENDIDAS IS select p.codigo_barras, p.precio_actual, nvl(sum(d.cantidad),0) "VENDIDAS"
                                      from producto p
                                      left outer join detalle d on p.codigo_barras = d.producto
                                      left outer join ticket t on d.ticket = t.id 
                                      WHERE t.FECHA_PEDIDO >= DESDE
                                      group by p.codigo_barras, p.precio_actual;
        VAR_MAS_VENDIDO T_PRODUCTO := T_PRODUCTO(-1, 0, 0);
        VAR_MENOS_VENDIDO T_PRODUCTO := T_PRODUCTO(-1, 0, 0);
        VAR_METROS_LINEALES NUMBER;
    BEGIN
        FOR VAR_PRODUCTO IN C_UNIDADES_VENDIDAS
        LOOP
            IF VAR_MAS_VENDIDO.CODIGO_BARRAS = -1
               OR VAR_MAS_VENDIDO.VENDIDAS < VAR_PRODUCTO.VENDIDAS
               OR (VAR_MAS_VENDIDO.VENDIDAS = VAR_PRODUCTO.VENDIDAS AND
                   VAR_MAS_VENDIDO.PRECIO_ACTUAL < VAR_PRODUCTO.PRECIO_ACTUAL)
            THEN
                VAR_MAS_VENDIDO := T_PRODUCTO(VAR_PRODUCTO.CODIGO_BARRAS,
                                              VAR_PRODUCTO.PRECIO_ACTUAL,
                                              VAR_PRODUCTO.VENDIDAS);
            END IF;

            IF VAR_MENOS_VENDIDO.CODIGO_BARRAS = -1
               OR VAR_MENOS_VENDIDO.VENDIDAS > VAR_PRODUCTO.VENDIDAS
               OR (VAR_MENOS_VENDIDO.VENDIDAS = VAR_PRODUCTO.VENDIDAS AND VAR_MENOS_VENDIDO.PRECIO_ACTUAL < VAR_PRODUCTO.PRECIO_ACTUAL)
            THEN
                VAR_MENOS_VENDIDO := T_PRODUCTO(VAR_PRODUCTO.CODIGO_BARRAS,
                                                VAR_PRODUCTO.PRECIO_ACTUAL,
                                                VAR_PRODUCTO.VENDIDAS);
            END IF;
        END LOOP;
        
        SELECT METROS_LINEALES INTO VAR_METROS_LINEALES FROM PRODUCTO WHERE CODIGO_BARRAS = VAR_MENOS_VENDIDO.CODIGO_BARRAS;
        IF VAR_METROS_LINEALES > 0.5 THEN
            DBMS_OUTPUT.PUT_LINE('Se han asignado 0.5 metros lineales más a ' || VAR_MAS_VENDIDO.CODIGO_BARRAS);
            DBMS_OUTPUT.PUT_LINE('Se han retirado 0.5 metros lineales a ' || VAR_MENOS_VENDIDO.CODIGO_BARRAS);
            UPDATE PRODUCTO SET METROS_LINEALES = METROS_LINEALES - 0.5 WHERE CODIGO_BARRAS = VAR_MENOS_VENDIDO.CODIGO_BARRAS;
            UPDATE PRODUCTO SET METROS_LINEALES = METROS_LINEALES + 0.5 WHERE CODIGO_BARRAS = VAR_MAS_VENDIDO.CODIGO_BARRAS;
        ELSE
            DBMS_OUTPUT.PUT_LINE('ERROR: El menos vendido tiene asignado menos de 0.5 metros lineales');
        END IF;
    END;
END;
/

--   d) Crear un TRIGGER que cada vez que se modifique el precio de un producto almacene el precio anterior en HISTORICO_PRECIO,
--      poniendo la fecha a sysdate - 1 (se supone que el atributo PRECIO de HISTORICO_PRECIO indica la fecha hasta la que es válido
--      el precio del producto).
CREATE OR REPLACE TRIGGER TR_PRECIO_HISTORICO
AFTER UPDATE OF PRECIO_ACTUAL ON PRODUCTO
FOR EACH ROW
BEGIN
    INSERT INTO HISTORICO_PRECIO VALUES (:old.codigo_barras, sysdate-1, :old.precio_actual);
END;
/

/*
UPDATE PRODUCTO
    SET PRECIO_ACTUAL = PRECIO_ACTUAL*0.5
    WHERE UPPER(DESCRIPCION) = 'CERVEZA SAN MIGUEL';
    
SELECT * FROM PRODUCTO WHERE UPPER(DESCRIPCION) = 'CERVEZA SAN MIGUEL';

SELECT * FROM HISTORICO_PRECIO;
*/

   
-- 5. 
--   a) Modificar la tabla Ticket con el campo Total de tipo number. Crear un paquete en PL/SQL de gestión de puntos de clientes fidelizados. 
ALTER TABLE TICKET
ADD (TOTAL NUMBER);

--   b) El procedimiento P_Calcular_Puntos, tomará el ID de un ticket y un número de cliente fidelizado y calculará los puntos correspondientes
--      a la compra (un punto por cada euro, pero usando la función TRUNC en el redondeo).
--      El procedimiento siempre calculará el precio total de toda la compra y lo almacenará en el campo Total.
--      Además, si el cliente existe (puede ser nulo o no estar en la tabla), actualizará el atributo Puntos_acumulados del cliente fidelizado.

CREATE OR REPLACE PROCEDURE P_CALCULAR_PUNTOS(ID_TICKET NUMBER, ID_CLIENTE_FIDELIZADO VARCHAR2) IS
TYPE T_TICKET IS RECORD (ID NUMBER, TOTAL NUMBER);
VAR_TICKET T_TICKET;
VAR_PTOS NUMBER;
BEGIN
    BEGIN
        SELECT d.TICKET, SUM(d.CANTIDAD * p.PRECIO_ACTUAL) "TOTAL" INTO VAR_TICKET FROM DETALLE d
            JOIN PRODUCTO p ON d.PRODUCTO = p.CODIGO_BARRAS
            WHERE d.TICKET = ID_TICKET
            GROUP BY d.TICKET;
        VAR_PTOS := TRUNC(VAR_TICKET.TOTAL);
        UPDATE TICKET SET TOTAL = TICKET.TOTAL WHERE ID = ID_TICKET;
        BEGIN
            UPDATE FIDELIZADO SET PUNTOS_ACUMULADOS = PUNTOS_ACUMULADOS + VAR_PTOS WHERE DNI = ID_CLIENTE_FIDELIZADO;
            DBMS_OUTPUT.PUT_LINE('ACTUALIZACION DE PUNTOS DE UN CLIENTE FIDELIZADO:');
            DBMS_OUTPUT.PUT_LINE(' - Incremento de puntos: ' || VAR_PTOS);
        EXCEPTION 
            WHEN NO_DATA_FOUND THEN
                DBMS_OUTPUT.PUT_LINE('WARNING: Ticket no tiene asociado ningun cliente fidelizado o este no ha sido encontrado');
        END;
    EXCEPTION 
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('ERROR: Ticket no encontrado');
    END;
END;
/

/*
SELECT * FROM FIDELIZADO WHERE DNI = '78678644';
EXECUTE P_CALCULAR_PUNTOS(2, '78678644');
*/

--   c) El procedimiento P_Aplicar_puntos tomará el ID de un ticket y un número de cliente fidelizado. Cada punto_acumulado es un céntimo de
--      descuento. Calcular el descuento teniendo en cuenta que no puede ser mayor que el precio total y actualizar el precio total y los
--      puntos acumulados. Por ejemplo, si el precio total es 40 y tiene 90 puntos, el nuevo precio es  40-0,9=39,1 y los puntos pasan a ser cero.
--      Si el precio es 10 y tiene 1500 puntos, el nuevo precio es 0 y le quedan 500 puntos.

CREATE OR REPLACE VIEW DESCUENTO_MAXIMO_FIDELIZADO AS
    SELECT NUM_CLIENTE, PUNTOS_ACUMULADOS/100 "DESCUENTO_MAXIMO" FROM FIDELIZADO;

CREATE OR REPLACE PROCEDURE P_APLICAR_PUNTOS(ID_TICKET NUMBER, ID_CLIENTE_FIDELIZADO NUMBER) IS
VAR_TOTAL_TICKET NUMBER;
VAR_DESCUENTO NUMBER;
BEGIN
    SELECT TOTAL            INTO VAR_TOTAL_TICKET FROM TICKET WHERE ID = ID_TICKET;
    SELECT DESCUENTO_MAXIMO INTO VAR_DESCUENTO FROM DESCUENTO_MAXIMO_FIDELIZADO WHERE NUM_CLIENTE = ID_CLIENTE_FIDELIZADO;
    
    IF VAR_TOTAL_TICKET >= VAR_DESCUENTO THEN
        UPDATE TICKET     SET TOTAL = VAR_TOTAL_TICKET - VAR_DESCUENTO WHERE ID = ID_TICKET;
        UPDATE FIDELIZADO SET PUNTOS_ACUMULADOS = 0                    WHERE NUM_CLIENTE = ID_CLIENTE_FIDELIZADO;
    ELSE
        UPDATE TICKET     SET TOTAL = 0                                                    WHERE ID = ID_TICKET;
        UPDATE FIDELIZADO SET PUNTOS_ACUMULADOS = PUNTOS_ACUMULADOS - VAR_TOTAL_TICKET*100 WHERE NUM_CLIENTE = ID_CLIENTE_FIDELIZADO;
    END IF;
END;
/
     
-- 6. Crear un paquete en PL/SQL de gestión de empleados que incluya las operaciones para crear, borrar y modificar los datos de un empleado. 
/* NOTA 1: AL FINAL TERMINE HICIENDO BORRON Y CUENTA NUEVA CON ESTE APARTADO AL COMPLETO PORQUE TENIA DEMASIADOS ERRORES.*/
/* NOTA 2: NO HE PROBADO LOS METODOS PERO DEBERIAN FUNCIONAR CORRECTAMENTE */

-- Definicion del paquete
create or replace PACKAGE MERCORACLE.PK_EMPLEADO IS
    PROCEDURE SET_NOMBRE(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE,
                         E_NOMBRE MERCORACLE.EMPLEADO.NOMBRE%TYPE);
                         
    PROCEDURE SET_PRIMER_APELLIDO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE,
                                  E_APELLIDO MERCORACLE.EMPLEADO.APELLIDO1%TYPE);
                                  
    PROCEDURE SET_SEGUNDO_APELLIDO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE,
                                   E_APELLIDO MERCORACLE.EMPLEADO.APELLIDO2%TYPE);
    
    PROCEDURE SET_EMAIL(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE,
                        E_EMAIL MERCORACLE.EMPLEADO.EMAIL%TYPE);
                        
    PROCEDURE SET_TELEFONO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE,
                           E_TELEFONO MERCORACLE.EMPLEADO.TELEFONO%TYPE);
    
    PROCEDURE SET_DOMICILIO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE,
                            E_NUEVO_DOMICILIO MERCORACLE.EMPLEADO.DOMICILIO%TYPE,
                            E_NUEVO_COD_POSTAL NUMBER);
                            
    PROCEDURE PAGAR_NOMINA(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE, IMPORTE_BRUTO NUMBER, IMPORTE_NETO NUMBER);
    
    PROCEDURE REPONER_PASILLO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE, N_PASILLO NUMBER);
    PROCEDURE DEJAR_DE_REPONER_PASILLO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE, N_PASILLO NUMBER);
    
    PROCEDURE SUPERVISAR_EQUIPO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE, ID_EQUIPO NUMBER);
    PROCEDURE DEJAR_DE_SUPERVISAR_EQUIPO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE, ID_EQUIPO NUMBER);
    
    
    PROCEDURE ASIGNAR_CUENTA(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE,
                             NOMBRE_USUARIO MERCORACLE.EMPLEADO.USUARIO%TYPE,
                             CLAVE VARCHAR2,
                             ESPACIO_TABLAS VARCHAR2,
                             CUOTA VARCHAR2);
END;
/

-- Implementacion del paquete
create or replace PACKAGE BODY MERCORACLE.PK_EMPLEADO IS

    -- Actualiza el nombre del empleado con el DNI dado
    
    PROCEDURE SET_NOMBRE(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE, E_NOMBRE MERCORACLE.EMPLEADO.NOMBRE%TYPE) IS
    BEGIN
        UPDATE MERCORACLE.EMPLEADO SET NOMBRE = E_NOMBRE WHERE UPPER(DNI) = UPPER(E_DNI);
        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Error en PK_EMPLEADO.SET_NOMBRE: No existe ningun empleado con DNI ' || E_DNI);
    END SET_NOMBRE;

    -------------------------------------------------------------------------------------------------------------

    -- Actualiza el primer apellido del empleado con el DNI dado

    PROCEDURE SET_PRIMER_APELLIDO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE, E_APELLIDO MERCORACLE.EMPLEADO.APELLIDO1%TYPE) IS
    BEGIN
        UPDATE MERCORACLE.EMPLEADO SET APELLIDO1 = E_APELLIDO WHERE UPPER(DNI) = UPPER(E_DNI);
        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Error en PK_EMPLEADO.SET_PRIMER_APELLIDO: No existe ningun empleado con DNI ' || E_DNI);
    END SET_PRIMER_APELLIDO;

    -------------------------------------------------------------------------------------------------------------

    -- Actualiza el segundo apellido del empleado con el DNI dado

    PROCEDURE SET_SEGUNDO_APELLIDO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE, E_APELLIDO MERCORACLE.EMPLEADO.APELLIDO2%TYPE) IS
    BEGIN
        UPDATE MERCORACLE.EMPLEADO SET APELLIDO2 = E_APELLIDO WHERE UPPER(DNI) = UPPER(E_DNI);
        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Error en PK_EMPLEADO.SET_SEGUNDO_APELLIDO: No existe ningun empleado con DNI ' || E_DNI);
    END SET_SEGUNDO_APELLIDO;

    -------------------------------------------------------------------------------------------------------------

    -- Actualiza el email del empleado con el DNI dado

    PROCEDURE SET_EMAIL(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE,
                        E_EMAIL MERCORACLE.EMPLEADO.EMAIL%TYPE) IS
    BEGIN
        UPDATE MERCORACLE.EMPLEADO SET EMAIL = E_EMAIL WHERE UPPER(DNI) = UPPER(E_DNI);
        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Error en PK_EMPLEADO.SET_EMAIL: No existe ningun empleado con DNI ' || E_DNI);
    END SET_EMAIL;

    -------------------------------------------------------------------------------------------------------------
    
    -- Actualiza el telefono del empleado con el DNI dado

    PROCEDURE SET_TELEFONO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE,
                           E_TELEFONO MERCORACLE.EMPLEADO.TELEFONO%TYPE) IS
    BEGIN
        UPDATE MERCORACLE.EMPLEADO SET TELEFONO = E_TELEFONO WHERE UPPER(DNI) = UPPER(E_DNI);
        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Error en PK_EMPLEADO.SET_TELEFONO: No existe ningun empleado con DNI ' || E_DNI);
    END SET_TELEFONO;

    -------------------------------------------------------------------------------------------------------------
    
    -- Actualiza el domicilio del empleado con el DNI dado

    PROCEDURE SET_DOMICILIO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE,
                            E_NUEVO_DOMICILIO MERCORACLE.EMPLEADO.DOMICILIO%TYPE,
                            E_NUEVO_COD_POSTAL NUMBER) IS
    BEGIN
        UPDATE MERCORACLE.EMPLEADO SET DOMICILIO = E_NUEVO_DOMICILIO WHERE UPPER(DNI) = UPPER(E_DNI);
        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Error en PK_EMPLEADO.SET_DOMICILIO: No existe ningun empleado con DNI ' || E_DNI);
    END SET_DOMICILIO;

    -------------------------------------------------------------------------------------------------------------
    
    -- Pagar la nomina al empleado con el DNI dado

    PROCEDURE PAGAR_NOMINA(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE, IMPORTE_BRUTO NUMBER, IMPORTE_NETO NUMBER) IS
        ID_EMPLEADO NUMBER;
    BEGIN
        SELECT ID INTO ID_EMPLEADO FROM MERCORACLE.EMPLEADO WHERE UPPER(DNI) = UPPER(E_DNI);
        INSERT INTO MERCORACLE.NOMINA(FECHA_EMISION, IMPORTE_NETO, EMPLEADO, IMPORTE_BRUTO)
               VALUES (SYSDATE, IMPORTE_NETO, ID_EMPLEADO, IMPORTE_BRUTO);
        COMMIT;
    END PAGAR_NOMINA;

    -------------------------------------------------------------------------------------------------------------
    
    -- Asignar un pasillo para reponer al empleado dado

    PROCEDURE REPONER_PASILLO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE, N_PASILLO NUMBER) IS
        ID_EMPLEADO NUMBER;
    BEGIN
        SELECT ID INTO ID_EMPLEADO FROM MERCORACLE.EMPLEADO WHERE UPPER(DNI) = UPPER(E_DNI);
        INSERT INTO MERCORACLE.REPONE VALUES(ID_EMPLEADO, N_PASILLO);
        COMMIT;
    END REPONER_PASILLO;

    -------------------------------------------------------------------------------------------------------------
    
    -- El empleado dado dejara de reponer en el pasillo en cuestion

    PROCEDURE DEJAR_DE_REPONER_PASILLO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE, N_PASILLO NUMBER) IS
        ID_EMPLEADO NUMBER;
    BEGIN
        SELECT ID INTO ID_EMPLEADO FROM MERCORACLE.EMPLEADO WHERE UPPER(DNI) = UPPER(E_DNI);
        DELETE FROM MERCORACLE.REPONE WHERE EMPLEADO = ID_EMPLEADO AND PASILLO = N_PASILLO;
        COMMIT;
    END DEJAR_DE_REPONER_PASILLO;

    -------------------------------------------------------------------------------------------------------------
    
    -- Se le asigna la supervision de un equipo a un empleado dado

    PROCEDURE SUPERVISAR_EQUIPO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE, ID_EQUIPO NUMBER) IS
        ID_EMPLEADO NUMBER;
    BEGIN
        SELECT ID INTO ID_EMPLEADO FROM MERCORACLE.EMPLEADO WHERE UPPER(DNI) = UPPER(E_DNI);
        INSERT INTO MERCORACLE.SUPERVISA VALUES(ID_EMPLEADO, ID_EQUIPO);
        COMMIT;
    END SUPERVISAR_EQUIPO;

    -------------------------------------------------------------------------------------------------------------
    
    -- Se elimina la supervision de un equipo por parte de un empleado dado

    PROCEDURE DEJAR_DE_SUPERVISAR_EQUIPO(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE, ID_EQUIPO NUMBER) IS
        ID_EMPLEADO NUMBER;
    BEGIN
        SELECT ID INTO ID_EMPLEADO FROM MERCORACLE.EMPLEADO WHERE UPPER(DNI) = UPPER(E_DNI);
        DELETE FROM MERCORACLE.SUPERVISA WHERE EMPLEADO = ID_EMPLEADO AND EQUIPO = ID_EQUIPO;
        COMMIT;
    END DEJAR_DE_SUPERVISAR_EQUIPO;

    -------------------------------------------------------------------------------------------------------------
    
    -- Crea una cuenta para el usuario dado

    PROCEDURE ASIGNAR_CUENTA(E_DNI MERCORACLE.EMPLEADO.DNI%TYPE,
                             NOMBRE_USUARIO MERCORACLE.EMPLEADO.USUARIO%TYPE,
                             CLAVE VARCHAR2,
                             ESPACIO_TABLAS VARCHAR2,
                             CUOTA VARCHAR2) IS
                             
        SENT_CREAR_USUARIO VARCHAR2(100);
        SENT_GRANT_CONNECT VARCHAR2(100);
        SENT_ASIGNAR_ROL   VARCHAR2(100);
        EMP                MERCORACLE.EMPLEADO%ROWTYPE;
    BEGIN
        SENT_CREAR_USUARIO := 'CREATE USER ' || NOMBRE_USUARIO ||
                              ' IDENTIFIED BY "' || CLAVE || '"' ||
                              ' DEFAULT TABLESPACE ' || ESPACIO_TABLAS ||
                              ' QUOTA ' || CUOTA || ' ON ' || ESPACIO_TABLAS;
        SENT_GRANT_CONNECT := 'GRANT CONNECT TO ' || NOMBRE_USUARIO;
        
        DBMS_OUTPUT.PUT_LINE(SENT_CREAR_USUARIO);       
        EXECUTE IMMEDIATE SENT_CREAR_USUARIO;
        
        DBMS_OUTPUT.PUT_LINE(SENT_GRANT_CONNECT);
        EXECUTE IMMEDIATE SENT_GRANT_CONNECT;

        SELECT * INTO EMP FROM EMPLEADO WHERE UPPER(DNI) = UPPER(E_DNI);
        
        IF UPPER(EMP.CAT_EMPLEADO) = 'DIRECTOR' THEN
            SENT_ASIGNAR_ROL := 'GRANT ROLE R_DIRECTOR TO ' || EMP.USUARIO || ';';
            DBMS_OUTPUT.PUT_LINE(SENT_ASIGNAR_ROL);
            EXECUTE IMMEDIATE SENT_ASIGNAR_ROL;
        ELSIF UPPER(EMP.CAT_EMPLEADO) = 'SUPERVISOR' THEN
            SENT_ASIGNAR_ROL := 'GRANT ROLE R_SUPERVISOR TO ' || EMP.USUARIO || ';';
            DBMS_OUTPUT.PUT_LINE(SENT_ASIGNAR_ROL);
            EXECUTE IMMEDIATE SENT_ASIGNAR_ROL;
        ELSIF UPPER(EMP.CAT_EMPLEADO) = 'CAJERO-REPONEDOR' THEN
            SENT_ASIGNAR_ROL := 'GRANT ROLE R_CAJERO TO ' || EMP.USUARIO || ';';
            DBMS_OUTPUT.PUT_LINE(SENT_ASIGNAR_ROL);
            EXECUTE IMMEDIATE SENT_ASIGNAR_ROL;
        END IF;
        
        UPDATE MERCORACLE.EMPLEADO SET USUARIO = NOMBRE_USUARIO WHERE UPPER(DNI) = UPPER(E_DNI); 
        
        DBMS_OUTPUT.PUT_LINE('Usuario creado con exito');
    END ASIGNAR_CUENTA;

    -------------------------------------------------------------------------------------------------------------

END;
/
                        
--- 
                         
CREATE OR REPLACE PACKAGE PK_EMPLEADO IS
    /* CREACION DE EMPLEADOS Y CUENTAS */
    PROCEDURE CREAR_EMPLEADO (EMP EMPLEADO%ROWTYPE, CLAVE VARCHAR2);
    PROCEDURE ASIGNAR_CUENTA(DNI VARCHAR2, NOMBRE_USUARIO VARCHAR2,
                             CLAVE VARCHAR2,
                             ESPACIO_TABLAS VARCHAR2 DEFAULT 'MERCORACLE',
                             CUOTA NUMBER DEFAULT '10',
                             CUOTA_UNIDAD CHAR DEFAULT 'M');
    
    /* ACTUALIZACION DE INFORMACION */
    PROCEDURE SET_NOMBRE(DNI VARCHAR2, NOMBRE VARCHAR2);
    PROCEDURE SET_PRIMER_APELLIDO(DNI VARCHAR2, APELLIDO VARCHAR2);
    PROCEDURE SET_SEGUNDO_APELLIDO(DNI VARCHAR2, APELLIDO VARCHAR2);
    
    PROCEDURE SET_EMAIL(DNI VARCHAR2, EMAIL VARCHAR);
    PROCEDURE SET_TELEFONO(DNI VARCHAR2, TELEFONO VARCHAR);
    
    PROCEDURE SET_DOMICILIO(DNI VARCHAR2, NUEVO_DOMICILIO VARCHAR2, NUEVO_COD_POSTAL NUMBER);
    
    PROCEDURE SET_CATEGORIA(DNI VARCHAR2, NUEVA_CATEGORIA VARCHAR2);
    
    PROCEDURE PAGAR_NOMINA(DNI VARCHAR2, IMPORTE_BRUTO NUMBER, IMPORTE_NETO NUMBER);
    
    PROCEDURE REPONER_PASILLO(DNI VARCHAR2, PASILLO NUMBER);
    PROCEDURE DEJAR_DE_REPONER_PASILLO(DNI VARCHAR2, PASILLO NUMBER);
    
    PROCEDURE SUPERVISAR_EQUIPO(DNI VARCHAR2, ID_EQUIPO NUMBER);
    PROCEDURE DEJAR_DE_SUPERVISAR_EQUIPO(DNI VARCHAR2, ID_EQUIPO NUMBER);
    
    /* ELIMINAR INFORMACION */
    PROCEDURE ELIMINAR_EMPLEADO(DNI VARCHAR2, BORRAR_CUENTA BOOLEAN);
    
    /* BLOQUEAR Y DESBLOQUEAR */
    PROCEDURE BLOQUEAR_CUENTA(DNI VARCHAR2);
    PROCEDURE DESBLOQUEAR_CUENTA(DNI VARCHAR2);
    
    PROCEDURE BLOQUEAR_TODOS; -- excepto directivos
    PROCEDURE DESBLOQUEAR_TODOS;
    
    PROCEDURE P_EMPLEADO_DEL_AÑO;
END;
/

CREATE OR REPLACE PACKAGE BODY PK_EMPLEADO IS
    PROCEDURE CREAR_EMPLEADO (EMP EMPLEADO%ROWTYPE, CLAVE VARCHAR2) IS
        SENT_CREAR_USUARIO VARCHAR2(100); 
        SENT_ASIGNAR_ROL   VARCHAR2(100);
    BEGIN
        INSERT INTO EMPLEADO VALUES EMP;
        ASIGNAR_CUENTA(EMP.DNI, EMP.USUARIO, CLAVE);
    END CREAR_EMPLEADO;

    PROCEDURE SET_NOMBRE(DNI VARCHAR2, NOMBRE VARCHAR2) IS
    BEGIN
        UPDATE EMPLEADO E SET E.NOMBRE = TRIM(NOMBRE) WHERE E.DNI = DNI;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Error en PK_EMPLEADO.SET_NOMBRE: No existe ningun empleado con DNI ' || DNI);
    END SET_NOMBRE;

    PROCEDURE SET_PRIMER_APELLIDO(DNI VARCHAR2, APELLIDO VARCHAR2) IS
    BEGIN
        UPDATE EMPLEADO E SET E.APELLIDO1 = TRIM(APELLIDO) WHERE E.DNI = DNI;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Error en PK_EMPLEADO.SET_PRIMER_APELLIDO: No existe ningun empleado con DNI ' || DNI);
    END SET_PRIMER_APELLIDO;

    PROCEDURE SET_SEGUNDO_APELLIDO(DNI VARCHAR2, APELLIDO VARCHAR2) IS
    BEGIN
        UPDATE EMPLEADO E SET E.APELLIDO2 = TRIM(APELLIDO) WHERE E.DNI = DNI;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Error en PK_EMPLEADO.SET_SEGUNDO_APELLIDO: No existe ningun empleado con DNI ' || DNI);
    END SET_SEGUNDO_APELLIDO;

    PROCEDURE SET_EMAIL(DNI VARCHAR2, EMAIL VARCHAR) IS
    BEGIN
        UPDATE EMPLEADO E SET E.EMAIL = TRIM(EMAIL) WHERE E.DNI = DNI;
    END SET_EMAIL;

    PROCEDURE SET_TELEFONO(DNI VARCHAR2, TELEFONO VARCHAR) IS
    BEGIN
        UPDATE EMPLEADO E SET E.TELEFONO = TRIM(TELEFONO) WHERE E.DNI = DNI;
    END SET_TELEFONO;

    PROCEDURE SET_DOMICILIO(DNI VARCHAR2, NUEVO_DOMICILIO VARCHAR2, NUEVO_COD_POSTAL NUMBER) IS
    BEGIN
        UPDATE EMPLEADO E SET E.DOMICILIO = TRIM(NUEVO_DOMICILIO), E.CODIGO_POSTAL = TRIM(NUEVO_COD_POSTAL) WHERE E.DNI = DNI;
    END SET_DOMICILIO;

    PROCEDURE SET_CATEGORIA(DNI VARCHAR2, NUEVA_CATEGORIA VARCHAR2) IS
        USUARIO VARCHAR2(100);
        ANTIGUA_CATEGORIA VARCHAR2(100);
        SENT_ASIGNAR_ROL   VARCHAR2(100);
        SENT_ELIMINAR_ROL   VARCHAR2(100);
    BEGIN
        SELECT UPPER(E.CAT_EMPLEADO) INTO ANTIGUA_CATEGORIA FROM EMPLEADO E WHERE E.DNI = DNI;
        SELECT UPPER(E.USUARIO) INTO USUARIO FROM EMPLEADO E WHERE E.DNI = DNI;

        IF ANTIGUA_CATEGORIA != UPPER(NUEVA_CATEGORIA) THEN
            -- Eliminar roles de la categoria antigua
            IF ANTIGUA_CATEGORIA = 'DIRECTOR' THEN
                SENT_ELIMINAR_ROL := 'REVOKE R_DIRECTOR FROM ' || USUARIO || ';';
                EXECUTE IMMEDIATE SENT_ELIMINAR_ROL;
            ELSIF ANTIGUA_CATEGORIA = 'SUPERVISOR' THEN
                SENT_ELIMINAR_ROL := 'REVOKE R_SUPERVISOR FROM ' || USUARIO || ';';
                EXECUTE IMMEDIATE SENT_ELIMINAR_ROL;
            ELSIF ANTIGUA_CATEGORIA = 'CAJERO-REPONEDOR' THEN
                SENT_ELIMINAR_ROL := 'REVOKE R_CAJERO FROM ' || USUARIO || ';';
                EXECUTE IMMEDIATE SENT_ELIMINAR_ROL;
            END IF;

            -- Asignar roles de la nueva categoria
            IF UPPER(NUEVA_CATEGORIA) = 'DIRECTOR' THEN
                SENT_ASIGNAR_ROL := 'GRANT ROLE R_DIRECTOR TO ' || USUARIO || ';';
                DBMS_OUTPUT.PUT_LINE(SENT_ASIGNAR_ROL);
                EXECUTE IMMEDIATE SENT_ASIGNAR_ROL;
            ELSIF UPPER(NUEVA_CATEGORIA) = 'SUPERVISOR' THEN
                SENT_ASIGNAR_ROL := 'GRANT ROLE R_SUPERVISOR TO ' || USUARIO || ';';
                DBMS_OUTPUT.PUT_LINE(SENT_ASIGNAR_ROL);
                EXECUTE IMMEDIATE SENT_ASIGNAR_ROL;
            ELSIF UPPER(NUEVA_CATEGORIA) = 'CAJERO-REPONEDOR' THEN
                SENT_ASIGNAR_ROL := 'GRANT ROLE R_CAJERO TO ' || USUARIO || ';';
                DBMS_OUTPUT.PUT_LINE(SENT_ASIGNAR_ROL);
                EXECUTE IMMEDIATE SENT_ASIGNAR_ROL;
            END IF;
        END IF;
    END SET_CATEGORIA;

    PROCEDURE ASIGNAR_CUENTA(DNI VARCHAR2, NOMBRE_USUARIO VARCHAR2, CLAVE VARCHAR2, ESPACIO_TABLAS VARCHAR2, CUOTA NUMBER, CUOTA_UNIDAD CHAR) IS
        SENT_CREAR_USUARIO VARCHAR2(100); 
        SENT_ASIGNAR_ROL   VARCHAR2(100);
        EMP                EMPLEADO%ROWTYPE;
    BEGIN
        SENT_CREAR_USUARIO := 'CREATE USER ' || NOMBRE_USUARIO ||
                              ' IDENTIFIED BY ' || CLAVE ||
                              ' DEFAULT TABLESPACE ' || ESPACIO_TABLAS ||
                              ' QUOTA ' || CUOTA || CUOTA_UNIDAD || ' ON ' || ESPACIO_TABLAS ||
                              ';';
        DBMS_OUTPUT.PUT_LINE(SENT_CREAR_USUARIO);
        EXECUTE IMMEDIATE SENT_CREAR_USUARIO;

        SELECT * INTO EMP FROM EMPLEADO E WHERE E.DNI = DNI;
        
        IF UPPER(EMP.CAT_EMPLEADO) = 'DIRECTOR' THEN
            SENT_ASIGNAR_ROL := 'GRANT ROLE R_DIRECTOR TO ' || EMP.USUARIO || ';';
            DBMS_OUTPUT.PUT_LINE(SENT_ASIGNAR_ROL);
            EXECUTE IMMEDIATE SENT_ASIGNAR_ROL;
        ELSIF UPPER(EMP.CAT_EMPLEADO) = 'SUPERVISOR' THEN
            SENT_ASIGNAR_ROL := 'GRANT ROLE R_SUPERVISOR TO ' || EMP.USUARIO || ';';
            DBMS_OUTPUT.PUT_LINE(SENT_ASIGNAR_ROL);
            EXECUTE IMMEDIATE SENT_ASIGNAR_ROL;
        ELSIF UPPER(EMP.CAT_EMPLEADO) = 'CAJERO-REPONEDOR' THEN
            SENT_ASIGNAR_ROL := 'GRANT ROLE R_CAJERO TO ' || EMP.USUARIO || ';';
            DBMS_OUTPUT.PUT_LINE(SENT_ASIGNAR_ROL);
            EXECUTE IMMEDIATE SENT_ASIGNAR_ROL;
        END IF;
    END ASIGNAR_CUENTA;
    
    PROCEDURE PAGAR_NOMINA(DNI VARCHAR2, IMPORTE_BRUTO NUMBER, IMPORTE_NETO NUMBER) IS
        ID_EMPLEADO NUMBER;
    BEGIN
        SELECT ID INTO ID_EMPLEADO FROM EMPLEADO E WHERE E.DNI = DNI;
        INSERT INTO NOMINA(FECHA_EMISION, IMPORTE_NETO, EMPLEADO, IMPORTE_BRUTO) VALUES (SYSDATE, IMPORTE_NETO, ID_EMPLEADO, IMPORTE_BRUTO);
    END PAGAR_NOMINA;
    
    PROCEDURE REPONER_PASILLO(DNI VARCHAR2, PASILLO NUMBER) IS
        ID_EMPLEADO NUMBER;
    BEGIN
        SELECT ID INTO ID_EMPLEADO FROM EMPLEADO E WHERE E.DNI = DNI;
        INSERT INTO REPONE VALUES(ID_EMPLEADO, PASILLO);
    END REPONER_PASILLO;
    
    PROCEDURE DEJAR_DE_REPONER_PASILLO(DNI VARCHAR2, PASILLO NUMBER)  IS
        ID_EMPLEADO NUMBER;
    BEGIN
        SELECT ID INTO ID_EMPLEADO FROM EMPLEADO E WHERE E.DNI = DNI;
        DELETE FROM REPONE R WHERE R.EMPLEADO = ID_EMPLEADO AND R.PASILLO = PASILLO;
    END DEJAR_DE_REPONER_PASILLO;
    
    PROCEDURE SUPERVISAR_EQUIPO(DNI VARCHAR2, ID_EQUIPO NUMBER) IS
        ID_EMPLEADO NUMBER;
    BEGIN
        SELECT ID INTO ID_EMPLEADO FROM EMPLEADO E WHERE E.DNI = DNI;
        INSERT INTO SUPERVISA VALUES(ID_EMPLEADO, ID_EQUIPO);
    END SUPERVISAR_EQUIPO;
    
    PROCEDURE DEJAR_DE_SUPERVISAR_EQUIPO(DNI VARCHAR2, ID_EQUIPO NUMBER) IS
        ID_EMPLEADO NUMBER;
    BEGIN
        SELECT ID INTO ID_EMPLEADO FROM EMPLEADO E WHERE E.DNI = DNI;
        DELETE FROM SUPERVISA S WHERE S.EMPLEADO = ID_EMPLEADO AND S.EQUIPO = ID_EQUIPO;
    END DEJAR_DE_SUPERVISAR_EQUIPO;
    
    PROCEDURE ELIMINAR_EMPLEADO(DNI VARCHAR2, BORRAR_CUENTA BOOLEAN) IS
        SENT_BORRAR_CUENTA VARCHAR2(100);
        CUENTA VARCHAR2(100);
    BEGIN
        SELECT USUARIO INTO CUENTA FROM EMPLEADO E WHERE E.DNI = DNI;
        IF BORRAR_CUENTA AND CUENTA IS NOT NULL THEN
            SENT_BORRAR_CUENTA := 'DROP USER ' || CUENTA || ';';
            EXECUTE IMMEDIATE SENT_BORRAR_CUENTA;
        END IF;
        DELETE FROM EMPLEADO E WHERE E.DNI = DNI;
    END ELIMINAR_EMPLEADO;
    
    PROCEDURE BLOQUEAR_CUENTA(DNI VARCHAR2) IS
        CUENTA VARCHAR2(100);
        SENT_BLOQUEO VARCHAR2(100);
    BEGIN
        SELECT USUARIO INTO CUENTA FROM EMPLEADO E WHERE E.DNI = DNI;
        SENT_BLOQUEO := 'ALTER USER ' || CUENTA || ' ACCOUNT LOCK;';
        EXECUTE IMMEDIATE SENT_BLOQUEO;
    END BLOQUEAR_CUENTA;
    
    PROCEDURE DESBLOQUEAR_CUENTA(DNI VARCHAR2) IS
        CUENTA VARCHAR2(100);
        SENT_BLOQUEO VARCHAR2(100);
    BEGIN
        SELECT USUARIO INTO CUENTA FROM EMPLEADO E WHERE E.DNI = DNI;
        SENT_BLOQUEO := 'ALTER USER ' || CUENTA || ' ACCOUNT UNLOCK;';
        EXECUTE IMMEDIATE SENT_BLOQUEO;
    END DESBLOQUEAR_CUENTA;
    
    PROCEDURE BLOQUEAR_TODOS IS -- excepto directivos
        CURSOR C_EMPLEADOS_CON_CUENTA IS
            SELECT * FROM EMPLEADO WHERE USUARIO IS NOT NULL AND UPPER(CAT_EMPLEADO) != 'DIRECTIVO';
    BEGIN
        FOR EMP IN C_EMPLEADOS_CON_CUENTA LOOP
            BLOQUEAR_CUENTA(EMP.DNI);
        END LOOP;
    END BLOQUEAR_TODOS;
    
    PROCEDURE DESBLOQUEAR_TODOS IS
        CURSOR C_EMPLEADOS_CON_CUENTA IS
            SELECT * FROM EMPLEADO WHERE USUARIO IS NOT NULL AND UPPER(CAT_EMPLEADO) != 'DIRECTIVO';
    BEGIN
        FOR EMP IN C_EMPLEADOS_CON_CUENTA LOOP
            DESBLOQUEAR_CUENTA(EMP.DNI);
        END LOOP;
    END DESBLOQUEAR_TODOS;
    
    -- Habrá un procedimiento P_EmpleadoDelAño que aumentará el sueldo bruto en un 10% al empleado más eficiente en caja (que ha emitido un mayor número de tickets).
    PROCEDURE P_EMPLEADO_DEL_AÑO AS
    VAR_MAX_EMITIDOS NUMBER;
    VAR_EMPLEADO NUMBER;
    CURSOR C_NOMINAS(empleado_id number) IS SELECT * FROM NOMINA
                                            WHERE EXTRACT(YEAR FROM FECHA_EMISION) = EXTRACT(YEAR FROM SYSDATE)
                                                  AND EMPLEADO = (empleado_id);
    BEGIN
        SELECT MAX(EMITIDOS) INTO VAR_MAX_EMITIDOS FROM
            (SELECT EMPLEADO, COUNT(*) "EMITIDOS"
             FROM TICKET
             WHERE EXTRACT(YEAR FROM FECHA_PEDIDO) = EXTRACT(YEAR FROM SYSDATE) 
             GROUP BY EMPLEADO, EXTRACT(YEAR FROM FECHA_PEDIDO));
             
        SELECT EMPLEADO INTO VAR_EMPLEADO FROM (SELECT EMPLEADO
            FROM TICKET
            WHERE EXTRACT(YEAR FROM FECHA_PEDIDO) = EXTRACT(YEAR FROM SYSDATE)
            GROUP BY EMPLEADO, EXTRACT(YEAR FROM FECHA_PEDIDO)
            HAVING COUNT(*) = VAR_MAX_EMITIDOS)
        FETCH FIRST ROW ONLY;
        
        DBMS_OUTPUT.PUT_LINE('INFO: El empleado mas eficiente en caja el año ' || EXTRACT(YEAR FROM SYSDATE) || ' fue ' || VAR_EMPLEADO);
        
        -- en la tabla nomina?
        FOR VAR_NOMINA IN C_NOMINAS(VAR_EMPLEADO)
        LOOP
            UPDATE NOMINA SET IMPORTE_BRUTO = VAR_NOMINA.IMPORTE_BRUTO*1.1 WHERE FECHA_EMISION = VAR_NOMINA.FECHA_EMISION;
        END LOOP;
    END P_EMPLEADO_DEL_AÑO;
    
    -- PROCEDIMIENTOS PRIVADOS -------------------------------------------------

END;
/






     
-- 7.
--Escribir un trigger que al introducir un ticket (en realidad, el detalle del ticket) decremente convenientemente el atributo Exposición de dicho producto. 
--Si no fuese posible, debe evitarse la inserción de dicho detalle en el ticket.
create or replace TRIGGER tr_introducir_ticket
before insert on detalle for each row
declare
var_exposicion number;
error_cantidad_insuficiente exception;
begin     
    select exposicion into var_exposicion from producto where codigo_barras = :new.Producto;
    if var_exposicion < :new.Cantidad
    then
        raise error_cantidad_insuficiente;
    end if;
    update Producto set exposicion = var_exposicion - :new.Cantidad where codigo_barras = :new.Producto;
exception
    when error_cantidad_insuficiente then
        dbms_output.put_line('ERROR: Cantidad insuficiente en exposicion');
end tr_introducir_ticket;
                                    
/
create or replace TRIGGER Introducir_ticket
before insert on detalle for each row
declare
number1 number;
begin
    select exposicion into number1 from producto where codigo_barras = :new.Producto;
    if (:new.Cantidad > number1)
    then RAISE_APPLICATION_ERROR(-20005, 'No hay suficientes productos');
    else        
        update Producto set exposicion = exposicion - :new.Cantidad
        where codigo_barras = :new.Producto;
    end if;
end Introducir_ticket;
/
 
-- 8.Escribir un trigger que cuando se eliminen los datos de un cliente fidelizado se eliminen a su vez toda su información de fidelización 
-- y las entregas que tuviera pendientes en su caso.
create or replace TRIGGER Eliminar_fidelizado
before delete on fidelizado 
for each row 
DECLARE
    CURSOR C_ENTREGAS IS 
        SELECT ID FROM TICKET WHERE FIDELIZADO = :old.DNI;
begin
    FOR e_ticket IN C_ENTREGAS LOOP
        DELETE FROM ENTREGA WHERE TICKET = e_ticket.ID;
        DELETE FROM FACTURA WHERE ID = e_ticket.ID;
        UPDATE TICKET SET FIDELIZADO = NULL WHERE ID = e_ticket.ID;
    END LOOP;   
end Eliminar_fidelizado;
/     

     
-- 9. Crear un JOB que ejecute el procedimiento P_REVISA todos los días a las 07:00. Crear otro JOB que semanalmente (los sábados a las 22:00) 
--    llame a P_Reasignar_metros
BEGIN
DBMS_SCHEDULER.CREATE_JOB (
job_name => 'Job_Revisa_DIA',
job_type => 'STORED_PROCEDURE',
job_action => 'P_REVISA',
start_date => SYSDATE+1,
repeat_interval => 'FREQ=DAILY;BYHOUR=7',
end_date => null,
enabled => TRUE,
comments => 'Ejecuta el procedimiento P_REVISA todos los dias a las 07:00');
END;
/
     
BEGIN
DBMS_SCHEDULER.CREATE_JOB (
job_name => 'Job_Revisa_Semana',
job_type => 'STORED_PROCEDURE',
job_action => 'P_Reasignar_metros',
start_date => SYSDATE,
repeat_interval => 'FREQ=WEEKLY;BYDAY=SAT;BYHOUR=22',
end_date => '30/MAY/2020 20.00.00',
enabled => TRUE,
comments => 'Ejecuta el procedimiento P_Reasignar_metros todos los sabados a las 22:00'),
credential_name => 'PLANIFICADOR');
END;
/


-- El codigo que viene a continuacion es para introducir funcionalidades y otros elementos no exigidos explicitamente en el enunciado

-- A. Creación de secuencias para atributos auto-generados.
                                        
CREATE SEQUENCE SECUENCIA_ID_FACTURA;
CREATE SEQUENCE SECUENCIA_ID_TICKET;
CREATE SEQUENCE SECUENCIA_ID_EMPLEADO;
CREATE SEQUENCE SECUENCIA_NUMERO_TARJETA;
CREATE SEQUENCE SECUENCIA_ID_PROVEEDOR;
CREATE SEQUENCE SECUENCIA_ID_EQUIPO;
CREATE SEQUENCE SECUENCIA_ID_MOBILIARIO;
CREATE SEQUENCE SECUENCIA_ID_LOTE;
CREATE SEQUENCE SECUENCIA_ID_OFERTA;
CREATE SEQUENCE SECUENCIA_ID_PASILLO;
CREATE SEQUENCE SECUENCIA_ID_ENTREGA;
CREATE SEQUENCE SECUENCIA_ID_RETENCION;
CREATE SEQUENCE SECUENCIA_ID_CATEGORIA;
CREATE SEQUENCE SECUENCIA_ID_CAT_EMPLEADO;

ALTER TABLE FACTURA      MODIFY (ID DEFAULT SECUENCIA_ID_FACTURA.NEXTVAL);
ALTER TABLE TICKET       MODIFY (ID DEFAULT SECUENCIA_ID_TICKET.NEXTVAL);
ALTER TABLE EMPLEADO     MODIFY (ID DEFAULT SECUENCIA_ID_EMPLEADO.NEXTVAL);
ALTER TABLE FIDELIZADO   MODIFY (N_TARJETA DEFAULT SECUENCIA_NUMERO_TARJETA.NEXTVAL);
ALTER TABLE PROVEEDOR    MODIFY (ID DEFAULT SECUENCIA_ID_PROVEEDOR.NEXTVAL);
ALTER TABLE EQUIPO       MODIFY (ID DEFAULT SECUENCIA_ID_EQUIPO.NEXTVAL);
ALTER TABLE MOBILIARIO   MODIFY (ID DEFAULT SECUENCIA_ID_MOBILIARIO.NEXTVAL);
ALTER TABLE LOTE         MODIFY (ID DEFAULT SECUENCIA_ID_LOTE.NEXTVAL);
ALTER TABLE OFERTA       MODIFY (ID DEFAULT SECUENCIA_ID_OFERTA.NEXTVAL);
ALTER TABLE PASILLO      MODIFY (ID DEFAULT SECUENCIA_ID_PASILLO.NEXTVAL);
ALTER TABLE ENTREGA      MODIFY (ID DEFAULT SECUENCIA_ID_ENTREGA.NEXTVAL);
ALTER TABLE RETENCION    MODIFY (ID DEFAULT SECUENCIA_ID_RETENCION.NEXTVAL);
ALTER TABLE CATEGORIA    MODIFY (ID DEFAULT SECUENCIA_ID_CATEGORIA.NEXTVAL);
ALTER TABLE CAT_EMPLEADO MODIFY (ID DEFAULT SECUENCIA_ID_CAT_EMPLEADO.NEXTVAL);
                                        
-- B. Comprobar el formato de los campos en las actualizaciones.
                                        
CREATE OR REPLACE TRIGGER TR_CHECK_EMPLEADO_EMAIL
BEFORE UPDATE
    OF EMAIL ON EMPLEADO
FOR EACH ROW
DECLARE
    REGEX_EMAIL VARCHAR2(50) := '^[A-Za-z0-9]+@[A-Za-z0-9]+\.[A-Za-z]+';
BEGIN
    IF NOT REGEXP_LIKE(:NEW.EMAIL, REGEX_EMAIL) THEN
        RAISE_APPLICATION_ERROR(-20000,'Email no valido');
    END IF;
END;
/

ALTER TABLE PRODUCTO
ADD CONSTRAINT CHECK_PRODUCTO_STOCK CHECK (STOCK >= 0);
                                        
ALTER TABLE PRODUCTO
ADD CONSTRAINT CHECK_PESO_NETO CHECK (PESO_NETO >= 0);

ALTER TABLE PRODUCTO
ADD CONSTRAINT CHECK_PRODUCTO_EXPOSICION CHECK (EXPOSICION >= 0);
                                        
ALTER TABLE PRODUCTO
ADD CONSTRAINT CHECK_PRODUCTO_PRECIO_ACTUAL CHECK (PRECIO_ACTUAL >= 0);                                    
                                        
CREATE OR REPLACE TRIGGER TR_CHECK_FIDELIZADO_PUNTOS_ACUMULADOS
BEFORE UPDATE
    OF PUNTOS_ACUMULADOS ON FIDELIZADO
FOR EACH ROW
BEGIN
    IF :NEW.PUNTOS_ACUMULADOS < 0 THEN
        RAISE_APPLICATION_ERROR(-20000,'El numero de puntos acumulados no puede ser negativo');
    ELSIF REMAINDER(:NEW.PUNTOS_ACUMULADOS, 1) != 0 THEN
        RAISE_APPLICATION_ERROR(-20000,'El numero de puntos acumulados tiene que ser un numero entero');
    END IF;
END;
/
                                        
CREATE OR REPLACE TRIGGER TR_CHECK_FIDELIZADO_EMAIL
BEFORE UPDATE
    OF EMAIL ON FIDELIZADO
FOR EACH ROW
DECLARE
    REGEX_EMAIL VARCHAR2(50) := '^[A-Za-z0-9]+@[A-Za-z0-9]+\.[A-Za-z]+';
BEGIN
    IF NOT REGEXP_LIKE(:NEW.EMAIL, REGEX_EMAIL) THEN
        RAISE_APPLICATION_ERROR(-20000,'Email no valido');
    END IF;
END;
/

ALTER TABLE MOBILIARIO
ADD CONSTRAINT CHECK_MOBILIARIO_CAPACIDAD CHECK (CAPACIDAD >= 0);   

ALTER TABLE MOBILIARIO
ADD CONSTRAINT CHECK_MOBILIARIO_EN_USO CHECK (EN_USO >= 0);   
                                        
ALTER TABLE NOMINA
ADD CONSTRAINT CHECK_NOMINA_IMPORTE_NETO CHECK (IMPORTE_NETO <= IMPORTE_BRUTO);   
                                  
                                        
CREATE OR REPLACE TRIGGER TR_CHECK_PROVEEDOR_EMAIL
BEFORE UPDATE
    OF EMAIL ON PROVEEDOR
FOR EACH ROW
DECLARE
    REGEX_EMAIL VARCHAR2(50) := '^[A-Za-z0-9]+@[A-Za-z0-9]+\.[A-Za-z]+';
BEGIN
    IF NOT REGEXP_LIKE(:NEW.EMAIL, REGEX_EMAIL) THEN
        RAISE_APPLICATION_ERROR(-20000,'Email no valido');
    END IF;
END;
/

ALTER TABLE RETENCIONES
ADD CONSTRAINT CHECK_RETENCIONES_PORCENTAJE CHECK (PORCENTAJE >= 0);   
                                        
ALTER TABLE TICKET
ADD CONSTRAINT CHECK_TICKET_TOTAL CHECK (TOTAL >= 0);   


ALTER TABLE TICKET
ADD CONSTRAINT CHECK_TICKET_PUNTOS CHECK (PUNTOS >= 0);

-- C. Conceder permisos a roles.

-- Solo los directores deberian tener acceso (lectura-escritura) a NOMINA.
GRANT SELECT, INSERT, UPDATE, DELETE ON NOMINA TO R_DIRECTOR;

-- Los cajeros pueden acceder e insertar nuevos tickets y facturas. No tienen permiso para actualizar o borrar este tipo de informacion.
GRANT SELECT, INSERT ON TICKET TO R_CAJERO;
GRANT SELECT, INSERT ON DETALLE TO R_CAJERO;
GRANT SELECT, INSERT ON FACTURA TO R_CAJERO;

GRANT SELECT, INSERT, UPDATE, DELETE ON REVISION TO R_SUPERVISOR;
GRANT SELECT, INSERT, UPDATE, DELETE ON MOBILIARIO TO R_SUPERVISOR;
GRANT SELECT, INSERT, UPDATE, DELETE ON PASILLO TO R_SUPERVISOR;
GRANT SELECT, INSERT, UPDATE, DELETE ON PROVEEDOR TO R_SUPERVISOR;
GRANT SELECT, INSERT, UPDATE, DELETE ON PROVEE TO R_SUPERVISOR;
GRANT SELECT, INSERT, UPDATE, DELETE ON REPONE TO R_SUPERVISOR;
GRANT SELECT, INSERT, UPDATE, DELETE ON SUPERVISA TO R_SUPERVISOR;
GRANT SELECT, INSERT, UPDATE, DELETE ON ENTREGA TO R_SUPERVISOR;
                                        
-- D. Creacion de indices.
                                        
CREATE BITMAP INDEX IDX_CLIENTE_CODIGO_POSTAL ON CLIENTE(CODIGO_POSTAL);
CREATE INDEX IDX_CLIENTE_APELLIDOS ON CLIENTE(APELLIDO1, APELLIDO2);

CREATE BITMAP INDEX IDX_EMPLEADO_CODIGO_POSTAL ON EMPLEADO(CODIGO_POSTAL);
CREATE INDEX IDX_EMPLEADO_APELLIDOS ON EMPLEADO(APELLIDO1, APELLIDO2);
CREATE INDEX IDX_EMPLEADO_EMAIL ON EMPLEADO(EMAIL);

CREATE BITMAP INDEX IDX_PRODUCTO_CATEGORIA ON PRODUCTO(CATEGORIA);

CREATE INDEX IDX_FIDELIZADO_EMAIL ON FIDELIZADO(EMAIL);
CREATE INDEX IDX_PROVEEDOR_NOMBRE ON PROVEEDOR(NOMBRE_PROVEEDOR);
                                        
-- E. Creacion de usuario PLANIFICADOR para la ejecucion de jobs.
-- [MANUEL] Por si no le diera tiempo al que se encargaba de esta tarea.
BEGIN
DBMS_CREDENTIAL.CREATE_CREDENTIAL (
   credential_name => 'CREDENCIAL_PLANIFICADOR',
   username        => 'PLANIFICADOR',
   password        => 'bd',
   comments        => 'Usuario para la ejecucion de jobs');
END;
/
   
-- E. Creacion de usuario PLANIFICADOR para la ejecucion de jobs.
            --[ADRIAN]
  BEGIN
DBMS_CREDENTIAL.CREATE_CREDENTIAL (
   credential_name => 'CREDENCIAL_PLANIFICADOR',
   username        => 'PLANIFICADOR',
   password        => 'password', /*Nos dijo enrique de no poner BD como contraseña a todo */
   comments        => 'Creación de usuario para la ejecución de jobs');
END;
/
 /*O, en Su defecto*/
   Create user Planificador IDENTIFIED by password default tablespace TS_MERCORACLE quota 10M on TS_MERCORACLE;
   GRANT EXECUTE on SYS.DBMS_JOB to Planificador ;
/*Hay que hacerlo desde Sys
En la documentación
The Database Administrator user does not have the right to allow the Database User to execute jobs in the Oracle 11g and 12c database software.
---------------------------------------------------------------------------------------------------------------------------------------------
*/

 -- F.1 Configuración de Audits para la Modificación de Empleados,Clientes y Nóminas
             --[ADRIAN]
CREATE AUDIT POLICY Mod_Empleado ACTIONS DELETE on Mercoracle.Empleado, INSERT on Mercoracle.Empleado, UPDATE on Mercoracle.Empleado;
              AUDIT POLICY Mod_Empleado BY MERCORACLE;
CREATE AUDIT POLICY Mod_Cliente ACTIONS DELETE on Mercoracle.Cliente, INSERT on Mercoracle.Cliente, UPDATE on Mercoracle.Cliente;
             AUDIT POLICY Mod_Cliente BY MERCORACLE;
CREATE AUDIT POLICY Mod_Nomina ACTIONS DELETE on Mercoracle.Nomina, INSERT on Mercoracle.Nomina, UPDATE on Mercoracle.Nomina;
             AUDIT POLICY Mod_Nomina BY MERCORACLE;

 -- F.2 Configuración de Audits para políticas de seguridad
              --[ADRIAN y ALBERTO]
CREATE AUDIT POLICY BAD_PRIVS ACTIONS GRANT ON Mercoracle.sec_function;
             AUDIT POLICY BAD_PRIVS BY MERCORACLE;
CREATE AUDIT POLICY EX_PRIV ACTIONS EXECUTE ON Mercoracle.sec_function;
             AUDIT POLICY EX_PRIV BY MERCORACLE;
             

  -- G Comprobación de privilegios donde se ejecuta Execute Immediate.
/*
Privilegios comprobados donde se realiza Execute Immediate, TODO OK.
---------------------------------------------------------------------------------------------------------------------------------------------
*/
             
-- H. Creación de perfiles.
CREATE PROFILE PROF_DIRECTIVO LIMIT
   SESSIONS_PER_USER 1
   IDLE_TIME         20
   CONNECT_TIME      120
   CPU_PER_SESSION   UNLIMITED 
   CPU_PER_CALL      3000
   PRIVATE_SGA       30K
   -- Politica de seguridad
   FAILED_LOGIN_ATTEMPTS 3
   PASSWORD_LIFE_TIME    30
   PASSWORD_GRACE_TIME   7
   PASSWORD_LOCK_TIME    1/24;
   
CREATE PROFILE PROF_EMPLEADO LIMIT
   SESSIONS_PER_USER 3
   IDLE_TIME 60
   CONNECT_TIME UNLIMITED
   CPU_PER_CALL 5000
   -- Politica de seguridad
   FAILED_LOGIN_ATTEMPTS 3
   PASSWORD_LIFE_TIME    30
   PASSWORD_GRACE_TIME   7
   PASSWORD_LOCK_TIME    1/24;
       
-- I. TDE.
-- Esta seccion esta comentada por si se intenta ejecutar el script al completo.
-- Al estar modificando un parametro estatico, hay que reiniciar la instancia una vez sea ejecutado
-- lo siguiente:
-- ALTER SYSTEM SET "WALLET_ROOT"='C:/Users/Manuel/Documents' scope=SPFILE;
--
ALTER TABLE NOMINA MODIFY(IMPORTE_NETO ENCRYPT);
ALTER TABLE NOMINA MODIFY(IMPORTE_BRUTO ENCRYPT);
-- Tenemos que debatir que columnas queremos considerar como sensibles.

-- VPD.
--[ALBERTO]
create or replace function sec_function(p_schema varchar2, p_obj varchar2)
  Return varchar2
is
  user VARCHAR2(100);
Begin
if (SYS_CONTEXT('USERENV', 'ISDBA')='TRUE') 
then return ''; -- Si el usuario se conecta como sysdba, podrá ver toda la tabla.
else
  user := SYS_CONTEXT('userenv', 'SESSION_USER');
  return 'UPPER(USUARIO) = ''' || user || '''';
end if;
End;
/
ALTER TABLE MERCORACLE.NOMINA ADD USUARIO VARCHAR2(100);
-- Muestra los datos pertenecientes al usuario conectado en la tabla NOMINA.
begin dbms_rls.add_policy (object_schema =>'MERCORACLE',
object_name =>'NOMINA',
policy_name =>'NOM_POLICY',
function_schema =>'MERCORACLE',
policy_function => 'SEC_FUNCTION',
statement_types => 'SELECT' ); end;
             
-- Muestra los datos pertenecientes al usuario conectado en la tabla EMPLEADO.
begin dbms_rls.add_policy (object_schema =>'MERCORACLE',
object_name =>'EMPLEADO',
policy_name =>'EMP_POLICY',
function_schema =>'SYSTEM',
policy_function => 'SEC_FUNCTION',
statement_types => 'SELECT' ); end;

-- Ahora hay que crear un usuario e introducir este en uno de los empleados. Lo he intentado pero me da un error de política. HAY QUE ARREGLARLO
