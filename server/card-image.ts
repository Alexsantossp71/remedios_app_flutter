/**
 * Preprocessamento de imagem para o OCR de cartões (`server/ocr-runtime.ts`).
 *
 * As cinco carteirinhas de teste revelaram três classes de falha do
 * Tesseract puro (via API de produção, 12/11/2026):
 *
 *   1. PNG com canal alpha (carteirinha 300px)  -> texto vazio;
 *   2. foto de cartão inclinado ~25°           -> texto embaralhado;
 *   3. foto com fundo ocupado (mão,Blur)       -> lixo nas bordas.
 *
 * Este módulo decodifica a imagem (JPEG via jpeg-js, PNG via zlib nativo —
 * sem dependência nativa, o bundle CJS da Vercel não pode carregar módulos
 * como sharp), nivela alpha sobre branco, amplia imagens pequenas, estima e
 * corrige a inclinação por perfil de projeção (linhas de texto alinhadas
 * maximizam a variância dos somatórios por linha), recorta margens
 * uniformes, estica o contraste e devolve BMP 24-bit — formato que o core
 * WASM do Tesseract lê direto e que é trivial de escrever sem libs.
 *
 * Regra de ouro intacta: nada aqui inventa texto — só prepara pixels para
 * o OCR ler melhor.
 */
import { inflateSync } from 'node:zlib';
import { decode as jpegDecode } from 'jpeg-js';

/** jpeg-js não traz tipos — contrato mínimo usado aqui. */
declare module 'jpeg-js' {
  interface JpegImageData {
    width: number;
    height: number;
    data: Uint8Array;
  }
  export function decode(
    data: Uint8Array | ArrayBuffer | Buffer,
    opts?: { useTArray?: boolean; formatAsRGBA?: boolean },
  ): JpegImageData;
  export function encode(
    imgData: { data: Uint8Array; width: number; height: number },
    quality?: number,
  ): { width: number; height: number; data: Buffer };
}

export interface RawImage {
  width: number;
  height: number;
  /** RGBA, 8 bit por canal, comprimento width*height*4. */
  rgba: Uint8Array;
}

/* ------------------------------------------------------------------ */
/* Decodificação                                                       */
/* ------------------------------------------------------------------ */

/** Decodifica JPEG/PNG para RGBA. Retorna null quando o formato não é
 * suportado (ex.: PNG interlaçado, WEBP) — o chamador passa o buffer
 * original ao Tesseract, como antes. */
export function decodeImage(buffer: Buffer, mime: string): RawImage | null {
  if (mime === 'image/jpeg') {
    try {
      const img = jpegDecode(buffer, { useTArray: true, formatAsRGBA: true });
      return { width: img.width, height: img.height, rgba: img.data as Uint8Array };
    } catch {
      return null;
    }
  }
  if (mime === 'image/png') return decodePng(buffer);
  return null;
}

/** Decodificador PNG mínimo: bit depth 8/16, color types 0/2/3/4/6,
 * não interlaçado. O que aparecer diferente vira null (passthrough). */
