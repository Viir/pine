module CompileElmAppWithStateShim exposing (..)

import Common
import CompileElmApp
    exposing
        ( AppFiles
        , CompilationError(..)
        , CompileEntryPointConfig
        , ElmChoiceTypeStruct
        , ElmMakeEntryPointKind(..)
        , ElmTypeAnnotation
        , LocatedInSourceFiles(..)
        , SourceDirectories
        , SourceParsedElmModule
        , addModulesFromTextToAppFiles
        , buildJsonConverterFunctionsForTypeAnnotation
        , buildTypeAnnotationText
        , fileContentFromString
        , filePathFromElmModuleName
        , importSyntaxTextFromModuleNameAndAlias
        , indentElmCodeLines
        , mapAppFilesToSupportJsonConverters
        , mapLocatedInSourceFiles
        , modulesToAddForBase64Coding
        , updateFileContentAtPath
        )
import Dict
import Elm.Syntax.Module
import Elm.Syntax.Node
import Elm.Syntax.Range
import Elm.Syntax.TypeAnnotation
import Set


type alias StateShimConfig =
    { jsonConverterDeclarationsConfigs : List ( String, StateShimConfigJsonConverterConfig )
    , jsonConverterDeclarations : Dict.Dict String StateShimConfigJsonConverter
    , appStateType : StateShimConfigSupportingType
    , initAppShimStateExpression : String
    , appStateLessShimExpression : String
    , exposedFunctions : Dict.Dict String ExposedFunctionConfig
    , supportingModules : List String
    , rootModuleSupportingFunctions : List String
    , modulesToImport : List (List String)
    , appStateWithPlatformShimTypeAnnotationFromAppStateAnnotation : String -> String
    }


type alias RootModuleConfig =
    { interfaceToHostRootModuleName : String
    , appRootDeclarationModuleName : String
    , appStateTypeAnnotation : ElmTypeAnnotation
    , modulesToImport : List (List String)
    , supportingJsonConverterFunctions : Dict.Dict String ( List String, String )
    , otherSupportingFunctions : List String
    , appStateWithPlatformShimTypeAnnotationFromAppStateAnnotation : String -> String
    }


type alias ExposedFunctionConfig =
    { description : ExposedFunctionDescription
    , handlerExpression : String
    }


type alias ExposedFunctionDescription =
    { returnType : ExposedFunctionReturnTypeDescription
    , parameters : List ExposedFunctionParameterDescription
    }


type alias ExposedFunctionReturnTypeDescription =
    { sourceCodeText : String
    , containsAppStateType : Bool
    }


type alias ExposedFunctionParameterDescription =
    { patternSourceCodeText : String
    , typeSourceCodeText : String
    , typeIsAppStateType : Bool
    }


type alias StateShimConfigJsonConverterConfig =
    { isDecoder : Bool
    , moduleName : List String
    , declarationName : String
    }


type alias StateShimConfigJsonConverter =
    { isDecoder : Bool
    , typeAnnotation : ElmTypeAnnotation
    , dependencies : Dict.Dict ( List String, String ) ElmChoiceTypeStruct
    }


type alias StateShimConfigSupportingType =
    { typeAnnotation : ElmTypeAnnotation
    , dependencies : Dict.Dict ( List String, String ) ElmChoiceTypeStruct
    }


loweredForAppInStateManagementShim :
    SourceDirectories
    -> StateShimConfig
    -> CompileEntryPointConfig
    -> AppFiles
    -> Result (List (LocatedInSourceFiles CompilationError)) AppFiles
