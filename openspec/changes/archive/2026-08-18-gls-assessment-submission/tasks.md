# Tasks

## 1. Walking skeleton

- [x] 1.1 Python project: `pyproject.toml`, `.python-version`, `uv sync`
- [x] 1.2 Deterministic GS1 EPCIS parcel scan event generator, REST-shaped payloads
- [x] 1.3 dlt source + pipeline loading events into DuckDB, incremental on event time
- [x] 1.4 dbt project on DuckDB: one staging model, one fact, `dbt build` green
- [x] 1.5 `Justfile` running generate → ingest → build in one command

**Verified:** `just demo-all` exits zero from a clean state.

Scope grew during 1.3: rather than reading files, a stdlib `http.server` serves
the data as a paginated REST API, so the ingestion path is a real HTTP pagination
loop. The proposal claims dlt handles REST sources; this makes that executable.

## 2. Dimensional model

- [x] 2.1 Staging layer: typed, renamed 1:1 views over the landing tables
- [x] 2.2 `dim_parcel`, `dim_location`, `dim_biz_step`, `dim_date`, `dim_merchant`
- [x] 2.3 `fct_parcel_scan` — transaction fact, grain declared in the model description
- [x] 2.4 `fct_parcel_journey` — accumulating snapshot, milestones and durations
- [x] 2.5 `mrt_service_performance_daily` — on-time, first-attempt, exception rates

**Verified:** `dbt build` green; grain uniqueness and referential tests passing.

Conventions adopted from the Microblink `bi-platform` production repository:
`__sk`/`__fk` key suffixes, `stg_`/`int_`/`dim_`/`fct_`/`mrt_` prefixes, layer
schemas, grain header blocks, and a `final_select()` macro appending audit
columns to every row.

## 3. Data quality

- [x] 3.1 Ingestion contract: required-field violations diverted to quarantine
- [x] 3.2 Schema tests: not-null, unique, accepted values, relationships
- [x] 3.3 Singular tests: grain uniqueness, milestone ordering, terminal state
- [x] 3.4 Source freshness configured
- [x] 3.5 A deliberately broken input demonstrates the build failing loudly

**Verified:** 85 tests pass. The quarantine path is exercised by an injected
contract violation; idempotency by two consecutive loads returning 33,113 rows.

3.3 found a real defect. The milestone-ordering test failed on 20 parcels whose
delivery preceded their collection, caused by the generator resetting the clock
to morning for a delivery round that had already passed. Fixed by moving the
clock forward to the next van load instead.

## 4. Analytics surface

- [x] 4.1 marimo notebook over the marts, organised as tabs by assessment part
- [x] 4.2 HTML export
- [x] 4.3 Diagrams for the proposal

**Verified:** notebook exports headless with no failing cells; all five tab bodies
present in the HTML.

Diagrams are text-sourced: architecture as hand-authored SVG, star schema as
Mermaid rendered by `just docs-erd`, plus a DBML expression validated offline by
`just docs-dbml`. Mermaid SVG is rendered to PNG for the PDF because typst cannot
render the `foreignObject` elements Mermaid uses for text.

## 5. Infrastructure as code

- [x] 5.1 BigQuery datasets per layer with retention on raw
- [x] 5.2 Partitioning and clustering on the scan fact
- [x] 5.3 Service accounts and dataset-scoped IAM
- [x] 5.4 Policy tags and a data masking policy for recipient attributes

**Verified:** `just infra-check` — `terraform fmt -check` and `terraform validate`
both pass. Never applied; there is no GCP project behind it.

Added after the initial plan: the brief asks for an infrastructure strategy, and
describing Terraform without shipping any is a weaker answer than shipping
configuration that validates.

## 6. Proposal

