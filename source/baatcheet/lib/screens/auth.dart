import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/db.dart';
import '../widgets.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _signup = false;
  bool _busy = false;

  String _err(Object e) {
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'invalid-email' => 'That email address is not valid.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' => 'Email or password is wrong.',
        'email-already-in-use' => 'An account with this email already exists. Log in instead.',
        'weak-password' => 'Use a password of at least 6 characters.',
        'network-request-failed' => 'No internet connection.',
        _ => e.message ?? e.code,
      };
    }
    return '$e';
  }

  Future<void> _go() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    if (email.isEmpty || pass.isEmpty) return toast(context, 'Enter email and password');
    setState(() => _busy = true);
    try {
      if (_signup) {
        await Db.auth.createUserWithEmailAndPassword(email: email, password: pass);
      } else {
        await Db.auth.signInWithEmailAndPassword(email: email, password: pass);
      }
    } catch (e) {
      if (mounted) toast(context, _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (email.isEmpty) return toast(context, 'Type your email first');
    try {
      await Db.auth.sendPasswordResetEmail(email: email);
      if (mounted) toast(context, 'Password reset link sent to $email');
    } catch (e) {
      if (mounted) toast(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 60, 28, 28),
          children: [
            Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.chat_bubble, color: Colors.white, size: 46),
            ),
            const SizedBox(height: 16),
            const Center(child: Text('BaatCheet', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700))),
            const SizedBox(height: 6),
            Center(
              child: Text(_signup ? 'Create your account' : 'Log in to chat with friends and family',
                  style: const TextStyle(color: Colors.black54)),
            ),
            const SizedBox(height: 36),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
              onSubmitted: (_) => _go(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _go,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_signup ? 'Sign up' : 'Log in'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _signup = !_signup),
              child: Text(_signup ? 'Have an account? Log in' : 'New here? Create an account'),
            ),
            if (!_signup) TextButton(onPressed: _forgot, child: const Text('Forgot password?')),
          ],
        ),
      ),
    );
  }
}

/// First-time profile, also reused for editing from the Me tab.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, this.editing = false});
  final bool editing;
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final _name = TextEditingController(text: Db.me?['name'] ?? '');
  late final _id = TextEditingController(text: Db.me?['chatId'] ?? '');
  late final _about = TextEditingController(text: Db.me?['about'] ?? '');
  String? _avatar = Db.me?['avatar'];
  bool _busy = false;

  Future<void> _pickPhoto() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 256, maxHeight: 256, imageQuality: 70);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    setState(() => _avatar = Db.b64(bytes));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final id = _id.text.trim().toLowerCase();
    if (name.isEmpty) return toast(context, 'Enter your name');
    if (!RegExp(r'^[a-z][a-z0-9_]{4,19}$').hasMatch(id)) {
      return toast(context, 'ID: 5–20 letters, numbers or _, starting with a letter');
    }
    setState(() => _busy = true);
    try {
      if (await Db.chatIdTaken(id)) {
        if (mounted) toast(context, 'That ID is taken. Try another.');
        return;
      }
      await Db.saveProfile(name: name, chatId: id, about: _about.text, avatar: _avatar);
      if (!mounted) return;
      if (widget.editing) {
        Navigator.pop(context);
      } else {
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthGate()), (_) => false);
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.editing ? 'My profile' : 'Set up your profile')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: Stack(
                children: [
                  Avatar(data: _avatar, name: _name.text, size: 96),
                  const Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(radius: 14, backgroundColor: kGreen, child: Icon(Icons.camera_alt, size: 16, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _id,
            decoration: const InputDecoration(
              labelText: 'BaatCheet ID',
              helperText: 'Friends find you by this ID. Example: sushil_pune',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _about,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'About (optional)', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
