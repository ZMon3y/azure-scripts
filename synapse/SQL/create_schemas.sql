IF (NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'ods')) 
BEGIN
    EXEC ('CREATE SCHEMA [ods] AUTHORIZATION [dbo]')
END