# Architecture

Assistente G-LAB is moving toward a modular PowerShell/WPF layout inspired by mature Windows utility projects.

The current app still keeps most runtime code in `WinTool.ps1` for stability, while the repository now exposes the target architecture used for the next refactors.

## Target Layout

```text
.
├── config
│   ├── apps.json
│   ├── presets.json
│   └── tweaks.json
├── functions
│   ├── private
│   └── public
├── xaml
│   └── inputXML.xaml
├── assets
│   └── icons
├── scripts
│   ├── start.ps1
│   └── main.ps1
├── pester
└── Compile.ps1
```

## Runtime Flow

```text
bootstrap URL
    -> downloads GitHub ZIP
    -> extracts to TEMP
    -> starts WinTool.ps1 in STA mode
    -> loads config/apps.json
    -> renders app cards with assets/icons
    -> runs WinGet actions on selected apps
```

## Refactor Rules

- Keep `WinTool.ps1` working after every commit.
- Move one concern at a time into `functions`.
- Keep config in JSON and behavior in PowerShell.
- Keep destructive or system-wide changes explicit and logged.
- Validate with `WinTool.ps1 -ValidateOnly` before each push.

## Reference Notes

The reference project separates concerns into:

- `config` for applications, tweaks, presets and navigation.
- `functions/private` for internal helpers.
- `functions/public` for WPF actions.
- `xaml/inputXML.xaml` for the interface.
- `Compile.ps1` for producing a distributable script.

Assistente G-LAB should follow the pattern without copying branding or blindly importing commands.
