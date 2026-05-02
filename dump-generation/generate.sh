#!/bin/bash

GDAL_DRIVER_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GDAL_DRIVER_PATH

SOURCE_DUMP='/public/dumps/public/wikidatawiki/entities/latest-all.json.gz'
AVAILABLE_DUMP_DATE=$(date -r $SOURCE_DUMP "+%Y-%m-%d")
if [[ " $* " == *" --test "* ]] ; then
    TEST_MODE=true
    set -e
    set -x
    OUT_DUMPS_DIR="$TOOL_DATA_DIR/$AVAILABLE_DUMP_DATE-test"
else
    TEST_MODE=false
    OUT_DUMPS_DIR="$TOOL_DATA_DIR/$AVAILABLE_DUMP_DATE"
fi
PLACES_NDJSON_PATH="$OUT_DUMPS_DIR/places.ndjson"
PLACES_GEOJSON_PATH="$OUT_DUMPS_DIR/places.geojson"
PLACES_FLATGEOBUF_PATH="$OUT_DUMPS_DIR/places.fgb"

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
    echo "Filtering $PLACES_NDJSON_PATH from only the first 10'000 lines from $SOURCE_DUMP"
    time cat $SOURCE_DUMP | gzip -d | head -10000 | cat - <(echo ']') | grep 'P625":' | wikibase-dump-filter "${curl_options[@]}" > $PLACES_NDJSON_PATH
else
    echo "Filtering $PLACES_NDJSON_PATH from $SOURCE_DUMP"
    exit 1 #TODO delete when implementation complete
    #time cat $SOURCE_DUMP | gzip -d | grep 'P625":' | wikibase-dump-filter "${curl_options[@]}" > $PLACES_NDJSON_PATH
fi

if [ -f "$PLACES_GEOJSON_PATH" ]; then
    echo "$PLACES_GEOJSON_PATH already exists"
else
    echo "Converting $PLACES_NDJSON_PATH to $PLACES_GEOJSON_PATH"
    time ogr2ogr -f GeoJSON "$PLACES_GEOJSON_PATH" "$PLACES_NDJSON_PATH"
fi

#TODO Convert geojson to FlatGeobuf

