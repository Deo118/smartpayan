/// <reference lib="deno.ns" />
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (_req: Request) => {
  try {
    const supabase = createClient(
      Deno.env.get("URL")!,
      Deno.env.get("SERVICE_ROLE_KEY")!
    );

    const { data: devices, error } = await supabase
      .from("devices")
      .select("*");

    if (error) throw error;

    const now = new Date();
    const offlineThreshold = 45 * 1000;

    for (const dev of devices ?? []) {

      const deviceName = dev.name || dev.device_id;
      const lastSeen = new Date(dev.last_seen);
      const diff = now.getTime() - lastSeen.getTime();

      const shouldGoOffline = diff > offlineThreshold;

      if (shouldGoOffline && dev.is_online === true) {

        console.log("CRON OFFLINE TRIGGERED:", {
          device_id: dev.device_id,
          device_name: deviceName,
          last_seen: dev.last_seen,
          diff_ms: diff
        });

        await supabase
          .from("devices")
          .update({ is_online: false })
          .eq("device_id", dev.device_id);

        const offlineMessage = `Your device ${deviceName} has stopped sending data.`;

        await notifyFCM(
          "Device Offline",
          offlineMessage,
          "device_offline",
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

async function notifyFCM(title: string, message: string, event_type: string, device_id: string) {
  await fetch("https://dbwhtzoahlzgpiuhqvlv.supabase.co/functions/v1/send-notif", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${Deno.env.get("SERVICE_ROLE_KEY")!}`,
    },
    body: JSON.stringify({ title, message, event_type, device_id })
  });
}

