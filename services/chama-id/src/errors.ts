const STATUS: Record<string, number> = {
  invalid_phone: 400, invalid_code: 400, invalid_keys: 400, invalid_pin: 400, expired: 400, bad_request: 400,
  invalid_token: 401, forbidden: 403, pin_required: 403, not_found: 404, no_identity: 409, conflict: 409,
  too_many_attempts: 429, rate_limited: 429, pin_locked: 429,
};
export class AppError extends Error {
  code: string; status: number; extra?: Record<string, unknown>;
  constructor(code: string, extra?: Record<string, unknown>) {
    super(code); this.code = code; this.status = STATUS[code] ?? 500; this.extra = extra;
  }
}
