# Assistente G-LAB

Central de manutencao para Windows feita em PowerShell/WPF, com instalacao de aplicativos via WinGet, catalogo em JSON, icones por app, tweaks seguros e suporte a inicializacao remota.

O projeto segue a ideia de uma ferramenta unica para preparar, corrigir e padronizar maquinas Windows com rapidez, mantendo as acoes visiveis, auditaveis e faceis de evoluir.

## Comando Rapido

Quando a rota do dominio estiver publicada:

```powershell
irm https://www.glabcursos.com.br/win | iex
```

Enquanto isso, tambem e possivel chamar diretamente pelo GitHub:

```powershell
irm https://raw.githubusercontent.com/mrmatias-of/assistente-glab/main/web-bootstrap-template.ps1 | iex
```

## Recursos

- Interface grafica WPF em PowerShell.
- Catalogo de aplicativos em `config/apps.json`.
- Instalacao, atualizacao e remocao de apps via WinGet.
- Busca por nome, ID, categoria, descricao e tags.
- Categorias como Browsers, Development, Microsoft Tools, Multimedia Tools, Pro Tools e Utilities.
- Icones locais em PNG para os cards dos aplicativos.
- Abas dedicadas para Install, Tweaks, Config e Updates.
- Console de log integrado para acompanhar comandos executados.
- Bootstrap remoto que baixa o projeto completo antes de abrir a interface.

## Execucao Local

Clone o repositorio ou abra a pasta do projeto e execute:

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-Assistente-GLAB.ps1
```

Tambem e possivel chamar diretamente o app principal:

```powershell
powershell -ExecutionPolicy Bypass -File .\WinTool.ps1
```

Para validar o carregamento sem abrir a janela:

```powershell
powershell -ExecutionPolicy Bypass -File .\WinTool.ps1 -ValidateOnly
```

## Estrutura

```text
.
├── WinTool.ps1
├── Start-Assistente-GLAB.ps1
├── bootstrap.ps1
├── web-bootstrap-template.ps1
├── config
│   └── apps.json
├── assets
│   └── icons
└── src
    └── New-IconAssets.ps1
```

## Catalogo de Aplicativos

Os apps ficam em `config/apps.json`. Cada item usa este formato:

```json
{
  "name": "Visual Studio Code",
  "id": "Microsoft.VisualStudioCode",
  "category": "Development",
  "description": "Editor de codigo da Microsoft.",
  "icon": "VS",
  "accent": "#007ACC",
  "domain": "code.visualstudio.com",
  "tags": ["code", "editor", "dev"]
}
```

O campo `id` deve ser o identificador exato do WinGet. Para conferir um app:

```powershell
winget search "nome do app"
```

## Icones

Os icones usados pela interface ficam em:

```text
assets/icons
```

Para baixar favicons reais com base nos dominios do catalogo:

```powershell
powershell -ExecutionPolicy Bypass -File .\src\New-IconAssets.ps1
```

Se algum download falhar, o script gera um fallback visual com as iniciais do app.

## Bootstrap Remoto

O arquivo `web-bootstrap-template.ps1` baixa o ZIP da branch `main`, extrai em uma pasta temporaria e executa o `WinTool.ps1`.

Fluxo:

```text
irm dominio/win | iex
        │
        ├── baixa assistente-glab/main.zip
        ├── extrai em %TEMP%\Assistente-GLAB
        └── executa WinTool.ps1 em modo STA
```

## Seguranca

Este projeto executa comandos no Windows. Leia o script antes de usar em maquinas de producao.

Boas praticas recomendadas:

- Usar HTTPS para qualquer bootstrap remoto.
- Evitar comandos destrutivos na inicializacao.
- Separar tweaks sensiveis de acoes comuns.
- Manter logs visiveis para o usuario.
- Preferir alteracoes reversiveis.
- Assinar scripts em ambientes profissionais.
- Publicar releases ou commits fixos quando precisar de previsibilidade.

O MVP atual aplica somente tweaks simples no usuario atual:

- Mostrar extensoes de arquivos.
- Mostrar arquivos ocultos.

## Desenvolvimento

Depois de alterar o projeto, valide:

```powershell
powershell -ExecutionPolicy Bypass -File .\WinTool.ps1 -ValidateOnly
```

Depois registre as mudancas:

```powershell
git status
git add .
git commit -m "Describe your change"
git push
```

## Roadmap

- Substituir todos os fallbacks por icones oficiais.
- Adicionar perfis de instalacao, como tecnico, gamer, dev e escritorio.
- Criar painel de apps instalados.
- Adicionar backup/restore de configuracoes.
- Criar pontos de restauracao antes de tweaks sensiveis.
- Separar modulos em `functions`, `scripts` e `config`.
- Publicar releases versionadas.
- Adicionar assinatura de script.

## Inspiracao

Inspirado no formato de utilitarios Windows como o Chris Titus Tech WinUtil, com foco em uma identidade propria para o ecossistema G-LAB.
