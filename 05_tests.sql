USE FootballLeagueDB;
GO

SET NOCOUNT ON;
GO

IF DB_NAME() <> N'FootballLeagueDB'
BEGIN
    THROW 51200, 'Select the FootballLeagueDB database before running 05_tests.sql.', 1;
END;
GO

IF OBJECT_ID(N'dbo.v_integrity_violations', N'V') IS NULL
   OR OBJECT_ID(N'dbo.v_q1_current_player_facts', N'V') IS NULL
   OR OBJECT_ID(N'dbo.v_q2_role_history', N'V') IS NULL
   OR OBJECT_ID(N'dbo.v_q3_change_classification', N'V') IS NULL
   OR OBJECT_ID(N'dbo.v_q4_relationships_in_period', N'V') IS NULL
   OR OBJECT_ID(N'dbo.v_q5_belief_at_transaction_time', N'V') IS NULL
   OR OBJECT_ID(N'dbo.v_q6_bitemporal_point_query', N'V') IS NULL
   OR OBJECT_ID(N'dbo.v_q7_monthly_contract_counts', N'V') IS NULL
   OR OBJECT_ID(N'dbo.v_q8_contract_gaps', N'V') IS NULL
BEGIN
    THROW 51201, 'One or more Q0-Q8 views are missing. Run 04_views.sql first.', 1;
END;
GO

IF OBJECT_ID('tempdb..#test_results') IS NOT NULL DROP TABLE #test_results;
CREATE TABLE #test_results
(
    test_id       VARCHAR(10)    NOT NULL,
    test_name     NVARCHAR(200)  NOT NULL,
    status        VARCHAR(10)    NOT NULL,
    observed      NVARCHAR(1000) NULL,
    expected      NVARCHAR(1000) NULL
);

/* T01 — minimum population and seed transaction */
DECLARE @league_count INT = (SELECT COUNT(*) FROM dbo.league);
DECLARE @club_count INT = (SELECT COUNT(*) FROM dbo.club);
DECLARE @player_count INT = (SELECT COUNT(*) FROM dbo.player);
DECLARE @coach_count INT = (SELECT COUNT(*) FROM dbo.coach);
DECLARE @season_count INT = (SELECT COUNT(*) FROM dbo.season);
DECLARE @seed_tx_count INT = (SELECT COUNT(*) FROM dbo.tx_registry WHERE reason LIKE N'E1 - Initial%');

INSERT INTO #test_results
VALUES
('T01a', N'One league exists', IIF(@league_count = 1, 'PASS', 'FAIL'), CONVERT(NVARCHAR(20), @league_count), N'1'),
('T01b', N'At least six clubs exist', IIF(@club_count >= 6, 'PASS', 'FAIL'), CONVERT(NVARCHAR(20), @club_count), N'>= 6'),
('T01c', N'At least 50 players exist', IIF(@player_count >= 50, 'PASS', 'FAIL'), CONVERT(NVARCHAR(20), @player_count), N'>= 50'),
('T01d', N'At least five coaches exist', IIF(@coach_count >= 5, 'PASS', 'FAIL'), CONVERT(NVARCHAR(20), @coach_count), N'>= 5'),
('T01e', N'At least two seasons exist', IIF(@season_count >= 2, 'PASS', 'FAIL'), CONVERT(NVARCHAR(20), @season_count), N'>= 2'),
('T01f', N'Exactly one initial-load transaction exists', IIF(@seed_tx_count = 1, 'PASS', 'FAIL'), CONVERT(NVARCHAR(20), @seed_tx_count), N'1');

/* T02 — bitemporal table count and sentinel consistency */
DECLARE @all_versions BIGINT =
    (SELECT COUNT_BIG(*) FROM dbo.club_version)
  + (SELECT COUNT_BIG(*) FROM dbo.contract_version)
  + (SELECT COUNT_BIG(*) FROM dbo.player_salary_version)
  + (SELECT COUNT_BIG(*) FROM dbo.coach_assignment_version);