function decodePng(buffer: Buffer): RawImage | null {
  // Assinatura PNG: 89 50 4E 47 0D 0A 1A 0A
  if (buffer.length < 57 || buffer.readUInt32BE(0) !== 0x89504e47) return null;

  let offset = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  let interlace = 0;
  let palette: Buffer | null = null;
  let trns: Buffer | null = null;
  const idat: Buffer[] = [];

  while (offset + 8 <= buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString('ascii', offset + 4, offset + 8);
    const data = buffer.subarray(offset + 8, offset + 8 + length);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      interlace = data[12];
    } else if (type === 'PLTE') {
      palette = Buffer.from(data);
    } else if (type === 'tRNS') {
      trns = Buffer.from(data);
    } else if (type === 'IDAT') {
      idat.push(data);
    } else if (type === 'IEND') {
      break;
    }
    offset += 12 + length;
  }

  if (!width || !height || interlace !== 0) return null;
  // Canais por tipo: 0=gray, 2=RGB, 3=palette, 4=gray+alpha, 6=RGBA.
  const channelsByType: Record<number, number> = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 };
  const channels = channelsByType[colorType];
  if (!channels) return null;
  if (![1, 2, 4, 8, 16].includes(bitDepth)) return null;
  if (colorType === 3 && ![1, 2, 4, 8].includes(bitDepth)) return null;
  if (!palette && colorType === 3) return null;

  let raw: Buffer;
  try {
    raw = inflateSync(Buffer.concat(idat));
  } catch {
    return null;
  }

  const bpp = Math.max(1, (channels * bitDepth) / 8);
  const stride = Math.ceil((width * channels * bitDepth) / 8);
  if (raw.length < height * (stride + 1)) return null;

  const out = new Uint8Array(width * height * 4);
  const prev = new Uint8Array(stride);
  const line = new Uint8Array(stride);

  for (let y = 0; y < height; y += 1) {
    const filter = raw[y * (stride + 1)];
    raw.copy(line, 0, y * (stride + 1) + 1, (y + 1) * (stride + 1));
    unfilterLine(filter, line, prev, bpp);
    for (let x = 0; x < width; x += 1) {
      let r = 0;
      let g = 0;
      let b = 0;
      let a = 255;
      if (colorType === 6) {
        if (bitDepth === 8) {
          r = line[x * 4];
          g = line[x * 4 + 1];
          b = line[x * 4 + 2];
          a = line[x * 4 + 3];
        } else {
          r = line[x * 8];
          g = line[x * 8 + 2];
          b = line[x * 8 + 4];
          a = line[x * 8 + 6];
        }
      } else if (colorType === 2) {
        if (bitDepth === 8) {
          r = line[x * 3];
          g = line[x * 3 + 1];
          b = line[x * 3 + 2];
        } else {
          r = line[x * 6];
          g = line[x * 6 + 2];
          b = line[x * 6 + 4];
        }
      } else if (colorType === 4) {
        if (bitDepth === 8) {
          r = g = b = line[x * 2];
          a = line[x * 2 + 1];
        } else {
          r = g = b = line[x * 4];
          a = line[x * 4 + 2];
        }
      } else if (colorType === 0) {
        r =
          g =
          b =
            bitDepth === 16
              ? line[x * 2]
              : bitDepth === 8
                ? line[x]
                : unpackBits(line, bitDepth, x);
      } else if (colorType === 3) {
        const index = unpackBits(line, bitDepth, x);
        if (index * 3 + 2 >= palette!.length) return null;
        r = palette![index * 3];
        g = palette![index * 3 + 1];
        b = palette![index * 3 + 2];
        if (trns && index < trns.length) a = trns[index];
      }
      const o = (y * width + x) * 4;
      out[o] = r;
      out[o + 1] = g;
      out[o + 2] = b;
      out[o + 3] = a;
    }
    prev.set(line);
  }

  return { width, height, rgba: out };
}

function unpackBits(line: Uint8Array, bitDepth: number, x: number): number {
  const bitPos = x * bitDepth;
  const byte = line[bitPos >> 3];
  const shift = 8 - bitDepth - (bitPos & 7);
  const mask = (1 << bitDepth) - 1;
  return (byte >> shift) & mask;
}

function unfilterLine(filter: number, line: Uint8Array, prev: Uint8Array, bpp: number): void {
  const n = line.length;
  if (filter === 0) return;
  if (filter === 1) {
    for (let i = bpp; i < n; i += 1) line[i] = (line[i] + line[i - bpp]) & 0xff;
    return;
  }
  if (filter === 2) {
    for (let i = 0; i < n; i += 1) line[i] = (line[i] + prev[i]) & 0xff;
    return;
  }
  if (filter === 3) {
    for (let i = 0; i < n; i += 1) {
      const left = i >= bpp ? line[i - bpp] : 0;
      line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xff;
    }
    return;
  }
  if (filter === 4) {
    for (let i = 0; i < n; i += 1) {
      const a = i >= bpp ? line[i - bpp] : 0;
      const b = prev[i];
      const c = i >= bpp ? prev[i - bpp] : 0;
      const p = a + b - c;
      const pa = Math.abs(p - a);
      const pb = Math.abs(p - b);
      const pc = Math.abs(p - c);
      const pred = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      line[i] = (line[i] + pred) & 0xff;
    }
  }
}

/* ------------------------------------------------------------------ */
/* Operações sobre tons de cinza                                       */
/* ------------------------------------------------------------------ */

