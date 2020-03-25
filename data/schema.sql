--
-- PostgreSQL database dump
--

-- Dumped from database version 10.11
-- Dumped by pg_dump version 10.11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: app_hidden; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA app_hidden;


--
-- Name: app_private; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA app_private;


--
-- Name: app_public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA app_public;


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry, geography, and raster spatial types and functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: party_type; Type: TYPE; Schema: app_public; Owner: -
--

CREATE TYPE app_public.party_type AS ENUM (
    'user',
    'organization'
);


--
-- Name: project_state; Type: TYPE; Schema: app_public; Owner: -
--

CREATE TYPE app_public.project_state AS ENUM (
    'proposed',
    'pending_approval',
    'active',
    'hold',
    'ended'
);


--
-- Name: assert_valid_password(text); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.assert_valid_password(new_password text) RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
  -- TODO: add better assertions!
  if length(new_password) < 8 then
    raise exception 'Password is too weak' using errcode = 'WEAKP';
  end if;
end;
$$;


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: user; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public."user" (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    username public.citext NOT NULL,
    first_name text,
    last_name text,
    avatar_url text,
    is_admin boolean DEFAULT false NOT NULL,
    is_verified boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    wallet_id uuid,
    party_id uuid,
    type app_public.party_type DEFAULT 'user'::app_public.party_type NOT NULL,
    CONSTRAINT user_type_check CHECK ((type = 'user'::app_public.party_type))
);


--
-- Name: TABLE "user"; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON TABLE app_public."user" IS 'A user who can log in to the application.';


--
-- Name: COLUMN "user".id; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public."user".id IS 'Unique identifier for the user.';


--
-- Name: COLUMN "user".username; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public."user".username IS 'Public-facing username (or ''handle'') of the user.';


--
-- Name: COLUMN "user".first_name; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public."user".first_name IS 'Public-facing first name (or pseudonym) of the user.';


--
-- Name: COLUMN "user".last_name; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public."user".last_name IS 'Public-facing last name (or pseudonym) of the user.';


--
-- Name: COLUMN "user".avatar_url; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public."user".avatar_url IS 'Optional avatar URL.';


--
-- Name: COLUMN "user".is_admin; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public."user".is_admin IS 'If true, the user has elevated privileges.';


--
-- Name: link_or_register_user(uuid, character varying, character varying, json, json); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.link_or_register_user(f_user_id uuid, f_service character varying, f_identifier character varying, f_profile json, f_auth_details json) RETURNS app_public."user"
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'app_public', 'app_private', 'app_hidden', 'public'
    AS $$
declare
  v_matched_user_id uuid;
  v_matched_authentication_id uuid;
  v_email citext;
  v_first_name text;
  v_last_name text;
  v_avatar_url text;
  v_user app_public.user;
  v_user_email app_public.user_emails;
