import 'package:http/http.dart' as http;
import 'dart:convert';

Future<void> sendSupabaseNotif(String title, String message, String eventType, String deviceId) async {
  final url = Uri.parse(
      'https://dbwhtzoahlzgpiuhqvlv.supabase.co/functions/v1/send-notif');

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRid2h0em9haGx6Z3BpdWhxdmx2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ0NzM5ODYsImV4cCI6MjA4MDA0OTk4Nn0.Ny81j8nYmPteq6apMqIsJAHaNT2erIkXPNBDe7UCvP8',   
    },
    body: jsonEncode({
      'title': title,
      'message': message,
      'event_type': eventType,
      'device_id': deviceId,
    }),
  );

  print("Supabase response: ${response.statusCode}");
  print("Supabase body: ${response.body}");
}
