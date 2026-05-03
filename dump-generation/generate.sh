#!/bin/bash

#region Setup GDAL to make sure it uses the custom driver in this folder
SCRIPT_DIR_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GDAL_PYTHON_DRIVER_PATH="$SCRIPT_DIR_PATH"
export GDAL_DRIVER_PATH="$SCRIPT_DIR_PATH"
export GDAL_DRIVER_PATH_ALLOWED="$SCRIPT_DIR_PATH"
export GDAL_DATA="$(gdal-config --datadir 2>/dev/null || python3 -c 'from osgeo import gdal; print(gdal.GetConfigOption("GDAL_DATA"))')"
export PYTHONSO="$(python3 -c 'import os, sysconfig; print(os.path.join(sysconfig.get_config_var("LIBDIR"), sysconfig.get_config_var("INSTSONAME")))')"
#endregion

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
    echo "Filtering $PLACES_NDJSON_PATH from only the first 10'000 lines from $SOURCE_DUMP"
    time cat $SOURCE_DUMP | gzip -d | head -10000 | cat - <(echo ']') | grep 'P625":' | wikibase-dump-filter "${curl_options[@]}" > "$PLACES_NDJSON_PATH"
else
    echo "Filtering $PLACES_NDJSON_PATH from $SOURCE_DUMP"
    exit 1 #TODO delete when implementation complete
    #time cat $SOURCE_DUMP | gzip -d | grep 'P625":' | wikibase-dump-filter "${curl_options[@]}" > "$PLACES_NDJSON_PATH"
fi
#endregion 

#region Convert to GeoJSON
if [ -f "$PLACES_GEOJSON_PATH" ]; then
    echo "$PLACES_GEOJSON_PATH already exists"
elif $TEST_MODE ; then # GeoJSON supported only on small files in test mode
    echo "Converting $PLACES_NDJSON_PATH to $PLACES_GEOJSON_PATH"
    ogr2ogr --version
    time ogr2ogr -f GeoJSON "$PLACES_GEOJSON_PATH" "$PLACES_NDJSON_PATH"
fi
#endregion

#region Convert to FlatGeoBuf
if [ -f "$PLACES_FLATGEOBUF_PATH" ]; then
    echo "$PLACES_FLATGEOBUF_PATH already exists"
else
    echo "Converting $PLACES_NDJSON_PATH to $PLACES_FLATGEOBUF_PATH"
    time ogr2ogr -f FlatGeobuf "$PLACES_FLATGEOBUF_PATH" "$PLACES_NDJSON_PATH"
fi
#endregion

#region Convert to GeoParquet
if [ -f "$PLACES_GEOPARQUET_PATH" ]; then
    echo "$PLACES_GEOPARQUET_PATH already exists"
else
    echo "Converting $PLACES_NDJSON_PATH to $PLACES_GEOPARQUET_PATH"
    time ogr2ogr -f Parquet "$PLACES_GEOPARQUET_PATH" "$PLACES_NDJSON_PATH"
fi
#endregion
