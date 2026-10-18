# Two Clocks --- Bază de date bitemporală pentru o ligă de fotbal

**Disciplina:** Capitole avansate de baze de date și baze de date în
cloud\
**Tema:** Assignment 1 --- Two Clocks: Build a Bitemporal Database\
**Domeniu:** Ligă de fotbal\
**SGBD:** Microsoft SQL Server 2022\
**Facut de:** Guia Alex

## 1. Scopul proiectului

Proiectul modelează o ligă de fotbal folosind două dimensiuni temporale:

-   **Timp valid (`valid time`):** perioada în care o informație este
    adevărată în realitate.
-   **Timp tranzacțional (`transaction time`):** perioada în care baza
    de date păstrează o anumită versiune a informației.

Un contract poate fi introdus după data la care a început, iar o
informație deja introdusă poate fi corectată ulterior fără ștergerea
versiunii anterioare. Baza de date poate astfel răspunde la întrebări
despre ce era valabil la o dată și ce informații erau cunoscute la un
anumit moment.

## 2. Fișierele proiectului

``` text
<Guia_Alex>/
├── README.md
├── 01_schema.sql
├── 02_data.sql
├── 03_timeline.sql
├── 04_views.sql
├── 05_tests.sql
├── er_diagram.pdf
├── er_diagram.png
├── er_diagram.dot
└── report.pdf
```


## 3. Modelul de date

Schema separă identitatea entităților de valorile care se schimbă în
timp.

  -----------------------------------------------------------------------
  Tabel                               Rol
  ----------------------------------- -----------------------------------
  `league`                            Identitatea ligii.

  `club`                              Identitatea stabilă a clubului.

  `player`                            Datele de identitate ale
                                      jucătorilor.

  `coach`                             Datele de identitate ale
                                      antrenorilor.

  `season`                            Sezoanele și intervalele lor
                                      calendaristice.

  `club_version`                      Versiunile bitemporale ale numelui,
                                      orașului și ligii unui club.

  `contract_version`                  Versiunile bitemporale ale relației
                                      jucător--club, inclusiv contracte
                                      și împrumuturi.

  `player_salary_version`             Versiunile bitemporale ale
                                      salariului jucătorului.

  `coach_assignment_version`          Versiunile bitemporale ale
                                      rolurilor antrenorilor în cluburi.

  `tx_registry`                       Registrul tranzacțiilor logice, cu
                                      moment, autor și motiv.

  `query_params`                      Parametrii folosiți de view-urile
                                      temporale.

  `calendar_month`                    Calendarul lunar folosit de Q7
                                      pentru a include lunile fără
                                      rezultate.
  -----------------------------------------------------------------------

Cele patru tabele de versiuni conțin `valid_from`, `valid_to`,
`tx_from`, `tx_to` și `tx_id`. Cheile străine conectează versiunile la
tabelele anchor și la `tx_registry`.

### Convenții temporale

-   Intervalele sunt semi-deschise: `[început, sfârșit)`. Începutul este
    inclus, sfârșitul este exclus.
-   Timpul valid folosește `DATE`, deoarece faptele sunt modelate la
    nivel de zi.
-   Timpul tranzacțional folosește `DATETIME2(6)`, cu precizie de
    microsecunde. Valorile tranzacționale sunt simulate în UTC.
-   Capătul valid deschis este `9999-12-31`.
-   Capătul tranzacțional deschis este `9999-12-31 23:59:59.999999`.
-   Fiecare tabel bitemporal verifică `valid_from < valid_to` și
    `tx_from < tx_to`.
-   O versiune este curentă tranzacțional dacă
    `tx_to = '9999-12-31 23:59:59.999999'`.
-   Indexul `IX_contract_asof` este definit pentru interogări de tip
    *as-of* asupra `contract_version`.

La o schimbare, versiunea veche este închisă tranzacțional, iar
versiunea nouă este inserată când este necesar. Dacă un fapt încetează
să fie adevărat în realitate, se înregistrează sfârșitul timpului valid.
Dacă un fapt nu a fost niciodată adevărat, înregistrarea este retrasă
prin închiderea timpului tranzacțional, fără versiune de înlocuire.

## 4. Cerințe de sistem

