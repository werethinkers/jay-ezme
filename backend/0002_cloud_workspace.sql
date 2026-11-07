-- Per-user cloud workspace for the EzMe Mac app (Google sign-in through Supabase Auth).
-- workspace_files: each user's app data files (shortcuts, collections, records, settings) as text.
-- ezme-media bucket: each user's attachments under <user id>/..., private.

CREATE TABLE IF NOT EXISTS public.workspace_files (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  path text NOT NULL CHECK (path ~ '^[A-Za-z0-9._/-]{1,200}$' AND position('..' in path) = 0),
  content text NOT NULL CHECK (length(content) <= 20000000),
  sha256 text CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
  device text CHECK (device IS NULL OR length(device) <= 120),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, path)
);
ALTER TABLE public.workspace_files ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.workspace_files FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.workspace_files TO authenticated;
GRANT ALL ON public.workspace_files TO service_role;
CREATE POLICY "Own workspace files: read" ON public.workspace_files FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "Own workspace files: insert" ON public.workspace_files FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "Own workspace files: update" ON public.workspace_files FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "Own workspace files: delete" ON public.workspace_files FOR DELETE TO authenticated USING (user_id = auth.uid());

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('ezme-media', 'ezme-media', false, 524288000)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "EzMe media: own read" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'ezme-media' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "EzMe media: own insert" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'ezme-media' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "EzMe media: own update" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'ezme-media' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'ezme-media' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "EzMe media: own delete" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'ezme-media' AND (storage.foldername(name))[1] = auth.uid()::text);
