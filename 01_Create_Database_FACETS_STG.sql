/* =====================================================================
   01_Create_Database_FACETS_STG.sql
   =====================================================================
   Creates the FACETS_STG database and the four staging tables.
   A claim lands here first, completely unverified, before it is
   matched against master data and promoted into FACETS.

   ===================================================================== */

CREATE DATABASE FACETS_STG
GO

USE FACETS_STG
GO

CREATE TABLE STG_CMC_CLCL (			-- holds claim info, will be linked with all other tables
	CLCL_ID						VARCHAR(10)			NOT NULL,	-- generated
	MEME_CK						INT,			-- empty before member match
	MEME_ID						INT,			-- empty before member match
	CLCL_SUB_TYPE				VARCHAR(1),		-- medical (m), hospital(h), dental (d)
	CLCL_TOT_CHG				MONEY,			-- total charge on the submitted claim
	CLCL_TOT_PAYABLE			MONEY,			-- empty before payment
	CLCL_NTWK_IND				VARCHAR(1),		-- in or out of network
	PRPR_ID						VARCHAR(10),	-- empty before provider selection
	CLCL_CUR_STS				VARCHAR(2),		-- shows the current process of the claim
	CLCL_LOW_SVC_DT				DATETIME,		-- start treatment date, min(CDML_FROM_DT)
	CLCL_HIGH_SVC_DT			DATETIME,		-- end treatment date, max(CDML_TO_DT)
	CLCL_PA_ACCT_NO				VARCHAR(7),		-- unique identifier for members
	CLCL_INPUT_DT				DATETIME,		-- inputted date

	CONSTRAINT PK_STG_CMC_CLCL PRIMARY KEY (CLCL_ID)
)
GO

CREATE TABLE STG_CMC_CDML (		-- table with line level info, one or more lines for each claim id
	CLCL_ID						VARCHAR(10)			NOT NULL,		-- same claim id
	CDML_SEQ					SMALLINT			NOT NULL,	-- sequence number, generated
	CDML_SUB_TYPE				VARCHAR(1),
	CDML_CHG_AMT				MONEY,			-- charge on a single line
	CDML_NTWK_IND				VARCHAR(1),
	CDML_FROM_DT				DATETIME,		-- service start date for that claim line
	CDML_TO_DT					DATETIME,		-- service end date for that claim line
	CDML_ALLOW					MONEY,			-- empty before payment process
	CDML_DISALLOW				MONEY,			-- empty before payment process
	CDML_DISALLOW_EXCD			VARCHAR(7),		-- empty before payment process
	DIAG_CD						VARCHAR(7),		-- diagnosis code (ICD-10)
	PROC_CD						VARCHAR(7),		-- procedure code
	PRPR_ID						VARCHAR(10),
	CDML_CUR_STS				VARCHAR(2),
	CDML_INPUT_DT				DATETIME,

	CONSTRAINT PK_STG_CMC_CDML PRIMARY KEY (CLCL_ID, CDML_SEQ)
)
GO

CREATE TABLE STG_CMC_CLPR (		-- provider info as submitted on a single claim
	CLCL_ID					VARCHAR(10)			NOT NULL,
	CLPR_TYPE				VARCHAR(2)			NOT NULL,	-- 85=billing, 77=servicing, 70=rendering
	CLPR_TAX				VARCHAR(10),		-- tax id of provider
	CLPR_NPI				VARCHAR(50),		-- provider identification number
	CLPR_STATE				VARCHAR(50),
	CLPR_DT					DATETIME,			-- date claim was entered

	CONSTRAINT PK_STG_CMC_CLPR PRIMARY KEY (CLCL_ID, CLPR_TYPE)
)
GO

CREATE TABLE STG_CMC_MEME (		-- member (patient) info as submitted on a single claim
	CLCL_ID					VARCHAR(10)			NOT NULL,
	MEME_FIRST_NAME			VARCHAR(50),
	MEME_LAST_NAME			VARCHAR(50),
	MID_INIT				VARCHAR(30),
	BIRTH_DT				DATETIME,

	CONSTRAINT PK_STG_CMC_MEME PRIMARY KEY (CLCL_ID)
)
GO
