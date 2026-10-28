# Example: Robust Monitoring Pipeline

This example showcases a monitoring pipeline built from the core components of the [Rapid Deployment Platform](https://ait-rdp.github.io/) (RDP).
It ingests data from an emulated source with jitter and missing samples.
The example is kept as simple as possible on purpose, so that the behavior of the pipeline can be read off the data.

## Setup

The setup is defined via a single [Compose file](https://compose-spec.io/) ([`docker-compose.yml`](./docker-compose.yml)) and comprises the following services:

- *Dummy source*: An [InfluxDB](https://github.com/influxdata/influxdb) instance with a dedicated generator ([`dummy-source`](./dummy-source/)), which emits two synthetic signals with a period of 60 s on a 1 s grid.
  The timestamps are shifted by a random forward jitter of up to 300 ms, and each sample is dropped with a probability of 20 %.
- *Data crawler*: Polls the dummy source every 5 s and writes one Redis stream per signal ([`data-crawler/config.yml`](./data-crawler/config.yml)).
- *Regularizer*: Aligns both streams onto a common 1 s grid, imputes gaps, forecasts values that are due but still missing, and writes the result back to Redis ([`regularizer/config.yml`](./regularizer/config.yml)).
- *RedSQL*: Transfers raw and regularized streams (including a quality label for each grid point) to a [TimescaleDB](https://github.com/timescale/timescaledb/) instance initialized with the RDP Database schema ([`redsql/config.yml`](./redsql/config.yml)).
- *Grafana*: Provides a pre-configured dashboard ([`grafana`](./grafana/)) connected to the database.

*NOTE*: Please be aware that the dummy source is only part of this example and would typically not be part of a real deployment.

## Running the example

Create the environment file from the provided template and adapt it if needed (e.g., the Grafana admin credentials `GRAFANA_ADMIN_USER` and `GRAFANA_ADMIN_PASSWORD`):

```bash
cp .env.example .env
```

Start the pipeline:

```bash
docker compose up -d
```

When using Podman, `podman compose up -d` (or `podman-compose up -d`) can be used instead.

The Grafana dashboard *Sensor Data* is then available at [http://localhost:3000](http://localhost:3000).

## Startup behavior

On a fresh start, the dummy source backfills a history of 2 min (`HISTORY_MINUTES`).
After a restart, it continues after the last point already stored in the InfluxDB bucket.

The regularizer waits 5 s (`BOOTSTRAP_DELAY_SECONDS`) after its source streams have become available.
It then loads its history window (2 min) from the crawled series stored in TimescaleDB (i.e., not directly from InfluxDB) and catches the grid up to the first live tick.
Hence, imputations and forecasts can be computed right from the start.

During startup, the following log messages are expected:

- *NumPy warning about the mean of an empty slice*: This warning is printed while the regularizer assembles its history.
  The channels still finish the bootstrap, and the warning is confined to startup.
- *Dropping late sample*: This message is logged on the regularizer's first live tick for samples retrieved from the Redis stream, which have previously already been retrieved from the TimescaleDB during the history boostrap at startup.

Please be aware that neither message indicates a problem.
In steady state, late samples are no longer dropped (see [Troubleshooting](#troubleshooting)).

## What to look for

The two signals from the dummy source have been chosen such that their values at the same grid time always sum to one.
On the raw timestamps, this identity cannot be checked sample by sample, since the jitter and the dropped samples of both signals are independent.
However, after regularization both signals share the same time grid.
The dashboard shows this with the help of the following panels:

- *Crawler panels*: The raw samples, with jitter and gaps clearly visible.
- *Regularizer panels*: The filled 1 s series, labeled as *measured (snap to grid)*, *imputed*, or *forecast*.
- *Sum panels*: The sum of both signals, computed on the raw data and on the regularized data, respectively.

The most recent one or two grid points are typically labeled as *forecast* and change to *measured* on the following poll.
This late correction is a direct consequence of the configured delays of the crawler (1 s) and the regularizer (5 s), which have been chosen deliberately for the sake of illustration. In real-world deployments, these parameters should be tuned based on the desired performance guarantees.

*NOTE*: When experimenting with these settings, please be aware that several settings of the example depend on each other (see [Troubleshooting](#troubleshooting)).

## Stopping the example

```bash
docker compose down
```

To also remove the stored data, add the `-v` flag.

## Troubleshooting

### Log messages during operation

The following log messages may appear in steady state and are not errors:

- *`Queuing late measured correction`*: A measurement has arrived for a grid point that has already been forecast.
  The measurement replaces the forecast, and RedSQL overwrites the stored value (since duplicate updates are enabled).
- *`No samples found` (on both streams at the same time)*: The crawler has not published new data since the previous read of the regularizer.
  The regularizer still continues its work, and the following polls return to `Found N samples`.
  This message alone does not indicate that the source has stopped.

### Coupled settings

The settings of the example are not independent of each other.
When experimenting with different parameter values, changing only one of them may remove the effect the example is meant to show.
The following settings have to be adjusted together:

- *Jitter*: The jitter tolerance of the regularizer has to match the maximum forward jitter of the dummy source (`JITTER_MILLISECONDS`, 300 ms).
  A smaller tolerance rejects valid samples, whereas a larger one can snap a sample onto the neighboring grid point.
- *Period*: The period of the k-nearest neighbors model of the regularizer has to match the period of the dummy source (`PERIOD_SECONDS`, 60 s).
  Imputations and forecasts are only as good as this period.
- *Hold-back*: The delay of the regularizer (`REGULARIZER_LAG_TIME_SECONDS`, 5 s) is longer than the delay of the crawler (`CRAWLER_LAG_TIME_SECONDS`, 1 s).
  This difference, together with the shared polling phase, causes the forecast of the most recent one or two grid points.
- *Phase*: The polling interval (`POLLING_INTERVAL_SECONDS`, 5 s) is the same for the crawler and the regularizer, and both services wake up on the same phase.
- *Grid*: The grid interval (`INTERVAL_SECONDS`, 1 s) is used both by the dummy source and as output grid of the regularizer.
- *History*: The history window (`HISTORY_MINUTES`, 2 min) defines the backfill of the dummy source, the initial history of the crawler, and the history window of the regularizer.
