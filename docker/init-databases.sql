-- Create additional databases required by Rails 8 multi-database setup.
-- The primary database (scanarr_production) is created by POSTGRES_DB env var.
CREATE DATABASE scanarr_production_cache;
CREATE DATABASE scanarr_production_queue;
CREATE DATABASE scanarr_production_cable;
