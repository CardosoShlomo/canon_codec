## 0.1.2

- Add `Codec.email` — lenient `local@domain.tld` validation.

## 0.1.1

- `Record2Codec`/`Record3Codec`/`CsvCodec` are now public, `const`-constructible classes (the `Codec.recordN`/`Codec.csv` statics still return them), so a record/csv codec can be an enum-constant id.

## 0.1.0

- Initial release: strict const `Codec<T>` (value <-> string) with built-ins (string, integer, number, uuid, username, date, enumValues, csv, raw), `record2`/`record3` combinators, `NameableCodec` name override, and the repeated-key `list` carrier. Lifted from canon_link as the shared codec leaf.
