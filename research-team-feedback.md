# Feedback on the City Lookup Table

Two gaps we found while matching your lookup file against `dwh.dim_listing`. Both are
fixable at the source, which would be better than us patching around them.

Our coverage went from 91.7% to 98.4% of listings once these were worked around.

## 1. Lookup misses — 118 rows marked `Not Found` that the DOT file does have

Your join appears to be exact on city name, so it misses spelling differences between your
combos and the DOT file. Example:

```
your file:  MOUNT LAUREL / BURLINGTON / NJ  ->  Not Found
DOT file:   MT LAUREL    / BURLINGTON / NJ  ->  2081
```

That one row is 31,293 listings on our side.

Full list: **`research-team-lookup-misses.csv`** — your `cityname`, the DOT `cityname`, and
the `citycode` it should have picked up.

### The normalization that closes it

Apply to **both** sides before joining:

1. Upper-case, trim
2. Strip anything that isn't a letter or a space (kills stray commas, periods, digits)
3. Collapse runs of spaces to one
4. `SAINT ` → `ST `
5. `MOUNT ` → `MT `
6. Drop a trailing ` TOWNSHIP`, ` TWP`, ` BOROUGH`, ` BORO`
7. `HEIGHTS` / `HGTS` → `HTS`
8. Remove **all** remaining spaces before comparing

Step 6 matters most. New Jersey's municipal identity is townships, and DOT writes them out
while our listing data doesn't:

```
listing data:  EWING     ->  DOT:  EWING TOWNSHIP     0935
listing data:  HAMILTON  ->  DOT:  HAMILTON TOWNSHIP  1265
```

That rule alone recovered Hamilton (28,976 listings), Ewing (12,924), Westampton, Shamong,
Pittsgrove and Eastampton.

Rules 7 and 8 matter nearly as much — they cover three more classes:

```
MC HENRY         =  MCHENRY        (space after MC, ~20 towns)
DISTRICT HEIGHTS =  DISTRICT HTS   (HTS appears 14x in the footprint)
GREENTREE        =  GREEN TREE     (compound split or joined)
BELLE MEAD       =  BELLE-MEAD     (hyphen)
```

District Heights alone is 17,154 listings.

Always join on **`countyfipscode`, never county name** — county has at least three spellings
across sources (`ST. MARY'S`, `ST. MARYS`, `SAINT MARYS`), and our loader already carries a
hardcoded special case for it.

## 2. Coverage gaps — 454 combos missing from the file entirely

These are `(city, county, state)` combinations present in our listings and in the DOT file,
but absent from your lookup. Suggests the extract it was built from didn't cover everything.

Notable: six ordinary St. Mary's County, MD towns — **Lexington Park, California,
Leonardtown, Mechanicsville, Hollywood, Great Mills**. Those aren't edge cases, which makes
us think that county was missed wholesale rather than row by row.

To pull the current list with listing volumes:

```sql
WITH mine AS (
  SELECT stateorprovince AS st, countyfipscode AS cfips,
         REGEXP_REPLACE(REGEXP_REPLACE(UPPER(TRIM(postalcity)),'[^A-Z ]',''),' {2,}',' ') AS cityname,
         COUNT(*) AS listings
  FROM dwh.dim_listing dl
  WHERE dl.propertytype = 'Residential'
    AND ISNULL(dl.isdeleted, FALSE) = FALSE
    AND ISNULL(dl.oeyn, FALSE)      = FALSE
    AND dl.listingsourcebusinesspartner NOT IN ('CAAR','CVR','WMB')
    AND dl.brightserviceareayn IS TRUE
    AND dl.postalcity IS NOT NULL AND TRIM(dl.postalcity) <> ''
    AND dl.countyfipscode IS NOT NULL
  GROUP BY 1, 2, 3
)
SELECT m.st, m.cfips, m.cityname, m.listings
FROM mine m
LEFT JOIN dwh.lu_place p
       ON p.stateabbr = m.st AND p.countyfipscode = m.cfips AND p.citynamenorm = m.cityname
WHERE p.citynamenorm IS NULL
ORDER BY m.listings DESC;
```

(Run this against a copy of `lu_place` loaded from your file only — our working table has
the 454 already inserted.)

## 3. Two questions

**What does `crosscountyflag` mean?** We've seen `1`, `2`, `14` and `190`. `2` looks like a
county count (Milford DE is `0320` in both Kent and Sussex and shows `2`), but `14` and `190`
both appear on rows with no citycode, so they read like sentinels. We didn't want to infer
it.

**Was excluding municipalities deliberate?** The file behaves like a postal-city list, which
is why NJ townships are absent. If that's intentional we'll handle it on our side; if not,
it's the single biggest remaining gap.

## 4. What we still can't resolve — 167 combos, ~93,000 listings

Real places in neither your file nor DOT. These need codes created by someone, or a decision
that they don't get one:

```
MD  GWYNN OAK      8,299      VA  BROADLANDS      3,575
MD  WINDSOR MILL   7,926      VA  BRAMBLETON      3,113
MD  BROOKLYN       4,460      PA  LOWER GWYNEDD   2,508
VA  OAK HILL       3,736      MD  SPARKS GLENCOE  2,192
```

Loudoun County has only 21 rows in the entire DOT file, so newer master-planned communities
(Broadlands, Brambleton, Stone Ridge, Lansdowne) simply aren't represented.

A few have answers that normalization can't reach, because they're different *names* rather
than different spellings. Flagging them in case they're worth aliasing in your file:

| ours | DOT | listings |
|---|---|---|
| NJ `EVESHAM` | `MARLTON` (its postal name) | 6,150 |
| NJ `LAWRENCE` | `LAWRENCEVILLE` | 1,346 |
| PA `GLEN MILLS` | `GLENN MILLS` — looks like a typo in DOT | 9,798 |
| PA `FEASTERVILLE TREVOSE` | `FEASTERVILLE` + `TREVOSE`, listed separately | 3,483 |
| MD `SPARKS GLENCOE` | `SPARKS` + `GLENCOE`, listed separately | 2,192 |

## What we are *not* asking for

We haven't invented any codes and don't intend to. Where no real code exists the listing
stays unresolved and simply doesn't appear under a place — a visible gap is better than a
silently wrong number.