/** RGBA -> cinza (luma 709), com alpha nivelado sobre fundo branco. */
export function toGrayscale(img: RawImage): { gray: Uint8Array; width: number; height: number } {
  const { width, height, rgba } = img;
  const gray = new Uint8Array(width * height);
  for (let i = 0; i < width * height; i += 1) {
    const a = rgba[i * 4 + 3] / 255;
    // Composição sobre branco: c' = c*a + 255*(1-a).
    const r = rgba[i * 4] * a + 255 * (1 - a);
    const g = rgba[i * 4 + 1] * a + 255 * (1 - a);
    const b = rgba[i * 4 + 2] * a + 255 * (1 - a);
    gray[i] = Math.round(0.2126 * r + 0.7152 * g + 0.0722 * b);
  }
  return { gray, width, height };
}

/** Reamostragem bilinear de uma imagem em cinza. */
export function resizeGray(
  gray: Uint8Array,
  width: number,
  height: number,
  newWidth: number,
  newHeight: number,
): { gray: Uint8Array; width: number; height: number } {
  const out = new Uint8Array(newWidth * newHeight);
  const scaleX = width / newWidth;
  const scaleY = height / newHeight;
  for (let y = 0; y < newHeight; y += 1) {
    const sy = Math.min(height - 1, Math.max(0, (y + 0.5) * scaleY - 0.5));
    const y0 = Math.floor(sy);
    const y1 = Math.min(height - 1, y0 + 1);
    const fy = sy - y0;
    for (let x = 0; x < newWidth; x += 1) {
      const sx = Math.min(width - 1, Math.max(0, (x + 0.5) * scaleX - 0.5));
      const x0 = Math.floor(sx);
      const x1 = Math.min(width - 1, x0 + 1);
      const fx = sx - x0;
      const p00 = gray[y0 * width + x0];
      const p10 = gray[y0 * width + x1];
      const p01 = gray[y1 * width + x0];
      const p11 = gray[y1 * width + x1];
      out[y * newWidth + x] = Math.round(
        p00 * (1 - fx) * (1 - fy) + p10 * fx * (1 - fy) + p01 * (1 - fx) * fy + p11 * fx * fy,
      );
    }
  }
  return { gray: out, width: newWidth, height: newHeight };
}

/** Rotação bilinear em torno do centro com fundo branco. */
export function rotateGray(
  gray: Uint8Array,
  width: number,
  height: number,
  angleDeg: number,
): { gray: Uint8Array; width: number; height: number } {
  const rad = (angleDeg * Math.PI) / 180;
  const cos = Math.cos(rad);
  const sin = Math.sin(rad);
  // Novo bounding box: recobre a imagem inteira girada.
  const newWidth = Math.ceil(Math.abs(width * cos) + Math.abs(height * sin));
  const newHeight = Math.ceil(Math.abs(width * sin) + Math.abs(height * cos));
  const out = new Uint8Array(newWidth * newHeight).fill(255);
  const cx = width / 2;
  const cy = height / 2;
  const ncx = newWidth / 2;
  const ncy = newHeight / 2;
  for (let y = 0; y < newHeight; y += 1) {
    for (let x = 0; x < newWidth; x += 1) {
      // Inverso: pixel do destino -> pixel da origem (rotação -ângulo).
      const dx = x - ncx;
      const dy = y - ncy;
      const sx = cos * dx + sin * dy + cx;
      const sy = -sin * dx + cos * dy + cy;
      if (sx < 0 || sy < 0 || sx >= width - 1 || sy >= height - 1) continue;
      const x0 = Math.floor(sx);
      const y0 = Math.floor(sy);
      const fx = sx - x0;
      const fy = sy - y0;
      const p00 = gray[y0 * width + x0];
      const p10 = gray[y0 * width + x0 + 1];
      const p01 = gray[(y0 + 1) * width + x0];
      const p11 = gray[(y0 + 1) * width + x0 + 1];
      out[y * newWidth + x] = Math.round(
        p00 * (1 - fx) * (1 - fy) + p10 * fx * (1 - fy) + p01 * (1 - fx) * fy + p11 * fx * fy,
      );
    }
  }
  return { gray: out, width: newWidth, height: newHeight };
}

/** Limiar de Otsu (histograma de 256 níveis). */
export function otsuThreshold(gray: Uint8Array): number {
  const hist = new Array<number>(256).fill(0);
  for (let i = 0; i < gray.length; i += 1) hist[gray[i]] += 1;
  const total = gray.length;
  let sum = 0;
  for (let i = 0; i < 256; i += 1) sum += i * hist[i];
  let sumB = 0;
  let wB = 0;
  let best = 0;
  let threshold = 128;
  for (let t = 0; t < 256; t += 1) {
    wB += hist[t];
    if (wB === 0) continue;
    const wF = total - wB;
    if (wF === 0) break;
    sumB += t * hist[t];
    const mB = sumB / wB;
    const mF = (sum - sumB) / wF;
    const between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      threshold = t;
    }
  }
  return threshold;
}

