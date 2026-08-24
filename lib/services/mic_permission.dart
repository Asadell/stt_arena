import 'package:permission_handler/permission_handler.dart';

/// Cek izin mikrofon secara eksplisit sebelum memanggil engine mana pun,
/// supaya behavior kedua engine seragam (Engine A mengandalkan dialog OS
/// saat initialize(), Engine B punya requestPermissions() sendiri).
class MicPermission {
  static Future<String?> ensureGranted() async {
    var status = await Permission.microphone.status;
    if (status.isDenied) {
      status = await Permission.microphone.request();
    }
    if (status.isPermanentlyDenied) {
      return 'Izin mikrofon diblokir permanen. Buka Settings > Apps > stt_arena > Permissions.';
    }
    if (!status.isGranted) {
      return 'Izin mikrofon ditolak.';
    }
    return null;
  }
}
