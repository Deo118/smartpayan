Future<void> sendSupabaseNotif(
  String title,
  String message,
  String eventType,
  String deviceId,
) async {
  print(
    "[SmartPayan] sendSupabaseNotif() was called in Flutter, "
    "but notifications are now handled by the ESP32. Ignored."
  );
}
