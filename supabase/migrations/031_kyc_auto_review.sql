-- Apply an automatic name + photo check after the rider submits KYC.
-- The KYC guard blocks riders from setting verified, so the RPC
-- sets a transaction-local flag the trigger will honor.

create or replace function public.profiles_kyc_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('qride.kyc_auto_review', true) = 'on' then
    return new;
  end if;
  if public.is_admin() then
    return new;
  end if;
  new.role := old.role;
  if new.verification_status = 'verified' then
    new.verification_status := old.verification_status;
    new.verified_at := old.verified_at;
  end if;
  if old.verification_status = 'verified' then
    new.first_name := old.first_name;
    new.middle_name := old.middle_name;
    new.last_name := old.last_name;
    new.birthdate := old.birthdate;
  end if;
  return new;
end;
$$;

create or replace function public.kyc_apply_auto_review(
  p_name_ok boolean,
  p_photo_ok boolean,
  p_note text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_status text;
  v_id text;
  v_selfie text;
begin
  if v_uid is null then
    raise exception 'not_signed_in';
  end if;

  select verification_status, id_image_path, selfie_image_path
    into v_status, v_id, v_selfie
  from public.profiles
  where id = v_uid;

  if v_status = 'verified' then
    return 'verified';
  end if;

  if v_id is null or trim(v_id) = '' or v_selfie is null or trim(v_selfie) = '' then
    raise exception 'kyc_photos_missing';
  end if;

  perform set_config('qride.kyc_auto_review', 'on', true);

  if p_name_ok and p_photo_ok then
    update public.profiles
    set verification_status = 'verified',
        verified_at = now(),
        verification_note = null
    where id = v_uid;
    return 'verified';
  end if;

  update public.profiles
  set verification_status = 'rejected',
      verified_at = null,
      verification_note = nullif(trim(coalesce(p_note, '')), '')
  where id = v_uid;
  return 'rejected';
end;
$$;

revoke all on function public.kyc_apply_auto_review(boolean, boolean, text) from public;
grant execute on function public.kyc_apply_auto_review(boolean, boolean, text) to authenticated;
