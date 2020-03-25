--! Previous: sha1:56f99a18c9e4d9e3193e8c7ecc1e427751da9e78
--! Hash: sha1:7e5aa288474566a2fd7497bf5b52d05b49ce700f

CREATE TYPE app_public.party_type AS ENUM (
  'user',
  'organization'
);

CREATE TYPE app_public.project_state AS ENUM (
  'proposed',
  'pending_approval',
  'active',
  'hold',
  'ended'
);

CREATE TABLE app_public.party (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz,
  "type" party_type NOT NULL check("type" in ('user', 'organization')),
  "address" geometry,
  "short_description" char(130)
  -- "stripe_token" text
);

grant
  select,
  insert (updated_at, type, address, short_description),
  update (updated_at, type, address, short_description),
  delete
on app_public.party to :DATABASE_VISITOR;

CREATE TABLE app_public.wallet (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz,
  "addr" bytea NOT NULL
);

grant
  select,
  insert (updated_at, addr),
  update (updated_at, addr),
  delete
on app_public.wallet to :DATABASE_VISITOR;

CREATE TABLE app_public.account_balance (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz,
  "credit_vintage_id" uuid,
  "wallet_id" uuid,
  "liquid_balance" integer,
  "burnt_balance" integer
);

grant
  select,
  insert (updated_at, credit_vintage_id, wallet_id, liquid_balance, burnt_balance),
  update (updated_at, credit_vintage_id, wallet_id, liquid_balance, burnt_balance),
  delete
on app_public.account_balance to :DATABASE_VISITOR;

-- CREATE TABLE app_public.user (
--   "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
--   "created_at" timestamptz NOT NULL DEFAULT now(),
--   "updated_at" timestamptz,
--   "type" party_type NOT NULL DEFAULT 'user' check("type" in ('user')),
--   "email" citext NOT NULL,
--   "first_name" text NOT NULL,
--   "last_name" text NOT NULL,
--   "avatar" text,
--   "wallet_id" uuid
-- );
--
-- grant
--   select,
--   insert (updated_at, type, email, first_name, last_name, avatar, wallet_id),
--   update (updated_at, type, email, first_name, last_name, avatar, wallet_id),
--   delete
-- on app_public.user to :DATABASE_VISITOR;

CREATE TABLE app_public.organization (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz,
  "type" party_type NOT NULL DEFAULT 'organization' check("type" in ('organization')),
  "owner_id" uuid NOT NULL,
  "name" text NOT NULL,
  "logo" text,
  "website" text,
  "wallet_id" uuid, --NOT NULL
  "party_id" uuid, --NOT NULL
  UNIQUE ("party_id", "type")
);

ALTER TABLE app_public.user ADD "type" party_type NOT NULL DEFAULT 'user' check("type" in ('user'));

grant
  update (type)
on app_public.user to :DATABASE_VISITOR;

ALTER TABLE app_public.user ADD UNIQUE ("party_id", "type");

grant
  select,
  insert (updated_at, type, owner_id, name, logo, website, wallet_id),
  update (updated_at, type, owner_id, name, logo, website, wallet_id),
  delete
on app_public.organization to :DATABASE_VISITOR;

CREATE TABLE app_public.organization_member (
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz,
  "member_id" uuid NOT NULL,
  "organization_id" uuid NOT NULL
);

grant
  select,
  insert (updated_at, member_id, organization_id),
  update (updated_at, member_id, organization_id),
  delete
on app_public.organization_member to :DATABASE_VISITOR;

CREATE TABLE app_public.methodology (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz,
  "author_id" uuid NOT NULL
);

grant
  select,
  insert (updated_at, author_id),
  update (updated_at, author_id),
  delete
on app_public.methodology to :DATABASE_VISITOR;

CREATE TABLE app_public.methodology_version (
  "id" uuid,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "name" text NOT NULL,
  "version" text NOT NULL,
  "date_developed" timestamptz NOT NULL,
  "description" text,
  "boundary" geometry NOT NULL,
  --"_eco_regions" jsonb,
  --"_practices" jsonb,
  --"_outcomes_measured" jsonb,
  "metadata" jsonb,
  "files" jsonb,
  PRIMARY KEY ("id", "created_at")
);

grant
  select,
  insert (name, version, date_developed, description, boundary, metadata, files),
  update (name, version, date_developed, description, boundary, metadata, files),
  delete
on app_public.methodology_version to :DATABASE_VISITOR;

CREATE TABLE app_public.credit_class (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz,
  "designer_id" uuid,
  "methodology_id" uuid NOT NULL
);

grant
  select,
  insert (updated_at, designer_id, methodology_id),
  update (updated_at, designer_id, methodology_id),
  delete
on app_public.credit_class to :DATABASE_VISITOR;

