#!/bin/sh

toolforge jobs run generate-dump \
    --command ./dump-generation/generate.sh \
    --image node20 \
    --schedule "@daily" \
    --timeout 3600 \
    --retry 1
