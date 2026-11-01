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

test('cabeçalho de clínica não vira medicamento', () => {
  const receita = parseReceitaText(`
CLINICA MEDICA SAO LUCAS
Dr. Ana Souza - CRM 123456
Paciente: Joao Pereira Data: 31/10/2026
DIPIRONA 500MG
Tomar 1 comprimido a cada 8 horas por 5 dias
  `);
  assert.equal(receita.medicamentos.length, 1);
  assert.equal(receita.medicamentos[0].nome, 'DIPIRONA');
});

test('"dia sim, dia não" marca dias alternados', () => {
  const receita = parseReceitaText(`
CALCITRIOL 0,5MG
Tomar 1 cápsula pela manhã, dia sim, dia não
  `);
  const [calcitriol] = receita.medicamentos;
  assert.equal(calcitriol.nome, 'CALCITRIOL');
  assert.equal(calcitriol.diasAlternados, true);
  assert.deepEqual(calcitriol.horarios, ['08:00']);
});

test('"em dias alternados" (variação escrita) também marca', () => {
  const receita = parseReceitaText(`
PREDNISONA 20MG
Tomar 2 comprimidos pela manhã em dias alternados
  `);
  const [prednisona] = receita.medicamentos;
  assert.equal(prednisona.diasAlternados, true);
});

test('posologia comum não marca dias alternados', () => {
  const receita = parseReceitaText(RECEITA_CLASSICA);
  for (const med of receita.medicamentos) {
    assert.equal(med.diasAlternados, false, med.nome);
  }
});

test('dia sim, dia não na mesma linha do nome é dividido', () => {
  const receita = parseReceitaText(`
SUPLEMENTO D 2000UI DIA SIM DIA NÃO
Tomar 1 cápsula pela manhã
  `);
  const [suplemento] = receita.medicamentos;
  assert.equal(suplemento.nome, 'SUPLEMENTO D');
  assert.equal(suplemento.diasAlternados, true);
});

test('hospital e farmácia também são ruído', () => {
  const receita = parseReceitaText(`
HOSPITAL DAS CLINICAS
FARMACIA POPULAR
DIPIRONA 500MG
8/8 horas
  `);
  assert.equal(receita.medicamentos.length, 1);
  assert.equal(receita.medicamentos[0].nome, 'DIPIRONA');
});

// Receituário eletrônico (padrão My Prescription/ICP Brasil): layout de
// tabela com dados do paciente, do emitente, hash de assinatura e colunas
// "Uso | Medicamento | Dosagem | Posologia | Frequência | Duração". O OCR
// real devolve tudo isso junto — o medicamento é uma linha só.
const RECEITA_ELETRONICA = `My Prescription
Paciente: José da Silva DT. NASC': 23/06/2000
Endereço: Rua José da Silva, 111 CPF: 000.000.000-00
Bairro: José da Silva CEP: 00000-000
IDENTIFICAÇÃO DO EMITENTE
Nome da Instituição: Meu consultório
| Endereço: Rua José da Silva, 112 |
| CEP: 00000-000 |
Telefone: (00) 00000-0000
RECEITUARIO CONTROLE ESPECIAL
Medicamentos Prescritos
Uso: Medicamento: Dosagem: Posologia: Frequência: Duração:
ORAL TRAMAL 100 MG COM REVL 1COMP 12/12 HORAS 30 DIAS
Observações:
Data: 29 de Maio de 2020 Assinado com certificado digital - ICP Brasil
931f£27432240bcebaf46dec592bfedo9e - 29/05/2020 18:56:28
Dr(a). Júlio
Cirurgião Geral
C.R.M: 000000 - SP
IDENTIFICAÇÃO DO COMPRADOR IDENTIFICAÇÃO DO FORNECEDOR
Nome:
| Ident: Org. Emissor: | |
| Endereço: |
| Cidade: | |
Telefone: Assinatura do Farmacêutico
ACESSE A RECEITA DIGITAL
= . E] Otsensação: IC P
Em conformidade com à Portaria MS nº 467/2020 a autenticidade do documento deve ser checada no site https://assinaturadigital.iti.gov.br; Brasil
A Conferir, por meio do site www.cfm.org.br (menu CIDADÃO, sub menu BUSCA POR MÉDICO), se o prescritor é realmente médico:
[=] Fr "e Este receituário permanecerá disponível para acesso em meio eletrônico através do link disponível no OR Code,`;

test('receituário eletrônico devolve só o medicamento, completo', () => {
  const receita = parseReceitaText(RECEITA_ELETRONICA);
  assert.equal(receita.medicamentos.length, 1);

  const [tramal] = receita.medicamentos;
  // A linha de tabela carrega a coluna "Uso" (ORAL) e a posologia; o nome
  // reconhecido no índice da ANVISA reduz o header a "TRAMAL".
  assert.equal(tramal.nome, 'TRAMAL');
  assert.equal(tramal.dosagem, '100 MG');
  assert.equal(tramal.intervaloHoras, 12);
  assert.equal(tramal.vezesAoDia, 2);
  assert.deepEqual(tramal.horarios, ['08:00', '20:00']);
  // "30 DIAS" na coluna Duração, sem "por" na frente.
  assert.equal(tramal.duracaoDias, 30);
  assert.equal(tramal.diasAlternados, false);
  // Posologia limpa: sem hash de assinatura, sem rótulo de formulário.
  assert.equal(tramal.observacao, '12/12 HORAS 30 DIAS');
});

test('rótulos do formulário não viram medicamento', () => {
  const receita = parseReceitaText(`
My Prescription
Medicamentos Prescritos
Observações
IDENTIFICAÇÃO DO EMITENTE
Ao, "* -*
= . E] Otsensação: IC P
  `);
  assert.deepEqual(receita.medicamentos, []);
});

