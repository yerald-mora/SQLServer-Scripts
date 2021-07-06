-- =============================================
-- Author:		Yerald Mora
-- Description: Generates a script that create or replace the server logins with its hashed passwords and database users
-- sp_hexadecimal copied from https://docs.microsoft.com/en-US/troubleshoot/sql/security/transfer-logins-passwords-between-instances
-- =============================================
CREATE PROCEDURE sp_generates_logins_script
	
	@path as nvarchar(17),--a local or network path
	@DB nvarchar(10)
AS
BEGIN
	
SET NOCOUNT ON;

declare @login as nvarchar(20)
declare @PWD_varbinary  varbinary (256)
declare @PWD_string  varchar (514)
declare @SID_varbinary varbinary (85)
declare @SID_string varchar (514)
declare @policy_checked varchar (30)
declare @expiration_checked varchar (30)

declare @sql as nvarchar(max)='/*******************SERVER LOGINS GENERATOR SCRIPT*******************/'+CHAR(13)+CHAR(13)

DECLARE logins CURSOR FOR

	select name,sid from sys.syslogins
	where hasaccess = 1 and (sysadmin=0 or name  IN('sysadminusertokeep'))
	AND dbname =@DB and isntname=0

OPEN logins
FETCH logins INTO @login,@SID_varbinary

WHILE @@FETCH_STATUS=0
	begin
	
	SET @PWD_varbinary = CAST( LOGINPROPERTY( @login, 'PasswordHash' ) AS varbinary (256) )
    EXEC master.dbo.sp_hexadecimal @PWD_varbinary, @PWD_string OUT
    EXEC master.dbo.sp_hexadecimal @SID_varbinary,@SID_string OUT

	SELECT @policy_checked = CASE is_policy_checked 
								WHEN 1 THEN ', CHECK_POLICY = ON' 
								WHEN 0 THEN ', CHECK_POLICY = OFF' 
								ELSE ', CHECK_POLICY = ON' 
							END ,
		@expiration_checked = CASE is_expiration_checked 
								WHEN 1 THEN ', CHECK_EXPIRATION = ON' 
								WHEN 0 THEN ', CHECK_EXPIRATION = OFF' 
								ELSE ', CHECK_EXPIRATION = ON' 
							END
	FROM sys.sql_logins WHERE name = @login

	set @sql=@sql +
	'/************************************** '+@login+' ***************************************/'+CHAR(13)
	+'USE '+@DB+CHAR(13)+CHAR(13)

	+'IF EXISTS (SELECT name from sys.schemas where name='+''''+@login+''')'+CHAR(13)
	+'BEGIN
	DROP SCHEMA '	+@login+CHAR(13)
	+'END'+CHAR(13)+CHAR(13)+
		
	+'IF EXISTS (SELECT name from sys.database_principals where name='+''''+@login+''')'+CHAR(13)
	+'BEGIN
	DROP USER '	+@login+CHAR(13)
	+'END'+CHAR(13)+CHAR(13)+
	
	+'IF NOT EXISTS (SELECT name from sys.syslogins where name='+''''+@login+''')'+CHAR(13)
	+' CREATE LOGIN ' +@login+ ' WITH PASSWORD = ' + @PWD_string + ' HASHED, SID = ' + @SID_string + ', DEFAULT_DATABASE = ['+@DB+']' + @policy_checked + @expiration_checked + CHAR(13)
	 
	+'ELSE '+CHAR(13)
	+'BEGIN'+CHAR(13)
	+' ALTER LOGIN ' + @login + ' WITH PASSWORD = ' + @PWD_string + ' HASHED, CHECK_POLICY = OFF' + CHAR(13)
	+' ALTER LOGIN ' + @login + ' WITH' +REPLACE(@policy_checked,',','') + @expiration_checked + CHAR(13)
	+'END'
	SET @sql=@sql+ CHAR(13)+CHAR(13)
	+'CREATE USER '+@login+' FOR LOGIN '+ @login+CHAR(13)
	+'exec sp_addrolemember ''db_owner'','+''''+@login+''''+CHAR(13)+CHAR(13)

	fetch logins into @login,@SID_varbinary
	end
CLOSE logins
DEALLOCATE logins

select @sql as Texto into ##temp  

Declare @Comando varchar(2048)

Set @Comando=CONCAT('Exec Master..xp_Cmdshell ''bcp "select Texto from ##temp" queryout "',@path,'\LOGINS.sql" -w -T''')

Exec(@Comando) 
END
