// ============================================================
// CivicConnect — Edge Function: analyze-issue-photo
//
// Feature 3 (Gemini AI Integration).
// Called from the browser via sbClient.functions.invoke(...).
// The Gemini API key never touches the client — it lives only
// in this function's environment (Supabase secret).
//
// Deploy:
//   supabase functions deploy analyze-issue-photo
// Set the secret once:
//   supabase secrets set GEMINI_API_KEY=your_key_here
// ============================================================

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_MODEL = "gemini-3.5-flash";
const GEMINI_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

// Keep in sync with the `category` and `severity` CHECK constraints in issues table.
const CATEGORIES = ["roads", "water", "electric", "sanitation", "drainage", "other"];
const SEVERITIES = ["Low", "Medium", "High", "Critical"];

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    isCivicIssue: {
      type: "BOOLEAN",
      description:
        "true only if the photo shows a real civic/municipal infrastructure problem (pothole, road damage, water leak, broken streetlight/wiring, garbage/sanitation issue, blocked drain, etc). false for selfies, people, pets, food, memes, screenshots, blank/unclear images, or anything unrelated.",
    },
    category: { type: "STRING", enum: CATEGORIES },
    severity: { type: "STRING", enum: SEVERITIES },
    summary: {
      type: "STRING",
      description: "One short sentence (max ~20 words) describing what's wrong, suitable to prefill a report description.",
    },
    reason: {
      type: "STRING",
      description: "Max 12 words explaining the category/severity choice, or why it was rejected as not a civic issue.",
    },
  },
  required: ["isCivicIssue", "category", "severity", "summary", "reason"],
};

const PROMPT = `You are screening a photo submitted to a city civic-issue reporting app.

Step 1 — Decide if this photo genuinely depicts a civic/municipal infrastructure issue: damaged roads or potholes, water leaks, broken streetlights or exposed wiring, garbage/sanitation problems, blocked or overflowing drains, or another clear public-infrastructure problem.
Reject (isCivicIssue: false) selfies, portraits, people, pets/animals, food, memes, screenshots, random unrelated objects, or blank/unclear images.

Step 2 — If it IS a civic issue, classify it:
- category: one of roads, water, electric, sanitation, drainage, other
- severity: Low, Medium, High, or Critical, based on visible safety/health risk and scale
- summary: one short factual sentence describing the problem
- reason: max 12 words justifying the category/severity

If it is NOT a civic issue, still fill category as "other" and severity as "Low", and put a brief explanation of what the photo actually shows in "reason".

Respond only with the JSON object matching the given schema.`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ success: false, error: "Method not allowed" }), {
      status: 405,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  if (!GEMINI_API_KEY) {
    return new Response(
      JSON.stringify({ success: false, error: "Server is missing GEMINI_API_KEY. Set it with `supabase secrets set GEMINI_API_KEY=...`." }),
      { status: 500, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  }

  try {
    const { image, mimeType } = await req.json();

    if (!image || typeof image !== "string") {
      return new Response(JSON.stringify({ success: false, error: "Missing `image` (base64 string)." }), {
        status: 400,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    // Rough size guard on the base64 payload (~5MB decoded, base64 is ~4/3 that size).
    if (image.length > 7_000_000) {
      return new Response(JSON.stringify({ success: false, error: "Image too large. Please use a photo under 5MB." }), {
        status: 400,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const geminiRes = await fetch(`${GEMINI_URL}?key=${GEMINI_API_KEY}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [
              { text: PROMPT },
              { inlineData: { mimeType: mimeType || "image/jpeg", data: image } },
            ],
          },
        ],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: RESPONSE_SCHEMA,
          maxOutputTokens: 300,
        },
      }),
    });

    if (!geminiRes.ok) {
      const errText = await geminiRes.text();
      console.error("Gemini API error:", geminiRes.status, errText);
      return new Response(JSON.stringify({ success: false, error: "AI analysis is temporarily unavailable." }), {
        status: 502,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const data = await geminiRes.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text) {
      return new Response(JSON.stringify({ success: false, error: "AI returned an empty response." }), {
        status: 502,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch (_e) {
      return new Response(JSON.stringify({ success: false, error: "Couldn't parse AI response." }), {
        status: 502,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    // Defensive validation before trusting anything into the client's form.
    const category = CATEGORIES.includes(parsed.category) ? parsed.category : "other";
    const severity = SEVERITIES.includes(parsed.severity) ? parsed.severity : "Low";

    return new Response(
      JSON.stringify({
        success: true,
        isCivicIssue: !!parsed.isCivicIssue,
        category,
        severity,
        summary: typeof parsed.summary === "string" ? parsed.summary.slice(0, 300) : "",
        reason: typeof parsed.reason === "string" ? parsed.reason.slice(0, 150) : "",
      }),
      { headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("analyze-issue-photo error:", err);
    return new Response(JSON.stringify({ success: false, error: "Unexpected server error." }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
