#!/usr/bin/env node
// Every FoamyI18n.t()/tn() literal in the plugin's QML has an English and a
// Norwegian catalog entry, and English entries repeat their key.
"use strict"
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const root = path.join(__dirname, "..")
const en = JSON.parse(fs.readFileSync(path.join(root, "i18n/en.json"), "utf8"))
const no = JSON.parse(fs.readFileSync(path.join(root, "i18n/no.json"), "utf8"))
const sources = fs.readdirSync(root).filter(name => name.endsWith(".qml"))
const keys = new Set()
for (const name of sources) {
  const text = fs.readFileSync(path.join(root, name), "utf8")
  for (const match of text.matchAll(/FoamyI18n\.tn?\("((?:[^"\\]|\\.)*)"/g)) keys.add(JSON.parse(`"${match[1]}"`))
}
assert.ok(keys.size > 0, "found translatable strings")
for (const key of keys) {
  assert.ok(Object.hasOwn(en, key), `en.json lacks ${key}`)
  assert.ok(Object.hasOwn(no, key), `no.json lacks ${key}`)
}
for (const [key, value] of Object.entries(en)) {
  if (typeof value === "string") assert.equal(value, key, `English entry repeats its key: ${key}`)
  assert.ok(keys.has(key), `unused catalog entry: ${key}`)
}
console.log(`RESULT: ${keys.size} translatable strings have en and no entries`)
