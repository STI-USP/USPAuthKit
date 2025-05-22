# USPAuthKit

`USPAuthKit` é um package Swift (SPM) desenvolvido em Objective-C para facilitar a autenticação de utilizadores em aplicações iOS com os serviços da USP que utilizam o protocolo OAuth 1.0a.

## Visão Geral

Este package encapsula todo o fluxo de autenticação OAuth 1.0a, incluindo:

* Apresentação de uma interface web (WKWebView) para o utilizador inserir as suas credenciais da USP.
* Obtenção e gestão segura de tokens OAuth (request token e access token).
* Armazenamento persistente dos tokens de acesso e dados do utilizador em `NSUserDefaults`.
* Recuperação automática da sessão do utilizador a partir do cache, se disponível.
* Um método simplificado para garantir que o utilizador está logado antes de aceder a recursos protegidos.
* Busca de informações básicas do utilizador após a autenticação.
* Registo do token do utilizador num backend (opcional, conforme a implementação do `registerTokenWithCompletion:`).

## Funcionalidades

* **Fluxo OAuth 1.0a Completo:** Implementa os três passos do OAuth 1.0a.
* **Interface de Login Integrada:** Utiliza `WKWebView` para apresentar a página de login da USP de forma segura.
* **Gestão de Tokens:** Salva e recupera `oauth_token` e `oauth_token_secret`.
* **Cache de Sessão:** Verifica se o utilizador já está logado e recupera os dados da sessão.
* **Interface Simples:** Um único método principal para iniciar o fluxo de login e obter os dados do utilizador.
* **Construído para SPM:** Facilmente integrável em projetos iOS modernos.

## Requisitos

* iOS 13.0 ou superior (devido ao uso de `WKWebView` e práticas modernas de UI)
* Xcode 12.0 ou superior
* Conhecimento básico de Objective-C para integração (embora possa ser usado a partir de Swift também).

## Instalação

### Swift Package Manager (SPM)

Pode adicionar o `USPAuthKit` ao seu projeto Xcode seguindo estes passos:

1.  No Xcode, abra o seu projeto.
2.  Vá a `File` > `Add Packages...`
3.  Na barra de pesquisa no canto superior direito, cole a URL do repositório Git deste package.
4.  Clique em `Add Package`.
5.  Escolha o target do seu projeto onde deseja usar o package e clique em `Add Package` novamente.


## Estrutura do Package (Principais Componentes)
### USPAuthService: 
Singleton que serve como a fachada principal para a aplicação cliente. Orquestra o fluxo de login e a gestão de dados.

### LoginWebViewController: 
UIViewController que apresenta a WKWebView para o processo de login do utilizador.

### OAuth1Controller: 
Classe responsável por toda a lógica do protocolo OAuth 1.0a (obtenção de tokens, assinatura de requisições, etc.) e pela interação com a WKWebView.

### Dependências C: 
Inclui hmac.h e Base64Transcoder.h para operações criptográficas.

## Contribuições
Contribuições são bem-vindas! Se encontrar bugs ou tiver sugestões de melhoria, por favor, abra uma issue ou submeta um pull request.