- [x] 6.1 Architecture diagram as SVG
- [x] 6.2 Task 1 — architecture: components, lifecycle spine, infrastructure strategy
- [x] 6.3 Task 2 — pipeline: ingestion, orchestration, schema evolution, quality
- [x] 6.4 Task 3 — modelling: grain, star schema, incremental strategy, governance
- [x] 6.5 Task 4 — Looker: LookML layering, metric consistency, analyst collaboration
- [x] 6.6 Task 5 — CI/CD, security and privacy, documentation and lineage
- [x] 6.7 Airflow DAG shown as real code, reasoned about, not run
- [x] 6.8 Trade-off register: each decision with criteria and reversal condition
- [x] 6.9 Real snippets from the prototype throughout

**Verified:** every assessment requirement traced to a section; `mado check` clean.

## 7. Package and submit

- [x] 7.1 Render `docs/proposal.pdf` via pandoc + typst
- [x] 7.2 `README.md`: what this is, how to run it, where the deliverable is
- [x] 7.3 Read the PDF rendered — 14 pages, diagrams and tables render correctly
- [x] 7.4 Full clean run of `just demo-all`
- [x] 7.5 `ruff check`, `ruff format`, `terraform validate`, `mado check` all clean
- [x] 7.6 Commit — held back until the proposal was submitted, then landed on
      `main` as eight scoped commits (scaffolding, ingestion, warehouse, infra,
      orchestration, analytics, docs, change record) and pushed to `origin`

## 8. Hardening: ingestion cursors, fact grain, and pipeline gates

A design review of the working tree returned seven high findings. All are fixed;
the two mediums were in the same files and were fixed with them.

- [x] 8.1 Ingestion cursors on `recordTime`; source freshness measured on arrival
- [x] 8.2 Contract check covers every column the loadable table declares required
- [x] 8.3 `fct_parcel_scan` on the microbatch strategy; per-parcel window columns
      removed from a grain that cannot compute them correctly
- [x] 8.4 Journey merged over a bounded scan window that satisfies
      `require_partition_filter`, guarded by a window-invariant test
- [x] 8.5 Freshness gate fails the DAG instead of short-circuiting it
- [x] 8.6 Quarantine gate measured on this run's load packages, not the table
- [x] 8.7 `roles/bigquery.jobUser` for both pipeline service accounts
- [x] 8.8 `**/.terraform/` ignored; the 114 MiB provider binary is out of the tree
- [x] 8.9 `delivered_date__fk` is null while in flight, with a relationship test
- [x] 8.10 Every description moved to a `doc()` block in `_<layer>_docs.md`

**Verified:** `just demo-all` exits zero, 90 dbt tests pass, headline metrics
unchanged. Late arrival proven by a two-run test: a scan recorded three days
after the previous run's newest event time lands on the second run.

## 9. Hardening: guarantees that must hold at the edges

A second review returned five high findings, all concerning
guarantees the platform states but does not hold at its edges. All are fixed.

- [x] 9.1 A row missing the cursor column reaches quarantine: the API stops
      filtering cursorless rows out of the feed, the incremental is
      `on_cursor_value_missing="include"`, and a fifth generator defect exercises it
- [x] 9.2 `assert_scan_fact_covers_landed_events` — no landed event inside the
      fact's horizon may be unmodelled, so a lookback that is too short fails the
      build instead of undercounting the scorecard
- [x] 9.3 The DAG issues a bounded backfill over the event days the loader just
      landed when they precede the lookback horizon; `just dwh-backfill` is the
      manual equivalent
- [x] 9.4 The milestone read selects changed parcels from a bounded window, then
      rebuilds each from complete retained history
- [x] 9.5 The refresh floor drops to the start of retained history on a first
      build or full refresh, so a rebuild cannot silently drop older parcels
- [x] 9.6 `assert_scanned_parcels_have_journeys` — no parcel with scans lacks a
      journey row; `assert_journey_window_covers_transit` removed, its
      precondition no longer exists and its residual signal is covered more
      tightly by `assert_every_parcel_has_terminal_or_open_journey`
- [x] 9.7 Policy tags attached to `parcel_id` in every core model by dbt, from
      Terraform outputs; one masking data policy per tag, since a child tag does
      not inherit its parent's masking rule
