USE FootballLeagueDB;
GO

SET NOCOUNT ON;
GO

/* Default query parameters: player 1, valid date 2025-08-01,
   transaction knowledge after E9, and named period 2025/2026. */
IF EXISTS (SELECT 1 FROM dbo.query_params WHERE parameter_id = 1)
    UPDATE dbo.query_params
       SET valid_at = '2025-08-01',
           known_at = '2026-03-20T00:00:00.000000',
           period_start = '2025-07-01',
           period_end = '2026-07-01',
           subject_id = 1
     WHERE parameter_id = 1;
ELSE
    INSERT INTO dbo.query_params
        (parameter_id, valid_at, known_at, period_start, period_end, subject_id)
    VALUES
        (1, '2025-08-01', '2026-03-20T00:00:00.000000', '2025-07-01', '2026-07-01', 1);
GO

/* Q0 — Integrity violations. Checks I1 overlap, I2 parent coverage, I3
   at most one holder per club/role at an instant. Expected result: 0 rows. */
CREATE OR ALTER VIEW dbo.v_integrity_violations
AS
    /* I1: two current-transaction contract facts for one player overlap. */
    SELECT
        CAST(N'I1' AS NVARCHAR(10)) AS invariant_code,
        CAST(N'Overlapping current contract valid periods for one player' AS NVARCHAR(200)) AS violation,
        CAST(a.player_id AS NVARCHAR(40)) AS business_key,
        a.version_id AS version_id_1,
        b.version_id AS version_id_2
    FROM dbo.contract_version AS a
    JOIN dbo.contract_version AS b
      ON b.player_id = a.player_id
     AND b.version_id > a.version_id
     AND a.valid_from < b.valid_to
     AND b.valid_from < a.valid_to
    WHERE a.tx_to = '9999-12-31T23:59:59.999999'
      AND b.tx_to = '9999-12-31T23:59:59.999999'

    UNION ALL

    /* I2: contract period is not fully covered by a current club-version
       period. A contract is valid only if a parent club is known throughout
       its entire valid interval. */
    SELECT
        CAST(N'I2' AS NVARCHAR(10)),
        CAST(N'Contract valid period is not covered by a current club period' AS NVARCHAR(200)),
        CAST(CONCAT(N'player=', cv.player_id, N'; club=', cv.club_id) AS NVARCHAR(40)),
        cv.version_id,
        CAST(NULL AS BIGINT)
    FROM dbo.contract_version AS cv
    WHERE cv.tx_to = '9999-12-31T23:59:59.999999'
      AND NOT EXISTS
      (
          SELECT 1
          FROM dbo.club_version AS parent
          WHERE parent.club_id = cv.club_id
            AND parent.tx_to = '9999-12-31T23:59:59.999999'
            AND parent.valid_from <= cv.valid_from
            AND parent.valid_to >= cv.valid_to
      )

    UNION ALL

    /* I3: two different coaches hold the same role for the same club over
       overlapping valid periods, according to the current transaction view. */
    SELECT
        CAST(N'I3' AS NVARCHAR(10)),
        CAST(N'Multiple holders for the same club role over overlapping valid periods' AS NVARCHAR(200)),
        CAST(CONCAT(N'club=', a.club_id, N'; role=', a.role_name) AS NVARCHAR(40)),
        a.version_id,
        b.version_id
    FROM dbo.coach_assignment_version AS a
    JOIN dbo.coach_assignment_version AS b
      ON b.club_id = a.club_id
     AND b.role_name = a.role_name
     AND b.version_id > a.version_id
     AND b.coach_id <> a.coach_id
     AND a.valid_from < b.valid_to
     AND b.valid_from < a.valid_to
    WHERE a.tx_to = '9999-12-31T23:59:59.999999'
      AND b.tx_to = '9999-12-31T23:59:59.999999';
GO

