-- 04_mint_local_codes.sql -- run AFTER 03_apply_codes.sql
--
-- Mints 'L####' codes for 138 real communities that exist in neither the
-- research team's file nor the DOT file. Approved by the team.
--
-- Keyed on (stateabbr, citynamenorm), NOT per row -- so a place spanning two
-- counties (Glen Mills = Delaware + Chester) gets ONE code, not two.
--
-- DELIBERATELY EXCLUDED, do not add without a decision:
--   misspellings      BALTIIMORE, BALLTIMORE, ELLICOTT, REHOBETH
--   not a place       BALTIMORE CITY, SOUTHERN MD FACILITY
--   county as city    NJ MERCER, VA PRINCE WILLIAM, MD CARROLL
--   wrong state       MD SEAFORD (DE), PA HOCKESSIN (DE), DE CHADDS FORD (PA),
--                     VA POTOMAC (Alexandria City)
--   Baltimore City neighborhoods (team decision: not separate places)
--                     HIGHLANDTOWN, MCDONOGH RUN, RASPEBURG, NORTHWOOD,
--                     ROLAND PARK, DRUID, MOUNT WASHINGTON, GOVANS, EAST CASE,
--                     CLIFTON, ARLINGTON
--
-- 'L' prefix marks invented codes. Find them all: WHERE citycode LIKE 'L%'
-- Undo: UPDATE dwh.lu_place SET citycode=NULL, countycitycode=NULL
--       WHERE notes LIKE '%minted: real community%';

UPDATE dwh.lu_place p
SET citycode       = 'L' || LPAD(m.seq::VARCHAR, 4, '0'),
    countycitycode = p.countyfipscode || 'L' || LPAD(m.seq::VARCHAR, 4, '0'),
    notes          = COALESCE(p.notes || ' | ', '') || 'minted: real community, not in DOT'
