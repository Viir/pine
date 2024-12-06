module CompilationInterface.SourceFiles exposing (..)

{-| For documentation of the compilation interface, see <https://github.com/pine-vm/pine/blob/main/guide/how-to-use-elm-compilation-interfaces.md#compilationinterfacesourcefiles-elm-module>
-}


type alias Base64AndUtf8 =
    { utf8 : String, base64 : String }


file____a_file_txt : { utf8 : String }
file____a_file_txt =
    { utf8 = "The compiler replaces this value."
    }


file____directory_file_alpha_txt : Base64AndUtf8
file____directory_file_alpha_txt =
    { utf8 = "The compiler replaces this value."
    , base64 = "The compiler replaces this value."
    }
