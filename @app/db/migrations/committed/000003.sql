--! Previous: sha1:7ce3500d6b21b3ad749edda9a178d9cc9453772b
--! Hash: sha1:8f48064b5026b7a4b96b29d67454de09e9263e47

-- Enter migration here
drop function if exists app_public.issue_credits;

create function app_public.issue_credits(
  project_id uuid,
  units integer,
  initial_distribution jsonb
) returns app_public.credit_vintages as $$
declare
  -- v_credit_class_id uuid;
  v_issuer_wallet_id uuid;
  v_credit_class_issuer_id uuid;
  v_issuee_id uuid;
  v_credit_vintage app_public.credit_vintages;
  v_project app_public.projects;
  v_key text;
  v_value numeric;
begin
  if app_public.current_user_id() is null then
    raise exception 'You must log in to issue credits' using errcode = 'LOGIN';
  end if;

  -- find project
  select * into v_project
  from app_public.projects
  where id = project_id;

  if v_project.id is null then
    raise exception 'Project not found' using errcode = 'NTFND';
  end if;

  -- get current user (issuer)'s wallet id
  select wallet_id into v_issuer_wallet_id
  from app_public.users
  where id = app_public.current_user_id();

  if v_issuer_wallet_id is null then
    raise exception 'Wallet is required' using errcode = 'NTFND';
  end if;

  -- verify current user is allowed to issue credits for this credit class
  select id into v_credit_class_issuer_id from app_public.credit_class_issuers
  where credit_class_id = v_project.credit_class_id and issuer_id = v_issuer_wallet_id;

  if v_credit_class_issuer_id is null then
    raise exception 'User not allowed to issue credits for this project' using errcode = 'DNIED';
  end if;

  -- TODO verify sum initial_distribution values = 1

  -- create credit vintage
  insert into app_public.credit_vintages (credit_class_id, project_id, issuer_id, units, initial_distribution)
    values(v_project.credit_class_id, project_id, v_issuer_wallet_id, units, initial_distribution)
    returning * into v_credit_vintage;

  -- create account balances
  for v_key, v_value IN
     select * from jsonb_each_text(initial_distribution)
  loop
     -- raise notice '%: %', v_key, v_value;
     if v_value != 0 then
      if v_key = 'projectDeveloper' then
        if v_project.developer_id is null then
          raise exception 'Project does not have any project developer' using errcode = 'NTFND';
        end if;
        v_issuee_id := v_project.developer_id;
      end if;

      if v_key = 'landOwner' then
        if v_project.land_owner_id is null then
          raise exception 'Project does not have any land owner' using errcode = 'NTFND';
        end if;
        v_issuee_id := v_project.land_owner_id;
      end if;

      if v_key = 'landSteward' then
        if v_project.steward_id is null then
          raise exception 'Project does not have any land steward' using errcode = 'NTFND';
        end if;
        v_issuee_id := v_project.steward_id;
      end if;

      insert into app_public.account_balances (credit_vintage_id, wallet_id, liquid_balance, burnt_balance)
        values (v_project.credit_vintage_id, v_issuee_id, v_value * units , 0);
    end if;
  end loop;

  return v_credit_vintage;
end;
$$ language plpgsql strict volatile security definer set search_path to pg_catalog, public, pg_temp;