CREATE TABLE app_public.credit_class_version (
  "id" uuid,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "name" text NOT NULL,
  "version" text NOT NULL,
  "date_developed" timestamptz NOT NULL,
  "description" text,
  "state_machine" jsonb NOT NULL,
  --"_price" jsonb,
  --"_eco_metrics" jsonb,
  "metadata" jsonb,
  PRIMARY KEY ("id", "created_at")
);

grant
  select,
  insert (name, version, date_developed, description, state_machine, metadata),
  update (name, version, date_developed, description, state_machine, metadata),
  delete
on app_public.credit_class_version to :DATABASE_VISITOR;

CREATE TABLE app_public.credit_class_issuer (
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz,
  "credit_class_id" uuid NOT NULL,
  "issuer_id" uuid NOT NULL
);

grant
  select,
  insert (updated_at, credit_class_id, issuer_id),
  update (updated_at, credit_class_id, issuer_id),
  delete
on app_public.credit_class_issuer to :DATABASE_VISITOR;

CREATE TABLE app_public.credit_vintage (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "credit_class_id" uuid,
  "project_id" uuid,
  "issuer_id" uuid,
  "units" integer,
  "initial_distribution" jsonb
);

grant
  select,
  insert (credit_class_id, project_id, issuer_id, units, initial_distribution),
  update (credit_class_id, project_id, issuer_id, units, initial_distribution),
  delete
on app_public.credit_vintage to :DATABASE_VISITOR;

CREATE TABLE app_public.project (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz,
  "developer_id" uuid,
  "steward_id" uuid,
  "land_owner_id" uuid,
  "credit_class_id" uuid NOT NULL,
  "name" text NOT NULL,
  "location" geometry NOT NULL,
  "application_date" timestamptz NOT NULL,
  "start_date" timestamptz NOT NULL,
  "end_date" timestamptz NOT NULL,
  "summary_description" char(160) NOT NULL,
  "long_description" text NOT NULL,
  "photos" text[] NOT NULL,
  "documents" jsonb,
  "area" integer NOT NULL,
  "area_unit" char(10) NOT NULL,
  "state" project_state NOT NULL,
  "last_event_index" integer,
  --"_land_mgmt_actions" jsonb,
  --"_key_activities" jsonb,
  --"_protected_species" jsonb,
  "impact" jsonb,
  "metadata" jsonb,
  "registry_id" uuid,
  constraint check_project check ("developer_id" is not null or "land_owner_id" is not null or "steward_id" is not null)
);

grant
  select,
  insert (updated_at, developer_id, steward_id, land_owner_id, credit_class_id, name, location, application_date, start_date, end_date, summary_description, long_description, photos, documents, area, area_unit, state, last_event_index, impact, metadata, registry_id),
  update (updated_at, developer_id, steward_id, land_owner_id, credit_class_id, name, location, application_date, start_date, end_date, summary_description, long_description, photos, documents, area, area_unit, state, last_event_index, impact, metadata, registry_id),
  delete
on app_public.project to :DATABASE_VISITOR;

CREATE TABLE app_public.mrv (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz,
  "project_id" uuid
);

grant
  select,
  insert (updated_at, project_id),
  update (updated_at, project_id),
  delete
on app_public.mrv to :DATABASE_VISITOR;

CREATE TABLE app_public.registry (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz,
  "name" text NOT NULL
);

grant
  select,
  insert (updated_at, name),
  update (updated_at, name),
  delete
on app_public.registry to :DATABASE_VISITOR;

CREATE TABLE app_public.event (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz,
  "project_id" uuid NOT NULL,
  "date" timestamptz,
  "summary" char(160) NOT NULL,
  "description" text,
  "from_state" project_state,
  "to_state" project_state
);

grant
  select,
  insert (updated_at, project_id, "date", summary, description, from_state, to_state),
  update (updated_at, project_id, "date", summary, description, from_state, to_state),
  delete
on app_public.event to :DATABASE_VISITOR;

ALTER TABLE app_public.account_balance ADD FOREIGN KEY ("credit_vintage_id") REFERENCES app_public.credit_vintage ("id");

ALTER TABLE app_public.account_balance ADD FOREIGN KEY ("wallet_id") REFERENCES app_public.wallet ("id");

ALTER TABLE app_public.user ADD FOREIGN KEY ("party_id") REFERENCES app_public.party ("id");

--ALTER TABLE app_public.user" ADD FOREIGN KEY ("type") REFERENCES app_public.party ("type");

ALTER TABLE app_public.user ADD FOREIGN KEY ("wallet_id") REFERENCES app_public.wallet ("id");

ALTER TABLE app_public.organization ADD FOREIGN KEY ("party_id") REFERENCES app_public.party ("id");

--ALTER TABLE app_public.organization" ADD FOREIGN KEY ("type") REFERENCES app_public.party ("type");

ALTER TABLE app_public.organization ADD FOREIGN KEY ("owner_id") REFERENCES app_public.user ("id");

