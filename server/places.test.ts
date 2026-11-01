import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  buildNominatimUrl,
  mapNominatimResults,
} from './places.ts';

test('URL do Nominatim carrega busca BR com detalhes de endereço', () => {
  const url = new URL(buildNominatimUrl('Rua Ada Pereira, Campinas'));
  assert.equal(url.origin, 'https://nominatim.openstreetmap.org');
  assert.equal(url.pathname, '/search');
  assert.equal(url.searchParams.get('q'), 'Rua Ada Pereira, Campinas');
  assert.equal(url.searchParams.get('format'), 'jsonv2');
  assert.equal(url.searchParams.get('addressdetails'), '1');
  assert.equal(url.searchParams.get('countrycodes'), 'br');
  assert.equal(url.searchParams.get('limit'), '6');
  assert.equal(url.searchParams.get('accept-language'), 'pt-BR');
});

const NOMINATIM_FIXTURE = [
  {
    display_name:
      'Rua Ada Pereira, 150, Cambuí, Campinas, Região Metropolitana de Campinas, São Paulo, 13024-010, Brasil',
    address: {
      road: 'Rua Ada Pereira',
      house_number: '150',
      suburb: 'Cambuí',
      city: 'Campinas',
      state: 'São Paulo',
      postcode: '13024-010',
    },
  },
  {
    display_name: 'Rua Ada Pereira, Santo Amaro, Recife, Pernambuco, Brasil',
    address: {
      road: 'Rua Ada Pereira',
      neighbourhood: 'Santo Amaro',
      city: 'Recife',
      state: 'Pernambuco',
    },
  },
  {
    // Sem display_name não é sugestão utilizável.
    address: { road: 'Rua Fantasma' },
  },
];

test('mapeia resposta do Nominatim em sugestões estruturadas', () => {
  const results = mapNominatimResults(NOMINATIM_FIXTURE);
  assert.equal(results.length, 2);

  const [campinas, recife] = results;
  assert.equal(campinas.street, 'Rua Ada Pereira');
  assert.equal(campinas.number, '150');
  assert.equal(campinas.neighborhood, 'Cambuí');
  assert.equal(campinas.city, 'Campinas');
  assert.equal(campinas.uf, 'SP');
  assert.equal(campinas.postalCode, '13024-010');
  assert.ok(campinas.label.startsWith('Rua Ada Pereira, 150'));

  assert.equal(recife.city, 'Recife');
  assert.equal(recife.uf, 'PE');
  assert.equal(recife.number, '');
  assert.equal(recife.postalCode, '');
});

test('respostas inesperadas viram lista vazia, não erro', () => {
  assert.deepEqual(mapNominatimResults(null), []);
  assert.deepEqual(mapNominatimResults({}), []);
  assert.deepEqual(mapNominatimResults(['texto solto']), []);
});

test('estado fora da tabela deixa a UF vazia em vez de inventar sigla', () => {
  const results = mapNominatimResults([
    {
      display_name: 'Algum Lugar, Guarulhos, São Paulo, Brasil',
      address: { city: 'Guarulhos', state: 'Sao Paulo' },
    },
  ]);
  assert.equal(results[0].uf, 'SP');
});
