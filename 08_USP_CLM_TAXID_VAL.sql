/* =====================================================================
   08_USP_CLM_TAXID_VAL.sql
   =====================================================================
   Validates that the tax ID submitted on the claim (for whichever
   provider actually got matched in USP_CLM_PRPR_MTCH) agrees with
   the tax ID on file for that provider (CMC_PRPR.MCTN_ID). Mismatch
   -> rejects the claim with status 14.

   Note: the join on CLPR.CLPR_NPI = PRPR.PRPR_NPI naturally narrows
   to whichever submitted provider row (billing/85 or servicing/77)
   was the one actually matched - no separate CLPR_TYPE filter is
   needed for that.
   ===================================================================== */

USE [FACETS_Custom]
GO

CREATE OR ALTER PROCEDURE [dbo].[USP_CLM_TAXID_VAL]
AS
/* EXEC [DBO].[USP_CLM_TAXID_VAL] */
BEGIN
	SET NOCOUNT ON;

	DECLARE
	@RUN_ID				INT				= (SELECT ISNULL(MAX(RUN_ID),0) FROM dbo.CLM_JOB_STEP_LOG WITH(NOLOCK)),
	@JOB_ID				VARCHAR(255)	= 'CLCL_PROCESSING',
	@ERRRO_MSG			VARCHAR(255),
	@ERR_DTM			DATETIME,
	@ERROR				INT				= 0,
	@STEP_ID			INT				= 0,
	@USER_DEF_MSG		VARCHAR(5000),
	@SYS_DEF_MSG		VARCHAR(5000),
	@SP_START_DTM		DATETIME		= GETDATE(),
	@SP_NAME			VARCHAR(255)	= (SELECT OBJECT_NAME(@@PROCID)),
	@ROWS_PROCESSED		INT				= 0,
	@STEP_DESC			VARCHAR(255),
	@STATUS_DESC		VARCHAR(255),
	@STATUS				VARCHAR(1),
	@EMPTY_STRING		VARCHAR(1)		= '',
	@COMPLETION_STATUS	VARCHAR(255)	= 'C'

	BEGIN TRANSACTION;
	BEGIN TRY

		SET @RUN_ID = @RUN_ID + 1

		SET @STEP_ID	= @STEP_ID + 1
		SET @STEP_DESC	= 'INSERT REJECTED DATA INTO TEMP TABLE FOR Provider Tax ID verification process'

		IF OBJECT_ID('#InvalidClaims') IS NOT NULL
		DROP TABLE #InvalidClaims;

		SELECT
		    CLCL.CLCL_ID,
		    CLCL.PRPR_ID,
		    PRPR.PRPR_NPI,
		    CLPR.CLPR_TAX,
		    PRPR.MCTN_ID,
			CLCL.MEME_CK,
			CLCL.CLCL_SUB_TYPE,
			CLCL.CLCL_TOT_CHG,
			CLCL.CLCL_PA_ACCT_NO
		INTO #InvalidClaims
		FROM FACETS_STG..STG_CMC_CLCL CLCL
		INNER JOIN FACETS..CMC_PRPR PRPR
		    ON CLCL.PRPR_ID = PRPR.PRPR_ID
		INNER JOIN FACETS_STG..STG_CMC_CLPR CLPR
		    ON CLPR.CLCL_ID = CLCL.CLCL_ID
		   AND CLPR.CLPR_NPI = PRPR.PRPR_NPI
		WHERE
		    CLCL.CLCL_CUR_STS = '16'
		    AND ISNULL(CLCL.MEME_ID, 0) <> 0
		    AND ISNULL(CLCL.PRPR_ID, '') <> ''
		    AND ISNULL(CLPR.CLPR_TAX, '') <> ''
		    AND ISNULL(PRPR.MCTN_ID, '') <> ''
		    AND CLPR.CLPR_TAX <> PRPR.MCTN_ID;					-- Tax ID mismatch condition

		SELECT @ROWS_PROCESSED	= @@ROWCOUNT,
			   @STATUS_DESC		= @STEP_DESC + ' COMPLETED',
			   @STATUS			= 'C'

		EXEC DBO.USP_CLM_STEP_ERR_LOG @RUN_ID			= @RUN_ID,
									  @JOB_ID			= @JOB_ID,
									  @STATUS_DESC		= @STATUS_DESC,
									  @SYS_DEF_MSG		= @SYS_DEF_MSG,
									  @STEP_ID			= @STEP_ID,
									  @SP_NAME			= @SP_NAME,
									  @ERROR			= @ERROR,
									  @ROWS_PROCESSED	= @ROWS_PROCESSED,
									  @STATUS			= @STATUS

		SET @ROWS_PROCESSED	= 0
		SET @STEP_ID		= @STEP_ID + 1
		SET @STEP_DESC		= 'Update claim status for invalid claims in CLCL table'

		UPDATE CLCL
		SET CLCL_CUR_STS = '14'
		FROM FACETS_STG..STG_CMC_CLCL CLCL
		INNER JOIN #InvalidClaims IC
		    ON CLCL.CLCL_ID = IC.CLCL_ID;

		SELECT @ROWS_PROCESSED	= @@ROWCOUNT,
			   @STATUS_DESC		= @STEP_DESC + ' COMPLETED',
			   @STATUS			= 'C'

		EXEC DBO.USP_CLM_STEP_ERR_LOG @RUN_ID			= @RUN_ID,
									  @JOB_ID			= @JOB_ID,
									  @STATUS_DESC		= @STATUS_DESC,
									  @SYS_DEF_MSG		= @SYS_DEF_MSG,
									  @STEP_ID			= @STEP_ID,
									  @SP_NAME			= @SP_NAME,
									  @ERROR			= @ERROR,
									  @ROWS_PROCESSED	= @ROWS_PROCESSED,
									  @STATUS			= @STATUS

		SET @ROWS_PROCESSED	= 0
		SET @STEP_ID		= @STEP_ID + 1
		SET @STEP_DESC		= 'Update claim status for invalid claims in CDML table'

		UPDATE CDML
		SET CDML_CUR_STS = '14'
		FROM FACETS_STG..STG_CMC_CDML CDML
		INNER JOIN #InvalidClaims IC
		    ON CDML.CLCL_ID = IC.CLCL_ID;

		SELECT @ROWS_PROCESSED	= @@ROWCOUNT,
			   @STATUS_DESC		= @STEP_DESC + ' COMPLETED',
			   @STATUS			= 'C'

		EXEC DBO.USP_CLM_STEP_ERR_LOG @RUN_ID			= @RUN_ID,
									  @JOB_ID			= @JOB_ID,
									  @STATUS_DESC		= @STATUS_DESC,
									  @SYS_DEF_MSG		= @SYS_DEF_MSG,
									  @STEP_ID			= @STEP_ID,
									  @SP_NAME			= @SP_NAME,
									  @ERROR			= @ERROR,
									  @ROWS_PROCESSED	= @ROWS_PROCESSED,
									  @STATUS			= @STATUS

		SET @ROWS_PROCESSED	= 0
		SET @STEP_ID		= @STEP_ID + 1
		SET @STEP_DESC		= 'Log rejected claims into REJECTS table'

		INSERT INTO dbo.CW_RJCT_CLCL
		(
			CLCL_ID,
			MEME_CK,
			CLCL_SUB_TYPE,
			CLCL_TOT_CHG,
			PRPR_ID,
			CLCL_PA_ACCT_NO,
			RJCT_REAS,
			UPDT_DTM
		)
		SELECT DISTINCT
			CLCL_ID,
			MEME_CK,
			CLCL_SUB_TYPE,
			CLCL_TOT_CHG,
			PRPR_ID,
			CLCL_PA_ACCT_NO,
			'Provider Tax ID is incorrect for submitted provider',
			GETDATE()
		FROM #InvalidClaims

		SELECT @ROWS_PROCESSED	= @@ROWCOUNT,
			   @STATUS_DESC		= @STEP_DESC + ' COMPLETED',
			   @STATUS			= 'C'

		EXEC DBO.USP_CLM_STEP_ERR_LOG @RUN_ID			= @RUN_ID,
									  @JOB_ID			= @JOB_ID,
									  @STATUS_DESC		= @STATUS_DESC,
									  @SYS_DEF_MSG		= @SYS_DEF_MSG,
									  @STEP_ID			= @STEP_ID,
									  @SP_NAME			= @SP_NAME,
									  @ERROR			= @ERROR,
									  @ROWS_PROCESSED	= @ROWS_PROCESSED,
									  @STATUS			= @STATUS

		COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH

		SELECT @ERROR			= ERROR_NUMBER(),
			   @SYS_DEF_MSG		= ERROR_MESSAGE(),
			   @STATUS_DESC		= @STEP_DESC + ' FAILED.',
			   @STATUS			= 'E'

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

  		EXEC DBO.USP_CLM_STEP_ERR_LOG @RUN_ID			= @RUN_ID,
									  @JOB_ID			= @JOB_ID,
									  @STATUS_DESC		= @STATUS_DESC,
									  @SYS_DEF_MSG		= @SYS_DEF_MSG,
									  @STEP_ID			= @STEP_ID,
									  @SP_NAME			= @SP_NAME,
									  @ERROR			= @ERROR,
									  @ROWS_PROCESSED	= @ROWS_PROCESSED,
									  @STATUS			= @STATUS

    END CATCH;

END
GO
