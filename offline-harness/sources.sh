#!/bin/zsh
# App-target sources shared by the main, network and identity harnesses.
# NeoBiliDomain, NeoBiliCore and NeoBiliData are compiled separately by modules.sh.
harness_app_sources=(
    "$APP/Application/Content/VideoFiltering.swift"
    "$APP/Application/Settings/VideoDurationFilterSettings.swift"
    "$APP/Application/Content/PortraitVideoStore.swift"
    "$APP/Application/Content/SpaceVideo+Presentation.swift"
    "$APP/Application/Settings/RecommendationFilter+Preferences.swift"
    "$APP/Application/Settings/AppLanguage+Preferences.swift"
    "$APP/Core/Extensions/Int+BiliFormatting.swift"
    "$APP/App/NetworkingDefaults.swift"
    "$APP/Core/UI/EnvironmentAction.swift"
    "$APP/Application/Home/HomeViewModel.swift"
    "$APP/Application/Content/LoadFailureDescription.swift"
    "$APP/Core/Extensions/Error+Cancellation.swift"
    "$HARNESS/src/Stubs.swift"
)
