IF OBJECT_ID('ods.myTable', 'U') IS NOT NULL
    DROP TABLE ods.myTable 
CREATE TABLE ods.myTable 
(
    [foo]   int NOT NULL
)
WITH
( 
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX 
)