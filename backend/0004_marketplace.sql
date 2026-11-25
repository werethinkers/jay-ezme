-- Template Marketplace: publish, discover and install shortcut/design packs.
-- Model: free packs (anyone) + paid packs (Pro author, 70/30 split).

create table if not exists public.marketplace_packs (
    id            uuid primary key default gen_random_uuid(),
    author_id     uuid references auth.users(id) on delete set null,
    author_name   text not null default 'KeyDo User',
    -- Identity
    title         text not null,
    description   text not null default '',
    -- Classification
    category      text not null default 'general'
                    check (category in ('business', 'sales', 'hr', 'support', 'developer',
                                        'creative', 'personal', 'finance', 'student', 'general')),
    language      text not null default 'en',
    tags          text[] not null default '{}',
    -- The pack
    pack_data     jsonb not null default '{}',
    pack_version  text not null default '1.0',
    -- Pricing
    price_usd     numeric(8,2) not null default 0
                    check (price_usd >= 0 and price_usd <= 999),
    -- Stats
    install_count int not null default 0,
    rating_sum    int not null default 0,
    rating_count  int not null default 0,
    -- Moderation
    is_published  boolean not null default false,
    is_featured   boolean not null default false,
    is_staff_pick boolean not null default false,
    -- Metadata
    cover_url     text,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

-- Installs: one row per (user, pack) — idempotent
create table if not exists public.marketplace_installs (
    id           uuid primary key default gen_random_uuid(),
    pack_id      uuid references public.marketplace_packs(id) on delete cascade not null,
    user_id      uuid references auth.users(id) on delete cascade not null,
    installed_at timestamptz not null default now(),
    unique(pack_id, user_id)
);

-- Ratings: one per (user, pack)
create table if not exists public.marketplace_ratings (
    id         uuid primary key default gen_random_uuid(),
    pack_id    uuid references public.marketplace_packs(id) on delete cascade not null,
    user_id    uuid references auth.users(id) on delete cascade not null,
    stars      int not null check (stars between 1 and 5),
    review     text,
    rated_at   timestamptz not null default now(),
    unique(pack_id, user_id)
);

-- Purchases (for paid packs)
create table if not exists public.marketplace_purchases (
    id                 uuid primary key default gen_random_uuid(),
    pack_id            uuid references public.marketplace_packs(id) not null,
    buyer_id           uuid references auth.users(id) not null,
    seller_id          uuid references auth.users(id),
    amount_usd         numeric(8,2) not null,
    platform_cut_usd   numeric(8,2) not null,
    seller_payout_usd  numeric(8,2) not null,
    stripe_payment_id  text,
    purchased_at       timestamptz not null default now(),
    unique(pack_id, buyer_id)
);

-- RLS

alter table public.marketplace_packs      enable row level security;
alter table public.marketplace_installs   enable row level security;
alter table public.marketplace_ratings    enable row level security;
alter table public.marketplace_purchases  enable row level security;

-- Anyone can browse published packs
create policy "public reads published packs"
    on public.marketplace_packs for select
    using (is_published = true);

-- Author can read/update their own packs
create policy "author reads own packs"
    on public.marketplace_packs for select
    using (auth.uid() = author_id);

create policy "author updates own packs"
    on public.marketplace_packs for update
    using (auth.uid() = author_id);

create policy "author inserts packs"
    on public.marketplace_packs for insert
    with check (auth.uid() = author_id);

-- Users can read their own installs
create policy "user reads own installs"
    on public.marketplace_installs for select
    using (auth.uid() = user_id);

create policy "user inserts install"
    on public.marketplace_installs for insert
    with check (auth.uid() = user_id);

-- Users can read/write their own ratings
create policy "user reads own rating"
    on public.marketplace_ratings for select
    using (auth.uid() = user_id);

create policy "user upserts own rating"
    on public.marketplace_ratings for insert
    with check (auth.uid() = user_id);

create policy "user updates own rating"
    on public.marketplace_ratings for update
    using (auth.uid() = user_id);

-- Users can read their own purchases
create policy "user reads own purchases"
    on public.marketplace_purchases for select
    using (auth.uid() = buyer_id);

-- Function: install a pack (increments counter, records install)
create or replace function public.install_marketplace_pack(p_pack_id uuid)
returns void language plpgsql security definer as $$
begin
    insert into public.marketplace_installs (pack_id, user_id)
    values (p_pack_id, auth.uid())
    on conflict (pack_id, user_id) do nothing;

    update public.marketplace_packs
    set install_count = install_count + 1, updated_at = now()
    where id = p_pack_id and is_published = true;
end;
$$;

-- Function: submit or update a rating
create or replace function public.rate_marketplace_pack(p_pack_id uuid, p_stars int, p_review text default null)
returns void language plpgsql security definer as $$
declare
    old_stars int;
begin
    select stars into old_stars from public.marketplace_ratings
    where pack_id = p_pack_id and user_id = auth.uid();

    if found then
        update public.marketplace_ratings
        set stars = p_stars, review = p_review, rated_at = now()
        where pack_id = p_pack_id and user_id = auth.uid();
        update public.marketplace_packs
        set rating_sum = rating_sum - old_stars + p_stars, updated_at = now()
        where id = p_pack_id;
    else
        insert into public.marketplace_ratings (pack_id, user_id, stars, review)
        values (p_pack_id, auth.uid(), p_stars, p_review);
        update public.marketplace_packs
        set rating_sum = rating_sum + p_stars, rating_count = rating_count + 1, updated_at = now()
        where id = p_pack_id;
    end if;
end;
$$;

-- Seed: KeyDo staff picks (free packs)
insert into public.marketplace_packs
    (author_name, title, description, category, language, tags, price_usd, pack_data, is_published, is_featured, is_staff_pick)
values
    ('KeyDo Team', 'Sales Starter Kit', 'Cold outreach, follow-ups, proposals and closing. 20 proven templates used by real sales reps.', 'sales', 'en',
     array['sales', 'email', 'cold-outreach', 'follow-up'], 0,
     '{"type":"shortcuts","items":[{"key":"cold","label":"Cold intro email","body":"Hi {{name}},\n\nI noticed {{company}} is {{observation}}. We help teams like yours {{value_prop}}.\n\nWould a 15-minute call make sense this week?\n\nBest,\n{{from}}"},{"key":"fu1","label":"Follow-up 1","body":"Hi {{name}},\n\nJust checking in on my note from last week. Happy to share a quick case study if useful.\n\n{{from}}"},{"key":"props","label":"Proposal sent","body":"Hi {{name}},\n\nShared the proposal — it covers {{scope}} at {{price}}. Let me know if any questions.\n\n{{from}}"},{"key":"close","label":"Closing nudge","body":"Hi {{name}},\n\nWanted to follow up before {{deadline}}. Happy to adjust scope or timing if needed.\n\n{{from}}"}]}',
     true, true, true),

    ('KeyDo Team', 'Customer Support Essentials', 'Reply templates for the most common support scenarios. Works in Gmail, Freshdesk, Zendesk — anywhere you type.', 'support', 'en',
     array['support', 'customer-service', 'reply'], 0,
     '{"type":"shortcuts","items":[{"key":"thanks","label":"Thank you for writing","body":"Hi {{name}},\n\nThank you for reaching out. I''ve got your message and will get back to you within {{sla}}.\n\nBest,\n{{agent}}"},{"key":"refund","label":"Refund approved","body":"Hi {{name}},\n\nYour refund of {{amount}} has been approved and will reach you within {{days}} business days.\n\nSorry for any inconvenience.\n\n{{agent}}"},{"key":"closed","label":"Ticket closed","body":"Hi {{name}},\n\nI''m closing this ticket as resolved. If anything comes up, just reply and we''ll reopen it.\n\n{{agent}}"}]}',
     true, true, true),

    ('KeyDo Team', 'HR Basics', 'Interview invites, offer confirmations, rejection emails and onboarding messages. For small HR teams.', 'hr', 'en',
     array['hr', 'hiring', 'onboarding'], 0,
     '{"type":"shortcuts","items":[{"key":"invite","label":"Interview invite","body":"Dear {{name}},\n\nWe''d like to invite you for an interview for {{role}} on {{date}} at {{time}}.\n\nPlease confirm if this works.\n\n{{hr}}"},{"key":"offer","label":"Verbal offer","body":"Hi {{name}},\n\nGreat news — we''d like to offer you the {{role}} position. Formal letter follows shortly.\n\n{{hr}}"},{"key":"reject","label":"Rejection (kind)","body":"Dear {{name}},\n\nThank you for your time. After careful review, we won''t be moving forward for {{role}} right now. We''ll keep your profile for future roles.\n\n{{hr}}"}]}',
     true, false, true),

    ('KeyDo Team', 'Developer Shortcuts', 'Git messages, standup templates, bug reports and code review notes. Built for devs who live in Slack and Linear.', 'developer', 'en',
     array['developer', 'git', 'standup', 'code-review'], 0,
     '{"type":"shortcuts","items":[{"key":"stnd","label":"Daily standup","body":"Yesterday: {{yesterday}}\nToday: {{today}}\nBlockers: {{blockers}}"},{"key":"pr","label":"PR description","body":"## What\n{{what}}\n\n## Why\n{{why}}\n\n## How to test\n{{test}}\n\n## Checklist\n- [ ] Tests pass\n- [ ] Docs updated"},{"key":"bug","label":"Bug report","body":"**Bug:** {{title}}\n**Steps:** {{steps}}\n**Expected:** {{expected}}\n**Actual:** {{actual}}\n**Environment:** {{env}}"}]}',
     true, false, true)
on conflict do nothing;
