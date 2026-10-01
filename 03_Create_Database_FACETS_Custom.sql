/* =====================================================================
   03_Create_Database_FACETS_Custom.sql
   =====================================================================
   Creates the FACETS_Custom database: the "back office." This holds
   the logging infrastructure, the work/tracking tables, the claim ID
   sequence, and the table types used by the stored procedures. Every
   procedure in this project runs from inside this database.

   ===================================================================== */

CREATE DATABASE FACETS_Custom
GO

USE FACETS_Custom
GO

-- =========================================================
-- LOG TABLES - every procedure writes a step-by-step audit
-- trail here via USP_CLM_STEP_ERR_LOG
-- =========================================================

CREATE TABLE [dbo].[CLM_JOB_ERR_LOG]
(
	[RUN_ID] [int] NOT NULL,
	[JOB_ID] [varchar](255) NOT NULL,
	[SP_NAME] [varchar](255) NULL,
	[STEP_ID] [int] NULL,
	[USER_DEF_MSG] [varchar](5000) NULL,
	[SYS_DEF_MSG] [varchar](5000) NULL,
	[ERR_DTM] [datetime] NULL
) ON [PRIMARY]
GO

CREATE TABLE [dbo].[CLM_JOB_STEP_LOG]
(
	[RUN_ID] [int] NOT NULL,
	[JOB_ID] [varchar](255) NOT NULL,
	[SP_NAME] [varchar](255) NULL,
	[STEP_ID] [int] NULL,
	[STEP_DESC] [varchar](5000) NULL,
	[STATUS] [varchar](1) NULL,
	[STEP_DTM] [datetime] NULL,
	[ROWS_PROCESSED] [int] NULL
) ON [PRIMARY]
GO

-- =========================================================
-- WORK TABLES
-- =========================================================

CREATE TABLE CW_RJCT_CLCL (
    CLCL_ID             VARCHAR(10)     NOT NULL,
    MEME_CK             INT,
    CLCL_SUB_TYPE       VARCHAR(1),
    CLCL_TOT_CHG        MONEY,
    PRPR_ID             VARCHAR(10),
    CLCL_PA_ACCT_NO     VARCHAR(7),
    RJCT_REAS           VARCHAR(255),
    UPDT_DTM            DATETIME
)
GO

CREATE TABLE CW_HEADER (
    ACPR_REF_ID     VARCHAR(10)     NOT NULL,
    ACPR_TYPE       VARCHAR(2)      NOT NULL,
    ACPR_SUB_TYPE   VARCHAR(1)      NOT NULL,
    ACPR_CREATE_DT  DATETIME,
    STATUS          VARCHAR(20),
    UPDT_DTM        DATETIME,
    LAST_LTR_DT     DATETIME,
    ACPR_NET_AMT    MONEY,

    CONSTRAINT PK_CW_HEADER PRIMARY KEY (ACPR_REF_ID, ACPR_TYPE, ACPR_SUB_TYPE)
)
GO

CREATE TABLE CW_STATUS (
    ACPR_REF_ID     VARCHAR(10)     NOT NULL,
    ACPR_TYPE       VARCHAR(2)      NOT NULL,
    ACPR_SUB_TYPE   VARCHAR(1)      NOT NULL,
    STATUS          VARCHAR(20),
    UPDT_DTM        DATETIME        NOT NULL
)
GO

-- =========================================================
-- SEQUENCE - generates the numeric portion of each CLCL_ID
-- =========================================================

CREATE SEQUENCE [dbo].[CLCL_ID_1031SEQ]
 AS [int]
 START WITH 1
 INCREMENT BY 1
 MINVALUE 1
 MAXVALUE 9999999
 CYCLE
 CACHE
GO

-- =========================================================
-- TABLE TYPES - let a stored procedure accept multiple rows
-- of data as a single parameter
-- =========================================================

CREATE TYPE [dbo].[STG_CMC_CDML_TYPE] AS TABLE
(
	[CDML_CHG_AMT] [money] NULL,
	[CDML_FROM_DT] [date] NULL,
	[CDML_TO_DT] [date] NULL,
	[DIAG_CD] [varchar](7) NULL,
	[PROC_CD] [varchar](7) NULL
)
GO

CREATE TYPE [dbo].[STG_CMC_CLPR_TYPE] AS TABLE
(
	[CLPR_TYPE] [varchar](2) NULL,
	[CLPR_TAX] [varchar](20) NULL,
	[CLPR_NPI] [varchar](50) NULL,
	[CLPR_STATE] [varchar](50) NULL
)
GO

CREATE TYPE dbo.ClaimDetailType AS TABLE
(
    CDML_SEQ        INT,
    DEDUCTION_PCNTG DECIMAL(5,2)
)
GO
