import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'deps.dart';

/// Round avatar: the picture when there is one, else the first letter.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.mxc, this.radius = 22, this.group = false});

  final String name;
  final Uri? mxc;
  final double radius;
  final bool group;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      child: group || name.isEmpty
          ? Icon(group ? Icons.group : Icons.person, size: radius)
          : Text(name.characters.first.toUpperCase(), style: TextStyle(fontSize: radius * 0.8)),
    );
    final mxc = this.mxc;
    if (mxc == null) return fallback;
    return FutureBuilder<Uint8List?>(
      future: Deps.of(context).chat.thumbnail(mxc, size: (radius * 4).round()),
      builder: (context, snap) =>
          snap.data == null ? fallback : CircleAvatar(radius: radius, backgroundImage: MemoryImage(snap.data!)),
    );
  }
}