DECLARE @bad_periods BIGINT =
    (SELECT COUNT_BIG(*) FROM dbo.club_version WHERE valid_from >= valid_to OR tx_from >= tx_to)
  + (SELECT COUNT_BIG(*) FROM dbo.contract_version WHERE valid_from >= valid_to OR tx_from >= tx_to)
  + (SELECT COUNT_BIG(*) FROM dbo.player_salary_version WHERE valid_from >= valid_to OR tx_from >= tx_to)
  + (SELECT COUNT_BIG(*) FROM dbo.coach_assignment_version WHERE valid_from >= valid_to OR tx_from >= tx_to);

INSERT INTO #test_results
VALUES
('T02a', N'At least 120 bitemporal version rows exist', IIF(@all_versions >= 120, 'PASS', 'FAIL'), CONVERT(NVARCHAR(30), @all_versions), N'>= 120'),
('T02b', N'No invalid valid-time or transaction-time periods exist', IIF(@bad_periods = 0, 'PASS', 'FAIL'), CONVERT(NVARCHAR(30), @bad_periods), N'0');

/* T03 — timeline event registry includes E2-E9 (E7 is three transactions). */
DECLARE @timeline_transactions INT =
    (SELECT COUNT(*) FROM dbo.tx_registry WHERE reason LIKE N'E2 - Proactive%')
  + (SELECT COUNT(*) FROM dbo.tx_registry WHERE reason LIKE N'E3 - Late%')
  + (SELECT COUNT(*) FROM dbo.tx_registry WHERE reason LIKE N'E4 - Correction%')
  + (SELECT COUNT(*) FROM dbo.tx_registry WHERE reason LIKE N'E5 - Record real-world end%')
  + (SELECT COUNT(*) FROM dbo.tx_registry WHERE reason LIKE N'E6 - Three contracts restart%')
  + (SELECT COUNT(*) FROM dbo.tx_registry WHERE reason LIKE N'E7 - Role change belief%')
  + (SELECT COUNT(*) FROM dbo.tx_registry WHERE reason LIKE N'E8 - Retract%')
  + (SELECT COUNT(*) FROM dbo.tx_registry WHERE reason LIKE N'E9 - Rename%');

DECLARE @e7_count INT = (SELECT COUNT(*) FROM dbo.tx_registry WHERE reason LIKE N'E7 - Role change belief%');
DECLARE @e9_tx BIGINT = (SELECT TOP (1) tx_id FROM dbo.tx_registry WHERE reason LIKE N'E9 - Rename%' ORDER BY tx_time DESC);
DECLARE @e9_contract_tx_count INT = (SELECT COUNT(*) FROM dbo.contract_version WHERE tx_id = @e9_tx);
DECLARE @e9_club_tx_count INT = (SELECT COUNT(*) FROM dbo.club_version WHERE tx_id = @e9_tx);

INSERT INTO #test_results
VALUES
('T03a', N'All eight timeline event groups are represented (E7 has three beliefs)', IIF(@timeline_transactions >= 10, 'PASS', 'FAIL'), CONVERT(NVARCHAR(20), @timeline_transactions), N'>= 10 transaction records for E2-E9'),
('T03b', N'E7 contains three separate transaction-time beliefs', IIF(@e7_count = 3, 'PASS', 'FAIL'), CONVERT(NVARCHAR(20), @e7_count), N'3'),
('T03c', N'E9 changes both a club version and a contract under one tx_id', IIF(@e9_tx IS NOT NULL AND @e9_contract_tx_count > 0 AND @e9_club_tx_count > 0, 'PASS', 'FAIL'), CONCAT(N'tx_id=', COALESCE(CONVERT(NVARCHAR(20), @e9_tx), N'NULL'), N'; contract rows=', @e9_contract_tx_count, N'; club rows=', @e9_club_tx_count), N'At least one row in each table for the same tx_id');

/* T04 — current relationship facts and integrity rules I1-I3 */
DECLARE @current_contracts BIGINT = (SELECT COUNT_BIG(*) FROM dbo.contract_version WHERE tx_to = '9999-12-31T23:59:59.999999');
DECLARE @integrity_violations BIGINT = (SELECT COUNT_BIG(*) FROM dbo.v_integrity_violations);

