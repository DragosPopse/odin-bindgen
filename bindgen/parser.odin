package mani_generator

import fmt "core:fmt"
import os "core:os"
import ast "core:odin/ast"
import parser "core:odin/parser"
import tokenizer "core:odin/tokenizer"
import strings "core:strings"
import filepath "core:path/filepath"
import "core:log"
import "core:reflect"
import "core:strconv"



String :: string
Identifier :: distinct String
Int :: i64 
Float :: f64 

AttribVal :: union {
    // nil: empty attribute, like a flag, array element, etc
    String,
    Identifier,
    Int,
    Attributes,
}

Attributes :: distinct map[string]AttribVal



NodeExport :: struct {
    attribs: Attributes,
}

Field :: struct {
    name, type: string,
}

ProcedureExport :: struct {
    using base: NodeExport,
    name: string,
    type: string,
    calling_convention: string,
    params: #soa [dynamic]Field,
    results: #soa [dynamic]Field,
}

ForeignExport :: struct {
    using base: NodeExport,
    procs: [dynamic]ProcedureExport,
}

SymbolExport :: union {
    ForeignExport,
}

FileImport :: struct {
    name: string,
    text: string,
}

FileExports :: struct {
    symbols_package: string,
    relpath: string,
    symbols: [dynamic]SymbolExport,
    imports: map[string]FileImport,
}

file_exports_make :: proc(allocator := context.allocator) -> FileExports {
    result := FileExports{}
    result.symbols = make([dynamic]SymbolExport, allocator)
    result.imports = make(map[string]FileImport, 128, allocator)
    return result
}

file_exports_destroy :: proc(obj: ^FileExports) {
    // Note(Dragos): Taken from string builder, shouldn't it be reversed?
    delete(obj.symbols)
    clear(&obj.symbols)
    
}

parse_symbols :: proc(fileName: string) -> (symbol_exports: FileExports) {
    data, ok := os.read_entire_file(fileName);
    if !ok {
        fmt.fprintf(os.stderr, "Error reading the file\n")
    }

    p := parser.Parser{}
    p.flags += {parser.Flag.Optional_Semicolons}
    p.err = proc(pos: tokenizer.Pos, format: string, args: ..any) {
        fmt.printf(format, args)
        fmt.printf("\n")
    }
     

    f := ast.File{
        src = string(data),
        fullpath = fileName,
    }
    
    ok = parser.parse_file(&p, &f)

    
    if p.error_count > 0 {
        return
    }

    root := p.file

    
    
    // Note(Dragos): memory leaks around everywhere
    symbol_exports = file_exports_make()
    abspath, succ := filepath.abs(".")
    err: filepath.Relative_Error
    symbol_exports.relpath, err = filepath.rel(abspath, fileName)
    symbol_exports.relpath, _ = filepath.to_slash(symbol_exports.relpath)
    symbol_exports.symbols_package = root.pkg_name
    
    for x, index in root.decls {
        #partial switch x in x.derived {
            case ^ast.Foreign_Block_Decl: {
                //if len(x.attributes) == 0 do continue 
                foreignBlock, err := parse_foreign_block(root, x)
                if err == .Export {
                    append(&symbol_exports.symbols, foreignBlock)
                }
            }

            case ^ast.Import_Decl: {
                importName: string
                importText := root.src[x.pos.offset : x.end.offset]
                if x.name.kind != .Invalid {
                    // got a name
                    importName = x.name.text
                } else {
                    // Take the name from the path
                    startPos := 0
                    for c, i in x.fullpath {
                        if c == ':' {
                            startPos = i + 1
                            break
                        }
                    }
                    // Note(Dragos): Even more memory leaks I don't care
                    split := strings.split(x.fullpath[startPos:], "/")
                    importName = split[len(split) - 1]
                    importName = strings.trim(importName, "\"")
                    if importName not_in symbol_exports.imports {
                        symbol_exports.imports[importName] = FileImport {
                            name = importName,
                            text = importText,
                        }
                    }
                   
                }     
            }
        }
    }

    return
}



AttribErr :: enum {
    Skip,
    Export,
    Error,
}


get_attr_name :: proc(root: ^ast.File, elem: ^ast.Expr) -> (name: string) {
    #partial switch x in elem.derived  {
        case ^ast.Field_Value: {
            attr := x.field.derived.(^ast.Ident)
            name = attr.name
        }

        case ^ast.Ident: {
            name = x.name
        }
    }
    return
}

parse_attributes_value :: proc(root: ^ast.File, value_decl: ^ast.Value_Decl) -> (result: Attributes) {
    result = make(Attributes)
    for attr, i in value_decl.attributes {
        for x, j in attr.elems { 
            name := get_attr_name(root, x)
            
            result[name] = parse_attrib_val(root, x)
        }
        
    }
    return
}

parse_attributes_foreign :: proc(root: ^ast.File, foreign_decl: ^ast.Foreign_Block_Decl) -> (result: Attributes) {
    result = make(Attributes)
    for attr, i in foreign_decl.attributes {
        for x, j in attr.elems { 
            name := get_attr_name(root, x)
            
            result[name] = parse_attrib_val(root, x)
        }
        
    }
    return
}

parse_attributes :: proc {
    parse_attributes_value,
    parse_attributes_foreign,
}

