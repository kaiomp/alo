import 'package:flutter/material.dart';

/// An image by address: `data:` URIs (a photo just picked) from memory,
/// anything else from the network. Shows a soft placeholder while loading.
class NetImage extends StatelessWidget {
  const NetImage(this.uri, {super.key, this.fit = BoxFit.cover});
  final Uri uri;
  final BoxFit fit;

  static ImageProvider provider(Uri uri) {
    final data = uri.data;
    return data != null ? MemoryImage(data.contentAsBytes()) : NetworkImage(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHigh);
    return Image(
      image: provider(uri),
      fit: fit,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) => sync
          ? child
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              // Passthrough: the image keeps the box it was given (cover).
              layoutBuilder: (current, previous) => Stack(fit: StackFit.passthrough, children: [...previous, ?current]),
              child: frame == null ? placeholder : child,
            ),
      errorBuilder: (context, _, _) => placeholder,
    );
  }
}
