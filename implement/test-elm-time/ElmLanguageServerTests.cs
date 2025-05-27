using Pine;
using Pine.Core.LanguageServerProtocol;
using Pine.Elm;
using StreamJsonRpc;
using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Xunit;

namespace TestElmTime;

public class ElmLanguageServerTests
{
    [Fact]
    public async Task Language_server_reports_capabilities_Async()
    {
        var executablePath = FindPineExecutableFilePath();

        using var lspProcess = Process.Start(new ProcessStartInfo(executablePath)
        {
            Arguments = "  lsp  --log-dir=.",
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
        }) ?? throw new Exception("Failed starting process");

        try
        {
            var handler =
                new HeaderDelimitedMessageHandler(
                    sendingStream: lspProcess.StandardInput.BaseStream,
                    receivingStream: lspProcess.StandardOutput.BaseStream,
                    formatter: LanguageServerRpcTarget.JsonRpcMessageFormatterDefault());

            using var jsonRpc = new JsonRpc(handler);

            jsonRpc.StartListening();

            var initParams =
                new InitializeParams(
                    ProcessId: Environment.ProcessId,
                    Capabilities: new ClientCapabilities(Workspace: null, TextDocument: null),
                    RootPath: null,
                    RootUri: null,
                    WorkspaceFolders: [],
                    ClientInfo: null);

            Console.WriteLine(
                "initParams:\n" +
                System.Text.Json.JsonSerializer.Serialize(initParams));

            var initResponse =
                await jsonRpc.InvokeWithParameterObjectAsync<object>(
                    "initialize",
                    initParams);

            Console.WriteLine(
                "initResponse:\n" +
                System.Text.Json.JsonSerializer.Serialize(initResponse));

            /*
             * Example from deno lsp:
             * {"capabilities":{"textDocumentSync":{"openClose":true,"change":2,"save":{}},"selectionRangeProvider":true,"hoverProvider":true,"completionProvider":{"resolveProvider":true,"triggerCharacters":[".","\u0022","\u0027","\u0060","/","@","\u003C","#"],"allCommitCharacters":[".",";","("]},"signatureHelpProvider":{"triggerCharacters":[",","(","\u003C"],"retriggerCharacters":[")"]},"definitionProvider":true,"typeDefinitionProvider":true,"implementationProvider":true,"referencesProvider":true,"documentHighlightProvider":true,"documentSymbolProvider":{"label":"Deno"},"workspaceSymbolProvider":true,"codeActionProvider":true,"codeLensProvider":{"resolveProvider":true},"documentFormattingProvider":true,"renameProvider":true,"foldingRangeProvider":true,"executeCommandProvider":{"commands":["deno.cache","deno.reloadImportRegistries"]},"workspace":{"workspaceFolders":{"supported":true,"changeNotifications":true}},"callHierarchyProvider":true,"semanticTokensProvider":{"legend":{"tokenTypes":["class","enum","interface","namespace","typeParameter","type","parameter","variable","enumMember","property","function","method"],"tokenModifiers":["declaration","static","async","readonly","defaultLibrary","local"]},"range":true,"full":true},"inlayHintProvider":true,"experimental":{"denoConfigTasks":true,"testingApi":true}},"serverInfo":{"name":"deno-language-server","version":"2.0.0 (release, x86_64-pc-windows-msvc)"}}
             * */
        }
        finally
        {
            lspProcess.Kill();
        }
    }

