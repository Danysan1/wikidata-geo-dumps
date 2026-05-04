#!/bin/bash

# NOTE: dump-generation/gdal_Wikidata.py (the GDAL Python plugin driver) is no
# longer wired into this pipeline; we now pre-convert the wikibase-dump-filter
# NDJSON to GeoJSONSeq with jq and let ogr2ogr's native C++ drivers do the rest.
# The .py file is kept on disk as a fallback in case we ever need to revisit.

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
PLACES_NDJSON_PATH="$OUT_DUMPS_DIR/places.ndjson"
PLACES_GEOJSONSEQ_PATH="$OUT_DUMPS_DIR/places.geojsonl"
PLACES_GEOJSON_PATH="$OUT_DUMPS_DIR/places.geojson"
PLACES_FLATGEOBUF_PATH="$OUT_DUMPS_DIR/places.fgb"
PLACES_GEOPARQUET_PATH="$OUT_DUMPS_DIR/places.parquet"
#endregion

#region Filtering
declare -a filter_options
filter_options+=(--simplify --omit aliases --claim 'P625&~P585&~P376&~P580&~P571&~P1619&~P582&~P576&~P3999')
# P625 (coordinates) must be present
# P585 (date) or P376 (located on astronomical body) must be absent
#TODO Allow P3896 (geoshape) alternatively to P625
#TODO Check that no P582 qualifier is present in the P625 claim
#TODO Allow P580, P571, P1619 (start dates) with values in the past
#TODO Allow P582, P576, P3999 (end dates) with values in the future

mkdir -p "$OUT_DUMPS_DIR"
if [ -f "$PLACES_NDJSON_PATH" ]; then
    echo "$PLACES_NDJSON_PATH already exists"
elif $TEST_MODE ; then
    echo "Filtering $PLACES_NDJSON_PATH from only the first 1M lines from $SOURCE_DUMP"
    cat $SOURCE_DUMP | gzip -d | head -1000000 | cat - <(echo ']') | grep 'P625":' | wikibase-dump-filter "${filter_options[@]}" > "$PLACES_NDJSON_PATH"
else
    echo "Filtering $PLACES_NDJSON_PATH from $SOURCE_DUMP"
    exit 1 #TODO delete when implementation complete
    #cat $SOURCE_DUMP | gzip -d | grep 'P625":' | wikibase-dump-filter "${filter_options[@]}" > "$PLACES_NDJSON_PATH"
fi
#endregion

#region Convert wikibase NDJSON -> GeoJSONSeq with jq
# This intermediate format is what every downstream ogr2ogr step reads.
# Each output line is a single GeoJSON Feature (RFC 8142 newline-delimited).
# The filter mirrors the logic of the dormant gdal_Wikidata.py driver:
#   - skip lines that are not JSON objects
#   - emit one Feature per [lat, lon] pair in claims.P625
#   - reject pairs that are not [number, number] (also rejects booleans)
#   - GeoJSON expects [lon, lat] order, so we swap.
if [ -f "$PLACES_GEOJSONSEQ_PATH" ]; then
    echo "$PLACES_GEOJSONSEQ_PATH already exists"
else
    echo "Converting $PLACES_NDJSON_PATH to $PLACES_GEOJSONSEQ_PATH (GeoJSONSeq)"
    time jq --raw-input -c '
        try fromjson catch empty
        | select(type == "object")
        | . as $item
        | (.claims.P625 // [])[]
        | select(type == "array" and length == 2
                 and (.[0] | type) == "number"
                 and (.[1] | type) == "number")
        | {
            type: "Feature",
            properties: {
              id: $item.id,
              modified: $item.modified,
              label_en: $item.labels.en,
              description_en: $item.descriptions.en
            },
            geometry: {
              type: "Point",
              coordinates: [.[1], .[0]]
            }
          }
    ' "$PLACES_NDJSON_PATH" > "$PLACES_GEOJSONSEQ_PATH"
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
    echo "Converting $PLACES_GEOJSONSEQ_PATH to $PLACES_GEOPARQUET_PATH"
    time ogr2ogr -f Parquet "$PLACES_GEOPARQUET_PATH" "$PLACES_GEOJSONSEQ_PATH"
fi
#endregion
