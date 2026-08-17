import 'dart:async';

import 'package:flutter/painting.dart';

import '../iam_log.dart';
import '../models/in_app_message.dart';

/// Loads a message's artwork before it is displayed.
///
/// Internal: not exported to hosts. Exists because the impression is logged the
/// moment the widget mounts, so artwork that arrives a beat later means a view
/// has been counted of something the user could not yet see — and impression
/// timing is the one number this whole module is judged on.
abstract interface class ArtworkPrefetcher {
  /// Whether [message]'s artwork is decoded and ready to paint.
  ///
  /// A message carrying no artwork is ready by definition.
  Future<bool> prefetch(GameballInAppMessage message);
}

/// Fills the same image-cache entries the widgets will read at display.
///
/// Deliberately not `precacheImage`: that needs a [BuildContext], and a sync can
/// run before the first frame on a cold start, when the navigator key has none.
/// Resolving the provider directly needs no context, and it reaches the same
/// entry — a [NetworkImage]'s cache key is its url and scale, independent of the
/// [ImageConfiguration] it was resolved against.
class ImageCacheArtworkPrefetcher implements ArtworkPrefetcher {
  ImageCacheArtworkPrefetcher({ImageProvider Function(String url)? provider})
      : _provider = provider ?? _network;

  /// Injected so tests exercise the stream plumbing without a socket.
  final ImageProvider Function(String url) _provider;

  static ImageProvider _network(String url) => NetworkImage(url);

  @override
  Future<bool> prefetch(GameballInAppMessage message) async {
    final urls = <String>[
      if (message.imageUrl != null) message.imageUrl!,
      if (message.iconUrl != null) message.iconUrl!,
    ];
    if (urls.isEmpty) return true;

    // Concurrent, not serial: a slideup's icon and image are two independent
    // fetches, and paying for them one after the other would double the delay
    // before the message can honestly be shown.
    final loaded = await Future.wait(urls.map(_load));
    return loaded.every((ok) => ok);
  }

  /// Resolves one url, completing with whether it decoded.
  Future<bool> _load(String url) {
    final done = Completer<bool>();
    final stream = _provider(url).resolve(ImageConfiguration.empty);

    // `late` and self-referencing: the listener has to remove itself, and a
    // stream that already holds the image calls back synchronously from inside
    // `addListener`, so the variable must be assigned before that line runs.
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo image, bool synchronousCall) {
        stream.removeListener(listener);
        if (!done.isCompleted) done.complete(true);
      },
      onError: (Object error, StackTrace? stack) {
        stream.removeListener(listener);
        iamLog('artwork "$url" could not be loaded ($error)');
        if (!done.isCompleted) done.complete(false);
      },
    );
    stream.addListener(listener);

    return done.future;
  }
}
