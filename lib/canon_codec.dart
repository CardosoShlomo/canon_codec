/// A strict, bidirectional codec for a single string token. `decode` returns
/// null when the token is not valid for this codec — that null is what lets the
/// caller fall through (URL match fallthrough, or best-effort restore). `encode`
/// is the exact inverse for any value the codec can produce, so a value
/// round-trips to the same canonical token.
///
/// Custom codecs are const classes implementing this interface, so they compose
/// into a (const) enum constant or tree literal:
///   `class PriceCodec implements Codec<Price> { const PriceCodec(); ... }`
abstract interface class Codec<T> {
  /// Decode one already-percent-decoded token, or null if it isn't valid for T.
  T? decode(String token);

  /// Encode a value back to its token. Inverse of [decode] on valid values.
  String encode(T value);

  /// Accepts any token verbatim. A total catch-all (never null).
  static const NameableCodec<String> raw = _RawCodec();

  /// A non-empty string token (empty token → null, so a missing value fails
  /// rather than decoding to "").
  static const NameableCodec<String> string = _StringCodec();

  /// 8-4-4-4-12 hex UUID (case-insensitive), encoded lowercase.
  static const NameableCodec<String> uuid = _UuidCodec();

  /// A username/handle: letters, digits, and `_ . -` (one or more). Lenient by
  /// design — it should accept any handle a stricter app validator would.
  static const NameableCodec<String> username = _UsernameCodec();

  /// An email address. Lenient `local@domain.tld` shape (one `@`, a dotted
  /// domain, no spaces) — accept anything a stricter app validator would.
  static const NameableCodec<String> email = _EmailCodec();

  /// Base-10 integer (no leading zeros beyond "0", optional leading "-").
  static const NameableCodec<int> integer = _IntCodec();

  /// Finite double.
  static const NameableCodec<double> number = _DoubleCodec();

  /// ISO-8601 date/datetime (`DateTime.tryParse` / `toIso8601String`).
  static const NameableCodec<DateTime> date = _DateCodec();

  /// One value of an enum, matched by its `name`.
  static NameableCodec<E> enumValues<E extends Enum>(List<E> values) =>
      _EnumCodec<E>(values);

  /// Matches exactly one literal token (verbatim) — a fixed path word, e.g. in a
  /// `slot` union: `slot(Codec.literal('me') | Codec.uuid | Codec.username)`.
  /// The literal doubles as the generated branch name; override with
  /// `Codec.literal('me')(#name)`.
  static NameableCodec<String> literal(String value) => _LiteralCodec(value);

  /// Matches any token accepted by [pattern] (decoded verbatim) — a custom value
  /// shape the battery codecs don't cover.
  static NameableCodec<String> regex(String pattern) => _RegexCodec(pattern);

  /// A 2-field record, joined by [sep] (default '~'). Each field's encoded form
  /// must be sep-free for a clean round-trip; a token without exactly two parts
  /// decodes to null. `const`-constructible so it can be an enum-constant id:
  /// `product(widget, Record2Codec(Codec.string, Codec.integer))`.
  static Codec<(A, B)> record2<A, B>(Codec<A> a, Codec<B> b,
          {String sep = '~'}) =>
      Record2Codec<A, B>(a, b, sep);

  /// A 3-field record, joined by [sep] (default '~'). Same sep-free contract.
  static Codec<(A, B, C)> record3<A, B, C>(
          Codec<A> a, Codec<B> b, Codec<C> c, {String sep = '~'}) =>
      Record3Codec<A, B, C>(a, b, c, sep);

  /// A composite of 2–16 component codecs, one `~`-joined token; the value is a
  /// positional RECORD of the components' decoded values, in order. The
  /// 2-required + 14-optional signature is the arity cap (à la `Object.hash`).
  /// Not `const` ([Codec] is generic, so a const factory can't fix `T` to
  /// `Record`); the const path is [CompositeCodec] directly — or
  /// `IdNode.compose`, which is where composites live in practice.
  static Codec<Record> composite(Codec c1, Codec c2,
          [Codec? c3, Codec? c4, Codec? c5, Codec? c6, Codec? c7, Codec? c8,
          Codec? c9, Codec? c10, Codec? c11, Codec? c12, Codec? c13,
          Codec? c14, Codec? c15, Codec? c16]) =>
      CompositeCodec(c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13,
          c14, c15, c16);

