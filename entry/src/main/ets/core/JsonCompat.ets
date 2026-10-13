export type JsonCompatValue = Object | string | number | boolean | null;

export function parseJsonCompat<T>(text: string): T {
  return JSON.parse(text) as T;
}

export function stringifyJsonCompat(value: JsonCompatValue, space?: number): string {
  if (space === undefined) {
    return JSON.stringify(value);
  }
  return JSON.stringify(value, null, space);
}
