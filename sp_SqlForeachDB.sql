USE [master];
GO

/************************************************************************************
** Name: sp_SqlForeachDB                                                           **
** Desc: Executes a script against each database in an instance. The goal of this  **
**       procedure is to improve upon the undocumented system proc sp_MSforeachdb, **
**       by providing: documentation, options, messaging, and error handling       **
** Date: August 7, 2013                                                            **
** Auth: Jason Pierce (jason@2toad.com)                                            **
*************************************************************************************
** The MIT License (MIT)                                                           **
**                                                                                 **
** Copyright (c)2013 2Toad, LLC.                                                   **
**                                                                                 **
** Permission is hereby granted, free of charge, to any person obtaining a copy    **
** of this software and associated documentation files (the "Software"), to deal   **
** in the Software without restriction, including without limitation the rights    **
** to use, copy, modify, merge, publish, distribute, sublicense, and/or sell       **
** copies of the Software, and to permit persons to whom the Software is           **
** furnished to do so, subject to the following conditions:                        **
**                                                                                 **
** The above copyright notice and this permission notice shall be included in      **
** all copies or substantial portions of the Software.                             **
**                                                                                 **
** THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR      **
** IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,        **
** FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE     **
** AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER          **
** LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,   **
** OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN       **
** THE SOFTWARE.                                                                   **
*************************************************************************************/
CREATE PROCEDURE [dbo].[sp_SqlForeachDB] 
	 @script NVARCHAR(MAX)					-- The script to execute against each database
	,@databaseTag NVARCHAR(25) = N'{db}'	-- This tag will be replaced with the name of the database the @script is executing against
	,@excludeSystem BIT = 0					-- Do not execute the @script against system databases
	,@excludeUser BIT = 0					-- Do not execute the @script against user databases
	,@excludeReadOnly BIT = 0				-- Do not execute the @script against read-only databases
	,@includePattern NVARCHAR(256) = NULL	-- Include databases with names that match this pattern (uses LIKE Wildcards)
	,@includeList NVARCHAR(MAX) = NULL		-- A comma separated list of databases to include
	,@excludeList NVARCHAR(MAX) = NULL		-- A comma separated list of databases to exclude
	,@ignoreErrors BIT = 0					-- Continue executing the @script against the remaining databases if an error occurs
	,@printMode BIT = 0						-- Print @script instead of executing it
AS
BEGIN
	SET NOCOUNT ON;

	-- Generate query based on user options
	DECLARE @sql NVARCHAR(MAX) = N'
		SELECT [name] 
		FROM [sys].[databases] 
		WHERE 0=0' + 
		CASE WHEN @excludeSystem = 1 THEN ' AND [database_id] > 4' ELSE '' END + 
		CASE WHEN @excludeUser = 1 THEN ' AND [database_id] < 5' ELSE '' END + 
		CASE WHEN @excludeReadOnly = 1 THEN ' AND [is_read_only] = 0' ELSE '' END + 
		CASE WHEN @includePattern IS NOT NULL THEN ' AND [name] LIKE N''' + @includePattern + '''' ELSE '' END + 
		CASE WHEN @includeList IS NOT NULL THEN ' AND [name] IN (''' + REPLACE(@includeList, ',', ''',''') + ''')' ELSE '' END +
		CASE WHEN @excludeList IS NOT NULL THEN ' AND [name] NOT IN (''' + REPLACE(@excludeList, ',', ''',''') + ''')' ELSE '' END

	-- Populate table with databases to execute the @script against
	CREATE TABLE #databases ([database] NVARCHAR(128));
	INSERT #databases EXEC sp_executesql @sql;

	-- Loop through databases
	DECLARE @database NVARCHAR(300);
	DECLARE database_cursor CURSOR
		LOCAL FORWARD_ONLY STATIC READ_ONLY
		FOR	SELECT QUOTENAME([database]) FROM #databases ORDER BY [database];
	OPEN database_cursor;
	FETCH NEXT FROM database_cursor	INTO @database;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		-- Update @script with current database name
		SET @sql = REPLACE(@script, @databaseTag, @database);
		PRINT '/* ' + @database + ' */';

		-- Print the @script if we're in print mode
		IF @printMode = 1
			PRINT @sql;
		ELSE
		BEGIN
			-- Execute the script
			BEGIN TRY
				EXEC sp_executesql @sql;
			END TRY
			BEGIN CATCH
				SELECT @database AS [Database], ERROR_MESSAGE() AS [ErrorMessage], @sql AS [Script];
				RAISERROR('An error was thrown while executing the script against %s', 16, 1, @database) WITH NOWAIT;
				PRINT 'Error: ' + ERROR_MESSAGE();
				
				-- Failure
				IF @ignoreErrors = 0 RETURN 0;
			END CATCH
		END

		-- Next database
		PRINT CHAR(13)+CHAR(10);
		FETCH NEXT FROM database_cursor INTO @database;
	END

	-- Cleanup
	CLOSE database_cursor;
	DEALLOCATE database_cursor;

	-- Success
	RETURN 1;
END
GO