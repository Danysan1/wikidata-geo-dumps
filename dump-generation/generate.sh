#!/bin/bash

#region Setup filtering & conversion
SOURCE_DUMP='/public/dumps/public/wikidatawiki/entities/latest-all.json.gz'
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
COMPLEX_GREP_FILTER='P585":|P376":|P580":|P571":|P1619":|P582":|P576":|P3999":'
COMPLEX_ITEMS_PATH="$TMP_DIR/complex.ndjson"

declare -a filter_options
filter_options+=(--omit aliases --claim 'P625&~P585&~P376&~P580&~P571&~P1619&~P582&~P576&~P3999')
# P625 (coordinates) must be present
# P585 (date) or P376 (located on astronomical body) must be absent
#TODO Allow P3896 (geoshape) alternatively to P625
#TODO Check that no P582 qualifier is present in the P625 claim
#TODO Allow P580, P571, P1619 (start dates) with values in the past
#TODO Allow P582, P576, P3999 (end dates) with values in the future

# Each output line is a single GeoJSON Feature (RFC 8142 newline-delimited).
# The filter:
#   - skips lines that are not JSON objects
#   - emits one Feature for the first P625 statement with a valid globecoordinate value
#   - rejects statements where latitude/longitude are not numbers
JQ_FILTER='
    try fromjson catch empty
    | select(type == "object")
    | . as $item
    | (.claims.P625 // [])[0]
    | select(. != null)
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
            "name:en": $item.labels.en.value,
            "description:en": $item.descriptions.en.value,
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
    time cat "$SOURCE_DUMP" | gzip -d | ($TEST_MODE && head -1000000 || cat -) | grep 'P625":' | wikibase-dump-filter "${filter_options[@]}" | jq --raw-input -c "$JQ_FILTER" >> "$PLACES_GEOJSONSEQ_PATH"
    # time cat "$SOURCE_DUMP" | gzip -d | ($TEST_MODE && head -1000000 || cat -) | grep 'P625":' | tee >(grep -E $COMPLEX_GREP_FILTER > "$COMPLEX_ITEMS_PATH") | grep -Ev $COMPLEX_GREP_FILTER | jq --raw-input -c "$JQ_FILTER" > "$PLACES_GEOJSONSEQ_PATH"
    # time "$COMPLEX_ITEMS_PATH" | wikibase-dump-filter "${filter_options[@]}" | jq --raw-input -c "$JQ_FILTER" >> "$PLACES_GEOJSONSEQ_PATH"
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
