/* =====================================================================
   09_USP_CLM_SVCDT_VAL.sql
   =====================================================================
   Validates that all service lines on a claim fall within the same
   calendar month and year. Mismatch -> rejects the claim with status
   13. Only evaluates claims that already have a matched member and
   provider (per the requirement that unmatched/already-rejected
   claims are not re-evaluated).

   ===================================================================== */

USE [FACETS_Custom]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[USP_CLM_SVCDT_VAL]
AS
/* Execution Call - EXEC [dbo].[USP_CLM_SVCDT_VAL] */
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

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
	@completion_status	VARCHAR(255)	= 'C'

	BEGIN TRANSACTION;
	BEGIN TRY

		SET @run_id = @run_id + 1

		SET @step_id	= @step_id + 1
		SET @step_desc	= 'INSERT REJECTED CLAIMS DATA INTO TEMP TABLE FOR SERVICE DATES VALIDATION'

		DROP TABLE IF EXISTS #TMP_SVCDT_VAL

		CREATE TABLE #TMP_SVCDT_VAL
		(
			CLCL_ID VARCHAR(10) NULL,
			CLCL_SUB_TYPE VARCHAR(1),
			CLCL_TOT_CHG MONEY,
			MEME_CK INT,
			PRPR_ID VARCHAR(10) NULL,
			CLCL_PA_ACCT_NO VARCHAR(7),
			RJCT_REAS VARCHAR(255)
		)

		INSERT INTO #TMP_SVCDT_VAL
		(
			CLCL_ID,
			CLCL_SUB_TYPE,
			CLCL_TOT_CHG,
			MEME_CK,
			PRPR_ID,
			CLCL_PA_ACCT_NO,
			RJCT_REAS
		)
		SELECT
			CLCL.CLCL_ID,
			CLCL_SUB_TYPE,
			CLCL_TOT_CHG,
			MEME_CK,
			CLCL.PRPR_ID,
			CLCL_PA_ACCT_NO,
			'Service dates are not in same month and year for all the lines'
		FROM FACETS_STG.dbo.STG_CMC_CLCL CLCL
		WHERE CLCL_CUR_STS = '16'
		  AND ISNULL(CLCL.MEME_CK, 0) <> 0
		  AND ISNULL(CLCL.PRPR_ID, '') <> ''
		  AND CLCL.CLCL_ID IN (
								SELECT
									CLCL_ID
								FROM FACETS_STG.dbo.STG_CMC_CDML
								WHERE CDML_CUR_STS = '16' AND
								(MONTH(CDML_FROM_DT) <> MONTH(CDML_TO_DT) OR YEAR(CDML_FROM_DT) <> YEAR(CDML_TO_DT))
								UNION
								SELECT
									CLCL_ID
								FROM FACETS_STG.dbo.STG_CMC_CDML
								WHERE CDML_CUR_STS = '16'
								GROUP BY CLCL_ID
								HAVING COUNT(DISTINCT CONCAT(YEAR(CDML_FROM_DT),'-',MONTH(CDML_FROM_DT)))>1
								OR COUNT(DISTINCT CONCAT(YEAR(CDML_TO_DT),'-',MONTH(CDML_TO_DT)))>1
							)

		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status

		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'UPDATE STG_CLCL_TABLE WITH CURRENT STATUS '

		UPDATE CLCL
		SET
			CLCL_CUR_STS	= '13'
		FROM FACETS_STG.dbo.STG_CMC_CLCL CLCL
		JOIN #TMP_SVCDT_VAL SVC ON CLCL.CLCL_ID = SVC.CLCL_ID

		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status

		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'UPDATE STG_CDML TABLE WITH CURRENT STATUS'

		UPDATE CDML
		SET
			CDML_CUR_STS	= '13'
		FROM FACETS_STG.dbo.STG_CMC_CDML CDML
		JOIN #TMP_SVCDT_VAL SVC ON CDML.CLCL_ID = SVC.CLCL_ID

		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status

		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'INSERT REJECTED CLAIMS INTO CW_RJCT_CLCL TABLE'

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
			RJCT_REAS,
			GETDATE()
		FROM #TMP_SVCDT_VAL
		WHERE CLCL_ID NOT IN (SELECT CLCL_ID FROM dbo.CW_RJCT_CLCL)

		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'

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
