# Flockademic

## Project Summary

Flockademic is an open-source web application that visualizes the geographic growth of automated license plate reader (ALPR) surveillance infrastructure over time.

Instead of presenting another static map of camera locations, Flockademic treats the expansion of the camera network as a spatial diffusion process inspired by epidemiological visualizations. Users can move through time and watch documented cameras appear, form clusters, spread into neighboring municipalities, and increase in density.

The epidemiological terminology is explicitly a visualization and analytical metaphor. The application must not imply that cameras literally behave like pathogens or that geographic proximity proves one deployment caused another.

The initial focus is Flock Safety and other publicly documented ALPR cameras in the United States.

## Primary Goal

Answer:

> **How has publicly documented ALPR surveillance infrastructure spread geographically over time?**

The main experience should be an animated map where the user presses Play and watches documented camera locations accumulate over time.

Example:

`2021 → 2022 → 2023 → 2024 → 2025 → 2026`

New observations should visually appear while existing observations remain visible, making the expansion of the documented network immediately understandable.

## Technology Stack

Use:

* Elixir
* Phoenix
* Phoenix LiveView
* PostgreSQL
* PostGIS
* Flock for analytical/dataframe workloads where appropriate
* Parquet for large historical analytical datasets
* MapLibre GL JS for map rendering
* OpenStreetMap-compatible basemap data
* Tailwind CSS
* ExUnit

Avoid introducing React unless there is a strong technical reason. Phoenix LiveView should own application state and UI interactions wherever practical. JavaScript hooks should be used for MapLibre and animation functionality that needs direct browser control.

## Data Sources

Only use legitimately public/open datasets and document the provenance and license of every source.

### Initial Source

Start with the DeFlock/FlockHopper open-data ecosystem and its OpenStreetMap-derived ALPR dataset.

The ingestion architecture must support additional sources later without changing the core domain model.

Possible future sources include:

* OpenStreetMap
* DeFlock datasets
* EFF Atlas of Surveillance
* public procurement records
* municipal records
* publicly released Flock transparency information
* other open ALPR datasets

Never scrape authenticated/private Flock Safety or Ring systems.

## Critical Temporal Rule

Do NOT assume that the timestamp when a camera enters an open dataset is its installation date.

Store temporal provenance explicitly.

A camera should support fields such as:

```text
first_observed_at
last_observed_at
installed_at
installed_at_source
installed_at_confidence
```

`first_observed_at` means:

> Earliest date Flockademic can demonstrate that this camera existed in one of its source datasets.

`installed_at` should remain NULL unless a reliable source specifically establishes an installation/deployment date.

The default historical visualization should therefore be labeled **"First observed"** rather than **"Installed."**

This distinction must be preserved throughout the UI and analytics.

## Core Domain Model

### Camera

Suggested fields:

```text
id
source
source_id
manufacturer
operator
camera_type
latitude
longitude
geom
first_observed_at
last_observed_at
installed_at
installed_at_source
installed_at_confidence
metadata
inserted_at
updated_at
```

Use PostGIS geography/geometry types for spatial operations.

### Observation

Represents a camera appearing in a particular source snapshot.

```text
id
camera_id
source
source_record_id
observed_at
latitude
longitude
metadata
```

Observations should be immutable where practical.

### Region

Represent geographic areas such as:

```text
country
state
county
municipality
```

Suggested fields:

```text
id
type
name
fips
geom
```

### RegionSnapshot

Precomputed statistics for a region at a particular point in time.

```text
region_id
date
camera_count
new_camera_count
camera_density
growth_rate
```

These records should make historical animation and charts inexpensive.

## Data Ingestion

Create a source-adapter architecture.

Example:

```text
Flockademic.Ingest.Source
Flockademic.Ingest.OSM
Flockademic.Ingest.DeFlock
```

Each adapter should normalize external records into a common internal representation.

Pipeline:

```text
External dataset
      ↓
Source adapter
      ↓
Normalize
      ↓
Validate
      ↓
Deduplicate
      ↓
Camera / Observation records
      ↓
Spatial region assignment
      ↓
Historical snapshots
      ↓
Analytics
```

Ingestion must be idempotent.

Running the same snapshot twice must not create duplicate cameras or observations.

Preserve original source identifiers and metadata so provenance can always be reconstructed.

## Historical Dataset

The most important engineering challenge is reconstructing history.

Do not build the entire application around the assumption that a complete historical dataset already exists.