  /// An ordered list of [element], carried as repeated keys (URL query/fragment
  /// only). Its `decode`/`encode` operate on the repeated-key protocol, not one
  /// token — see [ListCodec].
  static Codec<List<T>> list<T>(Codec<T> element) => ListCodec<T>(element);

  /// An ordered list of [element] in ONE token, comma-joined (`a,b,c`). A plain
  /// scalar codec — safe only when element tokens are comma-free.
  static Codec<List<T>> csv<T>(Codec<T> element) => CsvCodec<T>(element);
}

/// `a | b` — a union: either token addresses the same `T`. Decode tries the
/// branches left-to-right (strict codecs return null on a non-match, so the
/// first that accepts the token wins); encode delegates to the left branch (the
/// canonical form). The nav/link generator reads the branches structurally; this
/// runtime form lets a spec written with `|` compile and round-trip. An
/// extension, not an interface member, so existing `implements Codec` classes
/// are unaffected.
extension CodecUnion<T> on Codec<T> {
  Codec<T> operator |(Codec<T> other) => UnionCodec<T>([
        ...this is UnionCodec<T> ? (this as UnionCodec<T>).branches : [this],
        ...other is UnionCodec<T> ? other.branches : [other],
      ]);
}

/// The flattened branches of an `a | b | c` union. Decode tries them left-to-
/// right (first non-null wins); encode uses the left/canonical branch. The
/// nav/link layer reads [branches] to recover the ordered union the spec wrote.
final class UnionCodec<T> implements Codec<T> {
  const UnionCodec(this.branches);
  final List<Codec<T>> branches;
  @override
  T? decode(String token) {
    for (final b in branches) {
      final v = b.decode(token);
      if (v != null) return v;
    }
    return null;
  }

  @override
  String encode(T value) => branches.first.encode(value);
}

/// Adds `(#name)` to a codec, overriding a generated field name at the use site
/// (`slot(.uuid(#adId))`). The returned codec drops the mixin, so a name can be
/// applied at most once. Battery codecs mix this in; custom codecs may.
mixin NameableCodec<T> implements Codec<T> {
  Codec<T> call(Symbol name) => _NamedCodec<T>(this, name);
}

/// A codec wearing a field-name override. Pure runtime passthrough — the name is
/// read off the source by a generator, not used by decode/encode.
final class _NamedCodec<T> implements Codec<T> {
  const _NamedCodec(this._inner, this.name);
  final Codec<T> _inner;
  final Symbol name;
  @override
  T? decode(String token) => _inner.decode(token);
  @override
  String encode(T value) => _inner.encode(value);
}

final class _RawCodec with NameableCodec<String> {
  const _RawCodec();
  @override
  String decode(String token) => token;
  @override
  String encode(String value) => value;
}

final class _StringCodec with NameableCodec<String> {
  const _StringCodec();
  @override
  String? decode(String token) => token.isEmpty ? null : token;
  @override
  String encode(String value) => value;
}

final class _UuidCodec with NameableCodec<String> {
  const _UuidCodec();
  static final _re = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  @override
  String? decode(String token) =>
      _re.hasMatch(token) ? token.toLowerCase() : null;
  @override
  String encode(String value) => value.toLowerCase();
}

final class _UsernameCodec with NameableCodec<String> {
  const _UsernameCodec();
  static final _re = RegExp(r'^[A-Za-z0-9_.-]+$');
  @override
  String? decode(String token) => _re.hasMatch(token) ? token : null;
  @override
  String encode(String value) => value;
}

final class _EmailCodec with NameableCodec<String> {
  const _EmailCodec();
  static final _re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  @override
  String? decode(String token) => _re.hasMatch(token) ? token : null;
  @override
  String encode(String value) => value;
}

/// A fixed-token codec ([Codec.literal]). Exposed so link-tree assembly can
/// detect literal branches (e.g. to order an injected id codec after them).
abstract interface class LiteralCodec implements NameableCodec<String> {
  String get literal;
}

final class _LiteralCodec with NameableCodec<String> implements LiteralCodec {
  const _LiteralCodec(this.literal);
  @override
  final String literal;
  @override
  String? decode(String token) => token == literal ? literal : null;
  @override
  String encode(String value) => value;
}

