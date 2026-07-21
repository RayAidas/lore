allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// 老插件（如 file_picker 8.3.7）硬编码 compileSdk=34，而
// flutter_plugin_android_lifecycle 要求 36，触发 AarMetadata 检查失败；
// 统一把所有 Android 库子工程的 compileSdk 抬到 36。
// 用反射设置，避免根 build 脚本显式依赖 AGP 类型（根脚本 classpath 上没有 AGP）；
// 用 gradle.afterProject（而非 afterEvaluate）是因为本工程 subprojects 里有
// evaluationDependsOn(":app")，会让部分工程在注册 afterEvaluate 时已 evaluated 而报错。
gradle.afterProject {
    val androidExt = extensions.findByName("android") ?: return@afterProject
    try {
        androidExt.javaClass
            .getMethod("setCompileSdk", Integer::class.java)
            .invoke(androidExt, 36)
    } catch (e: ReflectiveOperationException) {
        // 非 Android 扩展、AGP 版本不匹配、或 invoke 失败：跳过但留痕，便于诊断。
        logger.lifecycle("[compileSdk-override] skipped for $name: ${e.message}")
    } catch (e: SecurityException) {
        logger.lifecycle("[compileSdk-override] skipped for $name: ${e.message}")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