-   Microsoft SQL Server 2022.
-   SQL Server Management Studio (SSMS) 19 sau o versiune compatibilă.
-   Permisiuni pentru crearea bazei de date, tabelelor, view-urilor și
    indexurilor.

Fișierul `postgresql11_temporal_demo.sql` folosește sintaxă PostgreSQL
și nu se execută direct în SQL Server. Scripturile proiectului sunt
scrise în T-SQL.

## 5. Instalare și rulare

Scripturile se execută în ordinea `01_schema.sql` → `02_data.sql` →
`03_timeline.sql` → `04_views.sql` → `05_tests.sql`.

### Pasul 1 --- Crearea bazei de date

Dacă baza de date nu există, deschide o fereastră de query în SSMS și
execută:

``` sql
CREATE DATABASE FootballLeagueDB;
GO
USE FootballLeagueDB;
GO
```

Dacă baza de date există deja, selectează `FootballLeagueDB` în
selectorul de baze de date înainte de a rula fiecare fișier.

### Pasul 2 --- Rularea scripturilor

1.  **`01_schema.sql`** --- creează tabelele, cheile primare și străine,
    constrângerile și indexurile. Scriptul recreează tabelele
    proiectului și șterge datele existente în acestea.
2.  **`02_data.sql`** --- execută E1, încărcarea inițială: o ligă, șase
    cluburi, 50 de jucători, șase antrenori, două sezoane și versiunile
    temporale inițiale. Versiunile E1 folosesc același `tx_id` și
    același `tx_from`. Scriptul refuză încărcarea dacă găsește deja
    date.
3.  **`03_timeline.sql`** --- execută evenimentele E2--E9 în ordinea
    timpului tranzacțional. Scriptul verifică evenimentele și refuză
    repetarea cronologiei pentru a evita dublarea datelor.
4.  **`04_views.sql`** --- configurează parametrii de interogare,
    pregătește calendarul lunar și creează view-urile Q0--Q8. Execută
    verificări preliminare pentru integritate și interogări temporale.
5.  **`05_tests.sql`** --- rulează testele pentru populație, volume,
    evenimente, integritate și view-uri. Afișează rezultatele
    `PASS`/`FAIL`, un sumar și datele întoarse de Q0--Q8.

Pentru fiecare fișier: 1. Deschide fișierul în SSMS. 2. Selectează
`FootballLeagueDB`. 3. Apasă **F5 (Execute)**. 4. Verifică taburile
**Messages** și **Results**.

### Reluarea de la zero

Pentru a reproduce proiectul de la început, execută din nou
`01_schema.sql`, apoi `02_data.sql`, `03_timeline.sql`, `04_views.sql`
și `05_tests.sql`, în această ordine. Atenție: `01_schema.sql` recreează
schema și șterge datele proiectului. Nu rula din nou `02_data.sql` sau
`03_timeline.sql` pe o bază de date deja populată.

## 6. Date inițiale și volume

Datele inițiale conțin o ligă, șase cluburi, 50 de jucători, șase
antrenori și două sezoane.

  Sezon         Interval valid
  ------------- ----------------------------
  `2024/2025`   `[2024-07-01, 2025-07-01)`
  `2025/2026`   `[2025-07-01, 2026-07-01)`

După executarea `03_timeline.sql`, sumarul afișat în SSMS a fost:

  Tabel bitemporal               Toate versiunile   Versiuni curente tranzacțional
  ---------------------------- ------------------ --------------------------------
  `club_version`                                8                                7
  `coach_assignment_version`                   10                                7
  `contract_version`                           83                               65
  `player_salary_version`                      57                               54
  **Total**                               **158**                          **133**

Tabelul `contract_version` are 65 de rânduri curente tranzacțional, iar
cele patru tabele bitemporale conțin în total 158 de versiuni.

## 7. Jurnalul evenimentelor E1--E9

