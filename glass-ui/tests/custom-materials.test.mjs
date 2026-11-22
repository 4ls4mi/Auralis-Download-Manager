import test from 'node:test';
import assert from 'node:assert/strict';
import {parseMaterial,materialId,materialPresets,extraMaterials} from '../src/customMaterials.ts';
test('editable material templates validate and have stable distinct ids',()=>{
 for(const value of [...Object.values(materialPresets),...Object.values(extraMaterials)])assert.deepEqual(parseMaterial(value),value);
 const a=parseMaterial({format:'auralis-material',version:1,name:'My glass',finish:'clear',controls:'soft',translucency:60,shading:25});
 assert.equal(materialId(a),materialId({...a,name:'MY GLASS'}));
 assert.notEqual(materialId(a),materialId({...a,name:'Another glass'}));
});
test('unsafe or invalid material data is rejected or discarded',()=>{
 const a={...materialPresets['brushed-glass']};
 for(const change of [{version:2},{finish:'url(https://example.com)'},{controls:'x; color:red'},{translucency:101},{shading:NaN},{name:''}])assert.throws(()=>parseMaterial({...a,...change}));
 assert.equal('css' in parseMaterial({...a,css:'body{display:none}'}),false);
});

test('material finish selects its backdrop without a separate setting',async()=>{
 const {materialBackdrop}=await import('../src/customMaterials.ts');
 assert.equal(materialBackdrop('frosted-water-351',materialPresets['frosted-water-351']),'frosted');
 assert.equal(materialBackdrop('brushed-glass',materialPresets['brushed-glass']),'soft');
 assert.equal(materialBackdrop('rose-pine',materialPresets['rose-pine']),'frosted');
 assert.equal(materialBackdrop('oversimplified',materialPresets['oversimplified']),'clear');
 assert.equal(materialBackdrop('builtin-obsidian-matte',extraMaterials['builtin-obsidian-matte']),'tinted');
 assert.equal(materialBackdrop('window-glass',materialPresets['window-glass']),'clear');
 assert.equal(materialBackdrop('builtin-smoked-glass',extraMaterials['builtin-smoked-glass']),'tinted');
});

test('black blur glass uses the Windows acrylic backdrop', async()=>{
 const {materialBackdrop}=await import('../src/customMaterials.ts');
 const {nativeBackdrop}=await import('../src/nativeBackdrop.ts');
 const material=extraMaterials['builtin-black-glass'];
 assert.equal(materialBackdrop('builtin-black-glass',material),'tinted');
 assert.equal(nativeBackdrop('desktop',materialBackdrop('builtin-black-glass',material)),'acrylic');
 assert.equal(nativeBackdrop('wallpaper','tinted'),null);
});
