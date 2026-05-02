#!/bin/sh

toolforge build start https://gitlab.wikimedia.org/toolforge-repos/wikidata-geo-dumps.git
toolforge build show
#toolforge webservice buildservice start --mount=none 
toolforge webservice buildservice restart
