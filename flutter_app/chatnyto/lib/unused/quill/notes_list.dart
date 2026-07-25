import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'note_editor.dart';

class NotesList extends StatefulWidget {
  final List<String> notes;
  final Function(int) onDeleteNote;
  final Function(String, int) onEditNote;

  const NotesList({
    super.key,
    required this.notes,
    required this.onDeleteNote,
    required this.onEditNote,
  });

  @override
  State<NotesList> createState() => _NotesListState();
}

class _NotesListState extends State<NotesList> {
  late List<String> _notes;

  @override
  void initState() {
    super.initState();
    _notes = widget.notes;
    if (kDebugMode) {
      print("widget.notes at NotesList initState : ${widget.notes}");
    }
  }

  @override
  void didUpdateWidget(covariant NotesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notes != oldWidget.notes) {
      _notes = widget.notes;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) {
        // No action required here
      },
      child: ListView.builder(
        itemCount: _notes.length,
        itemBuilder: (context, index) {
          return Dismissible(
            key: Key(_notes[index]),
            direction: DismissDirection.endToStart,
            onDismissed: (direction) {
              widget.onDeleteNote(index);
            },
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16.0),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            child: ListTile(
              title: Text(
                jsonDecode(_notes[index])
                    .where((item) => item['insert'] != null)
                    .map((item) => item['insert'] as String)
                    .toList()
                    .join(" ")
                    .replaceAll('\n', ' ')
                    .substring(
                        0,
                        min<int>(
                            40,
                            (jsonDecode(_notes[index])
                                .where((item) => item['insert'] != null)
                                .map((item) => item['insert'] as String)
                                .toList()
                                .join(" ")
                                .length))),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => NoteEditor(
                      initialNote: _notes[index],
                      index: index,
                      onSaveNote: (List<String> notesList) {
                        setState(() {
                          _notes = notesList;
                        });
                      },
                    ),
                  ),
                );
              },
              onLongPress: () => shareNote(_notes[index]),
            ),
          );
        },
      ),
    );
  }
}

Future<void> shareNote(String note) async {
  await Share.share(note);
}
