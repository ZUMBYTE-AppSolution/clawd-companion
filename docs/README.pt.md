<p align="center"><img src="media/app-icon.png" width="104" height="104" alt="Claw’d Companion"></p>

# Claw’d Companion

[Deutsch](../README.md) · [English](README.en.md) · [简体中文](README.zh-Hans.md) · [हिन्दी](README.hi.md) · [Español](README.es.md) · [العربية](README.ar.md) · [Français](README.fr.md) · [বাংলা](README.bn.md) · **Português** · [Bahasa Indonesia](README.id.md) · [اردو](README.ur.md)

Um caranguejinho de píxeis no seu ambiente de trabalho. Claw’d levanta os olhos do portátil quando o Claude precisa de si, segue o ponteiro com o olhar e procura uma janela onde descansar entre respostas.

[**v0.7.0**](https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/tag/v0.7.0) · macOS · Windows · Linux · [Zumbyte · AppSolution](https://zumbyte.de/)

## Arena sem fim · 0.7.0

Abra a arena maximizada nos recordes. Use WASD ou as setas para mover Claw’d, que dispara automaticamente. Cada nível tem quatro ondas e um chefe.

Começa com três vidas e ganha mais uma a cada dois níveis concluídos. Combine tiros perfurantes, disparos múltiplos e dano em área. O melhor nível e a melhor onda ficam guardados neste dispositivo.

## Por dentro da aplicação

![Companheiro](media/app-overview.png)

| Definições da sobreposição | Ligações |
| --- | --- |
| ![Definições da sobreposição](media/app-settings.png) | ![Ligações](media/app-claude.png) |

| Sobre e atualizações | Recordes e contas da arena |
| --- | --- |
| ![Sobre e atualizações](media/app-updates.png) | ![Recordes e contas da arena](media/app-highscores.png) |


O painel de atualizações foi capturado sem qualquer pedido à rede. A imagem dos recordes mostra a classificação nativa com uma sessão de teste local e pontuações de exemplo.

As imagens mostram a interface do Mac em inglês com leituras de quota de exemplo. A consola do navegador é uma reconstituição local. [↗](media/CAPTURES.md)

## Instalação

No macOS 13 ou posterior, abra o PKG universal ou descomprima a aplicação e coloque-a em Aplicações. No Windows x64, execute o instalador ou extraia o ZIP portátil antes de abrir o executável. Em Linux x86-64 pode usar o DEB, o RPM ou o arquivo tar. A página da versão apresenta os ficheiros publicados para cada plataforma.

A versão para Mac suporta Apple Silicon e Intel. Os exemplos de janelas, permissões e integração com o Claude Code referem-se à aplicação nativa para Mac. Em Linux, a integração também depende do sistema de janelas.

Os clientes Windows e Linux usam Qt. Em Windows e X11, o Claw’d consegue ler a posição da janela ativa e fixar-se nela. A fixação a janelas está indisponível em Wayland. Nesse sistema, a deteção de inatividade usa o GNOME IdleMonitor quando disponível. Sem um sinal de inatividade, a arena aguarda a autorização explícita para jogar durante a utilização.

| OS | Instalação |
| --- | --- |
| macOS | [PKG](https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/download/v0.7.0/Clawd-Companion-0.7.0-macOS-universal.pkg) · [ZIP](https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/download/v0.7.0/Clawd-Companion-0.7.0-macOS-universal.zip) |
| Windows x64 | [Setup](https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/download/v0.7.0/Clawd-Companion-0.7.0-Windows-x64-Setup.exe) · [Portable ZIP](https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/download/v0.7.0/Clawd-Companion-0.7.0-Windows-x64-Portable.zip) |
| Linux x86-64 | [DEB](https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/download/v0.7.0/clawd-companion_0.7.0_amd64.deb) · [RPM](https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/download/v0.7.0/clawd-companion-0.7.0-1.x86_64.rpm) · [tar.gz](https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/download/v0.7.0/Clawd-Companion-0.7.0-Linux-x86_64.tar.gz) |

[SHA256SUMS](https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/download/v0.7.0/SHA256SUMS) · [GitHub Releases](https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases)

**macOS · Homebrew**

```sh
brew tap zumbyte/clawd https://github.com/ZUMBYTE-AppSolution/clawd-companion
brew install --cask zumbyte/clawd/clawd-companion
```

**Debian / Ubuntu**

```sh
sudo apt install ./clawd-companion_0.7.0_amd64.deb
```

**Fedora / RHEL**

```sh
sudo dnf install ./clawd-companion-0.7.0-1.x86_64.rpm
```

## Enquanto o Claude trabalha

| Evento visível | Reação do Claw’d |
| --- | --- |
| O Claude escreve ou edita | Escreve no teclado do seu pequeno portátil. |
| Planeamento, pesquisa ou leitura | Desenha um plano no quadro, examina fontes com uma lupa ou abre uma pasta. |
| Execução de código ou criação de um artefacto | Trabalha num pequeno terminal ou desenha num cavalete. |
| Uma ferramenta pede autorização | Desenrola um cartaz «OK?» até o pedido ser resolvido. Responda no Claude. |
| O Claude Code comunica subagentes | Faz malabarismos com pequenas figuras. O estado indica o número real de agentes. |
| Uma resposta termina ou surge um aviso | Desce por uma corda para festejar ou mostra o texto do aviso num balão de fala em píxeis. |

## Ligar o Claude Desktop (macOS)

1. Abra **Conexões** no Claw’d e ative a ligação ao **Claude Desktop**.
2. Escolha **Permitir acesso…**. No macOS, abra **Definições do Sistema → Privacidade e segurança → Acessibilidade** e ative o **Claw’d Companion**.
3. Na **aplicação Claude** do Mac, abra **Definições → Utilização** e deixe a página aberta por instantes. Selecione **Ler agora** no Claw’d para voltar a consultá-la.

Também pode abrir o menu **Utilização** junto à caixa de mensagem no Claude. Com o menu aberto, o Claw’d pode ler os períodos apresentados. Quando está fechado, o botão só indica o período identificado no rótulo, como o limite semanal.

O Claw’d lê a percentagem restante da sessão ou da semana e a hora de reposição quando o Claude apresenta esses valores num formato compatível. Volte a abrir a página de utilização para obter uma leitura atualizada.

Ao ativar a ligação, o Claw’d seleciona **Claude Desktop** como fonte da quota. A última leitura válida conserva a data e hora originais. Se escolher outra fonte em **Companheiro → Limites de uso**, a escolha mantém-se após reiniciar.

[Apple](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac) · [Claude](https://support.claude.com/en/articles/17007452-what-is-a-limit-reset)

## Ligar o Claude.ai

Ative a ligação ao navegador em Ligações. No Chrome, Edge ou Brave, ative o modo de programador, escolha carregar uma extensão descompactada e selecione a pasta BrowserExtension fornecida. Cole o código de emparelhamento no painel da extensão e recarregue o separador do Claude.ai. No Mac, a aplicação inclui também uma extensão para Safari. Ative-a e permita o acesso a claude.ai.

Abra a página de utilização no navegador emparelhado. Se o Claude apresentar uma quota de sessão ou semanal, o Claw’d pode mostrar a percentagem restante, a hora da reposição e a última leitura. Os prazos relativos são aproximados. Os valores ausentes ou expirados ficam em branco. A extensão transmite por ligação local a atividade e os avisos visíveis nos separadores abertos.

[Claude.ai](https://claude.ai/settings/usage) · [Safari](https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension)

### Experimente um balão de fala na consola do navegador

Este exemplo acrescenta um aviso temporário e visível ao separador emparelhado do Claude.ai. A extensão passa o texto ao Claw’d. A demonstração é local. A sequência ilustrada do navegador também usa eventos encenados.

```js
(() => {
  const notice = document.createElement("div");
  notice.setAttribute("role", "alert");
  notice.textContent = "Claw’d pixel bubble test";
  Object.assign(notice.style, {
    position: "fixed", top: "1rem", right: "1rem", zIndex: "2147483647",
    background: "#fff", color: "#222", padding: "0.75rem"
  });
  document.body.append(notice);
  setTimeout(() => notice.remove(), 4000);
})();
```

![Experimente um balão de fala na consola do navegador](media/browser-bridge-demo.gif)

**Claude.ai → Claw’d · JSON**

```jsonl
{"type":"activity","state":"planning"}
{"type":"activity","state":"executing"}
{"type":"activity","state":"done"}
```

## Passeios pelas janelas, jogos com o cursor e arena de vírus

No Mac, arraste o Claw’d para uma janela, clique com o botão direito e escolha Pin to Window. Mantém a posição quando a janela se move e pode descer por uma corda a partir desse ponto. Nos seus passeios, trepa às barras de título, olha à volta, pestaneja e salta. Os olhos seguem o ponteiro. O lança-letras volta a apontar em cada disparo de uma rajada aleatória de 3 a 42. O contador regista o contacto com um projétil visível.

No Mac, uma ronda automática no ambiente de trabalho pode começar após pelo menos 90 segundos sem interação. O Claw’d tem 100 pontos de vida. Duas vagas aleatórias antecedem o chefe final. Observe as barras de vida e apanhe curas, escudos ou tiro rápido. Uma interação pausa o jogo. Ative a opção de jogar durante a utilização para ajudar com cliques. Se perder, fica uma lápide com GIT durante cinco minutos reais, até ele sair da terra. A música e os efeitos podem ser ligados em separado.

Nas definições da sobreposição, escolha o idioma, reduza o movimento e ajuste o volume. Pode silenciar cada som em separado. Os avisos do Claude.ai mantêm o texto original.

## Recordes e contas da arena

Os recordes apresentam os pontos locais, eliminações, mortes, rácio entre eliminações e mortes e vitórias. Conta cada ronda concluída em que tenha atingido um inimigo ou apanhado um bónus que tenha tido efeito. Para entrar na classificação online, crie uma conta própria da arena com nome de utilizador, e-mail e palavra-passe e inicie sessão na aplicação. Cada ronda classificada é iniciada por si. O servidor confirma as ações e calcula o resultado. A classificação mostra o nome de utilizador e as estatísticas de jogo. O e-mail permanece privado. O jogo online requer ligação ao servidor.

## Galeria de animações

| Expressões e jogos | Movimento nas janelas |
| --- | --- |
| ![Expressões e jogos](media/poses-idle.gif) | ![Movimento nas janelas](media/poses-movement.gif) |

| Ferramentas e autorizações do Claude | Combate, sepultura e regresso à vida |
| --- | --- |
| ![Ferramentas e autorizações do Claude](media/poses-work.gif) | ![Combate, sepultura e regresso à vida](media/poses-arcade.gif) |

![Passeios pelas janelas, jogos com o cursor e arena de vírus](media/virus-arena.gif)

▶ [Ver a arena com som. O vídeo encurta os cinco minutos de espera junto à sepultura.](media/virus-arena.mp4)

## Atualizações e desenvolvimento local

A aplicação consulta as versões no GitHub ao arrancar e depois diariamente. O aviso de nova versão dá acesso às alterações e ao pacote adequado ao seu sistema.

Em Sobre e atualizações, procure uma nova versão e escolha um pacote. Depois de o descarregar, instale-o como indicado acima. Em Ligações no Mac, pode ativar separadamente a atividade do Claude Code e a leitura da quota. Inicie uma nova sessão do Claude Code após a configuração. O navegador e o terminal mantêm leituras independentes.

A aplicação para Mac usa Swift e AppKit. Instale o Xcode e compile a partir da raiz do repositório. Os testes JavaScript usam dados locais de navegador. O cliente de ambiente de trabalho portátil encontra-se em Desktop.

```sh
./Scripts/build-mac.sh
swift test
node --test BrowserTests/*.test.js
python3 Scripts/test-hooks.py
```

[Swift](../Package.swift) · [Desktop](../Desktop/) · [Claude Code](https://code.claude.com/docs/en/hooks) · [Status line](https://code.claude.com/docs/en/statusline)

[Windows](../Scripts/package-windows.ps1) · [Linux](../Scripts/package-linux.sh)

## Estúdio e comunidade

Andreas Zumbansen dirige a Zumbyte · AppSolution em Kamen, na Alemanha. O estúdio independente desenvolve aplicações móveis e de computador, bem como software à medida para empresas e equipas.

Zumbyte · AppSolution · Kastanienallee 16a · 59174 Kamen · DE · +49 177 4149667

[Zumbyte](https://zumbyte.de/) · [Informação legal](https://zumbyte.de/impressum/) · [info@zumbyte.de](mailto:info@zumbyte.de)

Um abraço a toda a comunidade que programa com IA. Obrigado por criarem, partilharem e se ajudarem!
