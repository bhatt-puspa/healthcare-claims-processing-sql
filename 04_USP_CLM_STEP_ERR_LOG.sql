/* =====================================================================
   04_USP_CLM_STEP_ERR_LOG.sql
   =====================================================================
   Shared logging procedure. Every other procedure in this project
   calls this once per step to write an audit trail row, and again
   with @ERROR <> 0 to log an error if the step failed.

   CREATED BY   - Puspa Bhatt
   ===================================================================== */

USE [FACETS_Custom]
GO

CREATE OR ALTER PROCEDURE [dbo].[USP_CLM_STEP_ERR_LOG]
(
	@RUN_ID			INT,
	@JOB_ID			VARCHAR(255),
	@STATUS_DESC	VARCHAR(255),
	@SYS_DEF_MSG	VARCHAR(5000),
	@STEP_ID		INT,
	@SP_NAME		VARCHAR(255),
	@ERROR			INT,
	@ROWS_PROCESSED	INT,
	@STATUS			VARCHAR(50)
)
AS
BEGIN
	BEGIN
		INSERT INTO dbo.CLM_JOB_STEP_LOG
		(
			RUN_ID,
			JOB_ID,
			SP_NAME,
			STEP_ID,
			STEP_DESC,
			STATUS,
			STEP_DTM,
			ROWS_PROCESSED
		)
		VALUES
		(
			@RUN_ID,
			@JOB_ID,
			@SP_NAME,
			@STEP_ID,
			@STATUS_DESC,
			@STATUS,
			GETDATE(),
			ISNULL(@ROWS_PROCESSED,0)
		)
	END

	/* INSERT INTO CLM_JOB_ERR_LOG TABLE IF FAILED */
	IF (@ERROR <> 0)
	BEGIN
		INSERT INTO dbo.CLM_JOB_ERR_LOG
		(
			RUN_ID,
			JOB_ID,
			USER_DEF_MSG,
			SYS_DEF_MSG,
			SP_NAME,
			STEP_ID,
			ERR_DTM
		)
		VALUES
		(
			@RUN_ID,
			@JOB_ID,
			@STATUS_DESC,
			@SYS_DEF_MSG,
			@SP_NAME,
			@STEP_ID,
			GETDATE()
		)
	END
END
GO
