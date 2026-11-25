-- 7-day KeyDo challenge: onboarding streak for new users.
-- Wall: community experiences, tips and showcases.

-- Challenge progress: one row per (user, day)
create table if not exists public.challenge_progress (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid references auth.users(id) on delete cascade not null,
    day          int not null check (day between 1 and 7),
    task_key     text not null,
    completed_at timestamptz not null default now(),
    unique(user_id, day)
);

-- Overall challenge completion (badge earned)
create table if not exists public.challenge_completions (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid references auth.users(id) on delete cascade not null,
    completed_at timestamptz not null default now(),
    badge_tier   text not null default 'pro',
    unique(user_id)
);

-- KeyDo Wall: community posts
create table if not exists public.wall_posts (
    id           uuid primary key default gen_random_uuid(),
    author_id    uuid references auth.users(id) on delete set null,
    display_name text not null,
    -- Content
    post_type    text not null default 'experience'
                   check (post_type in ('experience', 'tip', 'showcase', 'official')),
    content      text not null,
    shortcut_key text,
    image_url    text,
    -- Engagement
    likes        int not null default 0,
    -- Moderation
    is_approved  boolean not null default false,
    is_featured  boolean not null default false,
    is_keydo_official boolean not null default false,
    language     text not null default 'en',
    -- Metadata
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

-- Wall post likes (to prevent double-liking)
create table if not exists public.wall_likes (
    id       uuid primary key default gen_random_uuid(),
    post_id  uuid references public.wall_posts(id) on delete cascade not null,
    user_id  uuid references auth.users(id) on delete cascade not null,
    liked_at timestamptz not null default now(),
    unique(post_id, user_id)
);

-- Wall comments
create table if not exists public.wall_comments (
    id                uuid primary key default gen_random_uuid(),
    post_id           uuid references public.wall_posts(id) on delete cascade not null,
    author_id         uuid references auth.users(id) on delete set null,
    display_name      text not null,
    content           text not null,
    is_keydo_official boolean not null default false,
    is_approved       boolean not null default true,
    created_at        timestamptz not null default now()
);

-- RLS

alter table public.challenge_progress     enable row level security;
alter table public.challenge_completions  enable row level security;
alter table public.wall_posts             enable row level security;
alter table public.wall_likes             enable row level security;
alter table public.wall_comments          enable row level security;

-- Challenge: user reads/writes own progress
create policy "user reads own challenge"
    on public.challenge_progress for select
    using (auth.uid() = user_id);

create policy "user inserts challenge step"
    on public.challenge_progress for insert
    with check (auth.uid() = user_id);

create policy "user reads own completion"
    on public.challenge_completions for select
    using (auth.uid() = user_id);

create policy "user inserts completion"
    on public.challenge_completions for insert
    with check (auth.uid() = user_id);

-- Wall: anyone can read approved posts
create policy "public reads approved wall posts"
    on public.wall_posts for select
    using (is_approved = true);

create policy "user inserts wall post"
    on public.wall_posts for insert
    with check (auth.uid() = author_id);

create policy "user updates own post"
    on public.wall_posts for update
    using (auth.uid() = author_id);

create policy "public reads wall comments"
    on public.wall_comments for select
    using (is_approved = true);

create policy "user inserts comment"
    on public.wall_comments for insert
    with check (auth.uid() = author_id);

create policy "user reads own like"
    on public.wall_likes for select
    using (auth.uid() = user_id);

create policy "user inserts like"
    on public.wall_likes for insert
    with check (auth.uid() = user_id);

-- Function: complete a challenge day
create or replace function public.complete_challenge_day(p_day int, p_task_key text)
returns boolean language plpgsql security definer as $$
declare
    total int;
begin
    insert into public.challenge_progress (user_id, day, task_key)
    values (auth.uid(), p_day, p_task_key)
    on conflict (user_id, day) do nothing;

    select count(*) into total from public.challenge_progress
    where user_id = auth.uid();

    if total >= 7 then
        insert into public.challenge_completions (user_id)
        values (auth.uid())
        on conflict (user_id) do nothing;
        return true; -- badge earned
    end if;
    return false;
end;
$$;

-- Function: like a wall post
create or replace function public.like_wall_post(p_post_id uuid)
returns void language plpgsql security definer as $$
begin
    insert into public.wall_likes (post_id, user_id)
    values (p_post_id, auth.uid())
    on conflict (post_id, user_id) do nothing;

    update public.wall_posts
    set likes = likes + 1, updated_at = now()
    where id = p_post_id;
end;
$$;

-- Seed: KeyDo official wall posts to seed the wall
insert into public.wall_posts
    (display_name, post_type, content, shortcut_key, is_approved, is_featured, is_keydo_official, language)
values
    ('KeyDo Team', 'official',
     'Welcome to the KeyDo Wall! 🎉 Share how you use shortcuts, your favourite time-saving trick, or just say hello. The best posts get featured.',
     null, true, true, true, 'en'),

    ('KeyDo Team', 'tip',
     'Pro tip: use \inv to open your invoice template, then just type the client name and amount. Done in 10 seconds. No Excel, no Word.',
     'inv', true, true, true, 'en'),

    ('KeyDo Team', 'tip',
     'Save your email signature once as \sig — then it''s always three keystrokes away, in Gmail, Outlook, anywhere on your Mac.',
     'sig', true, true, true, 'en'),

    ('KeyDo Team', 'official',
     'Did you know WishStudio can send personalised birthday cards to clients in seconds? Type hbd-ClientName and you''re done. Try it.',
     null, true, false, true, 'en')
on conflict do nothing;
