# parcel-analytics-platform Specification

## Purpose
TBD - created by archiving change gls-assessment-submission. Update Purpose after archive.

## Requirements

### Requirement: Parcel scan event ingestion

The platform SHALL ingest parcel scan events shaped on the GS1 EPCIS event model,
carrying at minimum the *what* (parcel identifier), *when* (event time and record
time), *where* (business location), and *why* (business step, disposition) of
each scan.

Ingestion SHALL be incremental on a watermark the transport assigns on
acceptance, independent of every column the payload contract can find missing,
and SHALL be idempotent: re-running a load over an overlapping window MUST NOT
change downstream row counts.

#### Scenario: Incremental load over an overlapping window

- **GIVEN** a completed load covering scan events through a known watermark
- **WHEN** the pipeline runs again over a window overlapping that watermark
- **THEN** previously loaded events are not duplicated in the warehouse

#### Scenario: A scan arrives after the watermark that it predates

- **GIVEN** a completed load whose newest event time is later than a scan the
  source has not yet delivered
- **WHEN** the source subsequently accepts and serves that older scan
- **THEN** the next load ingests it rather than filtering it out

#### Scenario: Source adds an unknown field

- **GIVEN** a source payload carrying a field absent from the current schema
- **WHEN** the pipeline ingests that payload
- **THEN** the load succeeds and the new field is retained in the landing layer

#### Scenario: Source violates the agreed contract

- **GIVEN** a source payload missing any column the loadable table declares required
- **WHEN** the pipeline ingests that payload
- **THEN** the record is diverted to a quarantine table rather than failing the run
- **AND** the quarantine row names which requirement it failed
- **AND** the run reports a quarantine count scoped to that load

#### Scenario: A malformed record is served once and only once

- **GIVEN** a source payload missing a column the loadable table requires
- **WHEN** the pipeline ingests it, and then runs again with no new events
- **THEN** the record is quarantined on the first run and the loadable table
  gains no row for it
- **AND** the second run reports no rows loaded and no rows quarantined, so a
  quiet period cannot read as a total contract failure

### Requirement: Dimensional model over parcel journeys

The warehouse SHALL expose a Kimball dimensional model whose fact grains are
declared explicitly.

- A transaction fact SHALL record one row per parcel scan event.
- An accumulating snapshot fact SHALL record one row per parcel, carrying the
  milestone timestamps of its journey and the durations between them.
- Dimensions SHALL be conformed: a single parcel, location, business step, date,
  and merchant dimension serve all facts.

#### Scenario: Fact grain is unique

- **GIVEN** the built dimensional model
- **WHEN** the scan fact is grouped by its declared grain
- **THEN** no group contains more than one row

#### Scenario: Parcel journey milestones are ordered

- **GIVEN** a parcel with both a pickup and a delivery milestone
- **WHEN** the accumulating snapshot is built
- **THEN** the delivery timestamp is not earlier than the pickup timestamp

#### Scenario: Every fact row resolves to a dimension

- **GIVEN** the built dimensional model
- **WHEN** fact foreign keys are checked against their dimensions
- **THEN** no fact row references a missing dimension member
- **AND** a foreign key that is not yet knowable is null rather than a hash of null

#### Scenario: An incremental run does not rewrite settled attributes

- **GIVEN** a fact built incrementally over a bounded window
- **WHEN** a later run reprocesses that window
- **THEN** every column it writes is derivable from the rows inside the window

#### Scenario: An event lands outside the routine rebuild window

- **GIVEN** a scan accepted by the source whose event time precedes the
  transformation lookback
- **WHEN** a routine run builds the warehouse
- **THEN** the build fails and names the events the fact is missing
- **AND** a bounded backfill over the affected event days makes it pass

#### Scenario: A backfilled event day reaches the facts derived from it

- **GIVEN** a scan repaired into the transaction fact for an event day older than
  the routine refresh window, belonging to a parcel with no recent activity
- **WHEN** the backfill runs
- **THEN** the accumulating snapshot for that parcel is rebuilt from it as well
- **AND** the snapshot's measures agree with the transaction fact

#### Scenario: A parcel is rebuilt from history older than the refresh window

- **GIVEN** a parcel whose journey began before the refresh window and continued
  inside it
- **WHEN** the accumulating snapshot is rebuilt
- **THEN** its milestones are computed from its complete retained history
- **AND** a build with no incremental state to work from covers every parcel the
  warehouse holds scans for

### Requirement: Data quality enforcement in the transformation layer

The transformation layer SHALL enforce data quality as executable tests covering
schema-level constraints, business rules, and freshness, and a failing test SHALL
fail the build.

#### Scenario: Build fails on a broken business rule

- **GIVEN** a model whose output violates a declared business rule
- **WHEN** the transformation build runs
- **THEN** the build exits non-zero and names the failing test

### Requirement: Logistics service metrics

The platform SHALL serve carrier service metrics derived from the dimensional
model, including on-time delivery rate, first-attempt delivery rate, and
exception rate, each defined once and reused.

#### Scenario: A metric traces to its events

- **GIVEN** a published service metric
- **WHEN** its lineage is followed upstream
- **THEN** it resolves to the scan events it is computed from without an
  intermediate redefinition of the metric

### Requirement: Governance controls take effect on the objects they name

