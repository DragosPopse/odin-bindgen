package build_system

import "core:fmt"
import "shared:build"
import "core:os"
import "core:strings"

Mode :: enum {
    Deb,
    Rel,
    Fast,
}

Mode_str := [Mode]string {
    .Deb = "deb",
    .Rel = "rel",
    .Fast = "fast",
}

ProjectName :: enum {
    Bindgen,
    Test,
}

Target :: struct {
    name: ProjectName,
    platform: build.Platform,
    mode: Mode,
}
Project :: build.Project(Target)


PLATFORM := build.Platform{ODIN_OS, ODIN_ARCH}


modes := [?]Mode{.Deb, .Rel, .Fast}


add_targets :: proc(project: ^Project) {
    target: Target
    target.platform = PLATFORM

    // Add bindgen targets 
    target.name = .Bindgen
    for mode in modes {
        target.mode = mode
        build.add_target(project, target)
    }
    
    // Add test target
    target.name = .Test
    target.mode = .Deb 
    build.add_target(project, target)
}

configure_target :: proc(project: Project, target: Target) -> (config: build.Config) {
    config = build.config_make()

    osStr := build._os_to_arg[target.platform.os]
    archStr := build._arch_to_arg[target.platform.arch]
    
    
    config.platform = target.platform
    config.collections["shared"] = strings.concatenate({ODIN_ROOT, "shared"})

    exeExt := ".exe" if target.platform.os == .Windows else ""

    exeStr: string
    outFolder: string
    switch target.name {
        case .Bindgen: {
            config.name = Mode_str[target.mode]
            config.src = "bindgen"
            exeStr = "bindgen"
            outFolder = Mode_str[target.mode]
        }

        case .Test: {
            config.name = "test"
            config.src = "test"
            config.flags += {.Ignore_Unknown_Attributes}
            exeStr = "test"
            outFolder = Mode_str[target.mode]
        }
    }

    switch target.mode {
        case .Deb: {
            config.flags += {.Debug}
            config.optimization = .Minimal
        }

        case .Rel: {
            config.optimization = .Speed
        }

        case .Fast: {
            config.optimization = .Speed
            config.flags += {.Disable_Assert, .No_Bounds_Check}
        }
    }

    config.out = fmt.aprintf("out/%s/%s%s", outFolder, exeStr, exeExt)
 
    return
}


main :: proc() {
    project: build.Project(Target)
    project.targets = make([dynamic]Target)
    project.configure_target_proc = configure_target
  
    options := build.build_options_make_from_args(os.args[1:])
    add_targets(&project)
    build.build_project(project, options)
}