- [x] 9.8 Landing tables partitioned on `record_time` via dlt column hints, so
      the dataset's partition expiry reaches them

**Verified at the time:** `just demo-all` exits zero from clean, 91 dbt tests
pass, headline metrics unchanged. The quarantine reports `missing_record_time: 1`
and the load succeeds; a second load adds no rows. The coverage guarantee is
proven by
injecting a scan that arrived now and happened ten weeks ago — the routine run
misses it, the test fails and names it, and a single-day `just dwh-backfill`
closes it in one batch. The journey fix is proven at a 20-day window,
where 98 of 357 selected parcels have a collection scan outside it and all 357
keep a non-null `collected_ts`; and at a 10-day window with `--full-refresh`,
where all 4,000 journeys are rebuilt while a clock-relative read would have
selected zero parcels.

## 10. Hardening: extraction cursors and the retention spine

A third review returned five high findings. All five held up
under inspection; all are fixed. Two of them challenged design decisions rather
than defects, and both decisions moved.

- [x] 10.1 Extraction cursors on `feedOffset`, a sequence the transport stamps on
      acceptance, rather than on `recordTime`. A watermark the payload owns is a
      watermark a malformed payload can be missing, and the workaround for that -
      serving cursorless rows unconditionally - re-served every malformed row on
      every run, so a quiet hour reported one quarantined row against zero
      loaded and failed the DAG's 1% gate
- [x] 10.2 `on_cursor_value_missing` and the API's unfiltered serve removed; both
      existed only to cope with a cursor that should not have been a business
      column
- [x] 10.3 A backfill runs the models downstream of the fact and lowers the
      journey's refresh floor to the event day being repaired
      (`journey_refresh_floor_date`), in the DAG and in `just dwh-backfill`
- [x] 10.4 `assert_journey_agrees_with_scan_fact` - the snapshot's scan count
      must equal the fact's, which is the disagreement a stale rebuild creates
      and neither table can reveal alone
- [x] 10.5 The date spine is pinned to `scan_history_begin` rather than derived
      from `min(event_date)` in raw, so raw retention cannot delete calendar rows
      the retained facts still reference
- [x] 10.6 dbt owns the scan fact's `partition_by`, `cluster_by` and
      `require_partition_filter`; Terraform declares no BigQuery tables. The
      component that issues the CREATE owns the physical layout, and
      dbt-bigquery requires `partition_by` under microbatch regardless
- [x] 10.7 `event_time` and the partition column unified on `event_date`, so a
      batch replaces exactly one partition and every bounded downstream read is
      also the partition filter the guardrail demands
- [x] 10.8 The transformation service account gets `bigquery.tables.setCategory`
      as a narrow custom role and fine-grained reader on the tags, so
      classification does not break the build that applies it

**Verified:** `just demo-all` exits zero from clean, 92 dbt tests pass, headline
metrics unchanged. A steady-state re-ingest over an unchanged feed reports zero
loaded and zero quarantined, where it previously reported a 100% quarantine rate.
The journey fix is proven at a 20-day window by injecting a scan that happened on
2026-06-03 and arrived today: the routine build fails the coverage test, a
fact-only backfill leaves the fact at 9 scans and the journey at 8 with every
test green, and the downstream backfill brings the journey to 9 scans and 2
delivery attempts. The retention fix is proven by deleting raw rows before
2026-07-01 and rebuilding: the pinned spine still starts 2026-06-01 with zero
orphaned facts, where a spine derived from raw would have orphaned 16,208 rows.

## 11. Hardening: simplification

A fourth review returned four findings. All held up, and every fix removes
machinery rather than adding it: three earlier decisions were over-engineered,
and the defects were their edges. Tasks 8.4, 9.3, 9.4, 9.5, 10.3 and part of 10.6
are superseded here.

- [x] 11.1 `require_partition_filter` removed from the scan fact. dbt's generic
      tests compile to unpredicated selects, so on BigQuery the guardrail would
      have rejected the fact's own test suite before it validated any data.
      `partition_by` and `cluster_by` stay: they are what actually make the
      bounded reads cheap
