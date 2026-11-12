import { test } from 'node:test';
import assert from 'node:assert/strict';
import { deflateSync } from 'node:zlib';
import { encode as jpegEncode } from 'jpeg-js';

import {
  decodeImage,
  toGrayscale,
  resizeGray,
  rotateGray,
  estimateSkewAngle,
  trimUniformMargins,
  contrastStretch,
  encodeBmpGray,
  preprocessCardImage,
  type RawImage,
} from './card-image.ts';

/** PNG RGBA mínimo (sem interlaço, bit depth 8) para os testes. */
function makePng(width: number, height: number, rgba: Uint8Array): Buffer {
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  ihdr[10] = 0; // deflate
  ihdr[11] = 0; // filter
  ihdr[12] = 0; // sem interlaço
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y += 1) {
    raw[y * (stride + 1)] = 0; // filtro None
    Buffer.from(rgba.buffer, y * stride, stride).copy(raw, y * (stride + 1) + 1);
  }
  const chunk = (type: string, data: Buffer): Buffer => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crcTable = crc32Table();
    let crc = 0xffffffff;
    for (const byte of body) {
      crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
    }
    crc = (crc ^ 0xffffffff) >>> 0;
    const crcBuf = Buffer.alloc(4);
    crcBuf.writeUInt32BE(crc);
    return Buffer.concat([len, body, crcBuf]);
  };
  return Buffer.concat([
    signature,
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

function crc32Table(): number[] {
  const table: number[] = [];
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c >>> 0;
  }
  return table;
}

/** JPEG sintético via jpeg-js (encode está no mesmo pacote). */
function makeJpeg(width: number, height: number, rgba: Uint8Array): Buffer {
  return Buffer.from(jpegEncode({ data: rgba, width, height }, 90).data);
}

function solidImage(width: number, height: number, gray: number): RawImage {
  const rgba = new Uint8Array(width * height * 4);
  for (let i = 0; i < width * height; i += 1) {
    rgba[i * 4] = gray;
    rgba[i * 4 + 1] = gray;
    rgba[i * 4 + 2] = gray;
    rgba[i * 4 + 3] = 255;
  }
  return { width, height, rgba };
}

test('decodifica PNG RGBA e nivela alpha sobre branco', () => {
  const width = 4;
  const height = 2;
  const rgba = new Uint8Array(width * height * 4);
  for (let i = 0; i < width * height; i += 1) {
    rgba[i * 4] = 0;
    rgba[i * 4 + 1] = 0;
    rgba[i * 4 + 2] = 0;
    rgba[i * 4 + 3] = i % 2 === 0 ? 255 : 0; // metade opaca, metade transparente
  }
  const img = decodeImage(makePng(width, height, rgba), 'image/png');
  assert.ok(img);
  const { gray } = toGrayscale(img);
  // Pixel opaco preto -> 0; pixel transparente -> fundo branco (255).
  assert.equal(gray[0], 0);
  assert.equal(gray[1], 255);
});

test('decodifica JPEG sintético', () => {
  const img = decodeImage(makeJpeg(8, 6, solidImage(8, 6, 128).rgba), 'image/jpeg');
  assert.ok(img);
  assert.equal(img.width, 8);
  assert.equal(img.height, 6);
});

test('formato não suportado devolve null (WEBP passa direto)', () => {
  assert.equal(decodeImage(Buffer.from('qualquer-coisa'), 'image/webp'), null);
});

test('ampliação bilinear preserva dimensões e intervalo', () => {
  const { gray, width, height } = toGrayscale(solidImage(10, 8, 100));
  const up = resizeGray(gray, width, height, 30, 24);
  assert.equal(up.width, 30);
  assert.equal(up.height, 24);
  assert.equal(up.gray.length, 30 * 24);
  assert.ok(up.gray.every((v) => v >= 0 && v <= 255));
});

test('BMP codificado tem header válido e pixels de volta', () => {
  const { gray, width, height } = toGrayscale(solidImage(5, 3, 200));
  const bmp = encodeBmpGray(gray, width, height);
  assert.equal(bmp.toString('ascii', 0, 2), 'BM');
  assert.equal(bmp.readUInt16LE(26), 1); // planes
  assert.equal(bmp.readUInt16LE(28), 24); // bpp
  assert.equal(bmp.readInt32LE(18), width);
  assert.equal(bmp.readInt32LE(22), height);
  // Linha de baixo do BMP é a primeira da imagem (ordem invertida).
  assert.equal(bmp[54], 200);
});

test('rotação de imagem reta e gira sem estourar', () => {
  const { gray, width, height } = toGrayscale(solidImage(20, 10, 255));
  const rotated = rotateGray(gray, width, height, 5);
  assert.equal(rotated.gray.length, rotated.width * rotated.height);
  assert.ok(rotated.width >= width);
});

test('estimador de inclinação acerta ângulos grandes e ignora imagem reta', () => {
  // Cartão sintético: blocos "tipo texto" (pequenos, densidade moderada)
  // dispostos em linhas — o que o filtro de densidade do estimador espera.
  const width = 420;
  const height = 220;
  const straight = new Uint8Array(width * height).fill(255);
  const drawTextLine = (baseY: number) => {
    for (let x = 30; x < width - 40; x += 24) {
      const w = 12 + ((x * 7) % 9);
      const h = 5;
      for (let dy = 0; dy < h; dy += 1) {
        for (let dx = 0; dx < w; dx += 1) {
          straight[(baseY + dy) * width + x + dx] = 30;
        }
      }
    }
  };
  drawTextLine(30);
  drawTextLine(90);
  drawTextLine(150);
  assert.equal(estimateSkewAngle(straight, width, height).angle, 0);

  // Mesmo conteúdo inclinado ~15°: y deslocado por x·tan(15°).
  const tan = Math.tan((15 * Math.PI) / 180);
  const tilted = new Uint8Array(width * height).fill(255);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const srcY = Math.round(y - x * tan);
      if (srcY >= 0 && srcY < height) tilted[y * width + x] = straight[srcY * width + x];
    }
  }
  const angle = estimateSkewAngle(tilted, width, height).angle;
  assert.ok(Math.abs(angle - 15) <= 2.5, `ângulo estimado ${angle}, esperado ~15`);
});

