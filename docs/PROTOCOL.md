# Protocolo v1

Transporte: HTTP/1.1 sobre TCP com TLS, usando `dart:io HttpServer.bindSecure`. Esta escolha fornece framing, backpressure e limites de corpo sem criar um framing TCP proprietário. Não há endpoint HTTP sem TLS, WebSocket externo ou fallback sem criptografia.

Todas as operações são POST. JSON usa UTF-8. Credenciais: `Authorization: Bearer <token>` e `X-Omni-Id: <SHA-256 do certificado local>`. Nenhuma rota segue redirects. Erros retornam JSON `{ "error": "..." }` com HTTP 400/401/403/404/409/413/422/429/500.

| Rota | Corpo | Resultado |
| --- | --- | --- |
| `/v1/pair` | secret, id, name, fingerprint, port | id, name, token após confirmação |
| `/v1/info` | `{}` | nome, sistema, versão, IPs, bateria/espaço ou null |
| `/v1/offer` | id, name, size, hash | offset e complete após confirmação |
| `/v1/chunk` | bytes; headers x-transfer-id, x-offset | offset confirmado após flush |
| `/v1/complete` | id | ok apenas após SHA-256 integral |
| `/v1/cancel` | id | cancelamento persistido |
| `/v1/text` | text, máximo 64 KiB UTF-8 | ok após entrega ao receptor |

ID de transferência = SHA-256 de `senderId|receiverId|name|fileHash|size`. Isso torna reenvios idempotentes: um arquivo idêntico já recebido não é duplicado. A origem é revalidada antes de retomar. Se o arquivo final foi apagado/alterado no receptor, a operação falha explicitamente; renomeie o arquivo para iniciar outra entrega.

As requisições de blocos são sequenciais. Offset é obtido do tamanho real do parcial, inclusive após reinício. Um bloco só recebe confirmação após gravação e flush. A falta de resposta não implica perda dos bytes: uma nova oferta recupera o offset. A finalização renomeia o parcial após hash e grava histórico. Há uma janela residual de recuperação manual se o processo morrer entre rename e persistência SQLite; transação distribuída entre filesystem e banco não foi implementada.

Descoberta: `_omnilink._tcp`, atributos id/name/v. Nunca contém token ou segredo do convite. IP e porta anunciados são sugestões; a confiança continua exigindo certificado fixado. Heartbeat a cada oito segundos enquanto o processo roda. O envio interrompido requer “Retomar”; não há repetição automática de dados sem ação do usuário.
