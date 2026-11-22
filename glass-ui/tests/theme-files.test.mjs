import test from 'node:test';
import assert from 'node:assert/strict';
import {parseTheme,themeId,paletteForTheme} from '../src/themeFiles.ts';
import {materialPresets} from '../src/customMaterials.ts';
const settings={tintStrength:22,fontFamily:'Trebuchet MS',fontSize:14,highContrast:true,uiScale:90,dim:26,blur:3,indicator:'blue-purple',connectionIndicator:'ocean',graphIndicator:'neon',progressMaterial:'liquid-glass',connectionMaterial:'gradient',graphMaterial:'liquid-aero',progressShape:'droplet',connectionShape:'square',graphShape:'area',trackFinish:'recessed',trackColor:'ice',connectionTrackFinish:'frosted',connectionTrackColor:'palette:forest'};
const theme={format:'auralis-theme',version:1,palette:{name:'My theme',accent:'#33AAFF',secondary:'#EE44CC',surface:[240,245,250],light:true},material:'frosted-water-351',customMaterial:null,settings};
test('theme files retain current palette, material, text and independent indicator settings',()=>{
 const parsed=parseTheme(JSON.parse(JSON.stringify(theme)));
 assert.equal(parsed.palette.accent,'#33aaff');
 assert.equal(parsed.settings.graphIndicator,'neon');
 assert.equal(parsed.settings.connectionTrackColor,'palette:forest');
 assert.equal(parsed.material,'frosted-water-351');
 assert.equal(paletteForTheme(parsed.palette).rgb,'51,170,255');
 assert.equal(themeId(parsed.palette),themeId({...parsed.palette,name:'MY THEME'}));
 const custom=parseTheme({...theme,material:'custom',customMaterial:materialPresets['brushed-glass']});
 assert.equal(custom.customMaterial.finish,'satin');
});
test('Aurora materials and bubble shapes survive theme export and import',()=>{
 for(const material of ['builtin-aurora-night','builtin-aurora-ice']){const parsed=parseTheme({...theme,material,settings:{...settings,progressShape:'bubble',connectionShape:'bubble'}});assert.equal(parsed.material,material);assert.equal(parsed.settings.progressShape,'bubble');assert.equal(parsed.settings.connectionShape,'bubble')}
});
test('theme files reject unsafe or invalid values and discard unrecognized content',()=>{
 for(const change of [{format:'other'},{version:2},{material:'url(evil)'},{palette:{...theme.palette,accent:'red;display:none'}},{palette:{...theme.palette,surface:[0,256,1]}},{palette:{...theme.palette,light:false}},{settings:{...settings,fontSize:100}},{settings:{...settings,graphShape:'bad'}}])assert.throws(()=>parseTheme({...theme,...change}));
 const parsed=parseTheme({...theme,css:'body{display:none}',palette:{...theme.palette,css:'unsafe'}});
 assert.equal('css' in parsed,false);assert.equal('css' in parsed.palette,false);
});

test('theme export captures current selections and imported edits apply to the app',async t=>{
 const {existsSync}=await import('node:fs');const {fileURLToPath}=await import('node:url');const {chromium}=await import('playwright-core');const {createServer}=await import('vite');
 const executablePath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');if(!executablePath||!existsSync(executablePath)){t.skip('Browser unavailable');return}
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 try{const page=await browser.newPage();await page.addInitScript(()=>{localStorage.setItem('mh-glass-theme','white-frost');localStorage.setItem('mh-glass-graph-indicator','neon');localStorage.setItem('mh-glass-progress-material','liquid-glass');window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'settings'},currentWebview:{label:'settings'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{if(cmd==='export_theme_file'){window.exportedTheme=JSON.parse(args.contents);return 'theme.json'}if(cmd==='glass_settings')return {};if(cmd==='glass_tool')return {tools:[],job:null};return null}}});await page.goto(server.resolvedUrls.local[0]+'?settings=1&tab=Appearance');await page.getByRole('button',{name:'Export current theme…'}).click();const saved=await page.evaluate(()=>window.exportedTheme);assert.equal(saved.settings.graphIndicator,'blue-purple');assert.equal(saved.settings.progressMaterial,'liquid-glass');assert.equal(saved.palette.light,true);saved.palette.name='Edited theme';saved.palette.accent='#1788cc';saved.settings.graphIndicator='ocean';await page.locator('label').filter({hasText:'Import theme…'}).locator('input').setInputFiles({name:'theme.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(saved))});await page.getByText('Imported Edited theme.').waitFor();assert.equal(await page.evaluate(()=>localStorage.getItem('mh-glass-graph-indicator')),'ocean');assert.ok(await page.locator('.cg-window.cg-custom-light').count());await page.getByRole('button',{name:'Export current theme…'}).click();assert.equal((await page.evaluate(()=>window.exportedTheme)).palette.accent,'#1788cc');
 const color=await page.locator('.cg-color-choices button').first().evaluate(el=>getComputedStyle(el).color);assert.ok(color.match(/\d+/g).map(Number).slice(0,3).every(v=>v<100),`Imported light theme text: ${color}`);
 }finally{await browser.close();await server.close()}
});