test('recorte de margens uniformes remove borda branca e mantém conteúdo', () => {
  const width = 60;
  const height = 60;
  const { gray } = toGrayscale(solidImage(width, height, 255));
  for (let y = 20; y < 40; y += 1) {
    for (let x = 10; x < 50; x += 1) gray[y * width + x] = 20;
  }
  const trimmed = trimUniformMargins(gray, width, height);
  assert.ok(trimmed.height < height);
  assert.ok(trimmed.width < width);
  assert.ok(trimmed.height >= 20);
});

test('stretch de contraste espalha histograma comprimido', () => {
  const flat = new Uint8Array(1000).fill(120);
  assert.equal(contrastStretch(flat), flat); // imagem plana: intocado
  const narrow = new Uint8Array(1000);
  for (let i = 0; i < 1000; i += 1) narrow[i] = 100 + (i % 20);
  const stretched = contrastStretch(narrow);
  const min = Math.min(...stretched);
  const max = Math.max(...stretched);
  assert.ok(max - min >= 200, `contraste final ${max - min}, esperado ~255`);
});

test('pipeline: WEBP segue original; PNG RGBA sai como BMP processado', () => {
  const original = Buffer.from('webp-falso');
  assert.equal(preprocessCardImage(original, 'image/webp'), original);

  const bmp = preprocessCardImage(makePng(30, 20, solidImage(30, 20, 90).rgba), 'image/png');
  assert.notEqual(bmp, original);
  assert.equal(bmp.toString('ascii', 0, 2), 'BM');
});
