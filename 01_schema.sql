
USE FootballLeagueDB;
GO

SET NOCOUNT ON;
GO

/* 1. Drop existing objects in dependency order */
IF OBJECT_ID(N'dbo.v_integrity_violations', N'V') IS NOT NULL DROP VIEW dbo.v_integrity_violations;
GO

IF OBJECT_ID(N'dbo.contract_version', N'U') IS NOT NULL DROP TABLE dbo.contract_version;
IF OBJECT_ID(N'dbo.coach_assignment_version', N'U') IS NOT NULL DROP TABLE dbo.coach_assignment_version;
IF OBJECT_ID(N'dbo.player_salary_version', N'U') IS NOT NULL DROP TABLE dbo.player_salary_version;
IF OBJECT_ID(N'dbo.club_version', N'U') IS NOT NULL DROP TABLE dbo.club_version;
IF OBJECT_ID(N'dbo.query_params', N'U') IS NOT NULL DROP TABLE dbo.query_params;
IF OBJECT_ID(N'dbo.calendar_month', N'U') IS NOT NULL DROP TABLE dbo.calendar_month;
IF OBJECT_ID(N'dbo.season', N'U') IS NOT NULL DROP TABLE dbo.season;
IF OBJECT_ID(N'dbo.coach', N'U') IS NOT NULL DROP TABLE dbo.coach;
IF OBJECT_ID(N'dbo.player', N'U') IS NOT NULL DROP TABLE dbo.player;
IF OBJECT_ID(N'dbo.club', N'U') IS NOT NULL DROP TABLE dbo.club;
IF OBJECT_ID(N'dbo.league', N'U') IS NOT NULL DROP TABLE dbo.league;
IF OBJECT_ID(N'dbo.tx_registry', N'U') IS NOT NULL DROP TABLE dbo.tx_registry;
GO

/* 2. Transaction registry */
CREATE TABLE dbo.tx_registry
(
    tx_id       BIGINT IDENTITY(1,1) NOT NULL,
    tx_time     DATETIME2(6) NOT NULL,
    author      NVARCHAR(100) NOT NULL,
    reason      NVARCHAR(500) NOT NULL,
    CONSTRAINT PK_tx_registry PRIMARY KEY (tx_id)
);
GO

/* 3. Stable identity tables. */
CREATE TABLE dbo.league
(
    league_id   INT IDENTITY(1,1) NOT NULL,
    league_name NVARCHAR(120) NOT NULL,
    country     NVARCHAR(80) NOT NULL,
    CONSTRAINT PK_league PRIMARY KEY (league_id),
    CONSTRAINT UQ_league_name UNIQUE (league_name)
);
GO

CREATE TABLE dbo.club
(
    club_id INT IDENTITY(1,1) NOT NULL,
    CONSTRAINT PK_club PRIMARY KEY (club_id)
);
GO

CREATE TABLE dbo.player
(
    player_id   INT IDENTITY(1,1) NOT NULL,
    full_name   NVARCHAR(120) NOT NULL,
    birth_date  DATE NOT NULL,
    nationality NVARCHAR(80) NOT NULL,
    CONSTRAINT PK_player PRIMARY KEY (player_id)
);
GO

CREATE TABLE dbo.coach
(
    coach_id    INT IDENTITY(1,1) NOT NULL,
    full_name   NVARCHAR(120) NOT NULL,
    nationality NVARCHAR(80) NOT NULL,
    birth_date  DATE NULL,
    CONSTRAINT PK_coach PRIMARY KEY (coach_id)
);
GO

CREATE TABLE dbo.season
(
    season_id   INT IDENTITY(1,1) NOT NULL,
    season_name NVARCHAR(30) NOT NULL,
    start_date  DATE NOT NULL,
    end_date    DATE NOT NULL,
    CONSTRAINT PK_season PRIMARY KEY (season_id),
    CONSTRAINT UQ_season_name UNIQUE (season_name),
    CONSTRAINT CK_season_dates CHECK (start_date < end_date)
);
GO

