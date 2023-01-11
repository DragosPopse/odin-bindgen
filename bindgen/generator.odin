package mani_generator

import strings "core:strings"
import fmt "core:fmt"
import filepath "core:path/filepath"
import os "core:os"
import json "core:encoding/json"


GeneratorConfig :: struct {
    input_directory: string,
    show_timings: bool,
    files: map[string]PackageFile,
    odin_ext: string,
    proc_name: string,
}


PackageFile :: struct {
    decl_builder: strings.Builder,
    proc_builder: strings.Builder,
    filename: string,
    imports: map[string]FileImport, // Key: import package name; Value: import text
}

package_file_make :: proc(path: string) -> PackageFile {
    return PackageFile {
        decl_builder = strings.builder_make(), 
        proc_builder = strings.builder_make(),
        filename = path,
        imports = make(map[string]FileImport),
    }
}

create_config_from_args :: proc() -> (result: GeneratorConfig) {
    result = GeneratorConfig{}
    foundJsonParam := false
    for arg in os.args[1:] {
        if arg[0] == '-' {
            pair := strings.split(arg, ":", context.temp_allocator)
            switch pair[0] {
                case "-show-timings": {
                    result.show_timings = true
                }
            }
        } else {
            foundJsonParam = true
            config_from_json(&result, arg)
        }
    }

    if !foundJsonParam {
        config_from_json(&result, "bindgen.json")
    }

    return
}

config_from_json :: proc(config: ^GeneratorConfig, file: string) {
    data, ok := os.read_entire_file(file, context.temp_allocator)
    if !ok {
        fmt.printf("Failed to read config file %s\n", file)
        return
    }
    str := strings.clone_from_bytes(data, context.temp_allocator)
    obj, err := json.parse_string(data = str, allocator = context.temp_allocator)
    if err != .None {
        return
    }

    root := obj.(json.Object)
    config.input_directory = strings.clone(root["src"].(json.String))
    config.odin_ext = strings.clone(root["odin_ext"].(json.String) or_else ".bindgen.odin")
    config.proc_name = strings.clone(root["proc_name"].(json.String) or_else "bindgen_load")
}


config_package :: proc(config: ^GeneratorConfig, pkg: string, filename: string) {
    result, ok := &config.files[pkg]
    if !ok {
        using strings

        
        path := filepath.dir(filename, context.temp_allocator)
    
        name := filepath.stem(filename)
        filename := strings.concatenate({path, "/", pkg, config.odin_ext})

        config.files[pkg] = package_file_make(filename)
        sb := &(&config.files[pkg]).decl_builder
        psb := &(&config.files[pkg]).proc_builder
        file := &config.files[pkg]

        file.imports["dynlib"] = FileImport {
            name = "dynlib",
            text = `import dynlib "core:dynlib"`,
        }

        write_string(sb, "package ")
        write_string(sb, pkg)
        write_string(sb, "\n\n")
    
        for _, imp in file.imports {
            write_string(sb, imp.text)
            write_string(sb, "\n")
        }

        fmt.sbprintf(psb, "%s :: proc(lib: dynlib.Library) -> bool {{\n    ", config.proc_name)
    }
}





generate_foreign_export :: proc(config: ^GeneratorConfig, exports: FileExports, f: ForeignExport, filename: string) {
    using strings, fmt
    sb := &(&config.files[exports.symbols_package]).decl_builder
    psb := &(&config.files[exports.symbols_package]).proc_builder
    exportAttribs := f.attribs["Bindgen"]
    defaultConvention := f.attribs["default_calling_convention"].(String) or_else "odin"
    linkPrefix := f.attribs["link_prefix"].(String) or_else ""

    

    write_string(sb, "\n")
    for fn in f.procs {
        write_string(sb, fn.name)
        write_string(sb, ": proc")
        convention: string 
        if len(fn.calling_convention) == 0 { // unspecified calling convention, use default
            convention = defaultConvention
        } else {
            convention = fn.calling_convention
        }
        sbprintf(sb, ` "%s" (`, defaultConvention)

        for param, i in fn.params {
            sbprintf(sb, "%s: %s", param.name, param.type)
            if i != len(fn.params) - 1 do write_string(sb, ", ")
        }
        write_string(sb, ")")

        if len(fn.results) > 0 {
            write_string(sb, " -> (")
            for result, i in fn.results {
                sbprintf(sb, "%s: %s", result.name, result.type)
                if i != len(fn.results) - 1 do write_string(sb, ", ")
            }
            write_string(sb, ")")
        }
        write_string(sb, "\n")

        // Add it to the loading proc 
        sbprintf(psb, "%s = type_of(%s)dynlib.symbol_address(lib, \"%s\") or_return\n    ", fn.name, fn.name, 
            strings.concatenate({linkPrefix, fn.name}, context.temp_allocator) if "link_name" not_in fn.attribs else fn.attribs["link_name"].(String))
    }
    
}


add_import :: proc(file: ^PackageFile, import_statement: FileImport) {
    if import_statement.name not_in file.imports {
        using strings
        sb := &file.decl_builder
        write_string(sb, import_statement.text)
        write_string(sb, "\n")
        file.imports[import_statement.name] = import_statement
    }
}


generate_bindgen_exports :: proc(config: ^GeneratorConfig, exports: FileExports) {
    using strings
    config_package(config, exports.symbols_package, exports.relpath)
    file := &config.files[exports.symbols_package]
    psb := &(file.proc_builder)
    
    for _, imp in exports.imports {
        add_import(file, imp)
    }

    for exp, i in exports.symbols {
        switch x in exp {
            case ForeignExport: {
                if "Bindgen" in x.attribs {
                    generate_foreign_export(config, exports, x, exports.relpath)
                }
            }
        }
    }
}