Momentele tranzacționale de mai jos sunt valori simulate, exprimate în
UTC. Timpul valid descrie perioada din realitate, iar timpul
tranzacțional arată când a fost înregistrată versiunea în baza de date.

  ------------------------------------------------------------------------------------
  Eveniment               Descriere și timp valid       Timp tranzacțional
  ----------------------- ----------------------------- ------------------------------
  **E1 --- Încărcare      Sunt introduse liga,          `2026-03-10 14:00:00.000000`
  inițială**              cluburile, jucătorii,         
                          antrenorii, sezoanele și      
                          faptele inițiale. Perioadele  
                          inițiale încep la             
                          `2024-07-01` și au capăt      
                          valid deschis.                

  **E2 --- Modificare     Salariile a trei jucători se  `2026-03-11 09:00:00.000000`
  proactivă**             modifică începând cu          
                          `2026-04-01`. Modificarea     
                          este înregistrată înainte să  
                          intre în vigoare.             

  **E3 --- Introducere    Sunt introduse cinci fapte    `2026-03-12 10:30:00.000000`
  întârziată**            istorice de împrumut,         
                          valabile în intervalul        
                          `[2025-01-01, 2025-03-01)`.   

  **E4 --- Corectarea     Sunt corectate numerele de    `2026-03-13 11:15:00.000000`
  unei valori**           tricou pentru trei contracte. 
                          Versiunile anterioare sunt    
                          păstrate în istoricul         
                          tranzacțional.                

  **E5 --- Încetare       Cinci contracte se încheie în `2026-03-14 08:45:00.000000`
  reală**                 timp valid la `2026-02-01`.   

  **E6 --- Reluare după o Pentru jucătorii 16--18, o    `2026-03-15 13:20:00.000000`
  pauză**                 perioadă contractuală se      
                          încheie la `2025-07-01`, iar  
                          următoarea începe la          
                          `2025-09-01`, lăsând o pauză. 
                          Este introdus și un contract  
                          eronat pentru jucătorul 16,   
                          cu perioada pretinsă          
                          `[2025-07-10, 2025-08-10)`.   

  **E7a --- Prima         Pentru clubul 1, antrenorul 2 `2026-03-16 08:00:00.000000`
  versiune a rolului**    este considerat `Head Coach`  
                          de la `2025-08-01`.           

  **E7b --- Corectarea    Pentru aceeași dată validă,   `2026-03-16 12:00:00.000000`
  rolului**               `2025-08-01`, baza de date    
                          consideră că antrenorul 3     
                          este `Head Coach` al clubului 
                          1.                            

  **E7c --- A doua        Pentru aceeași dată validă,   `2026-03-17 09:00:00.000000`
  corectare a rolului**   `2025-08-01`, baza de date    
                          consideră că antrenorul 4     
                          este `Head Coach` al clubului 
                          1.                            

  **E8 --- Retragerea     Contractul pretins valabil în `2026-03-18 10:00:00.000000`
  unui fapt eronat**      `[2025-07-10, 2025-08-10)`    
                          este retras tranzacțional.    
                          Înregistrarea rămâne în       
                          istoric și nu este înlocuită  
                          cu un fapt nou.               

  **E9 --- Modificare în  La `2026-05-01`, clubul 2 își `2026-03-19 14:30:00.000000`
  două tabele**           schimbă numele din            
                          `Cluj Wolves` în              
                          `Cluj Wolves FC`, iar         
                          contractul jucătorului 19     
                          este modificat în aceeași     
                          tranzacție logică. Ambele     
                          tabele folosesc același       
                          `tx_id`.                      
  ------------------------------------------------------------------------------------

### Trei răspunsuri pentru aceeași dată validă

Întrebarea este: „Cine era `Head Coach` al clubului 1 la `2025-08-01`,
conform informațiilor cunoscute la momentul ales?"

  Moment tranzacțional       Răspuns
  -------------------------- ----------------
  După E7a, înainte de E7b   `coach_id = 2`
  După E7b, înainte de E7c   `coach_id = 3`
  După E7c                   `coach_id = 4`

Răspunsurile diferă deoarece baza de date a primit două corectări
succesive pentru aceeași dată validă. Versiunile tranzacționale
anterioare sunt păstrate.

## 8. View-urile Q0--Q8

Parametrii de interogare sunt stocați în rândul `parameter_id = 1` din
`dbo.query_params`.

  Parametru        Valoare implicită
  ---------------- ------------------------------
  `subject_id`     `1`
  `valid_at`       `2025-08-01`
  `known_at`       `2026-03-20 00:00:00.000000`
  `period_start`   `2025-07-01`
  `period_end`     `2026-07-01`

