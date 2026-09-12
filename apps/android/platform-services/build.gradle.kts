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
}