final class _RegexCodec with NameableCodec<String> {
  _RegexCodec(String pattern) : _re = RegExp(pattern);
  final RegExp _re;
  @override
  String? decode(String token) => _re.hasMatch(token) ? token : null;
  @override
  String encode(String value) => value;
}

final class _IntCodec with NameableCodec<int> {
  const _IntCodec();
  @override
  int? decode(String token) {
    final n = int.tryParse(token);
    // Reject non-canonical forms ("+1", "01", " 1") so encode is the inverse.
    return (n != null && n.toString() == token) ? n : null;
  }

  @override
  String encode(int value) => value.toString();
}

final class _DoubleCodec with NameableCodec<double> {
  const _DoubleCodec();
  @override
  double? decode(String token) {
    final n = double.tryParse(token);
    return (n != null && n.isFinite) ? n : null;
  }

  @override
  String encode(double value) => value.toString();
}

final class _DateCodec with NameableCodec<DateTime> {
  const _DateCodec();
  @override
  DateTime? decode(String token) => DateTime.tryParse(token);
  @override
  String encode(DateTime value) => value.toIso8601String();
}

final class _EnumCodec<E extends Enum> with NameableCodec<E> {
  const _EnumCodec(this.values);
  final List<E> values;
  @override
  E? decode(String token) {
    for (final v in values) {
      if (v.name == token) return v;
    }
    return null;
  }

  @override
  String encode(E value) => value.name;
}

/// A 2-field record codec (see [Codec.record2]); `const` so it works as an
/// enum-constant id, e.g. `Record2Codec(Codec.string, Codec.integer)`.
final class Record2Codec<A, B> implements Codec<(A, B)> {
  const Record2Codec(this.a, this.b, [this.sep = '~']);
  final Codec<A> a;
  final Codec<B> b;
  final String sep;
  @override
  (A, B)? decode(String token) {
    final parts = token.split(sep);
    if (parts.length != 2) return null;
    final av = a.decode(parts[0]);
    final bv = b.decode(parts[1]);
    return (av != null && bv != null) ? (av, bv) : null;
  }

  @override
  String encode((A, B) value) =>
      '${a.encode(value.$1)}$sep${b.encode(value.$2)}';
}

/// A 3-field record codec (see [Codec.record3]); `const`-constructible.
final class Record3Codec<A, B, C> implements Codec<(A, B, C)> {
  const Record3Codec(this.a, this.b, this.c, [this.sep = '~']);
  final Codec<A> a;
  final Codec<B> b;
  final Codec<C> c;
  final String sep;
  @override
  (A, B, C)? decode(String token) {
    final parts = token.split(sep);
    if (parts.length != 3) return null;
    final av = a.decode(parts[0]);
    final bv = b.decode(parts[1]);
    final cv = c.decode(parts[2]);
    return (av != null && bv != null && cv != null) ? (av, bv, cv) : null;
  }

  @override
  String encode((A, B, C) value) =>
      '${a.encode(value.$1)}$sep${b.encode(value.$2)}$sep${c.encode(value.$3)}';
}

/// A composite codec (see [Codec.composite]); `const`-constructible. Components
/// are individual fields — a const constructor can't build a list — so the
/// signature itself caps the arity at 16. The value is a positional RECORD of
/// the components' decoded values: a record's runtime type comes from its
/// fields' runtime types, so a 2-part composite of string codecs decodes to a
/// value that IS a `(String, String)` — typed casts and structural equality
/// (repeat-collapse, prefix reuse) work as if it were declared that shape.
final class CompositeCodec implements Codec<Record> {
  const CompositeCodec(this.c1, this.c2,
      [this.c3, this.c4, this.c5, this.c6, this.c7, this.c8, this.c9, this.c10,
      this.c11, this.c12, this.c13, this.c14, this.c15, this.c16,
      this.sep = '~']);

  final Codec c1, c2;
  final Codec? c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16;
  final String sep;

  /// The component codecs, in order (optionals only trail).
  List<Codec> get codecs => [
        c1, c2,
        ?c3, ?c4, ?c5, ?c6, ?c7, ?c8, ?c9, ?c10, ?c11, ?c12, ?c13, ?c14,
        ?c15, ?c16,
      ];

