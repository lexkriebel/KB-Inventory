# Setting up live sync with Supabase

These steps connect the inventory page to a free Supabase database. When you're done:

- **Anyone with the link** can see the live counts. They don't need to log in.
- **Approved editors** sign in with their email and can change counts. Everyone else sees the change within a second or two.
- Every change is logged: who, which item, old → new, when. You can see it under **Recent changes** on the page.

It takes about 20 minutes. You don't need to install anything. Everything happens in your web browser.

> Supabase sometimes renames its menus. If a label below doesn't match exactly, look for the nearest equivalent. The left sidebar icons usually show their names when you hover over them.

---

## 1. Create the Supabase project

1. Go to **supabase.com** and click **Start your project**. Sign up, for example with your GitHub account.
2. Click **New project**. If it asks for an organization first, create one with any name on the **Free** plan.
3. Fill in:
   - **Project name:** `kb-inventory` (or anything you like)
   - **Database password:** click **Generate a password**, then save it somewhere safe. You won't need it for this setup.
   - **Region:** pick the one closest to your group.
4. Click **Create new project**. Wait 1–2 minutes until the dashboard finishes setting up.

## 2. Create the tables (run the setup SQL)

1. In this GitHub repository, open the file **`supabase-setup.sql`**. Click the **Copy raw file** button (two overlapping squares, top right of the file view).
2. In Supabase, click **SQL Editor** in the left sidebar (the icon looks like a terminal: `>_`).
3. Click **New query**, or the **+** button. Paste the whole file into the big text box.
4. Click **Run**, bottom right.
5. You should see **Success. No rows returned**. Messages that say something "does not exist, skipping" or "already exists, skipping" are normal.

This step also loads all 93 standard items and your current counts from `inventory.json` (Archery Weapon, Armor – Heavy, Armor – Light and Armor – Moderate, 1 each).

You can run this file again later without harm. It never resets counts.

## 3. Add yourself (and others) as an editor

1. Click **Table Editor** in the left sidebar (the grid icon).
2. Click the **editors** table.
3. Click **Insert** → **Insert row**.
4. Type your **email**. Optionally type a **name**, which is what appears in "Recent changes", e.g. `Lex`. Leave the other fields alone.
5. Click **Save**.

Repeat for each person who should be able to edit. **To remove an editor,** tick their row in this table and click **Delete**. Their changes are refused from that moment on.

> Only emails in this table can change anything. Anyone else who signs in can still only view.

## 4. Turn on email sign-in

1. Click **Authentication** in the left sidebar (the people icon).
2. Open **Sign In / Providers** (sometimes just **Providers**) and click **Email**.
3. Make sure **Enable Email provider** is **on**. It usually is by default.
4. Make sure **Confirm email** is **on**. This stops anyone from claiming an email address that isn't theirs.
5. Click **Save** if you changed anything.

### How your editors will log in

Supabase's built-in email sender is very limited on the free plan. It only sends a few emails per hour, and usually only to members of your Supabase team. That means "Email me a sign-in link" won't reliably reach your group. The easiest way around it is to **create each editor's login yourself, with a password**:

1. Go to **Authentication** → **Users**.
2. Click **Add user** → **Create new user**.
3. Enter the person's **email** and a starting **password** (at least 6 characters). Tick **Auto Confirm User**.
4. Click **Create user**.
5. Tell the person their password privately. Once signed in, they can change it under **Account** on the inventory page.

Also make sure that email is in the **editors** table (step 3). Creating a user lets them sign in. The **editors** table is what lets them edit.

*Optional, later:* to make the "Email me a sign-in link" button work for everyone, connect a free email-sending service. Go to **Authentication** → **Emails** → **SMTP Settings** and fill in the details from a provider such as Resend or Brevo. Until then, people can still click the link button, but the email may not arrive.

## 5. Tell Supabase where your page lives

1. Go to **Authentication** → **URL Configuration**.
2. Set **Site URL** to:
   `https://lexkriebel.github.io/KB-Inventory/`
3. Under **Redirect URLs**, click **Add URL**, paste the same address and save.

This is where people land after clicking a sign-in link in their email.

## 6. Copy your project's address and public key

1. Click **Project Settings** (the gear icon at the bottom of the left sidebar).
2. Open **Data API** or **API Keys**. Some projects show both.
3. Copy the **Project URL**. It looks like `https://abcdefghijkl.supabase.co`.
4. Copy the **public** key. Depending on your project it's called either:
   - **Publishable key** (starts with `sb_publishable_`), or
   - **anon public** key (a long string starting with `eyJ`, sometimes under a **Legacy API keys** tab).

   Either one works.

