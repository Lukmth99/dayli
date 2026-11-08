# Servidor gratuito da Dayli AI

`worker.js` implementa [docs/AI_BACKEND_CONTRACT.md](../docs/AI_BACKEND_CONTRACT.md) usando **Cloudflare Workers** (grátis, 100 mil requisições/dia) e **Google Gemini** (`gemini-2.5-flash`, camada gratuita com limite diário).

## Implantação (sem instalar nada)
1. Crie a chave do Gemini em https://aistudio.google.com/apikey.
2. Em https://dash.cloudflare.com: **Workers & Pages → Create → Start with Hello World → Deploy**.
3. **Edit code**, apague o conteúdo, cole o `worker.js` inteiro e clique em **Deploy**.
4. **Settings → Variables and Secrets → Add**:
   - `GEMINI_API_KEY` (Secret) = chave do passo 1
   - `DAYLI_ACCESS_CODE` (Secret) = um código longo inventado por você
5. Abra o endereço `https://<nome>.<conta>.workers.dev` no navegador: deve mostrar `"configured":true`.
6. No app: **Perfil → Inteligência artificial** → cole o endereço, salve, salve o mesmo código de acesso e ative o consentimento.

## Privacidade — leia
- Na **camada gratuita**, o Google pode usar o conteúdo enviado para melhorar seus produtos, inclusive com revisão humana. Por isso o app, por padrão, **não envia títulos** das tarefas e remove e-mail, CPF, CNPJ, cartão, conta e telefone antes do envio.
- Para retenção mínima e sem uso para treino, use a camada paga do provedor.
- O Worker não registra conteúdo das requisições; o `DAYLI_ACCESS_CODE` impede que terceiros consumam a cota.

## Comportamento
- A saída do Gemini é forçada a JSON (`responseSchema`), saneada (tipos fora do contrato, `taskID` desconhecido e campos inválidos são descartados) e convertida de horário local para UTC ISO 8601 sem frações de segundo. O app valida tudo novamente e nada é executado sem confirmação.
- Erros do provedor viram `502` (ou `429` quando a cota diária acaba); o app mostra indisponibilidade temporária e o assistente local continua funcionando.
