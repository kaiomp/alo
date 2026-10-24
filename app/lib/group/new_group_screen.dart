import 'package:flutter/material.dart';

import '../auth/phone.dart';
import '../common/deps.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(l.newGroup)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create_group'),
        onPressed: _busy ? null : _create,
        icon: const Icon(Icons.check),
        label: Text(l.create),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('group_name'),
            controller: _name,
            maxLength: 100,
            decoration: InputDecoration(labelText: l.groupName),
          ),
          PhoneLookupField(
            fieldKey: const ValueKey('group_member_phone'),
            buttonLabel: l.addMember,
            onUser: (userId, digits) async => setState(() => _members[userId] = digits),
          ),
          for (final MapEntry(key: id, value: digits) in _members.entries)
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(formatPhone(digits)),
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _members.remove(id))),
            ),
        ],
      ),
    );
  }
}
