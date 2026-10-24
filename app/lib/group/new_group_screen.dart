import 'package:flutter/material.dart';

import '../auth/phone.dart';
import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/widgets.dart';
import '../l10n/app_localizations.dart';
import 'phone_field.dart';

/// Group name + members by phone number. Pops with the new room ID.
class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _name = TextEditingController();
  final _members = <String, String>{}; // user ID -> phone digits
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty || _members.isEmpty) return;
    setState(() => _busy = true);
    try {
      final roomId = await Deps.of(context).chat.createGroup(_name.text.trim(), _members.keys.toList());
      if (mounted) Navigator.pop(context, roomId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L10n.of(context).errUnknown)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l.newGroup)),
      floatingActionButton: FloatingActionButton(
        key: const Key('create_group'),
        tooltip: l.create,
        onPressed: _busy ? null : _create,
        child: _busy
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.check),
      ),
      body: FormWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            TextField(
              key: const Key('group_name'),
              controller: _name,
              maxLength: 100,
              buildCounter: counterNearLimit,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l.groupName),
            ),
            const SizedBox(height: 8),
            if (_members.isNotEmpty)
              SizedBox(
                key: const Key('group_members'),
                height: 96,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final MapEntry(key: id, value: digits) in _members.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 72,
                          child: Column(
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Avatar(name: '', seed: id, radius: 28),
                                  Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: Material(
                                      color: scheme.onSurfaceVariant,
                                      shape: CircleBorder(side: BorderSide(color: scheme.surface, width: 2)),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: () => setState(() => _members.remove(id)),
                                        child: Padding(
                                          padding: const EdgeInsets.all(2),
                                          child: Icon(Icons.close, size: 14, color: scheme.surface),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                formatPhone(digits),
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            PhoneLookupField(
              fieldKey: const ValueKey('group_member_phone'),
              buttonLabel: l.addMember,
              onUser: (userId, digits) async => setState(() => _members[userId] = digits),
            ),
          ],
        ),
      ),
    );
  }
}
