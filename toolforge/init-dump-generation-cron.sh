#!/bin/sh

toolforge jobs run generate-dump \
    --command ./dump-generation/generate.sh \
    --image node20 \
    --schedule "@daily" \
    --timeout 3600 \
    --retry 2

toolforge jobs run test-generate-dump \
    --command ./dump-generation/generate.sh --test \
    --image node20 \
    --timeout 3600