Pentru schimbarea parametrilor, actualizează rândul respectiv din
`dbo.query_params`, apoi interoghează view-ul dorit.

  -----------------------------------------------------------------------------------
  Întrebare               View                                Scop
  ----------------------- ----------------------------------- -----------------------
  **Q0**                  `v_integrity_violations`            Detectează încălcările
                                                              I1, I2 și I3:
                                                              suprapuneri de
                                                              perioade, acoperire
                                                              temporală a entității
                                                              părinte și unicitatea
                                                              titularului unui rol.

  **Q1**                  `v_q1_current_player_facts`         Afișează informațiile
                                                              contractuale pentru
                                                              jucătorul selectat.

  **Q2**                  `v_q2_role_history`                 Afișează istoricul
                                                              rolurilor, unește
                                                              perioadele adiacente
                                                              pentru același titular
                                                              și calculează durata
                                                              mandatului.

  **Q3**                  `v_q3_change_classification`        Clasifică evenimentele
                                                              și modificările
                                                              înregistrate în
                                                              cronologie.

  **Q4**                  `v_q4_relationships_in_period`      Identifică relațiile
                                                              care se suprapun cu
                                                              perioada selectată sau
                                                              sunt cuprinse în
                                                              aceasta.

  **Q5**                  `v_q5_belief_at_transaction_time`   Afișează relațiile
                                                              pentru jucătorul
                                                              selectat, conform
                                                              timpului valid și
                                                              timpului tranzacțional
                                                              configurate.

  **Q6**                  `v_q6_bitemporal_point_query`       Interoghează relația
                                                              jucător--club la un
                                                              timp valid și un timp
                                                              tranzacțional.

  **Q7**                  `v_q7_monthly_contract_counts`      Numără lunar relațiile
                                                              contractuale active și
                                                              include lunile fără
                                                              rezultate.

  **Q8**                  `v_q8_contract_gaps`                Folosește `LAG` pentru
                                                              a identifica pauzele
                                                              dintre perioadele
                                                              valide succesive ale
                                                              unui jucător.
  -----------------------------------------------------------------------------------

Predicatul bitemporal folosit pentru o versiune este:

``` sql
valid_from <= @valid_at
AND @valid_at < valid_to
AND tx_from <= @known_at
AND @known_at < tx_to
```

## 9. Testare

`05_tests.sql` se execută după celelalte patru scripturi. Afișează
rezultatul fiecărui test (`PASS` sau `FAIL`), valoarea observată și
valoarea așteptată, un sumar cu `tests_passed`, `tests_failed` și
`tests_total`, rezultatul `v_integrity_violations` și seturile de
rezultate Q1--Q8.

Testele acoperă populația inițială, numărul versiunilor, evenimentele
E2--E9, modificarea din două tabele la E9, contractele curente, cele
trei versiuni ale rolului din E7, retragerea din E8 și rezultatele
view-urilor temporale.

Interogări utile pentru verificarea manuală:

``` sql
USE FootballLeagueDB;
GO

SELECT *
FROM dbo.v_integrity_violations;

SELECT tx_id, tx_time, author, reason
FROM dbo.tx_registry
ORDER BY tx_time, tx_id;

SELECT *
FROM dbo.v_q3_change_classification
ORDER BY tx_time;

SELECT *
FROM dbo.v_q6_bitemporal_point_query;
```

## 10. Indexul pentru Q6

Indexul `IX_contract_asof` este definit pe `contract_version` pentru
coloanele `(player_id, tx_to, valid_from)`, cu coloane suplimentare
incluse pentru interogare. Comparația planului de execuție se realizează
în SSMS folosind **Include Actual Execution Plan** (`Ctrl+M`), cu
aceeași interogare Q6 cu indexul disponibil și într-o copie de test fără
index. Planurile se compară după operatorii folosiți, rândurile estimate
și reale, citirile logice și durata execuției.

## 11. Diagrama și raportul

-   `er_diagram.pdf` --- diagrama entităților și relațiilor pentru
    documentație.
-   `er_diagram.png` --- versiunea imagine a diagramei.
-   `er_diagram.dot` --- sursa Graphviz a diagramei.
-   `report.pdf` --- raportul proiectului.

## 12. Fișierele pentru predare

Dosarul proiectului conține `README.md`, scripturile
`01_schema.sql`--`05_tests.sql`, `er_diagram.pdf` și `report.pdf`.
`er_diagram.png` și `er_diagram.dot` sunt incluse împreună cu diagrama.
