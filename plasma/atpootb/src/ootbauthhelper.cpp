// SPDX-License-Identifier: GPL-2.0-or-later

#include "ootbauthhelper.h"

#include <KConfig>
#include <KUser>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QSharedPointer>
#include "rollbackstate.h"
#include <algorithm>

static QSharedPointer<KConfig> openConfig(const QString &filePath)
{
    const QFileInfo fileInfo(filePath);
    const QDir parentDir = fileInfo.dir();

    if (!parentDir.exists() && !QDir().mkpath(parentDir.path())) {
        qWarning() << "Could not create cursor configuration directory:" << parentDir.path();
        return {};
    }

    if (fileInfo.exists() && !fileInfo.isFile()) {
        qWarning() << "Cursor configuration path is not a regular file:" << filePath;
        return {};
    }

    QFile file(filePath);
    if (!file.exists()) {
        if (!file.open(QIODevice::WriteOnly)) {
            qWarning() << "Could not create cursor configuration file:" << filePath;
            return {};
        }
        file.close();
    }

    // KConfig creates files with restrictive defaults when run as root.
    // SDDM must be able to read this system-wide cursor setting.
    const QFileDevice::Permissions requiredPermissions =
        QFileDevice::ReadOwner | QFileDevice::WriteOwner |
        QFileDevice::ReadGroup | QFileDevice::ReadOther;

    if (!file.setPermissions(requiredPermissions)) {
        qWarning() << "Could not set cursor configuration permissions:" << filePath;
        return {};
    }

    return QSharedPointer<KConfig>(new KConfig(file.fileName(), KConfig::SimpleConfig));
}

namespace
{
QString systemRollbackManifestPath()
{
    return QStringLiteral("/var/lib/aerothemeplasma/rollback/system.json");
}

QStringList systemRollbackPaths()
{
    QStringList paths{
        QStringLiteral("/usr/share/icons/default/index.theme"),
        QStringLiteral("/etc/sddm.conf"),
        QStringLiteral("/etc/sddm.conf.d/kde_settings.conf")
    };

    const QString sddmHome = KUser(QStringLiteral("sddm")).homeDir();
    if (!sddmHome.isEmpty()) {
        const QString config = QDir(sddmHome).filePath(QStringLiteral(".config"));
        paths.append({
            QDir(config).filePath(QStringLiteral("kdeglobals")),
            QDir(config).filePath(QStringLiteral("plasmarc")),
            QDir(config).filePath(QStringLiteral("kcminputrc")),
            QDir(config).filePath(QStringLiteral("kcmfonts")),
            QDir(config).filePath(QStringLiteral("kwinoutputconfig.json")),
            QDir(config).filePath(QStringLiteral("fontconfig/fonts.conf"))
        });
    }

    return paths;
}
} // namespace

ActionReply OotbAuthHelper::backup(const QVariantMap &args)
{
    Q_UNUSED(args);
    if (!AtpRollback::backupFiles(systemRollbackPaths(), systemRollbackManifestPath())) {
        ActionReply reply = ActionReply::HelperErrorReply();
        reply.setErrorDescription(QStringLiteral("Could not create the system configuration backup."));
        return reply;
    }
    return ActionReply::SuccessReply();
}

ActionReply OotbAuthHelper::capture(const QVariantMap &args)
{
    Q_UNUSED(args);
    if (!AtpRollback::captureExpectedState(systemRollbackManifestPath())) {
        ActionReply reply = ActionReply::HelperErrorReply();
        reply.setErrorDescription(QStringLiteral("Could not record the applied system configuration state."));
        return reply;
    }
    return ActionReply::SuccessReply();
}

ActionReply OotbAuthHelper::apply(const QVariantMap &args)
{
    Q_UNUSED(args);

    if (!AtpRollback::backupFiles(systemRollbackPaths(), systemRollbackManifestPath())) {
        ActionReply reply = ActionReply::HelperErrorReply();
        reply.setErrorDescription(QStringLiteral("Could not create the system cursor configuration backup."));
        return reply;
    }

    const QString path = QStringLiteral("/usr/share/icons/default/index.theme");
    const QString groupName = QStringLiteral("Icon Theme");
    const QString cursorTheme = QStringLiteral("aero-drop");
    const QSharedPointer<KConfig> cursorConfig = openConfig(path);

    if (!cursorConfig) {
        ActionReply reply = ActionReply::HelperErrorReply();
        reply.setErrorDescription(QStringLiteral("Could not open the system cursor configuration."));
        return reply;
    }

    if (cursorConfig->isImmutable()) {
        ActionReply reply = ActionReply::HelperErrorReply();
        reply.setErrorDescription(QStringLiteral("The system cursor configuration is immutable."));
        return reply;
    }

    const QStringList groups = cursorConfig->groupList();
    const auto groupIt = std::find_if(groups.cbegin(), groups.cend(), [&](const QString &group) {
        return group.compare(groupName, Qt::CaseInsensitive) == 0;
    });

    cursorConfig->group(groupIt == groups.cend() ? groupName : *groupIt)
        .writeEntry(QStringLiteral("Inherits"), cursorTheme);

    if (!cursorConfig->sync()) {
        ActionReply reply = ActionReply::HelperErrorReply();
        reply.setErrorDescription(QStringLiteral("Failed to write the system cursor configuration."));
        qWarning() << "Failed to sync cursor configuration:" << path;
        return reply;
    }

    if (!AtpRollback::captureExpectedState(systemRollbackManifestPath())) {
        ActionReply reply = ActionReply::HelperErrorReply();
        reply.setErrorDescription(QStringLiteral("Cursor changed, but its rollback state could not be recorded."));
        return reply;
    }

    return ActionReply::SuccessReply();
}

KAUTH_HELPER_MAIN("io.gitgud.wackyideas.ootb", OotbAuthHelper)

#include "moc_ootbauthhelper.cpp"
