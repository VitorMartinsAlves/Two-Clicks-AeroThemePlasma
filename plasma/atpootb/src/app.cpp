// SPDX-License-Identifier: GPL-2.0-or-later
// SPDX-FileCopyrightText: 2025 WackyIdeas <wackyideas@disroot.org>

#include "app.h"
#include <KSharedConfig>
#include <KWindowConfig>
#include <QQuickWindow>
#include <KWindowEffects>
#include <KAuth/ExecuteJob>
#include <KUser>
#include <QApplication>
#include <QFont>
#include <QProcess>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <QFile>
#include <QFileInfo>

#include "effectsmodel.h"
#include "rollbackstate.h"

#include <QStandardPaths>


namespace
{
QString userRollbackManifestPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + QStringLiteral("/aerothemeplasma/rollback/user.json");
}

QStringList userRollbackPaths()
{
    const QString config = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
    return {
        config + QStringLiteral("/kdeglobals"),
        config + QStringLiteral("/kwinrc"),
        config + QStringLiteral("/plasmarc"),
        config + QStringLiteral("/kcminputrc"),
        config + QStringLiteral("/kcmfonts"),
        config + QStringLiteral("/ksplashrc"),
        config + QStringLiteral("/kwinrulesrc"),
        config + QStringLiteral("/kscreenlockerrc"),
        config + QStringLiteral("/plasma-org.kde.plasma.desktop-appletsrc"),
        config + QStringLiteral("/aerothemeplasmarc"),
        config + QStringLiteral("/Kvantum/kvantum.kvconfig")
    };
}

bool beginUserRollback()
{
    const bool result = AtpRollback::backupFiles(userRollbackPaths(), userRollbackManifestPath());
    if (!result) {
        qCritical() << "Could not create the AeroThemePlasma user configuration backup.";
    }
    return result;
}

bool captureUserRollback()
{
    const bool result = AtpRollback::captureExpectedState(userRollbackManifestPath());
    if (!result) {
        qWarning() << "Could not update the AeroThemePlasma user rollback snapshot.";
    }
    return result;
}

bool runSystemRollbackAction(const QString &actionName)
{
    KAuth::Action action(actionName);
    action.setHelperId(QStringLiteral("io.gitgud.wackyideas.ootb"));
    const auto job = action.execute();
    if (!job->exec()) {
        qWarning() << "System rollback action failed:" << actionName << job->errorString() << job->errorText();
        return false;
    }
    return true;
}
} // namespace

App::App()
{
    model.load();
    KConfig ootbConfig(QStringLiteral("aerothemeplasmarc"));
    m_firstTime = ootbConfig.group(QStringLiteral("OOTB")).readEntry(QStringLiteral("wizardRun"), false);
    Q_EMIT firstTimeChanged();
}
bool App::firstTime() const
{
    return m_firstTime;
}
void App::setWindowProps(QWindow *handle)
{
    KWindowEffects::enableBlurBehind(handle, true, QRegion(0,0,0,0));
}

