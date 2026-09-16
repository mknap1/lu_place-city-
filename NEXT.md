# Where this stands

**99.5% coded.** All matching work is complete and validated. What remains is
handoff, not SQL.

## Backup

The repo is the backup. `06_lu_place_snapshot.sql` holds the full table as INSERTs --
rebuild from nothing, diff between versions, review changes in a PR. Regenerate it
after any batch of edits. Cluster snapshots cover an accidental DROP but restore
everything, not one table.

## Tables in prod

| table | what |
|---|---|
| `dwh.lu_place` | the answer. `(state, county, normalized name)` -> `citycode` |
| `dwh.lu_place_dot` | the DOT reference, verbatim. Needed only to rebuild |

`lu_census_dual` and `lu_county_adjacency` were analysis scaffolding and have been
dropped. Loaders are still here if they're ever needed again.

Dropped from `lu_place`: `countycitycode` (derivable, and grouping by it would split
multi-county places) and `crosscountyflag` (meaning never established).

## Validation that was run, all clean

- **No duplicate keys** on `(stateabbr, countyfipscode, citynamenorm)`
- **No wrong merges** — every code that groups multiple spellings groups them for a
  typography reason only. Checked by folding `SAINT`/`ST`, `MOUNT`/`MT`,
  `HEIGHTS`/`HTS`, township suffixes and spaces, then looking for codes whose members
  still disagree. Empty.
- **No wrong splits** — same name on two codes only where they're genuinely different
  towns in non-adjacent counties: PA Mechanicsville, Middletown, Warwick, Lehman.
- **Townships verified against Census** county subdivisions. 31 rows split with `T`
  codes, only where Census confirms a borough/city *and* a township both exist in that
  county.
- **Collision pairs resolved.** Of ~78 same-code-different-county pairs, Census
  confirmed three as genuinely two towns (Lehman, Fairview, Mount Pleasant) — split.
  The rest are miscoded listings.
- **Minted codes dense and unique**, no reuse. Gaps exist where a mint was later
  reverted to a real DOT code -- that is correct, codes are never recycled.
- **No minted township/plain pairs left split** -- the mint keyed on name, so
  `LAWRENCE` and `LAWRENCE TOWNSHIP` got separate codes; Census confirmed Mercer
  County has only the township, and they were merged.
- **Aliases added for every unmatched string that folds onto an already-coded row
  in the same county**, gated on the fold resolving to exactly one code.

## Two bugs found and fixed, worth remembering

**Duplicate minted codes.** Two mint scripts each started `ROW_NUMBER` at 1, so
`L0001`–`L0036` covered two unrelated towns each. Renumbered densely.

> **Rule: a new mint must start at `MAX(citycode) + 1`, and must first check whether
> that name already has a code elsewhere in the state.** Both bugs came from skipping
> one of those. Six places got a fresh code when they should have reused an adjacent
> county's.

**Missed township split.** `MT JOY TWP` didn't split because the Census join compared
`MOUNT JOY` against `MT JOY` without folding. Any future Census comparison needs the
same `MOUNT`/`MT` and `SAINT`/`ST` folding applied to both sides.

## Left to do

1. **Send the research team** `research-team-feedback.md` and
   `research-team-lookup-misses.csv` — 118 rows they marked `Not Found` that DOT
   actually has, plus 454 combos missing from their file entirely. Fixing it upstream
   means `lu_place` reloads clean instead of carrying local patches.
2. **Build the dropdown query** (see the display rule at the top of `README.md`).
   Not built — deliberately left to whoever owns the UI.
3. **Stamp `citycode` onto the serving table** at build time, so the dashboard filters
   an indexed column instead of doing a three-way string join per query.

## Deliberately not done

- The junk tail: `UNKNOWN` (17,080 listings), `21215BALTIIMORE`, misspellings.
  0.7% of listings, correctly invisible.
- Baltimore City neighborhoods (Roland Park, Highlandtown, Govans). Team decision:
  not separate places. Could be aliased onto Baltimore later.
- True township-vs-city splits where only the string differs. Most York Township homes
  have a "York, PA" postal address, so a string split gives two wrong numbers rather
  than one merged one. A real split needs coordinates.

## Rebuild from scratch

`01_load_lu_place.sql` -> `02_load_lu_place_reference.sql` -> `03_apply_codes.sql`
-> `04_mint_local_codes.sql`

`01` starts with `TRUNCATE`, so running it alone wipes every assigned code. Always run
the sequence. Note the manual fixes made after `04` (the three collision splits, the
six reverted mints, Mount Joy) are **not** in a script — they'd need re-applying, or
folding into `04`.