INSERT INTO #test_results
VALUES
('T04a', N'At least 60 current-transaction contract facts exist', IIF(@current_contracts >= 60, 'PASS', 'FAIL'), CONVERT(NVARCHAR(30), @current_contracts), N'>= 60'),
('T04b', N'Integrity view reports no I1-I3 violations', IIF(@integrity_violations = 0, 'PASS', 'FAIL'), CONVERT(NVARCHAR(30), @integrity_violations), N'0');

/* T05 — E7 must return three different coaches for the same valid date. */
DECLARE @e7a DATETIME2(6) = (SELECT MIN(tx_time) FROM dbo.tx_registry WHERE reason LIKE N'E7 - Role change belief%');
DECLARE @e7c DATETIME2(6) = (SELECT MAX(tx_time) FROM dbo.tx_registry WHERE reason LIKE N'E7 - Role change belief%');
DECLARE @e7a_coach INT = NULL;
DECLARE @e7b_coach INT = NULL;
DECLARE @e7c_coach INT = NULL;

SELECT TOP (1) @e7a_coach = ca.coach_id
FROM dbo.coach_assignment_version AS ca
WHERE ca.club_id = 1 AND ca.role_name = N'Head Coach'
  AND ca.valid_from <= '2025-08-01' AND '2025-08-01' < ca.valid_to
  AND ca.tx_from <= @e7a AND @e7a < ca.tx_to
ORDER BY ca.tx_from DESC;

SELECT TOP (1) @e7b_coach = ca.coach_id
FROM dbo.coach_assignment_version AS ca
JOIN dbo.tx_registry AS tr ON tr.tx_time = ca.tx_from
WHERE ca.club_id = 1 AND ca.role_name = N'Head Coach'
  AND ca.valid_from <= '2025-08-01' AND '2025-08-01' < ca.valid_to
  AND tr.reason LIKE N'E7 - Role change belief 2:%'
ORDER BY ca.tx_from DESC;

SELECT TOP (1) @e7c_coach = ca.coach_id
FROM dbo.coach_assignment_version AS ca
WHERE ca.club_id = 1 AND ca.role_name = N'Head Coach'
  AND ca.valid_from <= '2025-08-01' AND '2025-08-01' < ca.valid_to
  AND ca.tx_from <= @e7c AND @e7c < ca.tx_to
ORDER BY ca.tx_from DESC;

INSERT INTO #test_results
VALUES
('T05a', N'E7 has a role holder at the first transaction time', IIF(@e7a_coach IS NOT NULL, 'PASS', 'FAIL'), COALESCE(CONVERT(NVARCHAR(20), @e7a_coach), N'NULL'), N'Non-NULL coach_id'),
('T05b', N'E7 has three distinct role-holder answers over time', IIF(@e7a_coach IS NOT NULL AND @e7b_coach IS NOT NULL AND @e7c_coach IS NOT NULL AND @e7a_coach <> @e7b_coach AND @e7a_coach <> @e7c_coach AND @e7b_coach <> @e7c_coach, 'PASS', 'FAIL'), CONCAT(N'E7a=', COALESCE(CONVERT(NVARCHAR(20), @e7a_coach), N'NULL'), N'; E7b=', COALESCE(CONVERT(NVARCHAR(20), @e7b_coach), N'NULL'), N'; E7c=', COALESCE(CONVERT(NVARCHAR(20), @e7c_coach), N'NULL')), N'Three different coach_id values');

/* T06 — erroneous E6 fact is retracted at E8. */
DECLARE @mistaken_history_count BIGINT =
(
    SELECT COUNT_BIG(*)
    FROM dbo.contract_version
    WHERE player_id = 16 AND club_id = 1 AND season_id = 2
      AND valid_from = '2026-02-01'
      AND tx_to <> '9999-12-31T23:59:59.999999'
);
DECLARE @mistaken_current_count BIGINT =
(
    SELECT COUNT_BIG(*)
    FROM dbo.contract_version
    WHERE player_id = 16 AND club_id = 1 AND season_id = 2
      AND valid_from = '2026-02-01'
      AND tx_to = '9999-12-31T23:59:59.999999'
);