    [Fact]
    public void Computes_text_edits_for_format_document_request()
    {
        // Define test cases with original text, new text, and expected text edits
        var testCases = new List<(string OriginalText, string NewText, IReadOnlyList<TextEdit> ExpectedEdits)>
        {
            // Test case 1: No changes
            (
                "module Main exposing (..)\n\nmain = text \"Hello\"",
                "module Main exposing (..)\n\nmain = text \"Hello\"",
                new List<TextEdit>()
            ),

            // Test case 2: Single line change
            (
                "module Main exposing (..)\n\nmain = text \"Hello\"",
                "module Main exposing (..)\n\nmain = text \"Hello, World!\"",
                new List<TextEdit>
                {
                    new TextEdit(
                        Range: new Range(
                            Start: new Position(Line: 2, Character: 0),
                            End: new Position(Line: 2, Character: 19)),
                        NewText: "main = text \"Hello, World!\"")
                }
            ),

            // Test case 3: Multiple line changes in different parts
            (
                "module Main exposing (..)\n\ntype alias Model = {}\n\ninit = {}\n\nupdate msg model = model\n\nview model = text \"Hello\"",
                "module Main exposing (..)\n\ntype alias Model = { counter : Int }\n\ninit = { counter = 0 }\n\nupdate msg model = model\n\nview model = text \"Hello, World!\"",
                new List<TextEdit>
                {
                    new TextEdit(
                        Range: new Range(
                            Start: new Position(Line: 2, Character: 0),
                            End: new Position(Line: 2, Character: 21)),
                        NewText: "type alias Model = { counter : Int }"),
                    new TextEdit(
                        Range: new Range(
                            Start: new Position(Line: 4, Character: 0),
                            End: new Position(Line: 4, Character: 9)),
                        NewText: "init = { counter = 0 }"),
                    new TextEdit(
                        Range: new Range(
                            Start: new Position(Line: 8, Character: 0),
                            End: new Position(Line: 8, Character: 26)),
                        NewText: "view model = text \"Hello, World!\"")
                }
            ),

            // Test case 4: Adding lines
            (
                "module Main exposing (..)\n\nmain = text \"Hello\"",
                "module Main exposing (..)\n\n-- This is a comment\n-- Multiple lines added\n\nmain = text \"Hello\"",
                new List<TextEdit>
                {
                    new TextEdit(
                        Range: new Range(
                            Start: new Position(Line: 2, Character: 0),
                            End: new Position(Line: 2, Character: 0)),
                        NewText: "-- This is a comment\n-- Multiple lines added\n\n")
                }
            ),

            // Test case 5: Removing lines
            (
                "module Main exposing (..)\n\n-- This is a comment\n-- Multiple lines to remove\n\nmain = text \"Hello\"",
                "module Main exposing (..)\n\nmain = text \"Hello\"",
                new List<TextEdit>
                {
                    new TextEdit(
                        Range: new Range(
                            Start: new Position(Line: 2, Character: 0),
                            End: new Position(Line: 4, Character: 0)),
                        NewText: "")
                }
            ),

            // Test case 6: Change at beginning of document
            (
                "module Main exposing (..)\n\nmain = text \"Hello\"",
                "module App exposing (..)\n\nmain = text \"Hello\"",
                new List<TextEdit>
                {
                    new TextEdit(
                        Range: new Range(
                            Start: new Position(Line: 0, Character: 0),
                            End: new Position(Line: 0, Character: 23)),
                        NewText: "module App exposing (..)")
                }
            ),

            // Test case 7: Change at end of document (with/without trailing newline)
            (
                "module Main exposing (..)\n\nmain = text \"Hello\"",
                "module Main exposing (..)\n\nmain = text \"Hello\"\n",
                new List<TextEdit>
                {
                    new TextEdit(
                        Range: new Range(
                            Start: new Position(Line: 2, Character: 19),
                            End: new Position(Line: 2, Character: 19)),
                        NewText: "\n")
                }
            ),

            // Test case 8: Multiple adjacent line changes that should be combined
            (
                "module Main exposing (..)\n\nf x = x + 1\n\ng y = y * 2\n\nmain = text \"Hello\"",
                "module Main exposing (..)\n\nf x =\n    x + 1\n\ng y =\n    y * 2\n\nmain = text \"Hello\"",
                new List<TextEdit>
                {
                    new TextEdit(
                        Range: new Range(
                            Start: new Position(Line: 2, Character: 0),
                            End: new Position(Line: 2, Character: 10)),
                        NewText: "f x =\n    x + 1"),
                    new TextEdit(
                        Range: new Range(
                            Start: new Position(Line: 4, Character: 0),
                            End: new Position(Line: 4, Character: 10)),
                        NewText: "g y =\n    y * 2")
                }
            )
        };

        // Create a language server instance
        var languageServer = new LanguageServer(
            logDelegate: Console.WriteLine,
            elmPackagesSearchDirectories: new List<string>());

        // Test each case
        foreach (var (originalText, newText, expectedEdits) in testCases)
        {
            // Use the ComputeTextEdits method to get actual edits
            var actualEdits = LanguageServer.ComputeTextEdits(originalText, newText);

            // Validate the edits
            Assert.Equal(expectedEdits.Count, actualEdits.Count);

            for (int i = 0; i < expectedEdits.Count; i++)
            {
                var expected = expectedEdits[i];
                var actual = actualEdits[i];

                Assert.Equal(expected.Range.Start.Line, actual.Range.Start.Line);
                Assert.Equal(expected.Range.Start.Character, actual.Range.Start.Character);
                Assert.Equal(expected.Range.End.Line, actual.Range.End.Line);
                Assert.Equal(expected.Range.End.Character, actual.Range.End.Character);
                Assert.Equal(expected.NewText, actual.NewText);
            }

            // Verify that applying the edits to the original text results in the new text
            var resultText = ApplyTextEdits(originalText, actualEdits);
            Assert.Equal(newText, resultText);
        }
    }