  @override
  Record? decode(String token) {
    final cs = codecs;
    final parts = token.split(sep);
    if (parts.length != cs.length) return null;
    final v = <Object?>[];
    for (var i = 0; i < cs.length; i++) {
      final d = cs[i].decode(parts[i]);
      if (d == null) return null;
      v.add(d);
    }
    return switch (v.length) {
      2 => (v[0], v[1]),
      3 => (v[0], v[1], v[2]),
      4 => (v[0], v[1], v[2], v[3]),
      5 => (v[0], v[1], v[2], v[3], v[4]),
      6 => (v[0], v[1], v[2], v[3], v[4], v[5]),
      7 => (v[0], v[1], v[2], v[3], v[4], v[5], v[6]),
      8 => (v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]),
      9 => (v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8]),
      10 => (v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9]),
      11 => (v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9],
          v[10]),
      12 => (v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10],
          v[11]),
      13 => (v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10],
          v[11], v[12]),
      14 => (v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10],
          v[11], v[12], v[13]),
      15 => (v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10],
          v[11], v[12], v[13], v[14]),
      _ => (v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10],
          v[11], v[12], v[13], v[14], v[15]),
    };
  }

  @override
  String encode(Record value) {
    final vs = switch (value) {
      (Object? a, Object? b) => [a, b],
      (Object? a, Object? b, Object? c) => [a, b, c],
      (Object? a, Object? b, Object? c, Object? d) => [a, b, c, d],
      (Object? a, Object? b, Object? c, Object? d, Object? e) => [a, b, c, d, e],
      (Object? a, Object? b, Object? c, Object? d, Object? e, Object? f) => [
          a, b, c, d, e, f],
      (Object? a, Object? b, Object? c, Object? d, Object? e, Object? f,
        Object? g) => [a, b, c, d, e, f, g],
      (Object? a, Object? b, Object? c, Object? d, Object? e, Object? f,
        Object? g, Object? h) => [a, b, c, d, e, f, g, h],
      (Object? a, Object? b, Object? c, Object? d, Object? e, Object? f,
        Object? g, Object? h, Object? i) => [a, b, c, d, e, f, g, h, i],
      (Object? a, Object? b, Object? c, Object? d, Object? e, Object? f,
        Object? g, Object? h, Object? i, Object? j) => [
          a, b, c, d, e, f, g, h, i, j],
      (Object? a, Object? b, Object? c, Object? d, Object? e, Object? f,
        Object? g, Object? h, Object? i, Object? j, Object? k) => [
          a, b, c, d, e, f, g, h, i, j, k],
      (Object? a, Object? b, Object? c, Object? d, Object? e, Object? f,
        Object? g, Object? h, Object? i, Object? j, Object? k, Object? l) => [
          a, b, c, d, e, f, g, h, i, j, k, l],
      (Object? a, Object? b, Object? c, Object? d, Object? e, Object? f,
        Object? g, Object? h, Object? i, Object? j, Object? k, Object? l,
        Object? m) => [a, b, c, d, e, f, g, h, i, j, k, l, m],
      (Object? a, Object? b, Object? c, Object? d, Object? e, Object? f,
        Object? g, Object? h, Object? i, Object? j, Object? k, Object? l,
        Object? m, Object? n) => [a, b, c, d, e, f, g, h, i, j, k, l, m, n],
      (Object? a, Object? b, Object? c, Object? d, Object? e, Object? f,
        Object? g, Object? h, Object? i, Object? j, Object? k, Object? l,
        Object? m, Object? n, Object? o) => [
          a, b, c, d, e, f, g, h, i, j, k, l, m, n, o],
      (Object? a, Object? b, Object? c, Object? d, Object? e, Object? f,
        Object? g, Object? h, Object? i, Object? j, Object? k, Object? l,
        Object? m, Object? n, Object? o, Object? p) => [
          a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p],
      _ => throw ArgumentError.value(
          value, 'value', 'not a 2–16 field positional record'),
    };
    final cs = codecs;
    return [for (var i = 0; i < cs.length; i++) cs[i].encode(vs[i])].join(sep);
  }
}

/// Comma-joined list in a single token (see [Codec.csv]); `const`-constructible.
/// A normal scalar codec — no repeated-key protocol.
final class CsvCodec<T> implements Codec<List<T>> {
  const CsvCodec(this.element);
  final Codec<T> element;
  @override
  List<T>? decode(String token) {
    if (token.isEmpty) return <T>[];
    final out = <T>[];
    for (final part in token.split(',')) {
      final v = element.decode(part);
      if (v == null) return null;
      out.add(v);
    }
    return out;
  }