/* Q1 — Current facts for the selected player (current transaction belief). */
CREATE OR ALTER VIEW dbo.v_q1_current_player_facts
AS
    SELECT
        p.player_id,
        p.full_name,
        cv.club_id,
        clubv.club_name,
        cv.season_id,
        s.season_name,
        cv.contract_type,
        cv.shirt_number,
        cv.valid_from,
        cv.valid_to,
        sv.salary_eur,
        sv.valid_from AS salary_valid_from,
        sv.valid_to AS salary_valid_to
    FROM dbo.player AS p
    LEFT JOIN dbo.contract_version AS cv
      ON cv.player_id = p.player_id
     AND cv.tx_to = '9999-12-31T23:59:59.999999'
    LEFT JOIN dbo.season AS s ON s.season_id = cv.season_id
    LEFT JOIN dbo.club_version AS clubv
      ON clubv.club_id = cv.club_id
     AND clubv.tx_to = '9999-12-31T23:59:59.999999'
     AND cv.valid_from < clubv.valid_to
     AND clubv.valid_from < cv.valid_to
    LEFT JOIN dbo.player_salary_version AS sv
      ON sv.player_id = p.player_id
     AND sv.tx_to = '9999-12-31T23:59:59.999999'
     AND cv.valid_from < sv.valid_to
     AND sv.valid_from < cv.valid_to
    WHERE p.player_id = (SELECT subject_id FROM dbo.query_params WHERE parameter_id = 1);
GO

/* Q2 — Role history with adjacent periods coalesced for each club/role/coach.
   Tenure days are calculated from the coalesced start through end; open roles
   are measured to the current date. */
CREATE OR ALTER VIEW dbo.v_q2_role_history
AS
    WITH current_roles AS
    (
        SELECT ca.*, LAG(ca.valid_to) OVER
          (PARTITION BY ca.club_id, ca.role_name, ca.coach_id ORDER BY ca.valid_from, ca.version_id) AS previous_valid_to
        FROM dbo.coach_assignment_version AS ca
        WHERE ca.tx_to = '9999-12-31T23:59:59.999999'
    ),
    marked AS
    (
        SELECT *, CASE WHEN previous_valid_to = valid_from THEN 0 ELSE 1 END AS new_group
        FROM current_roles
    ),
    grouped AS
    (
        SELECT *, SUM(new_group) OVER
          (PARTITION BY club_id, role_name, coach_id ORDER BY valid_from, version_id ROWS UNBOUNDED PRECEDING) AS period_group
        FROM marked
    ),
    coalesced AS
    (
        SELECT club_id, role_name, coach_id, period_group,
               MIN(valid_from) AS tenure_start,
               MAX(valid_to) AS tenure_end
        FROM grouped
        GROUP BY club_id, role_name, coach_id, period_group
    )
    SELECT c.club_id, cv.club_name, c.role_name, c.coach_id, ch.full_name AS coach_name,
           c.tenure_start, c.tenure_end,
           DATEDIFF(DAY, c.tenure_start,
               CASE WHEN c.tenure_end = '9999-12-31' THEN CONVERT(DATE, GETDATE()) ELSE c.tenure_end END) AS tenure_days
    FROM coalesced AS c
    JOIN dbo.coach AS ch ON ch.coach_id = c.coach_id
    OUTER APPLY
    (
        SELECT TOP (1) v.club_name
        FROM dbo.club_version AS v
        WHERE v.club_id = c.club_id
          AND v.tx_to = '9999-12-31T23:59:59.999999'
          AND v.valid_from < c.tenure_end AND c.tenure_start < v.valid_to
        ORDER BY v.valid_from DESC
    ) AS cv;
GO

/* Q3 — Timeline classification with transaction delay and a concise old/new
   summary. Old/new values are summarized from event reasons and event types;
   detailed row-level before/after values remain queryable in version tables. */