/**
 * Estima a inclinação do texto por perfil de projeção: alinhar as linhas
 * de texto maximiza a concentração de tinta em poucas linhas do histograma
 * deslocado (cisalhamento por y - x*tan θ). Busca grossa ±30° em passos de
 * 1° e refinamento ±1° em passos de 0,25°.
 *
 * Antes de pontuar, a tinta passa por um filtro de densidade local: só
 * pixels em janelas 16×16 com densidade moderada (texto) entram no score —
 * faixas sólidas do cartão (logotipo, bandas de cor) têm densidade ~100%
 * e enganariam o estimador. Devolve também `scoreRatio` = concentração no
 * ângulo escolhido ÷ concentração em 0°: abaixo de ~1,25 a imagem já está
 * alinhada (ou o estimador está chutando) e girar só estraga.
 */
export function estimateSkewAngle(
  gray: Uint8Array,
  width: number,
  height: number,
): { angle: number; scoreRatio: number } {
  const scale = Math.min(1, 420 / width);
  const small = scale < 1 ? resizeGray(gray, width, height, Math.max(1, Math.round(width * scale)), Math.max(1, Math.round(height * scale))) : { gray, width, height };
  const { gray: g, width: w, height: h } = small;
  const threshold = otsuThreshold(g);

  // Máscara de tinta + imagem integral para densidade local por janela.
  const mask = new Uint8Array(w * h);
  // Otsu separa classes [0..t] e [t+1..255]: o limiar pertence à tinta.
  for (let i = 0; i < w * h; i += 1) mask[i] = g[i] <= threshold ? 1 : 0;
  const integral = new Float64Array((w + 1) * (h + 1));
  for (let y = 0; y < h; y += 1) {
    let rowAcc = 0;
    for (let x = 0; x < w; x += 1) {
      rowAcc += mask[y * w + x];
      integral[(y + 1) * (w + 1) + (x + 1)] = integral[y * (w + 1) + (x + 1)] + rowAcc;
    }
  }
  const windowDensity = (x: number, y: number): number => {
    const half = 8;
    const x0 = Math.max(0, x - half);
    const x1 = Math.min(w, x + half + 1);
    const y0 = Math.max(0, y - half);
    const y1 = Math.min(h, y + half + 1);
    const area = (x1 - x0) * (y1 - y0);
    const sum =
      integral[y1 * (w + 1) + x1] -
      integral[y0 * (w + 1) + x1] -
      integral[y1 * (w + 1) + x0] +
      integral[y0 * (w + 1) + x0];
    return sum / area;
  };

  const xs: number[] = [];
  const ys: number[] = [];
  for (let y = 0; y < h; y += 1) {
    for (let x = 0; x < w; x += 1) {
      if (mask[y * w + x] === 1) {
        const density = windowDensity(x, y);
        // Texto mora em densidade moderada: sólidos (~1) e ruído isolado
        // (~0) ficam de fora.
        if (density >= 0.03 && density <= 0.55) {
          xs.push(x);
          ys.push(y);
        }
      }
    }
  }
  const inkCount = xs.length;
  if (inkCount < 150) return { angle: 0, scoreRatio: 1 }; // tinta de texto insuficiente: inconclusivo

  const score = (angleDeg: number): number => {
    const tan = Math.tan((angleDeg * Math.PI) / 180);
    const rows = new Float64Array(h + w);
    for (let i = 0; i < inkCount; i += 1) {
      const shifted = Math.round(ys[i] - xs[i] * tan);
      if (shifted >= 0 && shifted < rows.length) rows[shifted] += 1;
    }
    // Concentração: soma dos quadrados penaliza espalhamento.
    let sumSq = 0;
    for (let i = 0; i < rows.length; i += 1) sumSq += rows[i] * rows[i];
    return sumSq / inkCount;
  };

  let bestAngle = 0;
  let bestScore = score(0);
  const straightScore = bestScore;
  for (let angle = -30; angle <= 30; angle += 1) {
    const s = score(angle);
    if (s > bestScore) {
      bestScore = s;
      bestAngle = angle;
    }
  }
  const start = bestAngle - 1;
  for (let angle = start; angle <= bestAngle + 1; angle += 0.25) {
    const s = score(angle);
    if (s > bestScore) {
      bestScore = s;
      bestAngle = angle;
    }
  }
  // Ângulos pequenos são ruído; só vale corrigir inclinação perceptível.
  const angle = Math.abs(bestAngle) >= 1 ? bestAngle : 0;
  return { angle, scoreRatio: bestScore / straightScore };
}

