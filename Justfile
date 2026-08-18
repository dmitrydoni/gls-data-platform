set shell := ["bash", "-uc"]

dbt_dir := "dbt"
api_pid := ".tracking-api.pid"

# List available recipes
default:
    @just --list

# --- environment ---

# Install Python dependencies
env-init:
    uv sync

# Show tool versions
env-versions:
    @uv run python --version
    @uv run dbt --version | head -2
    @uv --version

# --- data ---

# Generate the deterministic GS1 EPCIS parcel event set
data-generate:
    uv run python src/generate_events.py

# Start the local tracking API in the background
api-start:
    @if [ -f {{api_pid}} ] && kill -0 "$(cat {{api_pid}})" 2>/dev/null; then \
        echo "tracking API already running (pid $(cat {{api_pid}}))"; \
    else \
        uv run python src/tracking_api.py & echo $! > {{api_pid}}; \
        sleep 2; \
        echo "tracking API started (pid $(cat {{api_pid}}))"; \
    fi

# Stop the local tracking API
api-stop:
    @if [ -f {{api_pid}} ]; then \
        kill "$(cat {{api_pid}})" 2>/dev/null || true; \
        rm -f {{api_pid}}; \
        echo "tracking API stopped"; \
    else \
        echo "tracking API stopped"; \
    fi

# Check the tracking API is answering
api-health:
    @curl -sf http://127.0.0.1:8420/health && echo

# Ingest tracking data from the API into the warehouse
data-ingest:
    PYTHONPATH=src uv run python src/ingest_tracking.py

# --- warehouse ---

# Install dbt package dependencies
dwh-deps:
    cd {{dbt_dir}} && uv run dbt deps

# Load seeds, build all models, and run every test
dwh-build: dwh-deps
    cd {{dbt_dir}} && uv run dbt build --profiles-dir .

# Run tests only
dwh-test:
    cd {{dbt_dir}} && uv run dbt test --profiles-dir .

# Rebuild a bounded range of event days after a very late arrival, and every
# model downstream of it.
dwh-backfill start end:
    cd {{dbt_dir}} && uv run dbt run --profiles-dir . --select fct_parcel_scan+ \
        --event-time-start {{start}} --event-time-end {{end}}

# Check source freshness
dwh-freshness:
    cd {{dbt_dir}} && uv run dbt source freshness --profiles-dir .

# Generate and serve the dbt documentation site
dwh-docs:
    cd {{dbt_dir}} && uv run dbt docs generate --profiles-dir . && uv run dbt docs serve --profiles-dir .

# Rebuild the warehouse from scratch
dwh-reset:
    rm -rf ~/.dlt/pipelines/load__tracking_raw data/gls_platform.duckdb

# --- analytics ---

# Open the live operator and presentation notebook
app-notebook:
    uv run marimo edit analytics/service_performance.py

# Export the notebook to a shareable HTML file
app-export: docs-diagrams
    uv run marimo export html analytics/service_performance.py -o analytics/service_performance.html --no-include-code

# --- infrastructure (validated target configuration) ---

# Format and validate the Terraform
infra-check:
    cd infra/terraform && terraform fmt -check -recursive && terraform validate

# --- deliverable ---

# Render every formal view from Mermaid source
docs-diagrams:
    cd docs && mmdc -i architecture.mmd -o architecture.svg -b white
    cd docs && mmdc -i architecture.mmd -o architecture.png -b white -s 2
    cd docs && mmdc -i pipeline-sequence.mmd -o pipeline-sequence.svg -b white
    cd docs && mmdc -i pipeline-sequence.mmd -o pipeline-sequence.png -b white -s 2
    cd docs && mmdc -i data-model.mmd -o data-model.svg -b white
    cd docs && mmdc -i data-model.mmd -o data-model.png -b white -s 2
    cd docs && mmdc -i parcel-lifecycle.mmd -o parcel-lifecycle.svg -b white
    cd docs && mmdc -i parcel-lifecycle.mmd -o parcel-lifecycle.png -b white -s 2

# Render the data model diagram from Mermaid source
docs-erd: docs-diagrams

# Validate the DBML schema artifact
docs-dbml:
    cd docs && npx --yes dbdiagram validate data-model.dbml

# Render the written proposal to PDF
docs-pdf: docs-diagrams
    cd docs && pandoc proposal.md -o proposal.pdf --pdf-engine=typst

# --- end to end ---

# Shared execution path for the CLI and live notebook
demo-build:
    #!/usr/bin/env bash
    set -euo pipefail
    just dwh-reset
    just data-generate
    just api-start
    trap 'just api-stop' EXIT
    just data-ingest
    just dwh-build
    echo "done - warehouse built and tested"

# Full path from a clean state: build, test, and export the guided notebook
demo-all:
    just demo-build
    just app-export
    @echo "done - warehouse built and notebook exported"

# Rebuild all presentation artifacts
deliverables:
    just docs-pdf
    just app-export
