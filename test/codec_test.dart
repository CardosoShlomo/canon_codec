import 'package:canon_codec/canon_codec.dart';
import 'package:test/test.dart';

void roundTrips<T>(Codec<T> c, String token, T value) {
  expect(c.decode(token), value);
  expect(c.encode(value), token);
}

void main() {
  group('scalars', () {
    test('string', () => roundTrips(Codec.string, 'hello', 'hello'));
    test('integer', () => roundTrips(Codec.integer, '42', 42));
    test('number', () => roundTrips(Codec.number, '1.5', 1.5));
    test('uuid lowercases', () {
      const u = '550e8400-e29b-41d4-a716-446655440000';
      expect(Codec.uuid.decode(u.toUpperCase()), u);
    });
    test('email', () => roundTrips(Codec.email, 'a@b.com', 'a@b.com'));
    test('bad email', () => expect(Codec.email.decode('nope'), isNull));
  });

  group('rejections (decode → null)', () {
    test('empty string', () => expect(Codec.string.decode(''), isNull));
    test('non-int', () => expect(Codec.integer.decode('1.5'), isNull));
    test('leading zero', () => expect(Codec.integer.decode('01'), isNull));
    test('bad uuid', () => expect(Codec.uuid.decode('nope'), isNull));
    test('non-finite double', () =>
        expect(Codec.number.decode('Infinity'), isNull));
  });

  group('record combinator', () {
    final c = Codec.record2(Codec.string, Codec.integer);
    test('round-trips', () => roundTrips(c, 'sku~7', ('sku', 7)));
    test('wrong arity → null', () => expect(c.decode('sku~7~x'), isNull));
    test('bad field → null', () => expect(c.decode('sku~nope'), isNull));

    final c3 = Codec.record3(Codec.string, Codec.integer, Codec.string);
    test('record3 round-trips', () => roundTrips(c3, 'a~1~b', ('a', 1, 'b')));
  });

  group('composite', () {
    final c = Codec.composite(Codec.string, Codec.integer);
    test('round-trips a record', () => roundTrips(c, 'sku~7', ('sku', 7)));
    test('decodes to the fields\' RUNTIME record type (typed cast works)', () {
      expect(c.decode('sku~7'), isA<(String, int)>());
    });
    test('wrong arity → null', () => expect(c.decode('sku~7~x'), isNull));
    test('bad field → null', () => expect(c.decode('sku~nope'), isNull));

    final c3 = Codec.composite(Codec.string, Codec.integer, Codec.string);
    test('3 parts', () => roundTrips(c3, 'a~1~b', ('a', 1, 'b')));

    test('16 parts (the cap) round-trips', () {
      final s = Codec.string;
      final c16 = Codec.composite(
          s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s);
      final token = List.generate(16, (i) => 'v$i').join('~');
      final decoded = c16.decode(token);
      expect(decoded, isNotNull);
      expect(c16.encode(decoded!), token);
    });
  });

  group('literal', () {
    final me = Codec.literal('me');
    test('matches verbatim', () => roundTrips(me, 'me', 'me'));
    test('rejects other', () => expect(me.decode('bob'), isNull));
    test('rejects empty', () => expect(me.decode(''), isNull));
    test('nameable (decode unchanged)',
        () => expect(me(#self).decode('me'), 'me'));
  });

  group('regex', () {
    final year = Codec.regex(r'^\d{4}$');
    test('matches', () => roundTrips(year, '2026', '2026'));
    test('rejects non-match', () => expect(year.decode('26'), isNull));
    test('nameable', () => expect(year(#yr).decode('2026'), '2026'));
  });

  group('concat (+)', () {
    final thumb = Codec.integer + Codec.literal('_thumb');
    test('suffix round-trips', () {
      expect(thumb.encode(3), '3_thumb');
      expect(thumb.decode('3_thumb'), 3);
    });
    test('rejects a token without the suffix', () =>
        expect(thumb.decode('3'), isNull));
    test('rejects a suffix over a non-decodable core', () =>
        expect(thumb.decode('x_thumb'), isNull));

    final prefixed = Codec.literal('v') + Codec.integer;
    test('prefix round-trips', () {
      expect(prefixed.encode(2), 'v2');
      expect(prefixed.decode('v2'), 2);
    });

    final wrapped = Codec.literal('img_') + Codec.uuid + Codec.literal('.webp');
    const id = '550e8400-e29b-41d4-a716-446655440000';
    test('a variable framed on both sides', () {
      expect(wrapped.encode(id), 'img_$id.webp');
      expect(wrapped.decode('img_$id.webp'), id);
    });

    test('flattens left-to-right (one variable across the chain)',
        () => expect((Codec.literal('a') + Codec.integer + Codec.literal('b'))
            .decode('a5b'), 5));

    test('two variables have no boundary → rejected', () =>
        expect(() => Codec.integer + Codec.integer, throwsA(anything)));

    test('composes into a union, thumb branch first', () {
      final u = (Codec.integer + Codec.literal('_thumb')) | Codec.integer;
      expect(u.decode('4_thumb'), 4);
      expect(u.decode('4'), 4);
    });
  });
}
