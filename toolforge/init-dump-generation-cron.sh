#!/bin/sh
set -e

./build-and-update-web-service.sh
sleep 5
toolforge jobs load jobs.yaml
#watch -n 5 toolforge jobs list
toolforge jobs logs -f wikidata-geo-dumps-test
