{- For documentation of the compilation interface, see <https://github.com/pine-vm/pine/blob/main/guide/customizing-elm-app-builds-with-compilation-interfaces.md#compilationinterfacesourcefiles-elm-module> -}


module CompilationInterface.SourceFiles exposing (..)


type FileTreeNode blobStructure
    = BlobNode blobStructure
    | TreeNode (List ( String, FileTreeNode blobStructure ))


file_tree____static : FileTreeNode { base64 : String }
file_tree____static =
    TreeNode []


file____src_Backend_VolatileProcess_csx : { utf8 : String }
file____src_Backend_VolatileProcess_csx =
    { utf8 = "The compiler replaces this declaration." }


file_tree____elm_core_modules_implicit_import : FileTreeNode { utf8 : String }
file_tree____elm_core_modules_implicit_import =
    BlobNode { utf8 = "The compiler replaces this declaration." }


file_tree____elm_core_modules_explicit_import : FileTreeNode { utf8 : String }
file_tree____elm_core_modules_explicit_import =
    BlobNode { utf8 = "The compiler replaces this declaration." }


file_tree____elm_kernel_modules_json_src : FileTreeNode { utf8 : String }
file_tree____elm_kernel_modules_json_src =
    BlobNode { utf8 = "The compiler replaces this declaration." }


file_tree____elm_kernel_modules_http_src : FileTreeNode { utf8 : String }
file_tree____elm_kernel_modules_http_src =
    BlobNode { utf8 = "The compiler replaces this declaration." }


file_tree____elm_kernel_modules_time_src : FileTreeNode { utf8 : String }
file_tree____elm_kernel_modules_time_src =
    BlobNode { utf8 = "The compiler replaces this declaration." }


file_tree____elm_kernel_modules_html_src : FileTreeNode { utf8 : String }
file_tree____elm_kernel_modules_html_src =
    BlobNode { utf8 = "The compiler replaces this declaration." }


file_tree____elm_kernel_modules_browser_src : FileTreeNode { utf8 : String }
file_tree____elm_kernel_modules_browser_src =
    BlobNode { utf8 = "The compiler replaces this declaration." }
