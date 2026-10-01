/* =====================================================================
   02_Create_Database_FACETS.sql
   =====================================================================
   Creates the FACETS database: the "official records." Only claims
   that pass every validation step get copied in here, alongside the
   master lists of real members and real providers.
   ===================================================================== */

CREATE DATABASE FACETS
GO

USE FACETS
GO

CREATE TABLE CMC_CLCL (
    CLCL_ID             VARCHAR(10)     NOT NULL,
    MEME_CK             INT,
    MEME_ID             INT,
    CLCL_SUB_TYPE       VARCHAR(1),
    CLCL_TOT_CHG        MONEY,
    CLCL_TOT_PAYABLE    MONEY,
    CLCL_NTWK_IND       VARCHAR(1),
    PRPR_ID             VARCHAR(10),
    CLCL_CUR_STS        VARCHAR(2),
    CLCL_LOW_SVC_DT     DATETIME,
    CLCL_HIGH_SVC_DT    DATETIME,
    CLCL_PA_ACCT_NO     VARCHAR(7),
    CLCL_INPUT_DT       DATETIME,

    CONSTRAINT PK_CMC_CLCL PRIMARY KEY (CLCL_ID)
)
GO

CREATE TABLE CMC_CDML (
    CLCL_ID             VARCHAR(10)     NOT NULL,
    CDML_SEQ            SMALLINT        NOT NULL,
    CDML_SUB_TYPE       VARCHAR(1),
    CDML_CHG_AMT        MONEY,
    CDML_NTWK_IND       VARCHAR(1),
    CDML_FROM_DT        DATETIME,
    CDML_TO_DT          DATETIME,
    CDML_ALLOW          MONEY,
    CDML_DISALLOW       MONEY,
    CDML_DISALLOW_EXCD  VARCHAR(7),
    DIAG_CD             VARCHAR(7),
    PROC_CD             VARCHAR(7),
    PRPR_ID             VARCHAR(10),
    CDML_CUR_STS        VARCHAR(2),
    CDML_INPUT_DT       DATETIME,

    CONSTRAINT PK_CMC_CDML PRIMARY KEY (CLCL_ID, CDML_SEQ)
)
GO

CREATE TABLE CMC_CLOV (
    CLCL_ID             VARCHAR(10)     NOT NULL,
    PRPR_ID             VARCHAR(10),
    CLOV_AMT            MONEY,
    ACPR_REF_ID         VARCHAR(10)     NOT NULL,
    CLOV_CREATE_DT      DATETIME,

    CONSTRAINT PK_CMC_CLOV PRIMARY KEY (CLCL_ID, ACPR_REF_ID)
)
GO

CREATE TABLE CMC_ACPR (
    ACPR_REF_ID         VARCHAR(10)     NOT NULL,
    ACPR_TYPE           VARCHAR(2)      NOT NULL,
    ACPR_SUB_TYPE       VARCHAR(1)      NOT NULL,
    ACPR_CREATE_DT      DATETIME,
    ACPR_PAYEE_ID       VARCHAR(10),
    ACPR_STS            VARCHAR(1),
    ACPR_ORIG_AMT       MONEY,
    ACPR_NET_AMT        MONEY,
    ACPR_RECOV_AMT      MONEY,
    ACPR_WOFF_AMT       MONEY,
    EXCD_ID             VARCHAR(3),

    CONSTRAINT PK_CMC_ACPR PRIMARY KEY (ACPR_REF_ID, ACPR_TYPE, ACPR_SUB_TYPE)
)
GO

-- Recovery/reduction history: a surrogate key (ACRH_ID) is used because
-- this is an event log, not a one-row-per-key table - the same claim
-- can have multiple recovery events logged against it over time.
CREATE TABLE CMC_ACRH (
    ACRH_ID             INT             IDENTITY(1,1)   NOT NULL,
    ACPR_REF_ID         VARCHAR(10)     NOT NULL,
    ACPR_TYPE           VARCHAR(2),
    ACPR_SUB_TYPE       VARCHAR(1)      NOT NULL,
    ACRH_CREATE_DT      DATETIME,
    ACRH_EVENT_TYPE     VARCHAR(1),
    ACRH_AMT            MONEY,
    ACRH_MCTR_RSN       VARCHAR(10),

    CONSTRAINT PK_CMC_ACRH PRIMARY KEY (ACRH_ID)
)
GO

CREATE NONCLUSTERED INDEX IX_CMC_ACRH_ACPR_REF
ON dbo.CMC_ACRH (ACPR_REF_ID, ACPR_TYPE, ACPR_SUB_TYPE)
GO

CREATE TABLE CMC_PRWM (
    PRPR_ID             VARCHAR(10)     NOT NULL,
    PRWM_EFF_DT         DATETIME,
    PRWM_TERM_DT        DATETIME,
    WMDS_SEQ_NO         VARCHAR(4)      NOT NULL,

    CONSTRAINT PK_CMC_PRWM PRIMARY KEY (PRPR_ID, WMDS_SEQ_NO)
)
GO

CREATE TABLE CMC_PRPR (
    PRPR_ID             VARCHAR(10)     NOT NULL,
    PRPR_NAME           VARCHAR(50),
    PRPR_NPI            VARCHAR(10),
    MCTN_ID             VARCHAR(50),
    PRPR_ADD1           VARCHAR(255),
    PRPR_ADD2           VARCHAR(255),
    PRPR_CITY           VARCHAR(50),
    PRPR_STATE          VARCHAR(50),
    PRPR_CNTRY          VARCHAR(50),
    PRPR_TERM_DT        DATETIME,

    CONSTRAINT PK_CMC_PRPR PRIMARY KEY (PRPR_ID)
)
GO

CREATE TABLE CMC_MEME (
    MEME_CK             INT             NOT NULL,
    MEME_ID             INT,
    FIRST_NAME          VARCHAR(30),
    LAST_NAME           VARCHAR(30),
    MID_INIT            VARCHAR(30),
    BIRTH_DT            DATETIME,
    MEME_PHONE          VARCHAR(30),

    CONSTRAINT PK_CMC_MEME PRIMARY KEY (MEME_CK)
)
GO

CREATE TABLE CMC_CLPR (
    CLCL_ID         VARCHAR(10)     NOT NULL,
    CLPR_TYPE       VARCHAR(2)      NOT NULL,
    CLPR_TAX        VARCHAR(10),
    CLPR_NPI        VARCHAR(50),
    CLPR_STATE      VARCHAR(50),
    CLPR_DT         DATETIME,

    CONSTRAINT PK_CMC_CLPR PRIMARY KEY (CLCL_ID, CLPR_TYPE)
)
GO
