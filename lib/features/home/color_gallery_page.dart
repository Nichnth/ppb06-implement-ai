import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ColorGalleryPage extends StatelessWidget {
  const ColorGalleryPage(
      {super.key, required this.userId, required this.colorName});

  final String userId;
  final String colorName;

  @override
  Widget build(BuildContext context) {
    final photosRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('colors')
        .doc(colorName)
        .collection('photos')
        .orderBy('capturedAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: Text(colorName),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: photosRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No photos for this color yet.'));
          }

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final path = data['filePath'] as String?;
              return GestureDetector(
                onTap: () {
                  // show full screen
                  if (path != null) {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Photo')),
                        body: Center(child: Image.file(File(path))),
                      ),
                    ));
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.black12,
                  ),
                  child: path != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(path),
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Center(child: Icon(Icons.broken_image)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