- [x] 11.2 `fct_parcel_journey` is a plain table rebuilt from complete retained
      history. The bounded merge selected parcels by recent scan activity, but the
      snapshot copies parcel attributes a master-data correction can change
      *without producing any scan* — so a corrected `promised_delivery_ts` left
      `is_on_time` stale with every test green
- [x] 11.3 `journey_refresh_floor()`, `journey_scan_window_days` and
      `journey_refresh_floor_date` deleted, along with the two-step milestone read
      and the first-build/full-refresh special cases they needed
- [x] 11.4 `backfill_late_event_days` removed from the DAG. Its recovery range
      lived only in the ingestion task's return value, after ingestion had already
      committed the feed cursor — a failure lost the request, and the next run
      found nothing new to compute a range from. The coverage test already makes
      the case loud; `just dwh-backfill <start> <end>` is the repair
- [x] 11.5 Notebook KPIs computed over delivered parcels, the denominator the mart
      and Looker use. Averaging the flags over all 4,000 journeys reported 92.025%
      against the semantic layer's 92.094%
- [x] 11.6 Notebook trimmed to the three tabs that are analysis — service
      performance, journey analysis, data quality. The data-model and pipeline
      panels restated the proposal and are gone, along with a hardcoded test count
      that had already drifted

**Verified:** `just demo-all` exits zero from clean, 92 dbt tests pass. Notebook
and mart now report identical on-time rates (92.094%), confirmed by querying both.
Headline table restated over delivered parcels in `README.md` and the proposal:
network 3,997 delivered, 92.1% on-time, 87.5% first-attempt. The express hub-dwell
finding is unchanged at 23.4%.

## 12. Hardening: privacy, retention, environment

- [x] 12.1 Event identifiers are opaque UUIDs instead of `<parcel_id>-<step>`.
      `parcel_id` is policy-tagged and masked, and an unmasked `event_id` in the
      same fact reconstructed it verbatim. Guarded by
      `assert_event_id_hides_parcel_id`, because no other test can see it
- [x] 12.2 Landing tables partition on `landed_at`, stamped at extraction, not on
      the source's `record_time`. BigQuery drops rows written into an
      already-expired partition, so retention measured on a source timestamp
      deletes a historical replay on arrival — the loader advances its cursor and
      the coverage test cannot see rows that are no longer there
- [x] 12.3 Quarantine gate moved from the DAG into
      `assert_quarantine_rate_within_bounds`, scoped to the newest
      `_dlt_load_id`. A gate fed by the ingestion task's return value loses its
      input when that worker dies after committing rows and advancing the cursor;
      the retry sees an empty feed and passes the batch that should have failed.
      Same reasoning as 11.4, applied to the second lossy XCom path
- [x] 12.4 One environment per DAG run: a single `DBT_TARGET` constant passed to
      both freshness and build, a `prod` output added to `profiles.yml`, and the
      dlt destination taken from config rather than hardcoded to DuckDB.
      Previously ingestion wrote DuckDB, freshness validated `dev` and the build
      asked for an undefined `prod`
- [x] 12.5 `sensor_temp_c` no longer propagates past the landing table. It is the
      schema-evolution demo field, undeclared in the source contract, so a feed
      sending only the required payload would have failed the first staging build.
      Schema evolution is demonstrated where it happens — in raw

**Verified:** `just demo-all` exits zero from clean, `PASS=94 WARN=0 ERROR=0`.
Headline numbers unchanged — 33,113 scans, 4,000 journeys, 3,997 delivered,
92.094% on-time, 87.466% first-attempt. Zero rows match
`event_id like '%' || parcel_id || '%'`. `just data-ingest` twice leaves 33,113
and 3 rows, and the tests still pass after the second load.

## 13. Hardening: key derivation, config, master data

