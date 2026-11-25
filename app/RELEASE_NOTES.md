# KeyDo 5.0

## What's new

### Subscriptions — Free, Pro, Teams
KeyDo now has a full billing structure with three tiers. Free users get unlimited text shortcuts, live values, the calculator and 3 collections. Pro ($4.99/mo or $39/yr · ₹399/mo or ₹3,199/yr) unlocks cloud sync, unlimited collections, media shortcuts, the full Wish Studio, AppBuilder, EzTools, AI features and the Template Marketplace. Teams ($7.99/seat/mo · ₹649/seat/mo) adds shared collections, an admin dashboard, template locking, usage analytics and an onboarding kit.

The upgrade screen is accessible from the home page and from any Pro/Teams feature. Payment goes through the website (Stripe Checkout). The app verifies the subscription tier from the server on sign-in and refreshes it hourly.

### 7-Day KeyDo Challenge
A guided onboarding challenge with one practical task per day — from saving your email signature to building your first AppBuilder app. A streak pill on the home screen shows your progress. Completing all 7 days earns the **KeyDo Pro badge**, a shareable 1080×1080 image for LinkedIn, Twitter and WhatsApp.

### KeyDo Store — Template Marketplace 2.0
The Marketplace is now backed by Supabase with real install counts, ratings and category browse. Packs install with one click and their shortcuts land in your library automatically. Pro users can publish their own packs. Staff-picked packs are pre-seeded: Sales Starter Kit, Customer Support Essentials, HR Basics and Developer Shortcuts.

### KeyDo Wall
A community wall where users share how they use KeyDo — experiences, tips and showcases. The KeyDo team posts official tips and responds directly. Posts go through a lightweight approval step to keep the wall clean. Like posts, filter by type, and share your own experience.

### International Starter Pack
30 new international shortcut templates alongside the existing Indian packs: email replies (thanks, follow-up, out-of-office), professional signatures, sales sequences, support scripts, HR letters, developer shortcuts (standup, PR description), invoice and quotation templates, and common live-value shortcuts. No INR or GST — neutral global English.

### Upgrade sheet close button fixed
The × button on the subscription upgrade sheet now dismisses the sheet correctly on first tap.

### Stable app identity — no more permission re-prompts on update
KeyDo is now signed with an Apple Developer ID Application certificate. macOS recognises the same identity across updates, so Accessibility and Screen Recording permissions are granted once and kept — you will no longer be asked to re-approve them every time a new version is installed.

### Keyboard tap check ✓
No changes to `miniJSlashTap`, `pickerActive`, `triggerTracking`, or any key-swallowing logic. The heartbeat watchdog is active.
