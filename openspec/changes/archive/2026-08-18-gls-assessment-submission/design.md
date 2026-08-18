# Design

## Context

The primary artifact is a document; the prototype exists to make the document
defensible. Every design choice below is therefore filtered by whether it
strengthens the specification — nothing is built for its own sake.

The audience is a small data team. Recommendations sized for a platform org
would be wrong here even where they are good engineering.

## Goals / Non-Goals

### Goals

- Cover all five assessment tasks in one coherent document, not five essays.
- Ground the design in a named industry model rather than generic clickstream.
- Make every proposal snippet real, executed code.
- Be explicit about trade-offs, including what was deliberately not built.

### Non-Goals

- Production deployment, cloud infrastructure, or a running orchestrator.
- Breadth of technology coverage for its own sake.

## Decisions

### D1: GS1 EPCIS as the source event model

Parcel scan events are modeled on GS1 EPCIS — the industry-standard event model
for supply-chain visibility, where every event answers *what / when / where /
why*: `epc` (parcel identity), `eventTime`, `bizLocation` (depot or hub),
`bizStep` (pickup, hub scan, out-for-delivery, delivery attempt, delivery), and
`disposition` (in-transit, delivered, exception). Parcel identifiers follow the
UPU S10 convention.

*Why:* EPCIS supplies a carrier-domain vocabulary without inventing one, and the
model is genuinely simple — one event table with five meaningful columns.

*Alternative rejected:* an invented generic clickstream. Cheaper, but discards the
strongest differentiator available in a submission everyone else will answer with
the same tool list.

*Reversal condition:* if GLS/NXT's actual event stream is app/web product
telemetry rather than carrier scans, the fact grain changes but the layering does
not.

### D2: Batch lane implemented, streaming lane designed

The architecture shows two ingestion lanes. The prototype builds only the batch
lane: a REST-shaped source ingested with dlt.

*Why:* the brief asks for pragmatism, and a small team operating Kafka for
volumes that fit micro-batch is a real anti-pattern. Stating the threshold at
which streaming becomes worth its operational cost is a stronger senior answer
than provisioning a broker.

*Alternative rejected:* running Kafka locally in Compose. Costs hours, proves
little, and contradicts the recommendation the document makes.

*Reversal condition:* named explicitly in the proposal in terms of event volume,
latency requirement, and consumer count.

### D3: DuckDB as a warehouse-agnostic stand-in

dbt models are written to run on DuckDB locally; the proposal states what changes
on BigQuery, including partitioning, clustering, and slot cost.

*Why:* BigQuery is the selected target warehouse. DuckDB makes the prototype
runnable with no cloud account while preserving the same logical model.

*Alternative rejected:* targeting BigQuery directly — it cannot be executed
locally without credentials.

*Consequence:* portability is carried by `dbt.datediff` and `dbt.type_string`
rather than by an abstraction layer, with one exception: a calendar spine has no
portable spelling, so `dbt_utils.date_spine` supplies it. Weekday numbering is
counted from a known Monday for the same reason — `extract(dow …)` is DuckDB's
spelling, `dayofweek` is BigQuery's, and their bases disagree.

### D4: dlt for ingestion, dbt for transformation

*Why:* dlt handles schema evolution, incremental state, and idempotent merge
without hand-written loader code — exactly the properties the brief asks about in
Task 2. dbt is what the target stack already uses.

### D5: Data quality as a layered stack, not a single tool

Contract enforcement at ingestion (quarantine on required-field violation),
constraint and business-rule tests in dbt, freshness on sources, and anomaly
detection as the layer above. The proposal names the open-source options for the
top layer and recommends one sized for the team.

*Why:* the role description leads with quality and testing, more heavily than the
assessment document's equal-fifths structure implies. This is the section to
over-weight.

### D6: Document rendered Markdown to PDF; marimo as a separate artifact

`pandoc docs/proposal.md -o docs/proposal.pdf --pdf-engine=typst`, styling in
frontmatter and a small raw Typst preamble. Mermaid sources render to SVG for
browser use and high-resolution PNG for the PDF; the marimo notebook exports to
HTML as the working proof.

