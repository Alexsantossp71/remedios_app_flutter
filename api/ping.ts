// Sonda de runtime. Não importa nada e não tem dependência nenhuma:
// se ESTA função responder 200 em produção, o launcher da Vercel funciona.
// Ela usa a assinatura (req, res) porque é assim que o launcher Node invoca a
// função e espera `res.end()` — devolver um `Response` deixaria a requisição
// pendurar até o timeout.
export const config = { runtime: 'nodejs' };

interface NodeResponseLike {
  status(code: number): NodeResponseLike;
  json(body: unknown): unknown;
}

export default function handler(_req: unknown, res: NodeResponseLike): void {
  res.status(200).json({ ok: true });
}