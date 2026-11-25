#!/bin/zsh
# The callers own BUILD_DIR. The source roots match the synchronized Xcode targets.
harness_build_module() {
    local module="$1"
    shift
    swiftc -D NEOBILI_REGRESSION -swift-version 6 -parse-as-library -enable-testing \
        -module-cache-path "$BUILD_DIR/module-cache" -I "$BUILD_DIR" \
        -whole-module-optimization -emit-library -static -emit-module -module-name "$module" \
        -emit-module-path "$BUILD_DIR/$module.swiftmodule" -o "$BUILD_DIR/lib$module.a" "$@"
}

harness_build_modules() {
    harness_build_module NeoBiliDomain "$@" "$APP"/Domain/**/*.swift
    harness_build_module NeoBiliCore "$@" "$APP"/Core/Caching/**/*.swift "$APP"/Core/Formatting/**/*.swift
    harness_build_module NeoBiliData "$@" "$APP"/Data/**/*.swift
}

harness_compile() {
    swiftc -D NEOBILI_REGRESSION -swift-version 6 -parse-as-library \
        -module-cache-path "$BUILD_DIR/module-cache" -I "$BUILD_DIR" -L "$BUILD_DIR" \
        "$@" -lNeoBiliData -lNeoBiliCore -lNeoBiliDomain
}
