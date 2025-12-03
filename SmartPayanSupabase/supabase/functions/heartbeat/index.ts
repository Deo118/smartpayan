/// <reference lib="deno.ns" />
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req: Request) => {
  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: { "Content-Type": "application/json" } });
    }

    const body = await req.json().catch(() => ({}));
    const deviceId = body.device_id ?? body.deviceId ?? body.device;
    const mac = body.mac_address ?? body.macAddress ?? body.mac;

    if (!deviceId || typeof deviceId !== "string") {
      return new Response(JSON.stringify({ error: "Missing device_id" }), { status: 400, headers: { "Content-Type": "application/json" } });
    }

    const supabaseUrl = Deno.env.get("URL")!;
    const serviceRole = Deno.env.get("SERVICE_ROLE_KEY")!;

    const supabase = createClient(supabaseUrl, serviceRole);

    // Upsert device row
    const payload = {
      device_id: deviceId,
      mac_address: mac ?? null,
      last_seen: new Date().toISOString(),
      is_online: true
    };

    const { error } = await supabase
      .from("devices")
      .upsert(payload, { onConflict: "device_id" });

    if (error) {
      console.error("Upsert error:", error);
      return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { "Content-Type": "application/json" }});
    }

    return new Response(JSON.stringify({ success: true }), { status: 200, headers: { "Content-Type": "application/json" } });

  } catch (err) {
    console.error("Function error:", err);
    return new Response(JSON.stringify({ error: String(err) }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