test('nome conhecido sozinho abre medicamento', () => {
  const receita = parseReceitaText(`
Dr. Júlio CRM 000000
TRAMAL
12/12 HORAS 30 DIAS
  `);
  assert.equal(receita.medicamentos.length, 1);
  assert.equal(receita.medicamentos[0].nome, 'TRAMAL');
  assert.equal(receita.medicamentos[0].intervaloHoras, 12);
  assert.equal(receita.medicamentos[0].duracaoDias, 30);
});

test('nome desconhecido sozinho não abre medicamento', () => {
  const receita = parseReceitaText(`
IDENTIFICACAO DO EMITENTE
  `);
  assert.deepEqual(receita.medicamentos, []);
});

test('manipulado fora do catálogo mantém o nome limpo', () => {
  const receita = parseReceitaText(`
ORAL FORMULA MANIPULADA 30 CAPSULAS
Tomar 1 capsula de 12/12 horas por 20 dias
  `);
  assert.equal(receita.medicamentos.length, 1);
  const [manipulado] = receita.medicamentos;
  // Via de administração e quantidade saem; o nome segue editável na conferência.
  assert.equal(manipulado.nome, 'FORMULA MANIPULADA');
  assert.equal(manipulado.apresentacao, 'cápsula');
  assert.equal(manipulado.intervaloHoras, 12);
  assert.equal(manipulado.duracaoDias, 20);
});

test('grafia do nome vem da própria receita, não do catálogo', () => {
  const receita = parseReceitaText(`
Tramal 100mg
12/12 horas 30 dias
  `);
  assert.equal(receita.medicamentos[0].nome, 'Tramal');
  assert.equal(receita.medicamentos[0].dosagem, '100MG');
});

test('linha de continuação sem informação não suja a posologia', () => {
  const receita = parseReceitaText(`
TRAMAL 100MG
12/12 HORAS 30 DIAS
= . E] Otsensação: IC P
  `);
  assert.equal(receita.medicamentos[0].observacao, '12/12 HORAS 30 DIAS');
});

// --- Frequência semanal ("N vezes por semana") ---

test('metotrexato 1x por semana vira frequência semanal com o dia nomeado', () => {
  const receita = parseReceitaText(`
Dr. Júlio CRM 000000
METOTREXATO 15MG
Tomar 1 comprimido por semana, aos sábados
  `);
  assert.equal(receita.medicamentos.length, 1);
  const [metotrexato] = receita.medicamentos;
  assert.equal(metotrexato.nome, 'METOTREXATO');
  assert.equal(metotrexato.vezesPorSemana, 1);
  assert.deepEqual(metotrexato.diasDaSemana, [6]);
  // Semana não é dia: nada de vezesAoDia ou intervalo fantasma.
  assert.equal(metotrexato.vezesAoDia, null);
  assert.equal(metotrexato.intervaloHoras, null);
});

test('"uma vez por semana" e "semanalmente" contam como 1x sem dígito', () => {
  const receita = parseReceitaText(`
ACIDO FOLICO 5MG
Tomar uma vez por semana
DIPIRONA 500MG
Tomar semanalmente
  `);
  const [acidoFolico, dipirona] = receita.medicamentos;
  assert.equal(acidoFolico.vezesPorSemana, 1);
  assert.equal(dipirona.vezesPorSemana, 1);
});

test('"2x/semana" sem dia nomeado deixa a escolha para a conferência', () => {
  const receita = parseReceitaText(`
FUROSEMIDA 40MG
Tomar 2 comprimidos 2x/semana
  `);
  const [furosemida] = receita.medicamentos;
  assert.equal(furosemida.vezesPorSemana, 2);
  assert.deepEqual(furosemida.diasDaSemana, []);
});

test('dias nomeados sem contagem marcam a frequência semanal', () => {
  const receita = parseReceitaText(`
HIDROXOCOBALAMINA 1000MCG
Tomar aos sábados e domingos
  `);
  const [b12] = receita.medicamentos;
  assert.equal(b12.vezesPorSemana, null);
  assert.deepEqual(b12.diasDaSemana, [6, 7]);
});

test('posologia semanal na mesma linha do nome é dividida', () => {
  const receita = parseReceitaText(`
METOTREXATO 15MG 1X POR SEMANA
  `);
  const [metotrexato] = receita.medicamentos;
  assert.equal(metotrexato.nome, 'METOTREXATO');
  assert.equal(metotrexato.dosagem, '15MG');
  assert.equal(metotrexato.vezesPorSemana, 1);
});

test('nome conhecido sem dosagem abre medicamento com posologia semanal', () => {
  const receita = parseReceitaText(`
TRAMAL 1X POR SEMANA
  `);
  const [tramal] = receita.medicamentos;
  assert.equal(tramal.nome, 'TRAMAL');
  assert.equal(tramal.vezesPorSemana, 1);
});

test('duração em semanas não é frequência semanal', () => {
  const receita = parseReceitaText(`
CLONAZEPAM 0,5MG
Tomar 1 comprimido à noite por 2 semanas
  `);
  const [clonazepam] = receita.medicamentos;
  assert.equal(clonazepam.vezesPorSemana, null);
  assert.deepEqual(clonazepam.diasDaSemana, []);
  assert.equal(clonazepam.duracaoDias, 14);
});

test('posologia comum não marca frequência semanal', () => {
  const receita = parseReceitaText(RECEITA_CLASSICA);
  for (const med of receita.medicamentos) {
    assert.equal(med.vezesPorSemana, null, med.nome);
    assert.deepEqual(med.diasDaSemana, [], med.nome);
  }
});