FROM (
  SELECT stateabbr, citynamenorm,
         ROW_NUMBER() OVER (ORDER BY stateabbr, citynamenorm) AS seq
  FROM (
    SELECT DISTINCT stateabbr, citynamenorm
    FROM dwh.lu_place
    WHERE citycode IS NULL
      AND (
        (stateabbr = 'PA' AND citynamenorm = 'GLEN MILLS') OR
        (stateabbr = 'MD' AND citynamenorm = 'GWYNN OAK') OR
        (stateabbr = 'MD' AND citynamenorm = 'WINDSOR MILL') OR
        (stateabbr = 'NJ' AND citynamenorm = 'EVESHAM') OR
        (stateabbr = 'MD' AND citynamenorm = 'BROOKLYN') OR
        (stateabbr = 'VA' AND citynamenorm = 'OAK HILL') OR
        (stateabbr = 'DE' AND citynamenorm = 'CAMDEN WYOMING') OR
        (stateabbr = 'VA' AND citynamenorm = 'BROADLANDS') OR
        (stateabbr = 'PA' AND citynamenorm = 'FEASTERVILLE TREVOSE') OR
        (stateabbr = 'VA' AND citynamenorm = 'BRAMBLETON') OR
        (stateabbr = 'PA' AND citynamenorm = 'LOWER GWYNEDD') OR
        (stateabbr = 'NJ' AND citynamenorm = 'LITTLE EGG HARBOR TWP') OR
        (stateabbr = 'MD' AND citynamenorm = 'SPARKS GLENCOE') OR
        (stateabbr = 'PA' AND citynamenorm = 'JEFFERSONVILLE') OR
        (stateabbr = 'PA' AND citynamenorm = 'WARWICK') OR
        (stateabbr = 'MD' AND citynamenorm = 'CURTIS BAY') OR
        (stateabbr = 'MD' AND citynamenorm = 'NATIONAL HARBOR') OR
        (stateabbr = 'NJ' AND citynamenorm = 'LAWRENCE') OR
        (stateabbr = 'MD' AND citynamenorm = 'CHARLOTTE HALL') OR
        (stateabbr = 'VA' AND citynamenorm = 'STONE RIDGE') OR
        (stateabbr = 'NJ' AND citynamenorm = 'LAWRENCE TOWNSHIP') OR
        (stateabbr = 'MD' AND citynamenorm = 'LINTHICUM') OR
        (stateabbr = 'DE' AND citynamenorm = 'NORTH BETHANY') OR
        (stateabbr = 'DE' AND citynamenorm = 'SOUTH BETHANY') OR
        (stateabbr = 'MD' AND citynamenorm = 'SPRINGDALE') OR
        (stateabbr = 'DE' AND citynamenorm = 'LONG NECK') OR
        (stateabbr = 'VA' AND citynamenorm = 'LANSDOWNE') OR
        (stateabbr = 'MD' AND citynamenorm = 'SWAN POINT') OR
        (stateabbr = 'PA' AND citynamenorm = 'MOUNT HOLLY SPRINGS') OR
        (stateabbr = 'PA' AND citynamenorm = 'UPPER GWYNEDD') OR
        (stateabbr = 'WV' AND citynamenorm = 'CHERRY RUN') OR
        (stateabbr = 'PA' AND citynamenorm = 'PENNSYLVANIA FURNACE') OR
        (stateabbr = 'PA' AND citynamenorm = 'ROMANSVILLE') OR
        (stateabbr = 'NJ' AND citynamenorm = 'CREAM RIDGE') OR
        (stateabbr = 'MD' AND citynamenorm = 'STONEY BEACH') OR
        (stateabbr = 'MD' AND citynamenorm = 'URBANA') OR
        (stateabbr = 'VA' AND citynamenorm = 'DULLES') OR
        (stateabbr = 'MD' AND citynamenorm = 'CHESTNUT HILL COVE') OR
        (stateabbr = 'MD' AND citynamenorm = 'IDLEWYLDE') OR
        (stateabbr = 'NJ' AND citynamenorm = 'WEST TRENTON') OR
        (stateabbr = 'VA' AND citynamenorm = 'WEST MCLEAN') OR
        (stateabbr = 'MD' AND citynamenorm = 'RUXTON') OR
        (stateabbr = 'MD' AND citynamenorm = 'POCOMOKE') OR
        (stateabbr = 'PA' AND citynamenorm = 'UPPER HOLLAND') OR
        (stateabbr = 'NJ' AND citynamenorm = 'MANNINGTON') OR
        (stateabbr = 'VA' AND citynamenorm = 'KINGSTOWNE') OR
        (stateabbr = 'MD' AND citynamenorm = 'WHALEYVILLE') OR
        (stateabbr = 'VA' AND citynamenorm = 'MASON NECK') OR
        (stateabbr = 'PA' AND citynamenorm = 'EAST YORK') OR
        (stateabbr = 'PA' AND citynamenorm = 'WEST BRANDYWINE') OR
        (stateabbr = 'MD' AND citynamenorm = 'LAKE SHORE') OR
        (stateabbr = 'PA' AND citynamenorm = 'VALLEY TOWNSHIP') OR
        (stateabbr = 'PA' AND citynamenorm = 'LOWER MERION') OR
        (stateabbr = 'MD' AND citynamenorm = 'CARVEL BEACH') OR
        (stateabbr = 'PA' AND citynamenorm = 'EAST FALLOWFIELD TOWNSHIP') OR
        (stateabbr = 'DE' AND citynamenorm = 'EDGEMOOR') OR
        (stateabbr = 'MD' AND citynamenorm = 'CLEARWATER BEACH') OR
        (stateabbr = 'NJ' AND citynamenorm = 'STAFFORD TOWNSHIP') OR
        (stateabbr = 'VA' AND citynamenorm = 'VIEWTOWN') OR
        (stateabbr = 'NJ' AND citynamenorm = 'WEST COLLINGSWOOD') OR
        (stateabbr = 'MD' AND citynamenorm = 'MECHANICSVILLE') OR
        (stateabbr = 'MD' AND citynamenorm = 'GREENLAND BEACH') OR
        (stateabbr = 'MD' AND citynamenorm = 'LINEBORO CPO') OR
        (stateabbr = 'MD' AND citynamenorm = 'ECKHART') OR
        (stateabbr = 'PA' AND citynamenorm = 'BELMONT HILLS') OR
        (stateabbr = 'PA' AND citynamenorm = 'REXMONT') OR
        (stateabbr = 'MD' AND citynamenorm = 'MONTPELIER') OR
        (stateabbr = 'PA' AND citynamenorm = 'YORKANA') OR
        (stateabbr = 'PA' AND citynamenorm = 'SALUNGA') OR
        (stateabbr = 'PA' AND citynamenorm = 'STOUCHSBURG') OR
        (stateabbr = 'VA' AND citynamenorm = 'BROWNTOWN') OR
        (stateabbr = 'MD' AND citynamenorm = 'MCCOOLE') OR
        (stateabbr = 'MD' AND citynamenorm = 'CROCHERON') OR
        (stateabbr = 'MD' AND citynamenorm = 'CRELLIN') OR
        (stateabbr = 'WV' AND citynamenorm = 'BLUEMONT') OR
        (stateabbr = 'NJ' AND citynamenorm = 'WEST COLLINGSWOOD HEIGHTS') OR
        (stateabbr = 'DE' AND citynamenorm = 'MANOR') OR
        (stateabbr = 'MD' AND citynamenorm = 'EASTPORT') OR
        (stateabbr = 'MD' AND citynamenorm = 'DENTSVILLE') OR
        (stateabbr = 'MD' AND citynamenorm = 'DARES BEACH') OR
        (stateabbr = 'PA' AND citynamenorm = 'EDDINGTON') OR
        (stateabbr = 'PA' AND citynamenorm = 'ORVISTON') OR
        (stateabbr = 'PA' AND citynamenorm = 'MAHANOY PLANE') OR
        (stateabbr = 'MD' AND citynamenorm = 'UPPER HILL') OR
        (stateabbr = 'MD' AND citynamenorm = 'LOCH HILL') OR
        (stateabbr = 'MD' AND citynamenorm = 'BISHOPS HEAD') OR
        (stateabbr = 'PA' AND citynamenorm = 'MOREA') OR
        (stateabbr = 'MD' AND citynamenorm = 'WEST HYATTSVILLE') OR
        (stateabbr = 'MD' AND citynamenorm = 'RIDERWOOD') OR
        (stateabbr = 'PA' AND citynamenorm = 'OGDEN') OR
        (stateabbr = 'WV' AND citynamenorm = 'SHORT GAP') OR
        (stateabbr = 'PA' AND citynamenorm = 'HAZELTON') OR
        (stateabbr = 'NJ' AND citynamenorm = 'MYSTIC ISLANDS') OR
        (stateabbr = 'VA' AND citynamenorm = 'TYSONS') OR
        (stateabbr = 'MD' AND citynamenorm = 'SANG RUN') OR
        (stateabbr = 'PA' AND citynamenorm = 'SPRY') OR
        (stateabbr = 'PA' AND citynamenorm = 'MUHLENBERG TOWNSHIP') OR
        (stateabbr = 'PA' AND citynamenorm = 'LOWER PAXTON') OR
        (stateabbr = 'PA' AND citynamenorm = 'JOLIETT') OR
        (stateabbr = 'PA' AND citynamenorm = 'EAST PENNSBORO') OR
        (stateabbr = 'VA' AND citynamenorm = 'SUDLEY SPRINGS') OR
        (stateabbr = 'MD' AND citynamenorm = 'FRANKLIN') OR
        (stateabbr = 'MD' AND citynamenorm = 'OELLA') OR
        (stateabbr = 'PA' AND citynamenorm = 'LAMOTT') OR
        (stateabbr = 'PA' AND citynamenorm = 'DONALDSON') OR
        (stateabbr = 'VA' AND citynamenorm = 'VINT HILL FARMS') OR
        (stateabbr = 'VA' AND citynamenorm = 'SOUTHBRIDGE') OR
        (stateabbr = 'PA' AND citynamenorm = 'SWATARA') OR
        (stateabbr = 'PA' AND citynamenorm = 'SOUTH HEIDELBERG TWP') OR
        (stateabbr = 'PA' AND citynamenorm = 'HOLLYWOOD') OR
        (stateabbr = 'MD' AND citynamenorm = 'HYATTSTOWN') OR
        (stateabbr = 'PA' AND citynamenorm = 'ONTELAUNEE') OR
        (stateabbr = 'PA' AND citynamenorm = 'GLEN RIDDLE LIMA') OR
        (stateabbr = 'MD' AND citynamenorm = 'ABERDEEN PROVING GROUND') OR
        (stateabbr = 'VA' AND citynamenorm = 'PIMMIT') OR
        (stateabbr = 'MD' AND citynamenorm = 'HUTTON') OR
        (stateabbr = 'MD' AND citynamenorm = 'EUDOWOOD') OR
        (stateabbr = 'PA' AND citynamenorm = 'WEST BRISTOL') OR
        (stateabbr = 'MD' AND citynamenorm = 'FOWBELSBURG') OR
        (stateabbr = 'PA' AND citynamenorm = 'SWATARA TOWNSHIP') OR
        (stateabbr = 'MD' AND citynamenorm = 'RUSSETT') OR
        (stateabbr = 'PA' AND citynamenorm = 'PILGRIM GARDENS') OR
        (stateabbr = 'MD' AND citynamenorm = 'MILLER') OR
        (stateabbr = 'VA' AND citynamenorm = 'SULLY STATION') OR
        (stateabbr = 'MD' AND citynamenorm = 'WEST BETHESDA') OR
        (stateabbr = 'VA' AND citynamenorm = 'GREENWAY') OR
        (stateabbr = 'PA' AND citynamenorm = 'PRIMOS SECANE') OR
        (stateabbr = 'MD' AND citynamenorm = 'BECKLEYSVILLE') OR
        (stateabbr = 'PA' AND citynamenorm = 'PAXTONIA') OR
        (stateabbr = 'VA' AND citynamenorm = 'SHELBY') OR
        (stateabbr = 'PA' AND citynamenorm = 'PORTERS SIDELING') OR
        (stateabbr = 'WV' AND citynamenorm = 'LANDES STATION') OR
        (stateabbr = 'WV' AND citynamenorm = 'CLEARBROOK') OR
        (stateabbr = 'NJ' AND citynamenorm = 'PEAPACK') OR
        (stateabbr = 'MD' AND citynamenorm = 'JENNINGS') OR
        (stateabbr = 'VA' AND citynamenorm = 'RACCOON FORD') OR
        (stateabbr = 'VA' AND citynamenorm = 'MONTFORD') OR
        (stateabbr = 'VA' AND citynamenorm = 'JEFFERSON MANOR')
      )
  )
) m
WHERE m.stateabbr    = p.stateabbr
  AND m.citynamenorm = p.citynamenorm
  AND p.citycode IS NULL;
COMMIT;
