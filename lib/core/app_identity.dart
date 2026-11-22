/// Identidade do app para chamadas serverless.
///
/// O [appToken] NÃO é um segredo — é um identificador público que o app
/// oficial envia em todas as chamadas às funções serverless (`api/*`).
/// As funções rejeitam chamadas sem o header (ou com valor diferente),
/// filtrando crawlers casuais e abuso determinado que não se dá ao
/// trabalho de descobrir o valor.
///
/// Não substitui autenticação real nem rate limiting. É camada adicional
/// de defesa: bloqueia quem nem sabe qual app está chamando.
const String appToken = 'remedios-na-hora-app-v1';

/// Nome do header HTTP que carrega o [appToken].
const String appTokenHeader = 'X-App-Token';
