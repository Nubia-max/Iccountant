import 'package:firebase_auth/firebase_auth.dart';

Future<Map<String, String>> authHeaders({Map<String, String>? base}) async {
  final user = FirebaseAuth.instance.currentUser;
  final idToken = await user?.getIdToken(true); // refresh if needed
  final h = <String, String>{};
  if (base != null) h.addAll(base);
  h['Accept'] = 'application/json';
  if (idToken != null && idToken.isNotEmpty) {
    h['Authorization'] = 'Bearer $idToken';
  }
  return h;
}
