#!/bin/sh
set -e

./update-web-service.sh
toolforge jobs load jobs.yaml
watch -n 5 toolforge jobs list