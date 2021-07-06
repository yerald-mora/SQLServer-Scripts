-- =============================================
-- Author:		Yerald Mora
-- Description:	Generates a script to copy filtered registries from a given table
-- =============================================
CREATE PROCEDURE sp_generate_script_to_copy_rows
	@table_name as varchar(100)
AS
BEGIN

declare @sql as varchar(MAX)='SELECT''INSERT INTO '+@table_name+' VALUES ('','
declare @sqlcolumns as varchar(4000)=''
declare @column_name as varchar(100)
declare @column_count as integer=0
declare @column_cant as integer
declare @type as varchar(50)

set @column_cant=(select COUNT(c.name) from sys.sysobjects o join sys.syscolumns c on o.id=c.id
						join sys.systypes t on t.xusertype=c.xtype
					where o.name=@table_name and o.xtype='U')

DECLARE cur_tabla CURSOR FOR
	select o.name,c.name,t.name from sys.sysobjects o join sys.syscolumns c on o.id=c.id
		join sys.systypes t on t.xusertype=c.xtype
	where o.name=@table_name and o.xtype='U'
OPEN cur_tabla
FETCH cur_tabla INTO @table_name,@column_name,@type

WHILE @@FETCH_STATUS=0
	BEGIN
		set @column_count=@column_count+1
		set @column_name='isnull(cast('+@column_name+' as varchar(50)),''NULL'')+'
		
		if @type in ('text','date','time','smalldatetime','datetime','varchar','char','nvarchar','nchar') or @type like 'ut_%'
		begin
			set @column_name='''''''''+'+@column_name+''''''
		end
		
		set @column_name=@column_name+''''
		set @sqlcolumns=@sqlcolumns+@column_name+ case when @column_cant=@column_count then ')''' else ','',' end +CHAR(13)
		FETCH cur_tabla INTO @table_name,@column_name,@type
	END
		
CLOSE cur_tabla
DEALLOCATE cur_tabla

SET @sql=@sql+@sqlcolumns+'FROM '+@table_name

print @sql

END
GO
