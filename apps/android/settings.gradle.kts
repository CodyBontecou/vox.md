pluginManagement {
    includeBuild("build-logic")
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io") {
            content {
                includeModule("com.github.k2-fsa", "sherpa-onnx")
            }
        }
    }
}

rootProject.name = "vox-android"

include(":app")
include(":core-bridge")
include(":capture-domain")
include(":data")
include(":platform-services")
include(":wear")
include(":whisper_small")
