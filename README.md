# Assistente G-LAB

Um assistente local inspirado no Chris Titus Tech WinUtil: interface WPF em PowerShell, catalogo de aplicativos em JSON, icones reais por app e acoes em lote via WinGet.

## Como rodar localmente

Abra o PowerShell nesta pasta e execute:

```powershell
powershell -ExecutionPolicy Bypass -File .\WinTool.ps1
```

Ou use o bootstrap local:

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-Assistente-GLAB.ps1
```

## Como virar um comando estilo `irm ... | iex`

Quando voce hospedar o conteudo em um servidor HTTPS, o endpoint deve devolver um script pequeno de bootstrap que baixe/execute a versao principal. O modelo seria:

```powershell
irm https://seu-dominio.com/wintool | iex
```

Para producao, assine os scripts, use HTTPS, publique hashes das versoes e mantenha acoes sensiveis separadas da inicializacao.

## Publicar no GitHub

Depois de criar um repositorio vazio no GitHub, rode nesta pasta:

```powershell
git remote add origin https://github.com/SEU-USUARIO/assistente-glab.git
git branch -M main
git push -u origin main
```

## Arquivos

- `WinTool.ps1`: aplicacao WPF principal do Assistente G-LAB.
- `Start-Assistente-GLAB.ps1`: inicializador local com nome do projeto.
- `config/apps.json`: catalogo de aplicativos WinGet, com categoria, cor e icone.
- `assets/icons`: imagens PNG locais usadas nos cards dos aplicativos.
- `src/New-IconAssets.ps1`: baixa favicons reais dos dominios oficiais e usa fallback local quando necessario.
- `bootstrap.ps1`: inicializador local legado.
- `web-bootstrap-template.ps1`: modelo para criar um endpoint estilo `irm ... | iex`.

## Escopo seguro deste MVP

- Instala, atualiza e remove aplicativos selecionados usando WinGet.
- Atualiza todos os aplicativos via `winget upgrade --all`.
- Aplica apenas tweaks simples no usuario atual: mostrar extensoes e arquivos ocultos.
- Nao remove bloatware, nao mexe em servicos do sistema e nao altera politicas globais.
