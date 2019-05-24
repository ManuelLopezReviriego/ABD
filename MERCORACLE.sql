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

CREATE OR REPLACE PACKAGE PK_EMPLEADO IS
    /* CREACION DE EMPLEADOS Y CUENTAS */
    PROCEDURE CREAR_EMPLEADO (EMP EMPLEADO%ROWTYPE, CLAVE VARCHAR2);
    PROCEDURE ASIGNAR_CUENTA(DNI VARCHAR2, NOMBRE_USUARIO VARCHAR2, CLAVE VARCHAR2);
    
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
        UPDATE EMPLEADO E SET E.NOMBRE = NOMBRE WHERE E.DNI = DNI;
    END SET_NOMBRE;

    PROCEDURE SET_PRIMER_APELLIDO(DNI VARCHAR2, APELLIDO VARCHAR2) IS
    BEGIN
        UPDATE EMPLEADO E SET E.APELLIDO1 = APELLIDO WHERE E.DNI = DNI;
    END SET_PRIMER_APELLIDO;

    PROCEDURE SET_SEGUNDO_APELLIDO(DNI VARCHAR2, APELLIDO VARCHAR2) IS
    BEGIN
        UPDATE EMPLEADO E SET E.APELLIDO2 = APELLIDO WHERE E.DNI = DNI;
    END SET_SEGUNDO_APELLIDO;

    PROCEDURE SET_EMAIL(DNI VARCHAR2, EMAIL VARCHAR) IS
    BEGIN
        UPDATE EMPLEADO E SET E.EMAIL = EMAIL WHERE E.DNI = DNI;
    END SET_EMAIL;

    PROCEDURE SET_TELEFONO(DNI VARCHAR2, TELEFONO VARCHAR) IS
    BEGIN
        UPDATE EMPLEADO E SET E.TELEFONO = TELEFONO WHERE E.DNI = DNI;
    END SET_TELEFONO;

    PROCEDURE SET_DOMICILIO(DNI VARCHAR2, NUEVO_DOMICILIO VARCHAR2, NUEVO_COD_POSTAL NUMBER) IS
    BEGIN
        UPDATE EMPLEADO E SET E.DOMICILIO = NUEVO_DOMICILIO, E.CODIGO_POSTAL = NUEVO_COD_POSTAL WHERE E.DNI = DNI;
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

    PROCEDURE ASIGNAR_CUENTA(DNI VARCHAR2, NOMBRE_USUARIO VARCHAR2, CLAVE VARCHAR2) IS
        SENT_CREAR_USUARIO VARCHAR2(100); 
        SENT_ASIGNAR_ROL   VARCHAR2(100);
        EMP                EMPLEADO%ROWTYPE;
    BEGIN
        SENT_CREAR_USUARIO := 'CREATE USER ' || NOMBRE_USUARIO || ' IDENTIFIED BY ' || CLAVE || ';';
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
comments => 'Ejecuta el procedimiento P_Reasignar_metros todos los sabados a las 22:00');
END;
/
