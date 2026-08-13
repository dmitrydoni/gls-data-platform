# Senior Data Engineer Technical Assessment: Scalable Pipelines, Data Modeling & Analytics Infrastructure

## Overview

This assessment is designed to evaluate your capabilities as a **Senior Data Engineer** at GLS/NXT. Your submission should reflect your experience in building scalable data pipelines, managing data warehousing infrastructure, modeling data for analytics, and addressing real-world challenges such as data quality, cross-functional collaboration, and observability.

---

## Scenario

You are leading a cross-functional initiative to unify and scale GLS/NXT’s data infrastructure. The goal is to develop a data platform that supports the company’s analytics, reporting, and product teams with accurate, performant, and well-modeled data. The platform must ingest data from internal services, third-party tools (e.g., Segment), and streaming platforms (e.g., Kafka), and transform it into usable datasets within BigQuery and/or Snowflake for consumption in Looker.

---

## Tasks

### 1. Scalable Data Platform Architecture

- **Objective**: Design a high-level data infrastructure architecture that supports scalable ingestion, processing, storage, and analytics.
- **Requirements**:
    - **Component Overview**:
        - Define major components (e.g., ingestion, orchestration, transformation, warehousing, analytics).
        - Highlight technologies used (e.g., Airflow, DBT, Kafka, GCP, AWS, BigQuery, Snowflake, Looker).
    - **Infrastructure Strategy**:
        - Describe your approach to managing CI/CD, infrastructure as code, and scalability in a multi-cloud environment.
    - **Architecture Diagram**:
        - Provide a clear diagram showing your proposed data flow from source to insight.

---

### 2. Pipeline Design & Orchestration

- **Objective**: Create a batch or near-real-time data pipeline to ingest user event data and load it into a data warehouse.
- **Requirements**:
    - **Ingestion Strategy**:
        - Choose a source (e.g., Kafka, Segment, internal API) and describe how you would ingest and process this data.
    - **Orchestration & Monitoring**:
        - Outline how you would use Apache Airflow (or similar) to orchestrate the pipeline and ensure reliability with retries, alerts, and SLA monitoring.
    - **Schema Evolution & Quality**:
        - Discuss how you would handle evolving schemas and implement data validation or anomaly detection.

---

### 3. Data Modeling & Warehousing

- **Objective**: Design a model in BigQuery or Snowflake to support analytics use cases.
- **Requirements**:
    - **DBT & SQL Usage**:
        - Define a data model using DBT and describe incremental strategies, materializations, and partitioning logic.
    - **Schema Design**:
        - Propose a normalized or star schema model and justify your design decisions for performance and scalability.
    - **Data Governance**:
        - Share how you would implement data retention, access control, and compliance policies (e.g., GDPR readiness).

---

### 4. Visualization & Business Enablement

- **Objective**: Outline your approach to enabling stakeholders with well-modeled and accessible data.
- **Requirements**:
    - **Looker Integration**:
        - Explain how you would model data using LookML to support reusable, performant, and consistent metrics.
    - **Collaboration**:
        - Discuss how you would work with analysts and PMs to iterate on evolving business definitions and reporting needs.

---

### 5. Final Considerations

- **CI/CD for Data Pipelines**:
    - Describe how you would manage testing, deployment, and rollback of changes to data models and orchestration DAGs.
- **Security & Privacy**:
    - Share how you would implement role-based access, data masking, or encryption at rest/in transit.
- **Documentation**:
    - Describe your approach to maintaining up-to-date documentation for datasets, lineage, and architecture.

---

## Deliverables

1. **Architecture Diagram**:
    - A visual representation (embedded image or linked file) of your proposed data infrastructure and pipeline design.

2. **Written Proposal**:
    - A document (Markdown or PDF) that includes:
        - Overview of your architecture and technology choices.
        - Descriptions of your data flow, orchestration, and modeling logic.
        - CI/CD, security, and governance considerations.

3. **Optional Code Samples or Pseudo-code**:
    - Examples such as:
        - An Airflow DAG for a pipeline.
        - A DBT model with configurations.
        - SQL query examples for partitioning or LookML model snippets.

---

## Submission Guidelines

- **Format**:
    - Submit your architecture diagram and written proposal in Markdown or PDF.
    - Optional code snippets can be embedded or included as separate files.

- **Deadline**:
    - By [date].

- **Submission Method**:
    - Please send your completed assessment to: [glsnxt-engineering-leads@teams.gls-global.com](mailto:glsnxt-engineering-leads@teams.gls-global.com)

---

## Final Notes

This assessment is designed to highlight your ability to translate business needs into robust data systems. There is no perfect solution—we’re looking for clarity in your thought process, alignment with best practices, and effective communication of trade-offs. We encourage pragmatic solutions that balance performance, maintainability, and simplicity.

Good luck, and we look forward to reviewing your submission!
