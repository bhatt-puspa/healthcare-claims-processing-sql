/* =====================================================================
   12_USP_CLM_PYMT_RECOV.sql
   =====================================================================
   Handles a provider paying back some or all of an overpayment
   (partial recovery). Updates CMC_ACPR (ACPR_RECOV_AMT, ACPR_NET_AMT,
   ACPR_STS) and logs the recovery event to CMC_ACRH.

   PREREQUISITE: CMC_ACRH must have the surrogate ACRH_ID primary key
   (included in 02_Create_Database_FACETS.sql) so that multiple
   partial-recovery events against the same claim can each get their
   own row without a primary key violation.
   ===================================================================== */

USE [FACETS_Custom]
GO

CREATE OR ALTER PROCEDURE [dbo].[USP_CLM_PYMT_RECOV]
    @CLCL_ID            VARCHAR(10),
    @PRPR_ID            VARCHAR(10),
    @RECOV_AMT          MONEY,
    @ACRH_EVENT_TYPE    VARCHAR(1) = 'W',
    @ACRH_MCTR_RSN      VARCHAR(10) = NULL
AS
/*
EXEC [dbo].[USP_CLM_PYMT_RECOV] '25J0000066', 'PRPR0000001', 50.00
*/
BEGIN
    SET NOCOUNT ON;

    DECLARE
    @run_id				INT				= (SELECT ISNULL(MAX(RUN_ID),0) FROM dbo.CLM_JOB_STEP_LOG WITH(NOLOCK)),
    @job_id				VARCHAR(255)	= 'CLCL_PROCESSING',
    @error				INT				= 0,
    @step_id			INT				= 0,
    @sys_def_msg		VARCHAR(5000),
    @sp_name			VARCHAR(255)	= (SELECT OBJECT_NAME(@@PROCID)),
    @rows_processed		INT				= 0,
    @step_desc			VARCHAR(255),
    @status_desc		VARCHAR(255),
    @status				VARCHAR(1)

    DECLARE @ACPR_REF_ID    VARCHAR(10) = 'ARI' + RIGHT(@CLCL_ID, 7);
    DECLARE @ACPR_TYPE      VARCHAR(2);
    DECLARE @ACPR_SUB_TYPE  VARCHAR(1);
    DECLARE @ACPR_ORIG_AMT  MONEY;
    DECLARE @ACPR_NET_AMT   MONEY;
    DECLARE @ACPR_STS       VARCHAR(1);

    -- Look up the matching ACPR record for this claim + provider
    SELECT
        @ACPR_TYPE      = ACPR_TYPE,
        @ACPR_SUB_TYPE  = ACPR_SUB_TYPE,
        @ACPR_ORIG_AMT  = ACPR_ORIG_AMT,
        @ACPR_NET_AMT   = ACPR_NET_AMT,
        @ACPR_STS       = ACPR_STS
    FROM FACETS.dbo.CMC_ACPR
    WHERE ACPR_REF_ID = @ACPR_REF_ID
      AND ACPR_PAYEE_ID = @PRPR_ID;

    IF @ACPR_TYPE IS NULL
    BEGIN
        SELECT 'NO ACPR RECORD FOUND FOR THIS CLAIM/PROVIDER' AS ErrorMessage;
        RETURN;
    END

    IF @ACPR_STS = 'I'
    BEGIN
        SELECT 'ACPR RECORD IS ALREADY INACTIVE - NO OUTSTANDING RECOVERY AMOUNT' AS ErrorMessage;
        RETURN;
    END

    IF @RECOV_AMT > @ACPR_NET_AMT
    BEGIN
        SELECT 'RECOVERY AMOUNT EXCEEDS OUTSTANDING NET AMOUNT' AS ErrorMessage;
        RETURN;
    END

    BEGIN TRANSACTION;
    BEGIN TRY

        SET @step_id    = @step_id + 1
        SET @step_desc  = 'UPDATE CMC_ACPR WITH RECOVERY AMOUNT'

        UPDATE FACETS.dbo.CMC_ACPR
        SET
            ACPR_RECOV_AMT  = ACPR_RECOV_AMT + @RECOV_AMT,
            ACPR_NET_AMT    = ACPR_NET_AMT - @RECOV_AMT,
            ACPR_STS        = CASE WHEN ACPR_NET_AMT - @RECOV_AMT <= 0 THEN 'I' ELSE ACPR_STS END
        WHERE ACPR_REF_ID = @ACPR_REF_ID
          AND ACPR_PAYEE_ID = @PRPR_ID;

        SELECT @rows_processed = @@ROWCOUNT, @status_desc = @step_desc + ' COMPLETED', @status = 'C'

        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @run_id = @run_id, @job_id = @job_id, @status_desc = @status_desc,
             @sys_def_msg = @sys_def_msg, @step_id = @step_id, @sp_name = @sp_name,
             @error = @error, @rows_processed = @rows_processed, @status = @status

        SET @rows_processed = 0
        SET @step_id    = @step_id + 1
        SET @step_desc  = 'INSERT RECOVERY EVENT INTO CMC_ACRH'

        INSERT INTO FACETS.dbo.CMC_ACRH
        (
            ACPR_REF_ID, ACPR_TYPE, ACPR_SUB_TYPE,
            ACRH_CREATE_DT, ACRH_EVENT_TYPE, ACRH_AMT, ACRH_MCTR_RSN
        )
        VALUES
        (
            @ACPR_REF_ID, @ACPR_TYPE, @ACPR_SUB_TYPE,
            GETDATE(), @ACRH_EVENT_TYPE, @RECOV_AMT, @ACRH_MCTR_RSN
        );

        SELECT @rows_processed = @@ROWCOUNT, @status_desc = @step_desc + ' COMPLETED', @status = 'C'

        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @run_id = @run_id, @job_id = @job_id, @status_desc = @status_desc,
             @sys_def_msg = @sys_def_msg, @step_id = @step_id, @sp_name = @sp_name,
             @error = @error, @rows_processed = @rows_processed, @status = @status

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SELECT
            @error       = ERROR_NUMBER(),
            @sys_def_msg = ERROR_MESSAGE(),
            @status_desc = @step_desc + ' Failed.',
            @status      = 'E'

        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @run_id = @run_id, @job_id = @job_id, @status_desc = @status_desc,
             @sys_def_msg = @sys_def_msg, @step_id = @step_id, @sp_name = @sp_name,
             @error = @error, @rows_processed = @rows_processed, @status = @status

    END CATCH;
END
GO
