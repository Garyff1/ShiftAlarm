allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val buildDirectoryOverride = System.getenv("SHIFT_ALARM_BUILD_DIR")
    ?.takeIf { it.isNotBlank() }
val newBuildDir: Directory = if (buildDirectoryOverride == null) {
    rootProject.layout.buildDirectory.dir("../../build").get()
} else {
    rootProject.layout.projectDirectory.dir(buildDirectoryOverride)
}
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