/** Recorta margens uniformemente vazias (tinta < 0,5% por faixa). */
export function trimUniformMargins(
  gray: Uint8Array,
  width: number,
  height: number,
): { gray: Uint8Array; width: number; height: number } {
  const threshold = otsuThreshold(gray);
  const rowInk = new Float64Array(height);
  const colInk = new Float64Array(width);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (gray[y * width + x] <= threshold) {
        rowInk[y] += 1;
        colInk[x] += 1;
      }
    }
  }
  const rowMin = Math.max(2, width * 0.005);
  const colMin = Math.max(2, height * 0.005);
  const maxTrimY = Math.floor(height * 0.15);
  const maxTrimX = Math.floor(width * 0.15);

  let top = 0;
  while (top < maxTrimY && rowInk[top] < rowMin) top += 1;
  let bottom = height;
  while (bottom > height - maxTrimY && rowInk[bottom - 1] < rowMin) bottom -= 1;
  let left = 0;
  while (left < maxTrimX && colInk[left] < colMin) left += 1;
  let right = width;
  while (right > width - maxTrimX && colInk[right - 1] < colMin) right -= 1;

  if (bottom - top < 40 || right - left < 40) return { gray, width, height };
  if (top === 0 && left === 0 && bottom === height && right === width) {
    return { gray, width, height };
  }
  const newWidth = right - left;
  const newHeight = bottom - top;
  const out = new Uint8Array(newWidth * newHeight);
  for (let y = 0; y < newHeight; y += 1) {
    for (let x = 0; x < newWidth; x += 1) {
      out[y * newWidth + x] = gray[(y + top) * width + (x + left)];
    }
  }
  return { gray: out, width: newWidth, height: newHeight };
}

/** Estica o contraste linearmente entre os percentis 2 e 98. */
export function contrastStretch(gray: Uint8Array): Uint8Array {
  const hist = new Array<number>(256).fill(0);
  for (let i = 0; i < gray.length; i += 1) hist[gray[i]] += 1;
  const lowCut = gray.length * 0.02;
  const highCut = gray.length * 0.98;
  let acc = 0;
  let low = 0;
  let high = 255;
  for (let i = 0; i < 256; i += 1) {
    acc += hist[i];
    if (acc >= lowCut) {
      low = i;
      break;
    }
  }
  acc = 0;
  for (let i = 0; i < 256; i += 1) {
    acc += hist[i];
    if (acc >= highCut) {
      high = i;
      break;
    }
  }
  if (high - low < 6) return gray; // imagem praticamente plana: nada a esticar
  const out = new Uint8Array(gray.length);
  const span = high - low;
  for (let i = 0; i < gray.length; i += 1) {
    const v = Math.round(((gray[i] - low) * 255) / span);
    out[i] = v < 0 ? 0 : v > 255 ? 255 : v;
  }
  return out;
}

/* ------------------------------------------------------------------ */
/* Codificação BMP (entrada direta do core WASM do Tesseract)          */
/* ------------------------------------------------------------------ */

/** BMP 24-bit a partir de uma imagem em cinza (canais replicados). */
export function encodeBmpGray(
  gray: Uint8Array,
  width: number,
  height: number,
): Buffer {
  const rowSize = Math.ceil((width * 3) / 4) * 4;
  const pixelSize = rowSize * height;
  const fileSize = 54 + pixelSize;
  const bmp = Buffer.alloc(fileSize);
  bmp.write('BM', 0, 'ascii');
  bmp.writeUInt32LE(fileSize, 2);
  bmp.writeUInt32LE(54, 10);
  bmp.writeUInt32LE(40, 14);
  bmp.writeInt32LE(width, 18);
  bmp.writeInt32LE(height, 22);
  bmp.writeUInt16LE(1, 26);
  bmp.writeUInt16LE(24, 28);
  bmp.writeUInt32LE(0, 30);
  bmp.writeUInt32LE(pixelSize, 34);
  bmp.writeInt32LE(2835, 38);
  bmp.writeInt32LE(2835, 42);
  for (let y = 0; y < height; y += 1) {
    const srcY = height - 1 - y; // BMP é de baixo para cima
    for (let x = 0; x < width; x += 1) {
      const v = gray[srcY * width + x];
      const o = 54 + y * rowSize + x * 3;
      bmp[o] = v;
      bmp[o + 1] = v;
      bmp[o + 2] = v;
    }
  }
  return bmp;
}

