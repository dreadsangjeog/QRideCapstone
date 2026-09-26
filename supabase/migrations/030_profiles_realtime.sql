-- Live admin badges need profile changes (new KYC submissions).
do $$
begin
  alter publication supabase_realtime add table public.profiles;
exception
  when duplicate_object then
    null;
end $$;
