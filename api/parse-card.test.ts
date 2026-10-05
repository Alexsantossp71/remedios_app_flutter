import { test } from 'node:test';
import assert from 'node:assert/strict';

import { parseCardText } from './parse-card.ts';

// Texto exato devolvido pelo Tesseract na fixture do cartão.
const OCR_CARTAO = `UNIMED

NACIONAL FLEX
CARTEIRINHA 1234567890123456
GRUPO 987654321
BENEFICIARIO 456789123
VALIDADE 12/2028
AMBULATORIAL + HOSPITALAR`;

test('extrai todos os campos de um cartão legível', () => {
  const card = parseCardText(OCR_CARTAO);
  assert.equal(card.provider, 'Unimed');
  assert.equal(card.name, 'NACIONAL FLEX');
  assert.equal(card.cardNumber, '1234567890123456');
  assert.equal(card.groupNumber, '987654321');
  assert.equal(card.beneficiaryCode, '456789123');
  assert.equal(card.validity, '12/2028');
  assert.equal(card.coverageType, 'Ambulatorial + Hospitalar');
});

test('nunca inventa: texto vazio devolve tudo vazio', () => {
  const card = parseCardText('');
  assert.equal(card.name, '');
  assert.equal(card.provider, '');
  assert.equal(card.cardNumber, '');
  assert.equal(card.groupNumber, '');
  assert.equal(card.beneficiaryCode, '');
  assert.equal(card.validity, '');
  assert.equal(card.coverageType, '');
  assert.equal(card.rawText, '');
});

test('rótulo sem valor não vira número inventado', () => {
  const card = parseCardText('UNIMED\nCARTEIRINHA\nGRUPO\nVALIDADE');
  assert.equal(card.cardNumber, '');
  assert.equal(card.groupNumber, '');
  assert.equal(card.validity, '');
  // Provider ainda é achado, então o cliente mostra o erro de "não encontrei dados".
  assert.equal(card.provider, 'Unimed');
});

test('tolera ruído de OCR entre rótulo e valor', () => {
  const card = parseCardText(
    'UNIMED\nCARTEIRINHA — 1234567890123456\nVALIDADE 12 - 2028',
  );
  assert.equal(card.cardNumber, '1234567890123456');
  assert.equal(card.validity, '12/2028');
});

test('lê valor na linha seguinte quando o rótulo vem sozinho', () => {
  const card = parseCardText('UNIMED\nCARTEIRINHA\n1234567890123456');
  assert.equal(card.cardNumber, '1234567890123456');
});

test('aceita acentos e variações de rótulo', () => {
  const card = parseCardText(
    'SULAMÉRICA\nPLANO ESPECIAL\nNº CARTEIRINHA 987654321012345\nBENEFICIÁRIO 456123789',
  );
  assert.equal(card.provider, 'Sulamerica');
  assert.equal(card.beneficiaryCode, '456123789');
});

test('sem rótulo de cartão, usa a maior sequência longa de dígitos', () => {
  const card = parseCardText('UNIMED\n112233445566778899');
  assert.equal(card.cardNumber, '112233445566778899');
});

test('rejeita mês inválido na validade', () => {
  const card = parseCardText('UNIMED\nVALIDADE 19/2028');
  assert.equal(card.validity, '');
});

test('não confunde a data de validade com número de cartão', () => {
  const card = parseCardText(OCR_CARTAO);
  assert.notEqual(card.cardNumber, '122028');
  assert.equal(card.cardNumber, '1234567890123456');
});

test('dedup cobertura repetida', () => {
  const card = parseCardText('UNIMED\nAMBULATORIAL\nAMBULATORIAL');
  assert.equal(card.coverageType, 'Ambulatorial');
});

test('preserva o texto bruto para conferência do usuário', () => {
  const card = parseCardText(OCR_CARTAO);
  assert.equal(card.rawText, OCR_CARTAO.trim());
});