ALTER TABLE app_public.organization ADD FOREIGN KEY ("wallet_id") REFERENCES app_public.wallet ("id");

ALTER TABLE app_public.organization_member ADD FOREIGN KEY ("member_id") REFERENCES app_public.user ("id");

ALTER TABLE app_public.organization_member ADD FOREIGN KEY ("organization_id") REFERENCES app_public.organization ("id");

ALTER TABLE app_public.methodology ADD FOREIGN KEY ("author_id") REFERENCES app_public.party ("id");

ALTER TABLE app_public.methodology_version ADD FOREIGN KEY ("id") REFERENCES app_public.methodology ("id");

ALTER TABLE app_public.credit_class ADD FOREIGN KEY ("designer_id") REFERENCES app_public.party ("id");

ALTER TABLE app_public.credit_class ADD FOREIGN KEY ("methodology_id") REFERENCES app_public.methodology ("id");

ALTER TABLE app_public.credit_class_version ADD FOREIGN KEY ("id") REFERENCES app_public.credit_class ("id");

ALTER TABLE app_public.credit_class_issuer ADD FOREIGN KEY ("credit_class_id") REFERENCES app_public.credit_class ("id");

ALTER TABLE app_public.credit_class_issuer ADD FOREIGN KEY ("issuer_id") REFERENCES app_public.wallet ("id");

ALTER TABLE app_public.credit_vintage ADD FOREIGN KEY ("credit_class_id") REFERENCES app_public.credit_class ("id");

ALTER TABLE app_public.credit_vintage ADD FOREIGN KEY ("project_id") REFERENCES app_public.project ("id");

ALTER TABLE app_public.credit_vintage ADD FOREIGN KEY ("issuer_id") REFERENCES app_public.wallet ("id");

ALTER TABLE app_public.project ADD FOREIGN KEY ("developer_id") REFERENCES app_public.party ("id");

ALTER TABLE app_public.project ADD FOREIGN KEY ("steward_id") REFERENCES app_public.party ("id");

ALTER TABLE app_public.project ADD FOREIGN KEY ("land_owner_id") REFERENCES app_public.party ("id");

ALTER TABLE app_public.project ADD FOREIGN KEY ("credit_class_id") REFERENCES app_public.credit_class ("id");

ALTER TABLE app_public.project ADD FOREIGN KEY ("registry_id") REFERENCES app_public.registry ("id");

ALTER TABLE app_public.mrv ADD FOREIGN KEY ("project_id") REFERENCES app_public.project ("id");

ALTER TABLE app_public.event ADD FOREIGN KEY ("project_id") REFERENCES app_public.project ("id");

CREATE INDEX ON "app_public"."account_balance"("credit_vintage_id");
CREATE INDEX ON "app_public"."account_balance"("wallet_id");
CREATE INDEX ON "app_public"."credit_class"("designer_id");
CREATE INDEX ON "app_public"."credit_class"("methodology_id");
CREATE INDEX ON "app_public"."credit_class_issuer"("credit_class_id");
CREATE INDEX ON "app_public"."credit_vintage"("credit_class_id");
CREATE INDEX ON "app_public"."project"("credit_class_id");
CREATE INDEX ON "app_public"."credit_class_issuer"("issuer_id");
CREATE INDEX ON "app_public"."credit_vintage"("project_id");
CREATE INDEX ON "app_public"."credit_vintage"("issuer_id");
CREATE INDEX ON "app_public"."event"("project_id");
CREATE INDEX ON "app_public"."methodology"("author_id");
CREATE INDEX ON "app_public"."mrv"("project_id");
CREATE INDEX ON "app_public"."organization"("owner_id");
CREATE INDEX ON "app_public"."organization"("wallet_id");
CREATE INDEX ON "app_public"."organization_member"("organization_id");
CREATE INDEX ON "app_public"."project"("developer_id");
CREATE INDEX ON "app_public"."project"("steward_id");
CREATE INDEX ON "app_public"."project"("land_owner_id");
CREATE INDEX ON "app_public"."user"("wallet_id");
CREATE INDEX ON "app_public"."organization_member"("member_id");
CREATE INDEX ON "app_public"."project"("registry_id");

--CREATE UNIQUE INDEX ON app_public.party ("id", "type");

--COMMENT ON COLUMN "methodology_version"."metadata" IS 'eco-regions, practices/outcomes measures...';

--COMMENT ON COLUMN "credit_class_version"."metadata" IS 'eco metrics, price';

--COMMENT ON COLUMN "credit_vintage"."initial_distribution" IS 'breakdown of ownership of credits';

--COMMENT ON COLUMN app_public.project."land_owner_id" IS 'constraint check_project check (developer_id is not null or owner_id is not null or steward_id is not null)';

--COMMENT ON COLUMN app_public.project."metadata" IS 'land mgmt actions, key activities/outcomes, protected species...';