- [x] 13.1 Surrogate keys salted with a deployment secret (`surrogate_key_salt`).
      An unsalted `md5(parcel_id)` is recomputable by anyone holding a tracking
      number, so `parcel__sk` handed back the journey the policy tag withholds -
      the same failure class as 12.1, in a column no one reads as an identifier
- [x] 13.2 `assert_event_id_hides_parcel_id` renamed to
      `assert_parcel_id_not_recoverable` and extended to the surrogate key. One
      test for one property: nothing beside the masked column reconstructs it
- [x] 13.3 Destination, landing dataset and dbt target named once in the DAG's
      `WAREHOUSE_ENV` and passed to every task including the loader; the dbt
      source reads the landing dataset from the same variable. Previously the
      loader took its destination from checked-in dlt config while the build
      targeted BigQuery, and the source read `raw` where Terraform provisions
      `raw_prod`
- [x] 13.4 `dim_merchant` takes the merchant's most recent parcel rather than
      distinct attribute combinations, which emitted one row per historical tier
      under a single surrogate key - a routine account upgrade failing the build
- [x] 13.5 `parcels` and `locations` stamp and partition on `landed_at`, so raw
      retention reaches every landing table. The parcel master holds the
      pseudonymous identifier and was the one table the expiry did not reach

**Verified:** `just demo-all` exits zero from clean, `PASS=94 WARN=0 ERROR=0`,
headline numbers unchanged - 33,113 scans, 4,000 journeys, 3,997 delivered,
92.094% on-time, 87.466% first-attempt. `parcel__fk = md5(parcel_id)` matches
zero rows while the salted control matches all 33,113. `dim_merchant` holds 6
rows against 6 distinct merchants; `raw.parcels` and `raw.locations` carry
`landed_at` on every row. `RAW_DATASET=raw_prod` moves the compiled source to
`raw_prod`, unset resolves to `raw`. `just data-ingest` twice leaves
33,113 / 3 / 4,000. `ruff`, `terraform validate` and `openspec validate --strict`
clean.

## 14. Hardening: controls that reach their object

- [x] 14.1 `assert_policy_tag_configured` fails the build from `on-run-start`
      when the policy tag is empty on an adapter with column-level access
      control. An unset tag compiled to an untagged `parcel_id` that passed
      every test in the suite
- [x] 14.2 Unknown nested source fields are serialised into the parent row.
      dlt normalised `sensor_flags` into an unpartitioned child table with no
      `landed_at`, outside the retention policy the dataset advertises
- [x] 14.3 `assert_journey_milestones_ordered` extended with the null-safe half.
      Comparisons against a missing milestone are null, so a delivered parcel
      with a dropped collection scan passed the ordering test while counting as
      a first-attempt miss in the mart
- [x] 14.4 Terraform state prefix moved out of the backend block and supplied at
      `init`. One prefix across environments means production's first `init`
      loads development's state
- [x] 14.5 Date spine built with `dbt_utils.date_spine` and weekday counted from
      a known Monday, replacing DuckDB's `generate_series` and `extract(dow …)`

**Verified:** `just demo-all` exits zero from clean, `PASS=95 WARN=0 ERROR=0`
(94 tests plus the new run-start operation). Headline numbers unchanged -
33,113 scans, 4,000 journeys, 3,997 delivered, 92.094% on-time, 87.466%
first-attempt. `raw.scan_events__sensor_flags` no longer exists and the value
lands as `["cold_chain"]` in the parent row. The date spine holds 443 days from
`2026-06-01`, zero weekday mismatches against `isodow`, zero orphaned date
foreign keys. The guard raises on a target with column-level access control and
passes once `DBT_POLICY_TAG` is set. `ruff`, `terraform fmt`/`validate` and
`openspec validate --strict` clean.

## 15. Hardening: the documented recovery has to work

- [x] 15.1 `full_refresh=false` removed from `fct_parcel_scan`. The config
      overrode `--full-refresh`, so the salt rotation the proposal documents as
      a full rebuild left every historical scan on the old key while the
      dimensions were rebuilt on the new one
