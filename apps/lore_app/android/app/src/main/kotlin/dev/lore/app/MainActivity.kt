package dev.lore.app

import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var accessController: AndroidLibraryAccessController? = null
    private var storageController: AndroidLibraryStorageController? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        accessController = AndroidLibraryAccessController(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        storageController = AndroidLibraryStorageController(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (accessController?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        accessController?.dispose()
        storageController?.dispose()
        accessController = null
        storageController = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
