# OmniLink 0.1.0 Alpha

Aplicativo open-source em Flutter para compartilhar arquivos e textos entre Windows e Android pela rede local. Interface Material 3 com transparência, desfoque, temas claro/escuro/automático e português brasileiro.

**Estado da entrega:** APK debug Android e executável release Windows gerados e verificados. A assinatura do APK foi validada. A integração entre aparelhos físicos e o desempenho visual ainda precisam de validação. Consulte [VALIDATION.md](VALIDATION.md) para resultados e limites exatos.

## Recursos

- Descoberta mDNS (`_omnilink._tcp`), conexão por convite, QR Code com câmera no Android e entrada manual de IPv4/porta/certificado/código.
- Convites de cinco minutos e uso único, confirmação no receptor, TLS com certificado fixado, credenciais no armazenamento seguro e revogação de pares.
- Heartbeat com estados conectado/conectando/desconectado e reconexão de pares conhecidos. Atualização de IP por mDNS.
- Transferências de arquivos reais em blocos, seleção múltipla, drag-and-drop no Windows, progresso, MB/s, ETA estimada, cancelamento e retomada após interrupção/reinício.
- SHA-256 integral antes de considerar um recebimento concluído. Nomes validados, limite de 4 GiB por arquivo e confirmação em todo recebimento.
- Textos bidirecionais com cópia manual, histórico opcional e envio automático da área de transferência no Windows, desativado por padrão.
- Nome/sistema/versão/IP e última conexão reais; bateria e espaço livre são exibidos somente quando o sistema informa.
- Histórico de transferências e configurações em SQLite; opção de iniciar com Windows.
- Pasta de destino no Windows. Android recebe na área privada e oferece “Salvar em…” via seletor SAF, além do compartilhamento com outros aplicativos.

Não há conta, nuvem, analytics nem transporte externo. As dependências de desenvolvimento precisam de internet durante instalação/build; o uso entre aparelhos não precisa.

## Ambiente de desenvolvimento

Versão usada nesta entrega: **Flutter 3.47.9 stable / Dart 3.13.7**. Mantenha `pubspec.lock`. O resolvedor selecionou versões estáveis compatíveis; versões major mais novas não foram adotadas automaticamente.

### Windows

1. Instale Flutter e adicione `flutter/bin` ao PATH.
2. Instale Visual Studio com **Desktop development with C++**, MSVC, CMake, Windows SDK e a biblioteca ATL (exigida pelo armazenamento seguro).
3. Habilite Modo de Desenvolvedor do Windows para os links simbólicos usados pelos plugins.
4. Execute `flutter doctor -v` e corrija os requisitos de Windows.

### Android

1. Instale Android Studio, JDK 17 e Android SDK com command-line tools.
2. Instale a plataforma SDK 36 e as versões de build-tools/NDK solicitadas pelo Flutter/Gradle.
3. Execute `flutter doctor --android-licenses` e revise as licenças.
4. Ative depuração USB no celular, autorize o computador e confira `flutter devices`.

O projeto usa target SDK 36. Antes de elevar para API 37, implemente a permissão de rede local do Android 17. Não solicita acesso amplo ao armazenamento, localização ou execução em segundo plano. Câmera é necessária somente para ler QR.

## Rodar

Abra um terminal **na pasta que contém `pubspec.yaml`**:

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Em outro terminal, para o Android conectado:

```sh
flutter devices
flutter run -d ID_DO_ANDROID
```

Nesta máquina, o SDK preparado está em `../../work/flutter/bin`, relativo à pasta do projeto. Exemplo PowerShell para executar os testes sem alterar o PATH:

```powershell
$env:PUB_CACHE = (Resolve-Path ../../work/pub-cache).Path
& ../../work/flutter/bin/flutter.bat test --no-pub
```

Esse caminho é específico desta entrega; não faz parte do ZIP distribuível.

## Primeiro pareamento

