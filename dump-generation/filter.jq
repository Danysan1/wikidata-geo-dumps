# Wikidata JSON dump format: https://doc.wikimedia.org/Wikibase/master/php/docs_topics_json.html
# Each output line is a single GeoJSON Feature (RFC 8142 newline-delimited).
# Selection rules:
#   P625 (coordinates) must be present and without a P582 (end date) qualifier
#   P585 (date), P376 (located on astronomical body), P580/P571/P1619 (start dates), P582/P576/P3999 (end dates) must all be absent at the claim level
#TODO Allow P580, P571, P1619 (start dates) with values in the past
#TODO Allow P582, P576, P3999 (end dates) with values in the future

# Wikidata JSON dump is a JSON array: lines look like `{...},` (trailing comma)
# Strip the trailing comma so fromjson succeeds
rtrimstr(",")
| try fromjson catch empty
| select(type == "object")
| . as $item
| .claims as $c
| select($c.P625
            and $c.P571 == null and $c.P585 == null
            and $c.P580 == null and $c.P582 == null
            and $c.P576 == null and $c.P1619 == null
            and $c.P3999 == null and $c.P376 == null)
| (first(
    $c.P625[]
    | select(.qualifiers.P582 == null and .mainsnak.snaktype == "value")
    | .mainsnak.datavalue.value
    | select(type == "object"
        and (.longitude | type) == "number"
        and (.latitude | type) == "number")
    ) // empty) as $coord
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