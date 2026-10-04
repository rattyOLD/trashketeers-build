package io.trashketeers.updater;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import androidx.core.content.FileProvider;
import java.io.File;
import java.util.HashSet;
import java.util.Set;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

public final class TrashSquadUpdater extends GodotPlugin {
    public TrashSquadUpdater(Godot godot) { super(godot); }

    @Override public String getPluginName() { return "TrashSquadUpdater"; }

    @Override public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("installer_error", String.class));
        signals.add(new SignalInfo("installer_opened"));
        return signals;
    }

    @UsedByGodot public boolean can_install_packages() {
        Activity activity = getActivity();
        return activity != null && (Build.VERSION.SDK_INT < 26 || activity.getPackageManager().canRequestPackageInstalls());
    }

    @UsedByGodot public boolean request_install_permission() {
        Activity activity = getActivity();
        if (activity == null) return false;
        if (can_install_packages()) return true;
        activity.runOnUiThread(() -> {
            try {
                activity.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + activity.getPackageName())));
            } catch (RuntimeException e) {
                emitSignal("installer_error", "Не удалось открыть разрешение на обновления. Попробуй ещё раз.");
            }
        });
        return true;
    }

    @UsedByGodot public boolean install_apk(String path, int expectedCode) {
        Activity activity = getActivity();
        if (activity == null || !can_install_packages()) return false;
        try {
            File file = new File(path).getCanonicalFile();
            File updates = new File(activity.getFilesDir(), "updates").getCanonicalFile();
            if (!file.getParentFile().equals(updates) || !file.isFile() || !file.getName().endsWith(".apk")) return false;
            PackageManager manager = activity.getPackageManager();
            PackageInfo archive = manager.getPackageArchiveInfo(file.getPath(), 0);
            PackageInfo installed = manager.getPackageInfo(activity.getPackageName(), 0);
            if (archive == null || !activity.getPackageName().equals(archive.packageName)
                    || versionCode(archive) != expectedCode || versionCode(archive) <= versionCode(installed)) return false;
            Uri uri = FileProvider.getUriForFile(activity, activity.getPackageName() + ".updatefiles", file);
            activity.runOnUiThread(() -> {
                try {
                    Intent intent = new Intent(Intent.ACTION_VIEW);
                    intent.setDataAndType(uri, "application/vnd.android.package-archive");
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                    activity.startActivity(intent);
                    emitSignal("installer_opened");
                } catch (RuntimeException e) {
                    emitSignal("installer_error", "Android не открыл установку. Попробуй ещё раз.");
                }
            });
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static long versionCode(PackageInfo info) {
        return Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode;
    }
}
