// Supabase Edge Function: sync_ollama_models
// Syncs Ollama model inventory from Contabo server to Supabase

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "https://olhtxibbyhucxcmhzblq.supabase.co"
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_KEY") || ""
const OLLAMA_URL = Deno.env.get("OLLAMA_URL") || "http://169.58.68.183:11434"

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
        "Access-Control-Allow-Headers": "Authorization, apikey, Content-Type",
      },
    })
  }

  if (req.method === "GET") {
    return new Response(
      JSON.stringify({ status: "ok", service: "ollama-sync", timestamp: new Date().toISOString() }),
      { headers: { "Content-Type": "application/json" } }
    )
  }

  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 })
  }

  try {
    // Fetch models from Ollama on Contabo
    const ollamaRes = await fetch(`${OLLAMA_URL}/api/tags`)
    if (!ollamaRes.ok) throw new Error(`Ollama responded with ${ollamaRes.status}`)
    const models = await ollamaRes.json()

    // Upsert models into Supabase
    const upsertRes = await fetch(`${SUPABASE_URL}/rest/v1/ollama_models`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
        "apikey": SUPABASE_SERVICE_KEY,
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates",
      },
      body: JSON.stringify(models.models || []),
    })

    return new Response(
      JSON.stringify({ synced: models.models?.length || 0, status: upsertRes.status }),
      { headers: { "Content-Type": "application/json" } }
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    )
  }
})
