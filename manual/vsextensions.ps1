$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\external-tools.ps1')

$extensions = @(
    "ms-dotnettools.csdevkit"
    "ms-dotnettools.csharp"
    "ms-python.python"
    "ms-python.vscode-pylance"
    "ms-python.debugpy"
    "charliermarsh.ruff"
    "dbaeumer.vscode-eslint"
    "esbenp.prettier-vscode"
    "eamodio.gitlens"
    "humao.rest-client"
    "EditorConfig.EditorConfig"
    "redhat.vscode-yaml"
    "PKief.material-icon-theme"
    "Gruntfuggly.todo-tree"
    "openai.chatgpt"
)

foreach ($ext in $extensions) {
    Invoke-ExternalTool code @('--install-extension', $ext)
}
