-- ===========================================================================
-- 05_manual_fixes.sql -- run AFTER 04_mint_local_codes.sql
--
-- Corrections found by validation after the automated steps. Each one traces to
-- Census county-subdivision data or to a duplicate in the DOT source.
--
-- WITHOUT THIS FILE the rebuild is incomplete: 01 truncates lu_place, so every
-- fix below has to be re-applied.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 1. Duplicate rows from the step 6/8 inserts.
--
-- Where DOT lists a place twice, our one string matched both DOT rows and got
-- two lu_place rows -- which fans out the join and double-counts listings.
-- Keep one code per string.
--
--   SAINT/ST INIGOES  DOT has it twice (SAINT INIGOES 1364, ST. INIGOES 1372)
--   MT HOLLY          DOT has MT HOLLY 2080 and MOUNT HOLLY 2063; keep 2063 so
--                     both spellings land where the research file already had it
--   MECHANICSVILLE    DOT lists the identical name twice (5020, 5030)
--   BURLINGTON TWP    matched both BURLINGTON (0480) and BURLINGTON TOWNSHIP
--                     (0481) -- our string says TWP, so keep the township
--   CHESTER TWP       same shape, keep CHESTER TOWNSHIP (1296)
-- ---------------------------------------------------------------------------
DELETE FROM dwh.lu_place
WHERE (stateabbr='MD' AND countyfipscode='24037'
       AND citynamenorm IN ('SAINT INIGOES','ST INIGOES') AND citycode='1372')
   OR (stateabbr='NJ' AND countyfipscode='34005'
       AND citynamenorm='BURLINGTON TWP' AND citycode='0480')
   OR (stateabbr='NJ' AND countyfipscode='34005'
       AND citynamenorm='MT HOLLY' AND citycode='2080')
   OR (stateabbr='PA' AND countyfipscode='42045'
       AND citynamenorm='CHESTER TWP' AND citycode='1270')
   OR (stateabbr='PA' AND countyfipscode='42107'
       AND citynamenorm IN ('MECHANICSVILLE','MECHANICSVILLE BORO') AND citycode='5030');
COMMIT;


-- ---------------------------------------------------------------------------
-- 2. Township split the automated pass missed.
--
-- MT JOY TWP didn't split because the Census join compared 'MOUNT JOY' (Census)
-- against 'MT JOY' (ours) with no MOUNT/MT folding. Census confirms Lancaster
-- County has both a Mount Joy borough and a Mount Joy township.
--
-- ANY future Census comparison must fold MOUNT/MT and SAINT/ST on BOTH sides.
-- ---------------------------------------------------------------------------
UPDATE dwh.lu_place
SET citycode        = 'T5550',
    citydisplayname = 'MOUNT JOY TOWNSHIP (LANCASTER, PA)',
    notes           = COALESCE(notes || ' | ','') || 'minted: township split from 5550 per Census'
WHERE stateabbr='PA' AND countyfipscode='42071' AND citynamenorm='MT JOY TWP';
COMMIT;


-- ---------------------------------------------------------------------------
-- 3. Minted codes that should have reused an existing one.
--
-- 04 minted without checking whether the name already had a code elsewhere in
-- the state. These six are the same place spilling into an ADJACENT county, so
-- they belong on the existing DOT code, not a new one.
--
-- RULE FOR FUTURE MINTS: check for an existing code for that name in that state
-- first, and only mint when there isn't one (or when the counties don't touch).
-- ---------------------------------------------------------------------------
UPDATE dwh.lu_place SET citycode='0282' WHERE stateabbr='MD' AND citynamenorm='CHARLOTTE HALL' AND citycode LIKE 'L%';
UPDATE dwh.lu_place SET citycode='0412' WHERE stateabbr='MD' AND citynamenorm='CURTIS BAY'     AND citycode LIKE 'L%';
UPDATE dwh.lu_place SET citycode='0995' WHERE stateabbr='MD' AND citynamenorm='MECHANICSVILLE' AND citycode LIKE 'L%';
UPDATE dwh.lu_place SET citycode='0707' WHERE stateabbr='NJ' AND citynamenorm='CREAM RIDGE'    AND citycode LIKE 'L%';
UPDATE dwh.lu_place SET citycode='2512' WHERE stateabbr='VA' AND citynamenorm='VIEWTOWN'       AND citycode LIKE 'L%';
UPDATE dwh.lu_place SET citycode='0516' WHERE stateabbr='WV' AND citynamenorm='CHERRY RUN'     AND citycode LIKE 'L%';
COMMIT;


-- ---------------------------------------------------------------------------
-- 4. Genuinely different towns sharing one DOT code.
--
-- DOT assigns citycode per NAME per STATE, not per place -- so two towns with
-- the same name in one state collide. Census county subdivisions confirm both
-- exist (a township is by definition inside one county, so two hits = two
-- municipalities, never one place spanning).
--
--   MIDDLETOWN      Dauphin + Delaware
--   MECHANICSVILLE  Bucks + Schuylkill
--   LEHMAN          Luzerne + Pike        (the Monroe row is miscoded, left merged)
--   FAIRVIEW        Erie + York
--   MOUNT PLEASANT  Adams + Westmoreland
--
-- Checked and NOT split -- Census shows the name in only one of the two, so the
-- other county's rows are miscoded listings: HOPEWELL, LAWRENCEVILLE, WINDSOR,
-- LIVERPOOL, CATAWISSA, and the WV Taylor/Tyler rows (Friendly, Middlebourne,
-- Sistersville are all Tyler County towns).
-- ---------------------------------------------------------------------------
UPDATE dwh.lu_place
SET citycode        = 'L9001',
    citydisplayname = 'MIDDLETOWN (DELAWARE, PA)',
    notes           = COALESCE(notes || ' | ','') || 'split: distinct town sharing DOT 5120'
