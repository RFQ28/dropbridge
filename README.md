# DropBridge (hosted)

A private shared space for text, code, docs, images and audio — reachable
from your phone and both laptops through one URL. Invite-only: only the
emails you allow can sign in. Built on Supabase (auth + database + file
storage), frontend is a single HTML file with no build step.

Files auto-sort into tabs: **Text · Code · Docs · Images · Audio · Other**,
and everything is searchable by name, contents, or who sent it. Drop a voice
note and it comes back as text you can copy (optional — see below).

## Try it instantly — no setup required

Until you paste in Supabase keys, `index.html` runs in **Demo Mode**: it
loads straight into the app with sample data, entirely in your browser
(nothing is sent anywhere, nothing persists beyond `localStorage`). Just
open the file, or serve the folder locally:

```
python -m http.server 8743
```

then visit `http://localhost:8743/`. Use "Reset sample data" in the top bar
to start over. This is only for previewing the UI on one device — Demo Mode
does not sync between devices; follow the steps below for that.

---

## What you'll do (about 10 minutes, one time)

1. Create the database + storage in Supabase (paste one SQL file).
2. Add the invited emails.
3. Paste two keys into `index.html`.
4. Open it — or host it online so it's reachable anywhere.

---

## Step 1 — Set up Supabase

1. Go to your Supabase project (or create one at supabase.com — free tier is fine).
2. Left sidebar → **SQL Editor** → **New query**.
3. Open `supabase/setup.sql`, copy everything, paste it in, click **Run**.
   - Before running, change the sample line
     `('you@example.com')` to your own email, or just add emails later
     in Step 2.

This creates the `items` table, the `shared` storage bucket, the
invite allowlist, the security rules that keep it private, and turns on
**Realtime** so a shared item shows up on every device the instant it's sent
(no refresh, no waiting).

> Already ran an older version of this SQL? Just re-run the whole file — every
> statement is safe to run again. Two things it fixes:
> - realtime: `alter publication supabase_realtime add table public.items;`
> - sending/uploading failing with *"new row violates row-level security
>   policy"*. The security rules need to check the invite allowlist, but a
>   rule's sub-query runs as the signed-in user, who can't read that locked
>   table — so the check silently failed and blocked everyone. It now goes
>   through the `is_allowed()` helper instead, which can read it safely.

## Step 2 — Invite people

Add every email that's allowed to sign in:

- Sidebar → **Table Editor** → `allowed_emails` table → **Insert row** →
  type the email → Save.
- Do this for yourself and each trusted person.

Anyone whose email isn't in this table is blocked from creating an account,
even if they have the link.

## Step 3 — Plug in your keys

1. Sidebar → **Project Settings** → **API**.
2. Copy the **Project URL** and the **anon public** key.
3. Open `index.html`, find the CONFIG block near the top of the `<script>`:

   ```js
   const SUPABASE_URL  = "PASTE_YOUR_SUPABASE_URL";
   const SUPABASE_ANON = "PASTE_YOUR_SUPABASE_ANON_KEY";
   ```

   Paste your two values between the quotes. Save.

> The anon key is safe to ship in the page — your data is protected by the
> row-level security rules from the SQL file, not by hiding the key.

## Step 4 — Open it / put it online

**Test locally first:** just double-click `index.html`. Create your account
(the email must be on the allowlist), sign in, try sending text and a file.

**To reach it from your phone and anywhere, host it** (pick one — all free):

- **Netlify Drop** (easiest): go to app.netlify.com/drop and drag the
  `index.html` file (or the whole folder) onto the page. You get a public
  URL instantly.
- **Vercel:** import the folder, deploy. Static, no config.
- **GitHub Pages:** push the folder to a repo, enable Pages.
- **Supabase Storage:** you can also drop the HTML in a public bucket.

Then open that URL on your phone, your Mac, your Windows laptop — sign in,
same shared space everywhere.

---

## Optional — voice notes and YouTube links as text

Drop a voice note and it comes back as text you can copy straight into a
chat or an agent. Paste a YouTube link into the composer and it saves the
video's transcript instead of a bare URL. Everything else works without
this; skip it if you don't need it.

Transcription runs through a small Supabase function so the API key stays
on the server — **never put the key in `index.html`**, that file is public.

**1. Get a free Groq key** — sign up at [console.groq.com](https://console.groq.com),
create an API key. Groq hosts Whisper and has a free tier.

**2. Install the Supabase CLI** (once): see
[the install guide](https://supabase.com/docs/guides/local-development).

**3. Deploy the function and set the key:**

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set GROQ_API_KEY=your_groq_key_here
supabase functions deploy transcribe
```

Your project ref is the string in your dashboard URL:
`supabase.com/dashboard/project/<THIS_PART>`.

That's it — drop an `.m4a`/`.mp3`/voice note and the transcript appears
underneath it with a **Copy transcript** button. Transcripts are searchable
from the top bar too, so you can find a voice note by something said in it.

Notes:
- Audio files are capped at 24MB (Groq's limit).
- YouTube captions come from a free third-party endpoint — it only works on
  videos that *have* captions, and it's rate-limited for casual use.

---

## A note on the sign-up email confirmation

By default Supabase may email a confirmation link on sign-up. Two options:

- Leave it on (more secure) — each invited person clicks the link once.
- Turn it off for convenience: Supabase → **Authentication** → **Providers**
  → Email → turn off "Confirm email". Then accounts work immediately.

Since it's already invite-only via the allowlist, turning confirmation off
is a reasonable convenience trade-off for a small trusted group.

---

## How you'll actually use it

- **Text or code:** type/paste, pick Text or Code, hit Send. Appears on
  every signed-in device instantly; tap Copy on the other end.
- **Files:** drag onto the drop zone or tap "choose a file" (on phone this
  opens your files/photos). Any type works. Images show a preview.
- **Tabs** filter by type so you're not scrolling through everything.
- You can remove your own items; the file is deleted from storage too.

---

## Want me to take it further?

Easy add-ons if you find you need them: shareable per-file links for people
*not* invited, expiring items, a "sent by me vs everyone" filter, dark/light
toggle, or a proper deploy to your own domain. Just ask.

(Realtime sync is already built in — items appear on every device the moment
they're shared.)
