package lat.odai.ruta

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Actualizar la app desde la misma app: Flutter descarga el APK y aquí se abre el instalador de Android. */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lat.odai.ruta/actualizar").setMethodCallHandler { llamada, resultado ->
            when (llamada.method) {
                "carpeta" -> {
                    val carpeta = File(cacheDir, "actualizacion")
                    carpeta.mkdirs()
                    resultado.success(carpeta.absolutePath)
                }
                "instalar" -> {
                    val ruta = llamada.argument<String>("ruta")
                    if (ruta == null) {
                        resultado.error("datos", "Falta el archivo", null)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                        // Android pide permitir "instalar apps de esta fuente" una sola vez.
                        startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                        resultado.success("permiso")
                    } else {
                        val uri = FileProvider.getUriForFile(this, "$packageName.actualizacion", File(ruta))
                        val intento = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intento)
                        resultado.success("ok")
                    }
                }
                else -> resultado.notImplemented()
            }
        }
    }
}
