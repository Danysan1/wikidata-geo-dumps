#!/bin/bash

#region Configs
SOURCE_DUMP='/public/dumps/public/wikidatawiki/entities/latest-all.json.gz'
LANGUAGES=en # TODO use
PROPERTIES=P31 # TODO use
#endregion

#region Setup
if [ ! -f "$SOURCE_DUMP" ]; then
    echo "Source dump missing: $SOURCE_DUMP"
    exit 1
fi

AVAILABLE_DUMP_DATE=$(date -r $SOURCE_DUMP "+%Y-%m-%d")
if [[ " $* " == *" --test "* ]] ; then
    TEST_MODE=true
    set -e
    set -x
    OUT_DUMPS_DIR="$TOOL_DATA_DIR/dist/dumps/$AVAILABLE_DUMP_DATE-test"
else
    TEST_MODE=false
    OUT_DUMPS_DIR="$TOOL_DATA_DIR/dist/dumps/$AVAILABLE_DUMP_DATE"
fi
PLACES_GEOJSONSEQ_PATH="$OUT_DUMPS_DIR/places.geojsonl"
PLACES_FLATGEOBUF_PATH="$OUT_DUMPS_DIR/places.fgb"
PLACES_GEOPARQUET_PATH="$OUT_DUMPS_DIR/places.parquet"

TMP_DIR=$(mktemp -d)
#endregion

#region Filter and convert to GeoJSONSeq
# Wikidata JSON dump format: https://doc.wikimedia.org/Wikibase/master/php/docs_topics_json.html
# Each output line is a single GeoJSON Feature (RFC 8142 newline-delimited).
# Selection rules:
#   P625 (coordinates) must be present
#   P585 (date), P376 (located on astronomical body), P580/P571/P1619 (start dates),
#   P582/P576/P3999 (end dates) must all be absent
#TODO Allow P3896 (geoshape) alternatively to P625
#TODO Check that no P582 qualifier is present in the P625 claim
#TODO Allow P580, P571, P1619 (start dates) with values in the past
#TODO Allow P582, P576, P3999 (end dates) with values in the future
JQ_FILTER='
    try fromjson catch empty
    | select(type == "object")
    | select(.claims.P625)
    | select(.claims.P585 == null and .claims.P376 == null
             and .claims.P580 == null and .claims.P571 == null
             and .claims.P1619 == null and .claims.P582 == null
             and .claims.P576 == null and .claims.P3999 == null)
    | . as $item
    | .claims.P625[0]
    | select(
        .mainsnak.snaktype == "value"
        and (.mainsnak.datavalue.value | type) == "object"
        and (.mainsnak.datavalue.value.longitude | type) == "number"
        and (.mainsnak.datavalue.value.latitude | type) == "number"
      )
    | .mainsnak.datavalue.value as $coord
    | {
        type: "Feature",
        properties: {
            id: $item.id,
            "name": $item.labels.mul.value,
            "name:en": $item.labels.en.value
        },
        geometry: {
            type: "Point",
            coordinates: [$coord.longitude, $coord.latitude]
        }
    }
'

mkdir -p "$OUT_DUMPS_DIR"
if [ -f "$PLACES_GEOJSONSEQ_PATH" ]; then
    echo "$PLACES_GEOJSONSEQ_PATH already exists"
else
    echo "Filtering $PLACES_GEOJSONSEQ_PATH from $SOURCE_DUMP"
    # In TEST_MODE we get only a subset of the source dump, after grep it's around 189k lines / 3GB
    # It's hard to know the size of the uncompressed full dump, surely 150+ GB, probably after grep around 300GB
    time pigz -dc "$SOURCE_DUMP" \
        | ($TEST_MODE && head -1000000 || cat -) \
        | grep 'P625":' \
        | parallel --pipe --round-robin --block 500M -j 2 --line-buffer jq --raw-input -c "$JQ_FILTER" \
        > "$PLACES_GEOJSONSEQ_PATH"
fi
#endregion

#region Convert to FlatGeoBuf
if [ -f "$PLACES_FLATGEOBUF_PATH" ]; then
    echo "$PLACES_FLATGEOBUF_PATH already exists"
else
    echo "Converting $PLACES_GEOJSONSEQ_PATH to $PLACES_FLATGEOBUF_PATH"
    time ogr2ogr -f FlatGeobuf "$PLACES_FLATGEOBUF_PATH" "$PLACES_GEOJSONSEQ_PATH"
fi
#endregion

#region Convert to GeoParquet
if [ -f "$PLACES_GEOPARQUET_PATH" ]; then
    echo "$PLACES_GEOPARQUET_PATH already exists"
else
    echo "Converting $PLACES_FLATGEOBUF_PATH to $PLACES_GEOPARQUET_PATH"
    #time ogr2ogr -f Parquet "$PLACES_GEOPARQUET_PATH" "$PLACES_FLATGEOBUF_PATH" #! Requires conda-forge and libgdal-arrow-parquet which aren't available in Toolforge
    time python3 - <<EOF
import geopandas as gpd
gpd.read_file("$PLACES_FLATGEOBUF_PATH", driver="FlatGeobuf").to_parquet("$PLACES_GEOPARQUET_PATH")
EOF
fi
#endregion

echo 'Filtering & conversion completed'
