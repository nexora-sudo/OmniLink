# Contribuindo

Use Flutter 3.47.9 stable e o `pubspec.lock` versionado. Leia README.md e docs/SECURITY.md antes de alterar o protocolo.

1. Crie uma branch com uma alteração coesa.
2. Preserve camadas: `models`, `communication`, `persistence`, `services`, `ui`.
3. Execute `dart format lib test`, `flutter analyze` e `flutter test`.
4. Para mudanças de protocolo, inclua testes negativos e de recuperação com sockets reais.
5. Execute a matriz de docs/TESTING.md em dois aparelhos antes de declarar compatibilidade nativa.

Não registre convites, tokens, chaves privadas, textos compartilhados nem caminhos pessoais em issues. Use uma descrição do erro e versões dos sistemas. Não substitua falhas por dados demonstrativos. Falhas do sistema devem ser visíveis ou explicitamente apresentadas como informações indisponíveis.

Contribuições são licenciadas sob MIT. Antes de publicar releases, configure assinatura Android e Windows e revise as licenças das dependências.
