import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'auth_screen.dart';
import 'manager_chat_thread_screen.dart';
import '../services/manager_unread_service.dart';
import '../services/vps_media_service.dart';

class ManagerNotificationsScreen extends StatelessWidget {
  const ManagerNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const AuthScreen();

    return Scaffold(
      backgroundColor: const Color(0xFF070707),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070707),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
        ),
        title: Text(
          'Notifications',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ManagerUnreadService.conversationsStream(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFD6A85A)),
            );
          }

          final docs = snapshot.data?.docs.toList() ??
              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          docs.sort((a, b) {
            final aAt = a.data()['lastMessageAt'] as Timestamp?;
            final bAt = b.data()['lastMessageAt'] as Timestamp?;
            return (bAt?.millisecondsSinceEpoch ?? 0)
                .compareTo(aAt?.millisecondsSinceEpoch ?? 0);
          });

          if (docs.isEmpty) {
            return Center(
              child: Text(
                'Aucune notification pour le moment.',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 14,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final title =
                  (data['title'] as String?)?.trim().isNotEmpty == true
                      ? (data['title'] as String).trim()
                      : 'Conversation';
              final subtitle = (data['subtitle'] as String?)?.trim() ?? '';
              final lastMessage =
                  (data['lastMessage'] as String?)?.trim() ?? '';
              final isUnread =
                  ManagerUnreadService.isConversationUnread(data, user.uid);
              final photoUrl = VpsMediaService.resolveProfileImageUrl(data);
              final photoBase64 = _readPhotoBase64(data);
              final isAvailable = data['isAvailable'] == true;

              return GestureDetector(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManagerChatThreadScreen(
                        conversationId: docs[index].id,
                        title: title,
                        subtitle: subtitle,
                        avatarBase64: photoBase64,
                        avatarUrl: photoUrl,
                        isAvailable: isAvailable,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isUnread
                          ? const Color(0x33FF3B30)
                          : const Color(0x33D6A85A),
                    ),
                  ),
                  child: Row(
                    children: [
                      _NotificationAvatar(
                        title: title,
                        photoBase64: photoBase64,
                        photoUrl: photoUrl,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (isUnread)
                                  Container(
                                    width: 9,
                                    height: 9,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFF3B30),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isUnread
                                  ? 'Nouveau message'
                                  : 'Conversation recente',
                              style: GoogleFonts.inter(
                                color: const Color(0xFFD6A85A),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (lastMessage.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                lastMessage,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.64),
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String? _readPhotoBase64(Map<String, dynamic> data) {
    for (final key in <String>[
      'photoBase64',
      'profilePhotoBase64',
      'imageBase64',
      'avatarBase64',
    ]) {
      final value = (data[key] as String?)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}

class _NotificationAvatar extends StatelessWidget {
  const _NotificationAvatar({
    required this.title,
    required this.photoBase64,
    required this.photoUrl,
  });

  final String title;
  final String? photoBase64;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    if ((photoUrl ?? '').trim().isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photoUrl!,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      );
    }
    if ((photoBase64 ?? '').trim().isNotEmpty) {
      try {
        final bytes = base64Decode(photoBase64!);
        return ClipOval(
          child: Image.memory(
            bytes,
            width: 52,
            height: 52,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {}
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFD6A85A).withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        title.isNotEmpty ? title[0].toUpperCase() : '?',
        style: GoogleFonts.inter(
          color: const Color(0xFFD6A85A),
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
