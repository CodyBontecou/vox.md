package md.vox.android

/** Host gate must provision exact-hash assets; these tests fail rather than skip when missing. */
@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.RUNTIME)
annotation class ProvisionedModelTest
