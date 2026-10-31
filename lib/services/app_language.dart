String tr(String portuguese, String english) =>
    AppLanguage.code == 'pt' ? portuguese : english;

String statusLabel(String value) =>
    AppLanguage.code == 'pt' ? value : (AppLanguage.statuses[value] ?? value);

class AppLanguage {
  static String code = 'en';
  static void load(String? saved) => code = saved == 'pt' ? 'pt' : 'en';

  static const statuses = {
    'conectado': 'connected',
    'conectando': 'connecting',
    'desconectado': 'disconnected',
    'aguardando': 'waiting',
    'transferindo': 'transferring',
    'verificando': 'verifying',
    'concluído': 'completed',
    'cancelado': 'cancelled',
    'interrompido': 'interrupted',
    'falhou': 'failed',
  };

  // Translate application-owned diagnostic sentences only at presentation.
  // Protocol values, stored history, device names and received text stay intact.
  static String message(String source) {
    if (code == 'pt') return source;
    var result = source;
    for (final entry in diagnostics.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    result = result.replaceAll(
      ' deseja se conectar.\nConfirme somente se iniciou este pareamento.',
      ' wants to connect.\nOnly confirm if you initiated this pairing.',
    );
    result = result.replaceAll(' quer enviar ', ' wants to send ');
    return result;
  }

  static const diagnostics = <String, String>{
    'Somente endereços de rede local são permitidos.':
        'Only local network addresses are allowed.',
    'Falha remota.': 'Remote request failed.',
    'Arquivo de origem foi alterado. Selecione-o novamente.':
        'Source file changed. Select it again.',
    'Parear dispositivo?': 'Pair device?',
    'Receber arquivo?': 'Receive file?',
    'Nome de arquivo inválido.': 'Invalid filename.',
    'Identificador inválido.': 'Invalid identifier.',
    'Informe um IPv4 local e uma porta válida.':
        'Enter a local IPv4 address and a valid port.',
    'Convite OmniLink inválido.': 'Invalid OmniLink invitation.',
    'Versão de protocolo incompatível.': 'Incompatible protocol version.',
    'Convite inválido.': 'Invalid invitation.',
    'Certificado remoto divergente.': 'Remote certificate mismatch.',
    'Resposta de pareamento inválida.': 'Invalid pairing response.',
    'Método inválido.': 'Invalid method.',
    'Dispositivo não autorizado.': 'Unauthorized device.',
    'Compartilhamento de textos desativado.': 'Text sharing disabled.',
    'Aguarde antes de enviar outro texto.': 'Wait before sending another text.',
    'Texto muito grande.': 'Text is too large.',
    'Rota inexistente.': 'Route not found.',
    'Limite de solicitações.': 'Request limit reached.',
    'Muitas tentativas. Aguarde um minuto.':
        'Too many attempts. Wait one minute.',
    'Gere um novo convite no receptor.':
        'Create a new invitation on the receiver.',
    'Identidade inválida.': 'Invalid identity.',
    'Pareamento recusado.': 'Pairing declined.',
    'Transferência não encontrada.': 'Transfer not found.',
    'Outra confirmação está em andamento.':
        'Another confirmation is in progress.',
    'Limite de 4 GiB por arquivo.': '4 GiB limit per file.',
    'Metadados divergentes.': 'Metadata mismatch.',
    'Transferência ocupada.': 'Transfer is busy.',
    'Arquivo final ausente ou alterado. Inicie um novo envio.':
        'Completed file is missing or changed. Start a new transfer.',
    'Limite de transferências pendentes.': 'Pending transfer limit reached.',
    'Arquivo recusado.': 'File declined.',
    'Dispositivo removido.': 'Device removed.',
    'Destino inválido.': 'Invalid destination.',
    'Transferência inativa.': 'Inactive transfer.',
    'Offset divergente. Retome o envio.':
        'Offset mismatch. Resume the transfer.',
    'Bloco inválido.': 'Invalid chunk.',
    'Envio cancelado.': 'Sending cancelled.',
    'Arquivo parcial alterado.': 'Partial file changed.',
    'Transferência incompleta.': 'Incomplete transfer.',
    'SHA-256 divergente. O arquivo não foi aceito.':
        'SHA-256 mismatch. The file was not accepted.',
    'Transferência cancelada.': 'Transfer cancelled.',
    'Destino já existe.': 'Destination already exists.',
    'Este arquivo já está sendo enviado.': 'This file is already being sent.',
    'Retome pelo dispositivo remetente.': 'Resume from the sending device.',
    'Dispositivo não pareado.': 'Device not paired.',
    'Cancelado.': 'Cancelled.',
    'Arquivo de origem truncado.': 'Source file truncated.',
    'Confirmação de bloco inválida.': 'Invalid chunk acknowledgement.',
    'Arquivo não é um parcial inativo.':
        'File is not an inactive partial transfer.',
    'Limite de 64 KiB por texto.': '64 KiB limit per text.',
    'Solicitação muito grande.': 'Request is too large.',
    'JSON inválido.': 'Invalid JSON.',
    'Não foi possível persistir dispositivos:': 'Could not save devices:',
    'Falha ao atender solicitação:': 'Could not handle request:',
    'Cancelado localmente; receptor inacessível:':
        'Cancelled locally; receiver unreachable:',
    'Pasta Downloads indisponível.': 'Downloads folder unavailable.',
    'Arquivo recebido não encontrado.': 'Received file not found.',
    'Arquivo não encontrado.': 'File not found.',
    'Aguarde o salvamento atual.': 'Wait for the current save operation.',
    'Permissão negada. Você ainda pode usar Salvar em…':
        'Permission denied. You can still use Save as…',
    'Este formato não pode ser salvo na galeria. Use Downloads ou Salvar em…':
        'This format cannot be saved to the gallery. Use Downloads or Save as…',
    'Não foi possível criar o destino.': 'Could not create the destination.',
    'Não foi possível publicar o arquivo.': 'Could not publish the file.',
    'Não foi possível criar a pasta.': 'Could not create the folder.',
    'Uma exportação já está aberta.': 'An export is already open.',
    'Não foi possível abrir o destino.': 'Could not open the destination.',
    'Não foi possível alterar a inicialização:':
        'Could not change startup settings:',
  };
}
