

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}`;


const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    category: {
      type: "STRING",
      enum: ["roads", "water", "electric", "sanitation", "drainage", "other"],
    },
    severity: {
      type: "STRING",
      enum: ["Low", "Medium", "High", "Critical"],
    },
    summary: { type: "STRING" },
    is_civic_issue: { type: "BOOLEAN" },
    confidence: { type: "NUMBER" },
  },
  required: ["category", "severity", "summary", "is_civic_issue", "confidence"],
};

const PROMPT = `You are classifying a photo submitted to a civic issue reporting app.

If the photo does NOT show a genuine civic infrastructure problem (e.g. it's a selfie, a random object, a meme, an unrelated scene), set is_civic_issue to false. Still fill category/severity with your best guess and set confidence to reflect how sure you are that it is NOT a civic issue.

If it DOES show a civic issue, set is_civic_issue to true and classify it:
- category: one of roads (potholes/road damage), water (leaks), electric (streetlights/wiring), sanitation (garbage), drainage (blocked drains), other
- severity: Low, Medium, High, or Critical, based on visible safety risk and urgency
- summary: one short, plain sentence describing what's wrong
- confidence: a number from 0 to 1 reflecting your confidence in this classification

Return only the JSON object matching the schema, nothing else.`;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (!GEMINI_API_KEY) {
    return new Response(
      JSON.stringify({ error: "Server is missing GEMINI_API_KEY. Set it with `supabase secrets set`." }),
      { status: 500, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  try {
    const { imageBase64, mimeType } = await req.json();

    if (!imageBase64) {
      return new Response(
        JSON.stringify({ error: "No image provided" }),
        { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    const geminiRes = await fetch(GEMINI_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{
          parts: [
            { text: PROMPT },
            { inline_data: { mime_type: mimeType || "image/jpeg", data: imageBase64 } },
          ],
        }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: RESPONSE_SCHEMA,
        },
      }),
    });

    if (!geminiRes.ok) {
      const errText = await geminiRes.text();
      return new Response(
        JSON.stringify({ error: "Gemini request failed", detail: errText }),
        { status: 502, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    const geminiData = await geminiRes.json();
    const textOut = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text;

    if (!textOut) {
      return new Response(
        JSON.stringify({ error: "No response from model" }),
        { status: 502, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    let parsed;
    try {
      parsed = JSON.parse(textOut);
    } catch (_e) {
      return new Response(
        JSON.stringify({ error: "Could not parse model output", raw: textOut }),
        { status: 502, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    return new Response(JSON.stringify(parsed), {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "Unexpected error", detail: String(err) }),
      { status: 500, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }
});