import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/auth.dart';
import 'screens/home.dart';
import 'services/db.dart';
import 'services/notify.dart';
import 'widgets.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!FirebaseConfig.isPlaceholder) {
    await Firebase.initializeApp(options: FirebaseConfig.options);
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  }
  await Notify.init();
  runApp(const BaatCheetApp());
}

class BaatCheetApp extends StatelessWidget {
  const BaatCheetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BaatCheet',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kGreen, primary: kGreen),
        scaffoldBackgroundColor: kBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: kBg,
          foregroundColor: Colors.black87,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(color: Colors.black87, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: kGreen,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        useMaterial3: true,
      ),
      home: FirebaseConfig.isPlaceholder ? const _NotConfigured() : const AuthGate(),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'This build is not connected to a server yet.\n\nAdd google-services.json to the project and rebuild.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.data == null) return const LoginScreen();
        return FutureBuilder(
          key: ValueKey(snap.data!.uid),
          future: Db.loadMe(),
          builder: (context, me) {
            if (me.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (me.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load your profile.\n${me.error}', textAlign: TextAlign.center),
                  ),
                ),
              );
            }
            if (me.data == null) return const ProfileSetupScreen();
            return const HomeScreen();
          },
        );
      },
    );
  }
}
