import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/manager_unread_service.dart';

class UnreadMessagesNavItem extends StatefulWidget {
  const UnreadMessagesNavItem({
    super.key,
    required this.isActive,
    required this.onTap,
    this.activeColor = const Color(0xFFD6A85A),
    this.inactiveColor = const Color(0xA6FFFFFF),
    this.dotColor = const Color(0xFFFF3B30),
    this.icon = LucideIcons.messageCircle,
    this.label = 'Messages',
    this.activeSize = 22,
    this.inactiveSize = 20,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.fontSize = 12,
    this.activeFontWeight = FontWeight.w600,
    this.inactiveFontWeight = FontWeight.w500,
  });

  final bool isActive;
  final VoidCallback? onTap;
  final Color activeColor;
  final Color inactiveColor;
  final Color dotColor;
  final IconData icon;
  final String label;
  final double activeSize;
  final double inactiveSize;
  final EdgeInsets padding;
  final double fontSize;
  final FontWeight activeFontWeight;
  final FontWeight inactiveFontWeight;

  @override
  State<UnreadMessagesNavItem> createState() => _UnreadMessagesNavItemState();
}

class _UnreadMessagesNavItemState extends State<UnreadMessagesNavItem> {
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive ? widget.activeColor : widget.inactiveColor;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: widget.padding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              initialData: FirebaseAuth.instance.currentUser,
              builder: (context, snapshot) {
                final uid = _uid;
                if (uid.isEmpty) {
                  return Icon(
                    widget.icon,
                    color: color,
                    size: widget.isActive
                        ? widget.activeSize
                        : widget.inactiveSize,
                  );
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: ManagerUnreadService.conversationsStream(uid),
                  builder: (context, unreadSnapshot) {
                    if (unreadSnapshot.hasError) {
                      return Icon(
                        widget.icon,
                        color: color,
                        size: widget.isActive
                            ? widget.activeSize
                            : widget.inactiveSize,
                      );
                    }
                    final hasUnread = unreadSnapshot.hasData &&
                        ManagerUnreadService.snapshotHasUnread(
                          unreadSnapshot.data!,
                          uid,
                        );
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          widget.icon,
                          color: color,
                          size: widget.isActive
                              ? widget.activeSize
                              : widget.inactiveSize,
                        ),
                        if (hasUnread)
                          Positioned(
                            top: -3,
                            right: -4,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: widget.dotColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF111111),
                                  width: 1.2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 3),
            Text(
              widget.label,
              style: GoogleFonts.inter(
                color: color,
                fontSize: widget.fontSize,
                fontWeight: widget.isActive
                    ? widget.activeFontWeight
                    : widget.inactiveFontWeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UnreadMessagesDot extends StatefulWidget {
  const UnreadMessagesDot({
    super.key,
    this.size = 9,
    this.color = const Color(0xFFFF3B30),
    this.borderColor = const Color(0xFF070707),
  });

  final double size;
  final Color color;
  final Color borderColor;

  @override
  State<UnreadMessagesDot> createState() => _UnreadMessagesDotState();
}

class _UnreadMessagesDotState extends State<UnreadMessagesDot> {
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        final uid = _uid;
        if (uid.isEmpty) return const SizedBox.shrink();
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: ManagerUnreadService.conversationsStream(uid),
          builder: (context, unreadSnapshot) {
            if (unreadSnapshot.hasError) {
              return const SizedBox.shrink();
            }
            final hasUnread = unreadSnapshot.hasData &&
                ManagerUnreadService.snapshotHasUnread(
                  unreadSnapshot.data!,
                  uid,
                );
            if (!hasUnread) return const SizedBox.shrink();
            return Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                border: Border.all(color: widget.borderColor, width: 1),
              ),
            );
          },
        );
      },
    );
  }
}
