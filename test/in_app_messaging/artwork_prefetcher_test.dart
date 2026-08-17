import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/artwork_prefetcher.dart';

/// An [ImageProvider] whose outcome the test decides.
///
/// A real [NetworkImage] would need a socket; this exercises the same
/// [ImageStream] plumbing the prefetcher actually listens to, which is the part
/// worth testing.
class FakeImageProvider extends ImageProvider<FakeImageProvider> {
  FakeImageProvider(this.url, this.result);

  final String url;
  final Completer<ImageInfo> result;

  @override
  Future<FakeImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<FakeImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    FakeImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(result.future);
  }

  @override
  bool operator ==(Object other) =>
      other is FakeImageProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

GameballInAppMessage message({String? imageUrl, String? iconUrl}) {
  return GameballInAppMessage(
    id: 'msg',
    type: GameballMessageType.modal,
    body: 'body',
    imageUrl: imageUrl,
    iconUrl: iconUrl,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image decoded;

  setUpAll(() async {
    decoded = await createTestImage(width: 4, height: 4);
  });

  setUp(() {
    // The image cache is global. A url resolved by an earlier test would
    // complete synchronously here and hide whatever this one is asserting.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  test('a message carrying no artwork is ready without resolving anything',
      () async {
    var resolved = 0;
    final prefetcher = ImageCacheArtworkPrefetcher(
      provider: (url) {
        resolved++;
        return FakeImageProvider(url, Completer<ImageInfo>());
      },
    );

    final ready = await prefetcher.prefetch(message());

    expect(ready, isTrue);
    expect(resolved, 0, reason: 'nothing to fetch');
  });

  test('reports ready once the artwork has decoded', () async {
    final arrival = Completer<ImageInfo>();
    final prefetcher = ImageCacheArtworkPrefetcher(
      provider: (url) => FakeImageProvider(url, arrival),
    );

    final ready = prefetcher.prefetch(message(imageUrl: 'a.png'));
    arrival.complete(ImageInfo(image: decoded));

    expect(await ready, isTrue);
  });

  test('reports not ready when the artwork fails to load', () async {
    final arrival = Completer<ImageInfo>();
    final prefetcher = ImageCacheArtworkPrefetcher(
      provider: (url) => FakeImageProvider(url, arrival),
    );

    final ready = prefetcher.prefetch(message(imageUrl: 'gone.png'));
    arrival.completeError(StateError('404'));

    expect(await ready, isFalse);
  });

  test('waits for the icon as well as the image', () async {
    final arrivals = <String, Completer<ImageInfo>>{};
    final prefetcher = ImageCacheArtworkPrefetcher(
      provider: (url) => FakeImageProvider(
        url,
        arrivals.putIfAbsent(url, Completer<ImageInfo>.new),
      ),
    );

    final ready = prefetcher.prefetch(
      message(imageUrl: 'art.png', iconUrl: 'icon.png'),
    );
    arrivals['art.png']!.complete(ImageInfo(image: decoded));
    await pumpEventQueue();

    expect(arrivals.keys, containsAll(<String>['art.png', 'icon.png']));

    arrivals['icon.png']!.complete(ImageInfo(image: decoded));

    expect(await ready, isTrue);
  });

  test('one failed url makes the whole message not ready', () async {
    final arrivals = <String, Completer<ImageInfo>>{};
    final prefetcher = ImageCacheArtworkPrefetcher(
      provider: (url) => FakeImageProvider(
        url,
        arrivals.putIfAbsent(url, Completer<ImageInfo>.new),
      ),
    );

    final ready = prefetcher.prefetch(
      message(imageUrl: 'art.png', iconUrl: 'icon.png'),
    );
    arrivals['art.png']!.complete(ImageInfo(image: decoded));
    arrivals['icon.png']!.completeError(StateError('404'));

    expect(await ready, isFalse);
  });
}