Support two modes.

### Snapshot History

Flockademic periodically downloads the current open dataset and stores a timestamped snapshot.

Over time this creates its own reliable history:

```text
2026-08-23.parquet
2026-08-24.parquet
2026-08-25.parquet
...
```

Comparing snapshots allows Flockademic to determine when a camera was first observed.

### Imported Historical Data

If historical OSM changesets, archived DeFlock datasets, public records, or other reliable sources provide earlier evidence, import those observations and update `first_observed_at`.

Never overwrite provenance.

## Map Experience

The landing page should primarily be a full-screen interactive map.

Include:

* timeline
* Play/Pause
* date display
* playback speed
* camera count
* cameras newly observed during current period
* region search
* filters
* optional heatmap/density mode

The user should be able to drag the timeline manually or press Play.

During playback:

```text
Jan 2023

      •


Jun 2023

      • •
       •


Jan 2024

    • •••
     ••• •


Jan 2025

   ••••••
  ••••••••
    •••••
```

Points should appear according to `first_observed_at`.

Do not continuously resend the entire camera dataset through LiveView during animation.

Large geographic data should be delivered using an efficient map-oriented representation such as vector tiles, PMTiles, GeoJSON subsets, or another appropriate mechanism.

## Epidemiological Metaphor

The application can use terminology inspired by epidemiology, but metrics must have precise definitions.

Potential concepts:

### Patient Zero

The earliest documented camera/observation within a selected region.

Label this:

**Earliest observed camera**

"Patient zero" can appear as secondary visual language.

### Outbreak

A period where the rate of newly observed cameras in a region increases significantly relative to its previous baseline.

The mathematical definition must be documented.

### Hotspot

A geographic region with unusually high camera density or recent growth.

### Spread

Change in geographic distribution over time.

### Saturation

A declining growth rate in a region that already has substantial camera density.

### Growth Index

Do NOT call this epidemiological `Rₜ` unless the implementation actually uses a defensible reproduction-number model.

Instead create a project-specific metric such as:

**Camera Growth Index (CGI)**

A simple initial version might use:

```text
new cameras observed during window
----------------------------------
cameras known at start of window
```

Display the exact definition in the UI.

More sophisticated spatial diffusion metrics can be added later.

## Analytics

Users should be able to select a state, county, or municipality and view:

```text
Total documented cameras
First documented observation
New observations — 30 days
New observations — 1 year
Camera density
Growth rate
Peak growth period
```

Historical charts should show cumulative camera observations over time.

Provide rankings such as:

```text
Fastest-growing counties
Fastest-growing municipalities
Highest camera density
Largest absolute increase
Newest emerging clusters
```

## Spatial Diffusion Analysis

One particularly interesting analysis should measure geographic expansion.

For each newly observed camera, calculate metrics such as:

```text
distance to nearest previously observed camera
distance to existing cluster
region of nearest previous observation
```

This allows analysis of whether documented deployment tends to:

* densify existing clusters
* expand outward from existing clusters
* appear as geographically independent clusters

Do NOT interpret nearest-neighbor relationships as causal deployment relationships.

UI language should say:

> "Nearest previously observed camera"

not:

> "This camera caused the next deployment."

## Flock / Parquet Analytics

Use Parquet as the durable analytical representation for large historical observation datasets.

Flock should be considered for operations such as:

```text
group observations by month
group observations by county
calculate cumulative counts
calculate regional growth
compare snapshots
produce ranking datasets
```

Do not force Flock into transactional workloads where PostgreSQL/PostGIS is better suited.

Broad division of responsibilities:

```text
PostgreSQL/PostGIS
    current application state
    cameras
    regions
    spatial queries
    UI-facing records

Parquet + Flock
    historical snapshots
    large aggregations
    temporal analysis
    research queries
```

## Phoenix / OTP Architecture

Use OTP where it provides genuine value rather than wrapping every domain object in a GenServer.

Potential supervised processes:

```text
Flockademic.Supervisor
│
├── Repo
├── PubSub
├── IngestSupervisor
│    ├── Source workers
│    └── Snapshot processor
│
├── AnalyticsSupervisor
│    └── Snapshot jobs
│
└── Phoenix.Endpoint
```

Newly completed ingestion runs can broadcast events such as:

```elixir
Phoenix.PubSub.broadcast(
  Flockademic.PubSub,
  "camera_updates",
  {:snapshot_complete, stats}
)
```

