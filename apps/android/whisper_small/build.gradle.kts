plugins {
    id("com.android.ai-pack")
}

aiPack {
    packName.set("whisper_small")
    dynamicDelivery {
        deliveryType.set("install-time")
    }
}

val provisionBundledWhisperSmall by tasks.registering(Exec::class) {
    group = "build setup"
    description = "Downloads and verifies the pinned Whisper Small files packaged with Android releases."
    val provisioner = rootProject.file("scripts/provision-bundled-whisper-small.py")
    val modelDirectory = file("src/main/assets/speech-models/ggml-small")
    inputs.file(provisioner)
    outputs.dir(modelDirectory)
    commandLine("python3", provisioner, "--output", modelDirectory)
}

tasks.configureEach {
    if (name.startsWith("generate") || name.startsWith("merge") || name.startsWith("package")) {
        dependsOn(provisionBundledWhisperSmall)
    }
}