1. Conecte os dois aparelhos à mesma rede e mantenha o OmniLink aberto.
2. No Windows, permita o aplicativo no Firewall apenas para redes privadas. A porta TCP padrão é 45832; mDNS usa UDP 5353. Nenhuma regra é alterada automaticamente.
3. Em um aparelho, clique **Criar convite**. Se houver várias interfaces, selecione o IPv4 da mesma rede do outro aparelho.
4. No Android, use **Ler QR Code**; ou no outro aparelho use **Conectar / IP manual** para colar o convite. A seção “Dados para conexão manual” apresenta IPv4, porta, SHA-256 e código secreto.
5. Confirme o nome/endereço no aparelho que criou o convite. Fechar a janela revoga o convite.
6. Selecione o dispositivo pareado. Em **Arquivos**, escolha arquivos ou arraste-os; confirme a recepção no destino.

A impressão digital/código devem vir diretamente do convite do outro aparelho. O anúncio mDNS não autentica nada. Evite enviar convites por canais públicos. A permissão de firewall pode ser necessária nos dois sentidos para comunicação bidirecional.

## Arquivos e retomada

Cada arquivo é recebido inicialmente como `.ID.omnipart`. Somente após validar SHA-256 é movido para `OmniLink-ID/nome-original` dentro da pasta escolhida. Não há sobrescrita de arquivos existentes.

Se a rede cair, o histórico mostra o erro e **Retomar** no remetente. O receptor reconfirma e informa quantos bytes persistiu. Depois de reiniciar, a origem deve continuar acessível no mesmo caminho; caso o cache do seletor Android tenha sido limpo, selecione o arquivo original novamente. Arquivos idênticos para o mesmo par são idempotentes, sem cópias duplicadas.

**Cancelar** interrompe o envio e preserva o parcial. **Excluir parcial** no receptor remove os bytes. O histórico é preservado. Uma desconexão pode impedir a confirmação remota do cancelamento; a UI informa essa situação.

No Android, a pasta privada evita permissões amplas e URLs SAF inválidas para `dart:io`. **Salvar em…** permite escolher onde exportar o arquivo concluído, sem carregar tudo na RAM. Esta Alpha não configura uma árvore SAF como destino automático permanente. Desinstalar o app remove seus arquivos privados; exporte os que deseja manter.

## Área de transferência

Textos recebidos não sobrescrevem o clipboard automaticamente. Use **Copiar**. No Android, use **Colar** com o aplicativo em primeiro plano, respeitando as restrições do sistema. No Windows, o envio automático é opcional e funciona enquanto o processo está aberto e um destino está selecionado. Qualquer texto copiado, inclusive senhas, pode ser enviado quando essa opção está ligada.

O histórico de textos fica desligado por padrão. Quando habilitado, guarda até 100 registros no SQLite local, sem criptografia adicional. É possível apagá-lo nos ajustes.

## Builds

```sh
# Windows (precisa de Visual Studio / C++ / Windows SDK)
flutter build windows --release

# APK instalável para testes Alpha, assinado com chave de desenvolvimento
flutter build apk --debug
```

Arquivos esperados, **somente após build bem-sucedido**:

- `build/windows/x64/runner/Release/omnilink.exe`: distribua toda a pasta Release, incluindo DLLs e data; não apenas o EXE.
- `build/app/outputs/flutter-apk/app-debug.apk`: instale com `adb install -r CAMINHO_DO_APK` ou pelo instalador Android.

Para automatizar validação e conferir existência/hash do artefato: `./scripts/build.ps1 -Target windows` ou `-Target android`.

O arquivo `packaging/windows/omnilink.iss` permite gerar um instalador com Inno Setup 6 após o build Windows. Não foi executado nesta máquina. A configuração release Android não usa silenciosamente uma chave debug: configure uma keystore e signingConfig antes de distribuir release. Builds e instaladores públicos também devem ser assinados e testados.

## GitHub

A pasta está preparada para publicação, mas nenhum repositório remoto foi criado nem conteúdo publicado. Inclui licença MIT, changelog, guia de contribuição, ignore, protocolo, segurança, plano de validação e dois workflows:

- `ci.yml`: formatação, análise e testes no Windows, em push/PR.
- `build.yml`: acionamento manual para APK debug e pasta release Windows, publicados apenas como artifacts da execução.

Os workflows estão preparados, **não executados no GitHub nesta entrega**. Use a raiz desta pasta como raiz do repositório. Confira o conteúdo antes do primeiro push; não inclua builds, bancos, credenciais nem caches.

