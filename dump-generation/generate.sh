#!/bin/bash

if [[ " $* " == *" --test "* ]] ; then
    set -e
    set -x
    TEST_MODE=true
else
    TEST_MODE=false
fi
SOURCE_DUMP='/public/dumps/public/wikidatawiki/entities/latest-all.json.gz'

available_dump_date=$(date -r $SOURCE_DUMP "+%Y-%m-%d")
places_json_path="./$available_dump_date/places.ndjson"
declare -a filter_options
filter_options+=(--claim P625)
# TODO other options
if [ -f $places_json_path ]; then
    echo "$places_json_path already exists"
elif $TEST_MODE ; then
    echo "Filtering $places_json_path from only the first 10'000 lines"
    cat $SOURCE_DUMP | gzip -d | head -10000 | cat - <(echo ']') | wikibase-dump-filter "${curl_options[@]}" > $places_json_path
else
    echo "Filtering $places_json_path"
    cat $SOURCE_DUMP | gzip -d | wikibase-dump-filter "${curl_options[@]}" > $places_json_path
fi

