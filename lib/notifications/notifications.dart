import 'package:firebase_database/firebase_database.dart';
import 'supabase_notif.dart';

void startListeningToClothesline(String deviceIdRaw) {
  final safeId = deviceIdRaw.replaceAll(':', '_');

  final dbRef = FirebaseDatabase.instance
      .ref("devices/$safeId/sensorData/state");

  print("Starting listener on devices/$safeId/sensorData/state");

  dbRef.onValue.listen((DatabaseEvent event) {
    final state = event.snapshot.value?.toString() ?? "";
    print("Clothesline state changed: $state");

    handleStateChange(state, safeId);
  });
}

void handleStateChange(String state, String deviceId) {
  String title = "Clothesline Update";
  String message = "";

  if (state == "retracted") {
    message = "Rain or low light detected. Clothesline is retracted.";
  } else if (state == "extended") {
    message = "Good weather detected. Clothesline is extended.";
  }

  if (message.isNotEmpty) {
    print("Sending notification: $message");
    sendSupabaseNotif(title, message, "clothesline_state", deviceId);
  }
}
