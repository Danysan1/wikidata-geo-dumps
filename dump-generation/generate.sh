#!/bin/bash

SOURCE_DUMP='/public/dumps/public/wikidatawiki/entities/latest-all.json.gz'
AVAILABLE_DUMP_DATE=$(date -r $SOURCE_DUMP "+%Y-%m-%d")
if [[ " $* " == *" --test "* ]] ; then
    TEST_MODE=true
    set -e
    set -x
    PLACES_JSON_PATH="./$AVAILABLE_DUMP_DATE/places.test.ndjson"
else
    TEST_MODE=false
    PLACES_JSON_PATH="./$AVAILABLE_DUMP_DATE/places.ndjson"
fi

declare -a filter_options
filter_options+=(--simplify --omit aliases --claim 'P625&~P585&~P376&~P580&~P571&~P1619&~P582&~P576&~P3999')
# P625 (coordinates) must be present
# P585 (date) or P376 (located on astronomical body) must be absent
#TODO Allow P3896 (geoshape) alternatively to P625
#TODO Check that no P582 qualifier is present in the P625 claim
#TODO Allow P580, P571, P1619 (start dates) with values in the past
#TODO Allow P582, P576, P3999 (end dates) with values in the future

mkdir -p "./$AVAILABLE_DUMP_DATE"
if [ -f $PLACES_JSON_PATH ]; then
    echo "$PLACES_JSON_PATH already exists"
elif $TEST_MODE ; then
    echo "Filtering $PLACES_JSON_PATH from only the first 10'000 lines"
    time cat $SOURCE_DUMP | gzip -d | head -10000 | cat - <(echo ']') | grep 'P625":' | wikibase-dump-filter "${curl_options[@]}" > $PLACES_JSON_PATH
else
    echo "Filtering $PLACES_JSON_PATH"
    #cat $SOURCE_DUMP | gzip -d | grep 'P625":' | wikibase-dump-filter "${curl_options[@]}" > $PLACES_JSON_PATH
    #TODO uncomment when implementation complete
fi

