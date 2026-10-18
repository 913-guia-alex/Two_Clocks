
USE FootballLeagueDB;
GO


SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* 0. Verify the expected E1 baseline and avoid duplicate timeline events. */
IF NOT EXISTS (SELECT 1 FROM dbo.tx_registry WHERE reason LIKE N'E1 - Initial load%')
    THROW 51100, 'Run 02_data.sql successfully before 03_timeline.sql.', 1;

IF EXISTS (SELECT 1 FROM dbo.tx_registry WHERE reason LIKE N'E2 -%' OR reason LIKE N'E3 -%' OR reason LIKE N'E4 -%' OR reason LIKE N'E5 -%' OR reason LIKE N'E6 -%' OR reason LIKE N'E7 -%' OR reason LIKE N'E8 -%' OR reason LIKE N'E9 -%')
    THROW 51101, 'Timeline events already exist. Re-run 01_schema.sql and 02_data.sql before replaying 03_timeline.sql.', 1;

IF (SELECT COUNT(*) FROM dbo.player) <> 51
   OR (SELECT COUNT(*) FROM dbo.club) <> 6
   OR (SELECT COUNT(*) FROM dbo.coach) <> 6
    THROW 51102, 'The E1 baseline does not match the expected 50 players, 6 clubs and 6 coaches.', 1;
GO

