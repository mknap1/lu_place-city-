-- ===========================================================================
-- 03_apply_codes.sql -- HISTORY, NOT THE RESTORE PATH.
--
-- How citycodes were originally filled in. To RESTORE lu_place use
-- 06_lu_place_snapshot.sql, which already contains all of this plus every later
-- correction. This file exists to explain WHY each code is what it is.
--
-- Every step records how it assigned the code in `notes`, so each is separately
-- reversible and auditable. No code is ever invented: they all come from the
-- research team's file or the upstream DOT file it is built from.
--
-- Coverage after each step (scoped per mv_dim_listing_projection; see 90_*.sql):
--   baseline ......... 91.7%
--   step 1 + 2 ....... 95.1%
--   step 3 ........... 96.5%
--   step 4 ........... 96.5%  (+1,700 listings)
--   step 5 ........... 97.5%
--   step 6 ........... 98.0%
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- Step 1. Spelling variants within the same county.
-- The same town spelled two ways, one coded and one not.
--   SAINT LEONARD = ST LEONARD (Calvert MD), MC CONNELLSBURG = MCCONNELLSBURG
-- Restricted to the same county, so it cannot link two different towns.
-- ~4 rows.
-- ---------------------------------------------------------------------------
UPDATE dwh.lu_place d
SET citycode       = c.citycode,
    countycitycode = d.countyfipscode || c.citycode,
    notes          = 'spelling variant of ' || c.citynamenorm
FROM dwh.lu_place c
WHERE d.citycode IS NULL
  AND c.citycode IS NOT NULL
  AND c.stateabbr      = d.stateabbr
  AND c.countyfipscode = d.countyfipscode
  AND ( REPLACE(c.citynamenorm,' ','') = REPLACE(d.citynamenorm,' ','')
     OR c.citynamenorm = REPLACE(d.citynamenorm,'SAINT ','ST ')
     OR REPLACE(c.citynamenorm,'ST ','SAINT ') = d.citynamenorm );
COMMIT;


-- ---------------------------------------------------------------------------
-- Step 2/3. Parent inherit -- postal-city spillover into a neighbouring county.
--
-- 179,451 listings say "Alexandria, VA" but sit in Fairfax County. Alexandria
-- City is coded 0040; the Fairfax row was blank. TEAM DECISION (~2026-09-11):
-- postal semantics -- those listings count as Alexandria.
--
-- Only fires when the name has EXACTLY ONE citycode in the whole state
-- (HAVING COUNT(DISTINCT citycode) = 1), so it can never pick between two
-- same-named places. Zero ambiguous cases exist in the footprint.
--
-- Also covers: Fredericksburg (Spotsylvania + Stafford), Manassas, Falls
-- Church, Winchester, Charlottesville, YORK TWP -> YORK, LANCASTER TWP ->
-- LANCASTER, Baltimore/Anne Arundel.
--
-- AUDITED: every inherited code was checked against dwh.lu_dot_place for a
-- conflicting code. Zero conflicts. Re-run that check after any reload:
--
--   SELECT p.stateabbr, p.county, p.citynamenorm, p.citycode, d.citycode
--   FROM dwh.lu_place p
--   JOIN dwh.lu_dot_place d
--     ON d.stateabbr = p.stateabbr AND d.countyfipscode = p.countyfipscode
--    AND d.citynamenorm = REGEXP_REPLACE(
--          REPLACE(REPLACE(p.citynamenorm,'SAINT ','ST '),'MOUNT ','MT '),
--          ' (TOWNSHIP|TWP|BOROUGH|BORO)$','')
--   WHERE p.notes LIKE '%inherited from%' AND d.citycode <> p.citycode;
--   -- must return no rows
--
-- REVERSIBLE: countyfipscode stays on every listing, so city-vs-county can be
-- split back apart in a query. This only sets the default grouping.
-- ~460 rows.
-- ---------------------------------------------------------------------------
UPDATE dwh.lu_place d
SET citycode       = p.parentcode,
    countycitycode = d.countyfipscode || p.parentcode,
    notes          = COALESCE(d.notes || ' | ', '') || 'inherited from ' || p.parentcounty
FROM (
  SELECT stateabbr, citynamenorm,
         MIN(citycode) AS parentcode,
         MIN(county)   AS parentcounty
  FROM dwh.lu_place
  WHERE citycode IS NOT NULL
  GROUP BY 1, 2
  HAVING COUNT(DISTINCT citycode) = 1
) p
WHERE d.citycode IS NULL
  AND p.stateabbr    = d.stateabbr
  AND p.citynamenorm = d.citynamenorm;
COMMIT;


-- ---------------------------------------------------------------------------
-- Step 4. Spelling variants statewide, with TWP/BORO/MT/ST folding.
-- Catches MT GRETNA = MOUNT GRETNA, MONROE TWP = MONROE TOWNSHIP, and
-- HONEYBROOK (Lancaster) = HONEY BROOK (Chester).
-- Still requires exactly one code statewide. ~7 rows.
-- ---------------------------------------------------------------------------
UPDATE dwh.lu_place d
SET citycode       = c.parentcode,
    countycitycode = d.countyfipscode || c.parentcode,
    notes          = COALESCE(d.notes || ' | ', '') || 'variant match -> ' || c.parentcounty
