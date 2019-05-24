/*** ESPECIFICACIÓN ***/

CREATE OR REPLACE PACKAGE paqueteEmpleados AS

PROCEDURE crearEmpleado
    (id NUMBER, 
    dni VARCHAR2, 
    nombre VARCHAR2, 
    apellido1 VARCHAR2, 
    apellido2 VARCHAR2, 
    domicilio VARCHAR2, 
    codigo_postal NUMBER, 
    telefono VARCHAR2, 
    email VARCHAR2, 
    cat_empleado NUMBER, 
    fecha_alta DATE, 
    usuario VARCHAR2,
    clave VARCHAR2);




PROCEDURE borrarEmpleado(empleado EMPLEADO%ROWTYPE);

PROCEDURE modificarEmpleado(
    id NUMBER, 
    dni VARCHAR2, 
    nombre VARCHAR2, 
    apellido1 VARCHAR2, 
    apellido2 VARCHAR2, 
    domicilio VARCHAR2, 
    codigo_postal NUMBER, 
    telefono VARCHAR2, 
    email VARCHAR2, 
    cat_empleado NUMBER, 
    fecha_alta DATE, 
    usuario VARCHAR2);

PROCEDURE bloquearUsuario(empleado EMPLEADO%ROWTYPE);
PROCEDURE desbloquearUsuario(empleado EMPLEADO%ROWTYPE);
PROCEDURE bloquearTodos();
PROCEDURE desbloquearTodos();

PROCEDURE P_EmpleadoDelAño(empleado EMPLEADO%ROWTYPE);

END paqueteEmpleados;






/*** CUERPO ***/

CREATE OR REPLACE PACKAGE BODY paqueteEmpleados AS

PROCEDURE crearEmpleado (
    id NUMBER, 
    dni VARCHAR2, 
    nombre VARCHAR2, 
    apellido1 VARCHAR2, 
    apellido2 VARCHAR2, 
    domicilio VARCHAR2, 
    codigo_postal NUMBER, 
    telefono VARCHAR2, 
    email VARCHAR2, 
    cat_empleado NUMBER, 
    fecha_alta DATE, 
    usuario VARCHAR2) IS
DECLARE
    sentencia VARCHAR2;
    catEmpleadoString VARCHAR2;
BEGIN
 
    INSERT INTO empleados(
        id,
        nombre,
        apellido1,
        apellido2,
        domicilio,
        codigo_postal,
        telefono,
        email,
        cat_empleado,
        fecha_alta,
        usuario
    )
    VALUES(
        crearEmpleado.id,
        crearEmpleado.nombre,
        crearEmpleado.apellido1,
        crearEmpleado.apellido2,
        crearEmpleado.domicilio,
        crearEmpleado.codigo_postal,
        crearEmpleado.telefono,
        crearEmpleado.email,
        crearEmpleado.cat_empleado,
        crearEmpleado.fecha_alta,
        crearEmpleado.usuario
    );
    
    IF crearEmpleado.usuario IS NOT NULL THEN
        
        
        
        IF crearEmpleado.cat_empleado = 1 THEN
            crearEmpleadoString := 'R_DIRECTOR';
        
            ELSEIF crearEmpleado.cat_empleado = 2 THEN
                crearEmpleadoString := 'R_SUPERVISOR';
            
            ELSEIF crearEmpleado.cat_empleado = 3 THEN
                crearEmpleadoString := 'R_CAJERO';
            
            ELSE NULL;
            
        END IF;
        
        sentencia := 'ALTER USER ' ||crearEmpleado.usuario|| ' IDENTIFIED BY '||crearEmpleado.clave||'
            PROFILE ' ||createEmpleadoString|| '; ';
        DBMS_OUTPUT.PUT_LINE(sentencia);
        EXECUTE IMMEDIATE sentencia;
    END IF;
         
EXCEPTION

END;

----------------------------------------

PROCEDURE borrarEmpleado(empleado EMPLEADO%ROWTYPE) AS

BEGIN
     EXECUTE IMMEDIATE 'DROP USER ' ||empleado.usuario|| ';' 
EXCEPTION

END;

--------------------------------------------------

