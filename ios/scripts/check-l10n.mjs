#!/usr/bin/env node
// Проверка локализации: одинаковые ключи в en и ru, одинаковые спецификаторы формата,
// все ключи из кода (`L10n.tr("…")` и составные ключи ошибок установки) есть в файлах.
// Запуск: node ios/scripts/check-l10n.mjs
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "iStore");
const languages = ["en", "ru"];

function parseStrings(path) {
  const text = readFileSync(path, "utf8");
  const entries = new Map();
  const withoutComments = text.replace(/\/\*[\s\S]*?\*\//g, "");
  const re = /"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;/g;
  let match;
  while ((match = re.exec(withoutComments)) !== null) {
    if (entries.has(match[1])) {
      throw new Error(`${path}: duplicate key ${match[1]}`);
    }
    entries.set(match[1], match[2]);
  }
  const leftovers = withoutComments.replace(re, "").trim();
  if (leftovers.length > 0) {
    throw new Error(`${path}: cannot parse fragment: ${leftovers.slice(0, 80)}`);
  }
  return entries;
}

function specifiers(value) {
  return (value.match(/%(\d+\$)?[@dfsu]/g) || []).join(",");
}

function swiftFiles(dir) {
  const result = [];
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) result.push(...swiftFiles(path));
    else if (name.endsWith(".swift")) result.push(path);
  }
  return result;
}

const tables = Object.fromEntries(
  languages.map((lang) => [lang, parseStrings(join(root, "Resources", `${lang}.lproj`, "Localizable.strings"))])
);

const errors = [];
const [base, ...others] = languages;
for (const other of others) {
  for (const key of tables[base].keys()) {
    if (!tables[other].has(key)) errors.push(`missing in ${other}: ${key}`);
    else if (specifiers(tables[base].get(key)) !== specifiers(tables[other].get(key))) {
      errors.push(`format mismatch ${key}: ${base}="${tables[base].get(key)}" ${other}="${tables[other].get(key)}"`);
    }
  }
  for (const key of tables[other].keys()) {
    if (!tables[base].has(key)) errors.push(`missing in ${base}: ${key}`);
  }
}

// Ключи, которые используются в коде.
const used = new Set();
for (const file of swiftFiles(root)) {
  const source = readFileSync(file, "utf8");
  for (const match of source.matchAll(/L10n\.tr\(\s*"([^"]+)"/g)) used.add(match[1]);
  for (const match of source.matchAll(/\?\s*"([a-z_]+\.[a-z_.]+)"\s*:\s*"([a-z_]+\.[a-z_.]+)"/g)) {
    used.add(match[1]);
    used.add(match[2]);
  }
  for (const match of source.matchAll(/"(tab\.[a-z_]+)"/g)) used.add(match[1]);
  for (const match of source.matchAll(/return "(install\.error\.[a-z_]+)"/g)) {
    used.add(`${match[1]}.title`);
    used.add(`${match[1]}.message`);
  }
}
for (const key of used) {
  for (const lang of languages) {
    if (!tables[lang].has(key)) errors.push(`used in code but missing in ${lang}: ${key}`);
  }
}

if (errors.length > 0) {
  console.error(errors.join("\n"));
  process.exit(1);
}
console.log(`OK: ${tables[base].size} keys in ${languages.join(", ")}, ${used.size} keys referenced from code.`);