    private static string ApplyTextEdits(string originalText, IReadOnlyList<TextEdit> edits)
    {
        // Convert string to lines for easier editing
        var lines = originalText.Split('\n').ToList();

        // Apply edits in reverse order to avoid position changes
        foreach (var edit in edits.OrderByDescending(e => e.Range.Start.Line).ThenByDescending(e => e.Range.Start.Character))
        {
            // Extract the range information
            var startLine = (int)edit.Range.Start.Line;
            var startChar = (int)edit.Range.Start.Character;
            var endLine = (int)edit.Range.End.Line;
            var endChar = (int)edit.Range.End.Character;
            
            // Handle the case where the edit spans multiple lines
            if (startLine != endLine)
            {
                // Remove full lines between start and end (exclusive)
                if (endLine - startLine > 1)
                {
                    lines.RemoveRange(startLine + 1, endLine - startLine - 1);
                }
                
                // Handle the partial start and end lines
                var startLineContent = lines[startLine];
                var endLineContent = lines.Count > endLine ? lines[endLine] : "";
                
                // Create the new content for the start line
                var newLineContent = startLineContent.Substring(0, startChar);
                
                if (endLine < lines.Count)
                {
                    // Add the remaining content from the end line
                    if (endChar < endLineContent.Length)
                    {
                        newLineContent += endLineContent.Substring(endChar);
                    }
                    
                    // Replace start line and remove end line
                    lines[startLine] = newLineContent;
                    lines.RemoveAt(startLine + 1); // End line is now at startLine + 1
                }
                else
                {
                    // End line doesn't exist, just update start line
                    lines[startLine] = newLineContent;
                }
            }
            else
            {
                // Single line edit
                var line = lines[startLine];
                lines[startLine] = line.Substring(0, startChar) + line.Substring(endChar);
            }
            
            // Insert the new text
            if (!string.IsNullOrEmpty(edit.NewText))
            {
                var newTextLines = edit.NewText.Split('\n');
                
                // Insert the first line at the edit position
                lines[startLine] = lines[startLine].Insert(startChar, newTextLines[0]);
                
                // Insert any additional lines
                for (int i = 1; i < newTextLines.Length; i++)
                {
                    lines.Insert(startLine + i, newTextLines[i]);
                }
            }
        }
        
        return string.Join('\n', lines);
    }

    static string FindPineExecutableFilePath()
    {
        /*
         * Navigate from current working directory to the first parent named "implement", then to "pine", then to "pine.exe"
         * Then find the pine executable file in "/pine/ ** /bin/*"
         * */

        var currentDirectory = Directory.GetCurrentDirectory();

        var implementDirectory = new DirectoryInfo(currentDirectory);

        while (implementDirectory.Name is not "implement")
        {
            implementDirectory =
                implementDirectory.Parent ?? throw new Exception("Could not find 'implement' directory");
        }

        var pineDirectoryPath = Path.Combine(implementDirectory.FullName, "pine");

        var pineDirectory =
            new FileStoreFromSystemIOFile(pineDirectoryPath);

        /*
         * The executable file name can differ depending on the platform, e.g. "pine.exe" on Windows, "pine" on Linux
         * */

        var allFiles =
            pineDirectory.ListFiles().ToImmutableArray();

        foreach (var fileSubPath in allFiles)
        {
            if (!fileSubPath.Contains("bin"))
                continue;

            var fileName = fileSubPath.Last();

            /*
             * The directory containing the executable file can also contain a file named "pine.pdb",
             * therefore, only accept the file if it has the name "pine" or "pine.exe"
             * */

            if (fileName is "pine" || fileName is "pine.exe")
                return Path.Combine(pineDirectoryPath, string.Join('/', fileSubPath));
        }

        throw new Exception("Could not find 'pine' executable");
    }
}