loweredForAppInStateManagementShim sourceDirs stateShimConfig config sourceFiles =
    let
        interfaceToHostRootFilePath : List String
        interfaceToHostRootFilePath =
            filePathFromElmModuleName sourceDirs config.interfaceToHostRootModuleName
    in
    case
        supportingTypesModules
            sourceDirs
            stateShimConfig
            config.originalSourceModules
    of
        Err err ->
            Err
                [ mapLocatedInSourceFiles
                    ((++) "Failed to prepare supporting types modules: " >> OtherCompilationError)
                    err
                ]

        Ok supportingTypes ->
            let
                appStateType : StateShimConfigSupportingType
                appStateType =
                    stateShimConfig.appStateType

                jsonConverterDeclarations : Dict.Dict String StateShimConfigJsonConverter
                jsonConverterDeclarations =
                    supportingTypes.jsonConverterDeclarations
                        |> Dict.union stateShimConfig.jsonConverterDeclarations

                supportingJsonConverterFunctionsDependencies : List ( ( List String, String ), ElmChoiceTypeStruct )
                supportingJsonConverterFunctionsDependencies =
                    jsonConverterDeclarations
                        |> Dict.values
                        |> List.concatMap (.dependencies >> Dict.toList)

                jsonConvertedTypesDependencies : List ( ( List String, String ), ElmChoiceTypeStruct )
                jsonConvertedTypesDependencies =
                    List.concat
                        [ Dict.toList appStateType.dependencies
                        , Tuple.second supportingTypes.stateShimRequestType
                        , Tuple.second supportingTypes.stateShimResponseResultType
                        , supportingJsonConverterFunctionsDependencies
                        ]
                        |> Common.listUnique

                typeToGenerateSerializersFor : List ElmTypeAnnotation
                typeToGenerateSerializersFor =
                    appStateType.typeAnnotation
                        :: Tuple.first supportingTypes.stateShimRequestType
                        :: Tuple.first supportingTypes.stateShimResponseResultType
                        :: (jsonConverterDeclarations
                                |> Dict.values
                                |> List.map .typeAnnotation
                           )

                modulesToAdd : List String
                modulesToAdd =
                    List.concat
                        [ modulesToAddForBase64Coding
                        , List.map
                            (\( _, supportingModule ) -> supportingModule.fileText)
                            supportingTypes.modules
                        ]

                ( appFiles, generateSerializersResult ) =
                    sourceFiles
                        |> addModulesFromTextToAppFiles sourceDirs modulesToAdd
                        |> mapAppFilesToSupportJsonConverters
                            { generatedModuleNamePrefix = config.interfaceToHostRootModuleName
                            , sourceDirs = sourceDirs
                            }
                            typeToGenerateSerializersFor
                            jsonConvertedTypesDependencies

                modulesToImport : List (List String)
                modulesToImport =
                    List.concat
                        [ generateSerializersResult.modulesToImport
                        , stateShimConfig.modulesToImport
                        , List.map
                            (\( _, supportingModule ) -> supportingModule.moduleName)
                            supportingTypes.modules
                        ]

                stateShimRequestFunctionsNamesInGeneratedModules : { encodeFunction : { name : String, text : String }, decodeFunction : { name : String, text : String } }
                stateShimRequestFunctionsNamesInGeneratedModules =
                    buildJsonConverterFunctionsForTypeAnnotation (Tuple.first supportingTypes.stateShimRequestType)

                stateShimResponseResultFunctionsNamesInGeneratedModules : { encodeFunction : { name : String, text : String }, decodeFunction : { name : String, text : String } }
                stateShimResponseResultFunctionsNamesInGeneratedModules =
                    buildJsonConverterFunctionsForTypeAnnotation (Tuple.first supportingTypes.stateShimResponseResultType)

                supportingJsonConverterFunctions : Dict.Dict String ( List String, String )
                supportingJsonConverterFunctions =
                    jsonConverterDeclarations
                        |> Dict.map
                            (\_ jsonConverter ->
                                let
                                    jsonConverterFunctionNames =
                                        buildJsonConverterFunctionsForTypeAnnotation jsonConverter.typeAnnotation

                                    getEncodeOrDecode =
                                        if jsonConverter.isDecoder then
                                            .decodeFunction

                                        else
                                            .encodeFunction
                                in
                                ( generateSerializersResult.generatedModuleName
                                , jsonConverterFunctionNames |> getEncodeOrDecode |> .name
                                )
                            )

                appRootDeclarationModuleName : String
                appRootDeclarationModuleName =
                    config.compilationRootModule.parsedSyntax.moduleDefinition
                        |> Elm.Syntax.Node.value
                        |> Elm.Syntax.Module.moduleName
                        |> String.join "."

                exposedFunctionsListSyntax : String
                exposedFunctionsListSyntax =
                    stateShimConfig.exposedFunctions
                        |> Dict.toList
                        |> List.map composeExposedFunctionListEntrySyntax
                        |> String.join "\n,"

                exposedFunctionsRootModuleSupportingFunction : String
                exposedFunctionsRootModuleSupportingFunction =
                    [ "config_exposedFunctions ="
                    , [ "[" ++ exposedFunctionsListSyntax
                      , "]"
                      , "|> Dict.fromList"
                      ]
                        |> String.join "\n"
                        |> indentElmCodeLines 1
                    ]
                        |> String.join "\n"

                rootElmModuleText : String
                rootElmModuleText =
                    composeRootElmModuleTextWithStateShim
                        { interfaceToHostRootModuleName = String.join "." config.interfaceToHostRootModuleName
                        , appRootDeclarationModuleName = appRootDeclarationModuleName
                        , appStateTypeAnnotation = appStateType.typeAnnotation
                        , modulesToImport = modulesToImport
                        , supportingJsonConverterFunctions = supportingJsonConverterFunctions
                        , otherSupportingFunctions =
                            exposedFunctionsRootModuleSupportingFunction
                                :: stateShimConfig.rootModuleSupportingFunctions
                        , appStateWithPlatformShimTypeAnnotationFromAppStateAnnotation =
                            stateShimConfig.appStateWithPlatformShimTypeAnnotationFromAppStateAnnotation
                        }
            in
            Ok
                (appFiles
                    |> updateFileContentAtPath
                        (always (fileContentFromString rootElmModuleText))
                        interfaceToHostRootFilePath
                )


