import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import 'color_gallery_page.dart';
import 'live_camera_page.dart';

class HomePage extends StatefulWidget {
  const HomePage(
      {super.key, required this.fullName, required this.authService});

  final String? fullName;
  final AuthService authService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class ColorItem {
  final String name;
  final String hex;

  ColorItem(this.name, this.hex);
}

class _HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<ColorItem> _colors = [];

  @override
  void initState() {
    super.initState();
    _loadColorsFromFirestore();
  }

  Future<void> _loadColorsFromFirestore() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final colRef =
        _firestore.collection('users').doc(user.uid).collection('colors');
    final snapshot = await colRef.get();
    setState(() {
      _colors = snapshot.docs.map((d) {
        final data = d.data();
        final name = data['name'] as String? ?? d.id;
        final hex = data['hex'] as String? ?? '#999999';
        return ColorItem(name, hex);
      }).toList();
    });
  }

  Future<void> _saveDetectedColor(
      String colorName, String hex, String filePath) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final colorDoc = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('colors')
        .doc(colorName);
    await colorDoc.set({
      'name': colorName,
      'hex': hex,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // add photo entry
    final photos = colorDoc.collection('photos');
    await photos.add({
      'filePath': filePath,
      'capturedAt': FieldValue.serverTimestamp(),
    });

    await _loadColorsFromFirestore();
  }

  Future<void> _openCamera() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveCameraPage(onColorDetected: _saveDetectedColor),
      ),
    );

    if (!mounted) return;
    await _loadColorsFromFirestore();
  }

  @override
  Widget build(BuildContext context) {
    final firstName =
        (widget.fullName ?? '').split(' ').where((s) => s.isNotEmpty).toList();
    final displayName = firstName.isNotEmpty ? firstName.first : '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('ColorCam'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await widget.authService.signOut();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome, ${displayName.isNotEmpty ? displayName : 'User'}!',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                "Colors you've encountered",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _colors.isEmpty
                    ? Center(
                        child: Text(
                          'No color cards yet.\\nTake a photo and we will detect colors.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      )
                    : GridView.builder(
                        itemCount: _colors.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.9,
                        ),
                        itemBuilder: (context, index) {
                          final c = _colors[index];
                          return GestureDetector(
                            onTap: () {
                              final user = _auth.currentUser;
                              if (user != null) {
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => ColorGalleryPage(
                                    userId: user.uid,
                                    colorName: c.name,
                                  ),
                                ));
                              }
                            },
                            child: Column(
                              children: [
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Color(int.parse(
                                          'FF${c.hex.replaceAll('#', '')}',
                                          radix: 16)),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.black12),
                                    ),
                                    margin: const EdgeInsets.only(bottom: 8),
                                  ),
                                ),
                                Text(c.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              Center(
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28)),
                    ),
                    onPressed: _openCamera,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Explore more colors'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
