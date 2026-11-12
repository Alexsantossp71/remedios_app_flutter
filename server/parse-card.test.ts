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

test('linha em branco entre rótulo e valor não perde o campo (OCR real: "Validade:", "", "04/2028")', () => {
  const card = parseCardText(
    'UNIMED Nacional Plus\nN Cartao:\n0611 4002 7385 6021\nNome do titular:\nMARIA APARECIDA SOUZA\nValidade:\n\n04/2028',
  );
  assert.equal(card.validity, '04/2028');
  assert.equal(card.cardNumber, '0611400273856021');
});

test('código de beneficiário após linha em branco também é casado', () => {
  const card = parseCardText('UNIMED\nBENEFICIARIO:\n\n456789123\nVALIDADE 12/2028');
  assert.equal(card.beneficiaryCode, '456789123');
});

test('titular a duas linhas do rótulo (linha em branco no meio) é encontrado', () => {
  const card = parseCardText('UNIMED\nNOME DO TITULAR:\n\nMARIA APARECIDA SOUZA');
  assert.equal(card.notes, 'Titular: MARIA APARECIDA SOUZA');
});

test('rótulo N CARTAO é reconhecido (layout "N Cartao:")', () => {
  const card = parseCardText('UNIMED\nN CARTAO 0611400273856021\nVALIDADE 12/2028');
  assert.equal(card.cardNumber, '0611400273856021');
});

test('gap de linhas em branco não inventa validade de rótulo sem data', () => {
  const card = parseCardText('UNIMED\nVALIDADE:\n\nNOME DO TITULAR:\nMARIA SOUZA');
  assert.equal(card.validity, '');
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
/* ------------------------------------------------------------------ */
/* Cenários reais (cinco carteirinhas de teste, 12/11/2026)            */
/* ------------------------------------------------------------------ */

test('reconstrói número formatado com pontos e traço (carteirinha SIM/Unimed)', () => {
  const card = parseCardText(
    `VIVA MAIS. NOVO SIM SAUDE
0000000000 0000.0000.000000.00-0
Número da matrícula SIM
JOÃO DA SILVA SOUZA
Nome do beneficiário`,
  );
  assert.equal(card.provider, 'SIM Saude');
  // 4+4+6+2+1 dígitos do número formatado, ignorando separadores.
  assert.equal(card.cardNumber, '00000000000000000');
  assert.equal(card.notes, 'Titular: JOÃO DA SILVA SOUZA');
});

test('número em grupos com O/0 confundidos (app Unimed Virtual)', () => {
  const card = parseCardText(
    `Unimed | Somos
COLABORADORES TOTAL CLASS A? EMP
O 029 100100 100 100 O
EDUARDO OLIVEIRA
Nome do Beneficiário`,
  );
  // 'O' nas pontas vira '0'; grupos são concatenados.
  assert.equal(card.cardNumber, '0029100100100100');
  assert.equal(card.notes, 'Titular: EDUARDO OLIVEIRA');
  assert.ok(card.name.includes('COLABORADORES'));
});

test('validade em layout de colunas vem da última data da linha de cima', () => {
  const card = parseCardText(
    `CARTÃO SAÚDE
CAROLINE MELO DE CASTRO
0101 010101010101 O
30/10/2009 30/01/2020 30/01/2021
NASCIMENTO VIGÊNCIA VALIDADE`,
  );
  // NASCIMENTO e VIGÊNCIA não podem vencer a VALIDADE (última coluna).
  assert.equal(card.validity, '01/2021');
  assert.equal(card.cardNumber, '0101010101010101');
});

test('validade MM/YYYY continua sendo lida', () => {
  const card = parseCardText('UNIMED\nVALIDADE 07/2029');
  assert.equal(card.validity, '07/2029');
});

test('titular pode vir abaixo do rótulo (Nome do Beneficiário)', () => {
  const card = parseCardText(
    `Unimed
EDUARDO OLIVEIRA
Nome do Beneficiário`,
  );
  assert.equal(card.notes, 'Titular: EDUARDO OLIVEIRA');
  // O titular não disputa o campo de nome do plano.
  assert.notEqual(card.name, 'EDUARDO OLIVEIRA');
});

test('lixo de OCR não vira nome do plano', () => {
  const card = parseCardText(
    `EE bb.
mm CÁ
VIVA MAIS. NOVO SIM SAUDE`,
  );
  assert.notEqual(card.name, 'EE bb.');
  assert.notEqual(card.name, 'mm CÁ');
  assert.ok(card.name.length >= 4);
});

test('operadoras novas das carteirinhas de teste', () => {
  assert.equal(parseCardText('Salutá Card').provider, 'Saluta');
  assert.equal(parseCardText('PREVENT CARTÃO SAÚDE').provider, 'Prevent');
  assert.equal(parseCardText('NOVO SIM SAUDE Plano').provider, 'SIM Saude');
});

test('nome do plano sai da linha da operadora quando lá está a palavra PLANO', () => {
  const card = parseCardText('E Salutá PLANO FAMILIAR\nTitular VIA\nLeandro Castan');
  assert.equal(card.provider, 'Saluta');
  assert.equal(card.name, 'PLANO FAMILIAR');
  assert.equal(card.notes, 'Titular: Leandro Castan');
});

test('datas não viram número de carteirinha', () => {
  const card = parseCardText(
    `UNIMED
30/10/2009 30/01/2020 30/01/2021
NASCIMENTO VIGÊNCIA VALIDADE`,
  );
  assert.equal(card.cardNumber, '');
});
