import { test } from 'node:test';
import assert from 'node:assert/strict';

import { parseReceitaText } from './parse-receita.ts';

// Formato clássico de receituário impresso: medicamento em maiúsculas com
// dosagem, posologia na linha de baixo.
const RECEITA_CLASSICA = `Dr. João da Silva - CRM 123456
Paciente: Maria Oliveira
Data: 31/10/2026

DIPIRONA 500MG
Tomar 1 comprimido a cada 8 horas por 5 dias

AMOXICILINA 500MG
Tomar 1 cápsula de 8/8 horas por 7 dias

LOSARTANA 50MG
1 comprimido pela manhã, uso contínuo`;

test('extrai os três medicamentos da receita clássica', () => {
  const receita = parseReceitaText(RECEITA_CLASSICA);
  assert.equal(receita.medicamentos.length, 3);

  const [dipirona, amoxicilina, losartana] = receita.medicamentos;
  assert.equal(dipirona.nome, 'DIPIRONA');
  assert.equal(dipirona.dosagem, '500MG');
  assert.equal(dipirona.apresentacao, 'comprimido');
  assert.equal(dipirona.intervaloHoras, 8);
  assert.equal(dipirona.vezesAoDia, 3);
  assert.deepEqual(dipirona.horarios, ['00:00', '08:00', '16:00']);
  assert.equal(dipirona.duracaoDias, 5);

  assert.equal(amoxicilina.nome, 'AMOXICILINA');
  assert.equal(amoxicilina.intervaloHoras, 8);
  assert.equal(amoxicilina.duracaoDias, 7);

  assert.equal(losartana.nome, 'LOSARTANA');
  assert.equal(losartana.dosagem, '50MG');
  assert.equal(losartana.usoContinuo, true);
  assert.equal(losartana.duracaoDias, null);
  assert.deepEqual(losartana.horarios, ['08:00']);
});

test('ruído do rodapé nunca vira medicamento', () => {
  const receita = parseReceitaText(`
Dr. João da Silva - CRM 123456
Rua das Flores, 123 - Telefone (11) 99999-9999
RETORNO EM 30 DIAS
DIPIRONA 500MG
8/8 horas
  `);
  assert.equal(receita.medicamentos.length, 1);
  assert.equal(receita.medicamentos[0].nome, 'DIPIRONA');
});

test('posologia na mesma linha do nome é dividida', () => {
  const receita = parseReceitaText(`
OMEPRAZOL 20MG - tomar 1 comprimido de 12/12 horas
  `);
  const [omeprazol] = receita.medicamentos;
  assert.equal(omeprazol.nome, 'OMEPRAZOL');
  assert.equal(omeprazol.dosagem, '20MG');
  assert.equal(omeprazol.intervaloHoras, 12);
  assert.equal(omeprazol.vezesAoDia, 2);
  assert.deepEqual(omeprazol.horarios, ['08:00', '20:00']);
});

test('"2x ao dia" sem intervalo gera 2 horários distribuídos', () => {
  const receita = parseReceitaText(`
SERTRALINA 50MG
Tomar 1 comprimido 2x ao dia
  `);
  const [sertralina] = receita.medicamentos;
  assert.equal(sertralina.intervaloHoras, null);
  assert.equal(sertralina.vezesAoDia, 2);
  assert.deepEqual(sertralina.horarios, ['08:00', '20:00']);
});

test('períodos do dia viram horários correspondentes', () => {
  const receita = parseReceitaText(`
AZITROMICINA 500MG
Tomar 1 comprimido pela manhã e à noite
  `);
  const [azitromicina] = receita.medicamentos;
  assert.deepEqual(azitromicina.horarios, ['08:00', '22:00']);
});

test('8 em 8 horas por extenso também casa', () => {
  const receita = parseReceitaText(`
PREDNISONA 20MG
Tomar 2 comprimidos de 8 em 8 horas por 3 dias
  `);
  const [prednisona] = receita.medicamentos;
  assert.equal(prednisona.intervaloHoras, 8);
  assert.equal(prednisona.duracaoDias, 3);
});

test('dosagem na posologia quando falta no nome', () => {
  const receita = parseReceitaText(`
METFORMINA
Tomar 1 comprimido de 850mg de 12/12 horas
  `);
  const [metformina] = receita.medicamentos;
  assert.equal(metformina.nome, 'METFORMINA');
  assert.equal(metformina.dosagem, '850MG');
  assert.equal(metformina.intervaloHoras, 12);
});

test('numeração de lista é removida do nome', () => {
  const receita = parseReceitaText(`
1. HIDROCLOROTIAZIDA 25MG
1 comprimido ao dia pela manhã
  `);
  const [hidro] = receita.medicamentos;
  assert.equal(hidro.nome, 'HIDROCLOROTIAZIDA');
  assert.equal(hidro.vezesAoDia, 1);
  assert.deepEqual(hidro.horarios, ['08:00']);
});

test('receita sem medicamentos legíveis devolve lista vazia', () => {
  const receita = parseReceitaText(`
Dr. Fulano CRM 123
Receituário
Assinatura e carimbo
  `);
  assert.deepEqual(receita.medicamentos, []);
});

test('texto vazio devolve lista vazia e preserva o bruto', () => {
  const receita = parseReceitaText('');
  assert.deepEqual(receita.medicamentos, []);
  assert.equal(receita.rawText, '');
});

test('semanas e meses viram dias', () => {
  const receita = parseReceitaText(`
CLONAZEPAM 0,5MG
Tomar 1 comprimido à noite por 2 semanas
  `);
  const [clonazepam] = receita.medicamentos;
  assert.equal(clonazepam.duracaoDias, 14);
});
