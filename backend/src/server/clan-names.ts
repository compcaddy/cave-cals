// Display names and clan names are seen by other people, so they're tidied and checked against a short list
// of slurs and strong profanity (Apple guideline 1.2 asks for a filter). Reports cover what slips through.
import { APIError } from './config';

// Matched on letters only, after undoing common look-alike swaps, so "b!tch" and "B I T C H" are caught.
const BLOCKED = [
  'fuck', 'shit', 'cunt', 'bitch', 'whore', 'slut', 'dick', 'cock', 'pussy', 'asshole', 'bastard', 'nigger', 'nigga',
  'faggot', 'fag', 'retard', 'spic', 'chink', 'wetback', 'tranny', 'coon', 'gook', 'beaner', 'rape',
  'nazi', 'hitler', 'porn', 'penis', 'vagina', 'cum', 'jizz', 'twat', 'wank',
];
// Short words that also appear inside ordinary names (Dickens, Cumberland, Nazir) only match whole words.
const WHOLE_WORD_ONLY = new Set(['dick', 'cock', 'cum', 'fag', 'coon', 'spic', 'twat', 'rape', 'porn', 'wank', 'nazi']);
const SWAPS: Record<string, string> = { '0': 'o', '1': 'i', '!': 'i', '3': 'e', '4': 'a', '@': 'a', '5': 's', '$': 's', '7': 't', '+': 't', '8': 'b' };

function folded(text: string) {
  return text.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[0-9!@$+]/g, ch => SWAPS[ch] ?? ch);
}
export function containsBlockedWord(text: string): boolean {
  const lower = folded(text);
  const words = lower.split(/[^a-z]+/).filter(Boolean);
  const squashed = lower.replace(/[^a-z]/g, '');
  return BLOCKED.some(word => WHOLE_WORD_ONLY.has(word)
    ? words.includes(word) || words.includes(`${word}s`)
    : squashed.includes(word));
}
// Trims, collapses spaces, drops control and invisible characters, and checks the length and words.
export function cleanName(raw: string, { min, max, what }: { min: number; max: number; what: string }): string {
  const name = raw.normalize('NFKC').replace(/[\p{Cc}\p{Cf}]/gu, '').replace(/\s+/g, ' ').trim();
  if ([...name].length < min) throw new APIError(400, 'name_too_short', `Pick a longer ${what}.`);
  if ([...name].length > max) throw new APIError(400, 'name_too_long', `Pick a ${what} of ${max} characters or fewer.`);
  if (containsBlockedWord(name)) throw new APIError(400, 'name_not_allowed', `Pick a different ${what}.`);
  return name;
}
export const cleanDisplayName = (raw: string) => cleanName(raw, { min: 1, max: 30, what: 'name' });
export const cleanClanName = (raw: string) => cleanName(raw, { min: 2, max: 30, what: 'clan name' });