WHERE stateabbr='PA' AND countyfipscode='42045'
  AND citynamenorm IN ('MIDDLETOWN','MIDDLETOWN TWP');

UPDATE dwh.lu_place
SET citycode        = 'L9002',
    citydisplayname = 'MECHANICSVILLE (SCHUYLKILL, PA)',
    notes           = COALESCE(notes || ' | ','') || 'split: distinct town sharing DOT 5020'
WHERE stateabbr='PA' AND countyfipscode='42107'
  AND citynamenorm IN ('MECHANICSVILLE','MECHANICSVILLE BORO');

UPDATE dwh.lu_place
SET citycode        = 'L9003',
    citydisplayname = 'LEHMAN TOWNSHIP (PIKE, PA)',
    notes           = COALESCE(notes || ' | ','') || 'split: distinct town sharing DOT 4385'
WHERE stateabbr='PA' AND countyfipscode='42103' AND citycode='4385';

UPDATE dwh.lu_place
SET citycode        = 'L9004',
    citydisplayname = 'FAIRVIEW TOWNSHIP (YORK, PA)',
    notes           = COALESCE(notes || ' | ','') || 'split: distinct town sharing DOT 2769'
WHERE stateabbr='PA' AND countyfipscode='42133' AND citycode='2769';

UPDATE dwh.lu_place
SET citycode        = 'L9005',
    citydisplayname = 'MOUNT PLEASANT TOWNSHIP (ADAMS, PA)',
    notes           = COALESCE(notes || ' | ','') || 'split: distinct town sharing DOT 5580'
WHERE stateabbr='PA' AND countyfipscode='42001' AND citycode='5580';
COMMIT;


-- ---------------------------------------------------------------------------
-- 5. Renumber minted codes densely.
--
-- Two mint scripts each started ROW_NUMBER at 1, so their ranges overlapped and
-- one code covered two unrelated towns. This collapses everything to a single
-- dense sequence while preserving intentional multi-name groups (MIDDLETOWN +
-- MIDDLETOWN TWP stay on one code, and so on).
--
-- Run this LAST, after every mint.
-- ---------------------------------------------------------------------------
UPDATE dwh.lu_place p
SET citycode = n.newcode
FROM (
  SELECT g.groupkey,
         'L' || LPAD(ROW_NUMBER() OVER (ORDER BY g.sortname)::VARCHAR, 4, '0') AS newcode
  FROM (
    SELECT CASE WHEN citycode IN ('L9001','L9002') THEN citycode
                ELSE stateabbr || '|' || citynamenorm END AS groupkey,
           MIN(stateabbr || '|' || citynamenorm) AS sortname
    FROM dwh.lu_place
    WHERE citycode LIKE 'L%'
    GROUP BY 1
  ) g
) n
WHERE n.groupkey = CASE WHEN p.citycode IN ('L9001','L9002') THEN p.citycode
                        ELSE p.stateabbr || '|' || p.citynamenorm END
  AND p.citycode LIKE 'L%';
COMMIT;


-- ---------------------------------------------------------------------------
-- 6. Normalize display casing -- our inserts used INITCAP, DOT's are uppercase.
-- ---------------------------------------------------------------------------
UPDATE dwh.lu_place
SET citydisplayname = UPPER(citydisplayname)
WHERE citydisplayname <> UPPER(citydisplayname);
COMMIT;


-- ===========================================================================
-- VALIDATION -- all four should return zero rows
-- ===========================================================================

-- duplicate join keys (would fan out and double-count listings)
SELECT stateabbr, countyfipscode, citynamenorm, COUNT(*)
FROM dwh.lu_place GROUP BY 1,2,3 HAVING COUNT(*) > 1;

-- one code covering two genuinely different names (wrong merge)
WITH k AS (
  SELECT stateabbr, citycode,
         REPLACE(REGEXP_REPLACE(REGEXP_REPLACE(
           REPLACE(REPLACE(citynamenorm,'SAINT ','ST '),'MOUNT ','MT '),
           '(HEIGHTS|HGTS)','HTS'), ' (TOWNSHIP|TWP|BOROUGH|BORO)$',''), ' ','') AS folded
  FROM dwh.lu_place WHERE citycode IS NOT NULL
)
SELECT stateabbr, citycode FROM k GROUP BY 1,2 HAVING COUNT(DISTINCT folded) > 1;

-- minted code covering two unrelated names
SELECT citycode FROM dwh.lu_place
WHERE citycode LIKE 'L%'
GROUP BY 1 HAVING COUNT(DISTINCT stateabbr || '|' || citynamenorm) > 1
   AND citycode NOT IN ('L9001','L9002');

-- township split where Census does NOT confirm both exist
-- (needs load_lu_census_dual.sql; note the MOUNT/MT fold on both sides)
SELECT p.stateabbr, p.cityname, p.citycode
FROM dwh.lu_place p
LEFT JOIN dwh.lu_census_dual d
       ON d.stateabbr = p.stateabbr
      AND d.countyfipscode = p.countyfipscode
      AND REPLACE(REPLACE(d.basename,'MOUNT ','MT '),'SAINT ','ST ')
        = REPLACE(REPLACE(
            REGEXP_REPLACE(p.citynamenorm,' (TOWNSHIP|TWP|BOROUGH|BORO)$',''),
            'MOUNT ','MT '),'SAINT ','ST ')
WHERE p.citycode LIKE 'T%' AND d.basename IS NULL;
