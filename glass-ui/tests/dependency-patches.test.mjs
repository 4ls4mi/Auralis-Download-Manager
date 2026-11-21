import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const patches=path=>{
 const toml=readFileSync(new URL(path,import.meta.url),'utf8');
 const section=toml.split('[patch.crates-io]')[1]?.split(/^\[/m)[0];
 assert.ok(section,`missing patches in ${path}`);
 return Object.fromEntries(section.split(/\r?\n/).map(line=>line.trim()).filter(line=>line&&!line.startsWith('#')).map(line=>{const i=line.indexOf('=');return [line.slice(0,i).trim(),line.slice(i+1).trim()]}));
};
test('embedded workspace uses the same patched downloader dependencies',()=>{
 assert.deepEqual(patches('../src-tauri/Cargo.toml'),patches('../../Cargo.toml'));
});