> ⚠️ **Never** copy the **service_role** or **secret** key into the page. That key can do anything. The public key is safe because the database only lets it read.

## 7. Put the address and key into the page

**Easiest:** send me the Project URL and the public key and I'll put them in and publish. The public key is safe to share.

**Or do it yourself on GitHub:**

1. In this repository, open **`index.html`** and click the **pencil icon** (Edit this file).
2. Near the start of the `<script>` section, find these two lines:
   ```
   const SUPABASE_URL = "";
   const SUPABASE_ANON_KEY = "";
   ```
3. Paste your values **between the quote marks**, like this:
   ```
   const SUPABASE_URL = "https://abcdefghijkl.supabase.co";
   const SUPABASE_ANON_KEY = "sb_publishable_xxxxxxxx";
   ```
4. Click **Commit changes…**, then **Commit changes** again.
5. GitHub Pages updates the live site within a minute or two.

## 8. Test it

1. Open `https://lexkriebel.github.io/KB-Inventory/` in a **private/incognito window**. You should see the counts. Next to the toolbar, the status should say **Live · view only — sign in to edit**. There should be no − / + buttons.
2. In a normal window, click **Sign in**, enter your email and password, and click **Sign in**. The status should change to **Live · editing as (your name)**, and the − / + buttons appear.
3. Press **+** on an item. Watch the private window, or your phone: the number should change there within a couple of seconds, without refreshing.
4. Click **Recent changes**. Your edit should be listed with your name.
5. In Supabase, open **Table Editor** → **change_log** to see the full log, including email addresses. Visitors to the page only see names, never emails.
6. Optional: sign in as someone who is *not* in the **editors** table. The page should say **not an approved editor yet**, and the controls stay hidden.

## 9. If the old GitHub version was used after November 20, 2026

The counts in step 2 were copied from `inventory.json` on November 20, 2026. If anyone changed counts with the old page after that:

1. Sign in on the new page as an editor.
2. Click **Export** → **Load old inventory.json**.
3. Confirm. This replaces the current counts with whatever is in `inventory.json`, and it can be undone with **Undo**.

Once you're happy, `inventory.json` is no longer used. You can delete it from the repository.

---

## Good to know

- **Free projects pause after about a week with no activity.** If the page says it can't load, log in to Supabase, open the project and click **Restore project**. Any visit or edit counts as activity, so regular use keeps it awake.
- **Several people editing at once is safe.** Each + / − is added on the server, one item at a time, so nothing gets overwritten.
- **Typing a number** sets that exact number. **Undo** reverses your own last changes in this browser.
- **Import** (in the Export window) replaces everyone's counts with the pasted list. Items not listed are set to 0. It asks before doing anything.
- **Someone forgot their password:** go to **Authentication** → **Users**, find them, and delete the user. Then create them again (step 4) with a new password. Their history in the change log stays.
- **Sign-in link says "expired" or "invalid":** links only work once and for a limited time. Request a new one, or use a password.

---

## Royaltea Bar sign-up sheet

The bar page (`royaltea-bar.html`) uses the same Supabase project and the same **editors** list.

1. In Supabase, open **SQL Editor** → **New query**.
2. Paste the whole of **`bar-setup.sql`** from this repository. Make sure nothing is highlighted, then click **Run**.
3. The result at the bottom should say **bar_items 32** and **with_translation 19**.

You can run `bar-setup.sql` again whenever it changes. It never removes sign-ups, and it only adds what's missing, such as the drink translations.

How it works:

- **Anyone** can tap items, press **Confirm selection**, and enter their real name, character name and how many they're bringing. No account needed.
- The sheet shows **character names only**. Real names are visible only to editors, who sign in with **Organizer sign in** on the bar page.
- After someone confirms, only editors can change things. Signed-in editors can:
  - click a name to change or remove that sign-up
  - use **Edit item** or **Add item** to change the list, including the real-world translation shown in brackets, e.g. Dew of the Mountain (Mt Dew)
  - use **Clear all sign-ups** to start a fresh sheet for the next event
- **Colors:** the page uses the dark **Highland Evening** scheme (moss green, loch blue, amber, cream). The older light schemes can still be previewed by adding `?palette=heather`, `?palette=tartan`, `?palette=loch` or `?palette=shortbread` to the bar page address. To change it for everyone, change `data-palette="highland"` near the top of `royaltea-bar.html`.
