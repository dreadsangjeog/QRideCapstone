-- AI name/face pass is only a filter. Staff make the final verified decision.

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
    set verification_status = 'pending',
        verified_at = null,
        verification_note = coalesce(
          nullif(trim(coalesce(p_note, '')), ''),
          'Name and face passed the app check. Waiting for staff to verify.'
        )
    where id = v_uid;
    return 'pending';
  end if;

  update public.profiles
  set verification_status = 'rejected',
      verified_at = null,
      verification_note = nullif(trim(coalesce(p_note, '')), '')
  where id = v_uid;
  return 'rejected';
end;
$$;
