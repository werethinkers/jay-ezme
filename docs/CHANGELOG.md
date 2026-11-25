# KeyDo — Change Log

Changes are logged in reverse chronological order per CLAUDE.md rule.
Format: date · version · what changed · how it was done · commands run.

---

## 2026-11-25 — Admin panel, creator dashboard, admin roles & creator backfill

**What changed:**
- Added `is_creator` column to `public.subscriptions`
- Created `public.admin_roles` table (roles: super_admin, admin, creator, eco_partner, developer, publisher)
- Created `public.creator_profiles` table (display_name, bio, avatar, website, twitter, packs_published, total_installs, total_earnings, is_verified)
- Created `public.ecosystem_partners` table (company, contact, partner_type, api_key)
- Backfilled all 5 founding users: Pro tier, 3000 credits/month, is_creator=true, super_admin + creator roles, verified creator profiles
- Built `guide/admin/index.html` — auth-gated admin panel (users, subscriptions, creators, eco partners, roles, store)
- Built `guide/creator/index.html` — creator dashboard (pack management, profile, subscription info, credits usage)
- Saved `backend/0006_admin_roles_creators.sql` with full schema + seed SQL

**How it was done:** SQL via Lovable `query_database` tool; HTML files written directly to repo.

**Commands run:**
```sql
ALTER TABLE public.subscriptions ADD COLUMN IF NOT EXISTS is_creator boolean NOT NULL DEFAULT false;
CREATE TABLE IF NOT EXISTS public.admin_roles (...);
CREATE TABLE IF NOT EXISTS public.creator_profiles (...);
CREATE TABLE IF NOT EXISTS public.ecosystem_partners (...);
UPDATE public.subscriptions SET is_creator = true WHERE user_id IN (SELECT id FROM auth.users);
INSERT INTO public.admin_roles ... SELECT ... FROM auth.users ON CONFLICT DO NOTHING;
INSERT INTO public.creator_profiles ... SELECT ... FROM auth.users ON CONFLICT DO NOTHING;
```

---

## 2026-11-25 · v5.0

### Database migrations (backend/)

**0003_subscriptions.sql** — added subscription tables and RPC
- `subscription_tiers` lookup table (free / pro / teams) with USD and INR pricing, credit quotas, collection limits
- `user_subscriptions` table with Stripe customer and subscription IDs, current period, cancel-at-period-end flag
- `get_my_subscription()` RPC returns the caller's tier with limits (server-authoritative, used by the app on sign-in)
- RLS: each user reads and updates only their own row
- Run via: `query_database` tool on Lovable project `5f041390-5f8c-439b-9bad-1b179e055700`

**0004_marketplace.sql** — added Template Marketplace tables and RPC
- `marketplace_packs` table: title, slug, category, author, description, price, install count, rating, preview images, pack data (JSONB), publish status, featured/staff-picked flags
- `marketplace_installs` table: tracks which users installed which packs (for install counts, deduplication)
- `install_marketplace_pack(p_pack_id)` RPC: records install, increments counter, returns the pack's data
- RLS: published packs are readable by everyone; authors can update their own unpublished packs
- Seeded 4 staff-picked packs: Sales Starter Kit, Customer Support Essentials, HR Basics, Developer Shortcuts
- Run via: `query_database` tool

**0005_challenges_wall.sql** — added 7-Day Challenge and Wall tables and RPCs
- `challenge_completions` table: one row per user per day (1–7), server timestamp
- `complete_challenge_day(p_day_number)` RPC: idempotent insert, returns completed days array
- `wall_posts` table: display_name, post_type (experience/tip/showcase/official), content, shortcut_key, likes, is_approved, is_featured, is_keydo_official, language
- `like_wall_post(p_post_id)` RPC: increments likes counter (no double-like guard on server — handled client-side)
- RLS: approved posts are public; users insert their own posts (is_approved defaults false)
- Seeded 3 wall posts (official KeyDo tips)
- Run via: `query_database` tool

---

