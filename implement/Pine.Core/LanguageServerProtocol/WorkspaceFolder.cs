namespace Pine.Core.LanguageServerProtocol;

/// <summary>
/// https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#workspaceFolder
/// </summary>
public record WorkspaceFolder(
    string Uri,
    string Name);