void App::syncPlasmaWithSDDM()
{
    // initial check for sddm user; abort if user not present
    // we have to check with QString and isEmpty() instead of QDir and exists() because
    // QDir returns "." and true for exists() in the case of a non-existent user;
    QString sddmHomeDirPath = KUser("sddm").homeDir();
    if (sddmHomeDirPath.isEmpty()) {
        qWarning() << "SDDM user not found";
        return;
    }

    // read Plasma values
    KConfig cursorConfig(QStringLiteral("kcminputrc"));
    KConfigGroup cursorConfigGroup(&cursorConfig, QStringLiteral("Mouse"));
    QString cursorTheme = cursorConfigGroup.readEntry("cursorTheme", QString());
    QString cursorSize = cursorConfigGroup.readEntry("cursorSize", QString());

    KConfig dpiConfig(QStringLiteral("kcmfonts"));
    KConfigGroup dpiConfigGroup(&dpiConfig, QStringLiteral("General"));
    QString dpiValue = dpiConfigGroup.readEntry("forceFontDPI");
    QString dpiArgument = QStringLiteral("-dpi ") + dpiValue;

    KConfig numLockConfig(QStringLiteral("kcminputrc"));
    KConfigGroup numLockConfigGroup(&numLockConfig, QStringLiteral("Keyboard"));
    QString numLock = numLockConfigGroup.readEntry("NumLock");

    // Syncing the font only works with SDDM >= 0.19, but will not have a negative effect with older versions
    KConfig plasmaFontConfig(QStringLiteral("kdeglobals"));
    KConfigGroup plasmaFontGroup(&plasmaFontConfig, QStringLiteral("General"));
    QString plasmaFont = plasmaFontGroup.readEntry("font", QApplication::font().toString());

    // define paths
    const QString fontconfigPath = QStandardPaths::locate(QStandardPaths::GenericConfigLocation, QStringLiteral("fontconfig"), QStandardPaths::LocateDirectory);
    const QString kdeglobalsPath = QStandardPaths::locate(QStandardPaths::GenericConfigLocation, QStringLiteral("kdeglobals"));
    const QString plasmarcPath = QStandardPaths::locate(QStandardPaths::GenericConfigLocation, QStringLiteral("plasmarc"));
    const QString kcminputrcPath = QStandardPaths::locate(QStandardPaths::GenericConfigLocation, QStringLiteral("kcminputrc"));
    const QString kwinoutputconfigPath = QStandardPaths::locate(QStandardPaths::GenericConfigLocation, QStringLiteral("kwinoutputconfig.json"));

    // Preserve SDDM's current settings before the upstream helper synchronizes them.
    if (!runSystemRollbackAction(QStringLiteral("io.gitgud.wackyideas.ootb.backup"))) {
        qWarning() << "Skipping SDDM synchronization because its rollback snapshot could not be created.";
        return;
    }

    // send values and paths to helper, debug if it fails
    QVariantMap args;

    args[QStringLiteral("kde_settings.conf")] = QString{QLatin1String(SDDM_CONFIG_DIR "/") + QStringLiteral("kde_settings.conf")};

    args[QStringLiteral("sddm.conf")] = QLatin1String(SDDM_CONFIG_FILE);

    args[QStringLiteral("kde_settings.conf/General/GreeterEnvironment")] = QStringLiteral("QML_DISABLE_DISTANCEFIELD=1");
    args[QStringLiteral("kde_settings.conf/Theme/Current")] = QStringLiteral("sddm-theme-mod");
    args[QStringLiteral("kde_settings.conf/Theme/CursorTheme")] = QStringLiteral("aero-drop");

    if (!cursorSize.isNull()) {
        args[QStringLiteral("kde_settings.conf/Theme/CursorSize")] = cursorSize;
    } else {
        qDebug() << "Cannot find cursor size value; unsetting it";
        args[QStringLiteral("kde_settings.conf/Theme/CursorSize")] = QVariant();
    }

    if (!dpiValue.isEmpty()) {
        args[QStringLiteral("kde_settings.conf/X11/ServerArguments")] = dpiArgument;
    } else {
        qDebug() << "Cannot find scaling DPI value.";
    }

    if (!numLock.isEmpty()) {
        if (numLock == QStringLiteral("0")) {
            args[QStringLiteral("kde_settings.conf/General/Numlock")] = QStringLiteral("on");
        } else if (numLock == QStringLiteral("1")) {
            args[QStringLiteral("kde_settings.conf/General/Numlock")] = QStringLiteral("off");
        } else if (numLock == QStringLiteral("2")) {
            args[QStringLiteral("kde_settings.conf/General/Numlock")] = QStringLiteral("none");
        }
    } else {
        qDebug() << "Cannot find NumLock value.";
    }

    if (!plasmaFont.isEmpty()) {
        args[QStringLiteral("kde_settings.conf/Theme/Font")] = plasmaFont;
    } else {
        qDebug() << "Cannot find Plasma font value.";
    }

    if (!fontconfigPath.isEmpty()) {
        args[QStringLiteral("fontconfig")] = fontconfigPath;
    } else {
        qDebug() << "Cannot find fontconfig folder.";
    }

    if (!kdeglobalsPath.isEmpty()) {
        args[QStringLiteral("kdeglobals")] = kdeglobalsPath;
    } else {
        qDebug() << "Cannot find kdeglobals file.";
    }

    if (!plasmarcPath.isEmpty()) {
        args[QStringLiteral("plasmarc")] = plasmarcPath;
    } else {
        qDebug() << "Cannot find plasmarc file.";
    }

    if (!kcminputrcPath.isEmpty()) {
        args[QStringLiteral("kcminputrc")] = kcminputrcPath;
    } else {
        qDebug() << "Cannot find kcminputrc file.";
    }

    if (!kwinoutputconfigPath.isEmpty()) {
        args[QStringLiteral("kwinoutputconfig")] = kwinoutputconfigPath;
    } else {
        qDebug() << "Cannot find kwinoutputconfiguration.json file";
    }

    auto path = QStandardPaths::locate(QStandardPaths::GenericDataLocation, QStringLiteral("kscreen/"), QStandardPaths::LocateDirectory);
    if (!path.isEmpty()) {
        args[QStringLiteral("kscreen-config")] = path;
    }
    KAuth::Action syncAction(QStringLiteral("org.kde.kcontrol.kcmsddm.sync"));
    syncAction.setHelperId(QStringLiteral("org.kde.kcontrol.kcmsddm"));
    syncAction.setArguments(args);

    auto job = syncAction.execute();
    if (!job->exec()) {
        qDebug() << "KAuth returned an error code:" << job->error();
        if (!job->errorText().isEmpty()) {
            qWarning() << job->errorString() << job->errorText();
        }
    } else {
        qDebug() << "KAuth succeeded.";
        if (!job->errorText().isEmpty()) {
            qWarning() << job->errorString() << job->errorText();
        }
    }

    // Capture final values even if synchronization failed part-way through.
    runSystemRollbackAction(QStringLiteral("io.gitgud.wackyideas.ootb.capture"));
}

