#!/bin/sh

toolforge jobs restart wikidata-geo-dumps-generate
toolforge jobs logs -f wikidata-geo-dumps-generate
