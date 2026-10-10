-- The parts of a Supabase project the migrations and checks rely on, for a
-- plain local PostgreSQL (with PostGIS and pg_cron). Not a full Supabase:
-- no GoTrue, PostgREST or Realtime, just their schemas and roles, so every
-- migration applies and every rolled-back check in supabase/tests runs
-- without touching the live project. Used by run-local.sh.

create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;
create role authenticator login noinherit;
create role supabase_auth_admin nologin;
grant anon, authenticated, service_role to authenticator;
grant anon, authenticated, service_role to postgres;

create schema extensions;
create extension pgcrypto with schema extensions;
create extension "uuid-ossp" with schema extensions;
grant usage on schema extensions to anon, authenticated, service_role;

-- Supabase's defaults: the API roles may use public, and get every new
-- table, sequence and function there unless a migration revokes it.
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;

create schema auth;
grant usage on schema auth to anon, authenticated, service_role;

create table auth.users (
  instance_id uuid, id uuid primary key, aud varchar(255), role varchar(255),
  email varchar(255), encrypted_password varchar(255), email_confirmed_at timestamptz,
  invited_at timestamptz, confirmation_token varchar(255), confirmation_sent_at timestamptz,
  recovery_token varchar(255), recovery_sent_at timestamptz, email_change_token_new varchar(255),
  email_change varchar(255), email_change_sent_at timestamptz, last_sign_in_at timestamptz,
  raw_app_meta_data jsonb, raw_user_meta_data jsonb, is_super_admin boolean,
  created_at timestamptz, updated_at timestamptz, phone text, phone_confirmed_at timestamptz,
  banned_until timestamptz, deleted_at timestamptz, is_anonymous boolean not null default false,
  confirmed_at timestamptz generated always as (least(email_confirmed_at, phone_confirmed_at)) stored);
create table auth.identities (
  id uuid primary key, provider_id text not null, user_id uuid not null references auth.users on delete cascade,
  identity_data jsonb not null, provider text not null, last_sign_in_at timestamptz,
  created_at timestamptz, updated_at timestamptz, email text);
create table auth.sessions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users on delete cascade,
  created_at timestamptz default now());
create table auth.refresh_tokens (
  id bigserial primary key, token varchar(255), user_id varchar(255),
  session_id uuid references auth.sessions on delete cascade, revoked boolean, created_at timestamptz);

create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $$;
create function auth.role() returns text language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')) $$;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;

-- pg_net: requests are recorded, never sent.
create schema net;
create table net._http_response (
  id bigint, status_code integer, content_type text, headers jsonb, content text,
  timed_out boolean, error_msg text, created timestamptz not null default now());
create sequence net.request_seq;
create function net.http_get(url text, params jsonb default '{}', headers jsonb default '{}',
                             timeout_milliseconds integer default 5000)
returns bigint language sql as $$ select nextval('net.request_seq') $$;
create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}',
                              headers jsonb default '{}', timeout_milliseconds integer default 5000)
returns bigint language sql as $$ select nextval('net.request_seq') $$;

create schema storage;
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, metadata jsonb);

create extension pg_cron;
