import test from 'node:test';
import assert from 'node:assert/strict';
import {nativeBackdrop} from '../src/nativeBackdrop.ts';
test('native effects do not paint a rectangle around floating frosted layers',()=>{
 assert.equal(nativeBackdrop('desktop','frosted-water-351','frosted',false),null);
 assert.equal(nativeBackdrop('desktop','frosted-water-351','frosted',true),'acrylic');
 assert.equal(nativeBackdrop('wallpaper','frosted-water-351','frosted',true),null);
 assert.equal(nativeBackdrop('desktop','builtin-smoked-glass','tinted',false),'acrylic');
 assert.equal(nativeBackdrop('desktop','brushed-glass','soft',false),'blur');
 assert.equal(nativeBackdrop('desktop','window-glass','clear',false),null);
});
