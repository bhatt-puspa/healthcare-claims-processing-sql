/* =====================================================================
   11_USP_CLM_PYMT_PRCS.sql
   =====================================================================
   Applies per-line deduction percentages to a core claim, calculates
   CLCL_TOT_PAYABLE, and - if any reduction applies - creates an ACPR
   (payment reduction) record and a CLOV record. Updates claim status
   to 02 (paid) or 91 (fully disallowed).

   PREREQUISITE: run this once per database before deploying the
   procedure below (only needs to be done once, not every deploy):

   USE FACETS_Custom
   GO
   CREATE TYPE dbo.ClaimDetailType AS TABLE
   (
       CDML_SEQ INT,
       DEDUCTION_PCNTG DECIMAL(5,2)
   );
   GO

   (This is already included in 03_Create_Database_FACETS_Custom.sql.)

   Explanation code examples
   C04: Missing medical modifier          C11: Coding error
   C15: Missing or invalid authorization  C16: Error or lack of information
   C18: Duplicate claim/service           C22: Coordination of benefits error
   C27: Insurance/coverage expired        C29: Time limit expired
   C45: Excessive charges                 C50: Not medically necessary
   C97: Service already adjudicated       PR: Patient responsibility
   CR: Correction and reversals

   ===================================================================== */

USE [FACETS_Custom]
GO

CREATE OR ALTER PROCEDURE [dbo].[USP_CLM_PYMT_PRCS]
    @CLCL_ID VARCHAR(10),
    @ClaimDetails dbo.ClaimDetailType READONLY,
	@EXCD_ID VARCHAR(3)
AS

/*
DECLARE @ClaimDetails dbo.ClaimDetailType;
INSERT INTO @ClaimDetails (CDML_SEQ, DEDUCTION_PCNTG)
VALUES (1, 5.00) , (2,25.00)

EXEC [dbo].[USP_CLM_PYMT_PRCS] '25J0000066', @ClaimDetails, 'C45'
*/

