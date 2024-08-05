import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'file_download.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'google_auth.dart';
import 'file_upload.dart';
import 'notes_list.dart';
import 'note_editor.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<String> notes = [];
  GoogleSignInAccount? _googleAccount;

  @override
  void initState() {
    super.initState();
    _initGoogleAccount();
    _loadNotes();
  }

  Future<void> _initGoogleAccount() async {
    _googleAccount = await signInWithGoogle();
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notesList = prefs.getStringList('notes') ?? [];
    setState(() {
      notes = notesList;
    });

    if (_googleAccount != null) {
      try {
        final notesText = await downloadNotes(_googleAccount!);
        final notesList = notesText.split('\n');
        await prefs.setStringList('notes', notesList);
        setState(() {
          notes = notesList;
        });
      } catch (e) {
        print('Error downloading notes: $e');
      }
    }
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('notes', notes);

    if (_googleAccount != null) {
      final notesText = notes.join('\n');
      try {
        await uploadNotes(notesText, _googleAccount!);
      } catch (e) {
        print('Error uploading notes: $e');
      }
    }
  }

  Future<void> _saveNote(String noteJson, int? index) async {
    final prefs = await SharedPreferences.getInstance();
    final notesList = notes;
    if (kDebugMode) {
      print("index of note to modify: $index");
    }
    if (kDebugMode) {
      print("modified note to save: $noteJson");
    }
    if (index != null) {
      notesList[index] = noteJson;
    } else {
      notesList.add(noteJson);
    }
    if (kDebugMode) {
      print("newnotes: $notesList");
    }
    await prefs.setStringList('notes', notesList);
    setState(() {
      notes = notesList;
    });
  }

  Future<void> _deleteNote(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final notesList = notes;
    notesList.removeAt(index);
    await prefs.setStringList('notes', notesList);
    setState(() {
      notes = notesList;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      print("notes at notesscreen build : $notes");
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nana Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_alt),
            onPressed: _saveNotes,
          ),
        ],
      ),
      body: NotesList(
        notes: notes,
        onDeleteNote: _deleteNote,
        onEditNote: _saveNote,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NoteEditor(
                onSaveNote: (List<String> notesList) {
                  setState(() {
                    notes = notesList;
                  });
                },
              ),
            ),
          );
          _loadNotes();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
