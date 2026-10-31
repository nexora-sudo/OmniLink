# Segurança do OmniLink Alpha

## Modelo

O aplicativo abre um servidor HTTPS IPv4 na porta TCP 45832, em todas as interfaces IPv4. Os clientes aceitam apenas endereços locais RFC 1918, loopback e link-local. O protocolo não usa serviços externos. mDNS publica nome, ID e porta na LAN; isso permite que pessoas na rede vejam esses metadados.

Cada instalação gera uma chave RSA 2048 e certificado autoassinado. A chave e o certificado são persistidos em `flutter_secure_storage`, assim como os tokens e a lista de pares. Windows usa o backend protegido do sistema; Android usa o backend criptográfico do plugin. A validação em hardware desses backends ainda está pendente.

O convite contém IPv4, porta, SHA-256 do certificado e 256 bits aleatórios. Expira em cinco minutos; é consumido uma única vez, inclusive em recusa. O receptor confirma visualmente a solicitação em até 55 segundos. Há limitação de tentativas por endereço. Não compartilhe a imagem do QR em lugares públicos.

O cliente usa um contexto TLS sem autoridades pré-carregadas. A exceção de certificado só é aceita quando o DER tem o hash fixado no convite/pareamento; o certificado da resposta é verificado novamente. O servidor autentica cada requisição por ID + token aleatório de 256 bits, exclusivo daquele par. Não é mTLS: a autenticação do cliente ocorre dentro do canal TLS por credencial bearer. Remover o par revoga a credencial local imediatamente. Para remoção completa nos dois lados, remova em ambos.

## Arquivos

- Todos os arquivos exigem confirmação do receptor, inclusive dos pares conhecidos.
- Antes do pareamento, endpoints de dados respondem 401.
- Máximo de 4 GiB por arquivo e 16 recebimentos pendentes; blocos de 256 KiB.
- Nomes são validados, incluindo separadores, traversal, controles e nomes reservados do Windows.
- Parciais usam IDs hexadecimais, sem caminhos fornecidos pela rede.
- O SHA-256 é calculado em fluxo e comparado antes da publicação.
- Cada entrega concluída usa uma pasta exclusiva, evitando sobrescrever arquivos do usuário.
- Retomada verifica tamanho/offset e depois SHA-256 integral. Conteúdo corrompido não é publicado.
- Cancelar mantém o parcial para retomada; “Excluir parcial” remove os bytes.
- Não abra arquivos executáveis recebidos de fontes em que você não confia.

## Limites desta Alpha

Não houve auditoria independente, fuzzing, teste de carga ou pentest. Os limites não equivalem a proteção completa contra negação de serviço. Não exponha a porta na internet. Uma máquina comprometida, malware com acesso à sessão do usuário e um par autorizado malicioso estão fora da proteção do transporte. Arquivos e histórico SQLite não têm criptografia própria em repouso; dependem da proteção do sistema/disco. Histórico de textos é opt-in e limitado a 100 entradas.

Certificados têm validade emitida de dez anos; a confiança é baseada no pin. Rotação automática de certificados não foi implementada. Alteração/perda da identidade exige novo pareamento. Não há serviço Android em segundo plano nem wake lock. Fechar ou suspender o app pode interromper envios.

Antes de reportar uma vulnerabilidade, reproduza em ambiente local e omita credenciais. O projeto entregue não possui endereço público de contato nem repositório publicado; o mantenedor deverá estabelecer um canal privado antes da publicação.
