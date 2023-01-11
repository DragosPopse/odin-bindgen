//+build ignore
package test

import "core:fmt"
import "core:c"

@(Bindgen)
foreign {
    first_proc :: proc(a, b: c.int) ---
}

@(Bindgen)
@(default_calling_convention = "c")
@(link_prefix = "prefixed_")
foreign {
    another_proc :: proc(a, b: c.int) -> c.bool ---
}
