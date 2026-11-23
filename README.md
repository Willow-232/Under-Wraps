# Under Wraps 🎁

**Gift planning for families, kept under wraps.**

Under Wraps is a shared gift tracker for families. Everyone logs what they've bought, tracks budgets, and sees spending at a glance, while gifts bought *for you* stay hidden from you on every device.

## Features

- **Family groups:** start a family, invite others with a six-character code, and belong to as many families as you like
- **Hidden gifts:** gifts for you are filtered out on the server, so they never reach your phone
- **Budgets:** a budget per person, plus a personal spending limit only you can see
- **Status tracking:** idea → bought → wrapped → given
- **Live sync:** changes show up on everyone's phones within seconds
- **Installable:** add it to your home screen on iPhone or Android and it opens like a regular app

## Install on your phone

Open the app link in your browser, then:

- **iPhone (Safari):** tap Share → **Add to Home Screen**
- **Android (Chrome):** tap ⋮ → **Install app** (or **Add to Home screen**)

## Run your own copy

1. Fork this repository.
2. Create a free project at [supabase.com](https://supabase.com), open the **SQL Editor**, paste in `supabase/schema.sql` and run it.
3. In Supabase, go to **Authentication → Sign In / Providers → Email** and turn **Confirm email** off (or set up custom SMTP).
4. Put your project URL and publishable key in `config.js`.
5. Turn on **GitHub Pages** (Settings → Pages → Deploy from branch → `main` / root).

## Tech

One HTML file, no build step. [Supabase](https://supabase.com) handles accounts, the Postgres database (with row-level security) and realtime sync. GitHub Pages hosts the site.

The publishable key in `config.js` is meant to be public. Access to the data is controlled by the security rules in `supabase/schema.sql`.

## Licence

MIT