## Arquitetura

```text
lib/
  communication/  identidade TLS, pareamento, autenticação, transporte e transferências
  models/         pares, convites, transferências e validação
  persistence/    contrato de repositório, SQLite e armazenamento seguro
  services/       descoberta mDNS e recursos nativos
  ui/             telas e tema de vidro
android/          host Kotlin, armazenamento e exportação SAF
windows/          host C++, espaço livre e integração com plugins
```

O transporte é HTTPS local, ou seja, HTTP enquadrado sobre TCP/TLS, sem servidor intermediário. Veja [protocolo](docs/PROTOCOL.md), [segurança](docs/SECURITY.md) e [plano de testes](docs/TESTING.md).

## Limitações conhecidas

- Os builds nativos foram concluídos. Câmera, mDNS entre aparelhos, secure storage em hardware, share sheet e autorun ainda precisam de testes integrados em aparelhos físicos.
- Uso em primeiro plano no Android. Não há serviço permanente ou garantia de transferência com tela suspensa.
- IPv4 privado/link-local; redes somente IPv6 e CGNAT 100.64/10 não são aceitas nesta versão.
- Sem rotação automática de identidade e sem auditoria independente de segurança.
- Sem métricas reais de FPS coletadas; 60 FPS depende de hardware e precisa de perfil.
- Arquivos grandes usam hash em fluxo e envio em blocos, mas throughput e uso de memória em celulares intermediários ainda não foram medidos.
- Casos extremos de queda do processo entre finalização do arquivo e persistência podem exigir recuperação manual (docs/PROTOCOL.md).
- Sem capturas de tela de execução nativa disponíveis. Nenhuma imagem simulada é apresentada como screenshot do aplicativo.

## Referências técnicas

- [Flutter: instalação](https://docs.flutter.dev/install)
- [Bonsoir: mDNS e endereços resolvidos](https://pub.dev/packages/bonsoir)
- [SQLite para Dart: native assets](https://pub.dev/packages/sqlite3)
- [Armazenamento seguro](https://pub.dev/packages/flutter_secure_storage)
- [Android: permissões de rede local](https://developer.android.com/privacy-and-security/local-network-permission)

## Licença

MIT — veja [LICENSE](LICENSE). Dependências mantêm suas próprias licenças, acessíveis em Configurações → Licenças de código aberto.

## Binários para teste (verificados em 31/10/2026)

O APK debug usa assinatura de desenvolvimento, minSdk 24 e targetSdk 36, com ARM64, ARM de 32 bits e x86_64. O pacote Windows é x64 e deve ser extraído integralmente antes de abrir omnilink.exe. Não há instalador Windows gerado.

O plugin desktop_drop 0.6.1 foi incluído em packages/desktop_drop com licença original e registro nativo Android removido. Arrastar arquivos é utilizado apenas no Windows; Android utiliza o seletor do sistema. Veja packages/desktop_drop/OMNILINK_PATCH.md.


## Build 2 — salvar arquivos recebidos

Depois de uma transferência concluída, a página Arquivos oferece:
- Android: **Salvar na galeria** para fotos/vídeos (álbum OmniLink) e **Salvar em Downloads** para qualquer arquivo.
- Windows: **Salvar em Downloads**, dentro de Downloads/OmniLink. Essa pasta continua sendo o destino padrão; se o arquivo já está ali, a ação confirma o local sem criar outra cópia.
- Android: **Salvar em…** permanece disponível para escolher manualmente outra pasta.

O salvamento é manual e preserva a cópia recebida. Android 10+ usa MediaStore; Android 7–9 solicita WRITE_EXTERNAL_STORAGE somente ao salvar, limitada a essas versões no manifesto. Falhas são exibidas e cópias parciais da exportação são removidas. No Android moderno, fotos vão para Pictures/OmniLink, vídeos para Movies/OmniLink e outros arquivos para Download/OmniLink. A galeria do aparelho pode levar alguns instantes para atualizar o álbum.

O aplicativo não depende de permissões para ler a galeria: ele apenas publica arquivos que recebeu. A apresentação de um formato específico depende dos aplicativos instalados no aparelho.
