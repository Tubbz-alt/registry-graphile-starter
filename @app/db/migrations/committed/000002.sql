--! Previous: sha1:2456e6fa5f0a889aada30de1b74526026ccf2ca9
--! Hash: sha1:7ce3500d6b21b3ad749edda9a178d9cc9453772b

CREATE TYPE app_public.project_state AS ENUM (
  'proposed',
  'pending_approval',
  'active',
  'hold',
  'ended'
);

CREATE TABLE app_public.wallets (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now(),
  "addr" bytea NOT NULL
);

grant
  select,
  insert (updated_at, addr),
  update (updated_at, addr),
  delete
on app_public.wallets to :DATABASE_VISITOR;

CREATE TABLE app_public.account_balances (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now(),
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
on app_public.account_balances to :DATABASE_VISITOR;

-- CREATE TABLE app_public.users (
--   "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
--   "created_at" timestamptz NOT NULL DEFAULT now(),
--   "updated_at" timestamptz NOT NULL DEFAULT now(),
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
-- on app_public.users to :DATABASE_VISITOR;

-- CREATE TABLE app_public.organizations (
--   "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
--   "created_at" timestamptz NOT NULL DEFAULT now(),
--   "updated_at" timestamptz NOT NULL DEFAULT now(),
--   "type" party_type NOT NULL DEFAULT 'organization' check("type" in ('organization')),
--   "owner_id" uuid NOT NULL,
--   "name" text NOT NULL,
--   "logo" text,
--   "website" text,
--   "wallet_id" uuid, --NOT NULL
--   "party_id" uuid, --NOT NULL
--   UNIQUE ("party_id", "type")
-- );

-- ALTER TABLE app_public.users ADD "type" party_type NOT NULL DEFAULT 'user' check("type" in ('user'));
ALTER TABLE app_public.users ADD "wallet_id" uuid;
-- ALTER TABLE app_public.users ADD "party_id" uuid;

grant
  update (type, wallet_id)
on app_public.users to :DATABASE_VISITOR;

ALTER TABLE app_public.users ADD UNIQUE ("party_id", "type");

-- ALTER TABLE app_public.organizations ADD "type" party_type NOT NULL DEFAULT 'organization' check("type" in ('organization'));
ALTER TABLE app_public.organizations ADD "logo" text;
ALTER TABLE app_public.organizations ADD "website" text;
ALTER TABLE app_public.organizations ADD "wallet_id" uuid;
ALTER TABLE app_public.organizations ADD "party_id" uuid;
ALTER TABLE app_public.organizations ADD UNIQUE ("party_id", "type");

grant
  update (type, logo, website, wallet_id, party_id)
on app_public.organizations to :DATABASE_VISITOR;

-- grant
--   select,
--   insert (updated_at, type, owner_id, name, logo, website, wallet_id),
--   update (updated_at, type, owner_id, name, logo, website, wallet_id),
--   delete
-- on app_public.organizations to :DATABASE_VISITOR;

-- CREATE TABLE app_public.organization_member (
--   "created_at" timestamptz NOT NULL DEFAULT now(),
--   "updated_at" timestamptz NOT NULL DEFAULT now(),
--   "member_id" uuid NOT NULL,
--   "organization_id" uuid NOT NULL
-- );
--
-- grant
--   select,
--   insert (updated_at, member_id, organization_id),
--   update (updated_at, member_id, organization_id),
--   delete
-- on app_public.organization_member to :DATABASE_VISITOR;

CREATE TABLE app_public.methodologies (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now(),
  "author_id" uuid NOT NULL
);

grant
  select,
  insert (updated_at, author_id),
  update (updated_at, author_id),
  delete
on app_public.methodologies to :DATABASE_VISITOR;

CREATE TABLE app_public.methodology_versions (
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
on app_public.methodology_versions to :DATABASE_VISITOR;

CREATE TABLE app_public.credit_classes (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now(),
  "designer_id" uuid,
  "methodology_id" uuid NOT NULL
);

grant
  select,
  insert (updated_at, designer_id, methodology_id),
  update (updated_at, designer_id, methodology_id),
  delete
on app_public.credit_classes to :DATABASE_VISITOR;

CREATE TABLE app_public.credit_class_versions (
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
on app_public.credit_class_versions to :DATABASE_VISITOR;

CREATE TABLE app_public.credit_class_issuers (
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now(),
  "credit_class_id" uuid NOT NULL,
  "issuer_id" uuid NOT NULL
);

grant
  select,
  insert (updated_at, credit_class_id, issuer_id),
  update (updated_at, credit_class_id, issuer_id),
  delete
on app_public.credit_class_issuers to :DATABASE_VISITOR;

CREATE TABLE app_public.credit_vintages (
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
on app_public.credit_vintages to :DATABASE_VISITOR;

CREATE TABLE app_public.projects (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now(),
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
on app_public.projects to :DATABASE_VISITOR;

CREATE TABLE app_public.mrvs (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now(),
  "project_id" uuid
);

grant
  select,
  insert (updated_at, project_id),
  update (updated_at, project_id),
  delete
on app_public.mrvs to :DATABASE_VISITOR;

CREATE TABLE app_public.registries (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now(),
  "name" text NOT NULL
);

grant
  select,
  insert (updated_at, name),
  update (updated_at, name),
  delete
on app_public.registries to :DATABASE_VISITOR;

CREATE TABLE app_public.events (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v1(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now(),
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
on app_public.events to :DATABASE_VISITOR;

ALTER TABLE app_public.account_balances ADD FOREIGN KEY ("credit_vintage_id") REFERENCES app_public.credit_vintages ("id");

ALTER TABLE app_public.account_balances ADD FOREIGN KEY ("wallet_id") REFERENCES app_public.wallets ("id");

--ALTER TABLE app_public.users" ADD FOREIGN KEY ("type") REFERENCES app_public.parties ("type");

ALTER TABLE app_public.users ADD FOREIGN KEY ("wallet_id") REFERENCES app_public.wallets ("id");

ALTER TABLE app_public.organizations ADD FOREIGN KEY ("party_id") REFERENCES app_public.parties ("id");

--ALTER TABLE app_public.organizations" ADD FOREIGN KEY ("type") REFERENCES app_public.parties ("type");

-- ALTER TABLE app_public.organizations ADD FOREIGN KEY ("owner_id") REFERENCES app_public.users ("id");

ALTER TABLE app_public.organizations ADD FOREIGN KEY ("wallet_id") REFERENCES app_public.wallets ("id");

-- ALTER TABLE app_public.organization_member ADD FOREIGN KEY ("member_id") REFERENCES app_public.users ("id");

-- ALTER TABLE app_public.organization_member ADD FOREIGN KEY ("organization_id") REFERENCES app_public.organizations ("id");

ALTER TABLE app_public.methodologies ADD FOREIGN KEY ("author_id") REFERENCES app_public.parties ("id");

ALTER TABLE app_public.methodology_versions ADD FOREIGN KEY ("id") REFERENCES app_public.methodologies ("id");

ALTER TABLE app_public.credit_classes ADD FOREIGN KEY ("designer_id") REFERENCES app_public.parties ("id");

ALTER TABLE app_public.credit_classes ADD FOREIGN KEY ("methodology_id") REFERENCES app_public.methodologies ("id");

ALTER TABLE app_public.credit_class_versions ADD FOREIGN KEY ("id") REFERENCES app_public.credit_classes ("id");

ALTER TABLE app_public.credit_class_issuers ADD FOREIGN KEY ("credit_class_id") REFERENCES app_public.credit_classes ("id");

ALTER TABLE app_public.credit_class_issuers ADD FOREIGN KEY ("issuer_id") REFERENCES app_public.wallets ("id");

ALTER TABLE app_public.credit_vintages ADD FOREIGN KEY ("credit_class_id") REFERENCES app_public.credit_classes ("id");

ALTER TABLE app_public.credit_vintages ADD FOREIGN KEY ("project_id") REFERENCES app_public.projects ("id");

ALTER TABLE app_public.credit_vintages ADD FOREIGN KEY ("issuer_id") REFERENCES app_public.wallets ("id");

ALTER TABLE app_public.projects ADD FOREIGN KEY ("developer_id") REFERENCES app_public.parties ("id");

ALTER TABLE app_public.projects ADD FOREIGN KEY ("steward_id") REFERENCES app_public.parties ("id");

ALTER TABLE app_public.projects ADD FOREIGN KEY ("land_owner_id") REFERENCES app_public.parties ("id");

ALTER TABLE app_public.projects ADD FOREIGN KEY ("credit_class_id") REFERENCES app_public.credit_classes ("id");

ALTER TABLE app_public.projects ADD FOREIGN KEY ("registry_id") REFERENCES app_public.registries ("id");

ALTER TABLE app_public.mrvs ADD FOREIGN KEY ("project_id") REFERENCES app_public.projects ("id");

ALTER TABLE app_public.events ADD FOREIGN KEY ("project_id") REFERENCES app_public.projects ("id");

CREATE INDEX ON "app_public"."account_balances"("credit_vintage_id");
CREATE INDEX ON "app_public"."account_balances"("wallet_id");
CREATE INDEX ON "app_public"."credit_classes"("designer_id");
CREATE INDEX ON "app_public"."credit_classes"("methodology_id");
CREATE INDEX ON "app_public"."credit_class_issuers"("credit_class_id");
CREATE INDEX ON "app_public"."credit_vintages"("credit_class_id");
CREATE INDEX ON "app_public"."projects"("credit_class_id");
CREATE INDEX ON "app_public"."credit_class_issuers"("issuer_id");
CREATE INDEX ON "app_public"."credit_vintages"("project_id");
CREATE INDEX ON "app_public"."credit_vintages"("issuer_id");
CREATE INDEX ON "app_public"."events"("project_id");
CREATE INDEX ON "app_public"."methodologies"("author_id");
CREATE INDEX ON "app_public"."mrvs"("project_id");
CREATE INDEX ON "app_public"."organizations"("wallet_id");
CREATE INDEX ON "app_public"."projects"("developer_id");
CREATE INDEX ON "app_public"."projects"("steward_id");
CREATE INDEX ON "app_public"."projects"("land_owner_id");
CREATE INDEX ON "app_public"."users"("wallet_id");
CREATE INDEX ON "app_public"."projects"("registry_id");

--CREATE UNIQUE INDEX ON app_public.parties ("id", "type");

--COMMENT ON COLUMN "methodology_versions"."metadata" IS 'eco-regions, practices/outcomes measures...';

--COMMENT ON COLUMN "credit_class_versions"."metadata" IS 'eco metrics, price';

--COMMENT ON COLUMN "credit_vintages"."initial_distribution" IS 'breakdown of ownership of credits';

--COMMENT ON COLUMN app_public.projects."land_owner_id" IS 'constraint check_project check (developer_id is not null or owner_id is not null or steward_id is not null)';

--COMMENT ON COLUMN app_public.projects."metadata" IS 'land mgmt actions, key activities/outcomes, protected species...';
