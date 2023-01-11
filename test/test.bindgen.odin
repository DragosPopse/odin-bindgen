package test

import dynlib "core:dynlib"
import "core:c"
import "core:fmt"

first_proc: proc "odin" (a: c.int, b: c.int)

another_proc: proc "c" (a: c.int, b: c.int) -> (bg_res0: c.bool)

load_bindings :: proc(lib: dynlib.Library) -> bool {
    first_proc = type_of(first_proc)dynlib.symbol_address(lib, "first_proc") or_return
    another_proc = type_of(another_proc)dynlib.symbol_address(lib, "prefixed_another_proc") or_return
    return true
}
