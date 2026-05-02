#!/bin/sh

toolforge jobs run generate-wikidata-geo-dumps \
    --command ./dump-generation/generate.sh \
    --image node20 \
    --schedule "@daily" \
    --timeout 7200 \
    --retry 2

toolforge jobs run wikidata-geo-dumps-test \
    --command ./dump-generation/generate.sh --test \
    --image node20 \
    --timeout 600
