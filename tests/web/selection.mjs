// Prueba la selección múltiple y el teclado de la versión de Windows/web (windows/app/index.html)
// con Chrome automático: ratón, teclado y pantalla táctil de verdad.
// Uso: cd tests/web && npm install && npm test        (necesita Google Chrome instalado)
import puppeteer from 'puppeteer-core';
import path from 'path';
import { fileURLToPath } from 'url';

const here = path.dirname(fileURLToPath(import.meta.url));
const page_url = 'file://' + path.resolve(here, '../../windows/app/index.html');
const chrome = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

let failures = 0;
const check = (ok, what) => { console.log((ok ? 'OK    ' : 'FALLO ') + what); if (!ok) failures++; };

const browser = await puppeteer.launch({ executablePath: chrome, headless: true, args: ['--force-device-scale-factor=1'] });
const page = await browser.newPage();
const errors = [];
page.on('pageerror', e => errors.push(e.message));
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
await page.setViewport({ width: 1366, height: 768, hasTouch: true });
await page.goto(page_url);
await page.evaluate(() => { loadCircuit(example(0)); zoomAt(1, 0, 0); pan = P(0, 0); });

const scr = (gx, gy) => page.evaluate((gx, gy) => {
  const r = canvas.getBoundingClientRect();
  return { x: r.left + pan.x + gx * 20 * zoom, y: r.top + pan.y + gy * 20 * zoom };
}, gx, gy);
const names = () => page.evaluate(() => selectedComps().map(k => k.name).sort());
const count = () => page.evaluate(() => ({ comps: circuit.components.length, wires: circuit.wires.length, sel: selection.length }));
const comp = n => page.evaluate(n => { const k = circuit.components.find(k => k.name === n); return k && { pos: k.pos, rot: k.rot }; }, n);
const withKey = async (key, fn) => { await page.keyboard.down(key); await fn(); await page.keyboard.up(key); };
const click = async (gx, gy) => { const p = await scr(gx, gy); await page.mouse.click(p.x, p.y); };
const drag = async (a, b) => {
  const p = await scr(...a), q = await scr(...b);
  await page.mouse.move(p.x, p.y); await page.mouse.down();
  await page.mouse.move(q.x, q.y, { steps: 8 }); await page.mouse.up();
};

const total = (await count()).comps;

// 1. Rectángulo de selección
await drag([8, 7], [21, 12]);
check(JSON.stringify(await names()) === '["E1","R1","S1"]', `rectángulo selecciona E1, R1 y S1 (${await names()})`);
check(await page.evaluate(() => marquee === null), 'el rectángulo desaparece al soltar');
check((await page.$eval('#sel h3', e => e.textContent)).includes('elementos seleccionados'), 'el panel muestra «N elementos seleccionados»');

// 2. Supr borra todo lo seleccionado; Ctrl+Z lo recupera
const before = await count();
await page.keyboard.press('Delete');
let now = await count();
check(now.comps === total - 3 && now.wires < before.wires, 'Supr borra las 3 piezas y sus cables seleccionados');
await withKey('Control', () => page.keyboard.press('z'));
check((await count()).comps === total, 'Ctrl+Z lo recupera');

// 3. Clic y Ctrl+clic
await click(28, 12);
check(JSON.stringify(await names()) === '["L1"]', 'clic selecciona solo L1');
await withKey('Control', () => click(22, 10));
check(JSON.stringify(await names()) === '["L1","R1"]', 'Ctrl+clic añade R1');
await withKey('Control', () => click(22, 10));
check(JSON.stringify(await names()) === '["L1"]', 'Ctrl+clic otra vez quita R1');
await withKey('Shift', () => click(22, 10));
check(JSON.stringify(await names()) === '["L1","R1"]', 'Mayús+clic añade R1');

// 4. Arrastrar una mueve las dos
const l1 = await comp('L1'), r1 = await comp('R1');
await drag([28, 12], [31, 12]);
const l1b = await comp('L1'), r1b = await comp('R1');
check(l1b.pos.x === l1.pos.x + 3 && r1b.pos.x === r1.pos.x + 3, 'arrastrar L1 mueve L1 y R1 juntas');
check(await page.evaluate(() => !result.error && Math.abs(result.comps[circuit.components[0].id].i) > 0.1), 'el circuito sigue conectado tras moverlas');
check((await page.evaluate(() => undoStack.length)) > 0 && JSON.stringify(await names()) === '["L1","R1"]', 'siguen seleccionadas tras moverlas');

// 5. R gira las dos (un solo paso de deshacer)
await page.keyboard.press('r');
check((await comp('L1')).rot === (l1.rot + 1) % 4 && (await comp('R1')).rot === (r1.rot + 1) % 4, 'R gira las dos');
await withKey('Control', () => page.keyboard.press('z'));
check((await comp('L1')).rot === l1.rot && (await comp('R1')).rot === r1.rot, 'un solo Ctrl+Z deshace el giro de las dos');
await withKey('Control', () => page.keyboard.press('z'));

// 6. Ctrl+A, Esc
await withKey('Control', () => page.keyboard.press('a'));
now = await count();
check(now.sel === now.comps + now.wires, 'Ctrl+A selecciona todo');
await page.keyboard.press('Escape');
check((await count()).sel === 0, 'Esc quita la selección');

// 7. Mayús+rectángulo añade; Retroceso borra
await click(28, 12);
const p = await scr(8, 7), q = await scr(11, 15);
await page.keyboard.down('Shift');
await page.mouse.move(p.x, p.y); await page.mouse.down(); await page.mouse.move(q.x, q.y, { steps: 6 }); await page.mouse.up();
await page.keyboard.up('Shift');
check(JSON.stringify(await names()) === '["E1","L1"]', `Mayús+rectángulo añade E1 a L1 (${await names()})`);
await page.keyboard.press('Backspace');
check(!(await comp('E1')) && !(await comp('L1')), 'Retroceso (la tecla de borrar de Mac y Chromebook) borra la selección');
await withKey('Control', () => page.keyboard.press('z'));

// 8. Escribiendo en el campo de nombre, Retroceso borra texto y no piezas
await click(22, 10);
await page.$eval('input.name', e => { e.focus(); e.setSelectionRange(e.value.length, e.value.length); });
await page.keyboard.press('Backspace');
check(await page.$eval('input.name', e => e.value) === 'R', 'Retroceso en el campo de nombre borra una letra');
check((await count()).comps === total, 'y no borra ninguna pieza');
await page.keyboard.press('Escape');

// 9. Un clic en un hueco quita la selección
await click(40, 25);
check((await count()).sel === 0, 'clic en un hueco quita la selección');

// 10. Con el dedo, arrastrar en un hueco desplaza (no selecciona)
const pan0 = await page.evaluate(() => ({ ...pan }));
const a = await scr(40, 25);
const t = await page.touchscreen.touchStart(a.x, a.y);
await t.move(a.x - 30, a.y - 20); await t.move(a.x - 60, a.y - 40); await t.end();
const pan1 = await page.evaluate(() => ({ ...pan }));
check(Math.round(pan1.x - pan0.x) === -60 && Math.round(pan1.y - pan0.y) === -40 && (await count()).sel === 0, 'con el dedo, arrastrar en un hueco desplaza el esquema');

check(errors.length === 0, 'sin errores de JavaScript ' + JSON.stringify(errors));
console.log(failures ? `${failures} FALLOS` : 'TODO BIEN');
await browser.close();
process.exit(failures ? 1 : 0);
