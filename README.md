# Rapid Deployment Platform – Release Bundle

The [Rapid Deployment Platform](https://ait-rdp.github.io/) (RDP) is an open-source technology stack of containerized components that together form a configurable pipeline for the robust real-time ingestion of time-series data.
It comprises dedicated components for polling-based and event-driven data acquisition, exchange of data via in-memory message streams, regularization onto a fixed time grid with explicit quality labels for imputed and forecast values, and long-term storage in a time-series database.

This repository bundles pinned versions of all RDP core components (as Git submodules) together with an example pipeline.
Development versions of the components are maintained in their separate repositories (see [Core components](#core-components)).

Further information is available at [ait-rdp.github.io](https://ait-rdp.github.io/).

## Motivation

Applications such as online monitoring, forecasting, closed-loop control, and digital twins rely on time-series data that typically arrives with irregular timing and gaps.
Handling these issues reliably requires considerable engineering effort that is unrelated to the actual application.
To this end, the RDP allows complete pipelines to be assembled from containers and configuration files, without project-specific code for standard sources.
Even though it has been developed in the context of energy research, none of its components is tied to the energy domain.

## Architecture

The ingestion pipeline comprises four layers:

- *Acquisition layer*: Dedicated connectors retrieve data from field devices and external services, either periodically (polling) or upon external events (push), and write it to Redis streams.
- *In-memory layer*: [Redis](https://redis.io/) streams act as an asynchronous message queue between all components.
  Since the streams only append data, a service that goes offline can process the backlog of missed data as soon as it reconnects (up to the retention limit).
- *Processing layer*: A generic regularizer maps raw streams onto a regular time grid, fills gaps, and writes regularized streams with quality labels back to Redis.
- *Persistence layer*: A generic synchronizer transfers selected streams to a time-series database for long-term storage.

All components are distributed as container images and are typically orchestrated with the help of [Docker Compose](https://docs.docker.com/compose/) or [Podman Compose](https://github.com/containers/podman-compose).
A deployment is fully described by a [Compose file](https://compose-spec.io/) and a set of YAML configuration files in a common format.

## Core components

The core components are included as submodules in the `src` folder:

| Component | Layer | Main functionality | Development repository |
| --- | --- | --- | --- |
| RDP Data Crawler | Acquisition | Polling-based and event-driven retrieval from devices and web services, writing to devices | [rdp-data-crawler](https://github.com/AIT-RDP/rdp-data-crawler) |
| RDP Regularizer | Processing | Alignment with a regular time grid, imputation and forecasting of missing values, quality labels | [rdp-regularizer](https://github.com/AIT-RDP/rdp-regularizer) |
| RedSQL Data Sync | Persistence | Configurable transfer of Redis streams to SQL tables | [rdp-redsql](https://github.com/AIT-RDP/rdp-redsql) |
| RDP Database | Persistence | [TimescaleDB](https://github.com/timescale/timescaledb/) schema for unitemporal and bitemporal time series, access control | [rdp-database](https://github.com/AIT-RDP/rdp-database) |

Please note that issues and contributions concerning an individual component should be directed to its development repository.

## Getting started

### Prerequisites

- A container runtime with [Compose](https://compose-spec.io/) support ([Docker](https://docs.docker.com/compose/) or [Podman](https://github.com/containers/podman-compose)).
- Git (for cloning the repository including its submodules).

### Cloning the repository

In order to retrieve the pinned versions of all core components, clone the repository with its submodules:

```bash
git clone --recurse-submodules https://github.com/AIT-RDP/rdp-release.git
```

If the repository has already been cloned without submodules, they can be retrieved with:

```bash
git submodule update --init
```

## Example

The [`example`](./example/) folder contains a monitoring pipeline that ingests data from an emulated source with jitter and missing samples.
A detailed description, including instructions for running the example, is provided in [example/README.md](./example/README.md).

## Updating the pinned versions

The versions of the core components are pinned to specific commits of their development repositories.
In order to update a component (e.g., to a new release tag), check out the corresponding version in its submodule and commit the change:

```bash
git -C src/<component> fetch --tags origin
git -C src/<component> checkout <tag>
git add src/<component>
git commit -m "Update <component> to <tag>"
```

## Citation

If you use the RDP in your research, please cite the following publications:

- M. H. Spiegel, C. Korner, D. Vettoretti, J. Kathan, M. Stefan: *Rapid deployment of capacity and energy management systems*, in: IET Conference Proceedings, Vol. 2024, No. 5, 2025, pp. 337–341. doi: [10.1049/icp.2024.2056](https://doi.org/10.1049/icp.2024.2056)
- E. Widl, M. Dünser, J. A. Groen: *A framework for digital twin runtime and lifecycle management*, in: 2026 Open Source Modelling and Simulation of Energy Systems (OSMSES), Karlsruhe, Germany, 2026, pp. 1–6. doi: [10.1109/OSMSES69376.2026.1145720](https://doi.org/10.1109/OSMSES69376.2026.1145720)

## Acknowledgements

Parts of this development have been supported by the REFORMERS project of the European Union's research and innovation programme Horizon Europe under grant agreement No. 101136211, and by the CELINE project of the European Union's research and innovation programme Horizon Europe under grant agreement No. 101160667.