BEGIN

	SET NOCOUNT ON;

	DECLARE
	@run_id				INT				= (SELECT ISNULL(MAX(RUN_ID),0) FROM dbo.CLM_JOB_STEP_LOG WITH(NOLOCK)),
	@job_id				VARCHAR(255)	= 'CLCL_PROCESSING',
	@errror_msg			VARCHAR(255),
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

    DECLARE @ClaimAmount MONEY;
    DECLARE @DeductedAmount MONEY;
    DECLARE @TotPayable MONEY;
	DECLARE @Acpr VARCHAR(10)

	IF EXISTS (SELECT 1 FROM FACETS.dbo.CMC_CLCL WHERE CLCL_ID = @CLCL_ID AND CLCL_CUR_STS <> '01')
	BEGIN
		SELECT 'CLAIM ALREADY PAID OR DENIED' AS ErrorMessage
		RETURN;
	END

    BEGIN TRANSACTION;
		BEGIN TRY

		SET @step_id		= @step_id + 1
		SET @step_desc		= 'UPDATE THE CDML AMOUNTS FOR ALL THE LINES THROUGH CURSOR'

		DECLARE @Seq INT;
		DECLARE @Percent DECIMAL(5, 2)

		DECLARE cur CURSOR FOR
		SELECT CDML_SEQ, DEDUCTION_PCNTG
		FROM @ClaimDetails;

		OPEN cur;
		FETCH NEXT FROM cur INTO @Seq, @Percent;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @ClaimAmount = NULL;	-- FIX: reset before each lookup so a non-matching
										-- CDML_SEQ can't silently reuse the previous
										-- iteration's charge amount

		    SELECT @ClaimAmount = CDML_CHG_AMT
		    FROM FACETS.dbo.CMC_CDML
		    WHERE CLCL_ID = @CLCL_ID
		      AND CDML_SEQ = @Seq;

			IF @ClaimAmount IS NULL		-- FIX: sequence didn't match a real line, skip it
			BEGIN
				FETCH NEXT FROM cur INTO @Seq, @Percent;
				CONTINUE;
			END

		    SET @DeductedAmount = @ClaimAmount * @Percent / 100.0;

		    UPDATE FACETS.dbo.CMC_CDML
		    SET CDML_ALLOW			= ISNULL(@ClaimAmount, 0) - @DeductedAmount,
		        CDML_DISALLOW		= @DeductedAmount,
				CDML_DISALLOW_EXCD	= @EXCD_ID
		    WHERE CLCL_ID = @CLCL_ID
		      AND CDML_SEQ = @Seq;

		    FETCH NEXT FROM cur INTO @Seq, @Percent;
		END

		CLOSE cur;
		DEALLOCATE cur;

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
		SET @step_desc		= 'UPDATE THE CLCL AMOUNTS FOR THE CLAIM AND INSERT ACPR DATA FOR REDUCTION CLAIMS'

		DECLARE @TOT_CHG MONEY
		DECLARE @TOT_DISALLOW MONEY
		DECLARE @TOT_ALLOW MONEY

		SELECT @TOT_CHG			= ISNULL(CLCL_TOT_CHG,0) FROM FACETS.dbo.CMC_CLCL WHERE CLCL_ID = @CLCL_ID
		SELECT @TOT_DISALLOW	= ISNULL(SUM(CDML_DISALLOW),0) FROM FACETS.dbo.CMC_CDML WHERE CLCL_ID = @CLCL_ID
		SELECT @TOT_ALLOW		= ISNULL(SUM(CDML_ALLOW),0) FROM FACETS.dbo.CMC_CDML WHERE CLCL_ID = @CLCL_ID

		IF (@TOT_CHG = @TOT_ALLOW)
		BEGIN
			UPDATE FACETS.dbo.CMC_CLCL
			SET
				CLCL_TOT_PAYABLE = @TOT_ALLOW
			WHERE CLCL_ID = @CLCL_ID
		END
		ELSE
		BEGIN

			UPDATE FACETS.dbo.CMC_CLCL
			SET
				CLCL_TOT_PAYABLE = CLCL_TOT_CHG - @TOT_DISALLOW
			WHERE CLCL_ID = @CLCL_ID

			SET @Acpr = 'ARI' + RIGHT(@CLCL_ID,7);	-- FIX: computed directly instead of
													-- inserting then re-querying it back

			INSERT INTO FACETS.dbo.CMC_ACPR
			(
				ACPR_REF_ID,
				ACPR_TYPE,
				ACPR_SUB_TYPE,
				ACPR_CREATE_DT,
				ACPR_PAYEE_ID,
				ACPR_STS,
				ACPR_ORIG_AMT,
				ACPR_NET_AMT,
				ACPR_RECOV_AMT,
				ACPR_WOFF_AMT,
				EXCD_ID
			)
			SELECT
				@Acpr,
				CASE
					WHEN @TOT_DISALLOW = @TOT_CHG THEN 'MO'
					WHEN @TOT_DISALLOW != @TOT_CHG THEN 'MR'
				END,
				CLCL_SUB_TYPE,
				GETDATE(),
				PRPR_ID,
				'A',								-- ACTIVE
				@TOT_DISALLOW,
				@TOT_DISALLOW,
				0,
				0,
				@EXCD_ID
			FROM FACETS.dbo.CMC_CLCL
			WHERE CLCL_ID = @CLCL_ID

			INSERT INTO FACETS.dbo.CMC_CLOV
			(
				ACPR_REF_ID,
				CLCL_ID,
				PRPR_ID,
				CLOV_AMT,
				CLOV_CREATE_DT
			)
			SELECT
				@Acpr,
				CLCL_ID,
				PRPR_ID,
				CLCL_TOT_PAYABLE,
				GETDATE()
			FROM FACETS.dbo.CMC_CLCL
			WHERE CLCL_ID = @CLCL_ID

		END

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
		SET @step_desc		= 'UPDATE THE CLAIM STATUS IN CLCL AND CDML TABLES'

		UPDATE FACETS.dbo.CMC_CLCL
		SET
			CLCL_CUR_STS =	CASE
								WHEN @TOT_CHG = @TOT_DISALLOW THEN '91'
								ELSE '02'
							END
		WHERE CLCL_ID = @CLCL_ID

		UPDATE FACETS.dbo.CMC_CDML
		SET
			CDML_CUR_STS = CASE
								WHEN @TOT_CHG = @TOT_DISALLOW THEN '91'
								ELSE '02'
							END
		WHERE CLCL_ID = @CLCL_ID

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

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

		SELECT @error			= ERROR_NUMBER(),
			   @sys_def_msg		= ERROR_MESSAGE(),
			   @status_desc		= @step_desc + ' Failed.',
			   @status			= 'E'

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
