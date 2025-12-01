/// <reference lib="deno.ns" />
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (_req: Request) => {
  try {
    const supabase = createClient(
      Deno.env.get("URL")!,
      Deno.env.get("SERVICE_ROLE_KEY")!
    );

    // Fetch all devices
    const { data: devices, error } = await supabase.from("devices").select("*");
    if (error) throw error;

    const now = new Date();

    for (const dev of devices ?? []) {
      const lastSeen = new Date(dev.last_seen);
      const diff = now.getTime() - lastSeen.getTime(); // ms
      const offlineThreshold = 2 * 60 * 1000; // 2 minutes

      let shouldGoOffline = diff > offlineThreshold;
      let shouldComeOnline = diff <= offlineThreshold;

      // === DEVICE GOES OFFLINE ===
      if (shouldGoOffline && dev.is_online === true) {
        console.log(`Device ${dev.device_id} is now OFFLINE.`);

        // Update row
        await supabase
          .from("devices")
          .update({ is_online: false })
          .eq("device_id", dev.device_id);

        // Insert into notifications table
        await supabase.from("notifications").insert({
          title: "Device Offline",
          message: `Your device (${dev.device_id}) has stopped sending data.`,
          event_type: "device_offline"
        });

        // Trigger push notification via send-notif
        await notifyFCM(
          "Device Offline",
          `Your device (${dev.device_id}) has stopped sending data.`,
          "device_offline",
          dev.device_id
        );
      }

      // === DEVICE COMES ONLINE AGAIN ===
      if (shouldComeOnline && dev.is_online === false) {
        console.log(`Device ${dev.device_id} is now ONLINE.`);

        // Update row
        await supabase
          .from("devices")
          .update({ is_online: true })
          .eq("device_id", dev.device_id);

        // Insert into notifications table
        await supabase.from("notifications").insert({
          title: "Device Online",
          message: `Your device (${dev.device_id}) is now back online.`,
          event_type: "device_online"
        });

        // Trigger push notification
        await notifyFCM(
          "Device Online",
          `Your device (${dev.device_id}) is now back online.`,
          "device_online",
          dev.device_id
        );
      }
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" }
    });
  }
});

// Helper to call your send-notif function
async function notifyFCM(title: string, message: string, event_type: string, device_id: string) {
  await fetch("https://dbwhtzoahlzgpiuhqvlv.supabase.co/functions/v1/send-notif", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${Deno.env.get("SERVICE_ROLE_KEY")!}`
    },
    body: JSON.stringify({ title, message, event_type, device_id })
  });
}
