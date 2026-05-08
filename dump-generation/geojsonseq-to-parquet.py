#!/usr/bin/env python3
"""Stream GeoJSONSeq to GeoParquet in fixed-size batches to keep memory bounded."""

import json
import sys
import pyarrow as pa
import pyarrow.parquet as pq
from shapely.geometry import shape

INPUT = sys.argv[1]
OUTPUT = sys.argv[2]
BATCH_SIZE = int(sys.argv[3]) if len(sys.argv) > 3 else 100_000

_GEO_METADATA = json.dumps({
    "version": "1.0.0",
    "primary_column": "geometry",
    "columns": {
        "geometry": {
            "encoding": "WKB",
            "geometry_types": ["Point"],
            "crs": {
                "$schema": "https://proj.org/schemas/v0.4/projjson.schema.json",
                "type": "GeographicCRS",
                "name": "WGS 84 longitude-latitude",
                "datum": {
                    "type": "GeodeticReferenceFrame",
                    "name": "World Geodetic System 1984",
                    "ellipsoid": {
                        "name": "WGS 84",
                        "semi_major_axis": 6378137,
                        "inverse_flattening": 298.257223563,
                    },
                },
                "coordinate_system": {
                    "subtype": "ellipsoidal",
                    "axis": [
                        {"name": "Geodetic longitude", "abbreviation": "Lon", "direction": "east", "unit": "degree"},
                        {"name": "Geodetic latitude", "abbreviation": "Lat", "direction": "north", "unit": "degree"},
                    ],
                },
                "id": {"authority": "OGC", "code": "CRS84"},
            },
        }
    },
}).encode()

_SCHEMA = pa.schema(
    [
        pa.field("id", pa.string()),
        pa.field("name", pa.string()),
        pa.field("name:en", pa.string()),
        pa.field("commons", pa.string()),
        pa.field("geometry", pa.binary()),
    ]
).with_metadata({"geo": _GEO_METADATA})


def _make_table(rows):
    ids, names, names_en, commons_list, geoms = [], [], [], [], []
    for r in rows:
        props = r.get("properties") or {}
        ids.append(props.get("id"))
        names.append(props.get("name"))
        names_en.append(props.get("name:en"))
        commons_list.append(props.get("commons"))
        geom = r.get("geometry")
        geoms.append(shape(geom).wkb if geom else None)
    return pa.table(
        {
            "id": pa.array(ids, type=pa.string()),
            "name": pa.array(names, type=pa.string()),
            "name:en": pa.array(names_en, type=pa.string()),
            "commons": pa.array(commons_list, type=pa.string()),
            "geometry": pa.array(geoms, type=pa.binary()),
        },
        schema=_SCHEMA,
    )


batch = []
with pq.ParquetWriter(OUTPUT, _SCHEMA) as writer:
    with open(INPUT) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                batch.append(json.loads(line))
            except json.JSONDecodeError:
                continue
            if len(batch) >= BATCH_SIZE:
                writer.write_table(_make_table(batch))
                batch.clear()
    if batch:
        writer.write_table(_make_table(batch))
