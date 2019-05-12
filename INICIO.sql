create tablespace ts_mercoracle datafile 'mercoracle.dbf' size 20M autoextend on next 2M;

create user MERCORACLE
identified by bd
default tablespace ts_mercoracle
quota unlimited on ts_mercoracle;

grant connect, create view, create table, create procedure to mercoracle;