- [x] 15.2 Production dbt job location aligned with the Terraform dataset
      region. `EU` is a multi-region and `europe-west3` a single region;
      BigQuery rejects a job whose location differs from its datasets

**Verified:** rotation reproduced on DuckDB. With the config in place,
`DBT_SURROGATE_KEY_SALT=rotated-salt-test dbt run --full-refresh` reported
`PASS=14 ERROR=0` while orphaning all 33,113 scan rows and emptying
`fct_parcel_journey` - a silent success that published an empty serving table.
With it removed the same rotation rebuilds all 443 event days: 33,113 scans,
zero orphaned `parcel__fk`, 4,000 journeys, `PASS=95 WARN=0 ERROR=0`. Rebuilt
on the canonical salt, the mart returns 92.094% on-time and 87.466%
first-attempt over 3,997 delivered - unchanged.

The salt-fallback finding was deferred here and actioned in section 16.

## 16. Hardening: privacy controls and replay horizon

- [x] 16.1 Masking rule changed from `SHA256` to `ALWAYS_NULL`. A tracking
      number is a short structured identifier, so an unkeyed digest is
      recomputable by anyone holding one - the masked column read back the
      parcel the tag exists to withhold. Grouping and joining are served by the
      salted surrogate key, which is not recomputable, so nulling costs the
      analyst nothing
- [x] 16.2 `assert_surrogate_key_salt_configured()` added to `on-run-start`.
      The salt fell back to a value checked into this repository, and an absent
      deployment secret produced a passing build whose keys anyone holding a
      tracking number could recompute. Gated on the adapter and on the
      environment variable rather than the resolved var, so the fallback stays
      defined in one place
- [x] 16.3 `assert_raw_covers_history_floor` added. Raw partitions expire and
      the fact does not, so a rebuild after they age out reconstructs only the
      surviving window; the existing coverage test compares fact with raw and
      stays green on the truncated result. Raw retention is the replay horizon,
      and the test asserts it still reaches `scan_history_begin`
- [x] 16.4 `DESTINATION__BIGQUERY__LOCATION` set in the DAG environment. dlt's
      BigQuery client defaults to the `US` multi-region while Terraform builds
      the datasets in `europe-west3`, and a load job cannot cross locations

**Verified:** `dbt build` on DuckDB is `PASS=97 WARN=0 ERROR=0` - two more than
before, the new test and the second hook. The new test was proved to fire:
run against a floor of `2026-05-01`, earlier than raw retains, it errors. The
salt guard was proved to fire by temporarily gating it on `duckdb`, which
refused the run with `DBT_SURROGATE_KEY_SALT is unset` before any model was
written; the gate is back on `bigquery`. `terraform fmt -check` and
`terraform validate` clean, `ruff` clean, DAG parses.

Neither BigQuery-side control is executed here - no BigQuery is reached by this
submission - so `ALWAYS_NULL` and the salt guard are verified as configuration
and as a raise path, not as a masked query result.

## 17. Hardening: source trust boundary and replay coverage

- [x] 17.1 `_flatten` no longer lets the payload set a field it owns. Unmapped
      keys were applied over the canonical mapping, so a record carrying
      `parcel_id` or `landed_at` replaced the merge key or the partition key and
      still passed the contract check. Colliding keys now land under a
      `source_` prefix - carried, not dropped, and not trusted. The comparison
      folds case and underscores because dlt normalises `parcelID` and
      `parcel_id` onto one column
- [x] 17.2 `assert_raw_covers_history_floor` rewritten. Comparing raw's earliest
      event against the floor passed on an empty table, where the aggregate is
      null, and on a single surviving row at the floor, which is a consistent
      history of itself. Neither end of the span is now taken from raw: it must
      cover every day between `scan_history_begin` and the last day the fact
      publishes, and an empty result fails rather than passing vacuously

