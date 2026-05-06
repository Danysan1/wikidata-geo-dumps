# Wikidata JSON dump format: https://doc.wikimedia.org/Wikibase/master/php/docs_topics_json.html
# Each output line is a single GeoJSON Feature (RFC 8142 newline-delimited).
# Selection rules:
#   P625 (coordinates) must be present
#   P585 (date), P376 (located on astronomical body), P580/P571/P1619 (start dates),
#   P582/P576/P3999 (end dates) must all be absent
#TODO Allow P3896 (geoshape) alternatively to P625
#TODO Check that no P582 qualifier is present in the P625 claim
#TODO Allow P580, P571, P1619 (start dates) with values in the past
#TODO Allow P582, P576, P3999 (end dates) with values in the future

try fromjson catch empty
| select(type == "object")
| select(.claims.P625)
| select(.claims.P585 == null and .claims.P376 == null
            and .claims.P580 == null and .claims.P571 == null
            and .claims.P1619 == null and .claims.P582 == null
            and .claims.P576 == null and .claims.P3999 == null)
| . as $item
| .claims.P625[0]
| select(
    .mainsnak.snaktype == "value"
    and (.mainsnak.datavalue.value | type) == "object"
    and (.mainsnak.datavalue.value.longitude | type) == "number"
    and (.mainsnak.datavalue.value.latitude | type) == "number"
    )
| .mainsnak.datavalue.value as $coord
| {
    type: "Feature",
    properties: {
        id: $item.id,
        "name": $item.labels.mul.value,
        "name:en": $item.labels.en.value
    },
    geometry: {
        type: "Point",
        coordinates: [$coord.longitude, $coord.latitude]
    }
}