LiveViews can then update counters or notify MapLibre that new data is available.

## Camera Detail

Clicking a camera should show only useful, source-supported information:

```text
Manufacturer
Camera type
Operator, if known
First observed
Last observed
Installation date, if independently known
Coordinates
Data source
Source record
Temporal confidence
```

Include a provenance section explaining exactly why Flockademic believes the camera existed at that location/date.

## Region Detail

Example:

```text
Hampshire County, Massachusetts

Documented cameras        143
Earliest observation      May 2022
Added in past year         38
Growth                    +36%
Density                   0.27 / sq mi

Peak expansion:
Aug–Nov 2024
```

Include:

* cumulative growth chart
* map
* monthly new observations
* Camera Growth Index
* neighboring-region comparison

## Filters

Eventually support:

```text
Manufacturer
Camera type
Operator
Source
State
County
Municipality
Observation date
Temporal confidence
```

The MVP does not need every filter.

## Provenance

Every displayed camera must ultimately be traceable to its source.

Create a provenance model capable of answering:

```text
Where did this record come from?
When was it retrieved?
What source identifier did it have?
What did the original source claim?
Has another source corroborated it?
```

Never silently merge conflicting claims.

## Data Quality

The UI should communicate uncertainty.

Possible temporal classifications:

```text
Confirmed installation date
Documented observation date
Dataset first-seen date
Unknown
```

A dataset observation is evidence that a camera was documented by that date—not proof of when it was physically installed.

## Privacy / Responsible Use

Flockademic is intended for:

* public-interest research
* journalism
* visualization
* understanding surveillance infrastructure
* studying technology adoption and geographic diffusion

Only ingest legitimately public/open information.

Do not add:

* tools for interfering with cameras
* instructions for disabling cameras
* features specifically designed to facilitate evasion of law enforcement
* private camera feeds
* plate-search functionality
* individual vehicle/person tracking

The project analyzes infrastructure, not individuals.

## MVP

The first release should remain intentionally small.

### MVP 1

Implement:

1. Phoenix application
2. PostgreSQL + PostGIS
3. Camera schema
4. Observation schema
5. one open-data ingestion adapter
6. idempotent ingestion
7. MapLibre map
8. camera markers
9. `first_observed_at`
10. timeline control
11. animated historical playback
12. total camera counter
13. selected-region statistics

Do NOT initially implement:

* machine learning
* user accounts
* plate recognition
* individual tracking
* complicated prediction models
* dozens of data sources
* elaborate distributed architecture

Get the historical visualization working first.

## MVP Success Condition

The MVP succeeds when a user can open Flockademic, select a geographic region, press **Play**, and visually understand how the publicly documented ALPR network expanded over the available historical period.

A successful demo should look approximately like:

```text
FLOCKADEMIC

Documented ALPR expansion
United States

2019 ━━━━━━━●━━━━━━━━━━━━━━━━ 2026
             ▶

Known by this date
       14,382

New this year
       +3,417

          [ANIMATED MAP]
```

Watching the map evolve should be the project's "wow" moment.

## Development Priorities

When implementing this project, optimize in this order:

1. correctness of provenance
2. correctness of temporal interpretation
3. compelling historical map
4. ingestion reliability
5. spatial query performance
6. analytical depth
7. visual polish

Do not sacrifice data correctness to make the visualization more dramatic.

## Initial Implementation Plan

Start by creating a technical spike rather than the entire application.

### Phase 1 — Data feasibility

Download one current open ALPR dataset.

Determine:

* available fields
* source identifiers
* manufacturer coverage
* timestamp availability
* duplicate characteristics
* geographic coverage
* whether historical records can be reconstructed

Produce a short findings document before designing the final database schema.

### Phase 2 — Historical prototype

Pick one state with substantial data.

Construct the best defensible `first_observed_at` history available.

Produce:

```text
camera_id
latitude
longitude
first_observed_at
source
confidence
```

Verify that the resulting timeline actually produces a meaningful animation.

### Phase 3 — Phoenix prototype

Create:

```text
/
```

with:

* MapLibre
* camera points
* timeline slider
* play/pause
* date
* cumulative count

No elaborate UI.

### Phase 4 — Geographic analytics

Add:

* states
* counties
* municipalities
* PostGIS containment
* regional growth statistics
* cumulative growth charts

### Phase 5 — Production ingestion

Implement scheduled snapshot collection and Parquet archival so Flockademic begins producing its own reliable longitudinal dataset.
