# Changelog

## 0.1.0 Alpha — 2026-10-30

- Aplicação Flutter para Windows e Android, Material 3, vidro, temas claro/escuro/sistema e português brasileiro.
- Descoberta mDNS, convite QR/manual de uso único, confirmação no receptor e certificados fixados por dispositivo.
- Transferência HTTPS/TLS em blocos, validação SHA-256, progresso, MB/s, estimativa, cancelamento e retomada.
- Seleção múltipla, arrastar e soltar no Windows, exportação SAF e compartilhamento no Android.
- Textos autenticados, cópia manual, sincronização opcional de saída no Windows e histórico opcional.
- SQLite para histórico/ajustes; credenciais e chave TLS no armazenamento seguro do sistema.
- Estado de conexão por heartbeat, reconexão e remoção de confiança.
- Testes locais de protocolo, persistência e componente visual; workflows de análise/testes/build.

Binários de teste foram compilados posteriormente; veja a seção de builds abaixo. Validação integrada em aparelhos físicos continua pendente.

### Builds de teste verificados em 31/10/2026
- Windows release x64 e APK Android debug compilados com sucesso.
- Incluído desktop_drop com registro Android desativado; drag-and-drop restrito ao Windows.
- Assinatura v2 do APK validada; Android mínimo 7/API 24.



## 0.1.0+2 — salvamento público
- Botões de salvar na galeria e em Downloads após receber arquivos.
- MediaStore no Android 10+ e permissão de gravação somente no Android 7–9.
- Cópia para Downloads/OmniLink no Windows sem sobrescrever arquivos existentes.
- Testes da cópia para Downloads e seleção de tipos de mídia.
