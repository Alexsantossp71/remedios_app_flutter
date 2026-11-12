// Gateway de arquivos do backup, por plataforma.
//
// Na web o arquivo é baixado/lido pelo próprio navegador (blob + input de
// arquivo); em mobile/desktop usa o seletor do sistema e o Documents do
// app. O default é a implementação web, seguindo o mesmo padrão do
// `database_service.dart`.
export 'backup_file_web.dart' if (dart.library.io) 'backup_file_io.dart';
