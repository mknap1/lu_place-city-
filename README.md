# City / Place matching — what we did and why

> **What this is for.** `dwh.lu_place` is what the city dropdown reads. A user types a
> city name, picks one entry, and the listings behind it are filtered by that entry's
> code. So the names in here are user-facing — they have to be clean, unambiguous, and
> free of junk like `21215BALTIIMORE`.
>
> **The key is `(stateabbr, citycode)`, never citycode alone** — codes repeat across
> states, and DOT assigns them per name-per-state rather than per place.
>
> **Display rule:** show `Takoma Park, MD`. Add a county qualifier only when a name
> appears more than once in a state — `Middletown (Dauphin Co.), PA` vs
> `Middletown (Delaware Co.), PA`. Qualifying everything makes the common case ugly.

## The problem

Listings only carry a **city name** and a **county**. That breaks two ways at once:

**One city looked like two.** Takoma Park sits in both Montgomery and Prince George's
County. Because county was part of how we identified a city, searching "Takoma Park"
returned half the data.

**Two cities looked like one.** Pennsylvania has three different Springfield Townships.
Merging anything by name alone would have blended three separate markets together.

Any fix has to do both — merge the first case, split the second.

## The fix

The research team has a lookup file that assigns every `(city, county, state)` combination
a **`citycode`**. The important property: **the citycode ignores county.**

- Same code = same place
- Different codes = different places

So you join on county to *find* the code, then group by the code to *get* the place.
County finds it; the code **is** it.

**Proof, on real data.** Milford, Delaware:

| city | county | citycode | listings |
|---|---|---|---|
| MILFORD | Kent | `0320` | 7,208 |
| MILFORD | Sussex | `0320` | 13,702 |

Two counties, one code. Group by citycode and Milford is one place with 20,910 listings
instead of two half-cities.

And the Springfields stay apart because each is a separate lookup with its own code.

## How we got from 92% to 98%

Everything below is **exact matching** — no fuzzy logic, no guessing, no invented codes.
The only transformations are on spelling.

| step | what it did | coverage |
|---|---|---|
| start | plain exact match | **91.7%** |
| 1 | spelling variants + first inherits | 95.1% |
| 2 | remaining inherits | 96.5% |
| 3 | more spelling variants | 96.5% |
| 4 | matched against the upstream DOT file | 97.5% |
| 5 | added combos missing from the lookup file | 98.0% |
| 6 | looser spelling rules (`HEIGHTS`/`HTS`, `MC X`/`MCX`, spaces) | 98.4% |
| 7 | minted codes for real places in neither file | 99.3% |
| 8 | aliases + minted townships found by validation | **99.5%** |

### Step 1 & 3 — spelling

Our data and the lookup file spelled the same town differently.

```
SAINT LEONARD   =  ST LEONARD          (Calvert County, MD)
MC CONNELLSBURG =  MCCONNELLSBURG      (Fulton County, PA)
FALLS  CHURCH   =  FALLS CHURCH        (a double space)
TROY,           =  TROY                (a stray comma)
```

Same town, same county — just typed differently. We match on a cleaned-up version of the
name, so both spellings find the same code.

### Step 2 — spillover into the next county

179,451 listings say **"Alexandria, VA"** but sit in **Fairfax County**, not Alexandria
City. They're real homes with Alexandria mailing addresses — the post office says
Alexandria, the county line says Fairfax.

```
ALEXANDRIA / ALEXANDRIA CITY  ->  0040   (already coded)
ALEXANDRIA / FAIRFAX          ->  ????   (blank)
```

The team decided these should count as Alexandria — **postal semantics**, matching what
someone typing "Alexandria" expects. So the blank row inherits `0040`.

Same pattern, same ruling: Fredericksburg (Spotsylvania + Stafford), Manassas, Falls
Church, Winchester, Charlottesville. Also `YORK TWP` → `YORK` and `LANCASTER TWP` →
`LANCASTER`.

**This is reversible.** Every listing still carries its `countyfipscode`, so city-vs-county
can be split back apart any time. We only set the default.

**It's also audited.** We checked all ~460 inherited codes against the upstream DOT file
looking for any that disagreed. **Zero conflicts.**

### Step 4 — going to the source

The research team's file is built *from* a Department of Transportation place-code file.
Where their file said `Not Found`, we checked DOT ourselves — and often the code was
there, just under a different spelling.

```
their file:  MOUNT LAUREL / Burlington, NJ  ->  Not Found
DOT file:    MT LAUREL    / Burlington, NJ  ->  2081     ← 31,293 listings
```

The big unlock was **dropping the "Township" suffix**, because New Jersey's identity is
townships:

```
our data says:  EWING         ->  DOT says:  EWING TOWNSHIP     0935
our data says:  HAMILTON      ->  DOT says:  HAMILTON TOWNSHIP  1265
```

That one rule recovered Hamilton (28,976), Ewing (12,924), Westampton, Shamong,
Pittsgrove, Eastampton.

### Step 5 — combos their file never had

Their file only lists combinations they happened to encounter. Ours had 454 more that DOT
covers — including six ordinary St. Mary's County, MD towns (Lexington Park, California,
Leonardtown, Mechanicsville, Hollywood, Great Mills). Added those directly from DOT.

### Step 6 — looser spelling rules

Steps 4 and 5 still respected spaces, which hid three more classes of difference:

```
MC HENRY         =  MCHENRY        (space after MC — about 20 towns)
DISTRICT HEIGHTS =  DISTRICT HTS   (DOT abbreviates HEIGHTS; HTS appears 14x)
GREENTREE        =  GREEN TREE     (compound split or joined)
BELLE MEAD       =  BELLE-MEAD     (hyphen)
```

Folding `HEIGHTS`/`HGTS` to `HTS` and then ignoring spaces entirely picked up another ~58
lookup rows (District Heights alone is 17,154 listings) plus ~135 typos in our own listing
data — `CLIFTON HGTS`, `CRUMLYNNE`, `LAPLATA`, `A LEXANDRIA`, `OAKLA ND`.

## Where we are

**99.5% of listings resolve to a place code** — 10,876,255 of 10,927,885.

The last 1.6% splits in two:

- **0.0% (1,563, across 27 combos)** — deliberately uncoded: misspellings, wrong-state
  entries, Baltimore City neighborhoods.  Was 167 combos before minting.
- Real places in neither file Gwynn Oak and Windsor Mill MD, Oak Hill VA,
  Camden Wyoming DE, and newer Loudoun County developments (Broadlands, Brambleton, Stone
  Ridge). Loudoun has only 21 rows in the entire DOT file, so recent master-planned
  communities simply aren't there. These need codes created, or a conversation with the
  research team.
- **0.7% (79,385, across 5,243 combos)** — genuine junk. `21215BALTIIMORE`, `UNKNOWN` (17,080 listings in PA alone),
  and Baltimore City neighborhood names (Roland Park, Highlandtown) that aren't cities.
  **This part is supposed to be missing.**

### Named leftovers that do have an answer

Not spelling problems — each needs a person to decide, so they were left alone:

| | listings | why |
|---|---|---|
| PA `GLEN MILLS` | 9,798 | DOT spells it `GLENN MILLS` — a typo in DOT, not in us |
| NJ `EVESHAM` | 6,150 | DOT calls it `MARLTON` (Evesham Township's postal name) |
| PA `FEASTERVILLE TREVOSE` | 3,483 | DOT has `FEASTERVILLE` and `TREVOSE` as two places |
| MD `SPARKS GLENCOE` | 2,192 | DOT has `SPARKS` and `GLENCOE` separately |
| NJ `LAWRENCE` | 1,346 | DOT calls it `LAWRENCEVILLE` |
| PA `PHILA` | 1,975 | our abbreviation of Philadelphia |
| PA `L MAKEFIELD` | 1,429 | our abbreviation of Lower Makefield |
| PA `LINCOLN UNIV` | 938 | our abbreviation of Lincoln University |

## Two things worth saying in the meeting

1. **Nothing was guessed.** Every code came from the research team's file or the DOT file
   it's built from. We never invented one. Where we couldn't find a real code, the listing
   stays unresolved rather than being assigned somewhere plausible — a visible gap beats a
   silent wrong answer.

2. **The research team's file has two fixable gaps**, both worth fixing upstream rather
   than patching here: 118 rows marked `Not Found` that DOT actually has under a different
   spelling (see `research-team-lookup-misses.csv`), and 454 combinations missing
   entirely. The normalization rules that close them are in
   `research-team-feedback.md`.

## Files here

| file | what it is |
|---|---|
| `01_load_lu_place.sql` | loads the research team's file into `dwh.lu_place` |
| `02_load_lu_dot_place.sql` | loads the upstream DOT file into `dwh.lu_dot_place` |
| `03_apply_codes.sql` | every code-filling step, in order — rebuilds the 98.4% |
| `90_reference_queries.sql` | coverage, worklist, and the Milford proof |
| `research-team-lookup-misses.csv` | the 118 `Not Found` rows DOT actually has |
| `research-team-feedback.md` | normalization rules + how to pull the 454 gaps |

Run 01 → 02 → 03 in order to rebuild from scratch. `01` begins with a `TRUNCATE`, so
running it alone wipes the applied codes — always follow it with `03`.
