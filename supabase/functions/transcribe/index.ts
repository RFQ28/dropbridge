// ============================================================
//  DropBridge — transcribe
//
//  Turns a shared voice note into text, and pulls the captions
//  off a YouTube link. Runs on Supabase so the Groq API key
//  stays on the server — it is never shipped to the browser.
//
//  Deploy:  supabase functions deploy transcribe
//  Secret:  supabase secrets set GROQ_API_KEY=...
// ============================================================
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const GROQ_URL = "https://api.groq.com/openai/v1/audio/transcriptions";
const GROQ_MODEL = "whisper-large-v3-turbo";
const MAX_BYTES = 24 * 1024 * 1024; // Groq caps uploads at 25MB

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

// Accepts any of the usual YouTube link shapes.
function youtubeId(url: string): string | null {
  const m = url.match(
    /(?:youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|shorts\/|live\/)|youtu\.be\/)([\w-]{11})/,
  );
  return m ? m[1] : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) return json({ error: "Sign in first." }, 401);

  // Act as the caller, so the invite allowlist and storage rules
  // apply here exactly like they do everywhere else.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return json({ error: "Sign in first." }, 401);

  const { data: allowed } = await supabase.rpc("is_allowed");
  if (!allowed) return json({ error: "This account isn't on the invite list." }, 403);

  let body: { storage_path?: string; youtube?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Expected a JSON body." }, 400);
  }

  // ---------- YouTube: captions already exist, just fetch them ----------
  if (body.youtube) {
    const id = youtubeId(body.youtube);
    if (!id) return json({ error: "That doesn't look like a YouTube link." }, 400);
    try {
      const r = await fetch(`https://youtube-transcript.ai/transcript/${id}.txt`);
      if (!r.ok) {
        return json({
          error: r.status === 404
            ? "No captions available for that video."
            : `Transcript service returned ${r.status}.`,
        }, 502);
      }
      const text = (await r.text()).trim();
      if (!text) return json({ error: "No captions available for that video." }, 502);
      return json({ text, source: "youtube", video_id: id });
    } catch (e) {
      return json({ error: `Couldn't reach the transcript service: ${e}` }, 502);
    }
  }

  // ---------- Voice note: run the audio through Groq's Whisper ----------
  if (!body.storage_path) {
    return json({ error: "Provide either storage_path or youtube." }, 400);
  }

  const groqKey = Deno.env.get("GROQ_API_KEY");
  if (!groqKey) {
    return json({ error: "GROQ_API_KEY isn't set on this project." }, 500);
  }

  const { data: file, error: dlErr } = await supabase
    .storage.from("shared").download(body.storage_path);
  if (dlErr || !file) {
    return json({ error: `Couldn't read that file: ${dlErr?.message ?? "not found"}` }, 404);
  }
  if (file.size > MAX_BYTES) {
    return json({
      error: `That recording is ${(file.size / 1024 / 1024).toFixed(1)}MB; the limit is 24MB.`,
    }, 413);
  }

  const form = new FormData();
  form.append("file", file, body.storage_path.split("/").pop() || "audio");
  form.append("model", GROQ_MODEL);
  form.append("response_format", "json");

  const r = await fetch(GROQ_URL, {
    method: "POST",
    headers: { Authorization: `Bearer ${groqKey}` },
    body: form,
  });

  if (!r.ok) {
    const detail = await r.text();
    return json({ error: `Transcription failed (${r.status}): ${detail.slice(0, 300)}` }, 502);
  }

  const out = await r.json();
  const text = (out.text ?? "").trim();
  return json({ text: text || "(no speech detected)", source: "groq", model: GROQ_MODEL });
});
