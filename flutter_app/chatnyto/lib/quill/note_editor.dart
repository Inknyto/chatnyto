// note_editor.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:shared_preferences/shared_preferences.dart';

class NoteEditor extends StatefulWidget {
  final String? initialNote;
  final int? index;
  final Function(List<String>) onSaveNote;

  const NoteEditor({
    super.key,
    this.initialNote,
    this.index,
    required this.onSaveNote,
  });

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late quill.QuillController _controller;
  bool _showToolbar = false;

  @override
  void initState() {
    super.initState();
    _controller = quill.QuillController(
      document: widget.initialNote != null
          ? quill.Document.fromJson(jsonDecode(widget.initialNote!))
          : quill.Document(),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nana Notes'),
        actions: [
          IconButton(
              icon: _showToolbar
                  ? const Icon(Icons.arrow_drop_up_sharp)
                  : const Icon(Icons.arrow_drop_down_sharp),
              onPressed: () => {
                    _showToolbar = !_showToolbar,
                    print(_showToolbar),
                    setState(() {})
                  }),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () => saveNote(context, widget.index),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showToolbar)
            quill.QuillToolbar.simple(
              configurations: quill.QuillSimpleToolbarConfigurations(
                controller: _controller,
                showBoldButton: true,
                showItalicButton: true,
                showUnderLineButton: true,
                showStrikeThrough: true,
                showColorButton: true,
                showBackgroundColorButton: true,
              ),
            ),
          Expanded(
            child: quill.QuillEditor(
              scrollController: ScrollController(),
              focusNode: FocusNode(),
              configurations: quill.QuillEditorConfigurations(
                controller: _controller,
                scrollable: true,
                autoFocus: true,
                checkBoxReadOnly: false,
                placeholder: 'Start typing...',
                expands: false,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> saveNote(BuildContext context, int? index) async {
    final prefs = await SharedPreferences.getInstance();
    if (kDebugMode) {
      print("index of note to modify: $index");
    }
    final notesList = prefs.getStringList('notes') ?? [];

    final noteJson = jsonEncode(_controller.document.toDelta().toJson());
    final noteText = _controller.document.toPlainText();
    print("plain text of saved document: $noteText");
    if (index != null) {
      notesList[index] = noteJson;
    } else {
      notesList.add(noteJson);
    }
    if (kDebugMode) {
      print("newnotes: $notesList");
    }

    if (kDebugMode) {
      print("note to be saved by the editor: $noteJson");
    }
    if (kDebugMode) {
      print("new notesList: $notesList");
    }
    await prefs.setStringList('notes', notesList);

    widget.onSaveNote(notesList);
    Navigator.pop(context);
  }
}