/* 4. Bitemporal club versions. */
CREATE TABLE dbo.club_version
(
    version_id  BIGINT IDENTITY(1,1) NOT NULL,
    club_id     INT NOT NULL,
    league_id   INT NOT NULL,
    club_name   NVARCHAR(120) NOT NULL,
    city        NVARCHAR(100) NOT NULL,
    valid_from  DATE NOT NULL,
    valid_to    DATE NOT NULL CONSTRAINT DF_club_version_valid_to DEFAULT ('9999-12-31'),
    tx_from     DATETIME2(6) NOT NULL,
    tx_to       DATETIME2(6) NOT NULL CONSTRAINT DF_club_version_tx_to DEFAULT ('9999-12-31 23:59:59.999999'),
    tx_id       BIGINT NOT NULL,
    CONSTRAINT PK_club_version PRIMARY KEY (version_id),
    CONSTRAINT FK_club_version_club FOREIGN KEY (club_id) REFERENCES dbo.club(club_id),
    CONSTRAINT FK_club_version_league FOREIGN KEY (league_id) REFERENCES dbo.league(league_id),
    CONSTRAINT FK_club_version_tx FOREIGN KEY (tx_id) REFERENCES dbo.tx_registry(tx_id),
    CONSTRAINT CK_club_version_valid_period CHECK (valid_from < valid_to),
    CONSTRAINT CK_club_version_tx_period CHECK (tx_from < tx_to)
);
GO

/* 5. Bitemporal player-club contracts. */
CREATE TABLE dbo.contract_version
(
    version_id    BIGINT IDENTITY(1,1) NOT NULL,
    player_id     INT NOT NULL,
    club_id       INT NOT NULL,
    season_id     INT NOT NULL,
    contract_type NVARCHAR(20) NOT NULL,
    shirt_number  INT NULL,
    valid_from    DATE NOT NULL,
    valid_to      DATE NOT NULL CONSTRAINT DF_contract_valid_to DEFAULT ('9999-12-31'),
    tx_from       DATETIME2(6) NOT NULL,
    tx_to         DATETIME2(6) NOT NULL CONSTRAINT DF_contract_tx_to DEFAULT ('9999-12-31 23:59:59.999999'),
    tx_id         BIGINT NOT NULL,
    CONSTRAINT PK_contract_version PRIMARY KEY (version_id),
    CONSTRAINT FK_contract_player FOREIGN KEY (player_id) REFERENCES dbo.player(player_id),
    CONSTRAINT FK_contract_club FOREIGN KEY (club_id) REFERENCES dbo.club(club_id),
    CONSTRAINT FK_contract_season FOREIGN KEY (season_id) REFERENCES dbo.season(season_id),
    CONSTRAINT FK_contract_tx FOREIGN KEY (tx_id) REFERENCES dbo.tx_registry(tx_id),
    CONSTRAINT CK_contract_valid_period CHECK (valid_from < valid_to),
    CONSTRAINT CK_contract_tx_period CHECK (tx_from < tx_to),
    CONSTRAINT CK_contract_type CHECK (contract_type IN (N'Permanent', N'Loan')),
    CONSTRAINT CK_contract_shirt_number CHECK (shirt_number IS NULL OR shirt_number BETWEEN 1 AND 99)
);
GO

/* 6. Bitemporal player salary versions. */
CREATE TABLE dbo.player_salary_version
(
    version_id BIGINT IDENTITY(1,1) NOT NULL,
    player_id  INT NOT NULL,
    salary_eur DECIMAL(12,2) NOT NULL,
    valid_from DATE NOT NULL,
    valid_to   DATE NOT NULL CONSTRAINT DF_salary_valid_to DEFAULT ('9999-12-31'),
    tx_from    DATETIME2(6) NOT NULL,
    tx_to      DATETIME2(6) NOT NULL CONSTRAINT DF_salary_tx_to DEFAULT ('9999-12-31 23:59:59.999999'),
    tx_id      BIGINT NOT NULL,
    CONSTRAINT PK_player_salary_version PRIMARY KEY (version_id),
    CONSTRAINT FK_salary_player FOREIGN KEY (player_id) REFERENCES dbo.player(player_id),
    CONSTRAINT FK_salary_tx FOREIGN KEY (tx_id) REFERENCES dbo.tx_registry(tx_id),
    CONSTRAINT CK_salary_valid_period CHECK (valid_from < valid_to),
    CONSTRAINT CK_salary_tx_period CHECK (tx_from < tx_to),
    CONSTRAINT CK_salary_nonnegative CHECK (salary_eur >= 0)
);
GO