parse_attrib_object :: proc(root: ^ast.File, obj: ^ast.Comp_Lit) -> (result: Attributes) {
    result = make(Attributes)
    for elem, i in obj.elems {
        name := get_attr_name(root, elem)
        result[name] = parse_attrib_val(root, elem)
    }
    return
}

parse_attrib_val :: proc(root: ^ast.File, elem: ^ast.Expr) -> (result: AttribVal) {
    #partial switch x in elem.derived  {
        case ^ast.Field_Value: {
            #partial switch v in x.value.derived {
                case ^ast.Basic_Lit: {
                    result = strings.trim(v.tok.text, "\"")
                    return
                }

                case ^ast.Ident: {
                    value := root.src[v.pos.offset : v.end.offset]
                    result = cast(Identifier)value
                }

                case ^ast.Comp_Lit: {
                    result = parse_attrib_object(root, v)
                }
            }
            return
        }

        case ^ast.Ident: {
            //result = cast(Identifier)x.name
            //fmt.printf("We shouldn't be an identifier %s\n", x.name)
            return nil
        }

        case ^ast.Comp_Lit: {
            //result = parse_attrib_object(root, x)
            fmt.printf("We shouldn't be in comp literal %v\n", x)
            return
        }
    }
    return nil
}

parse_foreign_block :: proc(root: ^ast.File, foreign_block_decl: ^ast.Foreign_Block_Decl, allocator := context.allocator) -> (result: ForeignExport, err: AttribErr) {
    result.attribs = parse_attributes(root, foreign_block_decl)


    block := foreign_block_decl.body.derived.(^ast.Block_Stmt)
    
    for stmt in block.stmts {
        decl := stmt.derived.(^ast.Value_Decl)
        #partial switch x in decl.values[0].derived {
            case ^ast.Proc_Lit: {
                procExport, _ := parse_proc(root, decl, x)
                append(&result.procs, procExport)
            }
        }
    }

    
    
    return result, .Export
}

parse_proc :: proc(root: ^ast.File, value_decl: ^ast.Value_Decl, proc_lit: ^ast.Proc_Lit, allocator := context.allocator) -> (result: ProcedureExport, err: AttribErr) {
 
    //result.properties, err = parse_properties(root, value_decl)
    result.attribs = parse_attributes(root, value_decl)
  
    v := proc_lit
    procType := v.type
    declName := value_decl.names[0].derived.(^ast.Ident).name // Note(Dragos): Does this work with 'a, b: int' ?????

    result.name = declName
    result.type = root.src[procType.pos.offset : procType.end.offset]
    switch conv in procType.calling_convention {
        case string: {
            result.calling_convention = strings.trim(conv, `"`)
        }

        case ast.Proc_Calling_Convention_Extra: {
            result.calling_convention = "c" //not fully correct
        }

        case: { // nil, default calling convention
            result.calling_convention = "" // Note(Dragos): This could be "" to make it easier to work with default_calling_convention
        }
    }
    // Note(Dragos): these should be checked for 0
    result.params = make_soa(type_of(result.params))
    result.results = make_soa(type_of(result.results))
    // Get parameters
    if procType.params != nil {
        
        for param, i in procType.params.list {
            paramType: string
            #partial switch x in param.type.derived {
                case ^ast.Ident: {
                    paramType = x.name
                }
                case ^ast.Selector_Expr: {
                    paramType = root.src[x.pos.offset : x.end.offset] //godlike odin
                }
                case ^ast.Pointer_Type: {
                    paramType = root.src[x.pos.offset : x.end.offset]
                }
            }

            for name in param.names {
                append_soa(&result.params, Field{
                    name = name.derived.(^ast.Ident).name, 
                    type = paramType,
                })
            }         
        }
    }
    
    // Get results
    if procType.results != nil {
        for rval, i in procType.results.list {
            resName: string
            resType: string
            #partial switch x in rval.type.derived {
                case ^ast.Ident: {
                    resType = x.name
                    if len(rval.names) != 0 {
                        resName = rval.names[0].derived.(^ast.Ident).name
                    }
                }
                case ^ast.Selector_Expr: {
                    if len(rval.names) != 0 {
                        resName = rval.names[0].derived.(^ast.Ident).name
                    }
                    resType = root.src[x.pos.offset : x.end.offset] //godlike odin
                }
            }
            if len(rval.names) == 0 || resName == resType {
                // Result name is not specified
                sb := strings.builder_make(context.temp_allocator)
                strings.write_string(&sb, "bg_res")
                strings.write_int(&sb, i)
                resName = strings.to_string(sb)
            }
            
    

            append_soa(&result.results, Field{
                name = resName, 
                type = resType,
            })
        }
    }

    
    return result, .Export
}


get_attr_elem :: proc(root: ^ast.File, elem: ^ast.Expr) -> (name: string, value: string) { // value can be a map maybe
    #partial switch x in elem.derived  {
        case ^ast.Field_Value: {
            attr := x.field.derived.(^ast.Ident)
            
            #partial switch v in x.value.derived {
                case ^ast.Basic_Lit: {
                    value = strings.trim(v.tok.text, "\"")
                }

                case ^ast.Ident: {
                    value = root.src[v.pos.offset : v.end.offset]
                }

                case ^ast.Comp_Lit: {
                    
                }
            }
            name = attr.name
        }

        case ^ast.Ident: {
            name = x.name
        }
    }
    return
}

is_pointer_type  :: #force_inline proc(token: string) -> bool {
    return token[0] == '^'
}


