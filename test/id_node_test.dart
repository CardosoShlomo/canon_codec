import 'package:canon_codec/canon_codec.dart';
import 'package:test/test.dart';

enum _N with IdNode {
  product(Codec.string),
  author(Codec.string);

  const _N(this.codec);
  @override
  final Codec codec;
}

void main() {
  group('IdNode', () {
    test('atomic node delegates to its codec', () {
      expect(_N.author.decode('a1'), 'a1');
      expect(_N.author.encode('a1'), 'a1');
    });

    test('composite: const, and codec matches components', () {
      const review = IdNode.compose(_N.product, _N.author);
      expect(review.codec.decode('p1~a1'), ('p1', 'a1'));
      expect(review.decode('p1~a1'), ('p1', 'a1')); // the node IS its codec
    });

    test('composite decodes to the fields\' runtime record type', () {
      const review = IdNode.compose(_N.product, _N.author);
      expect(review.decode('p1~a1'), isA<(String, String)>());
    });
  });
}
