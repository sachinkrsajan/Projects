# Feature 3 — Deploying the Gemini Vision Edge Function

The AI photo analysis now runs server-side (Supabase Edge Function), not from
the browser — so your Gemini key is never exposed in the page source.

## 1. Get a Gemini API key
Go to https://aistudio.google.com/apikey → Create API key. Copy it.

## 2. Install the Supabase CLI (if you don't have it)
```
npm install -g supabase
```

## 3. Log in and link your project
```
supabase login
supabase link --project-ref svbqmdgasstznlflohyz
```
(That project ref is the one already in your `civicconnect.html` — the part
before `.supabase.co` in `SUPABASE_URL`.)

## 4. Copy the function into your project
Put the `supabase/functions/analyze-issue-photo/index.ts` file (included in
this delivery) into your project at the same relative path:
```
your-project/
  supabase/
    functions/
      analyze-issue-photo/
        index.ts
```

## 5. Set your Gemini key as a secret (never in client code)
```
supabase secrets set GEMINI_API_KEY=your_gemini_key_here
```

## 6. Deploy
```
supabase functions deploy analyze-issue-photo
```

That's it — no extra config needed. The function is called with your app's
existing anon key (Supabase does this automatically via
`sbClient.functions.invoke`), so it inherits your project's default JWT
verification — no `--no-verify-jwt` flag required.

## Test it
1. Open `civicconnect.html`, sign in, go to **Report an issue**.
2. Upload a photo of something like a pothole → click **Analyze photo**.
3. You should see the category dropdown and severity radio auto-fill within
   a couple seconds, plus a one-line summary you can insert into the
   description.
4. Try a photo of something unrelated (e.g. a selfie or food) — it should
   still respond, but flag "may not show a clear civic issue." (Full
   hard-rejection of non-civic photos is Feature 5, next in your list.)

## If something goes wrong
- **"Server is missing GEMINI_API_KEY"** → you skipped step 5, or deployed
  before setting the secret. Re-run step 5, then step 6 again.
- **CORS error in browser console** → make sure you deployed the exact
  `index.ts` provided; it sets `Access-Control-Allow-Origin: *`.
- **"Analysis unavailable right now"** in the UI → open the Supabase
  dashboard → Edge Functions → analyze-issue-photo → Logs, to see the real
  error (bad key, quota, etc).
