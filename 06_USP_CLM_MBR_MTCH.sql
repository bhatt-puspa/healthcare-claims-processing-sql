/* =====================================================================
   06_USP_CLM_MBR_MTCH.sql
   =====================================================================
   Matches the member (patient) info submitted on a claim against the
   real CMC_MEME master list. Match -> stamps MEME_CK/MEME_ID onto the
   claim. No match -> rejects the claim with status 11.

   CREATED BY   - Puspa Bhatt

   ===================================================================== */

USE [FACETS_Custom]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[USP_CLM_MBR_MTCH]
AS
BEGIN

	/*  DECLARE LOCAL VARIABLES */
	DECLARE
	@run_id				INT				= (SELECT ISNULL(MAX(RUN_ID),0) FROM dbo.CLM_JOB_STEP_LOG WITH(NOLOCK)),
	@job_id				VARCHAR(255)	= 'CLCL_PROCESSING',
	@errro_msg			VARCHAR(255),
	@err_dtm			DATETIME,
	@error				INT				= 0,
	@step_id			INT				= 0,
	@user_def_msg		VARCHAR(5000),
	@sys_def_msg		VARCHAR(5000),
	@sp_start_dtm		DATETIME		= GETDATE(),
	@sp_name			VARCHAR(255)	= (SELECT OBJECT_NAME(@@PROCID)),
	@rows_processed		INT				= 0,
	@step_desc			VARCHAR(255),
	@status_desc		VARCHAR(255),
	@status				VARCHAR(1),
	@empty_string		VARCHAR(1)		= '',
	@completion_status	VARCHAR(255)	= 'C',
	@SequenceValue		INT,
	@CLCL_ID			VARCHAR(10)

	BEGIN TRANSACTION;
	BEGIN TRY

		SET @run_id = @run_id + 1

		---------------------------------------------------------------------
		-- STEP 1: TAKE ALL CLAIMS ELIGIBLE FOR MEMBER MATCH INTO A TEMP TABLE
		--   Eligible = still at status 16 (submitted) AND not yet matched
		--   (MEME_ID / MEME_CK are still NULL). This automatically prevents
		--   re-evaluating claims that have already been matched or rejected.
		---------------------------------------------------------------------
		SET @step_id	= @step_id + 1
		SET @step_desc	= 'TAKE ALL ELIGIBLE CLAIMS INTO TEMP TABLE'

		DROP TABLE IF EXISTS #MBR_DATA
		CREATE TABLE #MBR_DATA
		(
			CLCL_ID			VARCHAR(12),
			MEME_FIRST_NAME	VARCHAR(50),
			MEME_LAST_NAME	VARCHAR(50),
			BIRTH_DT		DATETIME,
			MEME_CK			INT,
			MEME_ID			INT,
			MATCH_STS		BIT,
			CLCL_SUB_TYPE	VARCHAR(1),
			CLCL_TOT_CHG	MONEY,
			PRPR_ID			VARCHAR(12),
			CLCL_PA_ACCT_NO	VARCHAR(7)
		)

		INSERT INTO #MBR_DATA
		(
			CLCL_ID,
			MEME_FIRST_NAME,
			MEME_LAST_NAME,
			BIRTH_DT,
			MATCH_STS,
			CLCL_SUB_TYPE,
			CLCL_TOT_CHG,
			PRPR_ID,
			CLCL_PA_ACCT_NO
		)
		SELECT
			CLCL.CLCL_ID,
			MEME.MEME_FIRST_NAME,
			MEME.MEME_LAST_NAME,
			MEME.BIRTH_DT,
			0,
			CLCL.CLCL_SUB_TYPE,
			CLCL.CLCL_TOT_CHG,
			CLCL.PRPR_ID,
			CLCL.CLCL_PA_ACCT_NO
		FROM FACETS_STG..STG_CMC_CLCL CLCL
		JOIN FACETS_STG..STG_CMC_MEME MEME ON CLCL.CLCL_ID = MEME.CLCL_ID
		WHERE CLCL.CLCL_CUR_STS = '16'
		AND (MEME_ID IS NULL OR MEME_CK IS NULL)

		/* Step Log - Setting completion status and description for step log */
		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		/* Execute dbo.USP_CLM_STEP_ERR_LOG Stored Procedure to insert step details and Error Details if Failed. */
		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status

		---------------------------------------------------------------------
		-- STEP 2: VALIDATE MEMBER INFORMATION AGAINST MASTER DATA
		--   LTRIM/RTRIM is applied to both sides of the FIRST_NAME and
		--   LAST_NAME comparison so that leading/trailing spaces in the
		--   submitted claim data (a realistic data-quality issue) do not
		--   cause a valid member to be missed. BIRTH_DT is a DATETIME
		--   comparison and is unaffected by whitespace, so no trim is
		--   needed there.
		---------------------------------------------------------------------
		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'VALIDATE MEMBER INFOMRATION WITH MASTER DATA AND UPDATE MATCH STATUS COLUMN'

		UPDATE M
		SET
			MATCH_STS = 1,
			MEME_CK	  = MEME.MEME_CK,
			MEME_ID	  = MEME.MEME_ID
		FROM #MBR_DATA M
		JOIN FACETS..CMC_MEME MEME
		  ON LTRIM(RTRIM(M.MEME_FIRST_NAME)) = LTRIM(RTRIM(MEME.FIRST_NAME))
		 AND LTRIM(RTRIM(M.MEME_LAST_NAME))  = LTRIM(RTRIM(MEME.LAST_NAME))
		 AND M.BIRTH_DT = MEME.BIRTH_DT

		/* Step Log - Setting completion status and description for step log */
		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		/* Execute dbo.USP_CLM_STEP_ERR_LOG Stored Procedure to insert step details and Error Details if Failed. */
		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status

		---------------------------------------------------------------------
		-- STEP 3: UPDATE CLAIM HEADER (STG_CMC_CLCL) BASED ON MATCH RESULT
		--   Matched  -> stamp MEME_CK / MEME_ID onto the claim
		--   Unmatched -> flip CLCL_CUR_STS to '11' (member not found)
		---------------------------------------------------------------------
		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'UPDATE CLAIM STATUS BASED ON MATCH INFORMATION'

		UPDATE CLCL
		SET
			CLCL.MEME_CK		= CASE
									WHEN MBR.MATCH_STS = 1 THEN MBR.MEME_CK
									ELSE CLCL.MEME_CK
								  END,
			CLCL.MEME_ID		= CASE
									WHEN MBR.MATCH_STS = 1 THEN MBR.MEME_ID
									ELSE CLCL.MEME_ID
								   END,
			CLCL.CLCL_CUR_STS	= CASE
									WHEN MBR.MATCH_STS = 0 THEN '11'
									ELSE CLCL.CLCL_CUR_STS
								   END
		FROM FACETS_STG.dbo.STG_CMC_CLCL CLCL
		JOIN #MBR_DATA MBR ON CLCL.CLCL_ID = MBR.CLCL_ID

		/* Step Log - Setting completion status and description for step log */
		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		/* Execute dbo.USP_CLM_STEP_ERR_LOG Stored Procedure to insert step details and Error Details if Failed. */
		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status

		---------------------------------------------------------------------
		-- STEP 4: UPDATE CLAIM LINES (STG_CMC_CDML) FOR UNMATCHED CLAIMS
		---------------------------------------------------------------------
		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'UPDATE CLAIM STATUS IN CDML TABLE'

		UPDATE CDML
		SET
			CDML.CDML_CUR_STS = '11'
		FROM FACETS_STG.dbo.STG_CMC_CDML CDML
		JOIN #MBR_DATA MBR ON CDML.CLCL_ID = MBR.CLCL_ID
		WHERE MATCH_STS = 0

		/* Step Log - Setting completion status and description for step log */
		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		/* Execute dbo.USP_CLM_STEP_ERR_LOG Stored Procedure to insert step details and Error Details if Failed. */
		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status

		---------------------------------------------------------------------
		-- STEP 5: INSERT UNMATCHED CLAIMS INTO THE REJECT TABLE FOR REPORTING
		--   FIX: CW_RJCT_CLCL lives in FACETS_Custom (the database this
		--   procedure already runs in), not FACETS - reference corrected.
		---------------------------------------------------------------------
		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'INSERT REJECTED CLAIMS INTO REJECT TABLE'

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
		SELECT
			CLCL_ID,
			MEME_CK,
			CLCL_SUB_TYPE,
			CLCL_TOT_CHG,
			PRPR_ID,
			CLCL_PA_ACCT_NO,
			'MEMBER DETAILS ARE NOT MATCHING WITH MASTER DATA',
			GETDATE()
		FROM #MBR_DATA
		WHERE MATCH_STS = 0

		/* Step Log - Setting completion status and description for step log */
		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		/* Execute dbo.USP_CLM_STEP_ERR_LOG Stored Procedure to insert step details and Error Details if Failed. */
		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status

		COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH

		SELECT @error			= ERROR_NUMBER(),
			   @sys_def_msg		= ERROR_MESSAGE(),
			   @status_desc		= @step_desc + ' Failed.',
			   @status			= 'E'

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

  		/* Execute dbo.USP_CLM_STEP_ERR_LOG Stored Procedure to insert step details and Error Details if Failed. */
		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status

    END CATCH;

END
GO