composeExposedFunctionListEntrySyntax : ( String, ExposedFunctionConfig ) -> String
composeExposedFunctionListEntrySyntax ( functionName, functionConfig ) =
    let
        syntaxFromBool : Bool -> String
        syntaxFromBool bool =
            if bool then
                "True"

            else
                "False"

        parametersTexts : List String
        parametersTexts =
            functionConfig.description.parameters
                |> List.map
                    (\parameterDescription ->
                        "{"
                            ++ ([ ( "patternSourceCodeText"
                                  , "\"" ++ parameterDescription.patternSourceCodeText ++ "\""
                                  )
                                , ( "typeSourceCodeText"
                                  , "\"" ++ parameterDescription.typeSourceCodeText ++ "\""
                                  )
                                , ( "typeIsAppStateType"
                                  , if parameterDescription.typeIsAppStateType then
                                        "True"

                                    else
                                        "False"
                                  )
                                ]
                                    |> List.map (\( key, value ) -> key ++ " = " ++ value)
                                    |> String.join ", "
                               )
                            ++ "}"
                    )
    in
    [ "(\"" ++ functionName ++ "\""
    , ", { description = { "
        ++ " returnType = { sourceCodeText = \""
        ++ functionConfig.description.returnType.sourceCodeText
        ++ "\", containsAppStateType = "
        ++ syntaxFromBool functionConfig.description.returnType.containsAppStateType
        ++ " }"
        ++ ", parameters = [ "
        ++ String.join ", " parametersTexts
        ++ " ]"
        ++ " }"
    , "  , handler ="
    , indentElmCodeLines 1 functionConfig.handlerExpression
    , "  }"
    , ")"
    ]
        |> String.join "\n"


supportingTypesModules :
    SourceDirectories
    -> StateShimConfig
    -> List ( List String, SourceParsedElmModule )
    ->
        Result
            (LocatedInSourceFiles String)
            { modules : List ( List String, SourceParsedElmModule )
            , stateShimRequestType : ( ElmTypeAnnotation, List ( ( List String, String ), ElmChoiceTypeStruct ) )
            , stateShimResponseResultType : ( ElmTypeAnnotation, List ( ( List String, String ), ElmChoiceTypeStruct ) )
            , jsonConverterDeclarations : Dict.Dict String StateShimConfigJsonConverter
            }
