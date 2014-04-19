#sp_SqlForeachDB

Executes a script against each database in an instance. The goal of this procedure is to improve upon the undocumented system proc sp_MSforeachdb, by providing: documentation, options, messaging, and error handling.

##Example

This example runs multiple scripts against all the user databases that are not read-only; stops execution of the script against the remaining databases if an error occurs; returns 0 if there is an error, so execution of the next script can be stopped.

```sql
DECLARE @sql NVARCHAR(MAX)
        , @scriptSuccess BIT;

SET @sql = N'
        USE {db};
        IF EXISTS (SELECT * FROM sys.schemas WHERE name = ''foo'')
                PRINT ''Schema already exists in {db}'';
        ELSE 
        BEGIN
                PRINT ''Adding schema to {db}'';
                EXEC spCreateSchema @schema  = ''foo'', @purpose = ''bar.''
        END';

EXEC @scriptSuccess = sp_SqlForeachDB
        @script = @sql
        ,@excludeSystem = 1
        ,@excludeReadOnly = 1;

IF @scriptSuccess = 0
BEGIN
        PRINT 'Execution aborted! Please view the message log for more details.';
        RETURN;
END

-- Next script
SET @sql = N'   USE {db};...
```