CREATE OR ALTER VIEW dbo.v_q3_change_classification
AS
    SELECT tx_id, tx_time, author, reason,
           CASE
             WHEN reason LIKE N'E2 - Proactive%' THEN N'Proactive'
             WHEN reason LIKE N'E3 - Late%' THEN N'Late entry'
             WHEN reason LIKE N'E4 - Correction%' OR reason LIKE N'E7 - Role change belief%' THEN N'Correction'
             WHEN reason LIKE N'E5 - Record real-world end%' THEN N'Real-world end'
             WHEN reason LIKE N'E6 - Three contracts restart%' THEN N'Restart after gap / includes mistaken insert'
             WHEN reason LIKE N'E8 - Retract%' THEN N'Erroneous retraction'
             WHEN reason LIKE N'E9 - Rename%' THEN N'Multi-table change'
             WHEN reason LIKE N'E1 - Initial%' THEN N'Initial load'
             ELSE N'Other'
           END AS change_type,
           CASE WHEN reason LIKE N'E3 - Late%' THEN DATEDIFF(DAY, CONVERT(DATE, '2025-03-01'), CONVERT(DATE, tx_time))
                WHEN reason LIKE N'E4 - Correction%' THEN NULL
                ELSE NULL END AS delay_days_for_late_entry,
           CASE
             WHEN reason LIKE N'E2 - Proactive%' THEN N'Old salary belief closed; new salary and valid-time segments inserted'
             WHEN reason LIKE N'E3 - Late%' THEN N'Prior contract segmented; historical loan facts inserted'
             WHEN reason LIKE N'E4 - Correction%' THEN N'Old shirt-number belief closed; corrected value inserted'
             WHEN reason LIKE N'E5 - Record real-world end%' THEN N'Open-ended contract belief replaced with valid-time end'
             WHEN reason LIKE N'E6 - Three contracts restart%' THEN N'Contracts restarted after gaps; mistaken fact inserted'
             WHEN reason LIKE N'E7 - Role change belief%' THEN N'Previous role-holder belief closed; new holder belief inserted'
             WHEN reason LIKE N'E8 - Retract%' THEN N'Mistaken version closed in transaction time only'
             WHEN reason LIKE N'E9 - Rename%' THEN N'Club name and player-club relationship changed under one tx_id'
             ELSE N'Initial population inserted'
           END AS old_new_summary
    FROM dbo.tx_registry;
GO

/* Q4 — Relationship facts that overlap or are fully contained in the named
   period [period_start, period_end). */
CREATE OR ALTER VIEW dbo.v_q4_relationships_in_period
AS
    SELECT cv.version_id, cv.player_id, p.full_name, cv.club_id, cl.club_name,
           cv.season_id, s.season_name, cv.contract_type, cv.shirt_number,
           cv.valid_from, cv.valid_to,
           CASE WHEN cv.valid_from >= qp.period_start AND cv.valid_to <= qp.period_end
                THEN N'Contained' ELSE N'Overlaps' END AS period_relation
    FROM dbo.contract_version AS cv
    JOIN dbo.player AS p ON p.player_id = cv.player_id
    JOIN dbo.season AS s ON s.season_id = cv.season_id
    CROSS JOIN dbo.query_params AS qp
    OUTER APPLY
    (
        SELECT TOP (1) club_name
        FROM dbo.club_version AS v
        WHERE v.club_id = cv.club_id
          AND v.tx_to = '9999-12-31T23:59:59.999999'
          AND v.valid_from < cv.valid_to AND cv.valid_from < v.valid_to
        ORDER BY v.valid_from DESC
    ) AS cl
    WHERE qp.parameter_id = 1
      AND cv.tx_to = '9999-12-31T23:59:59.999999'
      AND cv.valid_from < qp.period_end
      AND qp.period_start < cv.valid_to;
GO

/* Q5 — What the database believed at a chosen transaction timestamp for the
   selected valid date. */
CREATE OR ALTER VIEW dbo.v_q5_belief_at_transaction_time
AS
    SELECT qp.valid_at, qp.known_at,
           cv.player_id, p.full_name, cv.club_id, cl.club_name,
           cv.contract_type, cv.shirt_number, cv.valid_from, cv.valid_to,
           cv.tx_from, cv.tx_to, cv.tx_id
    FROM dbo.query_params AS qp
    JOIN dbo.contract_version AS cv
      ON cv.valid_from <= qp.valid_at AND qp.valid_at < cv.valid_to
     AND cv.tx_from <= qp.known_at AND qp.known_at < cv.tx_to
    JOIN dbo.player AS p ON p.player_id = cv.player_id
    OUTER APPLY
    (
        SELECT TOP (1) v.club_name
        FROM dbo.club_version AS v
        WHERE v.club_id = cv.club_id
          AND v.valid_from <= qp.valid_at AND qp.valid_at < v.valid_to
          AND v.tx_from <= qp.known_at AND qp.known_at < v.tx_to
        ORDER BY v.tx_from DESC
    ) AS cl
    WHERE qp.parameter_id = 1
      AND cv.player_id = qp.subject_id;
GO

/* Q6 — Bitemporal point query for one player and one valid-time instant,
   using the transaction-time instant from query_params. */
