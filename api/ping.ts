// Sonda de runtime. Não importa nada e não tem dependência nenhuma:
// se ESTA função responder 200 em produção, o launcher da Vercel funciona
// e o 500 do read-card está no código/bundle dele. Se ela também der 500,
// o problema é do runtime ou da configuração, não do OCR.
export const config = { runtime: 'nodejs' };

export default function handler(): Response {
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
}