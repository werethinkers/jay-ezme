-- EzMe app releases and update telemetry, in the Lovable Cloud (Supabase) project
-- "EzMe Marketing Backend" (5f041390-5f8c-439b-9bad-1b179e055700). Applied with direct SQL.

-- Every published Mac build. Anyone can read; only publish_release() can write.
CREATE TABLE IF NOT EXISTS public.app_releases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version text NOT NULL CHECK (length(version) BETWEEN 1 AND 20),
  build integer NOT NULL UNIQUE CHECK (build > 0),
  url text NOT NULL CHECK (url LIKE 'https://%' AND length(url) <= 500),
  sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  notes text CHECK (notes IS NULL OR length(notes) <= 5000),
  minimum_system_version text NOT NULL DEFAULT '14.0' CHECK (length(minimum_system_version) <= 20),
  channel text NOT NULL DEFAULT 'stable' CHECK (channel IN ('stable', 'beta')),
  published_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_releases ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_releases FROM anon, authenticated;
GRANT SELECT ON public.app_releases TO anon, authenticated;
GRANT ALL ON public.app_releases TO service_role;
DROP POLICY IF EXISTS "Anyone can read releases" ON public.app_releases;
CREATE POLICY "Anyone can read releases" ON public.app_releases FOR SELECT TO anon, authenticated USING (true);

-- Anonymous update events from the app (no user data): checks, installs, failures.
CREATE TABLE IF NOT EXISTS public.app_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event text NOT NULL CHECK (event IN ('update_check', 'update_started', 'update_failed', 'launch')),
  version text CHECK (version IS NULL OR length(version) <= 20),
  build integer,
  target_build integer,
  os_version text CHECK (os_version IS NULL OR length(os_version) <= 40),
  detail text CHECK (detail IS NULL OR length(detail) <= 300),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_events FROM anon, authenticated;
GRANT INSERT ON public.app_events TO anon, authenticated;
GRANT ALL ON public.app_events TO service_role;
DROP POLICY IF EXISTS "Apps can log events" ON public.app_events;
CREATE POLICY "Apps can log events" ON public.app_events FOR INSERT TO anon, authenticated
  WITH CHECK (event IN ('update_check', 'update_started', 'update_failed', 'launch'));

-- Release publishing: GitHub Actions calls publish_release() with a token whose SHA-256 is stored here.
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
CREATE TABLE IF NOT EXISTS private.release_publishers (
  token_sha256 text PRIMARY KEY,
  label text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.publish_release(
  p_token text, p_version text, p_build integer, p_url text, p_sha256 text,
  p_notes text DEFAULT NULL, p_minimum_system_version text DEFAULT '14.0', p_channel text DEFAULT 'stable'
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_token IS NULL OR NOT EXISTS (
    SELECT 1 FROM private.release_publishers
    WHERE token_sha256 = encode(pg_catalog.sha256(convert_to(p_token, 'UTF8')), 'hex')
  ) THEN
    RAISE EXCEPTION 'not allowed' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.app_releases (version, build, url, sha256, notes, minimum_system_version, channel)
  VALUES (p_version, p_build, p_url, lower(p_sha256), p_notes, coalesce(p_minimum_system_version, '14.0'), coalesce(p_channel, 'stable'))
  ON CONFLICT (build) DO UPDATE SET version = EXCLUDED.version, url = EXCLUDED.url, sha256 = EXCLUDED.sha256,
    notes = EXCLUDED.notes, minimum_system_version = EXCLUDED.minimum_system_version, channel = EXCLUDED.channel;
END;
$$;
REVOKE ALL ON FUNCTION public.publish_release(text, text, integer, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_release(text, text, integer, text, text, text, text, text) TO anon, authenticated;

-- The current hand-built release.
INSERT INTO public.app_releases (version, build, url, sha256, notes)
VALUES ('3.38', 168, 'https://ezme.ezyourlife.com/downloads/EzMe-3.38-macOS.zip',
        '907f6151a870ee8f4c4b04fe6d4b2ba70f3cec2cfc271d3ac610db9765e5f9cc', 'First public build.')
ON CONFLICT (build) DO NOTHING;
