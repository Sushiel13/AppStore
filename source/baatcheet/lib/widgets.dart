import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const kGreen = Color(0xFF12B886);
const kBubbleMine = Color(0xFFB2F2DB);
const kBg = Color(0xFFEDEDED);

class Avatar extends StatelessWidget {
  const Avatar({super.key, this.data, this.name = '', this.size = 44, this.group = false});
  final String? data;
  final String name;
  final double size;
  final bool group;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(size * 0.12);
    if (data != null && data!.isNotEmpty) {
      return ClipRRect(
        borderRadius: r,
        child: Image.memory(base64Decode(data!),
            width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
      );
    }
    final colors = [
      const Color(0xFF5B8FF9),
      const Color(0xFFF6BD16),
      const Color(0xFF5AD8A6),
      const Color(0xFFE86452),
      const Color(0xFF6DC8EC),
      const Color(0xFF945FB9),
    ];
    final c = colors[name.isEmpty ? 0 : name.codeUnitAt(0) % colors.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: group ? const Color(0xFFDDDDDD) : c, borderRadius: r),
      alignment: Alignment.center,
      child: group
          ? Icon(Icons.groups, color: Colors.white, size: size * 0.6)
          : Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(color: Colors.white, fontSize: size * 0.45, fontWeight: FontWeight.w600)),
    );
  }
}

String shortTime(dynamic t) {
  if (t is! Timestamp) return '';
  final d = t.toDate();
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return DateFormat('HH:mm').format(d);
  }
  final y = now.subtract(const Duration(days: 1));
  if (d.year == y.year && d.month == y.month && d.day == y.day) return 'Yesterday';
  if (now.difference(d).inDays < 7) return DateFormat('EEE').format(d);
  return DateFormat('dd/MM/yy').format(d);
}

String longTime(dynamic t) {
  if (t is! Timestamp) return '';
  final d = t.toDate();
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return DateFormat('HH:mm').format(d);
  }
  return DateFormat('d MMM, HH:mm').format(d);
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

class SectionTile extends StatelessWidget {
  const SectionTile({super.key, required this.icon, required this.title, this.color = kGreen, this.onTap, this.trailing});
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        title: Text(title),
        trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.black26),
        onTap: onTap,
      ),
    );
  }
}
