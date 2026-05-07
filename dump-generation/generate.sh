#!/bin/bash

#region Configs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# TMP_DIR=$(mktemp -d)
#endregion

#region Filter and convert to GeoJSONSeq
mkdir -p "$OUT_DUMPS_DIR"
if [ -s "$PLACES_GEOJSONSEQ_PATH" ]; then
    echo "$PLACES_GEOJSONSEQ_PATH already exists"
else
    if [ -f "$PLACES_GEOJSONSEQ_PATH" ]; then
        echo "$PLACES_GEOJSONSEQ_PATH exists but is empty, deleting and re-creating it"
        rm "$PLACES_GEOJSONSEQ_PATH"
    fi

    echo "Filtering $PLACES_GEOJSONSEQ_PATH from $SOURCE_DUMP"
    # In TEST_MODE we get only a subset of the source dump, after grep it's around 189k lines / 3GB
    # It's hard to know the size of the uncompressed full dump, surely 150+ GB, probably after grep around 300GB
    # Filter passed via file because parallel invokes the command through a shell, which would otherwise interpret the | metacharacters in the inline filter as pipes.
    time pigz -dc "$SOURCE_DUMP" \
        | if $TEST_MODE; then head -1000000; else cat; fi \
        | grep -F 'P625":[{"m' \
        | grep -Fv 'P585":[{"m' \
        | parallel --pipe --block 10M -j 2 --line-buffer jq --raw-input -c -f "$SCRIPT_DIR/filter.jq" \
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

#region Generate dumps index
# Lists every dump folder under dist/dumps/ (excluding *-test) and the files inside,
# so dist/dumps/index.html can render a static index page at /dumps/.
DUMPS_INDEX_PATH="$TOOL_DATA_DIR/dist/dumps/index.json"
echo "Generating $DUMPS_INDEX_PATH"
python3 "$SCRIPT_DIR/generate-index.py" "$TOOL_DATA_DIR/dist/dumps" > "$DUMPS_INDEX_PATH"
#endregion
