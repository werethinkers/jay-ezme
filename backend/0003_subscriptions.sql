-- Subscription tiers and billing.
-- Tier values: 'free' | 'pro' | 'teams'
-- Status values: 'active' | 'trial' | 'cancelled' | 'expired'

create table if not exists public.subscriptions (
    id                    uuid primary key default gen_random_uuid(),
    user_id               uuid references auth.users(id) on delete cascade not null,
    tier                  text not null default 'free'
                            check (tier in ('free', 'pro', 'teams')),
    billing_cycle         text check (billing_cycle in ('monthly', 'yearly')),
    status                text not null default 'active'
                            check (status in ('active', 'trial', 'cancelled', 'expired')),
    started_at            timestamptz not null default now(),
    expires_at            timestamptz,
    trial_ends_at         timestamptz,
    stripe_subscription_id text,
    stripe_customer_id    text,
    -- Teams billing
    team_id               uuid,
    team_name             text,
    seats                 int not null default 1,
    -- Credits refresh tracking
    credits_refreshed_at  timestamptz,
    monthly_credits_quota int not null default 50,
    -- Metadata
    created_at            timestamptz not null default now(),
    updated_at            timestamptz not null default now()
);

create unique index if not exists subscriptions_user_id_idx on public.subscriptions (user_id);

-- Teams: member list (user_id → team_id mapping for teams tier)
create table if not exists public.team_members (
    id         uuid primary key default gen_random_uuid(),
    team_id    uuid not null,
    user_id    uuid references auth.users(id) on delete cascade not null,
    role       text not null default 'member' check (role in ('owner', 'admin', 'member')),
    joined_at  timestamptz not null default now(),
    unique(team_id, user_id)
);

-- RLS

alter table public.subscriptions enable row level security;
alter table public.team_members   enable row level security;

create policy "user reads own subscription"
    on public.subscriptions for select
    using (auth.uid() = user_id);

create policy "team member reads team"
    on public.team_members for select
    using (auth.uid() = user_id);

-- Service role can manage everything (Stripe webhook / admin use)

-- Trigger: auto-create a free subscription when a user signs up
create or replace function public.create_free_subscription()
returns trigger language plpgsql security definer as $$
begin
    insert into public.subscriptions (user_id, tier, status, monthly_credits_quota)
    values (new.id, 'free', 'active', 50)
    on conflict (user_id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created_subscription on auth.users;
create trigger on_auth_user_created_subscription
    after insert on auth.users
    for each row execute function public.create_free_subscription();

-- Function: get active tier for a user (safe to call from app via RPC)
create or replace function public.get_my_subscription()
returns json language plpgsql security definer as $$
declare
    sub public.subscriptions%rowtype;
begin
    select * into sub from public.subscriptions
    where user_id = auth.uid()
    limit 1;

    if not found then
        return json_build_object('tier', 'free', 'status', 'active', 'monthly_credits_quota', 50);
    end if;

    -- Expire if past expiry date
    if sub.expires_at is not null and sub.expires_at < now() and sub.status = 'active' then
        update public.subscriptions set status = 'expired', tier = 'free', updated_at = now()
        where id = sub.id;
        sub.status := 'expired';
        sub.tier := 'free';
    end if;

    return row_to_json(sub);
end;
$$;

-- Function: refresh monthly AI credits (called by app on each month turn)
create or replace function public.refresh_monthly_credits(p_user_id uuid, p_grant int)
returns void language plpgsql security definer as $$
begin
    update public.subscriptions
    set credits_refreshed_at = now(), updated_at = now()
    where user_id = p_user_id;
end;
$$;
