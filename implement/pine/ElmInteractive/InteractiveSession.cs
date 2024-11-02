using Pine.Core;
using Pine.PineVM;
using System;
using System.Collections.Generic;

namespace ElmTime.ElmInteractive;

public interface IInteractiveSession : IDisposable
{
    Result<string, SubmissionResponse> Submit(string submission);

    static ElmEngineTypeCLI DefaultImplementation => ElmEngineTypeCLI.Pine;

    static IInteractiveSession Create(
        TreeNodeWithStringPath compilerSourceFiles,
        TreeNodeWithStringPath? appCodeTree,
        ElmEngineType engineType) =>
        engineType switch
        {
            ElmEngineType.JavaScript_Jint =>
            new InteractiveSessionJavaScript(
                compileElmProgramCodeFiles: compilerSourceFiles,
                appCodeTree: appCodeTree,
                InteractiveSessionJavaScript.JavaScriptEngineFlavor.Jint),

            ElmEngineType.JavaScript_V8 =>
            new InteractiveSessionJavaScript(
                compileElmProgramCodeFiles: compilerSourceFiles,
                appCodeTree: appCodeTree,
                InteractiveSessionJavaScript.JavaScriptEngineFlavor.V8),

            ElmEngineType.Pine pineConfig =>
            new InteractiveSessionPine(
                compilerSourceFiles: compilerSourceFiles,
                appCodeTree: appCodeTree,
                overrideSkipLowering: false,
                caching: pineConfig.Caching,
                autoPGO: pineConfig.DynamicPGOShare),

            _ =>
            throw new ArgumentOutOfRangeException(nameof(engineType), $"Unexpected engine type value: {engineType}"),
        };

    public record SubmissionResponse(
        ElmInteractive.EvaluatedStruct InteractiveResponse,
        IReadOnlyList<string>? InspectionLog = null);
}

public enum ElmEngineTypeCLI
{
    JavaScript_Jint = 1,
    JavaScript_V8 = 2,
    Pine = 4,
    Pine_without_cache = 4001
}

public abstract record ElmEngineType
{
    public record JavaScript_Jint
        : ElmEngineType;

    public record JavaScript_V8
        : ElmEngineType;

    public record Pine(
        bool Caching,
        DynamicPGOShare? DynamicPGOShare)
        : ElmEngineType;
}