/* ------------------------------------------------------------------ */
/* Pipeline                                                            */
/* ------------------------------------------------------------------ */

const MIN_SIDE_TARGET = 1100;
const MAX_SIDE_LIMIT = 2200;

/** Informações de cada etapa, para debug/laboratório. */
export interface PreprocessStages {
  decoded: { width: number; height: number } | null;
  afterUpscale: { width: number; height: number };
  skewAngle: number;
  skewScoreRatio: number;
  rotated: boolean;
  afterTrim: { width: number; height: number };
}

/**
 * Prepara a imagem para o OCR. Recebe os bytes originais e o MIME e
 * devolve um Buffer de imagem (BMP) já processado — ou o buffer original,
 * quando nada pode ser feito (formato desconhecido) ou nada precisa ser
 * feito (WEBP segue como veio: não há decodificador sem dependências).
 *
 * `debug`, quando informado, recebe o estado de cada etapa (usado pelo
 * laboratório e pelos testes para auditar decisões do pipeline).
 */
export function preprocessCardImage(
  buffer: Buffer,
  mime: string,
  debug?: (stages: PreprocessStages) => void,
): Buffer {
  const img = decodeImage(buffer, mime);
  const stages: PreprocessStages = {
    decoded: img ? { width: img.width, height: img.height } : null,
    afterUpscale: { width: 0, height: 0 },
    skewAngle: 0,
    skewScoreRatio: 1,
    rotated: false,
    afterTrim: { width: 0, height: 0 },
  };
  if (!img || img.width < 8 || img.height < 8) {
    debug?.(stages);
    return buffer;
  }

  let { gray, width, height } = toGrayscale(img);

  // Teto de tamanho: protege memória/tempo do Lambda antes de ampliar.
  const maxSide = Math.max(width, height);
  if (maxSide > MAX_SIDE_LIMIT) {
    const factor = MAX_SIDE_LIMIT / maxSide;
    const scaled = resizeGray(gray, width, height, Math.round(width * factor), Math.round(height * factor));
    gray = scaled.gray;
    width = scaled.width;
    height = scaled.height;
  }

  // Ampliação: cartão pequeno demais deixa o Tesseract cego (caso 300px).
  const minSide = Math.min(width, height);
  if (minSide < 700) {
    const factor = Math.min(3.5, MIN_SIDE_TARGET / minSide);
    const scaled = resizeGray(gray, width, height, Math.round(width * factor), Math.round(height * factor));
    gray = scaled.gray;
    width = scaled.width;
    height = scaled.height;
  }
  stages.afterUpscale = { width, height };

  // Inclinação: corrige fotos tortas (cartão inclinado ~25°). Só roda
  // quando o alinhamento melhora MUITO (score 1,25×) — foto com fundo
  // ocupado engana o estimador e girar errado estraga um OCR bom.
  // O sinal é invertido: o cisalhamento do estimador mede a inclinação do
  // texto, e a correção gira no sentido oposto (convenção do rotateGray).
  const angle = estimateSkewAngle(gray, width, height);
  stages.skewAngle = angle.angle;
  stages.skewScoreRatio = angle.scoreRatio;
  if (angle.angle !== 0 && angle.scoreRatio >= 1.25) {
    const rotated = rotateGray(gray, width, height, -angle.angle);
    gray = rotated.gray;
    width = rotated.width;
    height = rotated.height;
    stages.rotated = true;
  }

  // Margens uniformes (screenshots/scans) saem; fundo ocupado (foto na
  // mão) é preservado — o recorte é limitado a 15% por lado.
  const trimmed = trimUniformMargins(gray, width, height);
  gray = trimmed.gray;
  width = trimmed.width;
  height = trimmed.height;
  stages.afterTrim = { width, height };

  gray = contrastStretch(gray);

  debug?.(stages);
  return encodeBmpGray(gray, width, height);
}