PROCEDURE modificarEmpleado(
    id NUMBER, 
    dni VARCHAR2, 
    nombre VARCHAR2, 
    apellido1 VARCHAR2, 
    apellido2 VARCHAR2, 
    domicilio VARCHAR2, 
    codigo_postal NUMBER, 
    telefono VARCHAR2, 
    email VARCHAR2, 
    cat_empleado NUMBER, 
    fecha_alta DATE, 
    usuario VARCHAR2) AS
DECLARE
    sentencia VARCHAR2;
    catEmpleadoString VARCHAR2;
BEGIN
 
    UPDATE empleados SET
        (
        id,
        nombre,
        apellido1,
        apellido2,
        domicilio,
        codigo_postal,
        telefono,
        email,
        cat_empleado,
        fecha_alta,
        usuario
        )
        = (
        modificarEmpleado.id,
        modificarEmpleado.nombre,
        modificarEmpleado.apellido1,
        modificarEmpleado.apellido2,
        modificarEmpleado.domicilio,
        modificarEmpleado.codigo_postal,
        modificarEmpleado.telefono,
        modificarEmpleado.email,
        modificarEmpleado.cat_empleado,
        modificarEmpleado.fecha_alta,
        modificarEmpleado.usuario
    );
    
    IF crearEmpleado.usuario IS NOT NULL THEN
        
        
        
        IF crearEmpleado.cat_empleado = 1 THEN
            crearEmpleadoString := 'R_DIRECTOR';
        
            ELSEIF crearEmpleado.cat_empleado = 2 THEN
                crearEmpleadoString := 'R_SUPERVISOR';
            
            ELSEIF crearEmpleado.cat_empleado = 3 THEN
                crearEmpleadoString := 'R_CAJERO';
            
            ELSE NULL;
            
        END IF;
        
        sentencia := 'CREATE USER ' ||crearEmpleado.usuario|| ' IDENTIFIED BY '||||'
            PROFILE ' ||createEmpleadoString|| '; ';
        DBMS_OUTPUT.PUT_LINE(sentencia);
        EXECUTE IMMEDIATE sentencia;
    END IF;

         
EXCEPTION

END;


-----------------------------
PROCEDURE bloquearUsuario(empleado EMPLEADO%ROWTYPE) AS
DECLARE
 sentencia VARCHAR2;
BEGIN
 sentencia := 'ALTER USER ' || bloquearUsuario.empleado.usuario || ' ACCOUNT LOCK';
 EXECUTE IMMEDIATE sentencia;
EXCEPTION

END;
------------------------------
PROCEDURE desbloquearUsuario(empleado EMPLEADO%ROWTYPE) AS
 sentencia VARCHAR2;
BEGIN
 sentencia := 'ALTER USER ' || bloquearUsuario.empleado.usuario || ' ACCOUNT UNLOCK';
 EXECUTE IMMEDIATE sentencia;
EXCEPTION

END;

------------------------------

PROCEDURE bloquearTodos() AS
DECLARE
    sentencia VARCHAR2;
    prof VARCHAR2;
BEGIN
    CURSOR empleados_user IS
        SELECT usuario FROM empleados;
    FOR e_user IN empleados_user
        SELECT profile FROM dba_users 
        WHERE username IS e_user
        INTO prof;
        IF prof != "R_DIRECTOR" THEN
           sententcia := 'ALTER USER ' || e_user || ' ACCOUNT LOCK';
           EXECUTE IMMEDIATE sentencia;
        END IF;
    END LOOP;
EXCEPTION

END;
-------------------------------
PROCEDURE desbloquearTodos() AS
DECLARE
    sentencia VARCHAR2;
    prof VARCHAR2;
BEGIN
    CURSOR empleados_user IS
        SELECT usuario FROM empleados;
    FOR e_user IN empleados_user
        SELECT profile FROM dba_users 
        WHERE username IS e_user
        INTO prof;
        IF prof != "R_DIRECTOR" THEN
            sentencia := 'ALTER USER ' || e_user || ' ACCOUNT UNLOCK';
            EXECUTE IMMEDIATE sentencia;
        END IF;
    END LOOP;
EXCEPTION

END;
--------------------------------

PROCEDURE P_EmpleadoDelAño(empleado EMPLEADO%ROWTYPE) AS 
BEGIN

EXCEPTION
END;

END empleados;
/
