import { DatabaseSync } from 'node:sqlite';

// Limit: SQLite + in-process rate limits, single replica only; move to PostgreSQL + Redis (spec §12) in M7.
export function openDb(path: string): DatabaseSync {
  const db = new DatabaseSync(path);
  db.exec(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS otp (
      phone TEXT PRIMARY KEY, code_hash TEXT NOT NULL,
      expires_at INTEGER NOT NULL, tries INTEGER NOT NULL DEFAULT 0, sent_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS ip_requests (ip TEXT NOT NULL, at INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS ip_requests_ip_at ON ip_requests (ip, at);
    CREATE TABLE IF NOT EXISTS phone_events (phone TEXT NOT NULL, kind TEXT NOT NULL, at INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS phone_events_phone_kind_at ON phone_events (phone, kind, at);
    DROP TABLE IF EXISTS registered;
    CREATE TABLE IF NOT EXISTS directory (hash TEXT PRIMARY KEY, localpart TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS lookup_quota (user_id TEXT PRIMARY KEY, window_start INTEGER NOT NULL, used INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS accounts (
      phone TEXT PRIMARY KEY, localpart TEXT NOT NULL UNIQUE, last_signin_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS retired_accounts (phone TEXT NOT NULL, localpart TEXT NOT NULL, retired_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS admin_token (id INTEGER PRIMARY KEY CHECK (id = 1), token TEXT NOT NULL);
  `);
  return db;
}
