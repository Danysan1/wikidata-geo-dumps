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
filter_options+=(--simplify --omit aliases --claim 'P625&~P585&~P376&~P580&~P571&~P1619&~P582&~P576&~P3999')
# P625 (coordinates) must be present
# P585 (date) or P376 (located on astronomical body) must be absent
#TODO Allow P3896 (geoshape) alternatively to P625
#TODO Check that no P582 qualifier is present in the P625 claim
#TODO Allow P580, P571, P1619 (start dates) with values in the past
#TODO Allow P582, P576, P3999 (end dates) with values in the future

if [ -f $places_json_path ]; then
    echo "$places_json_path already exists"
elif $TEST_MODE ; then
    echo "Filtering $places_json_path from only the first 10'000 lines"
    time cat $SOURCE_DUMP | gzip -d | head -10000 | cat - <(echo ']') | grep 'P625":' | wikibase-dump-filter "${curl_options[@]}" > $places_json_path
else
    echo "Filtering $places_json_path"
    #cat $SOURCE_DUMP | gzip -d | grep 'P625":' | wikibase-dump-filter "${curl_options[@]}" > $places_json_path
    #TODO uncomment when implementation complete
fi

