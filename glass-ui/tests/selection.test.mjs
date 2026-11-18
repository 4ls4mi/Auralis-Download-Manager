import test from 'node:test';
import assert from 'node:assert/strict';
import {selectDownload} from '../src/selection.ts';
test('selects a single download, toggles with Ctrl, and selects ranges with Shift',()=>{
 const visible=[7,3,8,1];
 assert.deepEqual(selectDownload(visible,[],null,3,false,false),[3]);
 assert.deepEqual(selectDownload(visible,[3],3,1,false,true),[3,1]);
 assert.deepEqual(selectDownload(visible,[3,1],1,3,false,true),[1]);
 assert.deepEqual(selectDownload(visible,[3],3,1,true,false),[3,8,1]);
 assert.deepEqual(selectDownload(visible,[7],3,1,true,true),[7,3,8,1]);
 assert.deepEqual(selectDownload(visible,[7],99,3,true,false),[3]);
});
