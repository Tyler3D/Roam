export interface MentionResult {
  id: string;
  firstName: string;
  lastName: string;
  isFriend: boolean;
}

export function extractMentionQuery(input: string): string | null {
  const words = input.split(/\s/);
  const last = words[words.length - 1];
  if (last.startsWith("@") && last.length > 1) {
    return last.slice(1);
  }
  return null;
}

export function replaceMention(input: string, name: string): string {
  const words = input.split(/\s/);
  words[words.length - 1] = `@${name}`;
  return words.join(" ") + " ";
}