*Why:* the submission is by email; the PDF must stand alone with no repo access.
Proven toolchain, no new tooling risk.

### D7: Ingestion cursors on the feed's own sequence, not on any payload column

The dlt incremental cursor is `feedOffset` — a sequence number the tracking
service stamps on acceptance — while the warehouse batches and partitions on
`eventTime`. EPCIS `recordTime` remains a required business column and the
`loaded_at_field` for source freshness.

*Why:* two separate mistakes are available here. Cursoring on **event time** is a
data-loss bug: a depot handheld that loses connectivity buffers and replays days
later, an event-time cursor filters those rows out at extraction, and no
downstream lookback can recover a row that never arrived. Cursoring on
**record time** fixes the clock and leaves the ownership wrong — it is a payload
column the contract can find missing, and a feed cannot position a row that
lacks its own watermark. Serving such a row unconditionally means re-serving it
on every request forever; filtering it means deleting it from the feed. The
watermark therefore has to belong to the transport, which is the one participant
guaranteed to have it.

*Alternative rejected:* a lag applied to the event-time cursor. It works until the
lag is exceeded, and it fails silently when it is.

*Alternative rejected:* keeping the record-time cursor and de-duplicating
re-served rows in the quarantine accounting. It treats the symptom: the feed
still re-transmits every malformed row it has ever seen, on every run, for as
long as the row is retained.

*Verification:* a two-run test in which a scan whose event time predates run 1's
newest event is absent after run 1 and present after run 2; and a steady-state
run over an unchanged feed, which reports zero rows loaded and zero quarantined
rather than one quarantined row and a 100% contract-failure rate.

*Consequence:* the quarantine gate can divide by this run's rows without a quiet
hour reading as a total contract failure and failing the DAG.

### D8: Microbatch for the scan fact; full rebuild for the journey

`fct_parcel_scan` uses `incremental_strategy='microbatch'` (day batches, seven-day
lookback). `fct_parcel_journey` is a plain table, rebuilt from the complete
retained scan history on every run.

*Why:* microbatch makes each day independently idempotent and retryable, and turns
an old correction into a bounded backfill rather than a full refresh. The
constraint it imposes — every column must be a function of its own row — is the
point: window functions inside an incremental filter recompute against truncated
history and merge the truncation over correct values.

The journey does not get the same treatment, and that is the correction. Selecting
journeys to rebuild by recent scan activity is wrong in a way no test downstream
can see: the accumulating snapshot copies parcel attributes such as
`promised_delivery_ts`, and a master-data correction changes one *without
producing any scan*. The parcel is not selected, the copied value stays stale, and
`is_on_time` stays wrong while every test passes. Rebuilding is the cheaper
guarantee at this volume, and it also removes the first-build and full-refresh
special cases that a clock-relative floor needed.

*Rejected alternatives:* joining the mutable attributes downstream instead of
copying them (dimensionally purer, but moves `is_on_time` out of the fact and
ripples into the mart, Looker and the notebook); unioning changed parcel keys into
the incremental selection (correct, but needs a `dbt snapshot` on the parcel master
to know what changed — the right answer once rebuild time justifies it).

