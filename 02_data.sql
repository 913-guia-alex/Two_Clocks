USE FootballLeagueDB
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* 0. Guard against accidental duplicate loading */
IF EXISTS (SELECT 1 FROM dbo.tx_registry)
   OR EXISTS (SELECT 1 FROM dbo.league)
   OR EXISTS (SELECT 1 FROM dbo.club)
   OR EXISTS (SELECT 1 FROM dbo.player)
   OR EXISTS (SELECT 1 FROM dbo.coach)
   OR EXISTS (SELECT 1 FROM dbo.season)
   OR EXISTS (SELECT 1 FROM dbo.club_version)
   OR EXISTS (SELECT 1 FROM dbo.contract_version)
   OR EXISTS (SELECT 1 FROM dbo.player_salary_version)
   OR EXISTS (SELECT 1 FROM dbo.coach_assignment_version)
BEGIN
    THROW 51000, '02_data.sql expects an empty schema. Run 01_schema.sql first, then run 02_data.sql once.', 1;
END;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    /* 1. E1 transaction registry entry: one timestamp for the whole load */
    DECLARE @tx_time DATETIME2(6) = '2026-03-10T14:00:00.000000';
    DECLARE @tx_id BIGINT;

    INSERT INTO dbo.tx_registry (tx_time, author, reason)
    VALUES (@tx_time, N'FootballLeagueDB seed', N'E1 - Initial load of league, clubs, players, coaches, seasons and temporal facts');

    SET @tx_id = CONVERT(BIGINT, SCOPE_IDENTITY());

    /* 2. Stable anchors */
    INSERT INTO dbo.league (league_name, country)
    VALUES (N'Romanian Premier League', N'Romania');

    INSERT INTO dbo.season (season_name, start_date, end_date)
    VALUES
        (N'2024/2025', '2024-07-01', '2025-07-01'),
        (N'2025/2026', '2025-07-01', '2026-07-01');

    /* The club anchor contains identity only; names and cities are temporal. */
    INSERT INTO dbo.club DEFAULT VALUES; -- club_id 1: Bucharest Falcons
    INSERT INTO dbo.club DEFAULT VALUES; -- club_id 2: Cluj Wolves
    INSERT INTO dbo.club DEFAULT VALUES; -- club_id 3: Timisoara Lions
    INSERT INTO dbo.club DEFAULT VALUES; -- club_id 4: Iasi Eagles
    INSERT INTO dbo.club DEFAULT VALUES; -- club_id 5: Constanta Mariners
    INSERT INTO dbo.club DEFAULT VALUES; -- club_id 6: Craiova Royals

    INSERT INTO dbo.player (full_name, birth_date, nationality)
    VALUES
      (N'Andrei Popescu',       '1998-02-14', N'Romanian'),
      (N'Mihai Ionescu',        '1997-07-22', N'Romanian'),
      (N'Alexandru Dumitru',    '2000-11-03', N'Romanian'),
      (N'Gabriel Stan',         '1999-04-18', N'Romanian'),
      (N'Vlad Georgescu',       '1996-09-09', N'Romanian'),
      (N'Radu Matei',           '2001-01-27', N'Romanian'),
      (N'Cristian Rusu',        '1998-06-12', N'Romanian'),
      (N'David Marin',          '2002-03-05', N'Romanian'),
      (N'Stefan Dobre',         '1997-12-16', N'Romanian'),
      (N'Robert Stoica',        '1999-08-30', N'Romanian'),
      (N'Florin Neagu',         '1995-05-21', N'Romanian'),
      (N'Paul Ilie',            '2000-10-11', N'Romanian'),
      (N'Adrian Barbu',         '1998-01-08', N'Romanian'),
      (N'Cosmin Tudor',         '1996-03-19', N'Romanian'),
      (N'Bogdan Enache',        '2001-07-02', N'Romanian'),
      (N'Nicolae Sandu',        '1997-02-25', N'Romanian'),
      (N'Rareș Pavel',          '2002-09-14', N'Romanian'),
      (N'Lucian Munteanu',      '1995-12-07', N'Romanian'),
      (N'Octavian Ilinca',      '1999-06-28', N'Romanian'),
      (N'Valentin Oprea',       '2000-04-02', N'Romanian'),
      (N'Florin Petrescu',      '1998-10-17', N'Romanian'),
      (N'Darius Voicu',         '2001-05-09', N'Romanian'),
      (N'George Nistor',        '1996-08-13', N'Romanian'),
      (N'Alexandru Pavel',      '1997-11-24', N'Romanian'),
      (N'Emil Cristea',         '2000-02-06', N'Romanian'),
      (N'Sebastian Lupu',       '1999-09-01', N'Romanian'),
      (N'Constantin Preda',     '1995-04-29', N'Romanian'),
      (N'Ionut Vasile',         '2002-12-20', N'Romanian'),
      (N'Vasile Dragan',        '1998-07-15', N'Romanian'),
      (N'Claudiu Toma',         '1996-01-31', N'Romanian'),
      (N'Andrei Mocanu',        '2001-03-23', N'Romanian'),
      (N'Gabriel Dima',         '1997-06-04', N'Romanian'),
      (N'Marian Sava',          '1999-01-12', N'Romanian'),
      (N'Catalin Serban',       '2000-08-26', N'Romanian'),
      (N'Florentin Zaharia',    '1995-10-05', N'Romanian'),
      (N'Alexandru Barbu',      '2002-05-18', N'Romanian'),
      (N'Cristian Florea',      '1998-12-02', N'Romanian'),
      (N'Daniel Damian',        '1996-06-20', N'Romanian'),
      (N'Ionel Grigore',        '1997-03-11', N'Romanian'),
      (N'Patrick Moldovan',     '2001-09-27', N'Romanian'),
      (N'Andrei Muresan',       '1999-02-09', N'Romanian'),
      (N'Marius Chiriac',       '1995-07-17', N'Romanian'),
      (N'Alexandru Lazar',      '2000-12-08', N'Romanian'),
      (N'Bogdan Petcu',         '1998-05-30', N'Romanian'),
      (N'Robert Damian',        '2002-01-16', N'Romanian'),
      (N'Florin Coman',         '1996-10-22', N'Romanian'),
      (N'Victor Manole',        '1997-04-07', N'Romanian'),
      (N'Sorin Anghel',         '2001-11-29', N'Romanian'),
      (N'Paul Dinu',            '1999-03-14', N'Romanian'),
      (N'Liviu Balan',          '1995-08-03', N'Romanian'),
      (N'Tudor Stefan',         '2000-06-25', N'Romanian');

    INSERT INTO dbo.coach (full_name, nationality, birth_date)
    VALUES
      (N'Mircea Radu',      N'Romanian', '1974-04-12'),
      (N'Dan Petrescu',     N'Romanian', '1967-12-22'),
      (N'Adrian Mutu',      N'Romanian', '1979-01-08'),
      (N'Ioan Andone',      N'Romanian', '1960-03-15'),
      (N'Cosmin Contra',    N'Romanian', '1975-12-15'),
      (N'Laurentiu Reghecampf', N'Romanian', '1975-09-19');

    /* 3. Bitemporal club facts. Club IDs 1-6 are allocated above in this order. */
    INSERT INTO dbo.club_version
        (club_id, league_id, club_name, city, valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT v.club_id, l.league_id, v.club_name, v.city,
           CONVERT(DATE, '2024-07-01'), CONVERT(DATE, '9999-12-31'),
           @tx_time, CONVERT(DATETIME2(6), '9999-12-31T23:59:59.999999'), @tx_id
    FROM (VALUES
        (1, N'Bucharest Falcons', N'Bucharest'),
        (2, N'Cluj Wolves', N'Cluj-Napoca'),
        (3, N'Timisoara Lions', N'Timisoara'),
        (4, N'Iasi Eagles', N'Iasi'),
        (5, N'Constanta Mariners', N'Constanta'),
        (6, N'Craiova Royals', N'Craiova')
    ) AS v(club_id, club_name, city)
    CROSS JOIN dbo.league AS l;

    /* 4. Initial player-club contracts: one for every player. */
    ;WITH NumberedPlayers AS
    (
        SELECT player_id, ROW_NUMBER() OVER (ORDER BY player_id) AS rn
        FROM dbo.player
    )
    INSERT INTO dbo.contract_version
        (player_id, club_id, season_id, contract_type, shirt_number,
         valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT p.player_id,
           ((p.rn - 1) % 6) + 1,
           s.season_id,
           CASE WHEN p.rn IN (7, 14, 21, 28, 35, 42, 49) THEN N'Loan' ELSE N'Permanent' END,
           CASE WHEN ((p.rn - 1) % 99) + 1 BETWEEN 1 AND 99 THEN ((p.rn - 1) % 99) + 1 END,
           CONVERT(DATE, '2024-07-01'), CONVERT(DATE, '9999-12-31'),
           @tx_time, CONVERT(DATETIME2(6), '9999-12-31T23:59:59.999999'), @tx_id
    FROM NumberedPlayers AS p
    CROSS JOIN dbo.season AS s
    WHERE s.season_name = N'2024/2025';

    /* 5. Initial numeric attribute: yearly salary in EUR for every player. */
    ;WITH NumberedPlayers AS
    (
        SELECT player_id, ROW_NUMBER() OVER (ORDER BY player_id) AS rn
        FROM dbo.player
    )
    INSERT INTO dbo.player_salary_version
        (player_id, salary_eur, valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT player_id,
           CONVERT(DECIMAL(12,2), 18000 + (rn * 1250)),
           CONVERT(DATE, '2024-07-01'), CONVERT(DATE, '9999-12-31'),
           @tx_time, CONVERT(DATETIME2(6), '9999-12-31T23:59:59.999999'), @tx_id
    FROM NumberedPlayers;

    /* 6. Initial head-coach assignment for each of the six clubs. */
    INSERT INTO dbo.coach_assignment_version
        (coach_id, club_id, role_name, valid_from, valid_to, tx_from, tx_to, tx_id)
    SELECT c.coach_id, c.coach_id, N'Head Coach',
           CONVERT(DATE, '2024-07-01'), CONVERT(DATE, '9999-12-31'),
           @tx_time, CONVERT(DATETIME2(6), '9999-12-31T23:59:59.999999'), @tx_id
    FROM dbo.coach AS c;

    COMMIT TRANSACTION;

    /* 7. Basic validation output */
    PRINT '02_data.sql completed successfully: E1 initial load committed.';
    SELECT N'league' AS table_name, COUNT_BIG(*) AS row_count FROM dbo.league
    UNION ALL SELECT N'club', COUNT_BIG(*) FROM dbo.club
    UNION ALL SELECT N'player', COUNT_BIG(*) FROM dbo.player
    UNION ALL SELECT N'coach', COUNT_BIG(*) FROM dbo.coach
    UNION ALL SELECT N'season', COUNT_BIG(*) FROM dbo.season
    UNION ALL SELECT N'club_version', COUNT_BIG(*) FROM dbo.club_version
    UNION ALL SELECT N'contract_version', COUNT_BIG(*) FROM dbo.contract_version
    UNION ALL SELECT N'player_salary_version', COUNT_BIG(*) FROM dbo.player_salary_version
    UNION ALL SELECT N'coach_assignment_version', COUNT_BIG(*) FROM dbo.coach_assignment_version
    UNION ALL SELECT N'tx_registry', COUNT_BIG(*) FROM dbo.tx_registry
    ORDER BY table_name;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