supportingTypesModules sourceDirs stateShimConfig originalSourceModules =
    List.concat
        [ [ stateShimTypesModuleText
          , stateShimModuleText
          ]
        , stateShimConfig.supportingModules
        ]
        |> CompileElmApp.elmModulesDictFromModuleTexts (CompileElmApp.filePathFromElmModuleName sourceDirs)
        |> Result.mapError
            (LocatedInSourceFiles
                { filePath = []
                , locationInModuleText = Elm.Syntax.Range.emptyRange
                }
            )
        |> Result.andThen
            (\typesModules ->
                let
                    moduleFromName moduleName =
                        typesModules
                            |> List.filter (Tuple.second >> .moduleName >> (==) moduleName)
                            |> List.head
                in
                case moduleFromName [ "Backend", "Generated", "StateShimTypes" ] of
                    Nothing ->
                        Err
                            (LocatedInSourceFiles
                                { filePath = []
                                , locationInModuleText = Elm.Syntax.Range.emptyRange
                                }
                                "Did not find state shim types module"
                            )

                    Just ( stateShimTypesModuleFilePath, stateShimTypesModule ) ->
                        let
                            syntaxNodeFromEmptyRange =
                                Elm.Syntax.Node.Node Elm.Syntax.Range.emptyRange

                            fakeTypeAnnotationFromLocalName localName =
                                Elm.Syntax.TypeAnnotation.Typed
                                    (syntaxNodeFromEmptyRange ( [], localName ))
                                    []

                            stateShimRequestFakeTypeAnnotation : Elm.Syntax.TypeAnnotation.TypeAnnotation
                            stateShimRequestFakeTypeAnnotation =
                                fakeTypeAnnotationFromLocalName "StateShimRequest"

                            stateShimResponseResultFakeTypeAnnotation : Elm.Syntax.TypeAnnotation.TypeAnnotation
                            stateShimResponseResultFakeTypeAnnotation =
                                fakeTypeAnnotationFromLocalName "ResponseOverSerialInterface"

                            mergedModules : List ( List String, SourceParsedElmModule )
                            mergedModules =
                                List.foldl
                                    (\( moduleName, typeModule ) aggregate ->
                                        Common.assocListInsert moduleName typeModule aggregate
                                    )
                                    originalSourceModules
                                    typesModules

                            fromStateShimConfigJsonConverterConfig :
                                StateShimConfigJsonConverterConfig
                                -> Result (LocatedInSourceFiles String) StateShimConfigJsonConverter
                            fromStateShimConfigJsonConverterConfig converterConfig =
                                case moduleFromName converterConfig.moduleName of
                                    Nothing ->
                                        Err
                                            (LocatedInSourceFiles
                                                { filePath = [], locationInModuleText = Elm.Syntax.Range.emptyRange }
                                                ("Did not find module " ++ String.join "." converterConfig.moduleName)
                                            )

                                    Just ( converterTypeModuleFilePath, converterTypeModule ) ->
                                        CompileElmApp.parseElmTypeAndDependenciesRecursivelyFromAnnotation
                                            mergedModules
                                            ( ( converterTypeModuleFilePath, converterTypeModule.parsedSyntax )
                                            , syntaxNodeFromEmptyRange
                                                (fakeTypeAnnotationFromLocalName converterConfig.declarationName)
                                            )
                                            |> Result.map
                                                (\( typeAnnotation, dependencies ) ->
                                                    { isDecoder = converterConfig.isDecoder
                                                    , typeAnnotation = typeAnnotation
                                                    , dependencies = Dict.fromList dependencies
                                                    }
                                                )

                            jsonConverterDeclarationsResults : Result (LocatedInSourceFiles String) (List ( String, StateShimConfigJsonConverter ))
                            jsonConverterDeclarationsResults =
                                stateShimConfig.jsonConverterDeclarationsConfigs
                                    |> Common.resultListMapCombine
                                        (\( declarationName, converterConfig ) ->
                                            case fromStateShimConfigJsonConverterConfig converterConfig of
                                                Err err ->
                                                    Err err

                                                Ok converter ->
                                                    Ok ( declarationName, converter )
                                        )
                        in
                        CompileElmApp.parseElmTypeAndDependenciesRecursivelyFromAnnotation
                            mergedModules
                            ( ( stateShimTypesModuleFilePath, stateShimTypesModule.parsedSyntax )
                            , syntaxNodeFromEmptyRange stateShimRequestFakeTypeAnnotation
                            )
                            |> Result.andThen
                                (\stateShimRequestType ->
                                    CompileElmApp.parseElmTypeAndDependenciesRecursivelyFromAnnotation
                                        mergedModules
                                        ( ( stateShimTypesModuleFilePath, stateShimTypesModule.parsedSyntax )
                                        , syntaxNodeFromEmptyRange stateShimResponseResultFakeTypeAnnotation
                                        )
                                        |> Result.andThen
                                            (\stateShimResponseResultType ->
                                                jsonConverterDeclarationsResults
                                                    |> Result.map
                                                        (\jsonConverterDeclarations ->
                                                            { modules = typesModules
                                                            , stateShimRequestType = stateShimRequestType
                                                            , stateShimResponseResultType = stateShimResponseResultType
                                                            , jsonConverterDeclarations = Dict.fromList jsonConverterDeclarations
                                                            }
                                                        )
                                            )
                                )
            )


