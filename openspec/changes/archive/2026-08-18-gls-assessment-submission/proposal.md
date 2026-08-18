# Proposal: GLS/NXT assessment submission

## Why

GLS/NXT asked for a design for a unified data platform: ingestion from internal
services, Segment, and streaming sources into an analytical warehouse, served
through Looker. The required deliverable is an architecture diagram plus a
written proposal; code is explicitly optional.

Two forces shape this change:

1. **The deliverable is a specification, not a codebase.** Scope is set by what
   can be stated precisely and verified end to end, not by what would be
   exhaustive.
2. **The document has to support a technical walkthrough.** Target-state
   decisions, prototype status, limits, and reversal conditions must be
   distinguishable at a glance.

So the submission is a written proposal backed by a small prototype that actually
runs, rather than either artifact alone.

## What changes

- A concise technical specification (`docs/proposal.md`) rendered to a PDF of at
  most 10 pages. It covers all five assessment tasks and acts as the presentation
  guide for a technical walkthrough.
- Four source-controlled Mermaid views using established notations: a C4
  container view, a UML sequence diagram, a crow's-foot dimensional ERD, and a
  UML state diagram for parcel milestones.
- Structured text in place of narrative where possible: component contracts,
  ownership and trust boundaries, failure and recovery behavior, and control
  matrices.
- A short engineering stance that makes the author's systems approach explicit:
  purpose and boundary first, function before construction, role-specific views,
  closed operational feedback, durable verification, and reversible decisions.
- A working local prototype: synthetic GS1 EPCIS parcel scan events served over a
  REST-shaped source, ingested with dlt into DuckDB, modeled with dbt into a
  Kimball star schema, tested, and surfaced in a marimo notebook.
- A live marimo operator and presentation interface. It starts with the platform
  purpose and functional architecture, then follows the five assessment tasks
  using selected code, diagrams, tables, and executable prototype results.
- One execution contract in the `Justfile`, shared by the CLI and marimo rather
  than reimplemented in the notebook.
- A concise README landing page with the same terminology, entry points,
  artifact state, and artifact map as the proposal and notebook.

## Non-goals

- **No Kafka in the implementation.** The design shows the streaming lane and
  states the volume threshold at which it becomes worth operating; the prototype
  runs the batch lane. A small team should not operate a broker it does not
  need, and the brief asks for pragmatism.
- **No cloud deployment.** DuckDB stands in for the warehouse. Models are written
  warehouse-agnostic where practical, and the proposal states what changes on
  BigQuery.
- **No Airflow instance.** DAG structure is shown as real code and reasoned about;
  `just` sequences the prototype.
- **No Go service.** Mentioned as an option for a high-throughput consumer; the
  prototype is Python.
- **No Looker instance.** LookML is shown as code; there is no Looker to run it in.
- **No production-completeness claim.** The prototype demonstrates selected
  properties locally; cloud infrastructure, orchestration, and serving remain
  target-state designs and are labelled as such.
- **No marketing treatment.** The proposal does not use KPI banners or
  promotional copy. Prototype measurements appear only where they verify a
  technical property or analytical result.

## Impact

- New capability spec: `parcel-analytics-platform`.
- Repository gains a Python project, a dbt project, an analytics surface, and a
  Justfile. `docs/` gains the proposal, Mermaid sources, and generated diagram
  assets alongside the brief.
- The presentation pass changes the proposal, README, notebook, and build
  recipes. It adds an operator-facing execution surface but does not add a
  second orchestration implementation or claims beyond the brief,
  implementation, and verified OpenSpec record.