**Verified:** `just demo-all` from a clean warehouse is
`PASS=97 WARN=0 ERROR=0`, and the mart is unchanged at 92.094% on-time and 87.466%
first-attempt over 3,997 delivered. The collision is a reproduction, not a
reading: a payload carrying `parcel_id`, `landed_at`, `parcelID` and `LANDED_AT`
overwrote all of them before the fix and none of them after, while an ordinary
new field still passes through untouched. Four loss scenarios were replayed
against the rewritten test - empty raw, one day at the floor, a hole punched
mid-history, and the oldest month expired - and each returns a failing row where
the previous formulation returned none; the intact tree passes, and a floor of
`2026-05-01` errors the build. `ruff`, `ruff format --check`,
`terraform fmt -check` and `terraform validate` clean. No `source_` column shows
in the built warehouse: nothing in the real feed collides, so the guard is inert
on well-formed data.

## 18. Presentation-ready technical specification

- [x] 18.1 Revise the OpenSpec proposal, design, and capability requirement for
      a concise presentation guide with formal views and explicit
      target-state/prototype boundaries
- [x] 18.2 Replace the hand-authored architecture SVG with a Mermaid C4
      container source and generated SVG/PNG outputs
- [x] 18.3 Add Mermaid UML sequence and state sources with generated outputs;
      review the existing crow's-foot ERD for consistency with the final model
- [x] 18.4 Rewrite `docs/proposal.md` as a technical specification of at most 10 pages,
      remove the first-page KPI panel, and replace narrative with contracts,
      matrices, and decision tables where possible
- [x] 18.5 Convert the marimo notebook into a top-down operator and presentation
      interface over the shared CLI recipe, with a functional overview followed
      by Tasks 1 through 5 and clear live/static behavior
- [x] 18.6 Update the `Justfile` and `README.md` so the CLI and notebook share one
      execution path and every proposal diagram, PDF, and notebook export rebuilds
      from source
- [x] 18.7 Render and visually inspect the PDF and notebook HTML: navigation,
      diagram legibility, page breaks, live/static controls, and
      target/prototype labels
- [x] 18.8 Run Markdown lint, notebook checks, the end-to-end prototype, all
      diagram and document renders, OpenSpec strict validation, and diff checks

## 19. Implementation-specification terminology

- [x] 19.1 Express authored deliverables through system purpose,
      implementation responsibilities, and affirmative requirements.
- [x] 19.2 Name BigQuery as the target warehouse throughout the design and
      preserve the original assessment and role-description source files.
- [x] 19.3 Regenerate diagrams, PDF, and notebook HTML; verify authored sources
      and generated deliverables use the selected terminology.
- [x] 19.4 Remove the internal decision-register and implementation-status
      sections from the proposal; expose the `Justfile` command surface under
      `CLI`.
- [x] 19.5 Add a compact implementation-relevant repository structure to the
      beginning of the proposal and verify the rendered pagination.

## 20. Repository finalization

- [x] 20.1 Ignore `dbt/.user.yml` - a machine-local anonymous-usage id, not a
      project artifact
- [x] 20.2 Land the working tree on `main` as scoped commits rather than one
      bulk import: scaffolding, ingestion, warehouse, infra, orchestration,
      analytics, docs, and this change record
- [x] 20.3 Push to `origin/main`
- [x] 20.4 Archive this change and promote its spec delta into `openspec/specs/`

**Verified:** `just demo-all` from a clean warehouse is `PASS=97 WARN=0 ERROR=0`
with the mart unchanged at 92.094% on-time and 87.466% first-attempt over 3,997
delivered. `ruff check`, `ruff format --check`, `terraform fmt -check`,
`terraform validate`, `mado check` on the authored Markdown, and
`openspec validate --strict` are clean, and `git diff --check` reports no
whitespace damage. Nothing secret or machine-local is tracked: `.dlt/secrets.toml`,
`terraform.tfvars`, `*.tfstate`, the DuckDB file, and dbt `target/`, `logs/` and
`dbt_packages/` are all ignored, and a pattern scan over the added files found
only prose about secrets, never a value.
