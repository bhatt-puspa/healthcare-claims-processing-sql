/* =====================================================================
   10_USP_CLM_STG_TO_CORE.sql
   =====================================================================
   PURPOSE - Load accepted claims from STG to FACETS Core and remove
   completed/rejected claims from staging.

   WORKFLOW
   --------------------------------------------------------------------
   1. Perform final safety validation.
   2. Set invalid/unprocessed claims to status 15.
   3. Preserve rejected claims in CW_RJCT_CLCL.
   4. Load accepted claim headers into FACETS.dbo.CMC_CLCL.
   5. Load accepted claim details into FACETS.dbo.CMC_CDML.
   6. Set accepted claims to status 01 in Core.
   7. Delete successfully handled claims from staging.
   8. Keep status 15 claims in staging.

   STATUS
   --------------------------------------------------------------------
   01 = Loaded to Core
   11 = Member Not Found
   12 = Provider Not Found
   13 = Service Date Validation Failed
   14 = Provider Tax Validation Failed
   15 = Errored Out
   16 = Submitted / Passed Preprocessing
   ===================================================================== */

USE [FACETS_Custom]
GO

CREATE OR ALTER PROCEDURE [dbo].[USP_CLM_STG_TO_CORE]
AS
BEGIN

    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @RUN_ID INT =
        (
            SELECT ISNULL(MAX(RUN_ID), 0)
            FROM dbo.CLM_JOB_STEP_LOG WITH(NOLOCK)
        ),

        @JOB_ID             VARCHAR(255) = 'CLCL_PROCESSING',
        @ERROR              INT = 0,
        @STEP_ID            INT = 0,
        @SYS_DEF_MSG        VARCHAR(5000),
        @SP_NAME            VARCHAR(255) = OBJECT_NAME(@@PROCID),
        @ROWS_PROCESSED     INT = 0,
        @STEP_DESC          VARCHAR(255),
        @STATUS_DESC        VARCHAR(255),
        @STATUS             VARCHAR(1);


    BEGIN TRANSACTION;

    BEGIN TRY

        SET @RUN_ID = @RUN_ID + 1;

        /* =========================================================
           STEP 1 - FINAL SAFETY VALIDATION
           Status 15 if: MEME_ID is NULL, PRPR_ID is NULL, either
           service date is NULL, or LOW service date > HIGH service date
           ========================================================= */
        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC = 'PERFORM FINAL CLAIM VALIDATION BEFORE CORE LOAD';

        UPDATE CLCL
        SET CLCL.CLCL_CUR_STS = '15'
        FROM FACETS_STG.dbo.STG_CMC_CLCL CLCL
        WHERE CLCL.CLCL_CUR_STS = '16'
          AND
          (
                 CLCL.MEME_ID IS NULL
              OR CLCL.PRPR_ID IS NULL
              OR CLCL.CLCL_LOW_SVC_DT IS NULL
              OR CLCL.CLCL_HIGH_SVC_DT IS NULL
              OR CLCL.CLCL_LOW_SVC_DT > CLCL.CLCL_HIGH_SVC_DT
          );

        SELECT @ROWS_PROCESSED = @@ROWCOUNT, @STATUS_DESC = @STEP_DESC + ' COMPLETED', @STATUS = 'C';

        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID = @RUN_ID, @JOB_ID = @JOB_ID, @STATUS_DESC = @STATUS_DESC,
             @SYS_DEF_MSG = @SYS_DEF_MSG, @STEP_ID = @STEP_ID, @SP_NAME = @SP_NAME,
             @ERROR = @ERROR, @ROWS_PROCESSED = @ROWS_PROCESSED, @STATUS = @STATUS;

        /* =========================================================
           STEP 2 - UPDATE DETAIL STATUS TO 15 FOR HEADER ERROR CLAIMS
           ========================================================= */
        SET @ROWS_PROCESSED = 0;
        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC = 'UPDATE DETAIL STATUS FOR FINAL VALIDATION ERRORS';

        UPDATE CDML
        SET CDML.CDML_CUR_STS = '15'
        FROM FACETS_STG.dbo.STG_CMC_CDML CDML
        INNER JOIN FACETS_STG.dbo.STG_CMC_CLCL CLCL
            ON CDML.CLCL_ID = CLCL.CLCL_ID
        WHERE CLCL.CLCL_CUR_STS = '15';

        SELECT @ROWS_PROCESSED = @@ROWCOUNT, @STATUS_DESC = @STEP_DESC + ' COMPLETED', @STATUS = 'C';

        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID = @RUN_ID, @JOB_ID = @JOB_ID, @STATUS_DESC = @STATUS_DESC,
             @SYS_DEF_MSG = @SYS_DEF_MSG, @STEP_ID = @STEP_ID, @SP_NAME = @SP_NAME,
             @ERROR = @ERROR, @ROWS_PROCESSED = @ROWS_PROCESSED, @STATUS = @STATUS;

        /* =========================================================
           STEP 3 - PRESERVE REJECTED CLAIMS BEFORE STAGING DELETE
           NOT EXISTS protects against duplicates from prior procs.
           ========================================================= */
        SET @ROWS_PROCESSED = 0;
        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC = 'PRESERVE REJECTED CLAIMS BEFORE STAGING DELETE';

        INSERT INTO dbo.CW_RJCT_CLCL
        (
            CLCL_ID, MEME_CK, CLCL_SUB_TYPE, CLCL_TOT_CHG,
            PRPR_ID, CLCL_PA_ACCT_NO, RJCT_REAS, UPDT_DTM
        )
        SELECT
            CLCL.CLCL_ID, CLCL.MEME_CK, CLCL.CLCL_SUB_TYPE, CLCL.CLCL_TOT_CHG,
            CLCL.PRPR_ID, CLCL.CLCL_PA_ACCT_NO,
            CASE CLCL.CLCL_CUR_STS
                WHEN '11' THEN 'Invalid member details submitted on claim'
                WHEN '12' THEN 'Invalid Provider details submiteed on claim'
                WHEN '13' THEN 'Service Span dates are not in same month and year'
                WHEN '14' THEN 'Provider Tax ID is incorrect for submitted Claim'
            END,
            GETDATE()
        FROM FACETS_STG.dbo.STG_CMC_CLCL CLCL
        WHERE CLCL.CLCL_CUR_STS IN ('11','12','13','14')
          AND NOT EXISTS
          (
              SELECT 1 FROM dbo.CW_RJCT_CLCL RJCT WHERE RJCT.CLCL_ID = CLCL.CLCL_ID
          );

        SELECT @ROWS_PROCESSED = @@ROWCOUNT, @STATUS_DESC = @STEP_DESC + ' COMPLETED', @STATUS = 'C';

        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID = @RUN_ID, @JOB_ID = @JOB_ID, @STATUS_DESC = @STATUS_DESC,
             @SYS_DEF_MSG = @SYS_DEF_MSG, @STEP_ID = @STEP_ID, @SP_NAME = @SP_NAME,
             @ERROR = @ERROR, @ROWS_PROCESSED = @ROWS_PROCESSED, @STATUS = @STATUS;

        /* =========================================================
           STEP 4 - LOAD ACCEPTED CLAIM HEADERS TO CORE
           Status 16 at this point means member, provider, service
           date, and tax ID all passed. Core status becomes 01.
           ========================================================= */
        SET @ROWS_PROCESSED = 0;
        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC = 'LOAD ACCEPTED CLAIM HEADERS TO CORE';

        INSERT INTO FACETS.dbo.CMC_CLCL
        (
            CLCL_ID, MEME_CK, MEME_ID, CLCL_SUB_TYPE, CLCL_TOT_CHG, CLCL_TOT_PAYABLE,
            CLCL_NTWK_IND, PRPR_ID, CLCL_CUR_STS, CLCL_LOW_SVC_DT, CLCL_HIGH_SVC_DT,
            CLCL_PA_ACCT_NO, CLCL_INPUT_DT
        )
        SELECT
            STG.CLCL_ID, STG.MEME_CK, STG.MEME_ID, STG.CLCL_SUB_TYPE, STG.CLCL_TOT_CHG,
            STG.CLCL_TOT_PAYABLE, STG.CLCL_NTWK_IND, STG.PRPR_ID,
            '01',
            STG.CLCL_LOW_SVC_DT, STG.CLCL_HIGH_SVC_DT, STG.CLCL_PA_ACCT_NO, STG.CLCL_INPUT_DT
        FROM FACETS_STG.dbo.STG_CMC_CLCL STG
        WHERE STG.CLCL_CUR_STS = '16'
          AND NOT EXISTS
          (
              SELECT 1 FROM FACETS.dbo.CMC_CLCL CORE WHERE CORE.CLCL_ID = STG.CLCL_ID
          );

        SELECT @ROWS_PROCESSED = @@ROWCOUNT, @STATUS_DESC = @STEP_DESC + ' COMPLETED', @STATUS = 'C';

        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID = @RUN_ID, @JOB_ID = @JOB_ID, @STATUS_DESC = @STATUS_DESC,
             @SYS_DEF_MSG = @SYS_DEF_MSG, @STEP_ID = @STEP_ID, @SP_NAME = @SP_NAME,
             @ERROR = @ERROR, @ROWS_PROCESSED = @ROWS_PROCESSED, @STATUS = @STATUS;

        /* =========================================================
           STEP 5 - LOAD ACCEPTED CLAIM DETAILS TO CORE
           ========================================================= */
        SET @ROWS_PROCESSED = 0;
        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC = 'LOAD ACCEPTED CLAIM DETAILS TO CORE';

        INSERT INTO FACETS.dbo.CMC_CDML
        (
            CLCL_ID, CDML_SEQ, CDML_SUB_TYPE, CDML_CHG_AMT, CDML_NTWK_IND,
            CDML_FROM_DT, CDML_TO_DT, CDML_ALLOW, CDML_DISALLOW, CDML_DISALLOW_EXCD,
            DIAG_CD, PROC_CD, PRPR_ID, CDML_CUR_STS, CDML_INPUT_DT
        )
        SELECT
            CDML.CLCL_ID, CDML.CDML_SEQ, CDML.CDML_SUB_TYPE, CDML.CDML_CHG_AMT, CDML.CDML_NTWK_IND,
            CDML.CDML_FROM_DT, CDML.CDML_TO_DT, CDML.CDML_ALLOW, CDML.CDML_DISALLOW, CDML.CDML_DISALLOW_EXCD,
            CDML.DIAG_CD, CDML.PROC_CD, CDML.PRPR_ID,
            '01',
            CDML.CDML_INPUT_DT
        FROM FACETS_STG.dbo.STG_CMC_CDML CDML
        INNER JOIN FACETS_STG.dbo.STG_CMC_CLCL CLCL
            ON CDML.CLCL_ID = CLCL.CLCL_ID
        WHERE CLCL.CLCL_CUR_STS = '16'
          AND NOT EXISTS
          (
              SELECT 1 FROM FACETS.dbo.CMC_CDML CORE
              WHERE CORE.CLCL_ID = CDML.CLCL_ID AND CORE.CDML_SEQ = CDML.CDML_SEQ
          );

        SELECT @ROWS_PROCESSED = @@ROWCOUNT, @STATUS_DESC = @STEP_DESC + ' COMPLETED', @STATUS = 'C';

        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID = @RUN_ID, @JOB_ID = @JOB_ID, @STATUS_DESC = @STATUS_DESC,
             @SYS_DEF_MSG = @SYS_DEF_MSG, @STEP_ID = @STEP_ID, @SP_NAME = @SP_NAME,
             @ERROR = @ERROR, @ROWS_PROCESSED = @ROWS_PROCESSED, @STATUS = @STATUS;

        /* =========================================================
           STEP 6 - DELETE STG_CMC_CLPR (accepted + business rejected)
           ========================================================= */
        SET @ROWS_PROCESSED = 0;
        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC = 'DELETE PROCESSED PROVIDER DATA FROM STAGING';

        DELETE CLPR
        FROM FACETS_STG.dbo.STG_CMC_CLPR CLPR
        INNER JOIN FACETS_STG.dbo.STG_CMC_CLCL CLCL
            ON CLPR.CLCL_ID = CLCL.CLCL_ID
        WHERE CLCL.CLCL_CUR_STS IN ('11','12','13','14','16');

        SELECT @ROWS_PROCESSED = @@ROWCOUNT, @STATUS_DESC = @STEP_DESC + ' COMPLETED', @STATUS = 'C';

        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID = @RUN_ID, @JOB_ID = @JOB_ID, @STATUS_DESC = @STATUS_DESC,
             @SYS_DEF_MSG = @SYS_DEF_MSG, @STEP_ID = @STEP_ID, @SP_NAME = @SP_NAME,
             @ERROR = @ERROR, @ROWS_PROCESSED = @ROWS_PROCESSED, @STATUS = @STATUS;

        /* =========================================================
           STEP 7 - DELETE STG_CMC_MEME
           ========================================================= */
        SET @ROWS_PROCESSED = 0;
        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC = 'DELETE PROCESSED MEMBER DATA FROM STAGING';

        DELETE MEME
        FROM FACETS_STG.dbo.STG_CMC_MEME MEME
        INNER JOIN FACETS_STG.dbo.STG_CMC_CLCL CLCL
            ON MEME.CLCL_ID = CLCL.CLCL_ID
        WHERE CLCL.CLCL_CUR_STS IN ('11','12','13','14','16');

        SELECT @ROWS_PROCESSED = @@ROWCOUNT, @STATUS_DESC = @STEP_DESC + ' COMPLETED', @STATUS = 'C';

        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID = @RUN_ID, @JOB_ID = @JOB_ID, @STATUS_DESC = @STATUS_DESC,
             @SYS_DEF_MSG = @SYS_DEF_MSG, @STEP_ID = @STEP_ID, @SP_NAME = @SP_NAME,
             @ERROR = @ERROR, @ROWS_PROCESSED = @ROWS_PROCESSED, @STATUS = @STATUS;

        /* =========================================================
           STEP 8 - DELETE CLAIM DETAIL FROM STAGING
           ========================================================= */
        SET @ROWS_PROCESSED = 0;
        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC = 'DELETE PROCESSED CLAIM DETAILS FROM STAGING';

        DELETE CDML
        FROM FACETS_STG.dbo.STG_CMC_CDML CDML
        INNER JOIN FACETS_STG.dbo.STG_CMC_CLCL CLCL
            ON CDML.CLCL_ID = CLCL.CLCL_ID
        WHERE CLCL.CLCL_CUR_STS IN ('11','12','13','14','16');

        SELECT @ROWS_PROCESSED = @@ROWCOUNT, @STATUS_DESC = @STEP_DESC + ' COMPLETED', @STATUS = 'C';

        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID = @RUN_ID, @JOB_ID = @JOB_ID, @STATUS_DESC = @STATUS_DESC,
             @SYS_DEF_MSG = @SYS_DEF_MSG, @STEP_ID = @STEP_ID, @SP_NAME = @SP_NAME,
             @ERROR = @ERROR, @ROWS_PROCESSED = @ROWS_PROCESSED, @STATUS = @STATUS;

        /* =========================================================
           STEP 9 - DELETE CLAIM HEADERS FROM STAGING (keep status 15)
           ========================================================= */
        SET @ROWS_PROCESSED = 0;
        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC = 'DELETE PROCESSED CLAIM HEADERS FROM STAGING';

        DELETE FROM FACETS_STG.dbo.STG_CMC_CLCL
        WHERE CLCL_CUR_STS IN ('11','12','13','14','16');

        SELECT @ROWS_PROCESSED = @@ROWCOUNT, @STATUS_DESC = @STEP_DESC + ' COMPLETED', @STATUS = 'C';

        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID = @RUN_ID, @JOB_ID = @JOB_ID, @STATUS_DESC = @STATUS_DESC,
             @SYS_DEF_MSG = @SYS_DEF_MSG, @STEP_ID = @STEP_ID, @SP_NAME = @SP_NAME,
             @ERROR = @ERROR, @ROWS_PROCESSED = @ROWS_PROCESSED, @STATUS = @STATUS;

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH

        SELECT
            @ERROR = ERROR_NUMBER(),
            @SYS_DEF_MSG = ERROR_MESSAGE(),
            @STATUS_DESC = ISNULL(@STEP_DESC, 'STAGE TO CORE CLAIM LOAD') + ' FAILED.',
            @STATUS = 'E';

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID = @RUN_ID, @JOB_ID = @JOB_ID, @STATUS_DESC = @STATUS_DESC,
             @SYS_DEF_MSG = @SYS_DEF_MSG, @STEP_ID = @STEP_ID, @SP_NAME = @SP_NAME,
             @ERROR = @ERROR, @ROWS_PROCESSED = @ROWS_PROCESSED, @STATUS = @STATUS;

        THROW;

    END CATCH;

END
GO
