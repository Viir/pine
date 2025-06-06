module CompilationInterface.ElmMake exposing (..)

{-| For documentation of the compilation interface, see <https://github.com/pine-vm/pine/blob/main/guide/customizing-elm-app-builds-with-compilation-interfaces.md#compilationinterfaceelmmake-elm-module>
-}

import Basics


elm_make____src_Frontend_Main_elm : { debug : { javascript : { base64 : String } }, javascript : { base64 : String } }
elm_make____src_Frontend_Main_elm =
    { javascript = { base64 = "The compiler replaces this declaration." }
    , debug = { javascript = { base64 = "The compiler replaces this declaration." } }
    }