composeRootElmModuleTextWithStateShim : RootModuleConfig -> String
composeRootElmModuleTextWithStateShim config =
    let
        supportingJsonConverterFunctionsAliases : List ( String, ( List String, String ) )
        supportingJsonConverterFunctionsAliases =
            Dict.toList config.supportingJsonConverterFunctions

        functionAliases : List ( String, ( List String, String ) )
        functionAliases =
            supportingJsonConverterFunctionsAliases

        supportingFunctionsText : String
        supportingFunctionsText =
            (functionAliases
                |> List.map
                    (\( localDeclarationName, ( remoteModuleName, remoteDeclarationName ) ) ->
                        localDeclarationName
                            ++ " =\n    "
                            ++ String.join "." (remoteModuleName ++ [ remoteDeclarationName ])
                    )
            )
                ++ config.otherSupportingFunctions
                |> String.join "\n\n\n"

        importsText : String
        importsText =
            config.modulesToImport
                |> Set.fromList
                |> Set.toList
                |> List.map (Tuple.pair >> (|>) Nothing >> importSyntaxTextFromModuleNameAndAlias)
                |> String.join "\n"

        appStateWithPlatformShim : String
        appStateWithPlatformShim =
            config.appStateWithPlatformShimTypeAnnotationFromAppStateAnnotation "AppState"
    in
    "module "
        ++ config.interfaceToHostRootModuleName
        ++ """ exposing (..)

import """
        ++ config.appRootDeclarationModuleName
        ++ """
"""
        ++ importsText
        ++ """
import Platform
import Backend.Generated.StateShim exposing (StateShimConfig, StateShimState)


type alias AppState =
    ("""
        ++ buildTypeAnnotationText config.appStateTypeAnnotation
        ++ """)


type alias AppStateWithPlatformShim =
    """
        ++ appStateWithPlatformShim
        ++ """


type alias State =
    StateShimState AppStateWithPlatformShim


"""
        ++ supportingFunctionsText


