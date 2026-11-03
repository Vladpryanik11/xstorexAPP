/** Case-folding shared by indexing and querying: lower-case, ё→е, collapsed spaces. */
export function foldText(s: string): string {
  return s.toLocaleLowerCase('ru-RU').replace(/ё/g, 'е').replace(/\s+/g, ' ').trim();
}

export function appSearchText(app: {
  nameEn: string;
  nameRu?: string | null;
  subtitleEn?: string | null;
  subtitleRu?: string | null;
  developer: string;
}): string {
  return [app.nameEn, app.nameRu, app.subtitleEn, app.subtitleRu, app.developer]
    .filter((v): v is string => Boolean(v))
    .map(foldText)
    .join('\n');
}

const EN = "`qwertyuiop[]asdfghjkl;'zxcvbnm,.";
const RU = 'ёйцукенгшщзхъфывапролджэячсмитьбю';
const EN_TO_RU = new Map([...EN].map((c, i) => [c, RU[i]!]));
const RU_TO_EN = new Map([...RU].map((c, i) => [c, EN[i]!]));

/** Fixes a query typed in the wrong keyboard layout: "kevty" ↔ "лумен". */
export function switchLayout(query: string): string {
  const lower = query.toLocaleLowerCase('ru-RU');
  const cyr = (lower.match(/[а-яё]/g) ?? []).length;
  const lat = (lower.match(/[a-z]/g) ?? []).length;
  const map = cyr > lat ? RU_TO_EN : EN_TO_RU;
  return [...lower].map((c) => map.get(c) ?? c).join('');
}

/** Escapes LIKE wildcards (backslash is the default escape character in Postgres). */
export function escapeLike(s: string): string {
  return s.replace(/[\\%_]/g, (c) => `\\${c}`);
}
