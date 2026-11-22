import test from 'node:test';
import assert from 'node:assert/strict';
import {nativeBackdrop} from '../src/nativeBackdrop.ts';

test('desktop acrylic applies to square frosted and tinted windows', () => {
  assert.equal(nativeBackdrop('desktop', 'frosted'), 'acrylic');
  assert.equal(nativeBackdrop('desktop', 'tinted'), 'acrylic');
  assert.equal(nativeBackdrop('desktop', 'soft'), 'blur');
  assert.equal(nativeBackdrop('desktop', 'clear'), null);
  assert.equal(nativeBackdrop('wallpaper', 'frosted'), null);
  assert.equal(nativeBackdrop('solid', 'tinted'), null);
});