Infrastructure that declares a privacy or retention control SHALL be configured
so the control reaches the data it claims to cover, and the configuration SHALL
state which component completes it where ownership is split.

#### Scenario: A masking policy is declared

- **GIVEN** a policy tag carrying a data masking policy
- **WHEN** the warehouse is deployed
- **THEN** the tag is attached to every column holding the classified attribute
- **AND** the component that owns column schema is the one that attaches it

#### Scenario: A retention window is declared on a landing layer

- **GIVEN** a dataset configured to expire raw data on a schedule
- **WHEN** the loader creates its landing tables
- **THEN** those tables are partitioned on the axis the expiry applies to
- **AND** pipeline state the loader depends on is not subject to that expiry

#### Scenario: A conformed dimension outlives the landing data behind it

- **GIVEN** a raw landing partition that has aged out under retention
- **WHEN** the conformed dimensions are rebuilt
- **THEN** they still cover every member the retained facts reference

#### Scenario: A pipeline identity must read through a control it applies

- **GIVEN** a column classified by a policy tag the transformation layer attaches
- **WHEN** that layer builds a model reading the classified column
- **THEN** its identity holds the permissions to attach the tag and to read
  through it, so classification does not break the build that applies it

#### Scenario: A table's physical layout is declared

- **GIVEN** a table whose partitioning, clustering, or partition-filter guardrail
  is part of its design
- **WHEN** the platform is deployed
- **THEN** the layout is declared by the component that issues the table's
  CREATE, and no second component declares the same table

### Requirement: One-command reproducibility

The prototype SHALL run end to end from a clean checkout via a single command,
and that command SHALL exit non-zero if any stage fails.

#### Scenario: Clean-checkout run

- **GIVEN** a clean checkout with dependencies installed
- **WHEN** the operator runs the end-to-end command
- **THEN** events are generated, ingested, modeled, tested, and the analytics
  surface is produced, with a zero exit code

### Requirement: Presentation-ready technical specification

The submission SHALL provide a concise technical specification that gives
backend engineers, data engineers, and data scientists a navigable overview of
the target platform, supports a live technical walkthrough, and distinguishes
executed prototype from production design.

#### Scenario: Specification is navigated top down

- **GIVEN** the rendered PDF
- **WHEN** it is followed from scope to prototype status
- **THEN** all five assessment areas are covered in at most 10 A4 pages
- **AND** the first page contains document purpose and navigation rather than a
  KPI or marketing banner
- **AND** the first page maps the implementation-relevant repository directories
  to their responsibilities

#### Scenario: Engineering approach is explicit

- **GIVEN** the proposal overview
- **WHEN** design decisions are traced from principles to system views
- **THEN** it states a concise systems-thinking stance
- **AND** the architecture applies that stance through an explicit system
  boundary, functional decomposition, role-specific views, feedback paths,
  truth status, and reversal conditions
- **AND** statements express selected behavior, ownership, scope, and conditions
  directly

#### Scenario: Architecture is viewed from multiple concerns

- **GIVEN** the platform architecture, runtime behavior, information model, and
  parcel lifecycle
- **WHEN** their relationships are presented
- **THEN** they use source-controlled formal views: C4 container, UML sequence,
  crow's-foot ERD, and UML state diagram
- **AND** each view has a Mermaid source and generated render artifact

#### Scenario: Prototype status is explicit

- **GIVEN** a component, control, or behavior described by the proposal
- **WHEN** its execution state is stated
- **THEN** it is labelled as target state, executed prototype, or both
- **AND** no unexecuted cloud, orchestration, or serving artifact is presented as
  a deployed system

#### Scenario: A design decision is challenged

- **GIVEN** a material platform decision in the proposal
- **WHEN** its rationale is requested
- **THEN** the document supplies its criterion, consequence, and reversal
  condition without relying on promotional claims or casual explanation

### Requirement: Executable operator and presentation interface

The prototype SHALL provide a live marimo interface over the same execution
contract as the CLI. It SHALL present platform intent and functional
architecture through the five assessment tasks before presenting detailed
status.

#### Scenario: Operator runs the prototype from marimo

- **GIVEN** a checkout with dependencies installed
- **WHEN** the operator starts the live notebook and selects the complete build
- **THEN** marimo invokes the documented end-to-end `Justfile` recipe
- **AND** the interface reports the command status and output
- **AND** a failed stage is reported as a failed run rather than a successful
  notebook action

#### Scenario: Notebook follows the system top down

- **GIVEN** the live notebook or its exported HTML artifact
- **WHEN** the interface is opened
- **THEN** the platform summary and functional architecture precede detailed
  implementation detail
- **AND** Tasks 1 through 5 are navigable in assessment order
- **AND** each task uses only relevant code excerpts, diagrams, contracts,
  decision tables, or verified results

#### Scenario: Live and static behavior are distinguished

- **GIVEN** the exported HTML artifact
- **WHEN** the operator control is reached
- **THEN** it states that execution is available in the live notebook
- **AND** the remaining summary, architecture, task details, and analytical
  output remain readable without a Python kernel

#### Scenario: Repository entry points are compared

- **GIVEN** the README, proposal, and notebook
- **WHEN** their navigation and status statements are compared
- **THEN** they use consistent terms for the target platform, prototype, CLI,
  notebook, and generated artifacts
- **AND** the README provides a concise entry point rather than duplicating the
  technical specification