FROM (
  SELECT stateabbr,
         REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
           citynamenorm, 'SAINT ', 'ST '), 'MOUNT ', 'MT '),
           ' TOWNSHIP', ' TWP'), ' BOROUGH', ' BORO'), ' ', '') AS k,
         MIN(citycode) AS parentcode,
         MIN(county)   AS parentcounty
  FROM dwh.lu_place
  WHERE citycode IS NOT NULL
  GROUP BY 1, 2
  HAVING COUNT(DISTINCT citycode) = 1
) c
WHERE d.citycode IS NULL
  AND c.stateabbr = d.stateabbr
  AND c.k = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
              d.citynamenorm, 'SAINT ', 'ST '), 'MOUNT ', 'MT '),
              ' TOWNSHIP', ' TWP'), ' BOROUGH', ' BORO'), ' ', '');
COMMIT;


-- ---------------------------------------------------------------------------
-- Step 5. Match uncoded rows against the upstream DOT file.
--
-- The research team's join was exact, so it missed spelling differences:
--   their file: MOUNT LAUREL / Burlington NJ -> Not Found
--   DOT file:   MT LAUREL    / Burlington NJ -> 2081   (31,293 listings)
--
-- Dropping the TOWNSHIP suffix is what unlocks New Jersey, where the data says
-- EWING / HAMILTON and DOT says EWING TOWNSHIP / HAMILTON TOWNSHIP.
--
-- Same county required, so this is stricter than step 2. ~49 rows.
-- ---------------------------------------------------------------------------
UPDATE dwh.lu_place p
SET citycode       = d.citycode,
    countycitycode = p.countyfipscode || d.citycode,
    notes          = COALESCE(p.notes || ' | ', '') || 'DOT match: ' || d.cityname
FROM dwh.lu_dot_place d
WHERE p.citycode IS NULL
  AND d.stateabbr      = p.stateabbr
  AND d.countyfipscode = p.countyfipscode
  AND d.citynamenorm   = REGEXP_REPLACE(
                           REPLACE(REPLACE(p.citynamenorm,'SAINT ','ST '),'MOUNT ','MT '),
                           ' (TOWNSHIP|TWP|BOROUGH|BORO)$','');
COMMIT;


-- ---------------------------------------------------------------------------
-- Step 6. Insert combos absent from lu_place but present in DOT.
--
-- The research team's file only contains combinations they encountered. Our
-- listings have 454 more that DOT covers -- including six ordinary St. Mary's
-- County MD towns (Lexington Park, California, Leonardtown, Mechanicsville,
-- Hollywood, Great Mills).
--
-- Scope filters below MUST match mv_dim_listing_projection.
-- ~454 rows. Undo: DELETE FROM dwh.lu_place WHERE notes LIKE 'added from DOT file%';
-- ---------------------------------------------------------------------------
INSERT INTO dwh.lu_place
  (cityname, citynamenorm, county, stateabbr, countyfipscode,
   citycode, countycitycode, citydisplayname, notes)
WITH mine AS (
  SELECT stateorprovince AS st,
         countyfipscode  AS cfips,
         REGEXP_REPLACE(
           REGEXP_REPLACE(UPPER(TRIM(postalcity)), '[^A-Z ]', ''),
           ' {2,}', ' ')  AS cityname
  FROM dwh.dim_listing dl
  WHERE dl.propertytype = 'Residential'
    AND ISNULL(dl.isdeleted, FALSE) = FALSE
    AND ISNULL(dl.oeyn, FALSE)      = FALSE
    AND dl.listingsourcebusinesspartner NOT IN ('CAAR','CVR','WMB')
    AND dl.brightserviceareayn IS TRUE
    AND dl.postalcity IS NOT NULL AND TRIM(dl.postalcity) <> ''
    AND dl.countyfipscode IS NOT NULL
  GROUP BY 1, 2, 3
),
gaps AS (
  SELECT m.*
  FROM mine m
  LEFT JOIN dwh.lu_place p
         ON p.stateabbr      = m.st
        AND p.countyfipscode = m.cfips
        AND p.citynamenorm   = m.cityname
  WHERE p.citynamenorm IS NULL
)
SELECT g.cityname,
       g.cityname,
       d.county,
       g.st,
       g.cfips,
       d.citycode,
       g.cfips || d.citycode,
       INITCAP(d.cityname) || ' (' || INITCAP(d.county) || ', ' || g.st || ')',
       'added from DOT file: ' || d.cityname
FROM gaps g
JOIN dwh.lu_dot_place d
  ON d.stateabbr      = g.st
 AND d.countyfipscode = g.cfips
 AND d.citynamenorm   = REGEXP_REPLACE(
                          REPLACE(REPLACE(g.cityname,'SAINT ','ST '),'MOUNT ','MT '),
                          ' (TOWNSHIP|TWP|BOROUGH|BORO)$','');
COMMIT;


