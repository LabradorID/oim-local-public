-- OIM Default Configuration Script
-- This script runs on startup to configure default settings

USE OneIM;
GO

-- Enable full process history logging (All jobs logged, not just selected)
UPDATE DialogConfigParm
SET Value = 'ALL'
WHERE FullPath = 'Common\ProcessState\JobHistory'
  AND Value != 'ALL';

IF @@ROWCOUNT > 0
    PRINT 'Updated Common\ProcessState\JobHistory to ALL';
ELSE
    PRINT 'Common\ProcessState\JobHistory already set to ALL or not found';
GO

-- Optional: Set history retention period (days) - uncomment if needed
-- UPDATE DialogConfigParm
-- SET Value = '30'
-- WHERE FullPath = 'Common\ProcessState\LifeTime';
-- GO

PRINT 'OIM default configuration complete';
GO
