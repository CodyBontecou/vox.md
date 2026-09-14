plugins {
    id("vox.android.library")
    id("vox.android.test")
}

android {
    namespace = "md.vox.android.platformservices"
}

dependencies {
    implementation(project(":capture-domain"))
    implementation(libs.core.ktx)
    implementation(libs.coroutines.android)
    implementation(libs.serialization.json)
    // Phone-only inference runtimes are supplied by :app. Keeping them compile-only here lets
    // Wear reuse recorder/protocol classes without packaging unused ASR and OCR native assets.
    compileOnly(libs.mlkit.text.recognition)
    compileOnly(libs.vosk.android)
    compileOnly(libs.sherpa.onnx)
}
