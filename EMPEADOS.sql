/*** ESPECIFICACIÓN ***/

CREATE OR REPLACE PACKAGE paqueteEmpleados AS

PROCEDURE crearEmpleado
    (id NUMBER, 
    dni VARCHAR2(9 CHAR), 
    nombre VARCHAR2(20 CHAR), 
    apellido1 VARCHAR2(30 CHAR), 
    apellido2 VARCHAR2(30 CHAR), 
    domicilio VARCHAR2(100 CHAR), 
    codigo_postal NUMBER(5,0), 
    telefono VARCHAR2(15 CHAR), 
    email VARCHAR2(50 CHAR), 
    cat_empleado NUMBER, 
    fecha_alta DATE, 
    usuario VARCHAR2(30 BYTE));




PROCEDURE borrarEmpleado(empleado EMPLEADO%ROWTYPE);

PROCEDURE modificarEmpleado(
    id NUMBER, 
    dni VARCHAR2(9 CHAR), 
    nombre VARCHAR2(20 CHAR), 
    apellido1 VARCHAR2(30 CHAR), 
    apellido2 VARCHAR2(30 CHAR), 
    domicilio VARCHAR2(100 CHAR), 
    codigo_postal NUMBER(5,0), 
    telefono VARCHAR2(15 CHAR), 
    email VARCHAR2(50 CHAR), 
    cat_empleado NUMBER, 
    fecha_alta DATE, 
    usuario VARCHAR2(30 BYTE));

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
    dni VARCHAR2(9 CHAR), 
    nombre VARCHAR2(20 CHAR), 
    apellido1 VARCHAR2(30 CHAR), 
    apellido2 VARCHAR2(30 CHAR), 
    domicilio VARCHAR2(100 CHAR), 
    codigo_postal NUMBER(5,0), 
    telefono VARCHAR2(15 CHAR), 
    email VARCHAR2(50 CHAR), 
    cat_empleado NUMBER, 
    fecha_alta DATE, 
    usuario VARCHAR2(30 BYTE)) IS
DECLARE
    catEmpleadoString VARCHAR2(50 CHAR);
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
    
        EXECUTE IMMEDIATE
            'CREATE USER ' ||crearEmpleado.usuario|| ' IDENTIFIED BY mercoracle
            PROFILE ' ||createEmpleadoString|| '; ';
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
    dni VARCHAR2(9 CHAR), 
    nombre VARCHAR2(20 CHAR), 
    apellido1 VARCHAR2(30 CHAR), 
    apellido2 VARCHAR2(30 CHAR), 
    domicilio VARCHAR2(100 CHAR), 
    codigo_postal NUMBER(5,0), 
    telefono VARCHAR2(15 CHAR), 
    email VARCHAR2(50 CHAR), 
    cat_empleado NUMBER, 
    fecha_alta DATE, 
    usuario VARCHAR2(30 BYTE)) AS
DECLARE
    catEmpleadoString VARCHAR2(50 CHAR);
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
    
    IF modificarEmpleado.usuario IS NOT NULL THEN
        
        
        IF modificarEmpleado.cat_empleado = 1 THEN
            crearEmpleadoString := 'R_DIRECTOR';
        
            ELSEIF crearEmpleado.cat_empleado = 2 THEN
                crearEmpleadoString := 'R_SUPERVISOR';
            
            ELSEIF crearEmpleado.cat_empleado = 3 THEN
                crearEmpleadoString := 'R_CAJERO';
            
            ELSE NULL;
            
        END IF;
    
        EXECUTE IMMEDIATE
            'CREATE USER ' ||crearEmpleado.usuario|| ' IDENTIFIED BY mercoracle
            PROFILE ' ||createEmpleadoString|| '; ';
    END IF;
         
EXCEPTION

END;


-----------------------------
PROCEDURE bloquearUsuario(empleado EMPLEADO%ROWTYPE) AS

BEGIN
 ALTER USER bloquearUsuario.empleado.usuario ACCOUNT LOCK;
EXCEPTION

END;
------------------------------
PROCEDURE desbloquearUsuario(empleado EMPLEADO%ROWTYPE) AS

BEGIN
 ALTER USER bloquearUsuario.empleado.usuario ACCOUNT UNLOCK;
EXCEPTION

END;

------------------------------

PROCEDURE bloquearTodos() AS
DECLARE
    prof VARCHAR2;
BEGIN
    CURSOR empleados_user IS
        SELECT usuario FROM empleados;
    FOR e_user IN empleados_user
        SELECT profile FROM dba_users 
        WHERE username IS e_user
        INTO prof;
        IF prof != "R_DIRECTOR" THEN
            ALTER USER e_user ACCOUNT LOCK;
        END IF;
    END LOOP;
EXCEPTION

END;
-------------------------------
PROCEDURE desbloquearTodos() AS
DECLARE
    prof VARCHAR2;
BEGIN
    CURSOR empleados_user IS
        SELECT usuario FROM empleados;
    FOR e_user IN empleados_user
        SELECT profile FROM dba_users 
        WHERE username IS e_user
        INTO prof;
        IF prof != "R_DIRECTOR" THEN
            ALTER USER e_user ACCOUNT UNLOCK;
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