void App::setCursorThemeSDDM()
{
    QVariantMap args;
    KAuth::Action syncAction(QStringLiteral("io.gitgud.wackyideas.ootb.apply"));
    syncAction.setHelperId(QStringLiteral("io.gitgud.wackyideas.ootb"));
    syncAction.setArguments(args);

    auto job = syncAction.execute();
    if (!job->exec()) {
        qDebug() << "KAuth returned an error code:" << job->error();
        if (!job->errorText().isEmpty()) {
            qWarning() << job->errorString() << job->errorText();
        }
    } else {
        qDebug() << "KAuth succeeded.";
        if (!job->errorText().isEmpty()) {
            qWarning() << job->errorString() << job->errorText();
        }
        QString contents = job->data()["contents"].toString();
        qDebug() << "KAuth succeeded. Contents: " << contents;

    }

}

void App::applyLookAndFeel()
{
    if (!beginUserRollback()) {
        return;
    }

    // Font config
    KConfig kdeglobalsConfig(QStringLiteral("kdeglobals"));
    QFont font = QFont(QStringLiteral("Segoe UI"), 9);
    font.setStyleName(QStringLiteral("Regular"));
    QFont fontSmall = QFont(QStringLiteral("Segoe UI"), 8);
    fontSmall.setStyleName(QStringLiteral("Regular"));
    KConfigGroup generalGroup = kdeglobalsConfig.group(QStringLiteral("General"));
    generalGroup.writeEntry(QStringLiteral("font"), font);
    generalGroup.writeEntry(QStringLiteral("smallestReadableFont"), fontSmall);
    generalGroup.writeEntry(QStringLiteral("toolBarFont"), font);
    generalGroup.writeEntry(QStringLiteral("menuFont"), font);
    kdeglobalsConfig.group(QStringLiteral("WM")).writeEntry(QStringLiteral("activeFont"), font);
    kdeglobalsConfig.sync();

    model.updateEffectStatus(model.findByPluginId("smodpeekscript"), EffectsModel::Status::Enabled);
    model.updateEffectStatus(model.findByPluginId("minimizeall"), EffectsModel::Status::Enabled);
    model.updateEffectStatus(model.findByPluginId("aeroglassblur"), EffectsModel::Status::Enabled);
    model.updateEffectStatus(model.findByPluginId("aeroglide"), EffectsModel::Status::Enabled);
    model.updateEffectStatus(model.findByPluginId("smodglow"), EffectsModel::Status::Enabled);
    model.updateEffectStatus(model.findByPluginId("smodpeekeffect"), EffectsModel::Status::Enabled);
    model.updateEffectStatus(model.findByPluginId("libkwin_effect_smodsnap"), EffectsModel::Status::Enabled);
    model.updateEffectStatus(model.findByPluginId("launchfeedback"), EffectsModel::Status::Enabled);
    model.updateEffectStatus(model.findByPluginId("fadingpopupsaero"), EffectsModel::Status::Enabled);
    model.updateEffectStatus(model.findByPluginId("squashaero"), EffectsModel::Status::Enabled);
    model.updateEffectStatus(model.findByPluginId("dimscreenaero"), EffectsModel::Status::Enabled);
    model.updateEffectStatus(model.findByPluginId("aeroshell-thumbnails"), EffectsModel::Status::Enabled);

    model.updateEffectStatus(model.findByPluginId("blur"), EffectsModel::Status::Disabled);
    model.updateEffectStatus(model.findByPluginId("contrast"), EffectsModel::Status::Disabled);
    model.updateEffectStatus(model.findByPluginId("login"), EffectsModel::Status::Disabled);
    model.updateEffectStatus(model.findByPluginId("logout"), EffectsModel::Status::Disabled);
    model.updateEffectStatus(model.findByPluginId("maximize"), EffectsModel::Status::Disabled);
    model.updateEffectStatus(model.findByPluginId("scale"), EffectsModel::Status::Disabled);
    model.updateEffectStatus(model.findByPluginId("squash"), EffectsModel::Status::Disabled);
    model.updateEffectStatus(model.findByPluginId("slide"), EffectsModel::Status::Disabled);
    model.updateEffectStatus(model.findByPluginId("fade"), EffectsModel::Status::Disabled);
    model.updateEffectStatus(model.findByPluginId("slidingpopups"), EffectsModel::Status::Disabled);
    model.updateEffectStatus(model.findByPluginId("dialogparent"), EffectsModel::Status::Disabled);
    model.updateEffectStatus(model.findByPluginId("fadingpopups"), EffectsModel::Status::Disabled);
    model.updateEffectStatus(model.findByPluginId("windowaperture"), EffectsModel::Status::Disabled);
    model.save();

    QDBusMessage kwinDbus = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
                                                           QStringLiteral(""), QStringLiteral("reconfigure"));
    if (!QDBusConnection::sessionBus().send(kwinDbus)) {
        qWarning() << "DBus KWin reconfigure request failed; continuing the remaining look-and-feel steps.";
    }

    // Run synchronously so the rollback snapshot records the completed state.
    qInfo() << "plasma-apply-lookandfeel exit code:"
            << QProcess::execute("plasma-apply-lookandfeel", { "-a", "authui7" });
    qInfo() << "kvantummanager exit code:"
            << QProcess::execute("kvantummanager", { "--set", "Windows7Aero" });
    qInfo() << "plasma-apply-cursortheme exit code:"
            << QProcess::execute("plasma-apply-cursortheme", { "aero-drop", "--size", "32" });
    qInfo() << "aeroshell_update_default_rules exit code:"
            << QProcess::execute("aeroshell_update_default_rules", { "aeroshell.rules" });

    captureUserRollback();
}
void App::saveOotbConfig(bool reset)
{
    if (!beginUserRollback()) {
        return;
    }

    qInfo() << QProcess::execute("plasma-apply-cursortheme", { "breeze_cursors" }); // Prevent breeze cursor theme from showing up momentarily on splash screen
    KConfig ootbConfig(QStringLiteral("aerothemeplasmarc"));
    ootbConfig.group(QStringLiteral("OOTB")).writeEntry(QStringLiteral("wizardRun"), reset);
    ootbConfig.sync();
    qInfo() << QProcess::execute("plasma-apply-cursortheme", { "aero-drop", "--size", "32" });
    captureUserRollback();
}

#include "moc_app.cpp"