*Enforced by:* `assert_scan_fact_covers_landed_events` (no landed event is
unmodelled, so a lookback that is too short is a red build rather than a silent
undercount, repaired by `just dwh-backfill`), `assert_scanned_parcels_have_journeys`
(no parcel with scans lacks a journey row), and `assert_journey_agrees_with_scan_fact`
(the snapshot's scan count matches the fact's, catching scans dropped by the
milestone view's inner joins to `dim_biz_step` and `dim_location`).

### D8a: The late-arrival repair is human-run, not orchestrated

The DAG ingests, checks quarantine rate, gates on freshness, and builds. It does
not issue its own backfill for scans that landed outside the rebuild window.

*Why:* the orchestrated version keeps its recovery request in the ingestion task's
return value, and ingestion has already committed both the rows and its feed
cursor by the time the backfill runs. A failure there loses the request: the next
scheduled run finds nothing new, computes no range, and skips the repair. Making
it durable means a pending-work table and its own reconciliation — a second thing
that can be wrong, guarding a case the coverage test already makes loud.

*Consequence:* the build stays red, naming the missing events, until an operator
runs `just dwh-backfill <start> <end>`. Loud and manual beats automatic and
lossy.

*Same reasoning, second application:* the quarantine-rate gate moved out of the
DAG for the same reason and is now `assert_quarantine_rate_within_bounds`,
scoped to the newest `_dlt_load_id`. A gate reading counts returned by the
ingestion task loses them when that worker dies after the rows are committed and
the cursor has advanced; the retry sees an empty feed and passes the batch that
should have failed. Committed data is durable state, and a dbt test is where the
durable check belongs.

*Verified on:* dbt-core 1.12.2 with dbt-duckdb 1.11.0, where microbatch compiles
to delete+insert per batch and rejects `unique_key`. `concurrent_batches=false` is
required because DuckDB serialises catalogue writes; it comes off on BigQuery.

### D9: Column prose lives in `doc()` blocks

Every description in the schema YAML is a `{{ doc('...') }}` call resolving to a
block in a `_<layer>_docs.md` file, following the Microblink `bi-platform`
convention.

*Why:* a column keeps one definition wherever it surfaces. Copy-pasted
descriptions are how a warehouse acquires three subtly different definitions of
the same column.

### D10: Terraform declares the privacy controls; dbt attaches them

Terraform owns the taxonomy, the policy tags and the masking data policies, and
exports the tag names. dbt attaches a tag to a column in `_core_schema.yml`,
parameterised by a var the deploy fills from the Terraform output.

*Why:* BigQuery masks a column only once a tag is on that column, so a taxonomy
with nothing tagged is decoration. Columns are dbt's under D-split above, so the
attachment has to live with the models that create them. One masking policy per
tag, because a child tag inherits its parent's access grants and not its masking
rule.

*Consequence:* a mask is only as strong as the columns beside it, and two would
have reconstructed this one. Event identifiers are vendor-assigned UUIDs rather
than `<tracking number>-<step>`, and the surrogate key is salted with a
deployment secret rather than a plain `md5(parcel_id)` an analyst can recompute
from a tracking number. Both are guarded by `assert_parcel_id_not_recoverable`,
since no other test in the suite can see either.

*Consequence:* the tag name reaches dbt through the deployment environment, so it
can be absent, and an absent tag compiles to an untagged column that passes every
test here. `assert_policy_tag_configured` runs from `on-run-start` and fails the
build on any adapter with column-level access control, before a single table is
written. Empty stays correct on DuckDB, which has no such control.

*Consequence:* the identity that attaches a tag also has to read through it.
`bigquery.tables.setCategory` is not carried by Data Editor, and every model
downstream of a classified column joins on its real value — so the transformation
account gets that one permission as a custom role and fine-grained reader on the
tags, or classification breaks the build that applies it. Masking is for the
human audience; a transformation reading masked keys produces a broken warehouse.

*Related:* the same "the control has to reach the object" test applies to
retention. A dataset's default partition expiration only affects partitioned
tables, so the dlt source hints a partition column on every landing table, master
data included — the parcel master holds the pseudonymous identifier, and left
unpartitioned it would have persisted indefinitely under a policy that read as
covering it. Its merge re-stamps each row, so current state ages out when the
source stops serving it. Table level expiration is rejected: it would drop dlt's
own state tables and with them the incremental watermark.

Schema evolution reaches around the same control. dlt normalises a repeated field
into a child table, which is unpartitioned and carries no landing timestamp — the
prototype's one `sensor_flags` array produced exactly that. Unknown nested values
are serialised into the parent row, so the axis holds for the fields nobody has
designed for, which are the ones most likely to arrive carrying personal data.

The column is `landed_at`, stamped at extraction, not the source's `record_time`.
BigQuery drops rows written into a partition already past its expiry, so a
retention window measured on a source timestamp deletes a historical replay on
arrival — the loader advances its cursor, the rows are gone before the build
runs, and `assert_scan_fact_covers_landed_events` cannot see what is no longer
there. Retention is a promise about how long *we* keep data, so it is measured on
our clock. `record_time` stays a required business column and the freshness
field, which is the question it does answer.

*Related:* and to what retention *removes*. Deriving a conformed dimension from
the current contents of a landing table couples the dimension's domain to the
retention window — the day a raw partition ages out, the calendar rows for it
disappear while the facts still reference them. The date spine is therefore
pinned to `scan_history_begin`, not to `min(event_date)` in raw. Simulated on the
prototype, the derived spine loses 16,208 fact rows to a broken foreign key; the
pinned spine loses none.

### D11: The component that creates a table owns its physical layout

dbt declares the scan fact's `partition_by` and `cluster_by`. Terraform declares
no BigQuery tables at all.

*Why:* the earlier split — Terraform owns physical layout, dbt owns column
schema — cannot survive contact with a `CREATE`. Partitioning and clustering are
properties of table creation, and dbt creates the table: a Terraform-declared
table is replaced by the first full build, taking its partition spec with it,
while Terraform reports drift on an object it no longer describes. Declaring the
table in Terraform also means declaring its schema, which is the review
bottleneck the split existed to avoid. dbt-bigquery independently *requires*
`partition_by` under microbatch, because a batch is an `insert_overwrite` of the
partitions it covers.

*Consequence:* `event_time` and the partition column are the same column, so a
batch replaces exactly one partition and every bounded read downstream prunes on
the same predicate.

*Not set:* `require_partition_filter`. dbt's generic tests compile to
unpredicated selects, so the guardrail would reject the fact's own test suite
before it validated anything. Cost control is partitioning, clustering, and a
project-level bytes-billed cap.

*Gotcha:* `partition_by` is not a BigQuery-only config name. dbt-duckdb reads it
too, for hive-partitioned exports, and rejects the dict shape BigQuery requires —
so the physical block is guarded by `target.type` rather than passed through.

### D12: One environment per run, named once

The DAG names the destination, the landing dataset and the dbt target once, in
`WAREHOUSE_ENV`, and hands that environment to every task — the dlt loader
included. dbt reads the target in `profiles.yml` and the landing dataset in the
source definition, both from the same variables.

*Why:* the failure this prevents is quiet rather than loud. A loader configured
separately from the build lands rows in one warehouse while freshness and the
models read another, and every task goes green while checking data none of the
others wrote. A gate validating a different warehouse than the build reads is not
a gate.

### D13: Terraform state key supplied per environment at init

The `backend "gcs"` block names the bucket and not the prefix;
`terraform init -backend-config="prefix=data-platform/<env>"` supplies it.

*Why:* a backend block cannot read variables, so a hardcoded prefix is one state
file for every environment whose resources are parameterised by `environment` and
`project_id`. The first `init` in production would load development's state and
plan the replacement of a warehouse it never created. Locking solves concurrent
applies, not shared identity.

### D14: Top-down, multi-view technical specification

The proposal, README, and notebook use one top-down information hierarchy:
platform intent, repository structure, functional architecture, operating path,
the five assessment tasks, then prototype status and limits. They are organised
by system concern rather than implementation history. Four Mermaid views carry the
relationships that prose handles poorly:

1. C4 container view for platform components, actors, and system boundaries.
2. UML sequence diagram for scheduled ingestion, quality gates, transformation,
   and serving.
3. Crow's-foot ERD for dimensional relationships and fact grains.
4. UML state diagram for parcel journey milestones.

A short engineering stance precedes those views. It is applied rather than
promotional:

| Principle | Application in this submission |
|---|---|
| Purpose and boundary first | Name the analytics platform as the system of interest; show operational sources, consumers, and group systems as its environment. |
| Function before construction | Explain the capability flow before mapping it to dlt, BigQuery, dbt, Looker, and Airflow. |
| Multiple views for multiple concerns | Separate context and containers, runtime behavior, information structure, and parcel state. |
| Close the feedback loop | Failed contracts, freshness, and coverage return actionable context to the operator. |
| Claims have a truth condition | Label each statement as target state, executed prototype, or an explicit assumption. |
| Prefer reversible decisions | Record the trigger that would replace batch, rebuild, or local tooling choices. |

Each section labels **Target state** and **Executed prototype** explicitly. The
target state demonstrates the proposed platform; the prototype supports selected
claims and is never presented as a deployment. Tables define contracts,
ownership, failure handling, and decision reversal criteria. Code excerpts are
kept only where syntax itself is material to the decision.

Statements name selected behavior, ownership, scope, activation conditions, and
reversal conditions directly. This keeps the specification affirmative and
implementation-oriented.

*Why:* the document must stand alone and also support a live technical
walkthrough. Stable views and concise contracts let backend engineers, data
engineers, and data scientists enter through their own concerns without turning
the proposal into three separate narratives. The stance also makes the author's
systems-thinking method visible through the work products, without adding a
personal essay.

*Alternative rejected:* a shortened essay with more decorative diagrams. It
reduces length but keeps the reasoning implicit and gives the presenter no stable
map for questions.

### D15: Marimo as a thin operator and presentation interface

The live marimo notebook is the primary guided interface for operating and
presenting the local prototype.
It provides:

1. A concise platform summary and functional architecture before implementation
   detail.
2. A visible local build status and one control for the complete prototype run.
3. Sections matching Tasks 1 through 5 of the assessment, with selected real
   code excerpts, formal diagrams, contracts, decision tables, and analytical
   results.
4. Explicit labels for target-state design and executed prototype status.

The notebook invokes the same `Justfile` recipe as the CLI and reads the artifacts
that recipe produces. Pipeline stages, command construction, and failure rules
remain outside the notebook. Command output and non-zero exits are visible to the
operator. The static HTML export preserves the guided walkthrough but labels its
execution control as available only in the live notebook.

The README remains the repository landing page. It provides the short summary,
functional architecture, CLI and notebook entry points, artifact state,
and links to the proposal and generated artifacts. This reuses the compact
assessment structure established in the author's earlier submissions.

The development path is open-source driven: `uv`, `just`, dlt, DuckDB, dbt Core,
marimo, Mermaid, Pandoc, and Typst support local execution and review without
cloud credentials. BigQuery and Looker remain target interfaces where they are
not executed locally.

*Why:* one execution contract gives the CLI a stable automation interface and
the notebook a low-friction operator experience. The common information
hierarchy keeps the README, PDF, live walkthrough, and follow-up questions
consistent.

*Alternative rejected:* duplicate the pipeline in notebook cells. It improves
the demo superficially but creates a second orchestration path with different
ordering, error handling, and maintenance.

*Reversal condition:* if the workflow becomes an unattended production service,
Airflow and its observability surface become the operator interface. Marimo stays
the analytical and presentation surface, while the CLI remains the local
development contract.

## Risks / Trade-offs

- **Prototype overruns and eats proposal time.** Mitigated by building the
  walking skeleton first and keeping the proposal written to stand alone, with
  snippets swapped in rather than depended on.
- **EPCIS can be obscure outside logistics.** Mitigated by keeping the model
  self-explanatory: the standard is named once, then the columns speak for
  themselves.
- **Synthetic data proves less than real data.** Acknowledged in the document
  rather than hidden; the generator is deterministic and its assumptions stated.
- **Visual compression can hide operational detail.** Mitigated by keeping
  contracts, failure behavior, ownership, and reversal conditions in adjacent
  tables and linking every prototype claim to a repository artifact.
- **Notebook and CLI behavior can drift.** Mitigated by making the notebook call
  one documented `Justfile` recipe and by smoke-testing both entry points.

## Migration Plan

Not applicable — new repository, no existing behavior.

## Open Questions

- Whether GLS/NXT's Segment implementation is the system of record for product
  events or a secondary tap. Stated as an assumption in the proposal.