stateShimModuleText : String
stateShimModuleText =
    String.trimLeft """
module Backend.Generated.StateShim exposing (..)

import Backend.Generated.StateShimTypes exposing (..)
import Dict
import Json.Decode
import Json.Encode


type alias StateShimConfig appState appStateLessShim =
    { exposedFunctions : Dict.Dict String (ExposedFunctionRecord appState)
    , jsonEncodeAppState : appStateLessShim -> Json.Encode.Value
    , jsonDecodeAppState : Json.Decode.Decoder appStateLessShim
    , initAppShimState : appStateLessShim -> appState
    , appStateLessShim : appState -> appStateLessShim
    }


type alias StateShimState appState =
    { branches : Dict.Dict String appState }


type alias ExposedFunctionHandler appState =
    ApplyFunctionArguments (Maybe appState) -> Result String ( Maybe appState, Maybe Json.Encode.Value )


type alias ExposedFunctionRecord appState =
    { description : ExposedFunctionDescription
    , handler : ExposedFunctionHandler appState
    }


init : StateShimState appState
init =
    { branches = Dict.empty }


processEvent :
    StateShimConfig appState appStateLessShim
    -> StateShimRequest
    -> StateShimState appState
    -> ( StateShimState appState, StateShimResponse )
processEvent config hostEvent stateBefore =
    case hostEvent of
        ListExposedFunctionsShimRequest ->
            ( stateBefore
            , config.exposedFunctions
                |> Dict.toList
                |> List.map (Tuple.mapSecond .description)
                |> List.map
                    (\\( functionName, functionDescription ) ->
                        { functionName = functionName, functionDescription = functionDescription }
                    )
                |> ListExposedFunctionsShimResponse
            )


exposedFunctionExpectingSingleArgument :
    Json.Decode.Decoder arg
    -> (arg -> Result String ( Maybe appState, Maybe Json.Encode.Value ))
    -> ExposedFunctionHandler appState
exposedFunctionExpectingSingleArgument argumentDecoder funcAfterDecode genericArguments =
    case genericArguments.serializedArgumentsJson of
        [ singleArgumentJson ] ->
            case Json.Decode.decodeValue argumentDecoder singleArgumentJson of
                Err err ->
                    Err ("Failed to JSON decode argument: " ++ Json.Decode.errorToString err)

                Ok argument ->
                    funcAfterDecode argument

        serializedArgumentsJson ->
            Err
                ("Unexpected number of arguments: "
                    ++ String.fromInt (List.length serializedArgumentsJson)
                    ++ " instead of 1"
                )


exposedFunctionExpectingSingleArgumentAndAppState :
    Json.Decode.Decoder arg
    -> (arg -> appState -> Result String ( Maybe appState, Maybe Json.Encode.Value ))
    -> ExposedFunctionHandler appState
exposedFunctionExpectingSingleArgumentAndAppState argumentDecoder funcAfterDecode genericArguments =
    case genericArguments.stateArgument of
        Nothing ->
            Err "Type mismatch: Missing state argument"

        Just appState ->
            case genericArguments.serializedArgumentsJson of
                [ singleArgumentJson ] ->
                    case Json.Decode.decodeValue argumentDecoder singleArgumentJson of
                        Err err ->
                            Err ("Failed to JSON decode argument: " ++ Json.Decode.errorToString err)

                        Ok argument ->
                            funcAfterDecode argument appState

                serializedArgumentsJson ->
                    Err
                        ("Unexpected number of arguments: "
                            ++ String.fromInt (List.length serializedArgumentsJson)
                            ++ " instead of 1"
                        )

"""


stateShimTypesModuleText : String
stateShimTypesModuleText =
    String.trimLeft """
module Backend.Generated.StateShimTypes exposing (..)

import Json.Encode


type alias ResponseOverSerialInterface =
    Result String StateShimResponse


type StateShimRequest
    = ListExposedFunctionsShimRequest


type StateShimResponse
    = ListExposedFunctionsShimResponse (List { functionName : String, functionDescription : ExposedFunctionDescription })


type alias ApplyFunctionArguments state =
    { stateArgument : state
    , serializedArgumentsJson : List Json.Encode.Value
    }


type alias ExposedFunctionDescription =
    { returnType : ExposedFunctionReturnTypeDescription
    , parameters : List ExposedFunctionParameterDescription
    }


type alias ExposedFunctionReturnTypeDescription =
    { sourceCodeText : String
    , containsAppStateType : Bool
    }


type alias ExposedFunctionParameterDescription =
    { patternSourceCodeText : String
    , typeSourceCodeText : String
    , typeIsAppStateType : Bool
    }


type alias FunctionApplicationResult =
    { resultLessStateJson : Maybe Json.Encode.Value
    , producedStateDifferentFromStateArgument : Bool
    }

"""
