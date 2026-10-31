# Validação dos builds — conferência em 31/10/2026

- Flutter 3.47.9 stable / Dart 3.13.7 em Windows 11 x64.
- Visual Studio Build Tools 2022, MSVC, ATL e Windows SDK instalados.
- Modo de Desenvolvedor habilitado com autorização do usuário.
- Android SDK (plataformas 33/35/36), build-tools 36.0.0, NDK 28.2.13676358, CMake 3.22.1 e Java Temurin instalados.
- `flutter analyze --no-pub`: sem problemas.
- `flutter test --no-pub --reporter expanded`: 23 testes aprovados, incluindo cópia para Downloads sem sobrescrita e identificação de mídia.
- `flutter build windows --release --no-pub`: concluído; EXE e DLLs presentes.
- `flutter build apk --debug --no-pub`: concluído; APK de 188612474 bytes presente.
- `apksigner verify --verbose`: aprovado, assinatura v2, um signatário.
- `aapt dump badging`: org.omnilink.omnilink 0.1.0 (2), minSdk 24, targetSdk 36, atividade MainActivity, ABIs arm64-v8a/armeabi-v7a/x86_64.

Correção reproduzível: desktop_drop 0.6.1 incluído em packages/desktop_drop, com registro Android removido por incompatibilidade do módulo legado com AGP 9. O recurso de arrastar é habilitado apenas no Windows; o Android usa o seletor do sistema. Código Dart e Windows original do plugin preservado, junto com a licença.

Logs: validation/analyze.txt, validation/tests.txt, validation/build-windows.txt, validation/build-android.txt e validation/apk-signature.txt.

Ainda pendente: teste integrado de pareamento e transferência entre Windows e Android físicos, câmera, mDNS da rede, salvamento na galeria/Downloads (MediaStore e Android 7–9), exportação SAF, clipboard entre aparelhos, autorun, desempenho e FPS. Os testes automatizados incluem sockets TLS e arquivos reais de loopback, SQLite e componente visual; não substituem esses testes físicos. Não foi gerado instalador nem assinatura pública de distribuição Windows. O APK é um build debug para testes.

