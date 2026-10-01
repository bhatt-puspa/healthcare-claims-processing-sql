/* =====================================================================
   07_USP_CLM_PRPR_MTCH.sql
   =====================================================================
   Matches the provider NPI submitted on a claim against the real
   CMC_PRPR master list. Checks the billing provider (CLPR_TYPE = '85')
   first; if that doesn't match, falls back to the servicing provider
   (CLPR_TYPE = '77'). No match on either -> rejects with status 12.

   CREATED BY   - Puspa Bhatt

   ===================================================================== */

USE [FACETS_Custom]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[USP_CLM_PRPR_MTCH]
AS
BEGIN

	/*  DECLARE LOCAL VARIABLES */
	DECLARE
	@run_id				INT				= (SELECT ISNULL(MAX(RUN_ID),0) FROM dbo.CLM_JOB_STEP_LOG WITH(NOLOCK)),
	@job_id				VARCHAR(255)	= 'CLCL_PROCESSING',
	@sys_def_msg		VARCHAR(5000),
	@error				INT				= 0,
	@step_id			INT				= 0,
	@sp_name			VARCHAR(255)	= (SELECT OBJECT_NAME(@@PROCID)),
	@rows_processed		INT				= 0,
	@step_desc			VARCHAR(255),
	@status_desc		VARCHAR(255),
	@status				VARCHAR(1)

	BEGIN TRANSACTION;
	BEGIN TRY

		SET @run_id = @run_id + 1

		---------------------------------------------------------------------
		-- STEP 1: FIND CLAIMS ELIGIBLE FOR PROVIDER MATCH
		--   Still at status 16 (submitted) AND provider not yet matched
		--   (PRPR_ID still NULL). This naturally skips claims already
		--   rejected by member match (status 11) or a prior provider
		--   match run, satisfying "don't re-evaluate rejected claims."
		---------------------------------------------------------------------
		SET @step_id	= @step_id + 1
		SET @step_desc	= 'IDENTIFY CLAIMS ELIGIBLE FOR PROVIDER MATCH'

		DROP TABLE IF EXISTS #ELIGIBLE_CLAIMS
		CREATE TABLE #ELIGIBLE_CLAIMS
		(
			CLCL_ID			VARCHAR(10),
			MEME_CK			INT,
			CLCL_SUB_TYPE	VARCHAR(1),
			CLCL_TOT_CHG	MONEY,
			CLCL_PA_ACCT_NO	VARCHAR(7)
		)

		INSERT INTO #ELIGIBLE_CLAIMS (CLCL_ID, MEME_CK, CLCL_SUB_TYPE, CLCL_TOT_CHG, CLCL_PA_ACCT_NO)
		SELECT CLCL_ID, MEME_CK, CLCL_SUB_TYPE, CLCL_TOT_CHG, CLCL_PA_ACCT_NO
		FROM FACETS_STG.dbo.STG_CMC_CLCL
		WHERE CLCL_CUR_STS = '16'
		  AND PRPR_ID IS NULL

		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id=@run_id, @job_id=@job_id, @status_desc=@status_desc,
			@sys_def_msg=@sys_def_msg, @step_id=@step_id, @sp_name=@sp_name, @error=@error,
			@rows_processed=@rows_processed, @status=@status

		---------------------------------------------------------------------
		-- STEP 2: TRY TO MATCH THE BILLING PROVIDER (CLPR_TYPE = '85') FIRST
		--   NPI is trimmed on both sides so leading/trailing spaces in the
		--   submitted data (same data-quality issue seen in member match)
		--   don't cause a valid provider to be missed.
		---------------------------------------------------------------------
		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'MATCH BILLING PROVIDER (TYPE 85) AGAINST MASTER DATA'

		DROP TABLE IF EXISTS #MATCHED_85
		CREATE TABLE #MATCHED_85
		(
			CLCL_ID		VARCHAR(10),
			PRPR_ID		VARCHAR(10)
		)

		INSERT INTO #MATCHED_85 (CLCL_ID, PRPR_ID)
		SELECT E.CLCL_ID, PRPR.PRPR_ID
		FROM #ELIGIBLE_CLAIMS E
		JOIN FACETS_STG.dbo.STG_CMC_CLPR CLPR ON E.CLCL_ID = CLPR.CLCL_ID AND CLPR.CLPR_TYPE = '85'
		JOIN FACETS.dbo.CMC_PRPR PRPR ON LTRIM(RTRIM(CLPR.CLPR_NPI)) = LTRIM(RTRIM(PRPR.PRPR_NPI))

		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id=@run_id, @job_id=@job_id, @status_desc=@status_desc,
			@sys_def_msg=@sys_def_msg, @step_id=@step_id, @sp_name=@sp_name, @error=@error,
			@rows_processed=@rows_processed, @status=@status

		---------------------------------------------------------------------
		-- STEP 3: FOR ANY CLAIM NOT MATCHED ON TYPE 85, TRY THE SERVICING
		--   PROVIDER (CLPR_TYPE = '77') AS A FALLBACK.
		--   The NOT IN (#MATCHED_85) filter is what enforces the priority:
		--   a claim that already matched on 85 is never re-evaluated here,
		--   so 85 always wins when both providers happen to match.
		---------------------------------------------------------------------
		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'MATCH SERVICING PROVIDER (TYPE 77) AS FALLBACK'

		DROP TABLE IF EXISTS #MATCHED_77
		CREATE TABLE #MATCHED_77
		(
			CLCL_ID		VARCHAR(10),
			PRPR_ID		VARCHAR(10)
		)

		INSERT INTO #MATCHED_77 (CLCL_ID, PRPR_ID)
		SELECT E.CLCL_ID, PRPR.PRPR_ID
		FROM #ELIGIBLE_CLAIMS E
		JOIN FACETS_STG.dbo.STG_CMC_CLPR CLPR ON E.CLCL_ID = CLPR.CLCL_ID AND CLPR.CLPR_TYPE = '77'
		JOIN FACETS.dbo.CMC_PRPR PRPR ON LTRIM(RTRIM(CLPR.CLPR_NPI)) = LTRIM(RTRIM(PRPR.PRPR_NPI))
		WHERE E.CLCL_ID NOT IN (SELECT CLCL_ID FROM #MATCHED_85)

		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id=@run_id, @job_id=@job_id, @status_desc=@status_desc,
			@sys_def_msg=@sys_def_msg, @step_id=@step_id, @sp_name=@sp_name, @error=@error,
			@rows_processed=@rows_processed, @status=@status

		---------------------------------------------------------------------
		-- STEP 4: COMBINE BOTH MATCH SETS INTO ONE RESULT LIST
		---------------------------------------------------------------------
		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'COMBINE MATCHED PROVIDERS FROM BOTH PRIORITY LEVELS'

		DROP TABLE IF EXISTS #ALL_MATCHES
		CREATE TABLE #ALL_MATCHES
		(
			CLCL_ID		VARCHAR(10),
			PRPR_ID		VARCHAR(10)
		)

		INSERT INTO #ALL_MATCHES (CLCL_ID, PRPR_ID)
		SELECT CLCL_ID, PRPR_ID FROM #MATCHED_85
		UNION ALL
		SELECT CLCL_ID, PRPR_ID FROM #MATCHED_77

		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id=@run_id, @job_id=@job_id, @status_desc=@status_desc,
			@sys_def_msg=@sys_def_msg, @step_id=@step_id, @sp_name=@sp_name, @error=@error,
			@rows_processed=@rows_processed, @status=@status

		---------------------------------------------------------------------
		-- STEP 5: UPDATE STG_CMC_CLCL WITH THE MATCHED PROVIDER ID
		---------------------------------------------------------------------
		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'UPDATE STG_CMC_CLCL WITH MATCHED PROVIDER ID'

		UPDATE CLCL
		SET CLCL.PRPR_ID = M.PRPR_ID
		FROM FACETS_STG.dbo.STG_CMC_CLCL CLCL
		JOIN #ALL_MATCHES M ON CLCL.CLCL_ID = M.CLCL_ID

		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id=@run_id, @job_id=@job_id, @status_desc=@status_desc,
			@sys_def_msg=@sys_def_msg, @step_id=@step_id, @sp_name=@sp_name, @error=@error,
			@rows_processed=@rows_processed, @status=@status

		---------------------------------------------------------------------
		-- STEP 6: BUILD THE LIST OF UNMATCHED (REJECTED) CLAIMS
		--   Anything eligible that didn't land in #ALL_MATCHES failed both
		--   the 85 and 77 checks.
		---------------------------------------------------------------------
		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'BUILD LIST OF CLAIMS WITH NO PROVIDER MATCH'

		DROP TABLE IF EXISTS #UNMATCHED_CLAIMS
		CREATE TABLE #UNMATCHED_CLAIMS
		(
			CLCL_ID			VARCHAR(10),
			MEME_CK			INT,
			CLCL_SUB_TYPE	VARCHAR(1),
			CLCL_TOT_CHG	MONEY,
			CLCL_PA_ACCT_NO	VARCHAR(7)
		)

		INSERT INTO #UNMATCHED_CLAIMS (CLCL_ID, MEME_CK, CLCL_SUB_TYPE, CLCL_TOT_CHG, CLCL_PA_ACCT_NO)
		SELECT CLCL_ID, MEME_CK, CLCL_SUB_TYPE, CLCL_TOT_CHG, CLCL_PA_ACCT_NO
		FROM #ELIGIBLE_CLAIMS
		WHERE CLCL_ID NOT IN (SELECT CLCL_ID FROM #ALL_MATCHES)

		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id=@run_id, @job_id=@job_id, @status_desc=@status_desc,
			@sys_def_msg=@sys_def_msg, @step_id=@step_id, @sp_name=@sp_name, @error=@error,
			@rows_processed=@rows_processed, @status=@status

		---------------------------------------------------------------------
		-- STEP 7: UPDATE HEADER STATUS TO 12 (PROVIDER NOT FOUND) FOR REJECTS
		---------------------------------------------------------------------
		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'UPDATE STG_CMC_CLCL STATUS TO 12 FOR UNMATCHED CLAIMS'

		UPDATE CLCL
		SET CLCL.CLCL_CUR_STS = '12'
		FROM FACETS_STG.dbo.STG_CMC_CLCL CLCL
		JOIN #UNMATCHED_CLAIMS U ON CLCL.CLCL_ID = U.CLCL_ID

		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id=@run_id, @job_id=@job_id, @status_desc=@status_desc,
			@sys_def_msg=@sys_def_msg, @step_id=@step_id, @sp_name=@sp_name, @error=@error,
			@rows_processed=@rows_processed, @status=@status

		---------------------------------------------------------------------
		-- STEP 8: UPDATE ALL LINES OF THOSE CLAIMS TO 12 AS WELL
		---------------------------------------------------------------------
		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'UPDATE STG_CMC_CDML STATUS TO 12 FOR UNMATCHED CLAIMS'

		UPDATE CDML
		SET CDML.CDML_CUR_STS = '12'
		FROM FACETS_STG.dbo.STG_CMC_CDML CDML
		JOIN #UNMATCHED_CLAIMS U ON CDML.CLCL_ID = U.CLCL_ID

		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id=@run_id, @job_id=@job_id, @status_desc=@status_desc,
			@sys_def_msg=@sys_def_msg, @step_id=@step_id, @sp_name=@sp_name, @error=@error,
			@rows_processed=@rows_processed, @status=@status

		---------------------------------------------------------------------
		-- STEP 9: LOG THE UNMATCHED CLAIMS IN THE REJECT TABLE
		--   FIX: CW_RJCT_CLCL lives in FACETS_Custom (the database this
		--   procedure already runs in), not FACETS - reference corrected.
		---------------------------------------------------------------------
		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'INSERT UNMATCHED CLAIMS INTO CW_RJCT_CLCL'

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
			NULL,
			CLCL_PA_ACCT_NO,
			'PROVIDER NPI IS NOT MATCHING WITH MASTER DATA',
			GETDATE()
		FROM #UNMATCHED_CLAIMS

		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id=@run_id, @job_id=@job_id, @status_desc=@status_desc,
			@sys_def_msg=@sys_def_msg, @step_id=@step_id, @sp_name=@sp_name, @error=@error,
			@rows_processed=@rows_processed, @status=@status

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH

		SELECT @error			= ERROR_NUMBER(),
			   @sys_def_msg		= ERROR_MESSAGE(),
			   @status_desc		= @step_desc + ' Failed.',
			   @status			= 'E'

		IF @@TRANCOUNT > 0
			ROLLBACK TRANSACTION;

		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id=@run_id, @job_id=@job_id, @status_desc=@status_desc,
			@sys_def_msg=@sys_def_msg, @step_id=@step_id, @sp_name=@sp_name, @error=@error,
			@rows_processed=@rows_processed, @status=@status

	END CATCH;

END
GO
