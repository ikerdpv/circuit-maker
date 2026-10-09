// Crea un .ico (con imágenes PNG dentro) a partir de varios PNG cuadrados.
// Uso: node make-ico.mjs salida.ico 16.png 32.png 48.png 256.png
import fs from 'fs';

const [out, ...pngs] = process.argv.slice(2);
const images = pngs.map(p => {
  const data = fs.readFileSync(p);
  return { data, w: data.readUInt32BE(16), h: data.readUInt32BE(20) };
});
const header = Buffer.alloc(6);
header.writeUInt16LE(0, 0);
header.writeUInt16LE(1, 2);
header.writeUInt16LE(images.length, 4);
let offset = 6 + 16 * images.length;
const entries = images.map(img => {
  const e = Buffer.alloc(16);
  e.writeUInt8(img.w >= 256 ? 0 : img.w, 0);
  e.writeUInt8(img.h >= 256 ? 0 : img.h, 1);
  e.writeUInt16LE(1, 4);
  e.writeUInt16LE(32, 6);
  e.writeUInt32LE(img.data.length, 8);
  e.writeUInt32LE(offset, 12);
  offset += img.data.length;
  return e;
});
fs.writeFileSync(out, Buffer.concat([header, ...entries, ...images.map(i => i.data)]));