### Swift files added (app/Sources/EzMe/)

**EzMeSubscription.swift** (new file)
- `SubscriptionTier` enum with USD/INR pricing, credit quotas, collection limits
- `SubscriptionFeature` enum with `requiredTier` for each feature gate
- `SubscriptionManager.shared` (@MainActor ObservableObject): loads from `get_my_subscription()` RPC on sign-in, caches 1 hour in UserDefaults, `canUse(_:)` gate, `gate(_:)` returns Bool and shows upgrade sheet, `require(_:action:)` runs action or shows upgrade
- `SubscriptionUpgradeView`: pricing sheet with Free/Pro/Teams cards, monthly/yearly toggle
- `TierBadge`, `ProLockOverlay`, `SubscriptionStatusView`, `PricingPageView`

**EzMeChallenge.swift** (new file)
- `ChallengeDay` struct (taskKey, title, detail, symbol, cta, ctaAction)
- `Challenge.days` — 7 static days
- `ChallengeManager.shared` (@MainActor ObservableObject): UserDefaults + server sync via `complete_challenge_day()` RPC, fires badge sheet on completion
- `ChallengeStreakPill` for home screen
- `ChallengeView`, `DayCellView`, `BadgeView`, `BadgeCardMaker` (renders 1080×1080 PNG)

**EzMeMarketplace.swift** (new file)
- `MarketplacePack`, `MarketplaceCategory` models
- `MarketplaceManager.shared` (@MainActor ObservableObject): loads packs from Supabase REST, tracks `installedIDs`, `install(pack:)` calls `install_marketplace_pack()` RPC then posts `.keydoInstallPackShortcuts` notification
- `KeyDoStoreView` (named differently from existing `MarketplaceView` in EzMe.swift which handles emoticons/GIFs)
- `PackCard`, `PublishPackView` (Pro-gated)

**EzMeWall.swift** (new file)
- `WallPost` Codable model
- `WallManager.shared` (@MainActor ObservableObject): loads approved posts from Supabase REST, `like(post:)` RPC, `submit()` POSTs new post
- `WallView`, `WallPostCard`, `ComposeWallPostView`

**EzMeStarterPackIntl.swift** (new file)
- `StarterPackIntl` enum with 30 international shortcut templates across 10 categories
- `allClips: [Clip]` static property; seeded in `EzMe.swift`'s `seedDefaultShortcuts()` on first launch (flag key: `keydoIntlPackInstalled`)

---

### EzMe.swift edits

- Added `"KeyDo Store","Wall","Challenge"` to `filterShortcutClips` exclusion list (line ~62)
- Added the same 3 sections to no-scroll guard in `regularWorkspace` (line ~469)
- Added `HStack{SubscriptionStatusView();Spacer();ChallengeStreakPill().onTapGesture{...}}` to homeTop (line ~479)
- Added `else if section == "KeyDo Store"`, `"Wall"`, `"Challenge"` section views (line ~485)
- Added icon cases: `"KeyDo Store":"storefront.fill"`, `"Wall":"sparkles.rectangle.stack.fill"`, `"Challenge":"flame.fill"` (line ~566)
- On `onChange(isAuthenticated)`: added `Task{await SubscriptionManager.shared.signedIn()}` (line ~438)
- Added `.onReceive` for `keydoInstallPackShortcuts` notification to handle marketplace pack installs
- Added `.sheet` for `SubscriptionUpgradeView`
- Added intl pack seeding block inside `seedDefaultShortcuts()` (line ~673)
- Added `Notification.Name.keydoInstallPackShortcuts` extension (line ~3847)

---

### Other files

**app/VERSION**: bumped `4.64` → `5.0`

**app/RELEASE_NOTES.md**: written for v5.0 (Subscriptions, Challenge, KeyDo Store, Wall, International Starter Pack, keyboard tap check note)

**guide/index.html**: added nav links and guide sections for Subscriptions, 7-Day Challenge, KeyDo Store, KeyDo Wall, and International Starter Pack

---