-- ---------------------------------------------------------------------------
-- Sanity check. Must return no rows -- normalization can make two source rows
-- collide on the join key, which would fan out and double-count listings.
-- ---------------------------------------------------------------------------
SELECT stateabbr, countyfipscode, citynamenorm, COUNT(*)
FROM dwh.lu_place
GROUP BY 1, 2, 3
HAVING COUNT(*) > 1;


-- ---------------------------------------------------------------------------
-- Step 7. Loose DOT match on remaining uncoded rows.
--
-- Steps 5/6 kept spaces, which missed three whole classes of difference:
--   MC HENRY        vs MCHENRY      (space after MC)
--   DISTRICT HEIGHTS vs DISTRICT HTS (DOT abbreviates HEIGHTS; HTS appears
--                                     14x in the footprint, it's a pattern)
--   GREENTREE       vs GREEN TREE   (compound split or joined)
--   BELLE MEAD      vs BELLE-MEAD   (hyphen, already stripped by citynamenorm)
--
-- Fix: fold HEIGHTS/HGTS -> HTS, then ignore spaces entirely. Still same-county
-- only, so it cannot link two different towns. ~58 rows, ~36,000 listings,
-- biggest being DISTRICT HEIGHTS (17,154) and MC HENRY (5,943).
-- ---------------------------------------------------------------------------
UPDATE dwh.lu_place p
SET citycode       = d.citycode,
    countycitycode = p.countyfipscode || d.citycode,
    notes          = COALESCE(p.notes || ' | ', '') || 'DOT match (loose): ' || d.cityname
FROM dwh.lu_dot_place d
WHERE p.citycode IS NULL
  AND d.stateabbr      = p.stateabbr
  AND d.countyfipscode = p.countyfipscode
  AND REPLACE(REGEXP_REPLACE(d.citynamenorm,'(HEIGHTS|HGTS)','HTS'), ' ', '')
    = REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REPLACE(REPLACE(p.citynamenorm,'SAINT ','ST '),'MOUNT ','MT '),
            '(HEIGHTS|HGTS)','HTS'),
          ' (TOWNSHIP|TWP|BOROUGH|BORO)$',''),
        ' ','')
;
COMMIT;


-- ---------------------------------------------------------------------------
-- Step 8. Same loose rules, applied to combos with no lu_place row at all.
--
-- These are typos and spacing errors in the listing data itself:
--   CLIFTON HGTS (3,743), CRUMLYNNE, LAPLATA, NORTHEAST, BELAIR, GLENBURNIE,
--   A LEXANDRIA, OAKLA ND, V INELAND ...
-- ~135 rows, ~4,900 listings. Every one resolves to a real DOT code.
--
-- Undo: DELETE FROM dwh.lu_place WHERE notes LIKE 'added from DOT file (loose)%';
-- ---------------------------------------------------------------------------
INSERT INTO dwh.lu_place
  (cityname, citynamenorm, county, stateabbr, countyfipscode,
   citycode, countycitycode, citydisplayname, notes)
WITH mine AS (
  SELECT stateorprovince AS st,
         countyfipscode  AS cfips,
         REGEXP_REPLACE(
           REGEXP_REPLACE(UPPER(TRIM(postalcity)), '[^A-Z ]', ''),
           ' {2,}', ' ')  AS cityname
  FROM dwh.dim_listing dl
  WHERE dl.propertytype = 'Residential'
    AND ISNULL(dl.isdeleted, FALSE) = FALSE
    AND ISNULL(dl.oeyn, FALSE)      = FALSE
    AND dl.listingsourcebusinesspartner NOT IN ('CAAR','CVR','WMB')
    AND dl.brightserviceareayn IS TRUE
    AND dl.postalcity IS NOT NULL AND TRIM(dl.postalcity) <> ''
    AND dl.countyfipscode IS NOT NULL
  GROUP BY 1, 2, 3
),
gaps AS (
  SELECT m.*
  FROM mine m
  LEFT JOIN dwh.lu_place p
         ON p.stateabbr      = m.st
        AND p.countyfipscode = m.cfips
        AND p.citynamenorm   = m.cityname
  WHERE p.citynamenorm IS NULL
)
SELECT g.cityname, g.cityname, d.county, g.st, g.cfips,
       d.citycode, g.cfips || d.citycode,
       INITCAP(d.cityname) || ' (' || INITCAP(d.county) || ', ' || g.st || ')',
       'added from DOT file (loose): ' || d.cityname
FROM gaps g
JOIN dwh.lu_dot_place d
  ON d.stateabbr      = g.st
 AND d.countyfipscode = g.cfips
 AND REPLACE(REGEXP_REPLACE(d.citynamenorm,'(HEIGHTS|HGTS)','HTS'), ' ', '')
   = REPLACE(
       REGEXP_REPLACE(
         REGEXP_REPLACE(
           REPLACE(REPLACE(g.cityname,'SAINT ','ST '),'MOUNT ','MT '),
           '(HEIGHTS|HGTS)','HTS'),
         ' (TOWNSHIP|TWP|BOROUGH|BORO)$',''),
       ' ','')
;
COMMIT;
