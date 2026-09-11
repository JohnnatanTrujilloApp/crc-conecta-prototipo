-- Recover pending registrations created before the access-request trigger existed.
with missing_requests as (
  select
    person.organization_id,
    coalesce(account.requested_site_id, person.site_id) as site_id,
    account.id as user_account_id,
    person.id as person_id,
    coalesce(person.self_registered_at, account.created_at, now()) as registered_at
  from public.user_accounts account
  join public.people person on person.id=account.person_id
  where account.access_status='PENDING_APPROVAL'
    and coalesce(account.requested_site_id, person.site_id) is not null
    and not exists(
      select 1 from public.access_requests request
      where request.user_account_id=account.id or request.person_id=person.id
    )
), inserted as (
  insert into public.access_requests(
    organization_id, site_id, user_account_id, person_id, status, created_at, updated_at
  )
  select organization_id, site_id, user_account_id, person_id,
    'PENDING_APPROVAL'::public.campus_access_status, registered_at, now()
  from missing_requests
  on conflict do nothing
  returning id, organization_id, site_id, user_account_id, person_id
)
insert into public.audit_logs(
  organization_id, site_id, user_id, action, entity_type, entity_id, new_values
)
select organization_id, site_id, user_account_id, 'ACCESS_REQUEST_CREATED',
  'ACCESS_REQUEST', id, jsonb_build_object(
    'status', 'PENDING_APPROVAL',
    'person_id', person_id,
    'source', 'BACKFILL'
  )
from inserted;

notify pgrst,'reload schema';