CREATE OR ALTER VIEW dbo.v_q6_bitemporal_point_query
AS
    SELECT qp.subject_id AS player_id, p.full_name, qp.valid_at, qp.known_at,
           cv.version_id, cv.club_id, cl.club_name, cv.season_id, s.season_name,
           cv.contract_type, cv.shirt_number, cv.valid_from, cv.valid_to,
           cv.tx_from, cv.tx_to, cv.tx_id
    FROM dbo.query_params AS qp
    JOIN dbo.player AS p ON p.player_id = qp.subject_id
    JOIN dbo.contract_version AS cv
      ON cv.player_id = qp.subject_id
     AND cv.valid_from <= qp.valid_at AND qp.valid_at < cv.valid_to
     AND cv.tx_from <= qp.known_at AND qp.known_at < cv.tx_to
    LEFT JOIN dbo.season AS s ON s.season_id = cv.season_id
    OUTER APPLY
    (
        SELECT TOP (1) v.club_name
        FROM dbo.club_version AS v
        WHERE v.club_id = cv.club_id
          AND v.valid_from <= qp.valid_at AND qp.valid_at < v.valid_to
          AND v.tx_from <= qp.known_at AND qp.known_at < v.tx_to
        ORDER BY v.tx_from DESC
    ) AS cl
    WHERE qp.parameter_id = 1;
GO

/* Q7 — Monthly contract counts for the selected period, including zero months.
   Calendar months are generated from dbo.calendar_month; the script below
   seeds that calendar across both seasons if needed. */
IF NOT EXISTS (SELECT 1 FROM dbo.calendar_month WHERE month_start = '2024-07-01')
BEGIN
    ;WITH months AS
    (
        SELECT CONVERT(DATE, '2024-07-01') AS month_start
        UNION ALL
        SELECT DATEADD(MONTH, 1, month_start)
        FROM months
        WHERE month_start < '2026-12-01'
    )
    INSERT INTO dbo.calendar_month (month_start)
    SELECT month_start FROM months
    OPTION (MAXRECURSION 100);
END;
GO

CREATE OR ALTER VIEW dbo.v_q7_monthly_contract_counts
AS
    SELECT cm.month_start,
           COUNT(cv.version_id) AS contract_count
    FROM dbo.query_params AS qp
    JOIN dbo.calendar_month AS cm
      ON cm.month_start >= DATEFROMPARTS(YEAR(qp.period_start), MONTH(qp.period_start), 1)
     AND cm.month_start < DATEFROMPARTS(YEAR(qp.period_end), MONTH(qp.period_end), 1)
    LEFT JOIN dbo.contract_version AS cv
      ON cv.tx_to = '9999-12-31T23:59:59.999999'
     AND cv.valid_from < DATEADD(MONTH, 1, cm.month_start)
     AND cm.month_start < cv.valid_to
    WHERE qp.parameter_id = 1
    GROUP BY cm.month_start;
GO

/* Q8 — Gaps between consecutive current valid periods per player, using LAG. */
CREATE OR ALTER VIEW dbo.v_q8_contract_gaps
AS
    WITH ordered_periods AS
    (
        SELECT cv.player_id, p.full_name, cv.version_id, cv.club_id,
               cv.valid_from, cv.valid_to,
               LAG(cv.valid_to) OVER
                 (PARTITION BY cv.player_id ORDER BY cv.valid_from, cv.version_id) AS previous_valid_to
        FROM dbo.contract_version AS cv
        JOIN dbo.player AS p ON p.player_id = cv.player_id
        WHERE cv.tx_to = '9999-12-31T23:59:59.999999'
    )
    SELECT player_id, full_name, version_id, club_id,
           previous_valid_to AS gap_start,
           valid_from AS gap_end,
           DATEDIFF(DAY, previous_valid_to, valid_from) AS gap_days
    FROM ordered_periods
    WHERE previous_valid_to IS NOT NULL
      AND previous_valid_to < valid_from;
GO

PRINT 'views.sql completed successfully: Q0-Q8 views created.';
GO

/* Quick checks. These return result sets and do not change temporal data. */
SELECT invariant_code, violation, business_key, version_id_1, version_id_2
FROM dbo.v_integrity_violations
ORDER BY invariant_code, business_key;

SELECT * FROM dbo.v_q3_change_classification ORDER BY tx_time;

SELECT * FROM dbo.v_q6_bitemporal_point_query;
GO









