/// <reference lib="deno.ns" />

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { encode } from "https://deno.land/std@0.177.0/encoding/base64.ts";

serve(async (req) => {
  try {
    const body = await req.json();
    const { title, message, event_type, device_id } = body;

    if (!title || !message || !event_type || !device_id) {
      return jsonResponse({ error: "Missing fields" }, 400);
    }

    const supabase = createClient(
      Deno.env.get("URL")!,
      Deno.env.get("SERVICE_ROLE_KEY")!
    );

    // Insert notification record
    const { error: notifErr } = await supabase.from("notifications").insert({
      title,
      message,
      event_type,
    });

    if (notifErr) {
      console.error("DB Insert Error:", notifErr);
      return jsonResponse({ error: notifErr.message }, 500);
    }

    // Fetch tokens
    const { data: tokens, error: tokenErr } = await supabase
      .from("device_tokens")
      .select("fcm_token")
      .eq("device_id", device_id);

    if (tokenErr) {
      console.error("Token Fetch Error:", tokenErr);
      return jsonResponse({ error: tokenErr.message }, 500);
    }

    if (!tokens || tokens.length === 0) {
      console.log("No tokens found. Skipping push.");
      return jsonResponse({ success: true, message: "No registered tokens" });
    }

    // Deduplicate tokens
    const uniqueTokens = [...new Set(tokens.map((t) => t.fcm_token))];

    console.log("Unique tokens:", uniqueTokens);

    // Get OAuth access token
    const jwt = await createGoogleJwt();

    const oauthRes = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: jwt,
      }),
    });

    const oauthData = await oauthRes.json();
    const accessToken = oauthData.access_token;

    if (!accessToken) {
      console.error("OAuth Error:", oauthData);
      return jsonResponse({ error: "Failed to obtain OAuth token" }, 500);
    }

    const projectId = Deno.env.get("PROJECT_ID")!;
    const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    // Send push for each token
    for (const token of uniqueTokens) {
      const payload = {
        message: {
          token,
          notification: {
            title,
            body: message
          },
          data: {
            event_type,
            screen: "alerts"
          },
          android: {
            priority: "HIGH",
            notification: {
              channel_id: "default_channel"
            }
          }
        }
      };


      console.log("Sending to token:", token);

      const res = await fetch(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });

      console.log("FCM Status:", res.status);
      console.log("FCM Response:", await res.text());
    }

    return jsonResponse({ success: true }, 200);
  } catch (err) {
    console.error("Function error:", err);
    return jsonResponse({ error: String(err) }, 500);
  }
});

// ---------------------------------------------------
// UTILITIES
// ---------------------------------------------------

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function createGoogleJwt(): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };

  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss: Deno.env.get("CLIENT_EMAIL"),
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const encodedHeader = encode(JSON.stringify(header));
  const encodedClaims = encode(JSON.stringify(claims));
  const privateKey = Deno.env.get("PRIVATE_KEY")!.replace(/\\n/g, "\n");

  const signingInput = `${encodedHeader}.${encodedClaims}`;
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToBinary(privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput)
  );

  const encodedSignature = encode(new Uint8Array(signature));
  return `${signingInput}.${encodedSignature}`;
}

function pemToBinary(pem: string) {
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\n/g, "");

  return Uint8Array.from(atob(cleaned), (c) => c.charCodeAt(0));
}