/* 7. Bitemporal coaching-role assignment. */
CREATE TABLE dbo.coach_assignment_version
(
    version_id BIGINT IDENTITY(1,1) NOT NULL,
    coach_id   INT NOT NULL,
    club_id    INT NOT NULL,
    role_name  NVARCHAR(50) NOT NULL,
    valid_from DATE NOT NULL,
    valid_to   DATE NOT NULL CONSTRAINT DF_coach_assignment_valid_to DEFAULT ('9999-12-31'),
    tx_from    DATETIME2(6) NOT NULL,
    tx_to      DATETIME2(6) NOT NULL CONSTRAINT DF_coach_assignment_tx_to DEFAULT ('9999-12-31 23:59:59.999999'),
    tx_id      BIGINT NOT NULL,
    CONSTRAINT PK_coach_assignment_version PRIMARY KEY (version_id),
    CONSTRAINT FK_coach_assignment_coach FOREIGN KEY (coach_id) REFERENCES dbo.coach(coach_id),
    CONSTRAINT FK_coach_assignment_club FOREIGN KEY (club_id) REFERENCES dbo.club(club_id),
    CONSTRAINT FK_coach_assignment_tx FOREIGN KEY (tx_id) REFERENCES dbo.tx_registry(tx_id),
    CONSTRAINT CK_coach_assignment_valid_period CHECK (valid_from < valid_to),
    CONSTRAINT CK_coach_assignment_tx_period CHECK (tx_from < tx_to)
);
GO

/* 8. One-row parameter table used by the temporal query views. */
CREATE TABLE dbo.query_params
(
    parameter_id TINYINT NOT NULL,
    valid_at     DATE NOT NULL,
    known_at     DATETIME2(6) NOT NULL,
    period_start DATE NOT NULL,
    period_end   DATE NOT NULL,
    subject_id   INT NULL,
    CONSTRAINT PK_query_params PRIMARY KEY (parameter_id),
    CONSTRAINT CK_query_params_singleton CHECK (parameter_id = 1),
    CONSTRAINT CK_query_params_period CHECK (period_start < period_end)
);
GO

/* 9. Calendar table for Q7. */
CREATE TABLE dbo.calendar_month
(
    month_start DATE NOT NULL,
    CONSTRAINT PK_calendar_month PRIMARY KEY (month_start),
    CONSTRAINT CK_calendar_month_first_day CHECK (DAY(month_start) = 1)
);
GO

/* 10. Indexes for temporal as-of queries for Q6. */
CREATE INDEX IX_contract_asof
ON dbo.contract_version (player_id, tx_to, valid_from)
INCLUDE (valid_to, club_id, season_id, tx_from, tx_id, contract_type);
GO

CREATE INDEX IX_coach_assignment_asof
ON dbo.coach_assignment_version (club_id, role_name, tx_to, valid_from)
INCLUDE (valid_to, coach_id, tx_from, tx_id);
GO

CREATE INDEX IX_salary_asof
ON dbo.player_salary_version (player_id, tx_to, valid_from)
INCLUDE (valid_to, salary_eur, tx_from, tx_id);
GO

CREATE INDEX IX_club_version_asof
ON dbo.club_version (club_id, tx_to, valid_from)
INCLUDE (valid_to, club_name, league_id, city, tx_from, tx_id);
GO

PRINT 'schema.sql completed successfully.';
GO




/* Verify */

USE FootballLeagueDB;
GO

SELECT
    TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;


SELECT
    t.name AS table_name,
    c.name AS constraint_name,
    c.type_desc
FROM sys.tables AS t
JOIN sys.objects AS c
    ON c.parent_object_id = t.object_id
WHERE c.type IN ('PK', 'F', 'C', 'UQ')
ORDER BY t.name, c.type_desc, c.name;