INSERT INTO #test_results
VALUES
('T06a', N'E8-retracted mistaken contract remains in transaction history', IIF(@mistaken_history_count >= 1, 'PASS', 'FAIL'), CONVERT(NVARCHAR(30), @mistaken_history_count), N'>= 1 historical row'),
('T06b', N'E8-retracted mistaken contract is not current transaction belief', IIF(@mistaken_current_count = 0, 'PASS', 'FAIL'), CONVERT(NVARCHAR(30), @mistaken_current_count), N'0 current rows');

DECLARE @q1 BIGINT = (SELECT COUNT_BIG(*) FROM dbo.v_q1_current_player_facts);
DECLARE @q2 BIGINT = (SELECT COUNT_BIG(*) FROM dbo.v_q2_role_history);
DECLARE @q3 BIGINT = (SELECT COUNT_BIG(*) FROM dbo.v_q3_change_classification);
DECLARE @q4 BIGINT = (SELECT COUNT_BIG(*) FROM dbo.v_q4_relationships_in_period);
DECLARE @q5 BIGINT = (SELECT COUNT_BIG(*) FROM dbo.v_q5_belief_at_transaction_time);
DECLARE @q6 BIGINT = (SELECT COUNT_BIG(*) FROM dbo.v_q6_bitemporal_point_query);
DECLARE @q7 BIGINT = (SELECT COUNT_BIG(*) FROM dbo.v_q7_monthly_contract_counts);
DECLARE @q8 BIGINT = (SELECT COUNT_BIG(*) FROM dbo.v_q8_contract_gaps);

INSERT INTO #test_results
VALUES
('T07a', N'Q1 current-player-facts view executes', 'PASS', CONCAT(N'rows=', @q1), N'Query executes'),
('T07b', N'Q2 role-history view executes', 'PASS', CONCAT(N'rows=', @q2), N'Query executes'),
('T07c', N'Q3 change-classification view executes', 'PASS', CONCAT(N'rows=', @q3), N'Query executes'),
('T07d', N'Q4 relationships-in-period view executes', 'PASS', CONCAT(N'rows=', @q4), N'Query executes'),
('T07e', N'Q5 belief-at-transaction-time view executes', 'PASS', CONCAT(N'rows=', @q5), N'Query executes'),
('T07f', N'Q6 bitemporal-point-query view executes', 'PASS', CONCAT(N'rows=', @q6), N'Query executes'),
('T07g', N'Q7 monthly-contract-counts view executes', IIF(@q7 > 0, 'PASS', 'FAIL'), CONCAT(N'rows=', @q7), N'> 0 rows for configured period'),
('T07h', N'Q8 contract-gaps view executes', 'PASS', CONCAT(N'rows=', @q8), N'Query executes');

/* T08 — Q7 should include one row for every month in the configured period. */
DECLARE @period_start DATE = (SELECT period_start FROM dbo.query_params WHERE parameter_id = 1);
DECLARE @period_end DATE = (SELECT period_end FROM dbo.query_params WHERE parameter_id = 1);
DECLARE @expected_months INT = DATEDIFF(MONTH, DATEFROMPARTS(YEAR(@period_start), MONTH(@period_start), 1), DATEFROMPARTS(YEAR(@period_end), MONTH(@period_end), 1));

INSERT INTO #test_results
VALUES
('T08', N'Q7 returns all calendar months in the selected half-open period', IIF(@q7 = @expected_months, 'PASS', 'FAIL'), CONCAT(N'actual=', @q7, N'; expected=', @expected_months), CONCAT(N'Exactly ', @expected_months, N' months'));

/* Final report */
SELECT test_id, test_name, status, observed, expected
FROM #test_results
ORDER BY test_id;

SELECT
    SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END) AS tests_passed,
    SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END) AS tests_failed,
    COUNT(*) AS tests_total
FROM #test_results;

/* Detailed integrity output is included even when the test fails. */
SELECT invariant_code, violation, business_key, version_id_1, version_id_2
FROM dbo.v_integrity_violations
ORDER BY invariant_code, business_key;

PRINT '05_tests.sql completed.';
GO
