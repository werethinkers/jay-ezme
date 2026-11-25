-- KeyDo: Admin roles, creator profiles, ecosystem partners
-- Run: 2026-11-25

-- Add creator flag to subscriptions
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS is_creator boolean NOT NULL DEFAULT false;

-- Admin roles table
CREATE TABLE IF NOT EXISTS public.admin_roles (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  role       text NOT NULL CHECK (role IN ('super_admin','admin','creator','eco_partner','developer','publisher')),
  granted_by uuid REFERENCES auth.users(id),
  granted_at timestamptz NOT NULL DEFAULT now(),
  notes      text,
  UNIQUE(user_id, role)
);

-- Creator profiles
CREATE TABLE IF NOT EXISTS public.creator_profiles (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
  display_name    text NOT NULL,
  bio             text,
  avatar_url      text,
  website         text,
  twitter         text,
  packs_published int NOT NULL DEFAULT 0,
  total_installs  int NOT NULL DEFAULT 0,
  total_earnings  numeric(10,2) NOT NULL DEFAULT 0,
  is_verified     boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Ecosystem partners
CREATE TABLE IF NOT EXISTS public.ecosystem_partners (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  company_name  text NOT NULL,
  contact_email text NOT NULL,
  partner_type  text NOT NULL CHECK (partner_type IN ('reseller','integration','enterprise','api_consumer')),
  api_key       text UNIQUE DEFAULT encode(gen_random_bytes(32),'hex'),
  is_active     boolean NOT NULL DEFAULT true,
  notes         text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Seed: backfill founding team (all existing users)
UPDATE public.subscriptions
  SET is_creator = true
  WHERE user_id IN (SELECT id FROM auth.users);

INSERT INTO public.admin_roles (user_id, role, notes)
  SELECT id, 'super_admin', 'Founding team — granted at launch'
  FROM auth.users
  ON CONFLICT (user_id, role) DO NOTHING;

INSERT INTO public.admin_roles (user_id, role, notes)
  SELECT id, 'creator', 'Founding creator — 3000 credits/month'
  FROM auth.users
  ON CONFLICT (user_id, role) DO NOTHING;

INSERT INTO public.creator_profiles (user_id, display_name, is_verified)
  SELECT id, initcap(split_part(email, '@', 1)), true
  FROM auth.users
  ON CONFLICT (user_id) DO NOTHING;