begin
  -- See if a user account already matches these details
  select id, user_id
    into v_matched_authentication_id, v_matched_user_id
    from app_public.user_authentications
    where service = f_service
    and identifier = f_identifier
    limit 1;

  if v_matched_user_id is not null and f_user_id is not null and v_matched_user_id <> f_user_id then
    raise exception 'A different user already has this account linked.' using errcode = 'TAKEN';
  end if;

  v_email = f_profile ->> 'email';
  v_first_name := f_profile ->> 'first_name';
  v_last_name := f_profile ->> 'last_name';
  v_avatar_url := f_profile ->> 'avatar_url';

  if v_matched_authentication_id is null then
    if f_user_id is not null then
      -- Link new account to logged in user account
      insert into app_public.user_authentications (user_id, service, identifier, details) values
        (f_user_id, f_service, f_identifier, f_profile) returning id, user_id into v_matched_authentication_id, v_matched_user_id;
      insert into app_private.user_authentication_secrets (user_authentication_id, details) values
        (v_matched_authentication_id, f_auth_details);
    elsif v_email is not null then
      -- See if the email is registered
      select * into v_user_email from app_public.user_emails where email = v_email and is_verified is true;
      if v_user_email is not null then
        -- User exists!
        insert into app_public.user_authentications (user_id, service, identifier, details) values
          (v_user_email.user_id, f_service, f_identifier, f_profile) returning id, user_id into v_matched_authentication_id, v_matched_user_id;
        insert into app_private.user_authentication_secrets (user_authentication_id, details) values
          (v_matched_authentication_id, f_auth_details);
      end if;
    end if;
  end if;
  if v_matched_user_id is null and f_user_id is null and v_matched_authentication_id is null then
    -- Create and return a new user account
    return app_private.register_user(f_service, f_identifier, f_profile, f_auth_details, true);
  else
    if v_matched_authentication_id is not null then
      update app_public.user_authentications
        set details = f_profile
        where id = v_matched_authentication_id;
      update app_private.user_authentication_secrets
        set details = f_auth_details
        where user_authentication_id = v_matched_authentication_id;
      update app_public.user
        set
          first_name = coalesce("user".first_name, v_first_name),
          last_name = coalesce("user".last_name, v_last_name),
          avatar_url = coalesce("user".avatar_url, v_avatar_url)
        where id = v_matched_user_id
        returning  * into v_user;
      return v_user;
    else
      -- v_matched_authentication_id is null
      -- -> v_matched_user_id is null (they're paired)
      -- -> f_user_id is not null (because the if clause above)
      -- -> v_matched_authentication_id is not null (because of the separate if block above creating a user_authentications)
      -- -> contradiction.
      raise exception 'This should not occur';
    end if;
  end if;
end;
$$;


--
-- Name: FUNCTION link_or_register_user(f_user_id uuid, f_service character varying, f_identifier character varying, f_profile json, f_auth_details json); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.link_or_register_user(f_user_id uuid, f_service character varying, f_identifier character varying, f_profile json, f_auth_details json) IS 'If you''re logged in, this will link an additional OAuth login to your account if necessary. If you''re logged out it may find if an account already exists (based on OAuth details or email address) and return that, or create a new user account if necessary.';


--
-- Name: sessions; Type: TABLE; Schema: app_private; Owner: -
--

CREATE TABLE app_private.sessions (
    uuid uuid DEFAULT public.gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_active timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: login(public.citext, text); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.login(username public.citext, password text) RETURNS app_private.sessions
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    AS $$
declare
  v_user app_public.user;
  v_user_secret app_private.user_secrets;
  v_login_attempt_window_duration interval = interval '5 minutes';
  v_session app_private.sessions;
begin
  if username like '%@%' then
    -- It's an email
    select "user".* into v_user
    from app_public.user
    inner join app_public.user_emails
    on (user_emails.user_id = "user".id)
    where user_emails.email = login.username
    order by
      user_emails.is_verified desc, -- Prefer verified email
      user_emails.created_at asc -- Failing that, prefer the first registered (unverified user _should_ verify before logging in)
    limit 1;
  else
    -- It's a username
    select "user".* into v_user
    from app_public.user
    where "user".username = login.username;
  end if;

  if not (v_user is null) then
    -- Load their secrets
    select * into v_user_secret from app_private.user_secrets
    where user_secrets.user_id = v_user.id;

    -- Have there been too many login attempts?
    if (
      v_user_secret.first_failed_password_attempt is not null
    and
      v_user_secret.first_failed_password_attempt > NOW() - v_login_attempt_window_duration
    and
      v_user_secret.failed_password_attempts >= 3
    ) then
      raise exception 'User account locked - too many login attempts. Try again after 5 minutes.' using errcode = 'LOCKD';
    end if;

    -- Not too many login attempts, let's check the password.
    -- NOTE: `password_hash` could be null, this is fine since `NULL = NULL` is null, and null is falsy.
    if v_user_secret.password_hash = crypt(password, v_user_secret.password_hash) then
      -- Excellent - they're logged in! Let's reset the attempt tracking
      update app_private.user_secrets
      set failed_password_attempts = 0, first_failed_password_attempt = null, last_login_at = now()
      where user_id = v_user.id;
      -- Create a session for the user
      insert into app_private.sessions (user_id) values (v_user.id) returning * into v_session;
      -- And finally return the session
      return v_session;
    else
      -- Wrong password, bump all the attempt tracking figures
      update app_private.user_secrets
      set
        failed_password_attempts = (case when first_failed_password_attempt is null or first_failed_password_attempt < now() - v_login_attempt_window_duration then 1 else failed_password_attempts + 1 end),
        first_failed_password_attempt = (case when first_failed_password_attempt is null or first_failed_password_attempt < now() - v_login_attempt_window_duration then now() else first_failed_password_attempt end)
      where user_id = v_user.id;
      return null; -- Must not throw otherwise transaction will be aborted and attempts won't be recorded
    end if;
  else
    -- No user with that email/username was found
    return null;
  end if;
end;
$$;


--
-- Name: FUNCTION login(username public.citext, password text); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.login(username public.citext, password text) IS 'Returns a user that matches the username/password combo, or null on failure.';


--
-- Name: really_create_user(public.citext, text, boolean, text, text, text, text); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.really_create_user(username public.citext, email text, email_is_verified boolean, first_name text, last_name text, avatar_url text, password text DEFAULT NULL::text) RETURNS app_public."user"
    LANGUAGE plpgsql
    SET search_path TO 'app_public', 'app_private', 'app_hidden', 'public'
    AS $$
declare
  v_user app_public.user;
  v_username citext = username;
begin
  if password is not null then
    perform app_private.assert_valid_password(password);
  end if;
  if email is null then
    raise exception 'Email is required' using errcode = 'MODAT';
  end if;

  -- Insert the new user
  insert into app_public.user (username, first_name, last_name, avatar_url) values
    (v_username, first_name, last_name, avatar_url)
    returning * into v_user;

	-- Add the user's email
  insert into app_public.user_emails (user_id, email, is_verified, is_primary)
  values (v_user.id, email, email_is_verified, email_is_verified);

  -- Store the password
  if password is not null then
    update app_private.user_secrets
    set password_hash = crypt(password, gen_salt('bf'))
    where user_id = v_user.id;
  end if;

  -- Refresh the user
  select * into v_user from app_public.user where id = v_user.id;

  return v_user;
end;
$$;


--
-- Name: FUNCTION really_create_user(username public.citext, email text, email_is_verified boolean, first_name text, last_name text, avatar_url text, password text); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.really_create_user(username public.citext, email text, email_is_verified boolean, first_name text, last_name text, avatar_url text, password text) IS 'Creates a user account. All arguments are optional, it trusts the calling method to perform sanitisation.';


--
-- Name: register_user(character varying, character varying, json, json, boolean); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.register_user(f_service character varying, f_identifier character varying, f_profile json, f_auth_details json, f_email_is_verified boolean DEFAULT false) RETURNS app_public."user"
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'app_public', 'app_private', 'app_hidden', 'public'
    AS $$
declare
  v_user app_public.user;
  v_email citext;
  v_first_name text;
  v_last_name text;
  v_username citext;
  v_avatar_url text;
  v_user_authentication_id uuid;
begin
  -- Extract data from the user’s OAuth profile data.
  v_email := f_profile ->> 'email';
  v_first_name := f_profile ->> 'first_name';
  v_last_name := f_profile ->> 'last_name';
  v_username := f_profile ->> 'username';
  v_avatar_url := f_profile ->> 'avatar_url';

  -- Sanitise the username, and make it unique if necessary.
  if v_username is null then
    v_username = coalesce(v_email, 'user');
  end if;
  -- v_username = regexp_replace(v_username, '^[^a-z]+', '', 'i');
  -- v_username = regexp_replace(v_username, '[^a-z0-9]+', '_', 'i');
  if v_username is null or length(v_username) < 3 then
    v_username = 'user';
  end if;
  select (
    case
    when i = 0 then v_username
    else v_username || i::text
    end
  ) into v_username from generate_series(0, 1000) i
  where not exists(
    select 1
    from app_public.user
    where "user".username = (
      case
      when i = 0 then v_username
      else v_username || i::text
      end
    )
  )
  limit 1;

  -- Create the user account
  v_user = app_private.really_create_user(
    username => v_username,
    email => v_email,
    email_is_verified => f_email_is_verified,
    first_name => v_first_name,
    last_name => v_last_name,
    avatar_url => v_avatar_url
  );

  -- Insert the user’s private account data (e.g. OAuth tokens)
  insert into app_public.user_authentications (user_id, service, identifier, details) values
    (v_user.id, f_service, f_identifier, f_profile) returning id into v_user_authentication_id;
  insert into app_private.user_authentication_secrets (user_authentication_id, details) values
    (v_user_authentication_id, f_auth_details);

  return v_user;
end;
$$;


--
-- Name: FUNCTION register_user(f_service character varying, f_identifier character varying, f_profile json, f_auth_details json, f_email_is_verified boolean); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.register_user(f_service character varying, f_identifier character varying, f_profile json, f_auth_details json, f_email_is_verified boolean) IS 'Used to register a user from information gleaned from OAuth. Primarily used by link_or_register_user';


--
-- Name: tg__add_job(); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.tg__add_job() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'app_public', 'app_private', 'app_hidden', 'public'
    AS $$
begin
  perform graphile_worker.add_job(tg_argv[0], json_build_object('id', NEW.id), coalesce(tg_argv[1], public.gen_random_uuid()::text));
  return NEW;
end;
$$;


--
-- Name: FUNCTION tg__add_job(); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.tg__add_job() IS 'Useful shortcut to create a job on insert/update. Pass the task name as the first trigger argument, and optionally the queue name as the second argument. The record id will automatically be available on the JSON payload.';


--
-- Name: tg__timestamps(); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.tg__timestamps() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'app_public', 'app_private', 'app_hidden', 'public'
    AS $$
begin
  NEW.created_at = (case when TG_OP = 'INSERT' then NOW() else OLD.created_at end);
  NEW.updated_at = (case when TG_OP = 'UPDATE' and OLD.updated_at >= NOW() then OLD.updated_at + interval '1 millisecond' else NOW() end);
  return NEW;
end;
$$;


--
-- Name: FUNCTION tg__timestamps(); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.tg__timestamps() IS 'This trigger should be called on all tables with created_at, updated_at - it ensures that they cannot be manipulated and that updated_at will always be larger than the previous updated_at.';


--
-- Name: tg_user__make_first_user_admin(); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.tg_user__make_first_user_admin() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'app_public', 'app_private', 'app_hidden', 'public'
    AS $$
begin
  NEW.is_admin = true;
  return NEW;
end;
$$;


--
-- Name: tg_user_email_secrets__insert_with_user_email(); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.tg_user_email_secrets__insert_with_user_email() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'app_public', 'app_private', 'app_hidden', 'public'
    AS $$
declare
  v_verification_token text;
begin
  if NEW.is_verified is false then
    v_verification_token = encode(gen_random_bytes(7), 'hex');
  end if;
  insert into app_private.user_email_secrets(user_email_id, verification_token) values(NEW.id, v_verification_token);
  return NEW;
end;
$$;


--
-- Name: FUNCTION tg_user_email_secrets__insert_with_user_email(); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.tg_user_email_secrets__insert_with_user_email() IS 'Ensures that every user_email record has an associated user_email_secret record.';


--
-- Name: tg_user_secrets__insert_with_user(); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.tg_user_secrets__insert_with_user() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'app_public', 'app_private', 'app_hidden', 'public'
    AS $$
begin
  insert into app_private.user_secrets(user_id) values(NEW.id);
  return NEW;
end;
$$;


--
-- Name: FUNCTION tg_user_secrets__insert_with_user(); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.tg_user_secrets__insert_with_user() IS 'Ensures that every user record has an associated user_secret record.';


--
-- Name: change_password(text, text); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.change_password(old_password text, new_password text) RETURNS boolean
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    AS $$
declare
  v_user app_public.user;
  v_user_secret app_private.user_secrets;
begin
  select "user".* into v_user
  from app_public.user
  where id = app_public.current_user_id();

  if not (v_user is null) then
    -- Load their secrets
    select * into v_user_secret from app_private.user_secrets
    where user_secrets.user_id = v_user.id;

    if v_user_secret.password_hash = crypt(old_password, v_user_secret.password_hash) then
      perform app_private.assert_valid_password(new_password);
      -- Reset the password as requested
      update app_private.user_secrets
      set
        password_hash = crypt(new_password, gen_salt('bf'))
      where user_secrets.user_id = v_user.id;
      return true;
    else
      raise exception 'Incorrect password' using errcode = 'CREDS';
    end if;
  else
    raise exception 'You must log in to change your password' using errcode = 'LOGIN';
  end if;
end;
$$;


--
-- Name: FUNCTION change_password(old_password text, new_password text); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.change_password(old_password text, new_password text) IS 'Enter your old password and a new password to change your password.';


--
-- Name: confirm_account_deletion(text); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.confirm_account_deletion(token text) RETURNS boolean
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    SET search_path TO 'app_public', 'app_private', 'app_hidden', 'public'
    AS $$
declare
  v_user_secret app_private.user_secrets;
  v_token_max_duration interval = interval '3 days';
begin
  if app_public.current_user_id() is null then
    raise exception 'You must log in to delete your account' using errcode = 'LOGIN';
  end if;

  select * into v_user_secret
    from app_private.user_secrets
    where user_secrets.user_id = app_public.current_user_id();

  if v_user_secret is null then
    -- Success: they're already deleted
    return true;
  end if;

  -- Check the token
  if v_user_secret.delete_account_token = token then
    -- Token passes; delete their account :(
    delete from app_public.user where id = app_public.current_user_id();
    return true;
  end if;

  raise exception 'The supplied token was incorrect - perhaps you''re logged in to the wrong account, or the token has expired?' using errcode = 'DNIED';
end;
$$;


--
-- Name: FUNCTION confirm_account_deletion(token text); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.confirm_account_deletion(token text) IS 'If you''re certain you want to delete your account, use `requestAccountDeletion` to request an account deletion token, and then supply the token through this mutation to complete account deletion.';


--
-- Name: current_session_id(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.current_session_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select nullif(pg_catalog.current_setting('jwt.claims.session_id', true), '')::uuid;
$$;


--
-- Name: FUNCTION current_session_id(); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.current_session_id() IS 'Handy method to get the current session ID.';


--
-- Name: current_user(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public."current_user"() RETURNS app_public."user"
    LANGUAGE sql STABLE
    AS $$
  select "user".* from app_public.user where id = app_public.current_user_id();
$$;


--
-- Name: FUNCTION "current_user"(); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public."current_user"() IS 'The currently logged in user (or null if not logged in).';


--
-- Name: current_user_id(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.current_user_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'app_public', 'app_private', 'app_hidden', 'public'
    AS $$
  select user_id from app_private.sessions where uuid = app_public.current_session_id();
$$;


--
-- Name: FUNCTION current_user_id(); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.current_user_id() IS 'Handy method to get the current user ID for use in RLS policies, etc; in GraphQL, use `currentUser{id}` instead.';


--
-- Name: forgot_password(public.citext); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.forgot_password(email public.citext) RETURNS void
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    SET search_path TO 'app_public', 'app_private', 'app_hidden', 'public'
    AS $$
declare
  v_user_email app_public.user_emails;
  v_token text;
  v_token_min_duration_between_emails interval = interval '3 minutes';
  v_token_max_duration interval = interval '3 days';
  v_now timestamptz = clock_timestamp(); -- Function can be called multiple during transaction
  v_latest_attempt timestamptz;
begin
  -- Find the matching user_email:
  select user_emails.* into v_user_email
  from app_public.user_emails
  where user_emails.email = forgot_password.email
  order by is_verified desc, id desc;

  -- If there is no match:
  if v_user_email is null then
    -- This email doesn't exist in the system; trigger an email stating as much.

    -- We do not allow this email to be triggered more than once every 15
    -- minutes, so we need to track it:
    insert into app_private.unregistered_email_password_resets (email, latest_attempt)
      values (forgot_password.email, v_now)
      on conflict on constraint unregistered_email_pkey
      do update
        set latest_attempt = v_now, attempts = unregistered_email_password_resets.attempts + 1
        where unregistered_email_password_resets.latest_attempt < v_now - interval '15 minutes'
      returning latest_attempt into v_latest_attempt;

    if v_latest_attempt = v_now then
      perform graphile_worker.add_job(
        'user__forgot_password_unregistered_email',
        json_build_object('email', forgot_password.email::text)
      );
    end if;

    -- TODO: we should clear out the unregistered_email_password_resets table periodically.

    return;
  end if;

  -- There was a match.
  -- See if we've triggered a reset recently:
  if exists(
    select 1
    from app_private.user_email_secrets
    where user_email_id = v_user_email.id
    and password_reset_email_sent_at is not null
    and password_reset_email_sent_at > v_now - v_token_min_duration_between_emails
  ) then
    -- If so, take no action.
    return;
  end if;

  -- Fetch or generate reset token:
  update app_private.user_secrets
  set
    reset_password_token = (
      case
      when reset_password_token is null or reset_password_token_generated < v_now - v_token_max_duration
      then encode(gen_random_bytes(7), 'hex')
      else reset_password_token
      end
    ),
    reset_password_token_generated = (
      case
      when reset_password_token is null or reset_password_token_generated < v_now - v_token_max_duration
      then v_now
      else reset_password_token_generated
      end
    )
  where user_id = v_user_email.user_id
  returning reset_password_token into v_token;

  -- Don't allow spamming an email:
  update app_private.user_email_secrets
  set password_reset_email_sent_at = v_now
  where user_email_id = v_user_email.id;

  -- Trigger email send:
  perform graphile_worker.add_job(
    'user__forgot_password',
    json_build_object('id', v_user_email.user_id, 'email', v_user_email.email::text, 'token', v_token)
  );

end;
$$;


--
-- Name: FUNCTION forgot_password(email public.citext); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.forgot_password(email public.citext) IS 'If you''ve forgotten your password, give us one of your email addresses and we''ll send you a reset token. Note this only works if you have added an email address!';


--
-- Name: logout(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.logout() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'app_public', 'app_private', 'app_hidden', 'public'
    AS $$
begin
  -- Delete the session
  delete from app_private.sessions where uuid = app_public.current_session_id();
  -- Clear the identifier from the transaction
  perform set_config('jwt.claims.session_id', '', true);
end;
$$;


--
-- Name: user_emails; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.user_emails (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid DEFAULT app_public.current_user_id() NOT NULL,
    email public.citext NOT NULL,
    is_verified boolean DEFAULT false NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_emails_email_check CHECK ((email OPERATOR(public.~) '[^@]+@[^@]+\.[^@]+'::public.citext)),
    CONSTRAINT user_emails_must_be_verified_to_be_primary CHECK (((is_primary IS FALSE) OR (is_verified IS TRUE)))
);


--
-- Name: TABLE user_emails; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON TABLE app_public.user_emails IS 'Information about a user''s email address.';


--
-- Name: COLUMN user_emails.email; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.user_emails.email IS 'The user email address, in `a@b.c` format.';


--
-- Name: COLUMN user_emails.is_verified; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.user_emails.is_verified IS 'True if the user has is_verified their email address (by clicking the link in the email we sent them, or logging in with a social login provider), false otherwise.';


--
-- Name: make_email_primary(uuid); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.make_email_primary(email_id uuid) RETURNS app_public.user_emails
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_user_email app_public.user_emails;
begin
  select * into v_user_email from app_public.user_emails where id = email_id and user_id = app_public.current_user_id();
  if v_user_email is null then
    raise exception 'That''s not your email' using errcode = 'DNIED';
    return null;
  end if;
  if v_user_email.is_verified is false then
    raise exception 'You may not make an unverified email primary' using errcode = 'VRIFY';
  end if;
  update app_public.user_emails set is_primary = false where user_id = app_public.current_user_id() and is_primary is true and id <> email_id;
  update app_public.user_emails set is_primary = true where user_id = app_public.current_user_id() and is_primary is not true and id = email_id returning * into v_user_email;
  return v_user_email;
end;
$$;


--
-- Name: FUNCTION make_email_primary(email_id uuid); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.make_email_primary(email_id uuid) IS 'Your primary email is where we''ll notify of account events; other emails may be used for discovery or login. Use this when you''re changing your email address.';


--
-- Name: request_account_deletion(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.request_account_deletion() RETURNS boolean
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    SET search_path TO 'app_public', 'app_private', 'app_hidden', 'public'
    AS $$
declare
  v_user_email app_public.user_emails;
  v_token text;
  v_token_max_duration interval = interval '3 days';
begin
  if app_public.current_user_id() is null then
    raise exception 'You must log in to delete your account' using errcode = 'LOGIN';
  end if;

  -- Get the email to send account deletion token to
  select * into v_user_email
    from app_public.user_emails
    where user_id = app_public.current_user_id()
    and is_primary is true;

  -- Fetch or generate token
  update app_private.user_secrets
  set
    delete_account_token = (
      case
      when delete_account_token is null or delete_account_token_generated < NOW() - v_token_max_duration
      then encode(gen_random_bytes(7), 'hex')
      else delete_account_token
      end
    ),
    delete_account_token_generated = (
      case
      when delete_account_token is null or delete_account_token_generated < NOW() - v_token_max_duration
      then now()
      else delete_account_token_generated
      end
    )
  where user_id = app_public.current_user_id()
  returning delete_account_token into v_token;

  -- Trigger email send
  perform graphile_worker.add_job('user__send_delete_account_email', json_build_object('email', v_user_email.email::text, 'token', v_token));
  return true;
end;
$$;


--
-- Name: FUNCTION request_account_deletion(); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.request_account_deletion() IS 'Begin the account deletion flow by requesting the confirmation email';


--
-- Name: resend_email_verification_code(uuid); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.resend_email_verification_code(email_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  if exists(
    select 1
    from app_public.user_emails
    where user_emails.id = email_id
    and user_id = app_public.current_user_id()
    and is_verified is false
  ) then
    perform graphile_worker.add_job('user_emails__send_verification', json_build_object('id', email_id));
    return true;
  end if;
  return false;
end;
$$;


--
-- Name: FUNCTION resend_email_verification_code(email_id uuid); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.resend_email_verification_code(email_id uuid) IS 'If you didn''t receive the verification code for this email, we can resend it. We silently cap the rate of resends on the backend, so calls to this function may not result in another email being sent if it has been called recently.';


--
-- Name: reset_password(uuid, text, text); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.reset_password(user_id uuid, reset_token text, new_password text) RETURNS boolean
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    SET search_path TO 'app_public', 'app_private', 'app_hidden', 'public'
    AS $$
declare
  v_user app_public.user;
  v_user_secret app_private.user_secrets;
  v_token_max_duration interval = interval '3 days';
begin
  select "user".* into v_user
  from app_public.user
  where id = user_id;

  if not (v_user is null) then
    -- Load their secrets
    select * into v_user_secret from app_private.user_secrets
    where user_secrets.user_id = v_user.id;

    -- Have there been too many reset attempts?
    if (
      v_user_secret.first_failed_reset_password_attempt is not null
    and
      v_user_secret.first_failed_reset_password_attempt > NOW() - v_token_max_duration
    and
      v_user_secret.failed_reset_password_attempts >= 20
    ) then
      raise exception 'Password reset locked - too many reset attempts' using errcode = 'LOCKD';
    end if;

    -- Not too many reset attempts, let's check the token
    if v_user_secret.reset_password_token = reset_token then
      -- Excellent - they're legit
      perform app_private.assert_valid_password(new_password);
      -- Let's reset the password as requested
      update app_private.user_secrets
      set
        password_hash = crypt(new_password, gen_salt('bf')),
        failed_password_attempts = 0,
        first_failed_password_attempt = null,
        reset_password_token = null,
        reset_password_token_generated = null,
        failed_reset_password_attempts = 0,
        first_failed_reset_password_attempt = null
      where user_secrets.user_id = v_user.id;
      return true;
    else
      -- Wrong token, bump all the attempt tracking figures
      update app_private.user_secrets
      set
        failed_reset_password_attempts = (case when first_failed_reset_password_attempt is null or first_failed_reset_password_attempt < now() - v_token_max_duration then 1 else failed_reset_password_attempts + 1 end),
        first_failed_reset_password_attempt = (case when first_failed_reset_password_attempt is null or first_failed_reset_password_attempt < now() - v_token_max_duration then now() else first_failed_reset_password_attempt end)
      where user_secrets.user_id = v_user.id;
      return null;
    end if;
  else
    -- No user with that id was found
    return null;
  end if;
end;
$$;


--
-- Name: FUNCTION reset_password(user_id uuid, reset_token text, new_password text); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.reset_password(user_id uuid, reset_token text, new_password text) IS 'After triggering forgotPassword, you''ll be sent a reset token. Combine this with your user ID and a new password to reset your password.';


--
-- Name: tg__graphql_subscription(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.tg__graphql_subscription() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
declare
  v_process_new bool = (TG_OP = 'INSERT' OR TG_OP = 'UPDATE');
  v_process_old bool = (TG_OP = 'UPDATE' OR TG_OP = 'DELETE');
  v_event text = TG_ARGV[0];
  v_topic_template text = TG_ARGV[1];
  v_attribute text = TG_ARGV[2];
  v_record record;
  v_sub text;
  v_topic text;
  v_i int = 0;
  v_last_topic text;
begin
  for v_i in 0..1 loop
    if (v_i = 0) and v_process_new is true then
      v_record = new;
    elsif (v_i = 1) and v_process_old is true then
      v_record = old;
    else
      continue;
    end if;
     if v_attribute is not null then
      execute 'select $1.' || quote_ident(v_attribute)
        using v_record
        into v_sub;
    end if;
    if v_sub is not null then
      v_topic = replace(v_topic_template, '$1', v_sub);
    else
      v_topic = v_topic_template;
    end if;
    if v_topic is distinct from v_last_topic then
      -- This if statement prevents us from triggering the same notification twice
      v_last_topic = v_topic;
      perform pg_notify(v_topic, json_build_object(
        'event', v_event,
        'subject', v_sub
      )::text);
    end if;
  end loop;
  return v_record;
end;
$_$;


--
-- Name: FUNCTION tg__graphql_subscription(); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.tg__graphql_subscription() IS 'This function enables the creation of simple focussed GraphQL subscriptions using database triggers. Read more here: https://www.graphile.org/postgraphile/subscriptions/#custom-subscriptions';


--
-- Name: tg_user_emails__forbid_if_verified(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.tg_user_emails__forbid_if_verified() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'app_public', 'app_private', 'app_hidden', 'public'
    AS $$
begin
  if exists(select 1 from app_public.user_emails where email = NEW.email and is_verified is true) then
    raise exception 'An account using that email address has already been created.' using errcode='EMTKN';
  end if;
  return NEW;
end;
$$;


--
-- Name: tg_user_emails__verify_account_on_verified(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.tg_user_emails__verify_account_on_verified() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  update app_public.user set is_verified = true where id = new.user_id and is_verified is false;
  return new;
end;
$$;


--
-- Name: user_has_password(app_public."user"); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.user_has_password(u app_public."user") RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  select (password_hash is not null) from app_private.user_secrets where user_secrets.user_id = u.id and u.id = app_public.current_user_id();
$$;


--
-- Name: verify_email(uuid, text); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.verify_email(user_email_id uuid, token text) RETURNS boolean
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    AS $$
begin
  update app_public.user_emails
  set
    is_verified = true,
    is_primary = is_primary or not exists(
      select 1 from app_public.user_emails other_email where other_email.user_id = user_emails.user_id and other_email.is_primary is true
    )
  where id = user_email_id
  and exists(
    select 1 from app_private.user_email_secrets where user_email_secrets.user_email_id = user_emails.id and verification_token = token
  );
  return found;
end;
$$;


--
-- Name: FUNCTION verify_email(user_email_id uuid, token text); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.verify_email(user_email_id uuid, token text) IS 'Once you have received a verification token for your email, you may call this mutation with that token to make your email verified.';


--
-- Name: connect_pg_simple_sessions; Type: TABLE; Schema: app_private; Owner: -
--

CREATE TABLE app_private.connect_pg_simple_sessions (
    sid uuid NOT NULL,
    sess json NOT NULL,
    expire timestamp without time zone NOT NULL
);


--
-- Name: unregistered_email_password_resets; Type: TABLE; Schema: app_private; Owner: -
--

CREATE TABLE app_private.unregistered_email_password_resets (
    email public.citext NOT NULL,
    attempts integer DEFAULT 1 NOT NULL,
    latest_attempt timestamp with time zone NOT NULL
);


--
-- Name: TABLE unregistered_email_password_resets; Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON TABLE app_private.unregistered_email_password_resets IS 'If someone tries to recover the password for an email that is not registered in our system, this table enables us to rate-limit outgoing emails to avoid spamming.';


--
-- Name: COLUMN unregistered_email_password_resets.attempts; Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON COLUMN app_private.unregistered_email_password_resets.attempts IS 'We store the number of attempts to help us detect accounts being attacked.';


--
-- Name: COLUMN unregistered_email_password_resets.latest_attempt; Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON COLUMN app_private.unregistered_email_password_resets.latest_attempt IS 'We store the time the last password reset was sent to this email to prevent the email getting flooded.';


--
-- Name: user_authentication_secrets; Type: TABLE; Schema: app_private; Owner: -
--

CREATE TABLE app_private.user_authentication_secrets (
    user_authentication_id uuid NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: user_email_secrets; Type: TABLE; Schema: app_private; Owner: -
--

CREATE TABLE app_private.user_email_secrets (
    user_email_id uuid NOT NULL,
    verification_token text,
    verification_email_sent_at timestamp with time zone,
    password_reset_email_sent_at timestamp with time zone
);


--
-- Name: TABLE user_email_secrets; Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON TABLE app_private.user_email_secrets IS 'The contents of this table should never be visible to the user. Contains data mostly related to email verification and avoiding spamming user.';


--
-- Name: COLUMN user_email_secrets.password_reset_email_sent_at; Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON COLUMN app_private.user_email_secrets.password_reset_email_sent_at IS 'We store the time the last password reset was sent to this email to prevent the email getting flooded.';


--
-- Name: user_secrets; Type: TABLE; Schema: app_private; Owner: -
--

CREATE TABLE app_private.user_secrets (
    user_id uuid NOT NULL,
    password_hash text,
    last_login_at timestamp with time zone DEFAULT now() NOT NULL,
    failed_password_attempts integer DEFAULT 0 NOT NULL,
    first_failed_password_attempt timestamp with time zone,
    reset_password_token text,
    reset_password_token_generated timestamp with time zone,
    failed_reset_password_attempts integer DEFAULT 0 NOT NULL,
    first_failed_reset_password_attempt timestamp with time zone,
    delete_account_token text,
    delete_account_token_generated timestamp with time zone
);


--
-- Name: TABLE user_secrets; Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON TABLE app_private.user_secrets IS 'The contents of this table should never be visible to the user. Contains data mostly related to authentication.';


--
-- Name: account_balance; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.account_balance (
    id uuid DEFAULT public.uuid_generate_v1() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    credit_vintage_id uuid,
    wallet_id uuid,
    liquid_balance integer,
    burnt_balance integer
);


--
-- Name: credit_class; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.credit_class (
    id uuid DEFAULT public.uuid_generate_v1() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    designer_id uuid,
    methodology_id uuid NOT NULL
);


--
-- Name: credit_class_issuer; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.credit_class_issuer (
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    credit_class_id uuid NOT NULL,
    issuer_id uuid NOT NULL
);


--
-- Name: credit_class_version; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.credit_class_version (
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    name text NOT NULL,
    version text NOT NULL,
    date_developed timestamp with time zone NOT NULL,
    description text,
    state_machine jsonb NOT NULL,
    metadata jsonb
);


--
-- Name: credit_vintage; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.credit_vintage (
    id uuid DEFAULT public.uuid_generate_v1() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    credit_class_id uuid,
    project_id uuid,
    issuer_id uuid,
    units integer,
    initial_distribution jsonb
);


--
-- Name: event; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.event (
    id uuid DEFAULT public.uuid_generate_v1() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    project_id uuid NOT NULL,
    date timestamp with time zone,
    summary character(160) NOT NULL,
    description text,
    from_state app_public.project_state,
    to_state app_public.project_state
);


--
-- Name: methodology; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.methodology (
    id uuid DEFAULT public.uuid_generate_v1() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    author_id uuid NOT NULL
);


--
-- Name: methodology_version; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.methodology_version (
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    name text NOT NULL,
    version text NOT NULL,
    date_developed timestamp with time zone NOT NULL,
    description text,
    boundary public.geometry NOT NULL,
    metadata jsonb,
    files jsonb
);


--
-- Name: mrv; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.mrv (
    id uuid DEFAULT public.uuid_generate_v1() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    project_id uuid
);


--
-- Name: organization; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.organization (
    id uuid DEFAULT public.uuid_generate_v1() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    type app_public.party_type DEFAULT 'organization'::app_public.party_type NOT NULL,
    owner_id uuid NOT NULL,
    name text NOT NULL,
    logo text,
    website text,
    wallet_id uuid,
    party_id uuid,
    CONSTRAINT organization_type_check CHECK ((type = 'organization'::app_public.party_type))
);


--
-- Name: organization_member; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.organization_member (
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    member_id uuid NOT NULL,
    organization_id uuid NOT NULL
);


--
-- Name: party; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.party (
    id uuid DEFAULT public.uuid_generate_v1() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    type app_public.party_type NOT NULL,
    address public.geometry,
    short_description character(130),
    CONSTRAINT party_type_check CHECK ((type = ANY (ARRAY['user'::app_public.party_type, 'organization'::app_public.party_type])))
);


--
-- Name: project; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.project (
    id uuid DEFAULT public.uuid_generate_v1() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    developer_id uuid,
    steward_id uuid,
    land_owner_id uuid,
    credit_class_id uuid NOT NULL,
    name text NOT NULL,
    location public.geometry NOT NULL,
    application_date timestamp with time zone NOT NULL,
    start_date timestamp with time zone NOT NULL,
    end_date timestamp with time zone NOT NULL,
    summary_description character(160) NOT NULL,
    long_description text NOT NULL,
    photos text[] NOT NULL,
    documents jsonb,
    area integer NOT NULL,
    area_unit character(10) NOT NULL,
    state app_public.project_state NOT NULL,
    last_event_index integer,
    impact jsonb,
    metadata jsonb,
    registry_id uuid,
    CONSTRAINT check_project CHECK (((developer_id IS NOT NULL) OR (land_owner_id IS NOT NULL) OR (steward_id IS NOT NULL)))
);


--
-- Name: registry; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.registry (
    id uuid DEFAULT public.uuid_generate_v1() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    name text NOT NULL
);


--
-- Name: user_authentications; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.user_authentications (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    service text NOT NULL,
    identifier text NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE user_authentications; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON TABLE app_public.user_authentications IS 'Contains information about the login providers this user has used, so that they may disconnect them should they wish.';


--
-- Name: COLUMN user_authentications.service; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.user_authentications.service IS 'The login service used, e.g. `twitter` or `github`.';


--
-- Name: COLUMN user_authentications.identifier; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.user_authentications.identifier IS 'A unique identifier for the user within the login service.';


--
-- Name: COLUMN user_authentications.details; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.user_authentications.details IS 'Additional profile details extracted from this login method';


--
-- Name: wallet; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.wallet (
    id uuid DEFAULT public.uuid_generate_v1() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    addr bytea NOT NULL
);


--
-- Name: connect_pg_simple_sessions session_pkey; Type: CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.connect_pg_simple_sessions
    ADD CONSTRAINT session_pkey PRIMARY KEY (sid);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (uuid);


--
-- Name: unregistered_email_password_resets unregistered_email_pkey; Type: CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.unregistered_email_password_resets
    ADD CONSTRAINT unregistered_email_pkey PRIMARY KEY (email);


--
-- Name: user_authentication_secrets user_authentication_secrets_pkey; Type: CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.user_authentication_secrets
    ADD CONSTRAINT user_authentication_secrets_pkey PRIMARY KEY (user_authentication_id);


--
-- Name: user_email_secrets user_email_secrets_pkey; Type: CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.user_email_secrets
    ADD CONSTRAINT user_email_secrets_pkey PRIMARY KEY (user_email_id);


--
-- Name: user_secrets user_secrets_pkey; Type: CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.user_secrets
    ADD CONSTRAINT user_secrets_pkey PRIMARY KEY (user_id);


--
-- Name: account_balance account_balance_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.account_balance
    ADD CONSTRAINT account_balance_pkey PRIMARY KEY (id);


--
-- Name: credit_class credit_class_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.credit_class
    ADD CONSTRAINT credit_class_pkey PRIMARY KEY (id);


--
-- Name: credit_class_version credit_class_version_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.credit_class_version
    ADD CONSTRAINT credit_class_version_pkey PRIMARY KEY (id, created_at);


--
-- Name: credit_vintage credit_vintage_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.credit_vintage
    ADD CONSTRAINT credit_vintage_pkey PRIMARY KEY (id);


--
-- Name: event event_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.event
    ADD CONSTRAINT event_pkey PRIMARY KEY (id);


--
-- Name: methodology methodology_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.methodology
    ADD CONSTRAINT methodology_pkey PRIMARY KEY (id);


--
-- Name: methodology_version methodology_version_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.methodology_version
    ADD CONSTRAINT methodology_version_pkey PRIMARY KEY (id, created_at);


--
-- Name: mrv mrv_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.mrv
    ADD CONSTRAINT mrv_pkey PRIMARY KEY (id);


--
-- Name: organization organization_party_id_type_key; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization
    ADD CONSTRAINT organization_party_id_type_key UNIQUE (party_id, type);


--
-- Name: organization organization_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization
    ADD CONSTRAINT organization_pkey PRIMARY KEY (id);


--
-- Name: party party_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.party
    ADD CONSTRAINT party_pkey PRIMARY KEY (id);


--
-- Name: project project_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.project
    ADD CONSTRAINT project_pkey PRIMARY KEY (id);


--
-- Name: registry registry_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.registry
    ADD CONSTRAINT registry_pkey PRIMARY KEY (id);


--
-- Name: user_authentications uniq_user_authentications; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.user_authentications
    ADD CONSTRAINT uniq_user_authentications UNIQUE (service, identifier);


--
-- Name: user_authentications user_authentications_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.user_authentications
    ADD CONSTRAINT user_authentications_pkey PRIMARY KEY (id);


--
-- Name: user_emails user_emails_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.user_emails
    ADD CONSTRAINT user_emails_pkey PRIMARY KEY (id);


--
-- Name: user_emails user_emails_user_id_email_key; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.user_emails
    ADD CONSTRAINT user_emails_user_id_email_key UNIQUE (user_id, email);


--
-- Name: user user_party_id_type_key; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public."user"
    ADD CONSTRAINT user_party_id_type_key UNIQUE (party_id, type);


--
-- Name: user user_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (id);


--
-- Name: user user_username_key; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public."user"
    ADD CONSTRAINT user_username_key UNIQUE (username);


--
-- Name: wallet wallet_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.wallet
    ADD CONSTRAINT wallet_pkey PRIMARY KEY (id);


--
-- Name: account_balance_credit_vintage_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX account_balance_credit_vintage_id_idx ON app_public.account_balance USING btree (credit_vintage_id);


--
-- Name: account_balance_wallet_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX account_balance_wallet_id_idx ON app_public.account_balance USING btree (wallet_id);


--
-- Name: credit_class_designer_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX credit_class_designer_id_idx ON app_public.credit_class USING btree (designer_id);


--
-- Name: credit_class_issuer_credit_class_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX credit_class_issuer_credit_class_id_idx ON app_public.credit_class_issuer USING btree (credit_class_id);


--
-- Name: credit_class_issuer_issuer_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX credit_class_issuer_issuer_id_idx ON app_public.credit_class_issuer USING btree (issuer_id);


--
-- Name: credit_class_methodology_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX credit_class_methodology_id_idx ON app_public.credit_class USING btree (methodology_id);


--
-- Name: credit_vintage_credit_class_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX credit_vintage_credit_class_id_idx ON app_public.credit_vintage USING btree (credit_class_id);


--
-- Name: credit_vintage_issuer_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX credit_vintage_issuer_id_idx ON app_public.credit_vintage USING btree (issuer_id);


--
-- Name: credit_vintage_project_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX credit_vintage_project_id_idx ON app_public.credit_vintage USING btree (project_id);


--
-- Name: event_project_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX event_project_id_idx ON app_public.event USING btree (project_id);


--
-- Name: idx_user_emails_primary; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX idx_user_emails_primary ON app_public.user_emails USING btree (is_primary, user_id);


--
-- Name: methodology_author_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX methodology_author_id_idx ON app_public.methodology USING btree (author_id);


--
-- Name: mrv_project_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX mrv_project_id_idx ON app_public.mrv USING btree (project_id);


--
-- Name: organization_member_member_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX organization_member_member_id_idx ON app_public.organization_member USING btree (member_id);


--
-- Name: organization_member_organization_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX organization_member_organization_id_idx ON app_public.organization_member USING btree (organization_id);


--
-- Name: organization_owner_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX organization_owner_id_idx ON app_public.organization USING btree (owner_id);


--
-- Name: organization_wallet_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX organization_wallet_id_idx ON app_public.organization USING btree (wallet_id);


--
-- Name: project_credit_class_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX project_credit_class_id_idx ON app_public.project USING btree (credit_class_id);


--
-- Name: project_developer_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX project_developer_id_idx ON app_public.project USING btree (developer_id);


--
-- Name: project_land_owner_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX project_land_owner_id_idx ON app_public.project USING btree (land_owner_id);


--
-- Name: project_registry_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX project_registry_id_idx ON app_public.project USING btree (registry_id);


--
-- Name: project_steward_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX project_steward_id_idx ON app_public.project USING btree (steward_id);


--
-- Name: uniq_user_emails_primary_email; Type: INDEX; Schema: app_public; Owner: -
--

CREATE UNIQUE INDEX uniq_user_emails_primary_email ON app_public.user_emails USING btree (user_id) WHERE (is_primary IS TRUE);


--
-- Name: uniq_user_emails_verified_email; Type: INDEX; Schema: app_public; Owner: -
--

CREATE UNIQUE INDEX uniq_user_emails_verified_email ON app_public.user_emails USING btree (email) WHERE (is_verified IS TRUE);


--
-- Name: user_authentications_user_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX user_authentications_user_id_idx ON app_public.user_authentications USING btree (user_id);


--
-- Name: user_wallet_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX user_wallet_id_idx ON app_public."user" USING btree (wallet_id);


--
-- Name: user _100_timestamps; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _100_timestamps BEFORE INSERT OR UPDATE ON app_public."user" FOR EACH ROW EXECUTE PROCEDURE app_private.tg__timestamps();


--
-- Name: user_authentications _100_timestamps; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _100_timestamps BEFORE INSERT OR UPDATE ON app_public.user_authentications FOR EACH ROW EXECUTE PROCEDURE app_private.tg__timestamps();


--
-- Name: user_emails _100_timestamps; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _100_timestamps BEFORE INSERT OR UPDATE ON app_public.user_emails FOR EACH ROW EXECUTE PROCEDURE app_private.tg__timestamps();


--
-- Name: user_emails _200_forbid_existing_email; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _200_forbid_existing_email BEFORE INSERT ON app_public.user_emails FOR EACH ROW EXECUTE PROCEDURE app_public.tg_user_emails__forbid_if_verified();


--
-- Name: user _500_gql_update; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _500_gql_update AFTER UPDATE ON app_public."user" FOR EACH ROW EXECUTE PROCEDURE app_public.tg__graphql_subscription('userChanged', 'graphql:user:$1', 'id');


--
-- Name: user _500_insert_secrets; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _500_insert_secrets AFTER INSERT ON app_public."user" FOR EACH ROW EXECUTE PROCEDURE app_private.tg_user_secrets__insert_with_user();


--
-- Name: user_emails _500_insert_secrets; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _500_insert_secrets AFTER INSERT ON app_public.user_emails FOR EACH ROW EXECUTE PROCEDURE app_private.tg_user_email_secrets__insert_with_user_email();


--
-- Name: user_emails _500_verify_account_on_verified; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _500_verify_account_on_verified AFTER INSERT OR UPDATE OF is_verified ON app_public.user_emails FOR EACH ROW WHEN ((new.is_verified IS TRUE)) EXECUTE PROCEDURE app_public.tg_user_emails__verify_account_on_verified();


--
-- Name: user_emails _900_send_verification_email; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _900_send_verification_email AFTER INSERT ON app_public.user_emails FOR EACH ROW WHEN ((new.is_verified IS FALSE)) EXECUTE PROCEDURE app_private.tg__add_job('user_emails__send_verification');


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES app_public."user"(id) ON DELETE CASCADE;


--
-- Name: user_authentication_secrets user_authentication_secrets_user_authentication_id_fkey; Type: FK CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.user_authentication_secrets
    ADD CONSTRAINT user_authentication_secrets_user_authentication_id_fkey FOREIGN KEY (user_authentication_id) REFERENCES app_public.user_authentications(id) ON DELETE CASCADE;


--
-- Name: user_email_secrets user_email_secrets_user_email_id_fkey; Type: FK CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.user_email_secrets
    ADD CONSTRAINT user_email_secrets_user_email_id_fkey FOREIGN KEY (user_email_id) REFERENCES app_public.user_emails(id) ON DELETE CASCADE;


--
-- Name: user_secrets user_secrets_user_id_fkey; Type: FK CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.user_secrets
    ADD CONSTRAINT user_secrets_user_id_fkey FOREIGN KEY (user_id) REFERENCES app_public."user"(id) ON DELETE CASCADE;


--
-- Name: account_balance account_balance_credit_vintage_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.account_balance
    ADD CONSTRAINT account_balance_credit_vintage_id_fkey FOREIGN KEY (credit_vintage_id) REFERENCES app_public.credit_vintage(id);


--
-- Name: account_balance account_balance_wallet_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.account_balance
    ADD CONSTRAINT account_balance_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES app_public.wallet(id);


--
-- Name: credit_class credit_class_designer_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.credit_class
    ADD CONSTRAINT credit_class_designer_id_fkey FOREIGN KEY (designer_id) REFERENCES app_public.party(id);


--
-- Name: credit_class_issuer credit_class_issuer_credit_class_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.credit_class_issuer
    ADD CONSTRAINT credit_class_issuer_credit_class_id_fkey FOREIGN KEY (credit_class_id) REFERENCES app_public.credit_class(id);


--
-- Name: credit_class_issuer credit_class_issuer_issuer_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.credit_class_issuer
    ADD CONSTRAINT credit_class_issuer_issuer_id_fkey FOREIGN KEY (issuer_id) REFERENCES app_public.wallet(id);


--
-- Name: credit_class credit_class_methodology_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.credit_class
    ADD CONSTRAINT credit_class_methodology_id_fkey FOREIGN KEY (methodology_id) REFERENCES app_public.methodology(id);


--
-- Name: credit_class_version credit_class_version_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.credit_class_version
    ADD CONSTRAINT credit_class_version_id_fkey FOREIGN KEY (id) REFERENCES app_public.credit_class(id);


--
-- Name: credit_vintage credit_vintage_credit_class_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.credit_vintage
    ADD CONSTRAINT credit_vintage_credit_class_id_fkey FOREIGN KEY (credit_class_id) REFERENCES app_public.credit_class(id);


--
-- Name: credit_vintage credit_vintage_issuer_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.credit_vintage
    ADD CONSTRAINT credit_vintage_issuer_id_fkey FOREIGN KEY (issuer_id) REFERENCES app_public.wallet(id);


--
-- Name: credit_vintage credit_vintage_project_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.credit_vintage
    ADD CONSTRAINT credit_vintage_project_id_fkey FOREIGN KEY (project_id) REFERENCES app_public.project(id);


--
-- Name: event event_project_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.event
    ADD CONSTRAINT event_project_id_fkey FOREIGN KEY (project_id) REFERENCES app_public.project(id);


--
-- Name: methodology methodology_author_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.methodology
    ADD CONSTRAINT methodology_author_id_fkey FOREIGN KEY (author_id) REFERENCES app_public.party(id);


--
-- Name: methodology_version methodology_version_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.methodology_version
    ADD CONSTRAINT methodology_version_id_fkey FOREIGN KEY (id) REFERENCES app_public.methodology(id);


--
-- Name: mrv mrv_project_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.mrv
    ADD CONSTRAINT mrv_project_id_fkey FOREIGN KEY (project_id) REFERENCES app_public.project(id);


--
-- Name: organization_member organization_member_member_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization_member
    ADD CONSTRAINT organization_member_member_id_fkey FOREIGN KEY (member_id) REFERENCES app_public."user"(id);


--
-- Name: organization_member organization_member_organization_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization_member
    ADD CONSTRAINT organization_member_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES app_public.organization(id);


--
-- Name: organization organization_owner_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization
    ADD CONSTRAINT organization_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES app_public."user"(id);


--
-- Name: organization organization_party_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization
    ADD CONSTRAINT organization_party_id_fkey FOREIGN KEY (party_id) REFERENCES app_public.party(id);


--
-- Name: organization organization_wallet_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization
    ADD CONSTRAINT organization_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES app_public.wallet(id);


--
-- Name: project project_credit_class_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.project
    ADD CONSTRAINT project_credit_class_id_fkey FOREIGN KEY (credit_class_id) REFERENCES app_public.credit_class(id);


--
-- Name: project project_developer_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.project
    ADD CONSTRAINT project_developer_id_fkey FOREIGN KEY (developer_id) REFERENCES app_public.party(id);


--
-- Name: project project_land_owner_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.project
    ADD CONSTRAINT project_land_owner_id_fkey FOREIGN KEY (land_owner_id) REFERENCES app_public.party(id);


--
-- Name: project project_registry_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.project
    ADD CONSTRAINT project_registry_id_fkey FOREIGN KEY (registry_id) REFERENCES app_public.registry(id);


--
-- Name: project project_steward_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.project
    ADD CONSTRAINT project_steward_id_fkey FOREIGN KEY (steward_id) REFERENCES app_public.party(id);


--
-- Name: user_authentications user_authentications_user_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.user_authentications
    ADD CONSTRAINT user_authentications_user_id_fkey FOREIGN KEY (user_id) REFERENCES app_public."user"(id) ON DELETE CASCADE;


--
-- Name: user_emails user_emails_user_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.user_emails
    ADD CONSTRAINT user_emails_user_id_fkey FOREIGN KEY (user_id) REFERENCES app_public."user"(id) ON DELETE CASCADE;


--
-- Name: user user_party_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public."user"
    ADD CONSTRAINT user_party_id_fkey FOREIGN KEY (party_id) REFERENCES app_public.party(id);


--
-- Name: user user_wallet_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public."user"
    ADD CONSTRAINT user_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES app_public.wallet(id);


--
-- Name: connect_pg_simple_sessions; Type: ROW SECURITY; Schema: app_private; Owner: -
--

ALTER TABLE app_private.connect_pg_simple_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: sessions; Type: ROW SECURITY; Schema: app_private; Owner: -
--

ALTER TABLE app_private.sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: user_authentication_secrets; Type: ROW SECURITY; Schema: app_private; Owner: -
--

ALTER TABLE app_private.user_authentication_secrets ENABLE ROW LEVEL SECURITY;

--
-- Name: user_email_secrets; Type: ROW SECURITY; Schema: app_private; Owner: -
--

ALTER TABLE app_private.user_email_secrets ENABLE ROW LEVEL SECURITY;

--
-- Name: user_secrets; Type: ROW SECURITY; Schema: app_private; Owner: -
--

ALTER TABLE app_private.user_secrets ENABLE ROW LEVEL SECURITY;

--
-- Name: user_authentications delete_own; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY delete_own ON app_public.user_authentications FOR DELETE USING ((user_id = app_public.current_user_id()));


--
-- Name: user_emails delete_own; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY delete_own ON app_public.user_emails FOR DELETE USING ((user_id = app_public.current_user_id()));


--
-- Name: user delete_self; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY delete_self ON app_public."user" FOR DELETE USING ((id = app_public.current_user_id()));


--
-- Name: user_emails insert_own; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY insert_own ON app_public.user_emails FOR INSERT WITH CHECK ((user_id = app_public.current_user_id()));


--
-- Name: user select_all; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY select_all ON app_public."user" FOR SELECT USING (true);


--
-- Name: user_authentications select_own; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY select_own ON app_public.user_authentications FOR SELECT USING ((user_id = app_public.current_user_id()));


--
-- Name: user_emails select_own; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY select_own ON app_public.user_emails FOR SELECT USING ((user_id = app_public.current_user_id()));


--
-- Name: user update_self; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY update_self ON app_public."user" FOR UPDATE USING ((id = app_public.current_user_id()));


--
-- Name: user; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public."user" ENABLE ROW LEVEL SECURITY;

--
-- Name: user_authentications; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public.user_authentications ENABLE ROW LEVEL SECURITY;

--
-- Name: user_emails; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public.user_emails ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA app_hidden; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA app_hidden TO regen_registry_visitor;


--
-- Name: SCHEMA app_public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA app_public TO regen_registry_visitor;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO regen_registry;
GRANT USAGE ON SCHEMA public TO regen_registry_visitor;


--
-- Name: FUNCTION assert_valid_password(new_password text); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.assert_valid_password(new_password text) FROM PUBLIC;


--
-- Name: TABLE "user"; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT ON TABLE app_public."user" TO regen_registry_visitor;


--
-- Name: COLUMN "user".username; Type: ACL; Schema: app_public; Owner: -
--

GRANT UPDATE(username) ON TABLE app_public."user" TO regen_registry_visitor;


--
-- Name: COLUMN "user".first_name; Type: ACL; Schema: app_public; Owner: -
--

GRANT UPDATE(first_name) ON TABLE app_public."user" TO regen_registry_visitor;


--
-- Name: COLUMN "user".last_name; Type: ACL; Schema: app_public; Owner: -
--

GRANT UPDATE(last_name) ON TABLE app_public."user" TO regen_registry_visitor;


--
-- Name: COLUMN "user".avatar_url; Type: ACL; Schema: app_public; Owner: -
--

GRANT UPDATE(avatar_url) ON TABLE app_public."user" TO regen_registry_visitor;


--
-- Name: COLUMN "user".wallet_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT UPDATE(wallet_id) ON TABLE app_public."user" TO regen_registry_visitor;


--
-- Name: COLUMN "user".party_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT UPDATE(party_id) ON TABLE app_public."user" TO regen_registry_visitor;


--
-- Name: COLUMN "user".type; Type: ACL; Schema: app_public; Owner: -
--

GRANT UPDATE(type) ON TABLE app_public."user" TO regen_registry_visitor;


--
-- Name: FUNCTION link_or_register_user(f_user_id uuid, f_service character varying, f_identifier character varying, f_profile json, f_auth_details json); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.link_or_register_user(f_user_id uuid, f_service character varying, f_identifier character varying, f_profile json, f_auth_details json) FROM PUBLIC;


--
-- Name: FUNCTION login(username public.citext, password text); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.login(username public.citext, password text) FROM PUBLIC;


--
-- Name: FUNCTION really_create_user(username public.citext, email text, email_is_verified boolean, first_name text, last_name text, avatar_url text, password text); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.really_create_user(username public.citext, email text, email_is_verified boolean, first_name text, last_name text, avatar_url text, password text) FROM PUBLIC;


--
-- Name: FUNCTION register_user(f_service character varying, f_identifier character varying, f_profile json, f_auth_details json, f_email_is_verified boolean); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.register_user(f_service character varying, f_identifier character varying, f_profile json, f_auth_details json, f_email_is_verified boolean) FROM PUBLIC;


--
-- Name: FUNCTION tg__add_job(); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.tg__add_job() FROM PUBLIC;


--
-- Name: FUNCTION tg__timestamps(); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.tg__timestamps() FROM PUBLIC;


--
-- Name: FUNCTION tg_user__make_first_user_admin(); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.tg_user__make_first_user_admin() FROM PUBLIC;


--
-- Name: FUNCTION tg_user_email_secrets__insert_with_user_email(); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.tg_user_email_secrets__insert_with_user_email() FROM PUBLIC;


--
-- Name: FUNCTION tg_user_secrets__insert_with_user(); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.tg_user_secrets__insert_with_user() FROM PUBLIC;


--
-- Name: FUNCTION change_password(old_password text, new_password text); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.change_password(old_password text, new_password text) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.change_password(old_password text, new_password text) TO regen_registry_visitor;


--
-- Name: FUNCTION confirm_account_deletion(token text); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.confirm_account_deletion(token text) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.confirm_account_deletion(token text) TO regen_registry_visitor;


--
-- Name: FUNCTION current_session_id(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.current_session_id() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.current_session_id() TO regen_registry_visitor;


--
-- Name: FUNCTION "current_user"(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public."current_user"() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public."current_user"() TO regen_registry_visitor;


--
-- Name: FUNCTION current_user_id(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.current_user_id() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.current_user_id() TO regen_registry_visitor;


--
-- Name: FUNCTION forgot_password(email public.citext); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.forgot_password(email public.citext) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.forgot_password(email public.citext) TO regen_registry_visitor;


--
-- Name: FUNCTION logout(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.logout() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.logout() TO regen_registry_visitor;


--
-- Name: TABLE user_emails; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.user_emails TO regen_registry_visitor;


--
-- Name: COLUMN user_emails.email; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(email) ON TABLE app_public.user_emails TO regen_registry_visitor;


--
-- Name: FUNCTION make_email_primary(email_id uuid); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.make_email_primary(email_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.make_email_primary(email_id uuid) TO regen_registry_visitor;


--
-- Name: FUNCTION request_account_deletion(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.request_account_deletion() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.request_account_deletion() TO regen_registry_visitor;


--
-- Name: FUNCTION resend_email_verification_code(email_id uuid); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.resend_email_verification_code(email_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.resend_email_verification_code(email_id uuid) TO regen_registry_visitor;


--
-- Name: FUNCTION reset_password(user_id uuid, reset_token text, new_password text); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.reset_password(user_id uuid, reset_token text, new_password text) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.reset_password(user_id uuid, reset_token text, new_password text) TO regen_registry_visitor;


--
-- Name: FUNCTION tg__graphql_subscription(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.tg__graphql_subscription() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.tg__graphql_subscription() TO regen_registry_visitor;


--
-- Name: FUNCTION tg_user_emails__forbid_if_verified(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.tg_user_emails__forbid_if_verified() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.tg_user_emails__forbid_if_verified() TO regen_registry_visitor;


--
-- Name: FUNCTION tg_user_emails__verify_account_on_verified(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.tg_user_emails__verify_account_on_verified() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.tg_user_emails__verify_account_on_verified() TO regen_registry_visitor;


--
-- Name: FUNCTION user_has_password(u app_public."user"); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.user_has_password(u app_public."user") FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.user_has_password(u app_public."user") TO regen_registry_visitor;


--
-- Name: FUNCTION verify_email(user_email_id uuid, token text); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.verify_email(user_email_id uuid, token text) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.verify_email(user_email_id uuid, token text) TO regen_registry_visitor;


--
-- Name: TABLE account_balance; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.account_balance TO regen_registry_visitor;


--
-- Name: COLUMN account_balance.updated_at; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(updated_at),UPDATE(updated_at) ON TABLE app_public.account_balance TO regen_registry_visitor;


--
-- Name: COLUMN account_balance.credit_vintage_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(credit_vintage_id),UPDATE(credit_vintage_id) ON TABLE app_public.account_balance TO regen_registry_visitor;


--
-- Name: COLUMN account_balance.wallet_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(wallet_id),UPDATE(wallet_id) ON TABLE app_public.account_balance TO regen_registry_visitor;


--
-- Name: COLUMN account_balance.liquid_balance; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(liquid_balance),UPDATE(liquid_balance) ON TABLE app_public.account_balance TO regen_registry_visitor;


--
-- Name: COLUMN account_balance.burnt_balance; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(burnt_balance),UPDATE(burnt_balance) ON TABLE app_public.account_balance TO regen_registry_visitor;


--
-- Name: TABLE credit_class; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.credit_class TO regen_registry_visitor;


--
-- Name: COLUMN credit_class.updated_at; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(updated_at),UPDATE(updated_at) ON TABLE app_public.credit_class TO regen_registry_visitor;


--
-- Name: COLUMN credit_class.designer_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(designer_id),UPDATE(designer_id) ON TABLE app_public.credit_class TO regen_registry_visitor;


--
-- Name: COLUMN credit_class.methodology_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(methodology_id),UPDATE(methodology_id) ON TABLE app_public.credit_class TO regen_registry_visitor;


--
-- Name: TABLE credit_class_issuer; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.credit_class_issuer TO regen_registry_visitor;


--
-- Name: COLUMN credit_class_issuer.updated_at; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(updated_at),UPDATE(updated_at) ON TABLE app_public.credit_class_issuer TO regen_registry_visitor;


--
-- Name: COLUMN credit_class_issuer.credit_class_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(credit_class_id),UPDATE(credit_class_id) ON TABLE app_public.credit_class_issuer TO regen_registry_visitor;


--
-- Name: COLUMN credit_class_issuer.issuer_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(issuer_id),UPDATE(issuer_id) ON TABLE app_public.credit_class_issuer TO regen_registry_visitor;


--
-- Name: TABLE credit_class_version; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.credit_class_version TO regen_registry_visitor;


--
-- Name: COLUMN credit_class_version.name; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(name),UPDATE(name) ON TABLE app_public.credit_class_version TO regen_registry_visitor;


--
-- Name: COLUMN credit_class_version.version; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(version),UPDATE(version) ON TABLE app_public.credit_class_version TO regen_registry_visitor;


--
-- Name: COLUMN credit_class_version.date_developed; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(date_developed),UPDATE(date_developed) ON TABLE app_public.credit_class_version TO regen_registry_visitor;


--
-- Name: COLUMN credit_class_version.description; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(description),UPDATE(description) ON TABLE app_public.credit_class_version TO regen_registry_visitor;


--
-- Name: COLUMN credit_class_version.state_machine; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(state_machine),UPDATE(state_machine) ON TABLE app_public.credit_class_version TO regen_registry_visitor;


--
-- Name: COLUMN credit_class_version.metadata; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(metadata),UPDATE(metadata) ON TABLE app_public.credit_class_version TO regen_registry_visitor;


--
-- Name: TABLE credit_vintage; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.credit_vintage TO regen_registry_visitor;


--
-- Name: COLUMN credit_vintage.credit_class_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(credit_class_id),UPDATE(credit_class_id) ON TABLE app_public.credit_vintage TO regen_registry_visitor;


--
-- Name: COLUMN credit_vintage.project_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(project_id),UPDATE(project_id) ON TABLE app_public.credit_vintage TO regen_registry_visitor;


--
-- Name: COLUMN credit_vintage.issuer_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(issuer_id),UPDATE(issuer_id) ON TABLE app_public.credit_vintage TO regen_registry_visitor;


--
-- Name: COLUMN credit_vintage.units; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(units),UPDATE(units) ON TABLE app_public.credit_vintage TO regen_registry_visitor;


--
-- Name: COLUMN credit_vintage.initial_distribution; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(initial_distribution),UPDATE(initial_distribution) ON TABLE app_public.credit_vintage TO regen_registry_visitor;


--
-- Name: TABLE event; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.event TO regen_registry_visitor;


--
-- Name: COLUMN event.updated_at; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(updated_at),UPDATE(updated_at) ON TABLE app_public.event TO regen_registry_visitor;


--
-- Name: COLUMN event.project_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(project_id),UPDATE(project_id) ON TABLE app_public.event TO regen_registry_visitor;


--
-- Name: COLUMN event.date; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(date),UPDATE(date) ON TABLE app_public.event TO regen_registry_visitor;


--
-- Name: COLUMN event.summary; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(summary),UPDATE(summary) ON TABLE app_public.event TO regen_registry_visitor;


--
-- Name: COLUMN event.description; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(description),UPDATE(description) ON TABLE app_public.event TO regen_registry_visitor;


--
-- Name: COLUMN event.from_state; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(from_state),UPDATE(from_state) ON TABLE app_public.event TO regen_registry_visitor;


--
-- Name: COLUMN event.to_state; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(to_state),UPDATE(to_state) ON TABLE app_public.event TO regen_registry_visitor;


--
-- Name: TABLE methodology; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.methodology TO regen_registry_visitor;


--
-- Name: COLUMN methodology.updated_at; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(updated_at),UPDATE(updated_at) ON TABLE app_public.methodology TO regen_registry_visitor;


--
-- Name: COLUMN methodology.author_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(author_id),UPDATE(author_id) ON TABLE app_public.methodology TO regen_registry_visitor;


--
-- Name: TABLE methodology_version; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.methodology_version TO regen_registry_visitor;


--
-- Name: COLUMN methodology_version.name; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(name),UPDATE(name) ON TABLE app_public.methodology_version TO regen_registry_visitor;


--
-- Name: COLUMN methodology_version.version; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(version),UPDATE(version) ON TABLE app_public.methodology_version TO regen_registry_visitor;


--
-- Name: COLUMN methodology_version.date_developed; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(date_developed),UPDATE(date_developed) ON TABLE app_public.methodology_version TO regen_registry_visitor;


--
-- Name: COLUMN methodology_version.description; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(description),UPDATE(description) ON TABLE app_public.methodology_version TO regen_registry_visitor;


--
-- Name: COLUMN methodology_version.boundary; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(boundary),UPDATE(boundary) ON TABLE app_public.methodology_version TO regen_registry_visitor;


--
-- Name: COLUMN methodology_version.metadata; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(metadata),UPDATE(metadata) ON TABLE app_public.methodology_version TO regen_registry_visitor;


--
-- Name: COLUMN methodology_version.files; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(files),UPDATE(files) ON TABLE app_public.methodology_version TO regen_registry_visitor;


--
-- Name: TABLE mrv; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.mrv TO regen_registry_visitor;


--
-- Name: COLUMN mrv.updated_at; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(updated_at),UPDATE(updated_at) ON TABLE app_public.mrv TO regen_registry_visitor;


--
-- Name: COLUMN mrv.project_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(project_id),UPDATE(project_id) ON TABLE app_public.mrv TO regen_registry_visitor;


--
-- Name: TABLE organization; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.organization TO regen_registry_visitor;


--
-- Name: COLUMN organization.updated_at; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(updated_at),UPDATE(updated_at) ON TABLE app_public.organization TO regen_registry_visitor;


--
-- Name: COLUMN organization.type; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(type),UPDATE(type) ON TABLE app_public.organization TO regen_registry_visitor;


--
-- Name: COLUMN organization.owner_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(owner_id),UPDATE(owner_id) ON TABLE app_public.organization TO regen_registry_visitor;


--
-- Name: COLUMN organization.name; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(name),UPDATE(name) ON TABLE app_public.organization TO regen_registry_visitor;


--
-- Name: COLUMN organization.logo; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(logo),UPDATE(logo) ON TABLE app_public.organization TO regen_registry_visitor;


--
-- Name: COLUMN organization.website; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(website),UPDATE(website) ON TABLE app_public.organization TO regen_registry_visitor;


--
-- Name: COLUMN organization.wallet_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(wallet_id),UPDATE(wallet_id) ON TABLE app_public.organization TO regen_registry_visitor;


--
-- Name: TABLE organization_member; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.organization_member TO regen_registry_visitor;


--
-- Name: COLUMN organization_member.updated_at; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(updated_at),UPDATE(updated_at) ON TABLE app_public.organization_member TO regen_registry_visitor;


--
-- Name: COLUMN organization_member.member_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(member_id),UPDATE(member_id) ON TABLE app_public.organization_member TO regen_registry_visitor;


--
-- Name: COLUMN organization_member.organization_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(organization_id),UPDATE(organization_id) ON TABLE app_public.organization_member TO regen_registry_visitor;


--
-- Name: TABLE party; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.party TO regen_registry_visitor;


--
-- Name: COLUMN party.updated_at; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(updated_at),UPDATE(updated_at) ON TABLE app_public.party TO regen_registry_visitor;


--
-- Name: COLUMN party.type; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(type),UPDATE(type) ON TABLE app_public.party TO regen_registry_visitor;


--
-- Name: COLUMN party.address; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(address),UPDATE(address) ON TABLE app_public.party TO regen_registry_visitor;


--
-- Name: COLUMN party.short_description; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(short_description),UPDATE(short_description) ON TABLE app_public.party TO regen_registry_visitor;


--
-- Name: TABLE project; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.updated_at; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(updated_at),UPDATE(updated_at) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.developer_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(developer_id),UPDATE(developer_id) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.steward_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(steward_id),UPDATE(steward_id) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.land_owner_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(land_owner_id),UPDATE(land_owner_id) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.credit_class_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(credit_class_id),UPDATE(credit_class_id) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.name; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(name),UPDATE(name) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.location; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(location),UPDATE(location) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.application_date; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(application_date),UPDATE(application_date) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.start_date; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(start_date),UPDATE(start_date) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.end_date; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(end_date),UPDATE(end_date) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.summary_description; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(summary_description),UPDATE(summary_description) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.long_description; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(long_description),UPDATE(long_description) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.photos; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(photos),UPDATE(photos) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.documents; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(documents),UPDATE(documents) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.area; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(area),UPDATE(area) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.area_unit; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(area_unit),UPDATE(area_unit) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.state; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(state),UPDATE(state) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.last_event_index; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(last_event_index),UPDATE(last_event_index) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.impact; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(impact),UPDATE(impact) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.metadata; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(metadata),UPDATE(metadata) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: COLUMN project.registry_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(registry_id),UPDATE(registry_id) ON TABLE app_public.project TO regen_registry_visitor;


--
-- Name: TABLE registry; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.registry TO regen_registry_visitor;


--
-- Name: COLUMN registry.updated_at; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(updated_at),UPDATE(updated_at) ON TABLE app_public.registry TO regen_registry_visitor;


--
-- Name: COLUMN registry.name; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(name),UPDATE(name) ON TABLE app_public.registry TO regen_registry_visitor;


--
-- Name: TABLE user_authentications; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.user_authentications TO regen_registry_visitor;


--
-- Name: TABLE wallet; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.wallet TO regen_registry_visitor;


--
-- Name: COLUMN wallet.updated_at; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(updated_at),UPDATE(updated_at) ON TABLE app_public.wallet TO regen_registry_visitor;


--
-- Name: COLUMN wallet.addr; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(addr),UPDATE(addr) ON TABLE app_public.wallet TO regen_registry_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: app_hidden; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry IN SCHEMA app_hidden REVOKE ALL ON SEQUENCES  FROM regen_registry;
ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry IN SCHEMA app_hidden GRANT SELECT,USAGE ON SEQUENCES  TO regen_registry_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: app_hidden; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry IN SCHEMA app_hidden REVOKE ALL ON FUNCTIONS  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry IN SCHEMA app_hidden REVOKE ALL ON FUNCTIONS  FROM regen_registry;
ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry IN SCHEMA app_hidden GRANT ALL ON FUNCTIONS  TO regen_registry_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: app_public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry IN SCHEMA app_public REVOKE ALL ON SEQUENCES  FROM regen_registry;
ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry IN SCHEMA app_public GRANT SELECT,USAGE ON SEQUENCES  TO regen_registry_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: app_public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry IN SCHEMA app_public REVOKE ALL ON FUNCTIONS  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry IN SCHEMA app_public REVOKE ALL ON FUNCTIONS  FROM regen_registry;
ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry IN SCHEMA app_public GRANT ALL ON FUNCTIONS  TO regen_registry_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry IN SCHEMA public REVOKE ALL ON SEQUENCES  FROM regen_registry;
ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry IN SCHEMA public GRANT SELECT,USAGE ON SEQUENCES  TO regen_registry_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry IN SCHEMA public REVOKE ALL ON FUNCTIONS  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry IN SCHEMA public REVOKE ALL ON FUNCTIONS  FROM regen_registry;
ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry IN SCHEMA public GRANT ALL ON FUNCTIONS  TO regen_registry_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: -; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE regen_registry REVOKE ALL ON FUNCTIONS  FROM PUBLIC;


--
-- PostgreSQL database dump complete
--

