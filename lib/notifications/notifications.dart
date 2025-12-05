import 'package:firebase_database/firebase_database.dart';

void startListeningToClothesline(String deviceIdRaw) {
  final safeId = deviceIdRaw.replaceAll(':', '_');

  final dbRef = FirebaseDatabase.instance
      .ref("devices/$safeId/sensorData/state");

  print("Starting listener on devices/$safeId/sensorData/state");

  dbRef.onValue.listen((DatabaseEvent event) {
    final state = event.snapshot.value?.toString() ?? "";
    print("Clothesline state changed: $state");

    // Flutter no longer sends notifications.
    // ESP32 must call Supabase Edge Function directly.
    handleStateChange(state, safeId);
  });
}

void handleStateChange(String state, String deviceId) {
  // Flutter should ONLY update local UI.
  // No notifications are sent from the app anymore.

  print("State changed (UI only): $state");
}
