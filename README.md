# ArTray

App de bandeja do Windows para controlar o ar-condicionado Electrolux sem abrir o celular. É um único script PowerShell com flyout em WPF, no estilo dos flyouts do Windows 11 (Mica/DWM).

Usa a **API oficial do Electrolux Group** ([developer.electrolux.one](https://developer.electrolux.one)).

## Recursos

- Clique esquerdo no ícone abre o flyout: liga/desliga, temperatura, modo e ventilação.
- Clique direito: Sair.
- Instância única: abrir de novo substitui a que está rodando.
- Erros fatais (token inválido, config faltando) aparecem numa MessageBox, em vez de o app morrer em silêncio.

## Detalhes da API que deram trabalho

- O refresh token **rotaciona** a cada uso. O novo é salvo no `config.json` na hora, senão o próximo start falha.
- A API rejeita refreshes feitos logo depois de outro (`cas_3404`). Por isso o access token também fica em cache com a validade, e reiniciar o app reaproveita o token.

## Setup

1. Crie uma API key e um refresh token no portal de desenvolvedor da Electrolux.
2. `copy config.example.json config.json` e preencha `apiKey` e `refreshToken`. O `applianceId` é descoberto sozinho.
3. Rode o app:

```powershell
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File ArTray.ps1 -Show
```

O `config.json` guarda tokens e está no `.gitignore`.

Projeto pessoal, sem afiliação com a Electrolux.
