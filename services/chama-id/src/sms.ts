export interface SmsProvider { send(phoneDigits: string, text: string): Promise<void>; }
export class ConsoleSms implements SmsProvider {
  async send(phoneDigits: string, text: string) { console.log(`[sms] +${phoneDigits}: ${text}`); }
}
