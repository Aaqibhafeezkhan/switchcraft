# switchcraft 🪄

[![ci](https://github.com/FernandoPazCavalcante/switchcraft/actions/workflows/ci.yml/badge.svg)](https://github.com/FernandoPazCavalcante/switchcraft/actions/workflows/ci.yml)
[![licença: MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-blue.svg)](LICENSE)
[![shell: bash](https://img.shields.io/badge/shell-bash-4EAA25.svg)](https://www.gnu.org/software/bash/)

**A pasta decide quem você é.** Sua identidade no GitHub, chave SSH, assinatura
de commit, conta do `gh` e login do Claude Code trocam sozinhos quando você
dá `cd`.

*switch* + witch*craft* — a mágica de trocar de conta sem fazer nada.

🇺🇸 [Read in English](README.md)

<!-- Trocar este bloco por docs/demo.gif depois de gravar: vhs docs/demo.tape -->

```console
$ cd ~/projects/trabalho && switchcraft status

  directory   /home/voce/projects/trabalho
  profile     trabalho
  git         Seu Nome <voce@empresa.com>
  ssh key     /home/voce/.ssh/id_ed25519_trabalho
  claude      /home/voce/.claude-trabalho        ✓
  gh          /home/voce/.config/gh-trabalho     ✓
  effective   voce@empresa.com                   ✓

$ cd ~/projects/pessoal && switchcraft status

  directory   /home/voce/projects/pessoal
  profile     pessoal
  git         Seu Nome <voce@gmail.com>
  ssh key     /home/voce/.ssh/id_ed25519_pessoal
  claude      /home/voce/.claude-pessoal         ✓
  gh          /home/voce/.config/gh-pessoal      ✓
  effective   voce@gmail.com                     ✓
```

Entre os dois comandos não foi digitado nada além de `cd`.

## Por quê

Se você trabalha em mais de uma organização ao mesmo tempo — um emprego e um
cliente, uma empresa e seus projetos pessoais — cada contexto tem a sua conta do
GitHub, a sua chave SSH e, agora, o seu login do Claude Code.

Esquecer de trocar uma vez e você empurra um commit assinado com a identidade
errada para a org errada. Você descobre no PR, na frente de todo mundo.

As soluções usuais resolvem uma camada cada. O `includeIf` cuida de nome e
e-mail. O `~/.ssh/config` cuida das chaves. Um alias cuida do
`CLAUDE_CONFIG_DIR`. Você acaba mantendo quatro mecanismos que podem discordar
entre si, e nada avisa quando um deles está errado.

O switchcraft liga as cinco camadas à mesma chave — o diretório em que você está
— e traz um `doctor` que diz qual camada quebrou quando algo sai errado.

## Começando

```bash
git clone https://github.com/FernandoPazCavalcante/switchcraft.git
cd switchcraft && ./install.sh
```

Isso coloca o `switchcraft` no seu PATH e pergunta onde ficam seus projetos.
Depois adicione uma identidade por conta:

```bash
switchcraft add trabalho \
  --name 'Seu Nome' --email voce@empresa.com --github-user voce-no-trabalho

switchcraft add pessoal \
  --name 'Seu Nome' --email voce@gmail.com --github-user voce
```

Cada `add` gera a chave SSH, escreve o perfil do git, cria a pasta e configura o
`.envrc` dela. Sobram dois passos manuais, uma vez por conta:

1. **Registrar a chave pública no GitHub** — adicione
   `~/.ssh/id_ed25519_<perfil>.pub` **duas vezes**: como *Authentication key*
   (clone/push) e como *Signing key* (para os commits aparecerem como
   Verified).
2. **Fazer login no Claude Code** de dentro da pasta:
   ```bash
   cd ~/projects/trabalho && claude   # /login, e saia com /exit
   ```

Depois confira:

```bash
switchcraft doctor
```

Ele aponta cada peça faltando e o comando exato para resolver.

## Comandos

| Comando | O que faz |
| --- | --- |
| `switchcraft init` | cria a configuração |
| `switchcraft add <perfil>` | adiciona uma identidade (chave, perfil git, pasta, `.envrc`) |
| `switchcraft link <perfil> <dir>` | vincula **qualquer** diretório a um perfil |
| `switchcraft unlink <dir>` | para de gerenciar um diretório, sem mexer nos arquivos |
| `switchcraft list` | todos os perfis e onde cada um vale |
| `switchcraft status [dir]` | qual identidade vale aqui, e se ela está ativa |
| `switchcraft doctor` | checa as cinco camadas e diz o que falta |
| `switchcraft apply` | reconcilia tudo a partir da configuração (idempotente) |
| `switchcraft remove <perfil>` | remove uma identidade (`--purge` apaga chave e histórico também) |
| `switchcraft uninstall` | desfaz todas as mudanças nesta máquina |

Use `--dry-run` em qualquer comando para ver o que ele escreveria, sem escrever.

## Como funciona

| Camada | Mecanismo |
| --- | --- |
| Identidade git (nome/e-mail) | `includeIf "gitdir:…"` na config global do git |
| Chave SSH por conta | `core.sshCommand` por perfil (remotes seguem `git@github.com`) |
| Assinatura de commit | `user.signingkey` por perfil + `gpg.format = ssh` |
| Credenciais HTTPS | `credential.helper = store --file=…` por perfil |
| Conta do GitHub CLI | `GH_CONFIG_DIR` exportado pelo `.envrc` (direnv) |
| Conta do Claude Code | `CLAUDE_CONFIG_DIR` exportado pelo `.envrc` (direnv) |

Os commits são assinados com a mesma chave SSH que autentica a conta, então não
há GPG para administrar.

Tudo o que o switchcraft escreve em um arquivo que já é seu fica entre as cercas
`# >>> switchcraft >>>`, então uma nova execução substitui apenas o próprio
bloco e o `uninstall` desfaz exatamente aquilo. Sua config global do git recebe
um backup, antes da primeira edição, em `~/.gitconfig.switchcraft.bak`.

### Identidade por remote, não só por pasta

Uma regra de diretório não ajuda num repositório que você clonou em outro lugar.
No git 2.36+ dá para casar pela URL do remote, e aí a identidade segue o
*repositório*, em qualquer caminho:

```bash
switchcraft add trabalho --name 'Seu Nome' --email voce@empresa.com \
  --remote 'git@github.com:empresa/**'
```

Qualquer clone daquela org recebe a identidade de trabalho.

## Por que não só…

| Em vez do switchcraft | O que isso resolve | O que fica de fora |
| --- | --- | --- |
| `includeIf` na mão | nome e e-mail por pasta | chave SSH, assinatura, `gh`, Claude Code — e você mantém os blocos |
| `git config --local` por repo | a identidade certa naquele repo | você precisa lembrar, em cada clone novo. Esquecer é justamente o problema |
| um alias para `CLAUDE_CONFIG_DIR` | duas contas do Claude | você ainda escolhe a conta digitando o alias certo, e git/ssh/gh continuam de fora |
| `gh auth switch` | a conta do `gh` | é global, não por diretório, e não fala nada de git, ssh ou Claude |
| aliases de host no `~/.ssh/config` | uma chave por conta | toda URL de remote precisa ser reescrita; identidade, `gh` e Claude ficam de fora |
| [gitswitch](https://github.com/UzairRehman4/gitswitch), [gh-account-switcher](https://github.com/calghar/gh-account-switcher) | identidade git e SSH por pasta | sem Claude Code, sem `gh` por diretório, sem `doctor`, sem desinstalação reversível |

## Requisitos

- **bash** 3.2+ (funciona no macOS de fábrica), **git**, **ssh-keygen**
- **[direnv](https://direnv.net)** — instalado para você via brew, apt, pacman, dnf, apk ou zypper
- **git 2.36+** só para o casamento por `--remote`; por diretório funciona em qualquer versão
- opcional: **[gh](https://cli.github.com)** para contas do GitHub CLI por diretório
- opcional: **[Claude Code](https://claude.com/claude-code)** para logins por diretório

Shells: bash, zsh, fish, tcsh e elvish recebem o hook automaticamente. Outros
(nushell, por exemplo) recebem a linha para adicionar à mão.

Testado em Linux e macOS no CI.

## Pegadinhas

Estas custam tempo real para descobrir. São características das ferramentas
envolvidas, não bugs do switchcraft.

- **`cd` dentro de uma sessão do Claude não troca de conta.** Variáveis de
  ambiente são fixadas quando o processo inicia, então o direnv não consegue
  mudar uma sessão em andamento. Saia e rode `claude` de novo na pasta destino.
- **O `gh` dentro de uma sessão do Claude segue o diretório da sessão, não o seu
  `cd`.** Mesmo motivo: o `GH_CONFIG_DIR` foi herdado na inicialização.
- **Não dê Ctrl+C depois de fazer login no Claude Code.** As credenciais são
  gravadas em disco no encerramento normal; o SIGINT mata o processo antes e o
  login é perdido silenciosamente. Saia com `/exit` ou Ctrl+D.
- **O caminho na sua config do git pode não ser o que você digitou.** O git
  resolve symlinks antes de casar o `includeIf`, então o switchcraft escreve o
  caminho *canônico* na regra. No macOS isso é o caso comum, não exceção —
  `/var` é symlink para `/private/var`, então tudo sob `$TMPDIR` passa por um.
  Escrever o caminho lógico faria a regra nunca disparar, e você commitaria com
  a identidade global: exatamente a falha que esta ferramenta existe para
  evitar.
- **Clone via SSH** (`git@github.com:…`) para usar as chaves por conta. Remotes
  HTTPS também funcionam, pelo arquivo de credenciais do perfil, mas aí a chave
  e a assinatura não entram na história.

## Segurança

- Chaves privadas, tokens e credenciais do Claude são gerados ou obtidos **por
  máquina** e nunca entram neste repositório. O repo versiona só estrutura e
  templates — é por isso que ele pode ser público.
- As chaves são geradas **sem passphrase** para que o `cd` continue sem atrito.
  Defina `SC_ASK_PASSPHRASE=1` antes do `add` ou `apply` para ser perguntado, e
  use um agente.
- Tokens **não ficam na configuração**. Aponte o switchcraft para um comando que
  imprime o token, e o segredo continua no seu gerenciador de senhas:
  ```bash
  switchcraft add trabalho --token-cmd 'pass show github/trabalho'
  ```
  O token resolvido vai para `~/.config/switchcraft/credentials-<perfil>`
  (modo 600), fora da sua árvore de trabalho.
- Achou algo sensível? Veja o [SECURITY.md](SECURITY.md).

## Resolvendo problemas

Rode `switchcraft doctor` primeiro — ele cobre quase tudo disto. Depois:

| Sintoma | Causa | Solução |
| --- | --- | --- |
| commits com o e-mail errado | o diretório não está vinculado, ou um diretório pai está em outro perfil | `switchcraft status` na pasta; ele aponta qual perfil vence |
| `echo $CLAUDE_CONFIG_DIR` vazio | o hook do direnv não carregou, ou o dir não foi permitido | abra um terminal novo e rode `direnv allow <dir>` |
| `gh` na conta errada | `GH_TOKEN` ou `GITHUB_TOKEN` exportado no ambiente sobrepõe tudo | `unset GH_TOKEN GITHUB_TOKEN` |
| commits mostram "No signature" local | falta o arquivo de signatários permitidos | `switchcraft apply` (o GitHub verifica de todo jeito — isso é cosmético) |
| chave rejeitada pelo GitHub | a chave pública não está registrada, ou só como auth | adicione o `.pub` duas vezes: Authentication **e** Signing |
| Claude Code pede login de novo | a sessão anterior morreu com Ctrl+C | faça login e saia com `/exit` |

## Desinstalando

```bash
./uninstall.sh            # remove todo bloco que o switchcraft escreveu
./uninstall.sh --purge    # apaga também as chaves e os dirs de config do gh e Claude
```

Sem `--purge`, suas chaves SSH, o histórico de conversas do Claude e a
configuração são mantidos. Arquivos de projeto nunca são tocados.

## Vindo da v1

A v1 guardava seus dados num `.env` dentro do clone. A v2 move isso para
`~/.config/switchcraft/config`, então a ferramenta não depende mais de onde foi
clonada. Rodar `./install.sh` migra um `.env` existente automaticamente; só os
tokens não são levados, porque a v2 os lê de um comando.

## Contribuindo

Issues e pull requests são bem-vindos — veja o [CONTRIBUTING.md](CONTRIBUTING.md).
A suíte de testes roda contra um `$HOME` descartável, então você pode mexer no
instalador sem risco para o seu próprio setup:

```bash
bats tests/
```

## Licença

[MIT](LICENSE) © Fernando Paz Silva Cavalcante