  @override
  String encode(List<T> value) => value.map(element.encode).join(',');
}

/// The repeated-key list carrier. Its element codec is read by URL machinery (a
/// list key decodes element-wise from repeated keys, never as one token).
final class ListCodec<T> implements Codec<List<T>> {
  const ListCodec(this.element);
  final Codec<T> element;
  @override
  List<T>? decode(String token) =>
      throw StateError('Codec.list decodes from repeated keys, not one token');
  @override
  String encode(List<T> value) =>
      throw StateError('Codec.list encodes to repeated keys, not one token');
}

/// Marks the HAND-WRITTEN enum that is an app's id-space: each row is an identity
/// carrying its [Codec] — how its key serialises in a URL. Nothing is generated;
/// the enum IS the holder. Other grammar trees (canon's `@screens`, ledger's
/// `@registries`) reference these rows by dot-shorthand and read `row.codec` to
/// encode/decode and to validate a screen `id` or a registry key against them.
///
/// Applied as `@IDs()`. There is deliberately no lowercase `const ids`: the
/// natural name for the enum is `Ids`, and generated nav code uses `ids`
/// pervasively as an identifier, so a top-level `ids`/`Ids` would shadow it.
class IDs {
  const IDs();
}

/// The contract an `@ids` enum wears: every row carries a [codec]. The node IS a
/// [Codec] (it delegates to its inner one), so a screen can bind it straight into
/// a `Codec? id` field (`id: .user`) and a registry can key by it — the SAME node
/// across both grammar trees. Generators read `node.codec` to recover the value
/// type (the node itself erases to `Codec<Object?>`).
///
/// A node may be COMPOSITE ([compose]) — an identity made of 2–16 atomic nodes.
/// A composite lets an `inherit` from a screen keyed by it match ONE component
/// by node identity (`user.inherit(adChat)` finds the `user` component).
abstract mixin class IdNode implements Codec<Object?> {
  const IdNode();

  Codec get codec;

  @override
  Object? decode(String token) => codec.decode(token);

  @override
  String encode(Object? value) => codec.encode(value);

  /// A COMPOSITE id-node from 2–16 atomic nodes:
  /// `static const IdNode adChat = .compose(ad, user);`. Const, so it can key a
  /// screen's enum-constant id; `inherit` from a screen keyed by it matches one
  /// component by node identity.
  const factory IdNode.compose(IdNode n1, IdNode n2,
      [IdNode? n3, IdNode? n4, IdNode? n5, IdNode? n6, IdNode? n7, IdNode? n8,
      IdNode? n9, IdNode? n10, IdNode? n11, IdNode? n12, IdNode? n13,
      IdNode? n14, IdNode? n15, IdNode? n16]) = CompositeId;
}

/// See [IdNode.compose]. Component nodes are individual fields — a const
/// constructor can't build a list — so the signature itself caps the arity at
/// 16 (à la `Object.hash`); generators read the `n*` fields directly.
///
/// Why 16: a composite id is a composite PRIMARY KEY, and 16 is the strictest
/// column cap a mainstream database enforces on one (MySQL/InnoDB and SQL
/// Server key columns; PostgreSQL and Oracle allow 32) — so canon is never
/// more restrictive than a production database, while anything past ~4 is
/// already a modeling smell.
class CompositeId with IdNode {
  const CompositeId(this.n1, this.n2,
      [this.n3, this.n4, this.n5, this.n6, this.n7, this.n8, this.n9, this.n10,
      this.n11, this.n12, this.n13, this.n14, this.n15, this.n16]);

  final IdNode n1, n2;
  final IdNode? n3, n4, n5, n6, n7, n8, n9, n10, n11, n12, n13, n14, n15, n16;

  @override
  Codec get codec => Codec.composite(
      n1.codec, n2.codec,
      n3?.codec, n4?.codec, n5?.codec, n6?.codec, n7?.codec, n8?.codec,
      n9?.codec, n10?.codec, n11?.codec, n12?.codec, n13?.codec, n14?.codec,
      n15?.codec, n16?.codec);
}
