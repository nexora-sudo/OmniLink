# Validação

Consulte VALIDATION.md na raiz para os resultados efetivamente executados nesta entrega. A fixture `MemoryRepository` existe somente em `test/support`; nenhum dado demonstrativo é utilizado na aplicação.

## Automatizado

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded
```

Os testes de protocolo criam dois servidores TLS reais em portas efêmeras de loopback, identidades independentes, arquivos temporários e bytes determinísticos de teste. Cobrem pareamento/recusa/expiração, token e certificado errados, revogação, arquivos multibloco/vazios, SHA-256 divergente, retomada após reinício, cancelamento, desconexão/reconexão, caminhos/tamanho/offset inválidos e texto. A persistência é exercitada contra SQLite real. Os testes de vidro verificam o componente em tema claro/escuro e tela estreita; não substituem QA visual do aplicativo completo.

## Matriz manual pendente — aparelhos físicos

- Windows 10 1903+ / Windows 11 x64 e Android 7+ compatível com o mínimo do Flutter usado.
- Mesma rede: descoberta dos dois lados; modo avião com Wi-Fi reativado; sem internet.
- Parear por QR Android → Windows, convite colado e IP/credenciais manuais.
- Recusar um pareamento e um recebimento; remover par e verificar falha de autenticação.
- Transferir ambos os sentidos: 0 B, 1 KiB, 10 MiB, 1 GiB; comparar `Get-FileHash -Algorithm SHA256` com o original.
- Seleção múltipla, nomes com acentos, arrastar arquivo no Windows, exportação SAF e share sheet Android.
- Cancelar no remetente/receptor, retirar Wi-Fi no meio, reativar e retomar; fechar/reabrir receptor.
- Verificar disco cheio, origem alterada/removida e destino sem permissão. Não deve aparecer “concluído”.
- Trocar IP por DHCP; confirmar que mDNS atualiza endpoint mas certificado diferente é rejeitado.
- Textos de ambos os lados, limite de tamanho, histórico desativado/ativado/apagado, cópia manual.
- Temas, janela estreita, Android voltar, câmera negada, fonte grande e leitor de tela.
- Suspender Android: observar interrupção e retomar em primeiro plano; nenhuma promessa de execução permanente.
- Perfil de frame com `flutter run --profile`: testar 60 FPS em hardware disponível; ainda não medido.
- Autorun Windows: habilitar/desabilitar pela UI e conferir a entrada HKCU/Run.

Nenhum desses cenários manuais deve ser marcado aprovado sem execução.