/* ========================================================================
   E2 — Proactive change: three salary changes recorded before their
        valid-time effective date (2026-04-01).
   ======================================================================== */
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @e2_time DATETIME2(6) = '2026-03-11T09:00:00.000000';
    DECLARE @e2_tx BIGINT;
    DECLARE @salary_changes TABLE
    (
        player_id INT PRIMARY KEY,
        old_salary DECIMAL(12,2) NOT NULL,
        new_salary DECIMAL(12,2) NOT NULL
    );

    INSERT INTO dbo.tx_registry (tx_time, author, reason)
    VALUES (@e2_time, N'Timeline simulation', N'E2 - Proactive salary changes for three players effective 2026-04-01');
    SET @e2_tx = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO @salary_changes (player_id, old_salary, new_salary)
    SELECT player_id, salary_eur,
           CASE player_id WHEN 1 THEN 21000.00 WHEN 2 THEN 22500.00 WHEN 3 THEN 24000.00 END
    FROM dbo.player_salary_version
    WHERE player_id IN (1,2,3)
      AND valid_from = '2024-07-01'
      AND valid_to = '9999-12-31'
      AND tx_to = '9999-12-31T23:59:59.999999';

    IF (SELECT COUNT(*) FROM @salary_changes) <> 3
        THROW 51110, 'E2 expected exactly three current salary versions.', 1;

    UPDATE sv
       SET tx_to = @e2_time
    FROM dbo.player_salary_version AS sv
    JOIN @salary_changes AS sc ON sc.player_id = sv.player_id
    WHERE sv.valid_from = '2024-07-01'
      AND sv.valid_to = '9999-12-31'
      AND sv.tx_to = '9999-12-31T23:59:59.999999';

    /* Preserve the old salary until the effective date. */
    INSERT INTO dbo.player_salary_version
        (player_id, salary_eur, valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT player_id, old_salary, '2024-07-01', '2026-04-01',
           @e2_time, '9999-12-31T23:59:59.999999', @e2_tx
    FROM @salary_changes;

    /* The proactive salary takes effect on 2026-04-01. */
    INSERT INTO dbo.player_salary_version
        (player_id, salary_eur, valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT player_id, new_salary, '2026-04-01', '9999-12-31',
           @e2_time, '9999-12-31T23:59:59.999999', @e2_tx
    FROM @salary_changes;

    COMMIT TRANSACTION;
    PRINT 'E2 completed: 3 proactive salary changes.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* ========================================================================
   E3 — Late entry: five historical player-club loan facts are entered on
        2026-03-12, although their valid period was 2025-01-01 to 2025-03-01.
        Existing contract beliefs are split so valid periods do not overlap.
   ======================================================================== */
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @e3_time DATETIME2(6) = '2026-03-12T10:30:00.000000';
    DECLARE @e3_tx BIGINT;
    DECLARE @late_contracts TABLE
    (
        player_id INT PRIMARY KEY,
        original_club_id INT NOT NULL,
        season_id INT NOT NULL,
        contract_type NVARCHAR(20) NOT NULL,
        shirt_number INT NULL
    );

    INSERT INTO dbo.tx_registry (tx_time, author, reason)
    VALUES (@e3_time, N'Timeline simulation', N'E3 - Late entry of five historical loan contracts, valid in early 2025');
    SET @e3_tx = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO @late_contracts (player_id, original_club_id, season_id, contract_type, shirt_number)
    SELECT player_id, club_id, season_id, contract_type, shirt_number
    FROM dbo.contract_version
    WHERE player_id BETWEEN 11 AND 15
      AND valid_from = '2024-07-01'
      AND valid_to = '9999-12-31'
      AND tx_to = '9999-12-31T23:59:59.999999';

    IF (SELECT COUNT(*) FROM @late_contracts) <> 5
        THROW 51120, 'E3 expected exactly five current contracts for players 11-15.', 1;

    UPDATE cv
       SET tx_to = @e3_time
    FROM dbo.contract_version AS cv
    JOIN @late_contracts AS lc ON lc.player_id = cv.player_id
    WHERE cv.valid_from = '2024-07-01'
      AND cv.valid_to = '9999-12-31'
      AND cv.tx_to = '9999-12-31T23:59:59.999999';

    /* Segment before the late-entered fact. */
    INSERT INTO dbo.contract_version
        (player_id, club_id, season_id, contract_type, shirt_number,
         valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT player_id, original_club_id, season_id, contract_type, shirt_number,
           '2024-07-01', '2025-01-01', @e3_time,
           '9999-12-31T23:59:59.999999', @e3_tx
    FROM @late_contracts;

    /* The late-entered loan is a separate relationship fact. */
    INSERT INTO dbo.contract_version
        (player_id, club_id, season_id, contract_type, shirt_number,
         valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT player_id,
           CASE WHEN original_club_id = 6 THEN 1 ELSE original_club_id + 1 END,
           1, N'Loan', NULL,
           '2025-01-01', '2025-03-01', @e3_time,
           '9999-12-31T23:59:59.999999', @e3_tx
    FROM @late_contracts;

    /* The original relationship resumes after the loan. */
    INSERT INTO dbo.contract_version
        (player_id, club_id, season_id, contract_type, shirt_number,
         valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT player_id, original_club_id, season_id, contract_type, shirt_number,
           '2025-03-01', '9999-12-31', @e3_time,
           '9999-12-31T23:59:59.999999', @e3_tx
    FROM @late_contracts;

    COMMIT TRANSACTION;
    PRINT 'E3 completed: 5 late-entered historical loan facts.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* ========================================================================
   E4 — Correction: three incorrect shirt numbers are corrected. The old
        beliefs remain queryable at earlier transaction times.
   ======================================================================== */
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @e4_time DATETIME2(6) = '2026-03-13T11:15:00.000000';
    DECLARE @e4_tx BIGINT;
    DECLARE @corrected_contracts TABLE
    (
        player_id INT PRIMARY KEY,
        club_id INT NOT NULL,
        season_id INT NOT NULL,
        contract_type NVARCHAR(20) NOT NULL,
        old_shirt_number INT NULL,
        valid_from DATE NOT NULL,
        valid_to DATE NOT NULL
    );

    INSERT INTO dbo.tx_registry (tx_time, author, reason)
    VALUES (@e4_time, N'Timeline simulation', N'E4 - Correction of shirt numbers for three player contracts');
    SET @e4_tx = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO @corrected_contracts
        (player_id, club_id, season_id, contract_type, old_shirt_number, valid_from, valid_to)
    SELECT player_id, club_id, season_id, contract_type, shirt_number, valid_from, valid_to
    FROM dbo.contract_version
    WHERE player_id IN (1,2,3)
      AND valid_from = '2024-07-01'
      AND valid_to = '9999-12-31'
      AND tx_to = '9999-12-31T23:59:59.999999';

    IF (SELECT COUNT(*) FROM @corrected_contracts) <> 3
        THROW 51130, 'E4 expected exactly three current contracts for players 1-3.', 1;

    UPDATE cv
       SET tx_to = @e4_time
    FROM dbo.contract_version AS cv
    JOIN @corrected_contracts AS cc ON cc.player_id = cv.player_id
    WHERE cv.valid_from = '2024-07-01'
      AND cv.valid_to = '9999-12-31'
      AND cv.tx_to = '9999-12-31T23:59:59.999999';

    INSERT INTO dbo.contract_version
        (player_id, club_id, season_id, contract_type, shirt_number,
         valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT player_id, club_id, season_id, contract_type,
           CASE WHEN old_shirt_number IS NULL THEN NULL
                WHEN old_shirt_number = 99 THEN 98
                ELSE old_shirt_number + 1 END,
           valid_from, valid_to, @e4_time,
           '9999-12-31T23:59:59.999999', @e4_tx
    FROM @corrected_contracts;

    COMMIT TRANSACTION;
    PRINT 'E4 completed: 3 contract corrections.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* ========================================================================
   E5 — Real-world end: five contracts actually ended on 2026-02-01.
        We close their old transaction-time beliefs and insert corrected
        versions whose valid-time periods end on the real-world end date.
   ======================================================================== */
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @e5_time DATETIME2(6) = '2026-03-14T08:45:00.000000';
    DECLARE @e5_tx BIGINT;
    DECLARE @ended_contracts TABLE
    (
        player_id INT PRIMARY KEY,
        club_id INT NOT NULL,
        season_id INT NOT NULL,
        contract_type NVARCHAR(20) NOT NULL,
        shirt_number INT NULL,
        valid_from DATE NOT NULL
    );

    INSERT INTO dbo.tx_registry (tx_time, author, reason)
    VALUES (@e5_time, N'Timeline simulation', N'E5 - Record real-world end date 2026-02-01 for five contracts');
    SET @e5_tx = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO @ended_contracts
        (player_id, club_id, season_id, contract_type, shirt_number, valid_from)
    SELECT player_id, club_id, season_id, contract_type, shirt_number, valid_from
    FROM dbo.contract_version
    WHERE player_id BETWEEN 6 AND 10
      AND valid_from = '2024-07-01'
      AND valid_to = '9999-12-31'
      AND tx_to = '9999-12-31T23:59:59.999999';

    IF (SELECT COUNT(*) FROM @ended_contracts) <> 5
        THROW 51140, 'E5 expected exactly five current contracts for players 6-10.', 1;

    UPDATE cv
       SET tx_to = @e5_time
    FROM dbo.contract_version AS cv
    JOIN @ended_contracts AS ec ON ec.player_id = cv.player_id
    WHERE cv.valid_from = '2024-07-01'
      AND cv.valid_to = '9999-12-31'
      AND cv.tx_to = '9999-12-31T23:59:59.999999';

    INSERT INTO dbo.contract_version
        (player_id, club_id, season_id, contract_type, shirt_number,
         valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT player_id, club_id, season_id, contract_type, shirt_number,
           valid_from, '2026-02-01', @e5_time,
           '9999-12-31T23:59:59.999999', @e5_tx
    FROM @ended_contracts;

    COMMIT TRANSACTION;
    PRINT 'E5 completed: 5 contracts ended in valid time.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* ========================================================================
   E6 — Restart after a gap for three players. Each has a contract through
        2025-07-01 and a new contract from 2025-09-01, leaving July-August
        without a contract. A mistaken contract for player 16 is also
        inserted in that gap; E8 later retracts it transaction-time-only.
   ======================================================================== */
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @e6_time DATETIME2(6) = '2026-03-15T13:20:00.000000';
    DECLARE @e6_tx BIGINT;
    DECLARE @restart_contracts TABLE
    (
        player_id INT PRIMARY KEY,
        original_club_id INT NOT NULL,
        season_id INT NOT NULL,
        contract_type NVARCHAR(20) NOT NULL,
        shirt_number INT NULL,
        valid_from DATE NOT NULL
    );

    INSERT INTO dbo.tx_registry (tx_time, author, reason)
    VALUES (@e6_time, N'Timeline simulation', N'E6 - Three contracts restart after a gap; includes one mistaken gap-period record later retracted in E8');
    SET @e6_tx = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO @restart_contracts
        (player_id, original_club_id, season_id, contract_type, shirt_number, valid_from)
    SELECT player_id, club_id, season_id, contract_type, shirt_number, valid_from
    FROM dbo.contract_version
    WHERE player_id BETWEEN 16 AND 18
      AND valid_from = '2024-07-01'
      AND valid_to = '9999-12-31'
      AND tx_to = '9999-12-31T23:59:59.999999';

    IF (SELECT COUNT(*) FROM @restart_contracts) <> 3
        THROW 51150, 'E6 expected exactly three current contracts for players 16-18.', 1;

    UPDATE cv
       SET tx_to = @e6_time
    FROM dbo.contract_version AS cv
    JOIN @restart_contracts AS rc ON rc.player_id = cv.player_id
    WHERE cv.valid_from = '2024-07-01'
      AND cv.valid_to = '9999-12-31'
      AND cv.tx_to = '9999-12-31T23:59:59.999999';

    /* First segment ends as the gap begins. */
    INSERT INTO dbo.contract_version
        (player_id, club_id, season_id, contract_type, shirt_number,
         valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT player_id, original_club_id, 1, contract_type, shirt_number,
           '2024-07-01', '2025-07-01', @e6_time,
           '9999-12-31T23:59:59.999999', @e6_tx
    FROM @restart_contracts;

    /* New contract starts after a two-month gap. */
    INSERT INTO dbo.contract_version
        (player_id, club_id, season_id, contract_type, shirt_number,
         valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT player_id, original_club_id, 2, N'Permanent', shirt_number,
           '2025-09-01', '9999-12-31', @e6_time,
           '9999-12-31T23:59:59.999999', @e6_tx
    FROM @restart_contracts;

    /* Erroneous fact inserted now and retracted by E8: it falsely fills part
       of player 16's intended gap. No other player's gap is affected. */
    INSERT INTO dbo.contract_version
        (player_id, club_id, season_id, contract_type, shirt_number,
         valid_from, valid_to, tx_from, tx_to, tx_id)
    VALUES
        (16, 1, 2, N'Loan', NULL,
         '2025-07-10', '2025-08-10', @e6_time,
         '9999-12-31T23:59:59.999999', @e6_tx);

    COMMIT TRANSACTION;
    PRINT 'E6 completed: 3 contract restarts after a gap; one mistaken fact staged for E8 retraction.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* ========================================================================
   E7 — Role-holder changes. For club 1 / Head Coach, the same valid date
        (2025-08-01) yields three answers at three transaction times:
        E7a: coach 2; E7b: coach 3; E7c: coach 4.
   ======================================================================== */

/* E7a: first belief — coach 2 takes over from 2025-08-01. */
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @e7a_time DATETIME2(6) = '2026-03-16T08:00:00.000000';
    DECLARE @e7a_tx BIGINT;

    INSERT INTO dbo.tx_registry (tx_time, author, reason)
    VALUES (@e7a_time, N'Timeline simulation', N'E7 - Role change belief 1: coach 2 is Head Coach of club 1 from 2025-08-01');
    SET @e7a_tx = CONVERT(BIGINT, SCOPE_IDENTITY());

    IF (SELECT COUNT(*) FROM dbo.coach_assignment_version
        WHERE coach_id = 1 AND club_id = 1 AND role_name = N'Head Coach'
          AND valid_from = '2024-07-01' AND valid_to = '9999-12-31'
          AND tx_to = '9999-12-31T23:59:59.999999') <> 1
        THROW 51160, 'E7a expected the initial club 1 Head Coach assignment.', 1;

    UPDATE dbo.coach_assignment_version
       SET tx_to = @e7a_time
    WHERE coach_id = 1 AND club_id = 1 AND role_name = N'Head Coach'
      AND valid_from = '2024-07-01' AND valid_to = '9999-12-31'
      AND tx_to = '9999-12-31T23:59:59.999999';

    INSERT INTO dbo.coach_assignment_version
        (coach_id, club_id, role_name, valid_from, valid_to, tx_from, tx_to, tx_id)
    VALUES
        (1, 1, N'Head Coach', '2024-07-01', '2025-08-01', @e7a_time, '9999-12-31T23:59:59.999999', @e7a_tx),
        (2, 1, N'Head Coach', '2025-08-01', '9999-12-31', @e7a_time, '9999-12-31T23:59:59.999999', @e7a_tx);

    COMMIT TRANSACTION;
    PRINT 'E7a completed: first role-holder belief recorded.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* E7b: correction — same valid date, but coach 3 is now believed to hold it. */
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @e7b_time DATETIME2(6) = '2026-03-16T12:00:00.000000';
    DECLARE @e7b_tx BIGINT;

    INSERT INTO dbo.tx_registry (tx_time, author, reason)
    VALUES (@e7b_time, N'Timeline simulation', N'E7 - Role change belief 2: correct club 1 Head Coach to coach 3 from 2025-08-01');
    SET @e7b_tx = CONVERT(BIGINT, SCOPE_IDENTITY());

    IF (SELECT COUNT(*) FROM dbo.coach_assignment_version
        WHERE coach_id = 2 AND club_id = 1 AND role_name = N'Head Coach'
          AND valid_from = '2025-08-01' AND valid_to = '9999-12-31'
          AND tx_to = '9999-12-31T23:59:59.999999') <> 1
        THROW 51161, 'E7b expected coach 2 as the currently believed role holder.', 1;

    UPDATE dbo.coach_assignment_version
       SET tx_to = @e7b_time
    WHERE coach_id = 2 AND club_id = 1 AND role_name = N'Head Coach'
      AND valid_from = '2025-08-01' AND valid_to = '9999-12-31'
      AND tx_to = '9999-12-31T23:59:59.999999';

    INSERT INTO dbo.coach_assignment_version
        (coach_id, club_id, role_name, valid_from, valid_to, tx_from, tx_to, tx_id)
    VALUES
        (3, 1, N'Head Coach', '2025-08-01', '9999-12-31', @e7b_time, '9999-12-31T23:59:59.999999', @e7b_tx);

    COMMIT TRANSACTION;
    PRINT 'E7b completed: second role-holder belief recorded.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* E7c: another correction — same valid date, now coach 4 is believed. */
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @e7c_time DATETIME2(6) = '2026-03-17T09:00:00.000000';
    DECLARE @e7c_tx BIGINT;

    INSERT INTO dbo.tx_registry (tx_time, author, reason)
    VALUES (@e7c_time, N'Timeline simulation', N'E7 - Role change belief 3: correct club 1 Head Coach to coach 4 from 2025-08-01');
    SET @e7c_tx = CONVERT(BIGINT, SCOPE_IDENTITY());

    IF (SELECT COUNT(*) FROM dbo.coach_assignment_version
        WHERE coach_id = 3 AND club_id = 1 AND role_name = N'Head Coach'
          AND valid_from = '2025-08-01' AND valid_to = '9999-12-31'
          AND tx_to = '9999-12-31T23:59:59.999999') <> 1
        THROW 51162, 'E7c expected coach 3 as the currently believed role holder.', 1;

    UPDATE dbo.coach_assignment_version
       SET tx_to = @e7c_time
    WHERE coach_id = 3 AND club_id = 1 AND role_name = N'Head Coach'
      AND valid_from = '2025-08-01' AND valid_to = '9999-12-31'
      AND tx_to = '9999-12-31T23:59:59.999999';

    INSERT INTO dbo.coach_assignment_version
        (coach_id, club_id, role_name, valid_from, valid_to, tx_from, tx_to, tx_id)
    VALUES
        (4, 1, N'Head Coach', '2025-08-01', '9999-12-31', @e7c_time, '9999-12-31T23:59:59.999999', @e7c_tx);

    COMMIT TRANSACTION;
    PRINT 'E7c completed: third role-holder belief recorded.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* ========================================================================
   E8 — Erroneous insert retracted. Only tx_to is changed; the erroneous row
        remains in history and no replacement row is inserted.
   ======================================================================== */
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @e8_time DATETIME2(6) = '2026-03-18T10:00:00.000000';
    DECLARE @e8_tx BIGINT;

    INSERT INTO dbo.tx_registry (tx_time, author, reason)
    VALUES (@e8_time, N'Timeline simulation', N'E8 - Retract erroneous player 16 loan record for 2025-07-10 through 2025-08-10');
    SET @e8_tx = CONVERT(BIGINT, SCOPE_IDENTITY());

    IF (SELECT COUNT(*) FROM dbo.contract_version
        WHERE player_id = 16 AND club_id = 1 AND season_id = 2
          AND contract_type = N'Loan'
          AND valid_from = '2025-07-10' AND valid_to = '2025-08-10'
          AND tx_to = '9999-12-31T23:59:59.999999') <> 1
        THROW 51170, 'E8 could not find exactly one erroneous contract to retract.', 1;

    UPDATE dbo.contract_version
       SET tx_to = @e8_time
    WHERE player_id = 16 AND club_id = 1 AND season_id = 2
      AND contract_type = N'Loan'
      AND valid_from = '2025-07-10' AND valid_to = '2025-08-10'
      AND tx_to = '9999-12-31T23:59:59.999999';

    COMMIT TRANSACTION;
    PRINT 'E8 completed: erroneous row retracted by transaction time only.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* ========================================================================
   E9 — One logical change touching two bitemporal tables with the same tx_id:
        rename club 2 effective 2026-05-01 and transfer player 19 to that club
        on the same valid date.
   ======================================================================== */
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @e9_time DATETIME2(6) = '2026-03-19T14:30:00.000000';
    DECLARE @e9_tx BIGINT;
    DECLARE @effective_date DATE = '2026-05-01';
    DECLARE @club2 TABLE
    (
        league_id INT NOT NULL,
        club_name NVARCHAR(120) NOT NULL,
        city NVARCHAR(100) NOT NULL,
        valid_from DATE NOT NULL
    );
    DECLARE @player19 TABLE
    (
        old_club_id INT NOT NULL,
        season_id INT NOT NULL,
        contract_type NVARCHAR(20) NOT NULL,
        shirt_number INT NULL,
        valid_from DATE NOT NULL
    );

    INSERT INTO dbo.tx_registry (tx_time, author, reason)
    VALUES (@e9_time, N'Timeline simulation', N'E9 - Rename club 2 and transfer player 19 to club 2 in one logical change');
    SET @e9_tx = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO @club2 (league_id, club_name, city, valid_from)
    SELECT league_id, club_name, city, valid_from
    FROM dbo.club_version
    WHERE club_id = 2
      AND valid_from = '2024-07-01'
      AND valid_to = '9999-12-31'
      AND tx_to = '9999-12-31T23:59:59.999999';

    INSERT INTO @player19 (old_club_id, season_id, contract_type, shirt_number, valid_from)
    SELECT club_id, season_id, contract_type, shirt_number, valid_from
    FROM dbo.contract_version
    WHERE player_id = 19
      AND valid_from = '2024-07-01'
      AND valid_to = '9999-12-31'
      AND tx_to = '9999-12-31T23:59:59.999999';

    IF (SELECT COUNT(*) FROM @club2) <> 1 OR (SELECT COUNT(*) FROM @player19) <> 1
        THROW 51180, 'E9 expected one current club 2 version and one current open contract for player 19.', 1;

    /* Close prior beliefs in both tables under the same event timestamp. */
    UPDATE dbo.club_version
       SET tx_to = @e9_time
    WHERE club_id = 2 AND valid_from = '2024-07-01'
      AND valid_to = '9999-12-31'
      AND tx_to = '9999-12-31T23:59:59.999999';

    UPDATE dbo.contract_version
       SET tx_to = @e9_time
    WHERE player_id = 19 AND valid_from = '2024-07-01'
      AND valid_to = '9999-12-31'
      AND tx_to = '9999-12-31T23:59:59.999999';

    /* Club 2 keeps its former name until the effective date, then is renamed. */
    INSERT INTO dbo.club_version
        (club_id, league_id, club_name, city, valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT 2, league_id, club_name, city, valid_from, @effective_date,
           @e9_time, '9999-12-31T23:59:59.999999', @e9_tx
    FROM @club2;

    INSERT INTO dbo.club_version
        (club_id, league_id, club_name, city, valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT 2, league_id, N'Cluj Wolves FC', city, @effective_date, '9999-12-31',
           @e9_time, '9999-12-31T23:59:59.999999', @e9_tx
    FROM @club2;

    /* Player 19's old club relationship ends as the transfer takes effect. */
    INSERT INTO dbo.contract_version
        (player_id, club_id, season_id, contract_type, shirt_number,
         valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT 19, old_club_id, season_id, contract_type, shirt_number,
           valid_from, @effective_date, @e9_time,
           '9999-12-31T23:59:59.999999', @e9_tx
    FROM @player19;

    /* New relationship belongs to the 2025/2026 season. */
    INSERT INTO dbo.contract_version
        (player_id, club_id, season_id, contract_type, shirt_number,
         valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT 19, 2, 2, N'Permanent', shirt_number,
           @effective_date, '9999-12-31', @e9_time,
           '9999-12-31T23:59:59.999999', @e9_tx
    FROM @player19;

    COMMIT TRANSACTION;
    PRINT 'E9 completed: club_version and contract_version changed under the same tx_id.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* 10. Summary checks for the timeline. These do not replace 05_tests.sql. */
PRINT '03_timeline.sql completed: events E2-E9 committed.';

SELECT tx_id, tx_time, author, reason
FROM dbo.tx_registry
ORDER BY tx_time, tx_id;

SELECT N'contract_version' AS table_name,
       COUNT_BIG(*) AS all_version_rows,
       SUM(CASE WHEN tx_to = '9999-12-31T23:59:59.999999' THEN 1 ELSE 0 END) AS current_transaction_rows
FROM dbo.contract_version
UNION ALL
SELECT N'player_salary_version', COUNT_BIG(*),
       SUM(CASE WHEN tx_to = '9999-12-31T23:59:59.999999' THEN 1 ELSE 0 END)
FROM dbo.player_salary_version
UNION ALL
SELECT N'coach_assignment_version', COUNT_BIG(*),
       SUM(CASE WHEN tx_to = '9999-12-31T23:59:59.999999' THEN 1 ELSE 0 END)
FROM dbo.coach_assignment_version
UNION ALL
SELECT N'club_version', COUNT_BIG(*),
       SUM(CASE WHEN tx_to = '9999-12-31T23:59:59.999999' THEN 1 ELSE 0 END)
FROM dbo.club_version
ORDER BY table_name;
GO
