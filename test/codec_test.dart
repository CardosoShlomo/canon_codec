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
    test('round-trips', () => roundTrips(c, 'ad~7', ('ad', 7)));
    test('wrong arity → null', () => expect(c.decode('ad~7~x'), isNull));
    test('bad field → null', () => expect(c.decode('ad~nope'), isNull));

    final c3 = Codec.record3(Codec.string, Codec.integer, Codec.string);
    test('record3 round-trips', () => roundTrips(c3, 'a~1~b', ('a', 1, 'b')));
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
}
