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
  **whole folder** onto the page (not just `index.html` — the icons,
  `manifest.webmanifest` and `sw.js` need to come along for the phone
  install to work). You get a public URL instantly.
- **Vercel:** import the folder, deploy. Static, no config.
- **GitHub Pages:** push the folder to a repo, enable Pages.
- **Supabase Storage:** you can also drop the HTML in a public bucket.

Then open that URL on your phone, your Mac, your Windows laptop — sign in,
same shared space everywhere.

### Install it on your phone

Once it's hosted, DropBridge installs like a real app — its own icon, no
browser bars:

- **Android / Chrome:** open the URL → menu (⋮) → **Add to Home screen**
  (or tap the install prompt when it appears).
- **iPhone / Safari:** open the URL → Share button → **Add to Home Screen**.

Hosting must be over `https://` for this — every option above already is.

---

## Optional — turn voice notes into text

Drop a voice note → get the words as text, with a **Copy transcript**
button. Paste a YouTube link → get the video's transcript.

Everything else in the app works without this. Skip it if you don't want it.

Setup is **4 steps, all in your browser.** No command line, no installing
anything. About 5 minutes, once.

### Step 1 — Get a free key from Groq

Groq is the service that turns speech into text. It's free to start.

1. Go to **console.groq.com** and sign up.
2. In the left sidebar click **API Keys**.
3. Click **Create API Key**, give it any name, click submit.
4. **Copy the key** and paste it somewhere temporary (like Notepad) —
   Groq only shows it to you once.

> ⚠️ Do **not** put this key in `index.html`. That file is public — anyone
> visiting your site could read it and run up your bill. In Step 3 you give
> it to Supabase instead, where it stays hidden on the server.

### Step 2 — Update your database

1. Supabase dashboard → **SQL Editor** (left sidebar) → **New query**.
2. Open the file `supabase/setup.sql` from this project, select all, copy.
3. Paste it into the box and click **Run**.

Safe to run even if you've run it before — it only adds what's missing.

### Step 3 — Give Supabase your Groq key

1. Supabase dashboard → **Edge Functions** (left sidebar).
2. Open the **Secrets** tab.
3. Click **Add new secret** and enter:
   - Name: `GROQ_API_KEY`
   - Value: the key you copied in Step 1
4. Save.

### Step 4 — Create the function

1. Still in **Edge Functions**, click **Deploy a new function** →
   choose **Via Editor**.
2. Name it exactly: `transcribe` (lowercase, no spaces).
3. Delete the sample code that's already in the editor.
4. Open the file `supabase/functions/transcribe/index.ts` from this
   project, select all, copy, and paste it into the editor.
5. Click **Deploy**.

### That's it

Refresh the app and drop in a voice note. You'll see *"Transcribing voice
note…"*, then the text appears underneath with a **Copy transcript**
button. Search finds words inside transcripts too, so you can track down a
voice note by something that was said in it.

**Good to know:**
- Voice notes must be under 24MB (that's Groq's limit).
- YouTube only works on videos that already have captions.
- Already-shared voice notes get a **Transcribe** button you can click.

<details>
<summary>Prefer the command line? (optional alternative to steps 3 & 4)</summary>

```bash
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase secrets set GROQ_API_KEY=your_key_here
npx supabase functions deploy transcribe
```

Your project ref is the code in your dashboard URL:
`supabase.com/dashboard/project/`**`this-part-here`**
</details>

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
